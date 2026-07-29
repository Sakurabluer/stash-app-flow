import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/stash_api_client.dart';
import '../core/server/server_session.dart';
import 'models/scene.dart';
import 'models/tag_media.dart';

final stashApiProvider = Provider<StashApiClient?>((ref) {
  final session = ref.watch(activeServerSessionProvider);
  if (session == null) return null;
  return StashApiClient(baseUrl: session.baseUrl, apiKey: session.apiKey);
});

final recentScenesProvider = FutureProvider<ScenePage>((ref) async {
  final api = ref.watch(stashApiProvider);
  if (api == null) return const ScenePage(items: [], total: 0);
  return api.findScenes(perPage: 16);
});

final recommendedScenesProvider = FutureProvider<ScenePage>((ref) async {
  final api = ref.watch(stashApiProvider);
  if (api == null) return const ScenePage(items: [], total: 0);
  return api.findScenes(perPage: 10, sort: 'random');
});

final featuredSceneProvider = FutureProvider<Scene?>((ref) async {
  final api = ref.watch(stashApiProvider);
  if (api == null) return null;
  final page = await api.findScenes(perPage: 1, sort: 'random');
  return page.items.firstOrNull;
});

final sceneProvider = FutureProvider.family<Scene?, String>((ref, id) async {
  return ref.watch(stashApiProvider)?.findScene(id);
});

final searchScenesProvider = FutureProvider.family<ScenePage, String>((
  ref,
  query,
) async {
  final api = ref.watch(stashApiProvider);
  if (api == null || query.trim().isEmpty) {
    return const ScenePage(items: [], total: 0);
  }
  return api.findScenes(perPage: 40, query: query);
});

final tagsProvider = FutureProvider<List<MediaTag>>((ref) async {
  final api = ref.watch(stashApiProvider);
  if (api == null) return const [];
  return api.findTags();
});

class LibraryState {
  const LibraryState({
    required this.items,
    required this.total,
    required this.page,
    required this.isLoadingMore,
    required this.sort,
    required this.direction,
  });

  final List<Scene> items;
  final int total;
  final int page;
  final bool isLoadingMore;
  final String sort;
  final String direction;

  bool get hasMore => items.length < total;

  LibraryState copyWith({
    List<Scene>? items,
    int? total,
    int? page,
    bool? isLoadingMore,
    String? sort,
    String? direction,
  }) => LibraryState(
    items: items ?? this.items,
    total: total ?? this.total,
    page: page ?? this.page,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    sort: sort ?? this.sort,
    direction: direction ?? this.direction,
  );
}

final libraryProvider = AsyncNotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);

class LibraryController extends AsyncNotifier<LibraryState> {
  static const _pageSize = 30;
  static const _defaultSort = 'created_at';
  static const _defaultDirection = 'DESC';

  @override
  Future<LibraryState> build() async {
    final api = ref.watch(stashApiProvider);
    if (api == null) {
      return const LibraryState(
        items: [],
        total: 0,
        page: 1,
        isLoadingMore: false,
        sort: _defaultSort,
        direction: _defaultDirection,
      );
    }
    final page = await api.findScenes(
      perPage: _pageSize,
      sort: _defaultSort,
      direction: _defaultDirection,
    );
    return LibraryState(
      items: page.items,
      total: page.total,
      page: 1,
      isLoadingMore: false,
      sort: _defaultSort,
      direction: _defaultDirection,
    );
  }

  Future<void> changeSort(String sort, String direction) async {
    final api = ref.read(stashApiProvider);
    if (api == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final page = await api.findScenes(
        perPage: _pageSize,
        sort: sort,
        direction: direction,
      );
      return LibraryState(
        items: page.items,
        total: page.total,
        page: 1,
        isLoadingMore: false,
        sort: sort,
        direction: direction,
      );
    });
  }

  Future<void> refresh() async {
    final current = state.asData?.value;
    await changeSort(
      current?.sort ?? _defaultSort,
      current?.direction ?? _defaultDirection,
    );
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    final api = ref.read(stashApiProvider);
    if (current == null ||
        api == null ||
        !current.hasMore ||
        current.isLoadingMore) {
      return;
    }
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final nextPage = current.page + 1;
      final result = await api.findScenes(
        page: nextPage,
        perPage: _pageSize,
        sort: current.sort,
        direction: current.direction,
      );
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...result.items],
          total: result.total,
          page: nextPage,
          isLoadingMore: false,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}

final favoritesProvider =
    AsyncNotifierProvider<FavoritesController, Set<String>>(
      FavoritesController.new,
    );

class FavoritesController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final serverId = ref.watch(activeServerSessionProvider)?.id;
    if (serverId == null) return <String>{};
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(_key(serverId))?.toSet() ?? <String>{};
  }

  Future<void> toggle(String id) async {
    final next = {...?state.asData?.value};
    next.contains(id) ? next.remove(id) : next.add(id);
    state = AsyncData(next);
    final serverId = ref.read(activeServerSessionProvider)?.id;
    if (serverId == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _key(serverId),
      next.toList(growable: false),
    );
  }

  static String _key(String serverId) => 'favorite_scene_ids_$serverId';
}

final favoriteScenesProvider = FutureProvider<List<Scene>>((ref) async {
  final ids = await ref.watch(favoritesProvider.future);
  final api = ref.watch(stashApiProvider);
  if (api == null || ids.isEmpty) return const [];
  final values = await Future.wait(ids.take(50).map(api.findScene));
  return values.whereType<Scene>().toList(growable: false);
});
