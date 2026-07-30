import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:stash_mobile/features/player/video_viewport_transform.dart';

void main() {
  group('containedVideoSize', () {
    test('fits a landscape video inside a portrait viewport', () {
      final size = containedVideoSize(const ui.Size(400, 800), 16 / 9);

      expect(size.width, closeTo(400, 0.001));
      expect(size.height, closeTo(225, 0.001));
    });
  });

  group('VideoViewportTransform', () {
    test('clamps panning to the scaled video bounds', () {
      const transform = VideoViewportTransform(
        scale: 2,
        offset: ui.Offset(500, 500),
      );

      final clamped = transform.clamped(
        viewportSize: const ui.Size(400, 800),
        videoAspectRatio: 16 / 9,
      );

      expect(clamped.offset, const ui.Offset(200, 0));
    });

    test('keeps the content below the pinch focal point stationary', () {
      final transform = VideoViewportTransform.fromGesture(
        start: VideoViewportTransform.identity,
        startFocalPoint: const ui.Offset(750, 300),
        focalPoint: const ui.Offset(750, 300),
        scaleFactor: 2,
        viewportSize: const ui.Size(1000, 600),
        videoAspectRatio: 16 / 9,
      );

      expect(transform.scale, 2);
      expect(transform.offset.dx, closeTo(-250, 0.001));
      expect(transform.offset.dy, closeTo(0, 0.001));
    });

    test('allows one-finger panning after zooming', () {
      final transform = VideoViewportTransform.fromGesture(
        start: const VideoViewportTransform(scale: 2),
        startFocalPoint: const ui.Offset(500, 300),
        focalPoint: const ui.Offset(600, 300),
        scaleFactor: 1,
        viewportSize: const ui.Size(1000, 600),
        videoAspectRatio: 16 / 9,
      );

      expect(transform.scale, 2);
      expect(transform.offset, const ui.Offset(100, 0));
    });

    test('returns to identity at the minimum scale', () {
      final transform = VideoViewportTransform.fromGesture(
        start: const VideoViewportTransform(
          scale: 2,
          offset: ui.Offset(120, 40),
        ),
        startFocalPoint: const ui.Offset(500, 300),
        focalPoint: const ui.Offset(500, 300),
        scaleFactor: 0.5,
        viewportSize: const ui.Size(1000, 600),
        videoAspectRatio: 16 / 9,
      );

      expect(transform, same(VideoViewportTransform.identity));
    });
  });
}
