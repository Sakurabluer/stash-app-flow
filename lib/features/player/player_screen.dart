import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme.dart';
import '../../core/server/server_session.dart';
import '../../shared/models/scene.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/scene_widgets.dart';
import 'video_viewport_transform.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key, required this.sceneId, this.initialScene});

  final String sceneId;
  final Scene? initialScene;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeServerSessionProvider);
    if (initialScene != null && session != null) {
      return _PlayerView(scene: initialScene!, apiKey: session.apiKey);
    }
    return ref
        .watch(sceneProvider(sceneId))
        .when(
          loading: () => const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Scaffold(
            appBar: AppBar(backgroundColor: Colors.black),
            backgroundColor: Colors.black,
            body: EmptyState(
              icon: Icons.error_outline_rounded,
              title: '无法打开播放器',
              message: error.toString(),
            ),
          ),
          data: (scene) => scene == null || session == null
              ? const Scaffold(
                  backgroundColor: Colors.black,
                  body: EmptyState(
                    icon: Icons.hide_source_rounded,
                    title: '无法播放',
                    message: '场景或服务器连接已失效。',
                  ),
                )
              : _PlayerView(scene: scene, apiKey: session.apiKey),
        );
  }
}

class _PlayerView extends StatefulWidget {
  const _PlayerView({required this.scene, required this.apiKey});

  final Scene scene;
  final String apiKey;

  @override
  State<_PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<_PlayerView> {
  late final VideoPlayerController _controller;
  bool _showControls = true;
  bool _initializing = true;
  bool _fastForwarding = false;
  bool _wasPlayingBeforeFastForward = false;
  double _speedBeforeFastForward = 1;
  VideoViewportTransform _videoTransform = VideoViewportTransform.identity;
  VideoViewportTransform _gestureStartTransform =
      VideoViewportTransform.identity;
  Offset _gestureStartFocalPoint = Offset.zero;
  double _gestureStartScale = 1;
  int _gesturePointerCount = 0;
  bool _transformGestureActive = false;
  bool _showZoomIndicator = false;
  Timer? _controlsTimer;
  Timer? _zoomIndicatorTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _controller = VideoPlayerController.networkUrl(
      widget.scene.sanitizedStreamUri,
      httpHeaders: {'ApiKey': widget.apiKey},
    )..addListener(_onPlayerChanged);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (widget.scene.resumeSeconds > 0) {
        await _controller.seekTo(
          Duration(seconds: widget.scene.resumeSeconds.round()),
        );
      }
      await _controller.play();
    } catch (_) {
      _error = '视频流打开失败，请检查媒体文件和服务器转码状态。';
    }
    if (mounted) {
      setState(() => _initializing = false);
      if (_error == null) _scheduleControlsHide();
    }
  }

  void _onPlayerChanged() {
    if (mounted && !_initializing) setState(() {});
  }

  Future<void> _seekBy(Duration offset) async {
    if (!_controller.value.isInitialized) return;
    final value = _controller.value;
    final targetMilliseconds =
        (value.position.inMilliseconds + offset.inMilliseconds)
            .clamp(0, value.duration.inMilliseconds)
            .toInt();
    await _controller.seekTo(Duration(milliseconds: targetMilliseconds));
    _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    if (_error != null) return;
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_fastForwarding) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_showControls) {
      _controlsTimer?.cancel();
      setState(() => _showControls = false);
    } else {
      setState(() => _showControls = true);
      _scheduleControlsHide();
    }
  }

  Future<void> _startFastForward() async {
    if (!_controller.value.isInitialized || _fastForwarding) return;
    final value = _controller.value;
    _wasPlayingBeforeFastForward = value.isPlaying;
    _speedBeforeFastForward = value.playbackSpeed;
    _controlsTimer?.cancel();
    setState(() => _fastForwarding = true);
    HapticFeedback.mediumImpact();
    try {
      await _controller.setPlaybackSpeed(2);
      if (!_wasPlayingBeforeFastForward) await _controller.play();
    } catch (_) {
      if (mounted) setState(() => _fastForwarding = false);
    }
  }

  Future<void> _stopFastForward() async {
    if (!_fastForwarding) return;
    setState(() => _fastForwarding = false);
    await _controller.setPlaybackSpeed(_speedBeforeFastForward);
    if (!_wasPlayingBeforeFastForward) await _controller.pause();
    _scheduleControlsHide();
  }

  void _startTransformGesture(
    ScaleStartDetails details,
    Size viewportSize,
    double videoAspectRatio,
  ) {
    if (!_controller.value.isInitialized || _error != null) return;
    _gestureStartTransform = _videoTransform.clamped(
      viewportSize: viewportSize,
      videoAspectRatio: videoAspectRatio,
    );
    _gestureStartFocalPoint = details.localFocalPoint;
    _gestureStartScale = 1;
    _gesturePointerCount = details.pointerCount;
    _transformGestureActive =
        details.pointerCount >= 2 || _gestureStartTransform.isZoomed;
    if (_transformGestureActive) {
      _beginTransformFeedback();
    }
  }

  void _updateTransformGesture(
    ScaleUpdateDetails details,
    Size viewportSize,
    double videoAspectRatio,
  ) {
    if (!_controller.value.isInitialized || _error != null) return;

    if (!_transformGestureActive) {
      if (details.pointerCount < 2) return;
      _gestureStartTransform = _videoTransform.clamped(
        viewportSize: viewportSize,
        videoAspectRatio: videoAspectRatio,
      );
      _gestureStartFocalPoint = details.localFocalPoint;
      _gestureStartScale = details.scale;
      _gesturePointerCount = details.pointerCount;
      _transformGestureActive = true;
      _beginTransformFeedback();
      return;
    }

    if (details.pointerCount != _gesturePointerCount) {
      _gestureStartTransform = _videoTransform.clamped(
        viewportSize: viewportSize,
        videoAspectRatio: videoAspectRatio,
      );
      _gestureStartFocalPoint = details.localFocalPoint;
      _gestureStartScale = details.scale;
      _gesturePointerCount = details.pointerCount;
      return;
    }

    final normalizedScale = _gestureStartScale == 0
        ? 1.0
        : details.scale / _gestureStartScale;
    setState(() {
      _videoTransform = VideoViewportTransform.fromGesture(
        start: _gestureStartTransform,
        startFocalPoint: _gestureStartFocalPoint,
        focalPoint: details.localFocalPoint,
        scaleFactor: normalizedScale,
        viewportSize: viewportSize,
        videoAspectRatio: videoAspectRatio,
      );
    });
  }

  void _beginTransformFeedback() {
    _controlsTimer?.cancel();
    _zoomIndicatorTimer?.cancel();
    if (_fastForwarding) unawaited(_stopFastForward());
    if (!_showZoomIndicator) {
      setState(() => _showZoomIndicator = true);
    }
  }

  void _endTransformGesture() {
    if (!_transformGestureActive) return;
    _transformGestureActive = false;
    _gesturePointerCount = 0;
    _zoomIndicatorTimer?.cancel();
    _zoomIndicatorTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showZoomIndicator = false);
    });
    _scheduleControlsHide();
  }

  void _resetVideoTransform() {
    _zoomIndicatorTimer?.cancel();
    setState(() {
      _videoTransform = VideoViewportTransform.identity;
      _showZoomIndicator = true;
    });
    _zoomIndicatorTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showZoomIndicator = false);
    });
    HapticFeedback.selectionClick();
    _scheduleControlsHide();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _zoomIndicatorTimer?.cancel();
    _controller
      ..removeListener(_onPlayerChanged)
      ..dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  String _time(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    final viewportSize = MediaQuery.sizeOf(context);
    final videoAspectRatio = value.aspectRatio == 0
        ? 16 / 9
        : value.aspectRatio;
    final visibleTransform = _videoTransform.clamped(
      viewportSize: viewportSize,
      videoAspectRatio: videoAspectRatio,
    );
    final durationMs = value.duration.inMilliseconds.toDouble();
    final positionMs = value.position.inMilliseconds
        .clamp(0, value.duration.inMilliseconds)
        .toDouble();

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onScaleStart: (details) =>
            _startTransformGesture(details, viewportSize, videoAspectRatio),
        onScaleUpdate: (details) =>
            _updateTransformGesture(details, viewportSize, videoAspectRatio),
        onScaleEnd: (_) => _endTransformGesture(),
        onLongPressStart: (details) {
          if (details.localPosition.dx >= viewportSize.width * 0.55) {
            unawaited(_startFastForward());
          }
        },
        onLongPressEnd: (_) => unawaited(_stopFastForward()),
        onLongPressCancel: () => unawaited(_stopFastForward()),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: Transform.translate(
                offset: visibleTransform.offset,
                child: Transform.scale(
                  scale: visibleTransform.scale,
                  child: Center(
                    child: value.isInitialized
                        ? AspectRatio(
                            aspectRatio: videoAspectRatio,
                            child: VideoPlayer(_controller),
                          )
                        : SceneImage(scene: widget.scene, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            if (_initializing)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: StashColors.danger),
                  ),
                ),
              ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 54,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _showZoomIndicator ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xCC111311),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Text(
                          '${visibleTransform.scale.toStringAsFixed(1)}x',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_fastForwarding)
              Center(
                child: Transform.translate(
                  offset: const Offset(0, -74),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xCC111311),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fast_forward_rounded, size: 19),
                            SizedBox(width: 7),
                            Text(
                              '2 倍速播放',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            AnimatedOpacity(
              opacity: _showControls ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xAA000000),
                        Colors.transparent,
                        Color(0xCC000000),
                      ],
                      stops: [0, 0.52, 1],
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: '返回',
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            Expanded(
                              child: Text(
                                widget.scene.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (visibleTransform.isZoomed)
                              IconButton(
                                tooltip: '恢复原始画面',
                                onPressed: _resetVideoTransform,
                                icon: const Icon(Icons.center_focus_strong),
                              ),
                            PopupMenuButton<double>(
                              tooltip: '播放速度',
                              initialValue: value.playbackSpeed,
                              onOpened: () => _controlsTimer?.cancel(),
                              onCanceled: _scheduleControlsHide,
                              onSelected: (speed) {
                                _controller.setPlaybackSpeed(speed);
                                _scheduleControlsHide();
                              },
                              itemBuilder: (_) => [
                                for (final speed in const [
                                  0.5,
                                  1.0,
                                  1.25,
                                  1.5,
                                  2.0,
                                ])
                                  PopupMenuItem(
                                    value: speed,
                                    child: Text('${speed}x'),
                                  ),
                              ],
                              icon: const Icon(Icons.speed_rounded),
                            ),
                          ],
                        ),
                        const Spacer(),
                        if (value.isInitialized && _error == null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton.filledTonal(
                                tooltip: '回退 10 秒',
                                onPressed: () =>
                                    _seekBy(const Duration(seconds: -10)),
                                iconSize: 29,
                                style: IconButton.styleFrom(
                                  minimumSize: const Size.square(54),
                                  backgroundColor: const Color(0xCC292C2A),
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.replay_10_rounded),
                              ),
                              const SizedBox(width: 20),
                              IconButton.filled(
                                tooltip: value.isPlaying ? '暂停' : '播放',
                                onPressed: () {
                                  value.isPlaying
                                      ? _controller.pause()
                                      : _controller.play();
                                  _scheduleControlsHide();
                                },
                                iconSize: 38,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size.square(62),
                                ),
                                icon: Icon(
                                  value.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                              ),
                              const SizedBox(width: 20),
                              Tooltip(
                                message: '前进 10 秒，长按 2 倍速',
                                child: Semantics(
                                  button: true,
                                  label: '前进 10 秒，长按 2 倍速',
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () =>
                                        _seekBy(const Duration(seconds: 10)),
                                    onLongPressStart: (_) =>
                                        _startFastForward(),
                                    onLongPressEnd: (_) => _stopFastForward(),
                                    onLongPressCancel: _stopFastForward,
                                    child: const DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Color(0xCC292C2A),
                                        shape: BoxShape.circle,
                                      ),
                                      child: SizedBox.square(
                                        dimension: 54,
                                        child: Icon(
                                          Icons.forward_10_rounded,
                                          size: 29,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const Spacer(),
                        if (value.isInitialized)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: Row(
                              children: [
                                Text(
                                  _time(value.position),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                Expanded(
                                  child: Slider(
                                    value: durationMs <= 0 ? 0 : positionMs,
                                    max: durationMs <= 0 ? 1 : durationMs,
                                    onChangeStart: (_) =>
                                        _controlsTimer?.cancel(),
                                    onChanged: (position) => _controller.seekTo(
                                      Duration(milliseconds: position.round()),
                                    ),
                                    onChangeEnd: (_) => _scheduleControlsHide(),
                                  ),
                                ),
                                Text(
                                  _time(value.duration),
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
