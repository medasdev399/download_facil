import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:download_facil/services/media_detector_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  test('detects anime episode media from animesonlinecc.to', () async {
    const url = 'https://animesonlinecc.to/episodio/overlord-2-episodio-1/';
    final result = await MediaDetectorService.detectFromUrl(url);

    expect(result, isNotNull);
    print('Detected title: ${result!.title}');
    print('Detected thumbnail: ${result.thumbnailUrl}');
    print('Detected duration: ${result.duration}');
    print('Detected video formats (${result.videoFormats.length}):');
    for (final f in result.videoFormats) {
      final streamSnippet = (f.streamId != null && f.streamId!.length > 60)
          ? '${f.streamId!.substring(0, 60)}...'
          : f.streamId;
      print('  - ${f.label} (${f.qualityTag}) [${f.extension}] -> streamId: $streamSnippet');
      expect(f.httpHeaders, isNotNull);
      expect(f.httpHeaders!['Referer'], contains('blogger.com'));
    }
    print('Detected audio formats (${result.audioFormats.length}):');
    for (final f in result.audioFormats) {
      print('  - ${f.label} (${f.qualityTag}) [${f.extension}]');
    }

    expect(result.title, contains('Overlord 2 Episodio 1'));
    expect(result.thumbnailUrl, isNotNull);
    expect(result.videoFormats, isNotEmpty);
    expect(result.audioFormats, isNotEmpty);
  });
}
