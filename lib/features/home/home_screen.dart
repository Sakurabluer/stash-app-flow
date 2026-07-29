import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/models/scene.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/scene_widgets.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentScenesProvider);
    final recommended = ref.watch(recommendedScenesProvider);
    final featured = ref.watch(featuredSceneProvider);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.refresh(recentScenesProvider.future),
            ref.refresh(recommendedScenesProvider.future),
            ref.refresh(featuredSceneProvider.future),
          ]);
        },
        child: recent.when(
          loading: () => const CustomScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
          error: (error, _) => CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                child: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: '无法加载首页',
                  message: error.toString(),
                ),
              ),
            ],
          ),
          data: (page) => _HomeContent(
            scenes: page.items,
            recommendedScenes:
                recommended.asData?.value.items ?? const <Scene>[],
            featuredScene: featured.asData?.value,
          ),
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.scenes,
    required this.recommendedScenes,
    required this.featuredScene,
  });

  final List<Scene> scenes;
  final List<Scene> recommendedScenes;
  final Scene? featuredScene;

  @override
  Widget build(BuildContext context) {
    if (scenes.isEmpty) {
      return const CustomScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: EmptyState(
              icon: Icons.video_library_outlined,
              title: '媒体库为空',
              message: '在 Stash Server 中扫描媒体后，下拉刷新首页。',
            ),
          ),
        ],
      );
    }
    final hero = featuredScene ?? scenes.first;
    final continuing = scenes
        .where((scene) => scene.progress > 0)
        .take(10)
        .toList();
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _Hero(scene: hero)),
        if (continuing.isNotEmpty)
          SliverToBoxAdapter(
            child: _MediaRail(
              title: '继续观看',
              scenes: continuing,
              showProgress: true,
            ),
          ),
        SliverToBoxAdapter(
          child: _MediaRail(title: '最近添加', scenes: scenes.take(10).toList()),
        ),
        if (recommendedScenes.isNotEmpty)
          SliverToBoxAdapter(
            child: _MediaRail(title: '为你推荐', scenes: recommendedScenes),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.scene});

  final Scene scene;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 500,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SceneImage(scene: scene),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x44101214),
                  Color(0x11101214),
                  StashColors.background,
                ],
                stops: [0, 0.38, 0.95],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 13, 14, 0),
              child: Align(
                alignment: Alignment.topLeft,
                child: Row(
                  children: [
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        color: StashColors.accent,
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                      child: SizedBox.square(
                        dimension: 31,
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: Color(0xFF10200E),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    const Text(
                      'STASH FLOW',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    IconButton.filledTonal(
                      tooltip: '搜索',
                      onPressed: () => context.go('/search'),
                      icon: const Icon(Icons.search_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 31,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '随机推荐',
                  style: TextStyle(
                    color: StashColors.accentBright,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  scene.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 32,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '${scene.durationLabel}  ·  ${scene.qualityLabel}  ·  ${scene.playCount} 次播放',
                  style: const TextStyle(
                    color: Color(0xFFD2D7D4),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () =>
                          context.push('/player/${scene.id}', extra: scene),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF7F8F6),
                        foregroundColor: const Color(0xFF131614),
                        minimumSize: const Size(116, 43),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('播放'),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      tooltip: '查看详情',
                      onPressed: () =>
                          context.push('/scenes/${scene.id}', extra: scene),
                      icon: const Icon(Icons.info_outline_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaRail extends StatelessWidget {
  const _MediaRail({
    required this.title,
    required this.scenes,
    this.showProgress = false,
  });

  final String title;
  final List<Scene> scenes;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/library'),
                  child: const Text('查看全部'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 198,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              scrollDirection: Axis.horizontal,
              itemCount: scenes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 11),
              itemBuilder: (_, index) => SceneCard(
                scene: scenes[index],
                index: index,
                width: 230,
                showProgress: showProgress,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
