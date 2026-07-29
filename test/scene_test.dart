import 'package:flutter_test/flutter_test.dart';
import 'package:stash_mobile/shared/models/scene.dart';

void main() {
  test('uses the file basename when the scene title is empty', () {
    final scene = Scene.fromJson({
      'id': '42',
      'title': '',
      'paths': {'screenshot': '/image', 'stream': '/stream?apikey=secret'},
      'files': [
        {
          'basename': 'sample-video.mp4',
          'path': r'D:\Media\sample-video.mp4',
          'duration': 3660,
          'width': 1920,
          'height': 1080,
          'size': 1073741824,
        },
      ],
      'tags': [
        {'id': '7', 'name': '示例标签'},
      ],
    });

    expect(scene.title, 'sample-video');
    expect(scene.displayTitle, 'sample-video');
    expect(scene.filePath, r'D:\Media\sample-video.mp4');
    expect(scene.tags.single.id, '7');
    expect(scene.tags.single.name, '示例标签');
    expect(scene.durationLabel, '1 小时 1 分钟');
    expect(scene.qualityLabel, '1080P');
    expect(scene.sanitizedStreamUri.queryParameters, isEmpty);
  });

  test('uses the original filename for list display', () {
    final scene = Scene.fromJson({
      'id': '88',
      'title': '88',
      'paths': <String, dynamic>{},
      'files': [
        {'basename': 'original-file-name.mp4'},
      ],
    });

    expect(scene.title, '88');
    expect(scene.displayTitle, 'original-file-name');
  });

  test('clamps playback progress to the valid range', () {
    final scene = Scene.fromJson({
      'id': '1',
      'title': 'Scene',
      'resume_time': 500,
      'paths': <String, dynamic>{},
      'files': [
        {'duration': 100},
      ],
    });

    expect(scene.progress, 1);
  });
}
