import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/stash_api_client.dart';
import '../../core/server/server_session.dart';
import '../../shared/providers.dart';
import 'directory_index.dart';

DirectoryIndex _decodeIndex(String json) =>
    DirectoryIndex.fromJson(jsonDecode(json) as Map<String, dynamic>);
DirectoryIndex _buildIndex(Map<String, dynamic> json) =>
    DirectoryIndex.fromJson(json);

class DirectoryState {
  const DirectoryState({
    this.index,
    this.loading = true,
    this.error,
    this.loaded = 0,
    this.total = 0,
    this.pinned = const {},
    this.hidden = const {},
  });
  final DirectoryIndex? index;
  final bool loading;
  final String? error;
  final int loaded;
  final int total;
  final Set<String> pinned;
  final Set<String> hidden;

  bool isHidden(String path) => hidden.any((root) => pathWithin(path, root));

  DirectoryState copyWith({
    DirectoryIndex? index,
    bool? loading,
    String? error,
    int? loaded,
    int? total,
    Set<String>? pinned,
    Set<String>? hidden,
  }) => DirectoryState(
    index: index ?? this.index,
    loading: loading ?? this.loading,
    error: error,
    loaded: loaded ?? this.loaded,
    total: total ?? this.total,
    pinned: pinned ?? this.pinned,
    hidden: hidden ?? this.hidden,
  );
}

final directoryProvider = NotifierProvider<DirectoryController, DirectoryState>(
  DirectoryController.new,
);

class DirectoryController extends Notifier<DirectoryState> {
  int _generation = 0;
  StashApiClient? _api;
  String? _serverId;
  bool _refreshAgain = false;

  @override
  DirectoryState build() {
    _api = ref.watch(stashApiProvider);
    _serverId = ref.watch(activeServerSessionProvider)?.id;
    final generation = ++_generation;
    _refreshAgain = false;
    ref.onDispose(() => _generation++);
    final id = _serverId;
    if (id != null && _api != null) {
      Future.microtask(() => _restore(id, generation));
    }
    return DirectoryState(loading: id != null);
  }

  Future<void> _restore(String id, int generation) async {
    final preferences = await SharedPreferences.getInstance();
    DirectoryIndex? index;
    try {
      final raw =
          preferences.getString('directory_index_v2_$id') ??
          preferences.getString('directory_index_v1_$id');
      if (raw != null) index = await compute(_decodeIndex, raw);
    } catch (_) {
      // A corrupt/old cache is replaced with a fresh complete snapshot.
    }
    if (generation != _generation) return;
    state = DirectoryState(
      index: index,
      loading: true,
      pinned: preferences.getStringList('directory_pinned_$id')?.toSet() ?? {},
      hidden: preferences.getStringList('directory_hidden_$id')?.toSet() ?? {},
    );
    await _fetch(generation);
  }

  Future<void> refresh() async {
    if (_api == null) return;
    if (state.loading) {
      _refreshAgain = true;
      return;
    }
    state = state.copyWith(loading: true, loaded: 0, total: 0);
    await _fetch(_generation);
  }

  Future<void> _fetch(int generation) async {
    final api = _api;
    final serverId = _serverId;
    if (api == null || serverId == null) return;
    try {
      final config = await api.scanConfiguration();
      final videos = <String, DirectoryVideo>{};
      final folders = <String, ServerFolder>{};
      await Future.wait<void>([
        () async {
          for (var page = 1; ; page++) {
            final result = await api.directoryPage(page);
            if (generation != _generation) return;
            for (final video in result.videos) {
              videos[video.id] = video;
            }
            state = state.copyWith(loaded: videos.length, total: result.total);
            if (videos.length >= result.total) break;
            if (result.videos.isEmpty) {
              throw const StashApiException('视频数据发生变化，请刷新重试');
            }
          }
        }(),
        () async {
          for (var page = 1; ; page++) {
            final result = await api.folderPage(page);
            if (generation != _generation) return;
            for (final folder in result.folders) {
              folders[folder.id] = folder;
            }
            if (folders.length >= result.total) break;
            if (result.folders.isEmpty) {
              throw const StashApiException('目录数据发生变化，请刷新重试');
            }
          }
        }(),
      ]);
      if (generation != _generation) return;
      final payload = {
        'videos': videos.values.map((v) => v.toJson()).toList(),
        'roots': config.roots,
        'updatedAt': DateTime.now().toIso8601String(),
        'folders': folders.values.map((f) => f.toJson()).toList(),
      };
      final index = await compute(_buildIndex, payload);
      if (generation != _generation) return;
      state = state.copyWith(index: index, loading: false);
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(
          'directory_index_v2_$serverId',
          jsonEncode(payload),
        );
      } catch (_) {
        if (generation == _generation) {
          state = state.copyWith(error: '目录已更新，但本地缓存保存失败');
        }
      }
    } catch (error) {
      if (generation == _generation) {
        state = state.copyWith(loading: false, error: error.toString());
      }
    }
    if (generation == _generation && _refreshAgain) {
      _refreshAgain = false;
      state = state.copyWith(loading: true, loaded: 0, total: 0);
      await _fetch(generation);
    }
  }

  Future<void> togglePinned(String path) => _savePreference(path, true);
  Future<void> toggleHidden(String path) => _savePreference(path, false);

  Future<void> _savePreference(String path, bool pin) async {
    final id = _serverId;
    if (id == null) return;
    final generation = _generation;
    final values = {...(pin ? state.pinned : state.hidden)};
    final key = pathKey(path);
    values.contains(key) ? values.remove(key) : values.add(key);
    state = state.copyWith(
      pinned: pin ? values : null,
      hidden: pin ? null : values,
      error: state.error,
    );
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(
        'directory_${pin ? 'pinned' : 'hidden'}_$id',
        values.toList(),
      );
    } catch (_) {
      if (generation == _generation) {
        state = state.copyWith(error: '目录偏好保存失败，请重试');
      }
    }
  }
}
