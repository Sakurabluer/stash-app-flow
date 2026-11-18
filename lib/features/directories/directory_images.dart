import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/stash_api_client.dart';
import '../../shared/models/tag_media.dart';
import '../../shared/providers.dart';
import 'directory_index.dart';
import 'directory_providers.dart';

Map<String, dynamic> imageScopeFilter(
  DirectoryState state,
  DirectoryScope scope,
) {
  final folder = state.index?.directory(scope.path);
  Map<String, dynamic> location(String path, String? id, bool recursive) {
    if (id != null) {
      return {
        'parent_folder': {
          'value': [id],
          'modifier': 'INCLUDES',
          'depth': recursive ? -1 : 0,
        },
      };
    }
    final prefix = serverPath(path);
    final pattern =
        '${RegExp.escape(prefix)}${prefix.endsWith('/') ? '' : '/'}';
    return {
      'path': {
        'value': '^$pattern${recursive ? '' : '[^/]+\$'}',
        'modifier': 'MATCHES_REGEX',
      },
    };
  }

  Map<String, dynamic> filter = location(
    scope.path,
    folder?.folderId,
    scope.recursive,
  );
  // File-level exclusions retain an image that also has a copy in a visible folder.
  Map<String, dynamic>? exclusions;
  for (final hidden in state.hidden) {
    final excluded = location(
      state.index?.directory(hidden)?.path ?? hidden,
      state.index?.directory(hidden)?.folderId,
      true,
    );
    exclusions = {...excluded, 'OR': ?exclusions};
  }
  if (exclusions != null) {
    filter = {
      ...filter,
      'AND': {'NOT': exclusions},
    };
  }
  return {'files_filter': filter};
}

final directoryImageCountProvider = FutureProvider.autoDispose
    .family<int, DirectoryScope>((ref, scope) async {
      final api = ref.watch(stashApiProvider);
      final index = ref.watch(directoryProvider.select((s) => s.index));
      final hidden = ref.watch(directoryProvider.select((s) => s.hidden));
      final state = DirectoryState(index: index, hidden: hidden);
      if (api == null || state.index == null) return 0;
      final result = await api.imageCounts({
        'count': imageScopeFilter(state, scope),
      });
      return result['count']!;
    });

// Each visible directory page requests its counts in a single GraphQL request.
final folderImageCountsProvider = FutureProvider.autoDispose
    .family<Map<String, int>, String>((ref, encodedPaths) async {
      final api = ref.watch(stashApiProvider);
      final index = ref.watch(directoryProvider.select((s) => s.index));
      final hidden = ref.watch(directoryProvider.select((s) => s.hidden));
      final state = DirectoryState(index: index, hidden: hidden);
      if (api == null || state.index == null) return {};
      final paths = List<String>.from(jsonDecode(encodedPaths) as List);
      return api.imageCounts({
        for (final path in paths)
          path: imageScopeFilter(state, (path: path, recursive: true)),
      });
    });

typedef DirectoryImageQuery = ({
  String path,
  bool recursive,
  bool byDate,
  bool descending,
});

class DirectoryImagesState {
  const DirectoryImagesState({
    required this.items,
    required this.total,
    required this.offset,
    this.ids,
    this.loadingMore = false,
    this.error,
  });
  final List<StashImage> items;
  final int total;
  final int offset;
  final List<String>? ids;
  final bool loadingMore;
  final String? error;
  bool get hasMore => offset < total;
}

List<String> _sortImageIndex(Map<String, dynamic> payload) {
  final rows = (payload['rows'] as List)
      .map(
        (row) => DirectoryVideo.fromJson(Map<String, dynamic>.from(row as Map)),
      )
      .toList();
  final path = payload['path'] as String;
  final recursive = payload['recursive'] as bool;
  final hidden = List<String>.from(payload['hidden'] as List);
  final filenames = <String, String>{};
  for (final row in rows) {
    final paths =
        row.paths
            .where(
              (file) =>
                  fileInScope(file, (path: path, recursive: recursive), hidden),
            )
            .toList()
          ..sort(naturalCompare);
    filenames[row.id] = paths.isEmpty ? row.id : pathName(paths.first);
  }
  rows.sort((a, b) {
    var result = naturalCompare(filenames[a.id]!, filenames[b.id]!);
    if (result == 0) result = naturalCompare(a.id, b.id);
    return payload['descending'] == true ? -result : result;
  });
  return rows.map((row) => row.id).toList();
}

final directoryImagesProvider = AsyncNotifierProvider.autoDispose
    .family<
      DirectoryImagesController,
      DirectoryImagesState,
      DirectoryImageQuery
    >(DirectoryImagesController.new);

class DirectoryImagesController
    extends
        AutoDisposeFamilyAsyncNotifier<
          DirectoryImagesState,
          DirectoryImageQuery
        > {
  int _generation = 0;
  late DirectoryImageQuery _query;
  late Map<String, dynamic> _filter;
  StashApiClient? _api;

  @override
  Future<DirectoryImagesState> build(DirectoryImageQuery arg) async {
    _query = arg;
    _api = ref.watch(stashApiProvider);
    // Loading progress does not invalidate an already loaded directory list.
    final index = ref.watch(directoryProvider.select((s) => s.index));
    final hidden = ref.watch(directoryProvider.select((s) => s.hidden));
    final generation = ++_generation;
    ref.onDispose(() => _generation++);
    final api = _api;
    if (api == null || index == null) {
      return const DirectoryImagesState(items: [], total: 0, offset: 0);
    }
    final filter = imageScopeFilter(
      DirectoryState(index: index, hidden: hidden),
      (path: arg.path, recursive: arg.recursive),
    );
    _filter = filter;
    if (arg.byDate) {
      final page = await api.findImages(
        imageFilter: filter,
        direction: arg.descending ? 'DESC' : 'ASC',
      );
      return DirectoryImagesState(
        items: page.items,
        total: page.total,
        offset: page.items.length,
      );
    }
    // Natural ordering needs the whole selected scope, but only paths/IDs are read.
    final rows = <String, DirectoryVideo>{};
    for (var page = 1; ; page++) {
      final result = await api.imageIndexPage(page, filter);
      if (generation != _generation) {
        return const DirectoryImagesState(items: [], total: 0, offset: 0);
      }
      for (final image in result.items) {
        rows[image.id] = image;
      }
      if (rows.length >= result.total) break;
      if (result.items.isEmpty) throw const StashApiException('图片数据发生变化，请刷新重试');
    }
    final ids = await compute(_sortImageIndex, {
      'rows': rows.values.map((row) => row.toJson()).toList(),
      'path': arg.path,
      'recursive': arg.recursive,
      'descending': arg.descending,
      'hidden': hidden.toList(),
    });
    final batch = ids.take(30).toList();
    final items = await api.imagesByIds(batch);
    return DirectoryImagesState(
      items: items,
      total: ids.length,
      offset: batch.length,
      ids: ids,
    );
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    final api = _api;
    if (current == null ||
        api == null ||
        current.loadingMore ||
        !current.hasMore) {
      return;
    }
    final generation = _generation;
    final query = _query;
    final filter = _filter;
    state = AsyncData(
      DirectoryImagesState(
        items: current.items,
        total: current.total,
        offset: current.offset,
        ids: current.ids,
        loadingMore: true,
      ),
    );
    try {
      final ids = current.ids;
      final ImagePage page;
      final int offset;
      if (ids == null) {
        page = await api.findImages(
          page: current.offset ~/ 30 + 1,
          imageFilter: filter,
          direction: query.descending ? 'DESC' : 'ASC',
        );
        offset = current.offset + page.items.length;
        if (page.items.isEmpty && current.offset < page.total) {
          throw const StashApiException('图片列表发生变化，请刷新重试');
        }
      } else {
        final batch = ids.skip(current.offset).take(30).toList();
        page = ImagePage(
          items: await api.imagesByIds(batch),
          total: current.total,
        );
        offset = current.offset + batch.length;
      }
      if (generation != _generation) return;
      final seen = current.items.map((item) => item.id).toSet();
      state = AsyncData(
        DirectoryImagesState(
          items: [
            ...current.items,
            ...page.items.where((item) => seen.add(item.id)),
          ],
          total: page.total,
          offset: offset,
          ids: ids,
        ),
      );
    } catch (error) {
      if (generation == _generation) {
        state = AsyncData(
          DirectoryImagesState(
            items: current.items,
            total: current.total,
            offset: current.offset,
            ids: current.ids,
            error: error.toString(),
          ),
        );
      }
    }
  }
}
