import 'package:flutter_test/flutter_test.dart';
import 'package:stash_mobile/shared/models/scene_stream.dart';

void main() {
  test('parses stream endpoint metadata', () {
    final stream = SceneStreamEndpoint.fromJson({
      'url': 'https://stash.example/scene/42/stream.m3u8?resolution=720p',
      'mime_type': 'application/vnd.apple.mpegurl',
      'label': 'HLS HD (720p)',
    });

    expect(stream.url, contains('/stream.m3u8'));
    expect(stream.mimeType, 'application/vnd.apple.mpegurl');
    expect(stream.label, 'HLS HD (720p)');
  });

  test('removes API keys while preserving stream options', () {
    final stream = SceneStreamEndpoint.fromJson({
      'url':
          'https://stash.example/scene/42/stream.m3u8?apikey=secret&resolution=720p',
      'mime_type': 'application/vnd.apple.mpegurl',
      'label': 'HLS HD (720p)',
    });

    expect(stream.sanitizedUri.queryParameters, {'resolution': '720p'});
    expect(stream.sanitizedUrl, isNot(contains('secret')));
  });
}
