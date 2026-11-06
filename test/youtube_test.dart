import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('YoutubeExplode types verification', () {
    final yt = YoutubeExplode();
    // VideoId test
    final id = VideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(id.value, equals('dQw4w9WgXcQ'));
    yt.close();
  });
}
