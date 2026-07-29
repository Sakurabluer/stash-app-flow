import 'package:flutter_test/flutter_test.dart';
import 'package:stash_mobile/shared/models/tag_media.dart';

void main() {
  test('parses tag media counts', () {
    final tag = MediaTag.fromJson({
      'id': '7',
      'name': '示例标签',
      'scene_count': 12,
      'image_count': 8,
    });

    expect(tag.id, '7');
    expect(tag.name, '示例标签');
    expect(tag.sceneCount, 12);
    expect(tag.imageCount, 8);
    expect(tag.mediaCount, 20);
  });

  test('parses image paths and dimensions', () {
    final image = StashImage.fromJson({
      'id': '9',
      'title': '封面',
      'paths': {
        'thumbnail': 'http://example.test/thumb.jpg',
        'image': 'http://example.test/image.jpg',
      },
      'visual_files': [
        {'width': 1920, 'height': 1080},
      ],
    });

    expect(image.title, '封面');
    expect(image.thumbnailUrl, 'http://example.test/thumb.jpg');
    expect(image.imageUrl, 'http://example.test/image.jpg');
    expect(image.width, 1920);
    expect(image.height, 1080);
  });
}
