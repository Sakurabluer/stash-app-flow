import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/server/server_session.dart';
import '../models/scene.dart';
import '../providers.dart';

class SceneImage extends ConsumerWidget {
  const SceneImage({
    super.key,
    required this.scene,
    this.fit = BoxFit.cover,
    this.fallbackIndex = 0,
  });

  final Scene scene;
  final BoxFit fit;
  final int fallbackIndex;

  static const _fallbackColors = [
    StashColors.surfaceHigh,
    Color(0xFF26322E),
    Color(0xFF292B31),
    Color(0xFF302B2B),
  ];

  Widget _fallback() => ColoredBox(
    color: _fallbackColors[fallbackIndex % _fallbackColors.length],
    child: const Center(
      child: Icon(Icons.movie_outlined, size: 34, color: StashColors.muted),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeServerSessionProvider);
    if (scene.screenshotUrl.isEmpty || session == null) return _fallback();
    return CachedNetworkImage(
      imageUrl: scene.screenshotUrl,
      httpHeaders: {'ApiKey': session.apiKey},
      fit: fit,
      placeholder: (_, _) => const ColoredBox(
        color: StashColors.surfaceHigh,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (_, _, _) => _fallback(),
    );
  }
}

class SceneCard extends ConsumerWidget {
  const SceneCard({
    super.key,
    required this.scene,
    this.index = 0,
    this.width,
    this.showProgress = false,
  });

  final Scene scene;
  final int index;
  final double? width;
  final bool showProgress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites =
        ref.watch(favoritesProvider).asData?.value ?? const <String>{};
    final favorite = favorites.contains(scene.id);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => context.push('/scenes/${scene.id}', extra: scene),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SceneImage(scene: scene, fallbackIndex: index),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _QualityBadge(label: scene.qualityLabel),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: IconButton(
                        tooltip: favorite ? '取消收藏' : '收藏',
                        onPressed: () => ref
                            .read(favoritesProvider.notifier)
                            .toggle(scene.id),
                        icon: Icon(
                          favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: favorite ? StashColors.danger : Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0x88090B0A),
                          minimumSize: const Size.square(34),
                        ),
                      ),
                    ),
                    if (showProgress && scene.progress > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: scene.progress,
                          minHeight: 3,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              scene.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              '${scene.durationLabel} · ${scene.qualityLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: StashColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class SceneGrid extends StatelessWidget {
  const SceneGrid({super.key, required this.scenes, this.padding});

  final List<Scene> scenes;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 600
            ? 3
            : 2;
        return GridView.builder(
          padding: padding ?? const EdgeInsets.fromLTRB(14, 8, 14, 28),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 11,
            mainAxisSpacing: 19,
            mainAxisExtent: 198,
          ),
          itemCount: scenes.length,
          itemBuilder: (_, index) =>
              SceneCard(scene: scenes[index], index: index),
        );
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: StashColors.muted),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: StashColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xCC090C0A),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(
        label,
        style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800),
      ),
    ),
  );
}
