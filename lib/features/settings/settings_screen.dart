import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/server/server_session.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _busyServerId;

  Future<void> _switchServer(SavedServer server) async {
    setState(() => _busyServerId = server.id);
    try {
      await ref.read(serverSessionProvider.notifier).switchServer(server.id);
      if (mounted) context.go('/home');
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyServerId = null);
    }
  }

  Future<void> _confirmDelete(SavedServer server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除服务器？'),
        content: Text('将删除“${server.name}”及其本机保存的 API Key。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: StashColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyServerId = server.id);
    try {
      await ref.read(serverSessionProvider.notifier).deleteServer(server.id);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyServerId = null);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(serverSessionProvider).asData?.value;
    final session = connection?.activeSession;
    if (session == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          Row(
            children: [
              const Expanded(child: _GroupLabel('服务器')),
              IconButton(
                tooltip: '添加服务器',
                onPressed: () => context.push('/servers/add'),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
          Card(
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < connection!.servers.length;
                  index++
                ) ...[
                  _ServerTile(
                    server: connection.servers[index],
                    isActive: connection.servers[index].id == session.id,
                    isBusy: _busyServerId == connection.servers[index].id,
                    onSwitch: () => _switchServer(connection.servers[index]),
                    onDelete: () => _confirmDelete(connection.servers[index]),
                  ),
                  if (index < connection.servers.length - 1)
                    const Divider(height: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _GroupLabel('媒体库（连接时统计）'),
          Card(
            child: Column(
              children: [
                _StatTile(
                  icon: Icons.movie_outlined,
                  label: '视频总数',
                  value: '${session.sceneCount}',
                ),
                const Divider(height: 1),
                _StatTile(
                  icon: Icons.sell_outlined,
                  label: '标签总数',
                  value: '${session.tagCount}',
                ),
                const Divider(height: 1),
                _StatTile(
                  icon: Icons.info_outline_rounded,
                  label: '服务端版本',
                  value: session.version,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _GroupLabel('安全'),
          const Card(
            child: ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('凭据已加密'),
              subtitle: Text('每台服务器的 API Key 独立存储于 Android 安全存储中'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.isActive,
    required this.isBusy,
    required this.onSwitch,
    required this.onDelete,
  });

  final SavedServer server;
  final bool isActive;
  final bool isBusy;
  final VoidCallback onSwitch;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF18351B),
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      child: SizedBox.square(
        dimension: 42,
        child: isBusy
            ? const Padding(
                padding: EdgeInsets.all(11),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.dns_rounded, color: StashColors.accentBright),
      ),
    ),
    title: Row(
      children: [
        Flexible(
          child: Text(
            server.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (isActive) ...[
          const SizedBox(width: 8),
          const Icon(
            Icons.check_circle_rounded,
            color: StashColors.accentBright,
            size: 17,
          ),
        ],
      ],
    ),
    subtitle: Text(
      server.baseUrl,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: isActive || isBusy ? null : onSwitch,
    trailing: IconButton(
      tooltip: '删除服务器',
      onPressed: isBusy ? null : onDelete,
      icon: const Icon(Icons.delete_outline_rounded),
    ),
  );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(5, 0, 5, 8),
    child: Text(
      label,
      style: const TextStyle(
        color: StashColors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [Text(value, style: const TextStyle(color: StashColors.muted))],
    ),
  );
}
