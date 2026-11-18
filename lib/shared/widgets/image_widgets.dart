import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/server/server_session.dart';
import '../models/tag_media.dart';

class AuthenticatedImage extends ConsumerStatefulWidget {
  const AuthenticatedImage({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
  });
  final String url;
  final BoxFit fit;
  @override
  ConsumerState<AuthenticatedImage> createState() => _AuthenticatedImageState();
}

class _AuthenticatedImageState extends ConsumerState<AuthenticatedImage> {
  int _attempt = 0;
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeServerSessionProvider);
    if (widget.url.isEmpty || session == null) {
      return const ColoredBox(
        color: StashColors.surfaceHigh,
        child: Center(child: Icon(Icons.image_not_supported_outlined)),
      );
    }
    return CachedNetworkImage(
      key: ValueKey('${session.id}:${widget.url}:$_attempt'),
      imageUrl: widget.url,
      cacheKey: '${session.id}:${widget.url}',
      httpHeaders: {'ApiKey': session.apiKey},
      fit: widget.fit,
      width: double.infinity,
      placeholder: (_, _) => const ColoredBox(
        color: StashColors.surfaceHigh,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (_, _, _) => ColoredBox(
        color: StashColors.surfaceHigh,
        child: Center(
          child: TextButton.icon(
            onPressed: () async {
              await CachedNetworkImage.evictFromCache(
                widget.url,
                cacheKey: '${session.id}:${widget.url}',
              );
              if (mounted) setState(() => _attempt++);
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重试'),
          ),
        ),
      ),
    );
  }
}

class StashImageCard extends StatelessWidget {
  const StashImageCard({super.key, required this.image, this.onTap});
  final StashImage image;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap:
        onTap ??
        () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SingleImageViewer(image: image),
          ),
        ),
    borderRadius: BorderRadius.circular(6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: AuthenticatedImage(
              url: image.thumbnailUrl,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          image.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        Text(
          image.width > 0 ? '${image.width} × ${image.height}' : '图片',
          style: const TextStyle(fontSize: 10, color: StashColors.muted),
        ),
      ],
    ),
  );
}

class SingleImageViewer extends StatelessWidget {
  const SingleImageViewer({super.key, required this.image});
  final StashImage image;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: Text(image.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: Center(
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: AuthenticatedImage(
          url: image.imageUrl.isEmpty ? image.thumbnailUrl : image.imageUrl,
        ),
      ),
    ),
  );
}
