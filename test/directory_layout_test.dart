import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:stash_mobile/app/theme.dart';
import 'package:stash_mobile/features/directories/directory_images.dart';
import 'package:stash_mobile/features/directories/directory_index.dart';
import 'package:stash_mobile/features/directories/directory_providers.dart';
import 'package:stash_mobile/features/directories/directory_screen.dart';
import 'package:stash_mobile/features/scanning/scan_provider.dart';

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

class _Images extends DirectoryImagesController {
  @override
  Future<DirectoryImagesState> build(DirectoryImageQuery arg) async =>
      const DirectoryImagesState(items: [], total: 91065, offset: 91065);
}

void main() {
  for (final width in [320.0, 360.0, 412.0]) {
    for (final recursive in [false, true]) {
      testWidgets(
        'picture-only directory and aggregate fit ${width}px, recursive=$recursive',
        (tester) async {
          tester.view.reset();
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final router = GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => DirectoryScreen(
                  path: '/pictures',
                  recursive: recursive,
                  images: recursive,
                ),
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                directoryProvider.overrideWith(_Directory.new),
                scanProvider.overrideWith(_Scan.new),
                directoryImageCountProvider.overrideWith(
                  (ref, arg) async => 91065,
                ),
                directoryImagesProvider.overrideWith(_Images.new),
              ],
              child: MaterialApp.router(
                theme: buildStashTheme(),
                routerConfig: router,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('图片 91065'), findsOneWidget);
          expect(find.textContaining('91065 张图片'), findsOneWidget);
          if (!recursive) {
            expect(find.text('全部视频 0'), findsOneWidget);
            expect(find.text('全部图片 91065'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
