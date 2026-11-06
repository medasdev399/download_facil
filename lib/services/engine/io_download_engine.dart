import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import '../../models/download_item.dart';
import '../log_service.dart';
import '../youtube_service.dart';
import 'download_engine.dart';

DownloadEngine createEngine() => IoDownloadEngine();

class IoDownloadEngine implements DownloadEngine {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 30),
  ));

  @override
  Future<void> startOrResume(
    DownloadItem item, {
    required void Function() onUpdate,
  }) async {
    // Se for URL do YouTube, delega para o YouTubeService especializado
    if (YouTubeService.isYouTubeUrl(item.url)) {
      if (item.mediaType == DownloadMediaType.music) {
        await YouTubeService.downloadAudio(item, onUpdate: onUpdate);
      } else {
        await YouTubeService.downloadVideo(item, onUpdate: onUpdate);
      }
      return;
    }

    item.status = DownloadStatus.downloading;
    item.cancelToken = CancelToken();
    item.errorMessage = null;
    onUpdate();

    final tempFile = File('${item.savePath}.part');
    int existingBytes = 0;

    if (await tempFile.exists()) {
      existingBytes = await tempFile.length();
    }
    item.downloadedBytes = existingBytes;

    LogService.info(
      'Iniciando download direto: ${item.fileName}',
      tag: 'Download',
      details: 'URL: ${item.url}\nDestino: ${item.savePath}\nBytes já baixados: $existingBytes',
    );

    RandomAccessFile? raf;
    StreamSubscription<List<int>>? subscription;
    int bytesInLastSecond = 0;
    Timer? speedTimer;

    try {
      final response = await _dio.get<ResponseBody>(
        item.url,
        cancelToken: item.cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: existingBytes > 0 ? {'Range': 'bytes=$existingBytes-'} : null,
        ),
      );

      final isPartial = response.statusCode == 206;
      if (!isPartial && existingBytes > 0) {
        existingBytes = 0;
        item.downloadedBytes = 0;
        await tempFile.writeAsBytes([]);
        LogService.warning(
          'Servidor não suporta retoma (Range). Reiniciando do zero.',
          tag: 'Download',
        );
      }

      final contentLengthHeader = response.headers.value(Headers.contentLengthHeader);
      final contentLength = int.tryParse(contentLengthHeader ?? '0') ?? 0;
      if (item.totalBytes == 0 || !isPartial) {
        item.totalBytes = existingBytes + contentLength;
      }

      LogService.info(
        'Conexão estabelecida: HTTP ${response.statusCode} - Tamanho total: ${item.totalBytes} bytes',
        tag: 'Download',
      );

      // Garante que a árvore de pastas existe antes de abrir o arquivo
      await tempFile.parent.create(recursive: true);
      raf = await tempFile.open(mode: FileMode.append);

      speedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        item.speedBytesPerSec = bytesInLastSecond.toDouble();
        bytesInLastSecond = 0;
        onUpdate();
      });

      final completer = Completer<void>();

      subscription = response.data!.stream.listen(
        (chunk) {
          raf!.writeFromSync(chunk);
          item.downloadedBytes += chunk.length;
          bytesInLastSecond += chunk.length;
          onUpdate();
        },
        onDone: () => completer.complete(),
        onError: (e) => completer.completeError(e),
        cancelOnError: true,
      );

      item.cancelToken!.whenCancel.then((_) {
        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.completeError(DioException.requestCancelled(
            requestOptions: RequestOptions(path: item.url),
            reason: 'Paused by user',
          ));
        }
      });

      await completer.future;

      await raf.close();
      raf = null;

      // No Windows, rename falha se o arquivo de destino já existir
      final finalFile = File(item.savePath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(item.savePath);

      item.status = DownloadStatus.completed;
      LogService.info(
        'Download concluído com sucesso: ${item.fileName}',
        tag: 'Download',
        details: 'Caminho: ${item.savePath}',
      );
    } on DioException catch (e, stack) {
      if (CancelToken.isCancel(e)) {
        item.status = DownloadStatus.paused;
        LogService.info('Download pausado pelo usuário: ${item.fileName}', tag: 'Download');
      } else {
        item.status = DownloadStatus.failed;
        item.errorMessage = e.message ?? 'Erro de rede';
        LogService.error(
          'Falha de rede Dio ao baixar ${item.fileName}: ${e.message}',
          tag: 'Download',
          error: e,
          stackTrace: stack,
          details: 'Status Code: ${e.response?.statusCode}\nURL: ${item.url}',
        );
      }
    } catch (e, stack) {
      item.status = DownloadStatus.failed;
      item.errorMessage = e.toString();
      LogService.error(
        'Erro inesperado no download ${item.fileName}: $e',
        tag: 'Download',
        error: e,
        stackTrace: stack,
        details: 'URL: ${item.url}',
      );
    } finally {
      speedTimer?.cancel();
      try {
        await raf?.close();
      } catch (_) {}
      item.speedBytesPerSec = 0;
      onUpdate();
    }
  }

  @override
  void pause(DownloadItem item) {
    if (item.status == DownloadStatus.downloading) {
      item.cancelToken?.cancel('Paused');
      LogService.info('Comando de pausa enviado para ${item.fileName}', tag: 'Download');
    }
  }
}
