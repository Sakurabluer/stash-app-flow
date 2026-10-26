class SceneStreamEndpoint {
  const SceneStreamEndpoint({
    required this.url,
    required this.label,
    required this.mimeType,
  });

  final String url;
  final String label;
  final String? mimeType;

  factory SceneStreamEndpoint.fromJson(Map<String, dynamic> json) =>
      SceneStreamEndpoint(
        url: (json['url'] as String? ?? '').trim(),
        label: (json['label'] as String? ?? '').trim(),
        mimeType: json['mime_type'] as String?,
      );

  Uri get sanitizedUri => sanitizeMediaUri(Uri.parse(url));

  String get sanitizedUrl => sanitizedUri.toString();

  bool get supportsServerStart {
    final path = sanitizedUri.path.toLowerCase();
    return path.endsWith('.mp4') ||
        path.endsWith('.webm') ||
        path.endsWith('.mkv');
  }

  Uri uriAtStart(Duration position) {
    final uri = sanitizedUri;
    if (!supportsServerStart || position <= Duration.zero) return uri;

    final seconds = (position.inMilliseconds / 1000).toStringAsFixed(3);
    final start = seconds
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    final queryParameters = Map<String, dynamic>.from(uri.queryParametersAll)
      ..['start'] = start;
    return uri.replace(queryParameters: queryParameters);
  }
}

Uri sanitizeMediaUri(Uri uri) {
  final queryParameters = <String, dynamic>{};
  for (final entry in uri.queryParametersAll.entries) {
    if (entry.key.toLowerCase() != 'apikey') {
      queryParameters[entry.key] = entry.value;
    }
  }

  return queryParameters.isEmpty
      ? uri.replace(query: '')
      : uri.replace(queryParameters: queryParameters);
}
