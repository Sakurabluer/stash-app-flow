import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/scene_widgets.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _useQuery(String value) {
    _controller.text = value;
    setState(() => _query = value);
  }

  @override
  Widget build(BuildContext context) {
    final result = _query.isEmpty
        ? null
        : ref.watch(searchScenesProvider(_query));
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 14,
        title: TextField(
          controller: _controller,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '搜索场景、文件名或标签',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除',
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
      ),
      body: result == null
          ? _SearchPrompt(onSelected: _useQuery)
          : result.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off_rounded,
                title: '搜索失败',
                message: error.toString(),
              ),
              data: (page) => page.items.isEmpty
                  ? EmptyState(
                      icon: Icons.search_off_rounded,
                      title: '没有找到结果',
                      message: '没有与“$_query”匹配的场景。',
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(17, 10, 17, 0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '找到 ${page.total} 个场景',
                              style: const TextStyle(
                                color: StashColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        Expanded(child: SceneGrid(scenes: page.items)),
                      ],
                    ),
            ),
    );
  }
}

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.manage_search_rounded,
            size: 48,
            color: StashColors.muted,
          ),
          const SizedBox(height: 15),
          const Text(
            '搜索媒体库',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            '按标题、文件名或标签查找场景',
            style: TextStyle(color: StashColors.muted),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            children: [
              for (final query in const ['4K', '1080p', '合集'])
                ActionChip(
                  label: Text(query),
                  onPressed: () => onSelected(query),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
