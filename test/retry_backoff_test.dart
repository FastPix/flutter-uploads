import 'dart:math';

import 'package:fastpix_resumable_uploader/fastpix_resumable_uploader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoUploadRetry.computeBackoff', () {
    // Deterministic RNG so jitter tests aren't flaky.
    Random rng() => Random(42);

    test('first attempt returns base ± jitter', () {
      final base = const Duration(seconds: 2);
      final d = VideoUploadRetry.computeBackoff(base, 1, random: rng());
      // ±25% jitter around 2000ms.
      expect(d.inMilliseconds, greaterThanOrEqualTo(1500));
      expect(d.inMilliseconds, lessThanOrEqualTo(2500));
    });

    test('doubles each attempt up to the cap', () {
      final base = const Duration(seconds: 2);
      // attempt 2 → ~4s, attempt 3 → ~8s, attempt 4 → ~16s, attempt 5 → 30s
      // (capped). Each within ±25% jitter.
      for (final t in [
        (2, 3000, 5000),   // 4000 ± 25%
        (3, 6000, 10000),  // 8000 ± 25%
        (4, 12000, 20000), // 16000 ± 25%
      ]) {
        final d = VideoUploadRetry.computeBackoff(base, t.$1, random: rng());
        expect(d.inMilliseconds, greaterThanOrEqualTo(t.$2),
            reason: 'attempt ${t.$1}');
        expect(d.inMilliseconds, lessThanOrEqualTo(t.$3),
            reason: 'attempt ${t.$1}');
      }
    });

    test('caps at maxBackoff', () {
      final base = const Duration(seconds: 2);
      // 2 * 2^20 = ~2 million seconds raw — must cap at 30s ± jitter.
      final d = VideoUploadRetry.computeBackoff(base, 100, random: rng());
      // Cap is 30s, with ±25% jitter → 22.5s..37.5s
      expect(d.inMilliseconds, lessThanOrEqualTo(30000 + 7500));
      expect(d.inMilliseconds, greaterThanOrEqualTo(30000 - 7500));
    });

    test('never returns a negative duration', () {
      for (var attempt = 1; attempt < 30; attempt++) {
        // Use a fresh RNG per call to sample more of the jitter range.
        final d = VideoUploadRetry.computeBackoff(
            const Duration(milliseconds: 1), attempt,
            random: Random(attempt));
        expect(d.inMilliseconds, greaterThanOrEqualTo(0));
      }
    });

    test('treats attempt < 1 as attempt = 1', () {
      final base = const Duration(seconds: 2);
      final d = VideoUploadRetry.computeBackoff(base, 0, random: rng());
      expect(d.inMilliseconds, greaterThanOrEqualTo(1500));
      expect(d.inMilliseconds, lessThanOrEqualTo(2500));
    });
  });
}
