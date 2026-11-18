import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stash_mobile/core/network/stash_api_client.dart';
import 'package:stash_mobile/features/directories/directory_images.dart';
import 'package:stash_mobile/features/directories/directory_index.dart';
import 'package:stash_mobile/features/directories/directory_providers.dart';
import 'package:stash_mobile/shared/providers.dart';

class _Directory extends DirectoryController {
  @override
  DirectoryState build() => DirectoryState(
    loading: false,
    index: DirectoryIndex(
      videos: {},
      scanRoots: ['/pictures'],
      updatedAt: DateTime.utc(2026),
      folders: const [ServerFolder(id: '10', path: '/pictures')],
    ),
  );
}

void main() {
  test(
    'scope uses native folder depth and excludes hidden files within the same file filter',
    () {
      final state = _Directory().build();
      expect(imageScopeFilter(state, (path: '/pictures', recursive: false)), {
        'files_filter': {
          'parent_folder': {
            'value': ['10'],
            'modifier': 'INCLUDES',
            'depth': 0,
          },
        },
      });
      final recursive = imageScopeFilter(
        state.copyWith(hidden: {'/pictures/private'}),
        (path: '/pictures', recursive: true),
      );
      final files = recursive['files_filter'] as Map;
      expect((files['parent_folder'] as Map)['depth'], -1);
      expect((files['AND'] as Map)['NOT'], contains('path'));
      expect(recursive, isNot(contains('NOT')));
    },
  );

  test(
    'union image details, batched counts and natural sorting work across pages',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      server.listen((request) async {
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        requests.add(body);
        final query = body['query'] as String;
        final variables = body['variables'] as Map;
        Map<String, dynamic> data;
        if (query.contains('DirectoryImageCounts')) {
          data = {
            'scope0': {'count': 32},
            'scope1': {'count': 30},
          };
        } else if (query.contains('DirectoryImageIndex')) {
          data = {
            'findImages': {
              'count': 32,
              'images': [
                for (var i = 32; i >= 1; i--)
                  {
                    'id': '$i',
                    'created_at': '',
                    'visual_files': [
                      {'path': '/pictures/第$i张.jpg'},
                    ],
                  },
              ],
            },
          };
        } else {
          expect(query, contains('... on ImageFile'));
          expect(query, contains('... on VideoFile'));
          final ids = variables['ids'] as List? ?? ['1', '2'];
          data = {
            'findImages': {
              'count': 32,
              'images': [
                for (final id in ids.reversed)
                  {
                    'id': id,
                    'title': '',
                    'visual_files': [
                      {
                        'path': '/pictures/第$id张.jpg',
                        'width': 640,
                        'height': 480,
                      },
                    ],
                  },
              ],
            },
          };
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'data': data}));
        await request.response.close();
      });
      final api = StashApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: 'test',
      );
      final container = ProviderContainer(
        overrides: [
          stashApiProvider.overrideWithValue(api),
          directoryProvider.overrideWith(_Directory.new),
        ],
      );
      const query = (
        path: '/pictures',
        recursive: true,
        byDate: false,
        descending: false,
      );
      final subscription = container.listen(
        directoryImagesProvider(query),
        (_, _) {},
      );
      try {
        final counts = await api.imageCounts({'all': {}, 'direct': {}});
        expect(counts, {'all': 32, 'direct': 30});
        final first = await container.read(
          directoryImagesProvider(query).future,
        );
        expect(
          first.items.map((i) => i.id),
          List.generate(30, (i) => '${i + 1}'),
        );
        expect(first.items.first.title, '第1张.jpg');
        expect(first.total, 32);
        await container
            .read(directoryImagesProvider(query).notifier)
            .loadMore();
        final second = container
            .read(directoryImagesProvider(query))
            .requireValue;
        expect(
          second.items.map((i) => i.id),
          List.generate(32, (i) => '${i + 1}'),
        );
        expect(second.hasMore, false);
        expect(
          requests
              .where(
                (r) => (r['query'] as String).contains('DirectoryImageIndex'),
              )
              .length,
          1,
        );
      } finally {
        subscription.close();
        container.dispose();
        await server.close(force: true);
      }
    },
  );
}
