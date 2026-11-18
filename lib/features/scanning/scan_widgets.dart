import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'scan_provider.dart';

Future<void> showScanDialog(
  BuildContext context,
  WidgetRef ref, {
  String? path,
}) async {
  var previews = false;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(path == null ? '扫描媒体库' : '扫描此目录'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(path ?? '扫描服务器已配置的视频和图片媒体路径，发现新文件。'),
              const SizedBox(height: 12),
              const Text('默认仅扫描新文件，封面沿用服务器设置。'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('同时生成预览、缩略图等'),
                subtitle: const Text('会增加扫描时间和服务器负载'),
                value: previews,
                onChanged: (value) => setState(() => previews = value ?? false),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始扫描'),
          ),
        ],
      ),
    ),
  );
  if (accepted == true && context.mounted) {
    await ref
        .read(scanProvider.notifier)
        .start(path: path, generatePreviews: previews);
  }
}

class ScanAction extends ConsumerWidget {
  const ScanAction({super.key, this.path, this.enabled = true});
  final String? path;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanProvider);
    return IconButton(
      tooltip: !enabled
          ? '此目录不在服务器配置的媒体路径内'
          : scan.blocked
          ? '扫描任务处理中，请查看状态'
          : path == null
          ? '扫描媒体库'
          : '扫描此目录',
      onPressed: enabled && !scan.blocked
          ? () => showScanDialog(context, ref, path: path)
          : null,
      icon: const Icon(Icons.document_scanner_outlined),
    );
  }
}

class ScanStatusCard extends ConsumerStatefulWidget {
  const ScanStatusCard({super.key, this.readOnly = false});
  final bool readOnly;

  @override
  ConsumerState<ScanStatusCard> createState() => _ScanStatusCardState();
}

class _ScanStatusCardState extends ConsumerState<ScanStatusCard> {
  bool _expanded = false;
  String? _dismissed;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanProvider);
    final job = state.job;
    if (job == null && state.error == null && !state.busy) {
      return const SizedBox.shrink();
    }
    final running = job?.active ?? false;
    final identity =
        '${ref.watch(scanProvider.notifier).hashCode}|${job?.id}|${job?.status}|${state.error}|${state.refreshError}';
    if (!running && !state.busy && _dismissed == identity) {
      return const SizedBox.shrink();
    }
    final progress = job?.progress;
    final hasProgress =
        running && progress != null && progress.isFinite && progress >= 0;
    return Card(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  job?.status == 'FAILED'
                      ? Icons.error_outline
                      : running
                      ? Icons.sync
                      : Icons.document_scanner_outlined,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.busy ? '正在检查 / 提交扫描…' : job?.statusLabel ?? '扫描状态待确认',
                  ),
                ),
                IconButton(
                  tooltip: _expanded ? '收起详情' : '展开详情',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ),
                if (!running && !state.busy && !state.uncertain)
                  IconButton(
                    tooltip: '收起此提示',
                    onPressed: () => setState(() => _dismissed = identity),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                if (hasProgress)
                  Text('${(progress.clamp(0, 1) * 100).round()}%'),
              ],
            ),
            if (running || state.busy) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: hasProgress ? progress.clamp(0, 1) : null,
              ),
            ],
            if (_expanded) ...[
              if (state.path != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    state.path!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (job?.error?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(job!.error!),
                ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(state.error!),
                ),
              if (state.refreshError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(state.refreshError!),
                ),
              Wrap(
                spacing: 8,
                children: [
                  if (state.error != null || state.uncertain)
                    TextButton(
                      onPressed: state.busy
                          ? null
                          : () => ref.read(scanProvider.notifier).check(),
                      child: const Text('检查状态'),
                    ),
                  if (!widget.readOnly &&
                      (job?.status == 'FAILED' || job?.status == 'CANCELLED'))
                    TextButton(
                      onPressed: state.blocked
                          ? null
                          : () =>
                                showScanDialog(context, ref, path: state.path),
                      child: const Text('重新扫描'),
                    ),
                  if (!widget.readOnly &&
                      (job?.status == 'FINISHED' ||
                          job?.status == 'UNKNOWN' ||
                          state.uncertain))
                    TextButton(
                      onPressed: () =>
                          ref.read(scanProvider.notifier).refreshMedia(),
                      child: const Text('刷新列表和目录'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
