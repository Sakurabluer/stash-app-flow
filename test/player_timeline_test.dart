import 'package:flutter_test/flutter_test.dart';
import 'package:stash_mobile/features/player/player_timeline.dart';

void main() {
  test('uses scene metadata when a transcoded stream omits its duration', () {
    expect(
      PlayerTimeline.duration(
        sceneDurationSeconds: 3723.25,
        streamDuration: Duration.zero,
      ),
      const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 250),
    );
  });

  test('adds a server transcode start offset to local stream position', () {
    expect(
      PlayerTimeline.position(
        streamPosition: const Duration(seconds: 7),
        streamStart: const Duration(seconds: 61),
        duration: const Duration(seconds: 120),
      ),
      const Duration(seconds: 68),
    );
  });

  test('clamps reported position to the known scene duration', () {
    expect(
      PlayerTimeline.position(
        streamPosition: const Duration(seconds: 80),
        streamStart: const Duration(seconds: 40),
        duration: const Duration(seconds: 100),
      ),
      const Duration(seconds: 100),
    );
  });
}
