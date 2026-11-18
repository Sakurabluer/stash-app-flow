import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/server/server_session.dart';
import '../../shared/widgets/image_widgets.dart';
import 'directory_images.dart';
import 'directory_index.dart';
import 'directory_providers.dart';
import 'directory_screen.dart';

class DirectoryImageViewer extends ConsumerStatefulWidget {
  const DirectoryImageViewer({
    super.key,
    required this.query,
    required this.initialId,
  });
  final DirectoryImageQuery query;
  final String initialId;
  @override
  ConsumerState<DirectoryImageViewer> createState() =>
      _DirectoryImageViewerState();
}

class _DirectoryImageViewerState extends ConsumerState<DirectoryImageViewer> {
  PageController? _pages;
  String? _currentId;
  String? _serverId;
  int _position = 0;

  @override
  void initState() {
    super.initState();
    _currentId = widget.initialId;
    _serverId = ref.read(activeServerSessionProvider)?.id;
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  Future<void> _move(int delta) async {
    final current = ref
        .read(directoryImagesProvider(widget.query))
        .asData
        ?.value;
    if (current == null || _pages == null) return;
    var next = _position + delta;
    if (next >= current.items.length && current.hasMore) {
      await ref.read(directoryImagesProvider(widget.query).notifier).loadMore();
    }
    if (!mounted) return;
    final data = ref.read(directoryImagesProvider(widget.query)).asData?.value;
    if (data == null || next < 0 || next >= data.items.length) return;
    await _pages!.animateToPage(
      next,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(activeServerSessionProvider)?.id != _serverId) {
      return Scaffold(
        appBar: AppBar(title: const Text('图片浏览已结束')),
        body: const Center(child: Text('服务器已切换，请返回后重新打开图片。')),
      );
    }
    final result = ref.watch(directoryImagesProvider(widget.query));
    final data = result.asData?.value;
    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('图片')),
        body: result.hasError
            ? Center(
                child: TextButton(
                  onPressed: () =>
                      ref.invalidate(directoryImagesProvider(widget.query)),
                  child: const Text('图片列表加载失败，点击重试'),
                ),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    if (data.items.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('此范围已没有图片，请返回刷新。')),
      );
    }
    if (_pages == null) {
      final initial = data.items.indexWhere((item) => item.id == _currentId);
      _position = initial < 0 ? 0 : initial;
      _pages = PageController(initialPage: _position);
    }
    final current = data.items[_position.clamp(0, data.items.length - 1)];
    final hidden = ref.watch(directoryProvider.select((s) => s.hidden));
    final source = current.filePaths
        .where(
          (p) => fileInScope(p, (
            path: widget.query.path,
            recursive: widget.query.recursive,
          ), hidden),
        )
        .firstOrNull;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          current.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('${_position + 1} / ${data.total}'),
          ),
        ),
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: data.items.length + (data.hasMore ? 1 : 0),
        onPageChanged: (index) {
          setState(() {
            _position = index;
            if (index < data.items.length) _currentId = data.items[index].id;
          });
          if (index >= data.items.length - 3 && data.error == null) {
            ref.read(directoryImagesProvider(widget.query).notifier).loadMore();
          }
        },
        itemBuilder: (_, index) {
          if (index >= data.items.length) {
            return Center(
              child: data.error != null
                  ? TextButton(
                      onPressed: () => ref
                          .read(directoryImagesProvider(widget.query).notifier)
                          .loadMore(),
                      child: const Text('下一页加载失败，点击重试'),
                    )
                  : const CircularProgressIndicator(),
            );
          }
          final image = data.items[index];
          return Center(
            child: InteractiveViewer(
              key: ValueKey(image.id),
              minScale: 1,
              maxScale: 5,
              child: AuthenticatedImage(
                url: image.imageUrl.isEmpty
                    ? image.thumbnailUrl
                    : image.imageUrl,
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (source != null)
                TextButton.icon(
                  onPressed: () {
                    final router = GoRouter.of(context);
                    Navigator.pop(context);
                    router.push(directoryLocation(parentPath(source)));
                  },
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(
                    parentPath(source),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: _position > 0 ? () => _move(-1) : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('上一张'),
                  ),
                  TextButton.icon(
                    onPressed: _position < data.items.length - 1 || data.hasMore
                        ? () => _move(1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('下一张'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
