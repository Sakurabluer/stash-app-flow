import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/server/server_session.dart';
import '../features/favorites/favorites_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/onboarding/connect_screen.dart';
import '../features/player/player_screen.dart';
import '../features/scene_detail/scene_detail_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/tags/tag_browsing_screens.dart';
import '../shared/models/scene.dart';
import 'theme.dart';

class StashApp extends ConsumerWidget {
  const StashApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Stash Flow',
      debugShowCheckedModeBanner: false,
      theme: buildStashTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final connection = ref.watch(serverSessionProvider);
  final router = GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final loading = connection.isLoading;
      final connected = connection.asData?.value.activeSession != null;
      final location = state.matchedLocation;
      if (loading) return location == '/loading' ? null : '/loading';
      if (!connected) return location == '/connect' ? null : '/connect';
      if (location == '/connect' || location == '/loading') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/loading', builder: (_, _) => const _LoadingScreen()),
      GoRoute(path: '/connect', builder: (_, _) => const ConnectScreen()),
      GoRoute(
        path: '/servers/add',
        builder: (_, _) => const ConnectScreen(isAdding: true),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (_, _) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/favorites',
                builder: (_, _) => const FavoritesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/scenes/:id',
        builder: (_, state) => SceneDetailScreen(
          sceneId: state.pathParameters['id']!,
          initialScene: state.extra as Scene?,
        ),
      ),
      GoRoute(
        path: '/player/:id',
        builder: (_, state) => PlayerScreen(
          sceneId: state.pathParameters['id']!,
          initialScene: state.extra as Scene?,
        ),
      ),
      GoRoute(
        path: '/scene-categories',
        builder: (_, _) => const TagListScreen(sceneCategoriesOnly: true),
      ),
      GoRoute(
        path: '/tags',
        builder: (_, _) => const TagListScreen(sceneCategoriesOnly: false),
      ),
      GoRoute(
        path: '/tags/:id',
        builder: (_, state) {
          final arguments = state.extra as TagBrowseArguments?;
          return TagMediaScreen(
            tagId: state.pathParameters['id']!,
            tagName:
                arguments?.tag.name ??
                state.uri.queryParameters['name'] ??
                '标签内容',
            scenesOnly: arguments?.scenesOnly ?? false,
          );
        },
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
