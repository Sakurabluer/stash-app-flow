import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/server/server_session.dart';
import '../../shared/models/scene.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/image_widgets.dart';
import '../../shared/widgets/scene_widgets.dart';
import '../scanning/scan_provider.dart';
import '../scanning/scan_widgets.dart';
import 'directory_image_viewer.dart';
import 'directory_images.dart';
import 'directory_index.dart';
import 'directory_providers.dart';

String directoryLocation(String path, {String? sceneId}) => Uri(
  path: '/all/directory',
  queryParameters: {'path': path, 'scene': ?sceneId},
).toString();

String directoryContentsLocation(String path, {bool images = false}) => Uri(
  path: '/all/contents',
  queryParameters: {'path': path, 'type': images ? 'images' : 'videos'},
).toString();

Future<void> showDirectoryPreferences(
  BuildContext context,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (context) => Consumer(
    builder: (context, ref, _) {
      final state = ref.watch(directoryProvider);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .75,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('目录展示设置'),
                subtitle: Text('常用和隐藏设置仅保存在本 App'),
              ),
              const ListTile(title: Text('常用目录')),
              if (state.pinned.isEmpty)
                const ListTile(subtitle: Text('可通过目录菜单添加常用目录')),
              for (final path in state.pinned)
                ListTile(
                  title: Text(state.index?.directory(path)?.path ?? path),
                  trailing: IconButton(
                    tooltip: '取消常用',
                    icon: const Icon(Icons.star),
                    onPressed: () =>
                        ref.read(directoryProvider.notifier).togglePinned(path),
                  ),
                ),
              const ListTile(title: Text('已隐藏目录')),
              if (state.hidden.isEmpty)
                const ListTile(subtitle: Text('没有隐藏目录')),
              for (final path in state.hidden)
                ListTile(
                  title: Text(state.index?.directory(path)?.path ?? path),
                  trailing: TextButton(
                    onPressed: () =>
                        ref.read(directoryProvider.notifier).toggleHidden(path),
                    child: const Text('恢复显示'),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  ),
);

class DirectoryScreen extends ConsumerWidget {
  const DirectoryScreen({
    super.key,
    this.path,
    this.sceneId,
    this.recursive = false,
    this.images = false,
  });
  final String? path;
  final String? sceneId;
  final bool recursive;
  final bool images;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(directoryProvider);
    final scan = ref.watch(scanProvider);
    final current = path;
    final canScan =
        current == null ||
        (validScanPath(current) &&
            state.index?.directory(current)?.archive != true &&
            (state.index?.scanRoots.any((root) => pathWithin(current, root)) ??
                false));
    final hidden = current != null && state.hidden.contains(pathKey(current));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          current == null
              ? '全部'
              : '${pathName(current)}${recursive ? ' · 内容汇总' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (action) {
              if (action == 'scan') showScanDialog(context, ref, path: current);
              if (action == 'refresh') {
                ref.read(directoryProvider.notifier).refresh();
              }
              if (action == 'preferences') showDirectoryPreferences(context);
              if (current != null && action == 'pin') {
                ref.read(directoryProvider.notifier).togglePinned(current);
              }
              if (current != null && action == 'hide') {
                ref.read(directoryProvider.notifier).toggleHidden(current);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'scan',
                enabled: canScan && !scan.blocked,
                child: Text(current == null ? '扫描媒体库' : '扫描此目录'),
              ),
              PopupMenuItem(
                value: 'refresh',
                enabled: !state.loading,
                child: Text(current == null ? '刷新目录' : '刷新内容和目录'),
              ),
              if (current != null) ...[
                PopupMenuItem(
                  value: 'pin',
                  child: Text(
                    state.pinned.contains(pathKey(current))
                        ? '取消常用目录'
                        : '添加到常用目录',
                  ),
                ),
                PopupMenuItem(
                  value: 'hide',
                  child: Text(hidden ? '恢复显示此目录' : '隐藏此目录'),
                ),
              ],
              const PopupMenuItem(value: 'preferences', child: Text('目录展示设置')),
            ],
          ),
        ],
      ),
      body: DirectoryBrowser(
        key: ValueKey(
          '${ref.watch(activeServerSessionProvider)?.id}|$path|$recursive|$images|$sceneId',
        ),
        path: path,
        sceneId: sceneId,
        recursive: recursive,
        initialImages: images,
      ),
    );
  }
}

class DirectoryBrowser extends ConsumerStatefulWidget {
  const DirectoryBrowser({
    super.key,
    this.path,
    this.sceneId,
    this.recursive = false,
    this.initialImages = false,
  });
  final String? path;
  final String? sceneId;
  final bool recursive;
  final bool initialImages;
  @override
  ConsumerState<DirectoryBrowser> createState() => _DirectoryBrowserState();
}

class _DirectoryBrowserState extends ConsumerState<DirectoryBrowser> {
  final _scroll = ScrollController();
  late bool _images;
  bool _byDate = false;
  bool _descending = false;
  bool _kindInitialized = false;
  DirectoryIndex? _index;
  String _hiddenKey = '';
  List<String> _ids = [];
  List<Scene> _scenes = [];
  bool _loading = false;
  bool _retryPrevious = false;
  String? _error;
  int _start = 0;
  int _end = 0;
  int _request = 0;

  DirectoryImageQuery get _imageQuery => (
    path: widget.path!,
    recursive: widget.recursive,
    byDate: _byDate,
    descending: _descending,
  );
  DirectoryScope get _scope =>
      (path: widget.path!, recursive: widget.recursive);

  @override
  void initState() {
    super.initState();
    _images = widget.initialImages;
    if (_images) {
      _byDate = true;
      _descending = true;
    }
    _scroll.addListener(() {
      if (!_scroll.hasClients || _scroll.position.extentAfter >= 650) return;
      if (_images && widget.path != null) {
        final data = ref
            .read(directoryImagesProvider(_imageQuery))
            .asData
            ?.value;
        if (data != null && data.error == null) {
          ref.read(directoryImagesProvider(_imageQuery).notifier).loadMore();
        }
      } else if (_error == null) {
        _loadVideos();
      }
    });
  }

  @override
  void dispose() {
    _request++;
    _scroll.dispose();
    super.dispose();
  }

  void _resetVideos(DirectoryState state, {bool focus = false}) {
    _request++;
    _ids = widget.path == null || state.index == null
        ? []
        : state.index!.sceneIds(
            widget.path!,
            recursive: widget.recursive,
            byDate: _byDate,
            descending: _descending,
            hidden: state.hidden,
          );
    final position = focus && widget.sceneId != null
        ? _ids.indexOf(widget.sceneId!)
        : -1;
    _start = position < 0 ? 0 : position;
    _end = _start;
    _scenes = [];
    _loading = false;
    _error = null;
    if (!_images) Future.microtask(_loadVideos);
  }

  Future<void> _loadVideos({bool previous = false}) async {
    if (!mounted ||
        _loading ||
        (previous ? _start == 0 : _end >= _ids.length)) {
      return;
    }
    final api = ref.read(stashApiProvider);
    if (api == null) return;
    final request = _request;
    final begin = previous ? (_start - 30).clamp(0, _start) : _end;
    final end = previous ? _start : (_end + 30).clamp(0, _ids.length);
    setState(() {
      _loading = true;
      _error = null;
      _retryPrevious = previous;
    });
    try {
      final items = await api.scenesByIds(_ids.sublist(begin, end));
      if (!mounted || request != _request) return;
      setState(() {
        if (previous) {
          _start = begin;
          _scenes = [...items, ..._scenes];
        } else {
          _end = end;
          _scenes = [..._scenes, ...items];
        }
        _loading = false;
      });
    } catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  void _changeKind(bool images) {
    setState(() {
      _images = images;
      _kindInitialized = true;
      _byDate = images;
      _descending = images;
      _resetVideos(ref.read(directoryProvider));
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _changeSort(String action) {
    setState(() {
      if (action == 'direction') {
        _descending = !_descending;
      } else {
        _byDate = action == 'date';
        _descending = _byDate;
      }
      _resetVideos(ref.read(directoryProvider));
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _breadcrumbs(DirectoryIndex index) {
    final path = widget.path!;
    final ancestors = <String>[path];
    var parent = parentPath(path);
    while (parent.isNotEmpty) {
      ancestors.insert(0, parent);
      parent = parentPath(parent);
    }
    final root = ancestors.indexWhere((p) => index.roots.contains(pathKey(p)));
    final visible = root >= 0 ? ancestors.sublist(root) : ancestors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          TextButton(
            onPressed: () => context.go('/all'),
            child: const Text('全部'),
          ),
          for (final p in visible) ...[
            const Icon(Icons.chevron_right, size: 15),
            TextButton(
              onPressed: pathKey(p) == pathKey(path) && !widget.recursive
                  ? null
                  : () => context.push(directoryLocation(p)),
              child: Text(pathName(p)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scopeHeader(DirectoryState state) {
    final imageCount = ref.watch(directoryImageCountProvider(_scope));
    final allCount = widget.recursive
        ? imageCount
        : ref.watch(
            directoryImageCountProvider((path: widget.path!, recursive: true)),
          );
    final index = state.index!;
    final videos = index.sceneCount(
      widget.path!,
      recursive: widget.recursive,
      hidden: state.hidden,
    );
    final allVideos = index.sceneCount(
      widget.path!,
      recursive: true,
      hidden: state.hidden,
    );
    return ColoredBox(
      color: StashColors.background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 38, child: _breadcrumbs(index)),
            if (!widget.recursive) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          context.push(directoryContentsLocation(widget.path!)),
                      child: Text('全部视频 $allVideos', maxLines: 1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.push(
                        directoryContentsLocation(widget.path!, images: true),
                      ),
                      child: Text(
                        '全部图片 ${allCount.asData?.value ?? '…'}',
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const Text(
                '包含当前目录及所有子目录',
                style: TextStyle(fontSize: 11, color: StashColors.muted),
              ),
            ] else
              const Text(
                '范围：当前目录及所有子目录',
                style: TextStyle(fontSize: 12, color: StashColors.muted),
              ),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: ChoiceChip(
                          label: FittedBox(child: Text('视频 $videos')),
                          selected: !_images,
                          onSelected: (_) => _changeKind(false),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: ChoiceChip(
                          label: FittedBox(
                            child: Text(
                              '图片 ${imageCount.hasError ? '重试' : imageCount.asData?.value ?? '…'}',
                            ),
                          ),
                          selected: _images,
                          onSelected: (_) {
                            if (imageCount.hasError) {
                              ref.invalidate(
                                directoryImageCountProvider(_scope),
                              );
                            }
                            _changeKind(true);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '排序',
                  onSelected: _changeSort,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'name',
                      child: Text('文件名（自然排序）'),
                    ),
                    const PopupMenuItem(value: 'date', child: Text('添加时间')),
                    PopupMenuItem(
                      value: 'direction',
                      child: Text(_descending ? '切换为升序' : '切换为降序'),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    child: MediaQuery.sizeOf(context).width < 380
                        ? const Icon(Icons.sort, size: 22)
                        : Text(
                            '${_byDate ? '添加时间' : '文件名'} ${_descending ? '↓' : '↑'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _source(Iterable<String> files, DirectoryState state) {
    final matching =
        files.where((p) => fileInScope(p, _scope, state.hidden)).toList()
          ..sort(naturalCompare);
    return matching.firstOrNull;
  }

  Widget _sourceButton(String? file) {
    if (file == null) return const SizedBox(height: 30);
    final parent = parentPath(file);
    final base = serverPath(widget.path!);
    final relative = pathWithin(parent, base)
        ? serverPath(
            parent,
          ).substring(base.length).replaceFirst(RegExp(r'^/'), '')
        : parent;
    return SizedBox(
      height: 32,
      child: TextButton.icon(
        onPressed: () => context.push(directoryLocation(parent)),
        icon: const Icon(Icons.folder_open, size: 14),
        label: Text(
          relative.isEmpty ? '当前目录' : relative,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }

  List<Widget> _videoSlivers(DirectoryState state) => [
    SliverToBoxAdapter(
      child: ListTile(
        title: Text('${_ids.length} 部视频（${widget.recursive ? '含子目录' : '本层'}）'),
        subtitle: Text(
          _start > 0 ? '已定位当前视频，可加载前面的影片' : '已加载 ${_scenes.length} 部',
        ),
      ),
    ),
    if (_start > 0)
      SliverToBoxAdapter(
        child: TextButton(
          onPressed: _loading ? null : () => _loadVideos(previous: true),
          child: const Text('加载前 30 部'),
        ),
      ),
    if (_ids.isEmpty)
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('当前范围没有视频。可选择图片，或查看全部子目录内容。'),
        ),
      ),
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      sliver: SliverLayoutBuilder(
        builder: (_, constraints) {
          final columns = _columns(constraints.crossAxisExtent);
          final width =
              (constraints.crossAxisExtent - (columns - 1) * 11) / columns - 10;
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: width / 1.6 + (widget.recursive ? 146 : 114),
              crossAxisSpacing: 11,
              mainAxisSpacing: 14,
            ),
            itemCount: _scenes.length,
            itemBuilder: (_, i) {
              final scene = _scenes[i];
              final file = _source(scene.files.map((f) => f.path), state);
              final current = scene.id == widget.sceneId;
              return DecoratedBox(
                decoration: BoxDecoration(
                  border: current
                      ? Border.all(color: StashColors.accentBright, width: 2)
                      : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (current)
                        const Text(
                          '当前视频',
                          style: TextStyle(
                            color: StashColors.accentBright,
                            fontSize: 11,
                          ),
                        ),
                      Expanded(
                        child: SceneCard(
                          scene: scene,
                          index: i,
                          displayTitle: file == null
                              ? null
                              : pathName(
                                  file,
                                ).replaceFirst(RegExp(r'\.[^.]+$'), ''),
                        ),
                      ),
                      if (widget.recursive) _sourceButton(file),
                      SizedBox(
                        height: 32,
                        child: TextButton.icon(
                          onPressed: scene.streamUrl.isEmpty
                              ? null
                              : () => context.push(
                                  '/player/${scene.id}',
                                  extra: scene,
                                ),
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('播放'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
    if (_error != null)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text('视频加载失败：$_error'),
              TextButton(
                onPressed: () => _loadVideos(previous: _retryPrevious),
                child: const Text('重试加载'),
              ),
            ],
          ),
        ),
      ),
    if (_loading)
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    if (!_loading && _error == null && _end < _ids.length)
      SliverToBoxAdapter(
        child: TextButton(onPressed: _loadVideos, child: const Text('加载更多视频')),
      ),
  ];

  List<Widget> _imageSlivers(DirectoryState state) {
    final query = _imageQuery;
    final result = ref.watch(directoryImagesProvider(query));
    return result.when(
      loading: () => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(_byDate ? '正在加载图片…' : '正在准备当前范围的文件名排序…'),
              ],
            ),
          ),
        ),
      ],
      error: (error, _) => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text('图片加载失败：$error'),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(directoryImagesProvider(query)),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ],
      data: (data) => [
        SliverToBoxAdapter(
          child: ListTile(
            title: Text(
              '${data.total} 张图片（${widget.recursive ? '含子目录' : '本层'}）',
            ),
            subtitle: Text('已加载 ${data.items.length} 张'),
          ),
        ),
        if (data.items.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('当前范围没有已收录图片。可以查看全部子目录图片，或扫描新文件。'),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          sliver: SliverLayoutBuilder(
            builder: (_, constraints) {
              final columns = _columns(constraints.crossAxisExtent);
              final width =
                  (constraints.crossAxisExtent - (columns - 1) * 11) / columns;
              return SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: width * 1.05 + (widget.recursive ? 94 : 60),
                  crossAxisSpacing: 11,
                  mainAxisSpacing: 16,
                ),
                itemCount: data.items.length,
                itemBuilder: (_, i) {
                  final image = data.items[i];
                  return Column(
                    children: [
                      Expanded(
                        child: StashImageCard(
                          image: image,
                          onTap: () =>
                              Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => DirectoryImageViewer(
                                    query: query,
                                    initialId: image.id,
                                  ),
                                ),
                              ),
                        ),
                      ),
                      if (widget.recursive)
                        _sourceButton(_source(image.filePaths, state)),
                    ],
                  );
                },
              );
            },
          ),
        ),
        if (data.error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(data.error!),
                  TextButton(
                    onPressed: () => ref
                        .read(directoryImagesProvider(query).notifier)
                        .loadMore(),
                    child: const Text('重试加载'),
                  ),
                ],
              ),
            ),
          ),
        if (data.loadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        if (data.hasMore && !data.loadingMore && data.error == null)
          SliverToBoxAdapter(
            child: TextButton(
              onPressed: () =>
                  ref.read(directoryImagesProvider(query).notifier).loadMore(),
              child: const Text('加载更多图片'),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(directoryProvider);
    final index = state.index;
    final hiddenKey = jsonEncode(state.hidden.toList()..sort());
    if (index != null &&
        (!identical(index, _index) || hiddenKey != _hiddenKey)) {
      final focus = _index == null;
      _index = index;
      _hiddenKey = hiddenKey;
      if (!_kindInitialized && widget.path != null) {
        _images =
            widget.initialImages ||
            (!widget.recursive &&
                widget.sceneId == null &&
                index.sceneCount(
                      widget.path!,
                      recursive: true,
                      hidden: state.hidden,
                    ) ==
                    0);
        _byDate = _images;
        _descending = _images;
        _kindInitialized = true;
      }
      _resetVideos(state, focus: focus);
    }
    final node = widget.path == null ? null : index?.directory(widget.path!);
    final children =
        node?.children
            .map((key) => index!.nodes[key]!)
            .where((n) => !state.isHidden(n.path))
            .toList() ??
        <MediaDirectory>[];
    children.sort((a, b) => naturalCompare(pathName(a.path), pathName(b.path)));
    final roots =
        index?.roots
            .map((key) => index.nodes[key]!)
            .where((n) => !state.isHidden(n.path))
            .toList() ??
        <MediaDirectory>[];
    final pinned =
        state.pinned
            .map((path) => index?.directory(path))
            .whereType<MediaDirectory>()
            .where((n) => !state.isHidden(n.path))
            .toList()
          ..sort((a, b) => naturalCompare(a.path, b.path));
    return RefreshIndicator(
      onRefresh: () => ref.read(directoryProvider.notifier).refresh(),
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (widget.path != null && index != null && node != null)
            SliverPersistentHeader(
              pinned: true,
              delegate: _ScopeHeaderDelegate(
                height: widget.recursive ? 112 : 172,
                child: _scopeHeader(state),
              ),
            ),
          const SliverToBoxAdapter(child: ScanStatusCard()),
          if (widget.path == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '按目录浏览视频和图片',
                        style: TextStyle(color: StashColors.muted),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => context.push('/tags'),
                      icon: const Icon(Icons.sell_outlined, size: 18),
                      label: const Text('标签'),
                    ),
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (state.loading) ...[
                    const LinearProgressIndicator(),
                    Text(
                      '正在更新目录${state.total > 0 ? ' · 视频 ${state.loaded}/${state.total}' : ''}${index != null ? ' · 当前显示缓存' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: StashColors.muted,
                      ),
                    ),
                  ] else if (index != null)
                    Text(
                      '目录更新：${_time(index.updatedAt)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: StashColors.muted,
                      ),
                    ),
                  if (state.error != null)
                    TextButton(
                      onPressed: state.loading
                          ? null
                          : () =>
                                ref.read(directoryProvider.notifier).refresh(),
                      child: Text('${state.error} · 重试刷新'),
                    ),
                ],
              ),
            ),
          ),
          if (widget.path == null && index != null) ...[
            if (pinned.isNotEmpty) ...[
              const SliverToBoxAdapter(child: ListTile(title: Text('常用目录'))),
              _folderSliver(pinned, state, fullPath: true),
            ],
            const SliverToBoxAdapter(
              child: ListTile(
                title: Text('媒体根目录'),
                subtitle: Text('数量包含子目录，图片按需加载'),
              ),
            ),
            _folderSliver(roots, state, fullPath: true),
            if (roots.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('没有可显示的媒体目录。可在右上角菜单中恢复隐藏目录，或扫描媒体库。'),
                ),
              ),
          ],
          if (widget.path != null && node != null) ...[
            if (!widget.recursive && children.isNotEmpty) ...[
              const SliverToBoxAdapter(child: ListTile(title: Text('子目录'))),
              _folderSliver(children, state),
            ],
            if (_images) ..._imageSlivers(state) else ..._videoSlivers(state),
          ],
          if (widget.path != null && index != null && node == null)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('此目录暂无已收录内容，或已从服务器移除。可刷新目录后重试。'),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _folderSliver(
    List<MediaDirectory> folders,
    DirectoryState state, {
    bool fullPath = false,
  }) => SliverList.builder(
    itemCount: folders.length,
    itemBuilder: (_, i) {
      final batchStart = i ~/ 20 * 20;
      final paths = folders
          .skip(batchStart)
          .take(20)
          .map((folder) => folder.path)
          .toList();
      return _FolderRow(
        folder: folders[i],
        fullPath: fullPath,
        batch: jsonEncode(paths),
      );
    },
  );

  int _columns(double width) => width >= 900
      ? 4
      : width >= 600
      ? 3
      : 2;
  String _time(DateTime date) {
    final local = date.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _FolderRow extends ConsumerWidget {
  const _FolderRow({
    required this.folder,
    required this.batch,
    this.fullPath = false,
  });
  final MediaDirectory folder;
  final String batch;
  final bool fullPath;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(directoryProvider);
    final counts = ref.watch(folderImageCountsProvider(batch));
    final images = counts.asData?.value[folder.path];
    final videos =
        state.index?.sceneCount(
          folder.path,
          recursive: true,
          hidden: state.hidden,
        ) ??
        0;
    return ListTile(
      leading: Icon(
        folder.archive ? Icons.folder_zip_outlined : Icons.folder_outlined,
        color: StashColors.accentBright,
      ),
      title: Text(
        fullPath ? folder.path : pathName(folder.path),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '视频 $videos · 图片 ${images ?? (counts.hasError ? '读取失败' : '…')}（含子目录）',
      ),
      onTap: () => context.push(directoryLocation(folder.path)),
      trailing: PopupMenuButton<String>(
        tooltip: '目录操作',
        onSelected: (value) {
          final controller = ref.read(directoryProvider.notifier);
          if (value == 'pin') controller.togglePinned(folder.path);
          if (value == 'hide') controller.toggleHidden(folder.path);
          if (value == 'retry') {
            ref.invalidate(folderImageCountsProvider(batch));
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'pin',
            child: Text(
              state.pinned.contains(pathKey(folder.path))
                  ? '取消常用目录'
                  : '添加到常用目录',
            ),
          ),
          const PopupMenuItem(value: 'hide', child: Text('隐藏此目录')),
          if (counts.hasError)
            const PopupMenuItem(value: 'retry', child: Text('重新读取图片数量')),
        ],
      ),
    );
  }
}

class _ScopeHeaderDelegate extends SliverPersistentHeaderDelegate {
  _ScopeHeaderDelegate({required this.height, required this.child});
  final double height;
  final Widget child;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;
  @override
  bool shouldRebuild(covariant _ScopeHeaderDelegate oldDelegate) =>
      oldDelegate.child != child || oldDelegate.height != height;
}

class SameDirectoryEntry extends ConsumerWidget {
  const SameDirectoryEntry({super.key, required this.scene});
  final Scene scene;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paths = <String, String>{};
    for (final file in [
      ...scene.files.map((f) => f.path),
      if (scene.files.isEmpty) scene.filePath,
    ]) {
      final path = parentPath(file);
      if (path.isNotEmpty) paths[pathKey(path)] = path;
    }
    if (paths.isEmpty) return const SizedBox.shrink();
    final state = ref.watch(directoryProvider);
    String label(String path) {
      final count = state.index?.sceneCount(path, hidden: state.hidden);
      return '${pathName(path)} · ${count == null ? '正在统计…' : '$count 部视频（本层${state.loading ? '，缓存' : ''}）'}';
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.folder_open, color: StashColors.accentBright),
      title: const Text('同目录视频'),
      subtitle: Text(
        paths.length == 1
            ? label(paths.values.single)
            : '${paths.length} 个关联目录 · 点击选择',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        String? selected;
        if (paths.length == 1) {
          selected = paths.values.single;
        } else {
          selected = await showModalBottomSheet<String>(
            context: context,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('选择视频所在目录')),
                  for (final path in paths.values)
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(path),
                      subtitle: Text(label(path)),
                      onTap: () => Navigator.pop(context, path),
                    ),
                ],
              ),
            ),
          );
        }
        if (selected != null && context.mounted) {
          context.push(directoryLocation(selected, sceneId: scene.id));
        }
      },
    );
  }
}
