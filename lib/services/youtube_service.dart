import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/download_item.dart';
import 'ffmpeg_service.dart';
import 'log_service.dart';

class YouTubeMediaInfo {
  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;
  final List<String> videoQualities;

  YouTubeMediaInfo({
    required this.id,
    required this.title,
    required this.author,
    this.duration,
    required this.thumbnailUrl,
    required this.videoQualities,
  });
}

class YouTubeService {
  static YoutubeExplode _yt = YoutubeExplode();

  /// Reinicializa a instância do cliente YouTube
  static void resetClient() {
    try {
      _yt.close();
    } catch (_) {}
    _yt = YoutubeExplode();
  }

  /// Converte exceções comuns do YouTube em mensagens amigáveis e claras
  static String formatErrorMessage(dynamic error) {
    final str = error.toString();
    if (str.contains('RequestLimitExceededException') ||
        str.contains('rate limiting') ||
        str.contains('Rate limit') ||
        str.contains('too many requests')) {
      return 'O YouTube limitou temporariamente as requisições deste endereço IP (proteção anti-bot). Aguarde de 5 a 15 minutos ou conecte-se a outra rede (ex: dados móveis / 4G).';
    }
    if (str.contains('VideoUnplayableException') ||
        str.contains('VideoRequiresPurchaseException') ||
        str.contains('VideoUnavailableException')) {
      return 'Vídeo indisponível, privado ou com restrição de direitos no YouTube.';
    }
    return str;
  }

  /// Extrai e valida com precisão o VideoId do YouTube (suporta vídeos normais, shorts, music e IDs diretos)
  static VideoId? parseVideoId(String url) {
    final clean = url.trim();
    if (clean.isEmpty) return null;

    final lower = clean.toLowerCase();
    final isYouTubeDomain = lower.contains('youtube.com/') ||
        lower.contains('youtu.be/') ||
        lower.contains('music.youtube.com/');

    // Se for URL HTTP/HTTPS, só aceita se for comprovadamente domínio do YouTube
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      if (!isYouTubeDomain) return null;
    }

    try {
      return VideoId(clean);
    } catch (_) {
      return null;
    }
  }

  /// Identifica se uma URL é proveniente do YouTube e possui ID válido
  static bool isYouTubeUrl(String url) {
    return parseVideoId(url) != null;
  }

  /// Busca os metadados do vídeo do YouTube para pré-visualização
  static Future<YouTubeMediaInfo?> fetchInfo(String url) async {
    final videoId = parseVideoId(url);
    if (videoId == null) return null;

    LogService.info('Buscando informações do YouTube: ${videoId.value}', tag: 'YouTube');
    try {
      final video = await _yt.videos.get(videoId);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);

      final qualities = <String>{};
      for (final s in manifest.video) {
        if (s.videoQuality.name.isNotEmpty) {
          qualities.add(s.videoQuality.name);
        }
      }

      final info = YouTubeMediaInfo(
        id: video.id.value,
        title: video.title,
        author: video.author,
        duration: video.duration,
        thumbnailUrl: video.thumbnails.highResUrl.isNotEmpty
            ? video.thumbnails.highResUrl
            : video.thumbnails.mediumResUrl,
        videoQualities: qualities.toList()..sort((a, b) => b.compareTo(a)),
      );

      LogService.info(
        'Metadados obtidos: "${info.title}" por ${info.author} (${info.videoQualities.join(", ")})',
        tag: 'YouTube',
      );
      return info;
    } catch (e, stack) {
      final friendlyMsg = formatErrorMessage(e);
      LogService.error(
        'Falha ao obter metadados do YouTube: $friendlyMsg',
        tag: 'YouTube',
        error: e,
        stackTrace: stack,
        details: 'URL: $url\nVideoId: ${videoId.value}',
      );
      if (e.toString().contains('RequestLimitExceededException')) {
        resetClient();
      }
      rethrow;
    }
  }

  /// Baixa uma faixa de áudio (música) do YouTube com suporte a conversão automática para MP3
  static Future<void> downloadAudio(
    DownloadItem item, {
    required void Function() onUpdate,
  }) async {
    item.status = DownloadStatus.downloading;
    item.cancelToken = CancelToken();
    item.errorMessage = null;
    item.speedBytesPerSec = 0;
    onUpdate();

    LogService.info('Iniciando fluxo de áudio YouTube para: ${item.fileName}', tag: 'YouTube');

    try {
      final videoId = VideoId(item.url);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStream = manifest.audioOnly.withHighestBitrate();

      item.totalBytes = audioStream.size.totalBytes;
      onUpdate();

      final hasFFmpeg = await FFmpegService.isAvailable();
      final tempRawFile = File('${item.savePath}.temp_raw');
      await tempRawFile.parent.create(recursive: true);

      RandomAccessFile? raf = await tempRawFile.open(mode: FileMode.write);
      StreamSubscription<List<int>>? subscription;
      int bytesInLastSecond = 0;
      Timer? speedTimer;
      final completer = Completer<void>();

      speedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        item.speedBytesPerSec = bytesInLastSecond.toDouble();
        bytesInLastSecond = 0;
        onUpdate();
      });

      try {
        final stream = _yt.videos.streamsClient.get(audioStream);

        subscription = stream.listen(
          (chunk) {
            raf?.writeFromSync(chunk);
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
        speedTimer.cancel();

        // Conversão para MP3 se solicitado ou cópia para o caminho final
        if (item.savePath.toLowerCase().endsWith('.mp3') && hasFFmpeg) {
          item.status = DownloadStatus.converting;
          item.statusMessage = 'Convertendo áudio para MP3 (320kbps)...';
          item.speedBytesPerSec = 0;
          onUpdate();

          LogService.info('Convertendo áudio baixado para MP3: ${item.savePath}', tag: 'YouTube');

          final converted = await FFmpegService.convertMedia(
            inputPath: tempRawFile.path,
            outputPath: item.savePath,
            targetFormat: 'mp3',
            audioBitrate: '320k',
          );

          if (await tempRawFile.exists()) {
            await tempRawFile.delete();
          }

          if (!converted) {
            throw Exception('Falha ao converter áudio com FFmpeg');
          }
        } else {
          if (await File(item.savePath).exists()) {
            await File(item.savePath).delete();
          }
          await tempRawFile.rename(item.savePath);
        }

        item.status = DownloadStatus.completed;
        item.statusMessage = null;
        LogService.info('Download de áudio concluído: ${item.fileName}', tag: 'YouTube');
        onUpdate();
      } finally {
        speedTimer.cancel();
        try {
          await raf?.close();
        } catch (_) {}
      }
    } on DioException catch (e, stack) {
      if (CancelToken.isCancel(e)) {
        item.status = DownloadStatus.paused;
        LogService.info('Download de áudio pausado pelo usuário: ${item.fileName}', tag: 'YouTube');
      } else {
        item.status = DownloadStatus.failed;
        item.errorMessage = e.message ?? 'Erro no download de áudio';
        LogService.error(
          'Erro de conexão ao baixar áudio do YouTube: ${item.fileName}',
          tag: 'YouTube',
          error: e,
          stackTrace: stack,
        );
      }
    } catch (e, stack) {
      item.status = DownloadStatus.failed;
      item.errorMessage = formatErrorMessage(e);
      if (e.toString().contains('RequestLimitExceededException')) {
        resetClient();
      }
      LogService.error(
        'Falha no processo de áudio do YouTube: ${item.errorMessage}',
        tag: 'YouTube',
        error: e,
        stackTrace: stack,
        details: 'Arquivo: ${item.fileName}\nURL: ${item.url}',
      );
    } finally {
      item.speedBytesPerSec = 0;
      onUpdate();
    }
  }

  /// Baixa o vídeo do YouTube (muxed ou alta resolução com muxing via FFmpeg)
  static Future<void> downloadVideo(
    DownloadItem item, {
    required void Function() onUpdate,
  }) async {
    item.status = DownloadStatus.downloading;
    item.cancelToken = CancelToken();
    item.errorMessage = null;
    item.speedBytesPerSec = 0;
    onUpdate();

    LogService.info('Iniciando fluxo de vídeo YouTube para: ${item.fileName}', tag: 'YouTube');

    try {
      final videoId = VideoId(item.url);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);

      // Prioriza muxed com melhor qualidade se disponível
      final muxedStream = manifest.muxed.isNotEmpty
          ? manifest.muxed.withHighestBitrate()
          : null;
      final hasFFmpeg = await FFmpegService.isAvailable();

      // Se tiver FFmpeg e stream de vídeo 1080p/720p separado
      final videoOnlyStream = manifest.videoOnly.isNotEmpty
          ? manifest.videoOnly.withHighestBitrate()
          : null;
      final audioOnlyStream = manifest.audioOnly.isNotEmpty
          ? manifest.audioOnly.withHighestBitrate()
          : null;

      final bool useMuxing = hasFFmpeg &&
          videoOnlyStream != null &&
          audioOnlyStream != null &&
          videoOnlyStream.size.totalBytes > (muxedStream?.size.totalBytes ?? 0);

      if (useMuxing) {
        LogService.info('Vídeo em alta resolução detectado. Utilizando muxing FFmpeg.', tag: 'YouTube');
        await _downloadAndMuxHighRes(
          item,
          videoStream: videoOnlyStream,
          audioStream: audioOnlyStream,
          onUpdate: onUpdate,
        );
      } else {
        final streamToDownload = muxedStream ?? videoOnlyStream;
        if (streamToDownload == null) {
          throw Exception('Nenhum fluxo de vídeo compatível disponível para este conteúdo');
        }
        LogService.info(
          'Baixando fluxo direto (${streamToDownload.container.name}, ${streamToDownload.size.totalBytes} bytes)',
          tag: 'YouTube',
        );
        await _downloadSingleStream(
          item,
          streamInfo: streamToDownload,
          onUpdate: onUpdate,
        );
      }
    } catch (e, stack) {
      item.status = DownloadStatus.failed;
      item.errorMessage = formatErrorMessage(e);
      if (e.toString().contains('RequestLimitExceededException')) {
        resetClient();
      }
      LogService.error(
        'Falha no processamento de vídeo do YouTube: ${item.errorMessage}',
        tag: 'YouTube',
        error: e,
        stackTrace: stack,
        details: 'URL: ${item.url}',
      );
    } finally {
      item.speedBytesPerSec = 0;
      onUpdate();
    }
  }

  static Future<void> _downloadSingleStream(
    DownloadItem item, {
    required dynamic streamInfo,
    required void Function() onUpdate,
  }) async {
    item.totalBytes = streamInfo.size.totalBytes;
    onUpdate();

    final tempFile = File('${item.savePath}.temp_video');
    await tempFile.parent.create(recursive: true);

    RandomAccessFile? raf = await tempFile.open(mode: FileMode.write);
    StreamSubscription<List<int>>? subscription;
    int bytesInLastSecond = 0;
    Timer? speedTimer;
    final completer = Completer<void>();

    speedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      item.speedBytesPerSec = bytesInLastSecond.toDouble();
      bytesInLastSecond = 0;
      onUpdate();
    });

    try {
      final stream = _yt.videos.streamsClient.get(streamInfo);

      subscription = stream.listen(
        (chunk) {
          raf?.writeFromSync(chunk);
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
      speedTimer.cancel();

      final finalFile = File(item.savePath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(item.savePath);

      item.status = DownloadStatus.completed;
      LogService.info('Download de vídeo finalizado: ${item.fileName}', tag: 'YouTube');
      onUpdate();
    } on DioException catch (e, stack) {
      if (CancelToken.isCancel(e)) {
        item.status = DownloadStatus.paused;
        LogService.info('Download pausado: ${item.fileName}', tag: 'YouTube');
      } else {
        item.status = DownloadStatus.failed;
        item.errorMessage = e.message ?? 'Erro no download de vídeo';
        LogService.error(
          'Erro de conexão no download do vídeo: ${e.message}',
          tag: 'YouTube',
          error: e,
          stackTrace: stack,
        );
      }
    } catch (e, stack) {
      item.status = DownloadStatus.failed;
      item.errorMessage = e.toString();
      LogService.error(
        'Erro ao gravar fluxo de vídeo: $e',
        tag: 'YouTube',
        error: e,
        stackTrace: stack,
      );
    } finally {
      speedTimer.cancel();
      try {
        await raf?.close();
      } catch (_) {}
      item.speedBytesPerSec = 0;
      onUpdate();
    }
  }

  static Future<void> _downloadAndMuxHighRes(
    DownloadItem item, {
    required dynamic videoStream,
    required dynamic audioStream,
    required void Function() onUpdate,
  }) async {
    final totalBytes = videoStream.size.totalBytes + audioStream.size.totalBytes;
    item.totalBytes = totalBytes;
    item.downloadedBytes = 0;
    onUpdate();

    final tempVideo = File('${item.savePath}.raw_vid');
    final tempAudio = File('${item.savePath}.raw_aud');
    await tempVideo.parent.create(recursive: true);

    try {
      // 1. Baixa o fluxo de vídeo
      item.statusMessage = 'Baixando vídeo em alta resolução...';
      onUpdate();
      LogService.info('Baixando faixa de vídeo 1080p/720p...', tag: 'YouTube');
      await _pipeStreamToFile(
        _yt.videos.streamsClient.get(videoStream),
        tempVideo,
        item,
        onUpdate,
      );

      // 2. Baixa o fluxo de áudio
      item.statusMessage = 'Baixando faixa de áudio...';
      onUpdate();
      LogService.info('Baixando faixa de áudio...', tag: 'YouTube');
      await _pipeStreamToFile(
        _yt.videos.streamsClient.get(audioStream),
        tempAudio,
        item,
        onUpdate,
      );

      // 3. Junta via FFmpeg
      item.status = DownloadStatus.converting;
      item.statusMessage = 'Combinando vídeo e áudio em alta qualidade...';
      item.speedBytesPerSec = 0;
      onUpdate();

      LogService.info('Executando muxing FFmpeg para unificar faixas...', tag: 'YouTube');

      final muxSuccess = await FFmpegService.muxVideoAndAudio(
        videoPath: tempVideo.path,
        audioPath: tempAudio.path,
        outputPath: item.savePath,
      );

      if (await tempVideo.exists()) await tempVideo.delete();
      if (await tempAudio.exists()) await tempAudio.delete();

      if (!muxSuccess) {
        throw Exception('Falha ao unir áudio e vídeo com FFmpeg');
      }

      item.status = DownloadStatus.completed;
      item.statusMessage = null;
      LogService.info('Vídeo em alta definição gerado com sucesso: ${item.fileName}', tag: 'YouTube');
      onUpdate();
    } on DioException catch (e, stack) {
      if (CancelToken.isCancel(e)) {
        item.status = DownloadStatus.paused;
        LogService.info('Download em alta resolução pausado pelo usuário', tag: 'YouTube');
      } else {
        item.status = DownloadStatus.failed;
        item.errorMessage = e.message ?? 'Erro no download';
        LogService.error(
          'Erro ao baixar faixas de alta resolução: ${e.message}',
          tag: 'YouTube',
          error: e,
          stackTrace: stack,
        );
      }
    } catch (e, stack) {
      item.status = DownloadStatus.failed;
      item.errorMessage = e.toString();
      LogService.error(
        'Falha no download/muxing de alta resolução: $e',
        tag: 'YouTube',
        error: e,
        stackTrace: stack,
      );
    } finally {
      item.speedBytesPerSec = 0;
      onUpdate();
    }
  }

  static Future<void> _pipeStreamToFile(
    Stream<List<int>> stream,
    File destination,
    DownloadItem item,
    void Function() onUpdate,
  ) async {
    final raf = await destination.open(mode: FileMode.write);
    final completer = Completer<void>();
    int bytesInLastSecond = 0;

    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      item.speedBytesPerSec = bytesInLastSecond.toDouble();
      bytesInLastSecond = 0;
      onUpdate();
    });

    final sub = stream.listen(
      (chunk) {
        raf.writeFromSync(chunk);
        item.downloadedBytes += chunk.length;
        bytesInLastSecond += chunk.length;
        onUpdate();
      },
      onDone: () => completer.complete(),
      onError: (e) => completer.completeError(e),
      cancelOnError: true,
    );

    item.cancelToken?.whenCancel.then((_) {
      sub.cancel();
      if (!completer.isCompleted) {
        completer.completeError(DioException.requestCancelled(
          requestOptions: RequestOptions(path: item.url),
          reason: 'Cancelado pelo usuário',
        ));
      }
    });

    try {
      await completer.future;
    } finally {
      timer.cancel();
      await raf.close();
    }
  }
}
