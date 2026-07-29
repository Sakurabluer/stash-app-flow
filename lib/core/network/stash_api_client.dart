import 'package:dio/dio.dart';

import '../../shared/models/scene.dart';
import '../../shared/models/tag_media.dart';

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
        if (tagId != null)
          'scene_filter': <String, dynamic>{
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
    required String tagId,
    String? query,
  }) async {
    final data = await _query(
      _imageListQuery,
      variables: <String, dynamic>{
        'filter': <String, dynamic>{
          'page': page,
          'per_page': perPage,
          'sort': 'created_at',
          'direction': 'DESC',
          if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        },
        'image_filter': <String, dynamic>{
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

  static const _imageListQuery = r'''
    query FindImages($filter: FindFilterType, $image_filter: ImageFilterType) {
      findImages(filter: $filter, image_filter: $image_filter) {
        count
        images {
          id title
          paths { thumbnail image }
          visual_files { width height }
        }
      }
    }
  ''';

  static const _sceneDetailQuery =
      '''
    query FindScene(\$id: ID!) {
      findScene(id: \$id) { $_sceneFields }
    }
  ''';
}

class StashApiException implements Exception {
  const StashApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
