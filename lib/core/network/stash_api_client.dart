import 'package:dio/dio.dart';

import '../../shared/models/scene.dart';
import '../../shared/models/scene_stream.dart';
import '../../shared/models/tag_media.dart';
import '../../features/directories/directory_index.dart';

class ServerInfo {
  const ServerInfo({
    required this.version,
    required this.sceneCount,
    required this.tagCount,
  });

  final String version;
  final int sceneCount;
  final int tagCount;
}

class StashApiClient {
  StashApiClient({required String baseUrl, required String apiKey})
    : _dio = Dio(
        BaseOptions(
          baseUrl: _normalizeBaseUrl(baseUrl),
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 25),
          headers: <String, String>{
            'ApiKey': apiKey,
            'Content-Type': 'application/json',
          },
        ),
      );

  final Dio _dio;

  static String _normalizeBaseUrl(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');

  Future<Map<String, dynamic>> _query(
    String document, {
    Map<String, dynamic>? variables,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/graphql',
        data: <String, dynamic>{'query': document, 'variables': variables},
      );
      final body = response.data ?? const <String, dynamic>{};
      final errors = body['errors'] as List<dynamic>?;
      if (errors != null && errors.isNotEmpty) {
        final first = errors.first as Map;
        throw StashApiException(first['message']?.toString() ?? 'GraphQL 请求失败');
      }
      return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        throw const StashApiException('API Key 无效或权限不足');
      }
      throw StashApiException(
        error.type == DioExceptionType.connectionTimeout
            ? '连接服务器超时'
            : '无法连接 Stash Server',
        requestMayHaveSucceeded: document.trimLeft().startsWith('mutation'),
      );
    }
  }

  Future<ServerInfo> getServerInfo() async {
    final data = await _query(r'''
      query BootstrapInfo {
        version { version }
        stats { scene_count tag_count }
      }
    ''');
    final version = Map<String, dynamic>.from(data['version'] as Map);
    final stats = Map<String, dynamic>.from(data['stats'] as Map);
    return ServerInfo(
      version: version['version']?.toString() ?? '未知版本',
      sceneCount: (stats['scene_count'] as num?)?.round() ?? 0,
      tagCount: (stats['tag_count'] as num?)?.round() ?? 0,
    );
  }

  Future<ScenePage> findScenes({
    int page = 1,
    int perPage = 30,
    String? query,
    String sort = 'created_at',
    String direction = 'DESC',
    String? tagId,
    Map<String, dynamic>? sceneFilter,
  }) async {
    final filter = <String, dynamic>{
      'page': page,
      'per_page': perPage,
      'sort': sort,
      'direction': direction,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    };
    final data = await _query(
      _sceneListQuery,
      variables: <String, dynamic>{
        'filter': filter,
        if (sceneFilter != null || tagId != null)
          'scene_filter': <String, dynamic>{
            ...?sceneFilter,
            if (tagId != null)
              'tags': <String, dynamic>{
                'value': [tagId],
                'modifier': 'INCLUDES',
              },
          },
      },
    );
    final result = Map<String, dynamic>.from(data['findScenes'] as Map);
    final items = (result['scenes'] as List<dynamic>? ?? const [])
        .map((item) => Scene.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
    return ScenePage(
      items: items,
      total: (result['count'] as num?)?.round() ?? items.length,
    );
  }

  Future<List<MediaTag>> findTags() async {
    final data = await _query(
      _tagListQuery,
      variables: <String, dynamic>{
        'filter': <String, dynamic>{
          'page': 1,
          'per_page': -1,
          'sort': 'name',
          'direction': 'ASC',
        },
      },
    );
    final result = Map<String, dynamic>.from(data['findTags'] as Map);
    return (result['tags'] as List<dynamic>? ?? const [])
        .map(
          (item) => MediaTag.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .where((tag) => tag.name.isNotEmpty)
        .toList(growable: false);
  }

  Future<ImagePage> findImages({
    int page = 1,
    int perPage = 30,
    String? tagId,
    String? query,
    Map<String, dynamic>? imageFilter,
    String sort = 'created_at',
    String direction = 'DESC',
  }) async {
    final data = await _query(
      _imageListQuery,
      variables: <String, dynamic>{
        'filter': <String, dynamic>{
          'page': page,
          'per_page': perPage,
          'sort': sort,
          'direction': direction,
          if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        },
        'image_filter': <String, dynamic>{
          ...?imageFilter,
          if (tagId != null)
            'tags': <String, dynamic>{
              'value': [tagId],
              'modifier': 'INCLUDES',
            },
        },
      },
    );
    final result = Map<String, dynamic>.from(data['findImages'] as Map);
    final items = (result['images'] as List<dynamic>? ?? const [])
        .map(
          (item) => StashImage.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
    return ImagePage(
      items: items,
      total: (result['count'] as num?)?.round() ?? items.length,
    );
  }

  Future<Scene?> findScene(String id) async {
    final data = await _query(
      _sceneDetailQuery,
      variables: <String, dynamic>{'id': id},
    );
    final value = data['findScene'];
    return value is Map
        ? Scene.fromJson(Map<String, dynamic>.from(value))
        : null;
  }

  Future<({List<ServerFolder> folders, int total})> folderPage(int page) async {
    final data = await _query(
      r'''
      query DirectoryFolders($page: Int!) {
        findFolders(filter: {page: $page, per_page: 500, sort: "id", direction: ASC}) {
          count folders { id path zip_file { id } }
        }
      }
    ''',
      variables: {'page': page},
    );
    final result = data['findFolders'] as Map;
    return (
      folders: (result['folders'] as List)
          .map(
            (row) =>
                ServerFolder.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(),
      total: (result['count'] as num).toInt(),
    );
  }

  Future<Map<String, int>> imageCounts(
    Map<String, Map<String, dynamic>> scopes,
  ) async {
    if (scopes.isEmpty) return {};
    final variables = <String, dynamic>{};
    final arguments = <String>[];
    final fields = <String>[];
    var i = 0;
    for (final entry in scopes.entries) {
      final name = 'scope${i++}';
      arguments.add('\$$name: ImageFilterType');
      variables[name] = entry.value;
      fields.add(
        '$name: findImages(filter: {per_page: 0}, image_filter: \$$name) { count }',
      );
    }
    final data = await _query(
      'query DirectoryImageCounts(${arguments.join(',')}) { ${fields.join(' ')} }',
      variables: variables,
    );
    i = 0;
    return {
      for (final key in scopes.keys)
        key: ((data['scope${i++}'] as Map)['count'] as num).toInt(),
    };
  }

  Future<({List<DirectoryVideo> items, int total})> imageIndexPage(
    int page,
    Map<String, dynamic> imageFilter,
  ) async {
    final data = await _query(
      r'''
      query DirectoryImageIndex($page: Int!, $scope: ImageFilterType) {
        findImages(filter: {page: $page, per_page: 1000, sort: "id", direction: ASC}, image_filter: $scope) {
          count images { id created_at visual_files {
            ... on ImageFile { path }
            ... on VideoFile { path }
          } }
        }
      }
    ''',
      variables: {'page': page, 'scope': imageFilter},
    );
    final result = data['findImages'] as Map;
    return (
      items: (result['images'] as List).map((row) {
        final map = Map<String, dynamic>.from(row as Map);
        return DirectoryVideo.fromJson({...map, 'files': map['visual_files']});
      }).toList(),
      total: (result['count'] as num).toInt(),
    );
  }

  Future<List<StashImage>> imagesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final data = await _query(
      '''
      query DirectoryImageDetails(\$ids: [ID!]) {
        findImages(ids: \$ids, filter: {per_page: 30}) { images { $_imageFields } }
      }
    ''',
      variables: {'ids': ids},
    );
    final rows = ((data['findImages'] as Map)['images'] as List).map(
      (row) => StashImage.fromJson(Map<String, dynamic>.from(row as Map)),
    );
    final byId = {for (final image in rows) image.id: image};
    return ids.map((id) => byId[id]).whereType<StashImage>().toList();
  }

  Future<({List<DirectoryVideo> videos, int total})> directoryPage(
    int page,
  ) async {
    final data = await _query(
      r'''
      query DirectoryIndex($page: Int!) {
        findScenes(filter: {page: $page, per_page: 500, sort: "id", direction: ASC}) {
          count scenes { id created_at files { path } }
        }
      }
    ''',
      variables: {'page': page},
    );
    final result = data['findScenes'] as Map;
    return (
      videos: (result['scenes'] as List)
          .map(
            (row) =>
                DirectoryVideo.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(),
      total: (result['count'] as num).toInt(),
    );
  }

  Future<List<Scene>> scenesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final data = await _query(
      '''
      query DirectoryScenes(\$ids: [ID!]) {
        findScenes(ids: \$ids, filter: {per_page: 30}) { scenes { $_sceneFields } }
      }
    ''',
      variables: {'ids': ids},
    );
    final scenes = ((data['findScenes'] as Map)['scenes'] as List).map(
      (row) => Scene.fromJson(Map<String, dynamic>.from(row as Map)),
    );
    final byId = {for (final scene in scenes) scene.id: scene};
    return ids.map((id) => byId[id]).whereType<Scene>().toList();
  }

  Future<ScanConfiguration> scanConfiguration() async {
    final data = await _query(r'''
      query ScanConfiguration {
        configuration {
          general { stashes { path excludeVideo excludeImage } }
          defaults { scan { scanGenerateCovers } }
        }
      }
    ''');
    final config = data['configuration'] as Map;
    final stashes = (config['general'] as Map)['stashes'] as List;
    final scan = (config['defaults'] as Map?)?['scan'] as Map?;
    return ScanConfiguration(
      roots: stashes
          .where(
            (s) =>
                (s as Map)['excludeVideo'] != true || s['excludeImage'] != true,
          )
          .map((s) => (s as Map)['path'] as String)
          .toList(),
      generateCovers: scan?['scanGenerateCovers'] as bool? ?? true,
    );
  }

  Future<List<ScanJob>> jobQueue() async {
    final data = await _query('query { jobQueue { $_jobFields } }');
    return (data['jobQueue'] as List? ?? [])
        .map((row) => ScanJob.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<ScanJob?> findJob(String id) async {
    final data = await _query(
      '''
      query ScanJob(\$input: FindJobInput!) { findJob(input: \$input) { $_jobFields } }
    ''',
      variables: {
        'input': {'id': id},
      },
    );
    final row = data['findJob'];
    return row is Map ? ScanJob.fromJson(Map<String, dynamic>.from(row)) : null;
  }

  Future<String> scan({String? path, bool generatePreviews = false}) async {
    // Validate again immediately before submission, using live server configuration.
    final config = await scanConfiguration();
    if (config.roots.isEmpty) throw const StashApiException('服务器未配置媒体路径');
    if (path != null &&
        (!validScanPath(path) ||
            !config.roots.any((root) => pathWithin(path, root)))) {
      throw const StashApiException('此目录不在服务器配置的媒体路径内');
    }
    final data = await _query(
      r'''
      mutation Scan($input: ScanMetadataInput!) { metadataScan(input: $input) }
    ''',
      variables: {
        'input': {
          'paths': path == null ? config.roots : [path],
          'rescan': false,
          'scanGenerateCovers': config.generateCovers,
          'scanGeneratePreviews': generatePreviews,
          'scanGenerateImagePreviews': generatePreviews,
          'scanGenerateSprites': generatePreviews,
          'scanGeneratePhashes': generatePreviews,
          'scanGenerateThumbnails': generatePreviews,
          'scanGenerateClipPreviews': generatePreviews,
        },
      },
    );
    return data['metadataScan'].toString();
  }

  static const _jobFields = 'id status description progress error';

  Future<List<SceneStreamEndpoint>> findSceneStreams(String id) async {
    final data = await _query(
      _sceneStreamsQuery,
      variables: <String, dynamic>{'id': id},
    );
    final scene = data['findScene'];
    if (scene is! Map) return const [];
    final streams =
        (Map<String, dynamic>.from(scene)['sceneStreams'] as List<dynamic>?) ??
        const [];
    return streams
        .map(
          (item) => SceneStreamEndpoint.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .where((stream) => stream.url.isNotEmpty)
        .toList(growable: false);
  }

  static const _sceneFields = r'''
    id title details date rating100 play_count resume_time
    paths { screenshot stream }
    files { basename path duration width height size }
    tags { id name }
  ''';

  static const _sceneListQuery =
      '''
    query FindScenes(\$filter: FindFilterType, \$scene_filter: SceneFilterType) {
      findScenes(filter: \$filter, scene_filter: \$scene_filter) {
        count
        scenes { $_sceneFields }
      }
    }
  ''';

  static const _tagListQuery = r'''
    query FindTags($filter: FindFilterType) {
      findTags(filter: $filter) {
        count
        tags { id name scene_count image_count }
      }
    }
  ''';

  static const _imageFields = r'''
    id title
    paths { thumbnail image }
    visual_files {
      ... on ImageFile { path basename width height }
      ... on VideoFile { path basename width height }
    }
  ''';

  static const _imageListQuery =
      '''
    query FindImages(\$filter: FindFilterType, \$image_filter: ImageFilterType) {
      findImages(filter: \$filter, image_filter: \$image_filter) {
        count images { $_imageFields }
      }
    }
  ''';

  static const _sceneDetailQuery =
      '''
    query FindScene(\$id: ID!) {
      findScene(id: \$id) { $_sceneFields }
    }
  ''';

  static const _sceneStreamsQuery = r'''
    query SceneStreams($id: ID!) {
      findScene(id: $id) {
        sceneStreams {
          url
          mime_type
          label
        }
      }
    }
  ''';
}

class StashApiException implements Exception {
  const StashApiException(this.message, {this.requestMayHaveSucceeded = false});

  final String message;
  final bool requestMayHaveSucceeded;

  @override
  String toString() => message;
}

class ScanConfiguration {
  const ScanConfiguration({required this.roots, required this.generateCovers});
  final List<String> roots;
  final bool generateCovers;
}

class ScanJob {
  const ScanJob({
    required this.id,
    required this.status,
    required this.description,
    this.progress,
    this.error,
  });
  final String id;
  final String status;
  final String description;
  final double? progress;
  final String? error;
  bool get active => const ['READY', 'RUNNING', 'STOPPING'].contains(status);
  bool get isScan =>
      RegExp(r'scan|扫描', caseSensitive: false).hasMatch(description);
  String get statusLabel => switch (status) {
    'READY' => '排队中',
    'RUNNING' => '扫描中',
    'FINISHED' => '扫描完成',
    'FAILED' => '扫描失败',
    'CANCELLED' => '扫描已取消',
    'STOPPING' => '正在停止',
    _ => '状态待确认',
  };
  factory ScanJob.fromJson(Map<String, dynamic> json) => ScanJob(
    id: json['id'].toString(),
    status: json['status'] as String,
    description: json['description'] as String? ?? '',
    progress: (json['progress'] as num?)?.toDouble(),
    error: json['error'] as String?,
  );
}
