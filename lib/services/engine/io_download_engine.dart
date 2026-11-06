import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../models/download_item.dart';
import '../ffmpeg_service.dart';
import '../log_service.dart';
import '../youtube_service.dart';
import 'download_engine.dart';

DownloadEngine createEngine() => IoDownloadEngine();

class IoDownloadEngine implements DownloadEngine {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 60),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
    },
  ));

  @override
  Future<void> startOrResume(
    DownloadItem item, {
    required void Function() onUpdate,
  }) async {
    // 1. Se for URL do YouTube, delega para o YouTubeService especializado
    if (YouTubeService.isYouTubeUrl(item.url)) {
      if (item.mediaType == DownloadMediaType.music) {
        await YouTubeService.downloadAudio(item, onUpdate: onUpdate);
      } else {
        await YouTubeService.downloadVideo(item, onUpdate: onUpdate);
      }
      return;
    }

    // 2. Validação básica de URL HTTP(S) para evitar exceções do Dio
    if (!item.url.startsWith('http://') && !item.url.startsWith('https://')) {
      item.status = DownloadStatus.failed;
      item.errorMessage = 'URL inválida para download: ${item.url}';
      onUpdate();
      LogService.error('Tentativa de download com URL inválida: "${item.url}"', tag: 'Download');
      return;
    }

    // 3. Se for transmissão HLS (.m3u8), utiliza FFmpeg se disponível
    if (item.url.contains('.m3u8')) {
      final hasFFmpeg = await FFmpegService.isAvailable();
      if (hasFFmpeg) {
        await _downloadHlsWithFFmpeg(item, onUpdate: onUpdate);
        return;
      }
    }

    // 4. Download direto via Dio
    await _downloadDirectHttp(item, onUpdate: onUpdate);
  }

  Future<({bool supportsRange, int totalBytes})> _probeUrl(
    String url,
    Map<String, dynamic> headers,
    CancelToken? cancelToken,
  ) async {
    try {
      final probeHeaders = Map<String, dynamic>.from(headers);
      probeHeaders['Range'] = 'bytes=0-0';

      final res = await _dio.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: probeHeaders,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      // Cancela o stream imediatamente após ler os cabeçalhos de resposta sem baixar o arquivo
      res.data?.stream.listen((_) {}).cancel();

      final statusCode = res.statusCode ?? 200;
      final contentRange = res.headers.value('Content-Range') ?? res.headers.value('content-range');

      if (statusCode == 206 && contentRange != null) {
        final match = RegExp(r'bytes\s+\d+-\d+/(\d+)').firstMatch(contentRange);
        if (match != null) {
          final total = int.tryParse(match.group(1)!) ?? 0;
          return (supportsRange: true, totalBytes: total);
        }
        return (supportsRange: true, totalBytes: 0);
      }

      if (statusCode == 206) {
        return (supportsRange: true, totalBytes: 0);
      }

      final clHeader = res.headers.value(Headers.contentLengthHeader);
      final total = int.tryParse(clHeader ?? '0') ?? 0;
      return (supportsRange: false, totalBytes: total);
    } catch (e) {
      LogService.debug('Probe de Range/Tamanho falhou: $e', tag: 'Download');
      return (supportsRange: false, totalBytes: 0);
    }
  }

  Future<void> _downloadDirectHttp(
    DownloadItem item, {
    required void Function() onUpdate,
  }) async {
    item.status = DownloadStatus.downloading;
    item.cancelToken = CancelToken();
    item.errorMessage = null;
    item.statusMessage = null;
    onUpdate();

    final isAudioExtraction = item.mediaType == DownloadMediaType.music || item.targetFormat == 'mp3';
    final targetIsMp3 = item.savePath.toLowerCase().endsWith('.mp3');
    final needsAudioConversion = isAudioExtraction && !item.url.toLowerCase().split('?').first.endsWith('.mp3');

    // Se precisar extrair áudio de um vídeo, baixa para arquivo temporário de vídeo
    final actualDownloadTarget = needsAudioConversion
        ? '${item.savePath}.temp_download'
        : item.savePath;

    final tempFile = File('$actualDownloadTarget.part');
    int existingBytes = 0;

    if (await tempFile.exists()) {
      existingBytes = await tempFile.length();
    }
    item.downloadedBytes = existingBytes;

    LogService.info(
      'Iniciando download direto: ${item.fileName}',
      tag: 'Download',
      details: 'URL: ${item.url}\nDestino: $actualDownloadTarget\nBytes já baixados: $existingBytes',
    );

    // Garante que a árvore de pastas existe antes de abrir o arquivo
    await tempFile.parent.create(recursive: true);

    RandomAccessFile? raf;
    int bytesInLastSecond = 0;
    Timer? speedTimer;

    try {
      final requestHeaders = <String, dynamic>{
        'User-Agent':
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
      };

      if (item.httpHeaders != null) {
        requestHeaders.addAll(item.httpHeaders!);
      }

      // Servidores de GoogleVideo do Blogger exigem Referer para evitar 403 Forbidden
      if (item.url.contains('googlevideo.com') && !requestHeaders.containsKey('Referer')) {
        requestHeaders['Referer'] = 'https://www.blogger.com/';
      }

      // Tenta extrair tamanho da query string se informado em clen
      if (item.totalBytes <= 0) {
        final clenMatch = RegExp(r'[?&]clen=(\d+)').firstMatch(item.url);
        if (clenMatch != null) {
          item.totalBytes = int.tryParse(clenMatch.group(1)!) ?? 0;
        }
      }

      // Inicia o timer de medição de velocidade
      speedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        item.speedBytesPerSec = bytesInLastSecond.toDouble();
        bytesInLastSecond = 0;
        onUpdate();
      });

      // 1. Sondagem (Probe): verifica suporte a Range e obtém o totalBytes real
      final probe = await _probeUrl(item.url, requestHeaders, item.cancelToken);
      if (item.totalBytes <= 0 && probe.totalBytes > 0) {
        item.totalBytes = probe.totalBytes;
      }
      final supportsRange = probe.supportsRange;

      LogService.info(
        'Sondagem de conexão: Suporta Range: $supportsRange - Tamanho total: ${item.totalBytes} bytes',
        tag: 'Download',
      );

      raf = await tempFile.open(mode: FileMode.append);

      if (supportsRange) {
        // DOWNLOAD EM CHUNKS (SEGMENTADO)
        // Divide o download em blocos de 8MB. Essencial para googlevideo.com e streams HTTP
        // para contornar throttling de banda e desconexões prematuras.
        const chunkSize = 8 * 1024 * 1024;
        bool reachedEnd = false;

        while (!reachedEnd) {
          if (item.cancelToken?.isCancelled ?? false) {
            throw DioException.requestCancelled(
              requestOptions: RequestOptions(path: item.url),
              reason: 'Paused by user',
            );
          }

          if (item.totalBytes > 0 && existingBytes >= item.totalBytes) {
            break;
          }

          final startByte = existingBytes;
          final int endByte = item.totalBytes > 0
              ? (startByte + chunkSize - 1 < item.totalBytes
                  ? startByte + chunkSize - 1
                  : item.totalBytes - 1)
              : startByte + chunkSize - 1;

          final chunkHeaders = Map<String, dynamic>.from(requestHeaders);
          chunkHeaders['Range'] = 'bytes=$startByte-$endByte';

          int chunkBytesReceived = 0;
          int retryCount = 0;
          const maxRetries = 3;

          while (true) {
            try {
              final response = await _dio.get<ResponseBody>(
                item.url,
                cancelToken: item.cancelToken,
                options: Options(
                  responseType: ResponseType.stream,
                  headers: chunkHeaders,
                  validateStatus: (status) =>
                      status != null && (status == 200 || status == 206 || status == 416),
                ),
              );

              if (response.statusCode == 416) {
                // Range Not Satisfiable: fim do arquivo atingido
                reachedEnd = true;
                break;
              }

              // Atualiza totalBytes a partir do Content-Range se ainda desconhecido
              final contentRange = response.headers.value('Content-Range') ??
                  response.headers.value('content-range');
              if (contentRange != null && item.totalBytes <= 0) {
                final match = RegExp(r'bytes\s+\d+-\d+/(\d+)').firstMatch(contentRange);
                if (match != null) {
                  item.totalBytes = int.tryParse(match.group(1)!) ?? 0;
                }
              }

              final completer = Completer<void>();
              final subscription = response.data!.stream.listen(
                (chunk) {
                  raf!.writeFromSync(chunk);
                  existingBytes += chunk.length;
                  chunkBytesReceived += chunk.length;
                  item.downloadedBytes = existingBytes;
                  bytesInLastSecond += chunk.length;
                  onUpdate();
                },
                onDone: () => completer.complete(),
                onError: (e) => completer.completeError(e),
                cancelOnError: true,
              );

              item.cancelToken?.whenCancel.then((_) {
                subscription.cancel();
                if (!completer.isCompleted) {
                  completer.completeError(DioException.requestCancelled(
                    requestOptions: RequestOptions(path: item.url),
                    reason: 'Paused by user',
                  ));
                }
              });

              await completer.future;

              // Se o servidor respondeu 200 em vez de 206, transmitiu o fluxo até o final
              if (response.statusCode == 200) {
                reachedEnd = true;
              }
              break;
            } catch (e) {
              if (item.cancelToken?.isCancelled ?? false) rethrow;

              retryCount++;
              if (retryCount > maxRetries) {
                throw Exception(
                    'Falha ao baixar bloco ($startByte-$endByte) após $maxRetries tentativas: $e');
              }
              LogService.warning(
                'Falha temporária no chunk ($startByte-$endByte), tentativa $retryCount de $maxRetries...',
                tag: 'Download',
              );
              await Future.delayed(Duration(seconds: retryCount));
            }
          }

          if (reachedEnd) break;

          // Se recebeu 0 bytes ou menos do que o range quando totalBytes era desconhecido, encerra
          if (chunkBytesReceived == 0 ||
              (item.totalBytes <= 0 && chunkBytesReceived < (endByte - startByte + 1))) {
            break;
          }
        }
      } else {
        // FLUXO CONTÍNUO (para servidores que não aceitam Range)
        if (existingBytes > 0) {
          existingBytes = 0;
          item.downloadedBytes = 0;
          await tempFile.writeAsBytes([]);
          LogService.warning(
            'Servidor não suporta retoma (Range). Reiniciando do zero.',
            tag: 'Download',
          );
        }

        final response = await _dio.get<ResponseBody>(
          item.url,
          cancelToken: item.cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            headers: requestHeaders,
          ),
        );

        final contentLengthHeader = response.headers.value(Headers.contentLengthHeader);
        final contentLength = int.tryParse(contentLengthHeader ?? '0') ?? 0;
        if (item.totalBytes <= 0 && contentLength > 0) {
          item.totalBytes = contentLength;
        }

        final completer = Completer<void>();
        final subscription = response.data!.stream.listen(
          (chunk) {
            raf!.writeFromSync(chunk);
            existingBytes += chunk.length;
            item.downloadedBytes = existingBytes;
            bytesInLastSecond += chunk.length;
            onUpdate();
          },
          onDone: () => completer.complete(),
          onError: (e) => completer.completeError(e),
          cancelOnError: true,
        );

        item.cancelToken?.whenCancel.then((_) {
          subscription.cancel();
          if (!completer.isCompleted) {
            completer.completeError(DioException.requestCancelled(
              requestOptions: RequestOptions(path: item.url),
              reason: 'Paused by user',
            ));
          }
        });

        await completer.future;
      }

      await raf.close();
      raf = null;

      if (item.cancelToken?.isCancelled ?? false) {
        return;
      }

      // Validação rigorosa de integridade
      if (item.downloadedBytes == 0) {
        throw Exception('Download falhou: 0 bytes foram baixados do servidor.');
      }

      if (item.totalBytes > 0 && item.downloadedBytes < item.totalBytes) {
        throw Exception(
          'Download incompleto: foram recebidos apenas ${item.downloadedBytes} de ${item.totalBytes} bytes. O servidor encerrou a conexão prematuramente.',
        );
      }

      if (item.totalBytes <= 0) {
        item.totalBytes = item.downloadedBytes;
      }

      final downloadedFile = File(actualDownloadTarget);
      if (await downloadedFile.exists()) {
        await downloadedFile.delete();
      }
      await tempFile.rename(actualDownloadTarget);

      // Se requer conversão de áudio para MP3 via FFmpeg
      if (needsAudioConversion) {
        final hasFFmpeg = await FFmpegService.isAvailable();
        if (hasFFmpeg) {
          item.status = DownloadStatus.converting;
          item.statusMessage = 'Extraindo áudio MP3 com FFmpeg...';
          item.speedBytesPerSec = 0;
          onUpdate();

          final mp3Path = targetIsMp3
              ? item.savePath
              : '${p.withoutExtension(item.savePath)}.mp3';

          LogService.info('Convertendo stream baixado para MP3: $mp3Path', tag: 'Download');

          final success = await FFmpegService.convertMedia(
            inputPath: actualDownloadTarget,
            outputPath: mp3Path,
            targetFormat: 'mp3',
            audioBitrate: item.audioBitrate ?? '320k',
          );

          if (await downloadedFile.exists()) {
            await downloadedFile.delete();
          }

          if (!success) {
            throw Exception('Falha ao extrair áudio com FFmpeg');
          }

          item.savePath = mp3Path;
          item.fileName = p.basename(mp3Path);
        }
      }

      item.status = DownloadStatus.completed;
      item.statusMessage = null;
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

  Future<void> _downloadHlsWithFFmpeg(
    DownloadItem item, {
    required void Function() onUpdate,
  }) async {
    item.status = DownloadStatus.downloading;
    item.cancelToken = CancelToken();
    item.errorMessage = null;
    item.statusMessage = 'Gravando transmissão HLS via FFmpeg...';
    onUpdate();

    final headersList = <String>[
      'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
    ];

    if (item.httpHeaders != null) {
      item.httpHeaders!.forEach((k, v) {
        if (k.toLowerCase() != 'user-agent') {
          headersList.add('$k: $v');
        }
      });
    }

    final headersArg = headersList.map((h) => '$h\r\n').join();
    final args = <String>[
      '-y',
      '-headers',
      headersArg,
      '-i',
      item.url,
      '-c',
      'copy',
      '-bsf:a',
      'aac_adtstoasc',
      item.savePath,
    ];

    LogService.info('Iniciando gravação HLS com FFmpeg: ${item.fileName}', tag: 'HLS');

    try {
      final process = await Process.start('ffmpeg', args);
      item.cancelToken?.whenCancel.then((_) {
        process.kill();
      });

      process.stderr.transform(utf8.decoder).listen((output) {
        // Tenta capturar o tamanho baixado
        final sizeMatch = RegExp(r'size=\s*(\d+)kB').firstMatch(output);
        if (sizeMatch != null) {
          final kb = int.tryParse(sizeMatch.group(1) ?? '0') ?? 0;
          item.downloadedBytes = kb * 1024;
          if (item.totalBytes <= 0) item.totalBytes = item.downloadedBytes;
          onUpdate();
        }
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        item.status = DownloadStatus.completed;
        item.statusMessage = null;
        LogService.info('Download HLS concluído: ${item.fileName}', tag: 'HLS');
      } else {
        item.status = DownloadStatus.failed;
        item.errorMessage = 'Erro no download HLS (código $exitCode)';
        LogService.error('FFmpeg encerrou download HLS com código $exitCode', tag: 'HLS');
      }
    } catch (e, stack) {
      item.status = DownloadStatus.failed;
      item.errorMessage = e.toString();
      LogService.error('Exceção ao gravar transmissão HLS: $e', tag: 'HLS', error: e, stackTrace: stack);
    } finally {
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
