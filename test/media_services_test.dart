import 'package:flutter_test/flutter_test.dart';
import 'package:download_facil/models/conversion_item.dart';
import 'package:download_facil/models/download_item.dart';
import 'package:download_facil/services/ffmpeg_service.dart';
import 'package:download_facil/services/media_detector_service.dart';
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

  group('MediaDetectorService', () {
    test('identifies direct media URLs', () {
      expect(MediaDetectorService.isDirectMediaUrl('https://example.com/video.mp4'), isTrue);
      expect(MediaDetectorService.isDirectMediaUrl('https://example.com/stream.m3u8?token=123'), isTrue);
      expect(MediaDetectorService.isDirectMediaUrl('https://example.com/music.mp3'), isTrue);
      expect(MediaDetectorService.isDirectMediaUrl('https://example.com/index.html'), isFalse);
    });

    test('identifies Blogger player URLs', () {
      expect(MediaDetectorService.isBloggerUrl('https://www.blogger.com/video.g?token=XYZ'), isTrue);
      expect(MediaDetectorService.isBloggerUrl('https://www.blogger.com/video-redirect.g?token=XYZ'), isTrue);
      expect(MediaDetectorService.isBloggerUrl('https://example.com/page'), isFalse);
    });

    test('cleanTitle strips site promotional noise', () {
      expect(
        MediaDetectorService.cleanTitle('Overlord 2 Episodio 1 Online - Animes Online'),
        equals('Overlord 2 Episodio 1'),
      );
      expect(
        MediaDetectorService.cleanTitle('Naruto Shippuden 01 - Animes Online Grátis'),
        equals('Naruto Shippuden 01'),
      );
      expect(
        MediaDetectorService.cleanTitle('Filme Completo - Assistir Filmes Online HD'),
        equals('Filme Completo'),
      );
    });

    test('sniffHtml extracts direct video and audio elements', () {
      const html = '''
        <html>
          <head>
            <meta property="og:title" content="Teste Vídeo HD" />
            <meta property="og:image" content="https://example.com/thumb.jpg" />
          </head>
          <body>
            <video src="https://example.com/video1080.mp4"></video>
            <source src="/media/audio_sample.mp3" />
          </body>
        </html>
      ''';

      final detected = MediaDetectorService.sniffHtml(html, 'https://example.com/page.html');
      expect(detected, isNotNull);
      expect(detected!.title, equals('Teste Vídeo HD'));
      expect(detected.thumbnailUrl, equals('https://example.com/thumb.jpg'));
      expect(detected.videoFormats.any((f) => f.streamId?.contains('video1080.mp4') == true), isTrue);
      expect(detected.audioFormats.any((f) => f.streamId?.contains('audio_sample.mp3') == true), isTrue);
    });

    test('sniffHtml extracts JS player configuration streams', () {
      const html = '''
        <script>
          var player = new Player({
            file: "https://streaming.cdn.example/live/stream.m3u8"
          });
        </script>
      ''';

      final detected = MediaDetectorService.sniffHtml(html, 'https://example.com/');
      expect(detected, isNotNull);
      expect(detected!.videoFormats.any((f) => f.streamId?.contains('stream.m3u8') == true), isTrue);
      expect(detected.videoFormats.first.qualityTag, equals('HLS'));
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
