import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/stash_api_client.dart';
import '../../core/server/server_session.dart';
import '../../shared/providers.dart';
import '../directories/directory_providers.dart';

class ScanState {
  const ScanState({
    this.job,
    this.busy = false,
    this.error,
    this.path,
    this.uncertain = false,
    this.refreshError,
  });
  final ScanJob? job;
  final bool busy;
  final String? error;
  final String? path;
  final bool uncertain;
  final String? refreshError;
  bool get blocked => busy || uncertain || (job?.active ?? false);
}

final scanProvider = NotifierProvider<ScanController, ScanState>(
  ScanController.new,
);

class ScanController extends Notifier<ScanState> {
  StashApiClient? _api;
  String? _serverId;
  Timer? _timer;
  int _generation = 0;
  bool _polling = false;
  bool _foreground = true;

  @override
  ScanState build() {
    _api = ref.watch(stashApiProvider);
    _serverId = ref.watch(activeServerSessionProvider)?.id;
    final generation = ++_generation;
    _timer?.cancel();
    _polling = false;
    final lifecycle = AppLifecycleListener(
      onStateChange: (status) {
        _foreground = status == AppLifecycleState.resumed;
        if (!_foreground) {
          _timer?.cancel();
        } else {
          unawaited(check());
        }
      },
    );
    ref.onDispose(() {
      _generation++;
      _timer?.cancel();
      lifecycle.dispose();
    });
    if (_api != null) Future.microtask(() => _restore(generation));
    return ScanState(busy: _api != null);
  }

  String _key(String id) => 'scan_job_v1_$id';

  Future<void> _restore(int generation) async {
    final id = _serverId;
    if (id == null) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final jobId = preferences.getString(_key(id));
      if (generation != _generation) return;
      state = ScanState(
        job: jobId != null && jobId != 'pending'
            ? ScanJob(id: jobId, status: 'UNKNOWN', description: '恢复扫描状态')
            : null,
        uncertain: jobId == 'pending',
      );
      await check();
    } catch (error) {
      if (generation == _generation) {
        state = ScanState(error: '扫描状态暂不可用：$error');
      }
    }
  }

  Future<void> start({String? path, bool generatePreviews = false}) async {
    final api = _api;
    final serverId = _serverId;
    if (api == null || serverId == null || state.blocked || _polling) return;
    final generation = _generation;
    _timer?.cancel();
    state = ScanState(busy: true, path: path);
    var submitted = false;
    try {
      final jobs = await api.jobQueue();
      if (generation != _generation) return;
      final existing = jobs.where((j) => j.active && j.isScan).firstOrNull;
      if (existing != null) {
        state = ScanState(job: existing);
        await _persist(serverId, existing.id);
      } else {
        await _persist(serverId, 'pending');
        if (generation != _generation) return;
        submitted = true;
        final jobId = await api.scan(
          path: path,
          generatePreviews: generatePreviews,
        );
        // Persist under the originating server even if the user switched servers.
        await _persist(serverId, jobId);
        if (generation != _generation) return;
        state = ScanState(
          job: ScanJob(id: jobId, status: 'READY', description: '扫描'),
          path: path,
        );
      }
      await check();
    } catch (error) {
      if (generation != _generation) return;
      final uncertain =
          submitted &&
          (error is! StashApiException || error.requestMayHaveSucceeded);
      state = ScanState(
        path: path,
        uncertain: uncertain,
        error: uncertain ? '提交结果待确认：$error。请检查状态后再试。' : error.toString(),
      );
      if (uncertain) {
        _schedule();
      } else {
        final preferences = await SharedPreferences.getInstance();
        await preferences.remove(_key(serverId));
      }
    }
  }

  Future<void> _persist(String serverId, String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key(serverId), value);
  }

  Future<void> check() async {
    final api = _api;
    final serverId = _serverId;
    if (api == null || serverId == null || _polling || state.busy) return;
    final generation = _generation;
    _polling = true;
    try {
      ScanJob? job;
      final previous = state.job;
      if (previous != null) job = await api.findJob(previous.id);
      if (previous == null || job == null) {
        final jobs = await api.jobQueue();
        job = jobs.where((j) => j.active && j.isScan).firstOrNull;
      }
      if (generation != _generation) return;
      if (job == null && previous != null) {
        state = ScanState(
          job: ScanJob(
            id: previous.id,
            status: 'UNKNOWN',
            description: previous.description,
          ),
          path: state.path,
          error: '服务器已无此任务记录，无法确认完成状态。请刷新列表核对，需要时可重新扫描。',
        );
        final preferences = await SharedPreferences.getInstance();
        await preferences.remove(_key(serverId));
      } else if (job == null && state.uncertain) {
        // Queue reads cannot prove a timed-out submission failed or succeeded.
        state = const ScanState(error: '未发现正在运行的扫描。若曾提交，请刷新列表核对；需要时可重新扫描。');
        final preferences = await SharedPreferences.getInstance();
        await preferences.remove(_key(serverId));
      } else {
        final finishedNow =
            job?.status == 'FINISHED' && previous?.status != 'FINISHED';
        state = ScanState(
          job: job,
          path: state.path,
          refreshError: job?.id == previous?.id ? state.refreshError : null,
        );
        if (job != null) await _persist(serverId, job.id);
        if (finishedNow) await refreshMedia();
      }
    } catch (error) {
      if (generation == _generation) {
        state = ScanState(
          job: state.job,
          path: state.path,
          uncertain: state.uncertain || state.job == null,
          refreshError: state.refreshError,
          error: '暂时无法读取扫描状态：$error。服务器任务可能仍在运行。',
        );
      }
    } finally {
      if (generation == _generation) {
        _polling = false;
        _schedule();
      }
    }
  }

  Future<void> refreshMedia() async {
    final generation = _generation;
    ref.invalidate(recentScenesProvider);
    ref.invalidate(recommendedScenesProvider);
    ref.invalidate(featuredSceneProvider);
    ref.invalidate(sceneProvider);
    ref.invalidate(tagsProvider);
    ref.invalidate(favoriteScenesProvider);
    final directories = ref.read(directoryProvider.notifier);
    await Future.wait([
      directories.refresh(),
      ref.read(libraryProvider.notifier).refresh(),
    ]);
    if (generation != _generation) return;
    final directoryError = ref.read(directoryProvider).error;
    final libraryError = ref.read(libraryProvider).hasError;
    state = ScanState(
      job: state.job,
      path: state.path,
      error: state.error,
      uncertain: state.uncertain,
      refreshError: directoryError != null || libraryError
          ? '扫描已完成，部分列表刷新失败，请重试刷新。'
          : null,
    );
  }

  void _schedule() {
    _timer?.cancel();
    if (_foreground && (state.job?.active == true || state.uncertain)) {
      _timer = Timer(const Duration(seconds: 4), () => unawaited(check()));
    }
  }
}
