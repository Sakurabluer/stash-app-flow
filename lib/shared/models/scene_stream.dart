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
