import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers.dart';
import '../../shared/widgets/scene_widgets.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteScenesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: favorites.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_rounded,
          title: '收藏加载失败',
          message: error.toString(),
        ),
        data: (scenes) => scenes.isEmpty
            ? const EmptyState(
                icon: Icons.favorite_border_rounded,
                title: '还没有收藏',
                message: '点击场景封面上的心形按钮即可收藏。',
              )
            : SceneGrid(scenes: scenes),
      ),
    );
  }
}
