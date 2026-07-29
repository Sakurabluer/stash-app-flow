class MediaTag {
  const MediaTag({
    required this.id,
    required this.name,
    required this.sceneCount,
    required this.imageCount,
  });

  final String id;
  final String name;
  final int sceneCount;
  final int imageCount;

  int get mediaCount => sceneCount + imageCount;

  factory MediaTag.fromJson(Map<String, dynamic> json) => MediaTag(
    id: json['id'].toString(),
    name: (json['name'] as String? ?? '').trim(),
    sceneCount: (json['scene_count'] as num?)?.round() ?? 0,
    imageCount: (json['image_count'] as num?)?.round() ?? 0,
  );
}

class StashImage {
  const StashImage({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.imageUrl,
    required this.width,
    required this.height,
  });

  final String id;
  final String title;
  final String thumbnailUrl;
  final String imageUrl;
  final int width;
  final int height;

  factory StashImage.fromJson(Map<String, dynamic> json) {
    final paths = Map<String, dynamic>.from(json['paths'] as Map? ?? const {});
    final files = json['visual_files'] as List<dynamic>? ?? const [];
    final file = files.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(files.first as Map);
    final rawTitle = (json['title'] as String? ?? '').trim();
    return StashImage(
      id: json['id'].toString(),
      title: rawTitle.isEmpty ? '图片 #${json['id']}' : rawTitle,
      thumbnailUrl: paths['thumbnail'] as String? ?? '',
      imageUrl: paths['image'] as String? ?? '',
      width: (file['width'] as num?)?.round() ?? 0,
      height: (file['height'] as num?)?.round() ?? 0,
    );
  }
}

class ImagePage {
  const ImagePage({required this.items, required this.total});

  final List<StashImage> items;
  final int total;
}
