import 'dart:math' as math;

import 'package:flutter/widgets.dart';

@immutable
class VideoViewportTransform {
  const VideoViewportTransform({
    this.scale = minScale,
    this.offset = Offset.zero,
  });

  static const double minScale = 1;
  static const double maxScale = 5;
  static const VideoViewportTransform identity = VideoViewportTransform();

  final double scale;
  final Offset offset;

  bool get isZoomed => scale > minScale + 0.001;

  VideoViewportTransform clamped({
    required Size viewportSize,
    required double videoAspectRatio,
  }) {
    final nextScale = scale.clamp(minScale, maxScale).toDouble();
    if (nextScale <= minScale + 0.001) return identity;

    final videoSize = containedVideoSize(viewportSize, videoAspectRatio);
    final maxDx = math.max(
      0.0,
      (videoSize.width * nextScale - viewportSize.width) / 2,
    );
    final maxDy = math.max(
      0.0,
      (videoSize.height * nextScale - viewportSize.height) / 2,
    );

    return VideoViewportTransform(
      scale: nextScale,
      offset: Offset(
        offset.dx.clamp(-maxDx, maxDx).toDouble(),
        offset.dy.clamp(-maxDy, maxDy).toDouble(),
      ),
    );
  }

  static VideoViewportTransform fromGesture({
    required VideoViewportTransform start,
    required Offset startFocalPoint,
    required Offset focalPoint,
    required double scaleFactor,
    required Size viewportSize,
    required double videoAspectRatio,
  }) {
    final nextScale = (start.scale * scaleFactor)
        .clamp(minScale, maxScale)
        .toDouble();
    if (nextScale <= minScale + 0.001) return identity;

    final viewportCenter = Offset(
      viewportSize.width / 2,
      viewportSize.height / 2,
    );
    final contentPoint =
        (startFocalPoint - viewportCenter - start.offset) / start.scale;
    final nextOffset = focalPoint - viewportCenter - contentPoint * nextScale;

    return VideoViewportTransform(
      scale: nextScale,
      offset: nextOffset,
    ).clamped(viewportSize: viewportSize, videoAspectRatio: videoAspectRatio);
  }
}

Size containedVideoSize(Size viewportSize, double videoAspectRatio) {
  if (viewportSize.isEmpty) return Size.zero;
  final aspectRatio = videoAspectRatio > 0 ? videoAspectRatio : 16 / 9;
  final viewportAspectRatio = viewportSize.width / viewportSize.height;
  if (aspectRatio >= viewportAspectRatio) {
    return Size(viewportSize.width, viewportSize.width / aspectRatio);
  }
  return Size(viewportSize.height * aspectRatio, viewportSize.height);
}
