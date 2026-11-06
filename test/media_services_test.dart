import 'package:flutter_test/flutter_test.dart';
import 'package:download_facil/models/conversion_item.dart';
import 'package:download_facil/models/download_item.dart';
import 'package:download_facil/services/ffmpeg_service.dart';
import 'package:download_facil/services/youtube_service.dart';

void main() {
  group('YouTube URL Detection', () {
    test('identifies standard watch URLs', () {
      expect(
        YouTubeService.isYouTubeUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        isTrue,
      );
    });

    test('identifies short youtu.be URLs', () {
      expect(
        YouTubeService.isYouTubeUrl('https://youtu.be/dQw4w9WgXcQ'),
        isTrue,
      );
    });

    test('identifies YouTube Shorts URLs', () {
      expect(
        YouTubeService.isYouTubeUrl('https://www.youtube.com/shorts/abcdef12345'),
        isTrue,
      );
    });

    test('identifies YouTube Music URLs', () {
      expect(
        YouTubeService.isYouTubeUrl('https://music.youtube.com/watch?v=dQw4w9WgXcQ'),
        isTrue,
      );
    });

    test('returns false for generic URLs', () {
      expect(
        YouTubeService.isYouTubeUrl('https://example.com/video.mp4'),
        isFalse,
      );
    });
  });

  group('FFmpeg Formats & Models', () {
    test('contains expected audio and video formats', () {
      expect(FFmpegService.audioFormats, containsAll(['mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg']));
      expect(FFmpegService.videoFormats, containsAll(['mp4', 'mkv', 'webm', 'avi', 'mov']));
    });

    test('ConversionItem tracks status and progress', () {
      final item = ConversionItem(
        id: '1',
        inputPath: '/tmp/test.mp4',
        outputPath: '/tmp/test.mp3',
        inputFileName: 'test.mp4',
        outputFileName: 'test.mp3',
        targetFormat: 'mp3',
      );

      expect(item.status, equals(ConversionStatus.pending));
      expect(item.progress, equals(0.0));

      item.status = ConversionStatus.completed;
      item.progress = 1.0;
      expect(item.status, equals(ConversionStatus.completed));
      expect(item.progress, equals(1.0));
    });

    test('DownloadItem formattedDuration calculation', () {
      final item = DownloadItem(
        id: '1',
        url: 'https://example.com/audio.mp3',
        fileName: 'audio.mp3',
        savePath: '/tmp/audio.mp3',
        duration: const Duration(minutes: 3, seconds: 45),
        mediaType: DownloadMediaType.music,
      );

      expect(item.formattedDuration, equals('03:45'));
    });
  });
}

