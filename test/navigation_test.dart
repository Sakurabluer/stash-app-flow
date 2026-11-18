import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stash_mobile/app/app.dart';
import 'package:stash_mobile/core/server/server_session.dart';
import 'package:stash_mobile/features/directories/directory_index.dart';
import 'package:stash_mobile/features/directories/directory_images.dart';
import 'package:stash_mobile/features/directories/directory_providers.dart';
import 'package:stash_mobile/features/scanning/scan_provider.dart';
import 'package:stash_mobile/shared/models/scene.dart';
import 'package:stash_mobile/shared/providers.dart';

class _Server extends ServerSessionController {
  @override
  Future<ServerConnectionState> build() async => const ServerConnectionState(
    servers: [],
    activeSession: ServerSession(
      server: SavedServer(
        id: 'test',
        name: 'test',
        baseUrl: 'http://test',
        version: '0.31.1',
        sceneCount: 0,
        tagCount: 0,
      ),
      apiKey: 'test',
    ),
  );
}

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

class _Scan extends ScanController {
  @override
  ScanState build() => const ScanState();
}

class _Library extends LibraryController {
  @override
  Future<LibraryState> build() async => const LibraryState(
    items: [],
    total: 0,
    page: 1,
    isLoadingMore: false,
    sort: 'created_at',
    direction: 'DESC',
  );
}

class _Images extends DirectoryImagesController {
  @override
  Future<DirectoryImagesState> build(DirectoryImageQuery arg) async =>
      const DirectoryImagesState(items: [], total: 0, offset: 0);
}

void main() {
  testWidgets(
    'search returns to its source and directory aggregates retain the All tab',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverSessionProvider.overrideWith(_Server.new),
            scanProvider.overrideWith(_Scan.new),
            directoryProvider.overrideWith(_Directory.new),
            directoryImagesProvider.overrideWith(_Images.new),
            directoryImageCountProvider.overrideWith((ref, arg) async => 0),
            folderImageCountsProvider.overrideWith(
              (ref, arg) async => {'/pictures': 0},
            ),
            recentScenesProvider.overrideWith(
              (ref) async => const ScenePage(items: [], total: 0),
            ),
            recommendedScenesProvider.overrideWith(
              (ref) async => const ScenePage(items: [], total: 0),
            ),
            featuredSceneProvider.overrideWith((ref) async => null),
            libraryProvider.overrideWith(_Library.new),
          ],
          child: const StashApp(),
        ),
      );
      await tester.pumpAndSettle();
      final nav = find.byType(NavigationBar);
      expect(find.descendant(of: nav, matching: find.text('搜索')), findsNothing);
      expect(
        find.descendant(of: nav, matching: find.text('全部')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('搜索视频'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('STASH FLOW'), findsOneWidget);
      await tester.tap(find.descendant(of: nav, matching: find.text('媒体库')));
      await tester.pumpAndSettle();
      expect(find.text('视频'), findsNothing); // No old video/directory switch.
      await tester.tap(find.byTooltip('搜索媒体库'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byTooltip('搜索媒体库'), findsOneWidget);
      await tester.tap(find.descendant(of: nav, matching: find.text('全部')));
      await tester.pumpAndSettle();
      expect(find.text('按目录浏览视频和图片'), findsOneWidget);
      await tester.tap(find.text('/pictures'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部视频 0'));
      await tester.pumpAndSettle();
      expect(find.text('pictures · 内容汇总'), findsOneWidget);
      expect(find.text('0 部视频（含子目录）'), findsOneWidget);
      expect(tester.widget<NavigationBar>(nav).selectedIndex, 3);
      expect(tester.takeException(), isNull);
    },
  );
}
