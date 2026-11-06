import 'dart:convert';
import 'dart:io';
import 'log_service.dart';

class FFmpegService {
  static bool? _isAvailableCache;

  /// Verifica se o binário do FFmpeg está instalado e acessível no sistema operacional
  static Future<bool> isAvailable() async {
    if (_isAvailableCache != null) return _isAvailableCache!;
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      _isAvailableCache = result.exitCode == 0;
      if (_isAvailableCache!) {
        LogService.info('FFmpeg detectado e pronto para uso.', tag: 'FFmpeg');
      } else {
        LogService.warning(
          'FFmpeg retornou código de saída diferente de 0 no teste de versão (${result.exitCode}).',
          tag: 'FFmpeg',
        );
      }
    } catch (e, stack) {
      _isAvailableCache = false;
      LogService.warning(
        'FFmpeg não está instalado ou não foi encontrado no PATH do sistema.',
        tag: 'FFmpeg',
        details: e.toString(),
      );
    }
    return _isAvailableCache!;
  }

  /// Formatos de áudio suportados para conversão
  static const List<String> audioFormats = ['mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg'];

  /// Formatos de vídeo suportados para conversão
  static const List<String> videoFormats = ['mp4', 'mkv', 'webm', 'avi', 'mov'];

  /// Bitrates disponíveis para áudio
  static const List<String> audioBitrates = ['128k', '192k', '256k', '320k'];

  /// Executa conversão de vídeo/áudio utilizando FFmpeg
  static Future<bool> convertMedia({
    required String inputPath,
    required String outputPath,
    required String targetFormat,
    String audioBitrate = '192k',
    void Function(double progress)? onProgress,
  }) async {
    final format = targetFormat.toLowerCase().replaceAll('.', '');
    final isAudioTarget = audioFormats.contains(format);

    final args = <String>['-y', '-i', inputPath];

    if (isAudioTarget) {
      // Extrai ou converte apenas o áudio (-vn ignora vídeo)
      args.add('-vn');

      switch (format) {
        case 'mp3':
          args.addAll(['-c:a', 'libmp3lame', '-b:a', audioBitrate]);
          break;
        case 'm4a':
        case 'aac':
          args.addAll(['-c:a', 'aac', '-b:a', audioBitrate]);
          break;
        case 'ogg':
          args.addAll(['-c:a', 'libvorbis', '-b:a', audioBitrate]);
          break;
        case 'flac':
          args.addAll(['-c:a', 'flac']);
          break;
        case 'wav':
          args.addAll(['-c:a', 'pcm_s16le']);
          break;
        default:
          args.addAll(['-c:a', 'libmp3lame', '-b:a', audioBitrate]);
      }
    } else {
      // Conversão de vídeo
      switch (format) {
        case 'webm':
          args.addAll([
            '-c:v', 'libvpx-vp9',
            '-crf', '32',
            '-b:v', '0',
            '-c:a', 'libopus',
            '-b:a', '128k',
          ]);
          break;
        case 'mkv':
          args.addAll(['-c:v', 'libx264', '-preset', 'fast', '-crf', '23', '-c:a', 'aac', '-b:a', '192k']);
          break;
        case 'avi':
          args.addAll(['-c:v', 'mpeg4', '-vtag', 'xvid', '-qscale:v', '4', '-c:a', 'libmp3lame', '-b:a', '192k']);
          break;
        case 'mov':
        case 'mp4':
        default:
          args.addAll(['-c:v', 'libx264', '-preset', 'fast', '-crf', '22', '-c:a', 'aac', '-b:a', '192k']);
          break;
      }
    }

    args.add(outputPath);

    LogService.info(
      'Iniciando conversão: $inputPath -> $outputPath (Formato: $format, Bitrate: $audioBitrate)',
      tag: 'FFmpeg',
      details: 'Comando: ffmpeg ${args.join(" ")}',
    );

    final stderrBuffer = StringBuffer();

    try {
      final process = await Process.start('ffmpeg', args);
      double totalDurationSec = 0.0;

      process.stderr.transform(utf8.decoder).listen((output) {
        if (stderrBuffer.length < 4000) {
          stderrBuffer.write(output);
        }

        // Tenta capturar a duração total da mídia
        if (totalDurationSec <= 0) {
          final durationMatch = RegExp(r'Duration:\s*(\d+):(\d+):(\d+\.?\d*)').firstMatch(output);
          if (durationMatch != null) {
            final h = double.tryParse(durationMatch.group(1) ?? '0') ?? 0;
            final m = double.tryParse(durationMatch.group(2) ?? '0') ?? 0;
            final s = double.tryParse(durationMatch.group(3) ?? '0') ?? 0;
            totalDurationSec = (h * 3600) + (m * 60) + s;
          }
        }

        // Tenta capturar o progresso atual
        if (totalDurationSec > 0 && onProgress != null) {
          final timeMatch = RegExp(r'time=\s*(\d+):(\d+):(\d+\.?\d*)').firstMatch(output);
          if (timeMatch != null) {
            final h = double.tryParse(timeMatch.group(1) ?? '0') ?? 0;
            final m = double.tryParse(timeMatch.group(2) ?? '0') ?? 0;
            final s = double.tryParse(timeMatch.group(3) ?? '0') ?? 0;
            final currentSec = (h * 3600) + (m * 60) + s;
            final progress = (currentSec / totalDurationSec).clamp(0.0, 1.0);
            onProgress(progress);
          }
        }
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        onProgress?.call(1.0);
        LogService.info('Conversão concluída com sucesso: $outputPath', tag: 'FFmpeg');
        return true;
      } else {
        LogService.error(
          'Falha na conversão com FFmpeg (código de saída $exitCode)',
          tag: 'FFmpeg',
          details: 'Saída de erro:\n${stderrBuffer.toString().trim()}',
        );
        return false;
      }
    } catch (e, stack) {
      LogService.error(
        'Exceção ao executar o processo FFmpeg: $e',
        tag: 'FFmpeg',
        error: e,
        stackTrace: stack,
        details: 'Arquivo: $inputPath',
      );
      return false;
    }
  }

  /// Junta uma faixa de vídeo e áudio separadas em um arquivo final unificado
  static Future<bool> muxVideoAndAudio({
    required String videoPath,
    required String audioPath,
    required String outputPath,
  }) async {
    LogService.info(
      'Mesclando vídeo ($videoPath) e áudio ($audioPath) para $outputPath',
      tag: 'FFmpeg',
    );
    try {
      final result = await Process.run('ffmpeg', [
        '-y',
        '-i', videoPath,
        '-i', audioPath,
        '-c:v', 'copy',
        '-c:a', 'aac',
        outputPath,
      ]);
      if (result.exitCode == 0) {
        LogService.info('Mesclagem FFmpeg concluída com sucesso: $outputPath', tag: 'FFmpeg');
        return true;
      } else {
        LogService.error(
          'Falha na mesclagem FFmpeg (exitCode: ${result.exitCode})',
          tag: 'FFmpeg',
          details: result.stderr.toString(),
        );
        return false;
      }
    } catch (e, stack) {
      LogService.error(
        'Erro ao mesclar faixas de vídeo e áudio: $e',
        tag: 'FFmpeg',
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }
}
