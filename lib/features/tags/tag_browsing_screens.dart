import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/server/server_session.dart';
import '../../shared/models/scene.dart';
import '../../shared/models/tag_media.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/scene_widgets.dart';

class TagListScreen extends ConsumerStatefulWidget {
  const TagListScreen({super.key, required this.sceneCategoriesOnly});

  final bool sceneCategoriesOnly;

  @override
  ConsumerState<TagListScreen> createState() => _TagListScreenState();
}

class _TagListScreenState extends ConsumerState<TagListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagsProvider);
    final title = widget.sceneCategoriesOnly ? '场景分类' : '标签';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: tags.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_rounded,
          title: '$title加载失败',
          message: error.toString(),
        ),
        data: (values) {
          final normalizedQuery = _query.trim().toLowerCase();
          final filtered = values
              .where((tag) {
                if (widget.sceneCategoriesOnly && tag.sceneCount == 0) {
                  return false;
                }
                return normalizedQuery.isEmpty ||
                    tag.name.toLowerCase().contains(normalizedQuery);
              })
              .toList(growable: false);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(tagsProvider.future),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
              itemCount: filtered.length + 1,
              separatorBuilder: (_, index) => index == 0
                  ? const SizedBox(height: 14)
                  : const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: '搜索$title',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清空',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  );
                }
                final tag = filtered[index - 1];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Icon(
                    widget.sceneCategoriesOnly
                        ? Icons.movie_filter_outlined
                        : Icons.sell_outlined,
                  ),
                  title: Text(
                    tag.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    widget.sceneCategoriesOnly
                        ? '${tag.sceneCount} 个视频'
                        : '${tag.sceneCount} 个视频 · ${tag.imageCount} 张图片',
                    style: const TextStyle(color: StashColors.muted),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(
                    '/tags/${tag.id}',
                    extra: TagBrowseArguments(
                      tag: tag,
                      scenesOnly: widget.sceneCategoriesOnly,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class TagBrowseArguments {
  const TagBrowseArguments({required this.tag, required this.scenesOnly});

  final MediaTag tag;
  final bool scenesOnly;
}

enum _MediaKind { scenes, images }

class TagMediaScreen extends ConsumerStatefulWidget {
  const TagMediaScreen({
    super.key,
    required this.tagId,
    required this.tagName,
    required this.scenesOnly,
  });

  final String tagId;
  final String tagName;
  final bool scenesOnly;

  @override
  ConsumerState<TagMediaScreen> createState() => _TagMediaScreenState();
}

class _TagMediaScreenState extends ConsumerState<TagMediaScreen> {
  static const _pageSize = 30;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final List<Scene> _scenes = [];
  final List<StashImage> _images = [];
  _MediaKind _kind = _MediaKind.scenes;
  int _sceneTotal = 0;
  int _imageTotal = 0;
  int _scenePage = 0;
  int _imagePage = 0;
  bool _loadingScenes = false;
  bool _loadingImages = false;
  String? _sceneError;
  String? _imageError;
  String _searchQuery = '';
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 450), () {
      final next = value.trim();
      if (next == _searchQuery || !mounted) return;
      setState(() => _searchQuery = next);
      _loadInitial();
    });
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter >= 650) return;
    _kind == _MediaKind.scenes ? _loadScenes() : _loadImages();
  }

  Future<void> _loadInitial() async {
    await Future.wait([
      _loadScenes(reset: true),
      if (!widget.scenesOnly) _loadImages(reset: true),
    ]);
  }

  Future<void> _refresh() => _kind == _MediaKind.scenes
      ? _loadScenes(reset: true)
      : _loadImages(reset: true);

  Future<void> _loadScenes({bool reset = false}) async {
    if (_loadingScenes || (!reset && _scenes.length >= _sceneTotal)) return;
    final api = ref.read(stashApiProvider);
    if (api == null) return;
    final requestQuery = _searchQuery;
    setState(() {
      _loadingScenes = true;
      _sceneError = null;
      if (reset) {
        _scenePage = 0;
        _sceneTotal = 0;
        _scenes.clear();
      }
    });
    try {
      final page = _scenePage + 1;
      final result = await api.findScenes(
        page: page,
        perPage: _pageSize,
        tagId: widget.tagId,
        query: requestQuery,
      );
      if (!mounted || requestQuery != _searchQuery) return;
      setState(() {
        _scenePage = page;
        _sceneTotal = result.total;
        _scenes.addAll(result.items);
      });
    } catch (error) {
      if (mounted) setState(() => _sceneError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingScenes = false);
        if (requestQuery != _searchQuery) _loadScenes(reset: true);
      }
    }
  }

  Future<void> _loadImages({bool reset = false}) async {
    if (_loadingImages || (!reset && _images.length >= _imageTotal)) return;
    final api = ref.read(stashApiProvider);
    if (api == null) return;
    final requestQuery = _searchQuery;
    setState(() {
      _loadingImages = true;
      _imageError = null;
      if (reset) {
        _imagePage = 0;
        _imageTotal = 0;
        _images.clear();
      }
    });
    try {
      final page = _imagePage + 1;
      final result = await api.findImages(
        page: page,
        perPage: _pageSize,
        tagId: widget.tagId,
        query: requestQuery,
      );
      if (!mounted || requestQuery != _searchQuery) return;
      setState(() {
        _imagePage = page;
        _imageTotal = result.total;
        _images.addAll(result.items);
      });
    } catch (error) {
      if (mounted) setState(() => _imageError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingImages = false);
        if (requestQuery != _searchQuery) _loadImages(reset: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isScenes = _kind == _MediaKind.scenes;
    final loading = isScenes ? _loadingScenes : _loadingImages;
    final error = isScenes ? _sceneError : _imageError;
    final isEmpty = isScenes ? _scenes.isEmpty : _images.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.tagName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          if (!widget.scenesOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<_MediaKind>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: _MediaKind.scenes,
                      icon: const Icon(Icons.movie_outlined),
                      label: Text('视频 $_sceneTotal'),
                    ),
                    ButtonSegment(
                      value: _MediaKind.images,
                      icon: const Icon(Icons.image_outlined),
                      label: Text('图片 $_imageTotal'),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (values) {
                    setState(() => _kind = values.first);
                    if (_kind == _MediaKind.images &&
                        _images.isEmpty &&
                        !_loadingImages) {
                      _loadImages(reset: true);
                    }
                  },
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(14, widget.scenesOnly ? 8 : 0, 14, 10),
            child: TextField(
              controller: _searchController,
              onChanged: _scheduleSearch,
              onSubmitted: (value) {
                _searchTimer?.cancel();
                final next = value.trim();
                if (next == _searchQuery) return;
                setState(() => _searchQuery = next);
                _loadInitial();
              },
              decoration: InputDecoration(
                hintText: isScenes ? '搜索当前分类中的场景' : '搜索当前标签中的图片',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        onPressed: () {
                          _searchTimer?.cancel();
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          _loadInitial();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Expanded(
            child: error != null && isEmpty
                ? EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: '加载失败',
                    message: error,
                  )
                : loading && isEmpty
                ? const Center(child: CircularProgressIndicator())
                : isEmpty
                ? EmptyState(
                    icon: isScenes
                        ? Icons.video_library_outlined
                        : Icons.image_not_supported_outlined,
                    title: isScenes ? '这个分类没有视频' : '这个标签没有图片',
                    message: '返回后可以选择其他分类或标签。',
                  )
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: CustomScrollView(
                      key: ValueKey(_kind),
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                          sliver: SliverLayoutBuilder(
                            builder: (context, constraints) {
                              final columns = constraints.crossAxisExtent >= 900
                                  ? 4
                                  : constraints.crossAxisExtent >= 600
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
                                itemCount: isScenes
                                    ? _scenes.length
                                    : _images.length,
                                itemBuilder: (_, index) => isScenes
                                    ? SceneCard(
                                        scene: _scenes[index],
                                        index: index,
                                      )
                                    : _ImageCard(image: _images[index]),
                              );
                            },
                          ),
                        ),
                        if (loading)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(18),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ImageCard extends ConsumerWidget {
  const _ImageCard({required this.image});

  final StashImage image;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeServerSessionProvider);
    final headers = session == null ? null : {'ApiKey': session.apiKey};
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: session == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _ImageViewer(image: image, headers: headers!),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: image.thumbnailUrl.isEmpty
                  ? const ColoredBox(
                      color: StashColors.surfaceHigh,
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    )
                  : CachedNetworkImage(
                      imageUrl: image.thumbnailUrl,
                      httpHeaders: headers,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const ColoredBox(
                        color: StashColors.surfaceHigh,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, _, _) => const ColoredBox(
                        color: StashColors.surfaceHigh,
                        child: Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            image.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            image.width > 0 ? '${image.width} × ${image.height}' : '图片',
            style: const TextStyle(fontSize: 10, color: StashColors.muted),
          ),
        ],
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.image, required this.headers});

  final StashImage image;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      title: Text(image.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: Center(
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 5,
        child: CachedNetworkImage(
          imageUrl: image.imageUrl.isEmpty
              ? image.thumbnailUrl
              : image.imageUrl,
          httpHeaders: headers,
          fit: BoxFit.contain,
          placeholder: (_, _) =>
              const Center(child: CircularProgressIndicator()),
          errorWidget: (_, _, _) => const EmptyState(
            icon: Icons.broken_image_outlined,
            title: '图片加载失败',
            message: '请检查服务器中的图片文件。',
          ),
        ),
      ),
    ),
  );
}
