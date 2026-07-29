class Scene {
  const Scene({
    required this.id,
    required this.title,
    required this.fileName,
    required this.filePath,
    required this.details,
    required this.date,
    required this.rating100,
    required this.playCount,
    required this.resumeSeconds,
    required this.screenshotUrl,
    required this.streamUrl,
    required this.durationSeconds,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.tags,
  });

  final String id;
  final String title;
  final String fileName;
  final String filePath;
  final String details;
  final String? date;
  final int? rating100;
  final int playCount;
  final double resumeSeconds;
  final String screenshotUrl;
  final String streamUrl;
  final double durationSeconds;
  final int width;
  final int height;
  final int sizeBytes;
  final List<SceneTag> tags;

  factory Scene.fromJson(Map<String, dynamic> json) {
    final files = (json['files'] as List<dynamic>? ?? const []);
    final file = files.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(files.first as Map);
    final paths = Map<String, dynamic>.from(json['paths'] as Map? ?? const {});
    final rawTitle = (json['title'] as String? ?? '').trim();
    final basename = (file['basename'] as String? ?? '').trim();
    final fileName = basename.isEmpty
        ? ''
        : _cleanFilename(basename, json['id']);

    return Scene(
      id: json['id'].toString(),
      title: rawTitle.isNotEmpty
          ? rawTitle
          : _cleanFilename(basename, json['id']),
      fileName: fileName,
      filePath: (file['path'] as String? ?? '').trim(),
      details: (json['details'] as String? ?? '').trim(),
      date: json['date'] as String?,
      rating100: (json['rating100'] as num?)?.round(),
      playCount: (json['play_count'] as num?)?.round() ?? 0,
      resumeSeconds: (json['resume_time'] as num?)?.toDouble() ?? 0,
      screenshotUrl: paths['screenshot'] as String? ?? '',
      streamUrl: paths['stream'] as String? ?? '',
      durationSeconds: (file['duration'] as num?)?.toDouble() ?? 0,
      width: (file['width'] as num?)?.round() ?? 0,
      height: (file['height'] as num?)?.round() ?? 0,
      sizeBytes: (file['size'] as num?)?.round() ?? 0,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map(
            (item) => SceneTag.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .where((tag) => tag.id.isNotEmpty && tag.name.isNotEmpty)
          .toList(growable: false),
    );
  }

  String get displayTitle => fileName.isNotEmpty ? fileName : title;

  static String _cleanFilename(String basename, dynamic id) {
    if (basename.isEmpty) return '场景 #$id';
    return basename.replaceFirst(RegExp(r'\.[^.]+$'), '');
  }

  String get durationLabel {
    final totalMinutes = (durationSeconds / 60).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return hours > 0 ? '$hours 小时 $minutes 分钟' : '$minutes 分钟';
  }

  String get qualityLabel {
    if (width >= 3840 || height >= 2160) return '4K';
    if (width >= 1920 || height >= 1080) return '1080P';
    if (width >= 1280 || height >= 720) return 'HD';
    return 'SD';
  }

  String get sizeLabel {
    if (sizeBytes <= 0) return '未知';
    final gib = sizeBytes / 1073741824;
    return gib >= 1
        ? '${gib.toStringAsFixed(1)} GB'
        : '${(sizeBytes / 1048576).round()} MB';
  }

  double get progress => durationSeconds <= 0
      ? 0
      : (resumeSeconds / durationSeconds).clamp(0, 1).toDouble();

  Uri get sanitizedStreamUri {
    final uri = Uri.parse(streamUrl);
    final params = Map<String, String>.from(uri.queryParameters)
      ..removeWhere((key, _) => key.toLowerCase() == 'apikey');
    return params.isEmpty
        ? uri.replace(query: '')
        : uri.replace(queryParameters: params);
  }
}

class SceneTag {
  const SceneTag({required this.id, required this.name});

  final String id;
  final String name;

  factory SceneTag.fromJson(Map<String, dynamic> json) => SceneTag(
    id: json['id']?.toString() ?? '',
    name: (json['name'] as String? ?? '').trim(),
  );
}

class ScenePage {
  const ScenePage({required this.items, required this.total});

  final List<Scene> items;
  final int total;
}
