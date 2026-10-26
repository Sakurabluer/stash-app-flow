class PlayerTimeline {
  const PlayerTimeline._();

  static Duration duration({
    required double sceneDurationSeconds,
    required Duration streamDuration,
  }) {
    if (sceneDurationSeconds.isFinite && sceneDurationSeconds > 0) {
      return Duration(milliseconds: (sceneDurationSeconds * 1000).round());
    }
    return streamDuration;
  }

  static Duration position({
    required Duration streamPosition,
    required Duration streamStart,
    required Duration duration,
  }) {
    final milliseconds =
        streamPosition.inMilliseconds + streamStart.inMilliseconds;
    return Duration(
      milliseconds: milliseconds.clamp(0, duration.inMilliseconds).toInt(),
    );
  }
}
