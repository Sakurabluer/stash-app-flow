import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/server/server_session.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key, this.isAdding = false});

  final bool isAdding;

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  bool _obscureKey = true;
  bool _isConnecting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isConnecting = true;
      _error = null;
    });
    try {
      await ref
          .read(serverSessionProvider.notifier)
          .connect(
            _urlController.text,
            _keyController.text,
            name: _nameController.text,
          );
      if (!mounted) return;
      context.go(widget.isAdding ? '/settings' : '/home');
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _switchTo(SavedServer server) async {
    setState(() {
      _isConnecting = true;
      _error = null;
    });
    try {
      await ref.read(serverSessionProvider.notifier).switchServer(server.id);
      if (mounted) context.go('/home');
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(savedServersProvider);
    return Scaffold(
      appBar: widget.isAdding
          ? AppBar(
              title: const Text(
                '添加服务器',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      body: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(color: StashColors.background),
          ),
          if (!widget.isAdding)
            const Positioned(
              left: 0,
              top: 0,
              right: 0,
              height: 310,
              child: ColoredBox(color: Color(0xFF17302D)),
            ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!widget.isAdding) const _Brand(),
                        SizedBox(height: widget.isAdding ? 12 : 64),
                        Text(
                          widget.isAdding ? '连接另一台服务器' : '连接你的媒体库',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: StashColors.text,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '输入 Stash Server 地址和 API Key',
                          style: TextStyle(
                            color: StashColors.muted,
                            fontSize: 13,
                          ),
                        ),
                        if (!widget.isAdding && servers.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          const _SectionLabel('已保存的服务器'),
                          ...servers.map(
                            (server) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.dns_rounded),
                                title: Text(server.name),
                                subtitle: Text(
                                  server.baseUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.login_rounded),
                                enabled: !_isConnecting,
                                onTap: () => _switchTo(server),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const _SectionLabel('添加服务器'),
                        ],
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '服务器名称（可选）',
                            prefixIcon: Icon(Icons.label_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _urlController,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: '服务器地址',
                            hintText: 'http://192.168.1.10:9999',
                            prefixIcon: Icon(Icons.dns_outlined),
                          ),
                          validator: (value) {
                            final uri = Uri.tryParse(value?.trim() ?? '');
                            return uri != null &&
                                    (uri.scheme == 'http' ||
                                        uri.scheme == 'https') &&
                                    uri.host.isNotEmpty
                                ? null
                                : '请输入有效的 HTTP 或 HTTPS 地址';
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _keyController,
                          obscureText: _obscureKey,
                          autocorrect: false,
                          enableSuggestions: false,
                          onFieldSubmitted: (_) => _connect(),
                          decoration: InputDecoration(
                            labelText: 'API Key',
                            prefixIcon: const Icon(Icons.key_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscureKey
                                  ? '显示 API Key'
                                  : '隐藏 API Key',
                              onPressed: () =>
                                  setState(() => _obscureKey = !_obscureKey),
                              icon: Icon(
                                _obscureKey
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? '请输入 API Key'
                              : null,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            style: const TextStyle(color: StashColors.danger),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _isConnecting ? null : _connect,
                          icon: _isConnecting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login_rounded),
                          label: Text(_isConnecting ? '正在验证' : '连接服务器'),
                        ),
                        const SizedBox(height: 16),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 15,
                              color: StashColors.muted,
                            ),
                            SizedBox(width: 6),
                            Text(
                              '每台服务器的 API Key 均独立加密保存',
                              style: TextStyle(
                                color: StashColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
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

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: StashColors.accent,
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        child: SizedBox.square(
          dimension: 34,
          child: Icon(Icons.play_arrow_rounded, color: Color(0xFF10200E)),
        ),
      ),
      SizedBox(width: 10),
      Text(
        'STASH FLOW',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      ),
    ],
  );
}
