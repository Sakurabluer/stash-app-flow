import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/models/scene.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/scene_widgets.dart';

enum _LibraryFilter { all, unwatched, ultraHd, long }

class _SceneSort {
  const _SceneSort(this.field, this.label, this.defaultDirection);

  final String field;
  final String label;
  final String defaultDirection;
}

const _sceneSorts = <_SceneSort>[
  _SceneSort('organized', '整理状态', 'DESC'),
  _SceneSort('date', '场景日期', 'DESC'),
  _SceneSort('file_count', '文件数量', 'DESC'),
  _SceneSort('filesize', '文件大小', 'DESC'),
  _SceneSort('duration', '视频时长', 'DESC'),
  _SceneSort('framerate', '帧率', 'DESC'),
  _SceneSort('resolution', '分辨率', 'DESC'),
  _SceneSort('bitrate', '比特率', 'DESC'),
  _SceneSort('last_played_at', '最近播放时间', 'DESC'),
  _SceneSort('resume_time', '播放进度', 'DESC'),
  _SceneSort('play_duration', '累计播放时长', 'DESC'),
  _SceneSort('play_count', '播放次数', 'DESC'),
  _SceneSort('interactive', '交互式', 'DESC'),
  _SceneSort('interactive_speed', '交互速度', 'DESC'),
  _SceneSort('perceptual_similarity', '感知相似度', 'DESC'),
  _SceneSort('performer_age', '演员年龄', 'DESC'),
  _SceneSort('studio', '工作室', 'ASC'),
  _SceneSort('title', '标题', 'ASC'),
  _SceneSort('path', '文件名 / 路径', 'ASC'),
  _SceneSort('rating', '评分', 'DESC'),
  _SceneSort('file_mod_time', '文件修改时间', 'DESC'),
  _SceneSort('tag_count', '标签数量', 'DESC'),
  _SceneSort('performer_count', '演员数量', 'DESC'),
  _SceneSort('random', '随机', 'DESC'),
  _SceneSort('o_counter', 'O 计数', 'DESC'),
  _SceneSort('last_o_at', '最近 O 时间', 'DESC'),
  _SceneSort('group_scene_number', '片组场景编号', 'ASC'),
  _SceneSort('code', '场景编号', 'ASC'),
  _SceneSort('created_at', '添加时间', 'DESC'),
  _SceneSort('updated_at', '更新时间', 'DESC'),
];

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _scrollController = ScrollController();
  _LibraryFilter _filter = _LibraryFilter.all;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.extentAfter < 700) {
        ref.read(libraryProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<Scene> _filtered(List<Scene> scenes) => switch (_filter) {
    _LibraryFilter.all => scenes,
    _LibraryFilter.unwatched =>
      scenes.where((scene) => scene.playCount == 0).toList(),
    _LibraryFilter.ultraHd =>
      scenes.where((scene) => scene.qualityLabel == '4K').toList(),
    _LibraryFilter.long =>
      scenes
          .where(
            (scene) =>
                scene.durationSeconds >= const Duration(hours: 1).inSeconds,
          )
          .toList(),
  };

  String _filterLabel(_LibraryFilter filter) => switch (filter) {
    _LibraryFilter.all => '全部',
    _LibraryFilter.unwatched => '未观看',
    _LibraryFilter.ultraHd => '4K',
    _LibraryFilter.long => '长片',
  };

  _SceneSort _sortFor(String field) => _sceneSorts.firstWhere(
    (sort) => sort.field == field,
    orElse: () => const _SceneSort('created_at', '添加时间', 'DESC'),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体库', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: '搜索媒体库',
            onPressed: () => context.go('/search'),
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_rounded,
          title: '媒体库加载失败',
          message: error.toString(),
        ),
        data: (data) {
          final scenes = _filtered(data.items);
          final selectedSort = _sortFor(data.sort);
          final directionLabel = data.direction == 'ASC' ? '升序' : '降序';
          return RefreshIndicator(
            onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _LibraryToolbarDelegate(
                    child: _LibraryMenu(
                      filter: _filter,
                      sort: selectedSort,
                      direction: data.direction,
                      filterLabel: _filterLabel,
                      onFilterSelected: (filter) =>
                          setState(() => _filter = filter),
                      onSortSelected: (sort) => ref
                          .read(libraryProvider.notifier)
                          .changeSort(sort.field, sort.defaultDirection),
                      onDirectionSelected: (direction) => ref
                          .read(libraryProvider.notifier)
                          .changeSort(data.sort, direction),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(17, 0, 17, 13),
                    child: Row(
                      children: [
                        Text(
                          '${data.total} 个场景',
                          style: const TextStyle(
                            color: StashColors.muted,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            '${selectedSort.label} · $directionLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: StashColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (scenes.isEmpty)
                  const SliverFillRemaining(
                    child: EmptyState(
                      icon: Icons.filter_alt_off_outlined,
                      title: '没有匹配的场景',
                      message: '更换筛选条件后再试。',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.crossAxisExtent;
                        final columns = width >= 900
                            ? 4
                            : width >= 600
                            ? 3
                            : 2;
                        return SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
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
                    ),
                  ),
                if (data.isLoadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LibraryToolbarDelegate extends SliverPersistentHeaderDelegate {
  const _LibraryToolbarDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 66;

  @override
  double get maxExtent => 66;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(
    color: StashColors.background,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: child,
    ),
  );

  @override
  bool shouldRebuild(covariant _LibraryToolbarDelegate oldDelegate) => true;
}

class _LibraryMenu extends StatelessWidget {
  const _LibraryMenu({
    required this.filter,
    required this.sort,
    required this.direction,
    required this.filterLabel,
    required this.onFilterSelected,
    required this.onSortSelected,
    required this.onDirectionSelected,
  });

  final _LibraryFilter filter;
  final _SceneSort sort;
  final String direction;
  final String Function(_LibraryFilter) filterLabel;
  final ValueChanged<_LibraryFilter> onFilterSelected;
  final ValueChanged<_SceneSort> onSortSelected;
  final ValueChanged<String> onDirectionSelected;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    alignmentOffset: const Offset(0, 6),
    menuChildren: [
      SubmenuButton(
        menuChildren: [
          for (final value in _LibraryFilter.values)
            MenuItemButton(
              leadingIcon: Icon(
                filter == value
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
              ),
              onPressed: () => onFilterSelected(value),
              child: Text(filterLabel(value)),
            ),
        ],
        child: Text('筛选：${filterLabel(filter)}'),
      ),
      SubmenuButton(
        menuChildren: [
          for (final value in _sceneSorts)
            MenuItemButton(
              leadingIcon: Icon(
                sort.field == value.field
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
              ),
              onPressed: () => onSortSelected(value),
              child: Text(value.label),
            ),
        ],
        child: Text('排序：${sort.label}'),
      ),
      if (sort.field != 'random')
        SubmenuButton(
          menuChildren: [
            MenuItemButton(
              leadingIcon: Icon(
                direction == 'ASC'
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
              ),
              onPressed: () => onDirectionSelected('ASC'),
              child: const Text('升序'),
            ),
            MenuItemButton(
              leadingIcon: Icon(
                direction == 'DESC'
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
              ),
              onPressed: () => onDirectionSelected('DESC'),
              child: const Text('降序'),
            ),
          ],
          child: Text('顺序：${direction == 'ASC' ? '升序' : '降序'}'),
        ),
    ],
    builder: (context, controller, child) => SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.tune_rounded),
        label: Text(
          '${filterLabel(filter)} · ${sort.label}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size.fromHeight(46),
        ),
      ),
    ),
  );
}
