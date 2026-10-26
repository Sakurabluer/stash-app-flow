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

  test('adds the server start offset to seekable transcode endpoints', () {
    final stream = SceneStreamEndpoint.fromJson({
      'url':
          'https://stash.example/scene/42/stream.mp4?apikey=secret&resolution=720p',
      'mime_type': 'video/mp4',
      'label': 'MP4 HD (720p)',
    });

    final uri = stream.uriAtStart(
      const Duration(minutes: 1, milliseconds: 250),
    );

    expect(stream.supportsServerStart, isTrue);
    expect(uri.queryParameters, {'resolution': '720p', 'start': '60.25'});
    expect(uri.toString(), isNot(contains('secret')));
  });

  test('does not add server start to direct or segmented stream endpoints', () {
    for (final path in ['/stream', '/stream.m3u8', '/stream.mpd']) {
      final stream = SceneStreamEndpoint.fromJson({
        'url': 'https://stash.example/scene/42$path?resolution=720p',
        'label': 'Transcode',
      });

      expect(stream.supportsServerStart, isFalse);
      expect(stream.uriAtStart(const Duration(seconds: 20)).queryParameters, {
        'resolution': '720p',
      });
    }
  });
}
