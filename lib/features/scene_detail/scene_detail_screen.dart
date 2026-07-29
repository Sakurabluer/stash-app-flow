import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/models/scene.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/scene_widgets.dart';

class SceneDetailScreen extends ConsumerWidget {
  const SceneDetailScreen({
    super.key,
    required this.sceneId,
    this.initialScene,
  });

  final String sceneId;
  final Scene? initialScene;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initialScene != null) return _SceneDetail(scene: initialScene!);
    return ref
        .watch(sceneProvider(sceneId))
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              icon: Icons.error_outline_rounded,
              title: '场景加载失败',
              message: error.toString(),
            ),
          ),
          data: (scene) => scene == null
              ? const Scaffold(
                  body: EmptyState(
                    icon: Icons.hide_source_rounded,
                    title: '场景不存在',
                    message: '该场景可能已从服务器删除。',
                  ),
                )
              : _SceneDetail(scene: scene),
        );
  }
}

class _SceneDetail extends ConsumerWidget {
  const _SceneDetail({required this.scene});

  final Scene scene;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites =
        ref.watch(favoritesProvider).asData?.value ?? const <String>{};
    final isFavorite = favorites.contains(scene.id);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 330,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  SceneImage(scene: scene),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x33101214),
                          Colors.transparent,
                          StashColors.background,
                        ],
                        stops: [0, 0.55, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 36),
            sliver: SliverList.list(
              children: [
                Text(
                  scene.title,
                  style: const TextStyle(
                    fontSize: 27,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '${scene.date ?? '日期未知'} · ${scene.durationLabel} · ${scene.qualityLabel}',
                  style: const TextStyle(
                    color: StashColors.muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: scene.streamUrl.isEmpty
                      ? null
                      : () => context.push('/player/${scene.id}', extra: scene),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('播放'),
                ),
                const SizedBox(height: 14),
                Center(
                  child: IconButton.filledTonal(
                    tooltip: isFavorite ? '取消收藏' : '收藏',
                    onPressed: () =>
                        ref.read(favoritesProvider.notifier).toggle(scene.id),
                    icon: Icon(
                      isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: isFavorite ? StashColors.danger : null,
                    ),
                  ),
                ),
                if (scene.details.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    scene.details,
                    style: const TextStyle(
                      color: Color(0xFFB8BEBA),
                      fontSize: 13,
                      height: 1.65,
                    ),
                  ),
                ],
                if (scene.tags.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final tag in scene.tags)
                        ActionChip(
                          label: Text(tag.name),
                          tooltip: '查看“${tag.name}”标签内容',
                          onPressed: () => context.push(
                            Uri(
                              path: '/tags/${tag.id}',
                              queryParameters: {'name': tag.name},
                            ).toString(),
                          ),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: StashColors.surfaceHigh,
                          side: BorderSide.none,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 26),
                const Divider(),
                const SizedBox(height: 10),
                _InfoRow(
                  label: '分辨率',
                  value: '${scene.width} × ${scene.height}',
                ),
                _InfoRow(label: '文件大小', value: scene.sizeLabel),
                _InfoRow(label: '播放次数', value: '${scene.playCount}'),
                if (scene.filePath.isNotEmpty)
                  _InfoRow(label: '文件路径', value: scene.filePath),
                if (scene.rating100 != null)
                  _InfoRow(
                    label: '评分',
                    value: (scene.rating100! / 20).toStringAsFixed(1),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Text(label, style: const TextStyle(color: StashColors.muted)),
        const SizedBox(width: 20),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
