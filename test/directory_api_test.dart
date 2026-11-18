import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stash_mobile/core/network/stash_api_client.dart';

void main() {
  late HttpServer server;
  late StashApiClient api;
  late List<Map<String, dynamic>> mutations;

  setUp(() async {
    mutations = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = StashApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
      apiKey: 'test-only',
    );
    server.listen((request) async {
      expect(request.headers.value('ApiKey'), 'test-only');
      final body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      final query = body['query'] as String;
      Map<String, dynamic> data;
      if (query.contains('configuration {')) {
        data = {
          'configuration': {
            'general': {
              'stashes': [
                {'path': '/media/A', 'excludeVideo': false},
                {
                  'path': '/pictures',
                  'excludeVideo': true,
                  'excludeImage': true,
                },
                {
                  'path': '/images-only',
                  'excludeVideo': true,
                  'excludeImage': false,
                },
              ],
            },
            'defaults': {
              'scan': {'scanGenerateCovers': false},
            },
          },
        };
      } else if (query.contains('metadataScan')) {
        mutations.add(
          Map<String, dynamic>.from((body['variables'] as Map)['input'] as Map),
        );
        data = {'metadataScan': 'job-123'};
      } else if (query.contains('DirectoryScenes')) {
        data = {
          'findScenes': {
            'scenes': [
              {'id': '2', 'files': []},
              {'id': '1', 'files': []},
            ],
          },
        };
      } else if (query.contains('DirectoryIndex')) {
        expect(query, isNot(contains('screenshot')));
        data = {
          'findScenes': {
            'count': 1,
            'scenes': [
              {
                'id': '1',
                'created_at': '',
                'files': [
                  {'path': '/media/A/x.mp4'},
                ],
              },
            ],
          },
        };
      } else {
        data = {
          'findJob': {
            'id': 'job-123',
            'status': 'FAILED',
            'description': 'Scanning',
            'error': 'Disk unavailable',
            'progress': .4,
          },
        };
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': data}));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test(
    'scan is scoped to live configured roots and defaults to lightweight discovery',
    () async {
      expect(await api.scan(), 'job-123');
      expect(mutations.single['paths'], ['/media/A', '/images-only']);
      expect(mutations.single['rescan'], isFalse);
      expect(mutations.single['scanGenerateCovers'], isFalse);
      expect(mutations.single['scanGeneratePreviews'], isFalse);
      await api.scan(path: '/media/A/Season 1', generatePreviews: true);
      expect(mutations.last['paths'], ['/media/A/Season 1']);
      expect(mutations.last['scanGeneratePreviews'], isTrue);
    },
  );

  test('similar names and traversal cannot submit a scan mutation', () async {
    for (final path in [
      '/media/AB',
      '/media/A/../private',
      '/private',
      'relative',
    ]) {
      await expectLater(
        api.scan(path: path),
        throwsA(isA<StashApiException>()),
      );
    }
    expect(mutations, isEmpty);
  });

  test(
    'detail batches preserve the index order and tolerate deleted scene ids',
    () async {
      final scenes = await api.scenesByIds(['1', 'deleted', '2']);
      expect(scenes.map((s) => s.id), ['1', '2']);
    },
  );

  test(
    'lightweight index rows and failed jobs preserve useful fields',
    () async {
      final page = await api.directoryPage(1);
      expect(page.total, 1);
      expect(page.videos.single.paths, ['/media/A/x.mp4']);
      final job = await api.findJob('job-123');
      expect(job!.statusLabel, '扫描失败');
      expect(job.error, 'Disk unavailable');
      expect(job.active, isFalse);
    },
  );
}
