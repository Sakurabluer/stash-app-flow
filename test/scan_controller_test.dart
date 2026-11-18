import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stash_mobile/core/network/stash_api_client.dart';
import 'package:stash_mobile/core/server/server_session.dart';
import 'package:stash_mobile/features/scanning/scan_provider.dart';
import 'package:stash_mobile/shared/providers.dart';

class _Api extends StashApiClient {
  _Api() : super(baseUrl: 'http://test', apiKey: 'test');
  int submissions = 0;
  List<ScanJob> queue = [];
  bool disconnected = false;
  Completer<String>? pendingSubmission;

  @override
  Future<List<ScanJob>> jobQueue() async {
    if (disconnected) throw const StashApiException('offline');
    return queue;
  }

  @override
  Future<String> scan({String? path, bool generatePreviews = false}) async {
    submissions++;
    return pendingSubmission == null ? '123' : pendingSubmission!.future;
  }

  @override
  Future<ScanJob?> findJob(String id) async {
    if (disconnected) throw const StashApiException('offline');
    return ScanJob(id: id, status: 'RUNNING', description: 'Scanning');
  }
}

ServerSession _session(String id) => ServerSession(
  server: SavedServer(
    id: id,
    name: id,
    baseUrl: 'http://$id',
    version: '0.31.1',
    sceneCount: 0,
    tagCount: 0,
  ),
  apiKey: 'test',
);

Future<void> _flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Api api;
  late ProviderContainer container;
  final session = StateProvider<ServerSession?>((ref) => _session('a'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = _Api();
    container = ProviderContainer(
      overrides: [
        activeServerSessionProvider.overrideWith((ref) => ref.watch(session)),
        stashApiProvider.overrideWith((ref) {
          ref.watch(session);
          return api;
        }),
      ],
    );
    container.read(scanProvider);
  });
  tearDown(() => container.dispose());

  test(
    'rapid duplicate taps submit one job, and persist its identity',
    () async {
      await _flush();
      final controller = container.read(scanProvider.notifier);
      await Future.wait([controller.start(), controller.start()]);
      expect(api.submissions, 1);
      expect(container.read(scanProvider).job!.status, 'RUNNING');
      expect(
        (await SharedPreferences.getInstance()).getString('scan_job_v1_a'),
        '123',
      );
    },
  );

  test(
    'adopts an existing server scan instead of submitting another',
    () async {
      await _flush();
      api.queue = [
        const ScanJob(id: 'existing', status: 'READY', description: 'Scanning'),
      ];
      await container.read(scanProvider.notifier).start();
      expect(api.submissions, 0);
      expect(container.read(scanProvider).job!.id, 'existing');
    },
  );

  test(
    'connection loss keeps the server job and does not mark it failed',
    () async {
      await _flush();
      await container.read(scanProvider.notifier).start();
      api.disconnected = true;
      await container.read(scanProvider.notifier).check();
      final state = container.read(scanProvider);
      expect(state.job!.status, 'RUNNING');
      expect(state.error, contains('仍在运行'));
      expect(state.blocked, isTrue);
    },
  );

  test('late submission response stays with its original server', () async {
    await _flush();
    api.pendingSubmission = Completer<String>();
    final start = container.read(scanProvider.notifier).start();
    await _flush();
    container.read(session.notifier).state = _session('b');
    container.read(scanProvider);
    await _flush();
    api.pendingSubmission!.complete('from-a');
    await start;
    await _flush();
    expect(container.read(scanProvider).job, isNull);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('scan_job_v1_a'), 'from-a');
    expect(preferences.getString('scan_job_v1_b'), isNull);
  });
}
