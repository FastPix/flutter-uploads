import 'package:fastpix_resumable_uploader/fastpix_resumable_uploader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoUploadNetwork.parseRangeHeader', () {
    test('parses standard GCS Range header', () {
      expect(VideoUploadNetwork.parseRangeHeader('bytes=0-1572863'), 1572863);
    });

    test('tolerates extra spaces', () {
      expect(VideoUploadNetwork.parseRangeHeader('bytes = 0 - 1572863'),
          1572863);
    });

    test('returns null for missing header', () {
      expect(VideoUploadNetwork.parseRangeHeader(null), isNull);
      expect(VideoUploadNetwork.parseRangeHeader(''), isNull);
    });

    test('returns null for malformed header', () {
      expect(VideoUploadNetwork.parseRangeHeader('nonsense'), isNull);
      expect(VideoUploadNetwork.parseRangeHeader('bytes=abc'), isNull);
    });
  });

  group('VideoUploadNetwork.classifyResponse', () {
    test('200 → completed', () {
      final r = VideoUploadNetwork.classifyResponse(200, null);
      expect(r.outcome, ChunkUploadOutcome.completed);
      expect(r.statusCode, 200);
    });

    test('201 → completed (not retried)', () {
      final r = VideoUploadNetwork.classifyResponse(201, null);
      expect(r.outcome, ChunkUploadOutcome.completed);
    });

    test('204 → completed', () {
      final r = VideoUploadNetwork.classifyResponse(204, null);
      expect(r.outcome, ChunkUploadOutcome.completed);
    });

    test('308 with Range header → incomplete with serverNextOffset', () {
      final r = VideoUploadNetwork.classifyResponse(308, 'bytes=0-1572863');
      expect(r.outcome, ChunkUploadOutcome.incomplete);
      // Range gives the LAST committed byte inclusive; next offset is +1.
      expect(r.serverNextOffset, 1572864);
    });

    test('308 with no Range header → incomplete, server has 0 bytes', () {
      final r = VideoUploadNetwork.classifyResponse(308, null);
      expect(r.outcome, ChunkUploadOutcome.incomplete);
      expect(r.serverNextOffset, 0);
    });

    test('400 → permanent', () {
      final r = VideoUploadNetwork.classifyResponse(400, null);
      expect(r.outcome, ChunkUploadOutcome.permanentFailure);
    });

    test('403 (signed URL expired) → permanent', () {
      // The uploader special-cases 403/410 for refresh; classification
      // itself says "permanent" (don't blindly retry).
      final r = VideoUploadNetwork.classifyResponse(403, null);
      expect(r.outcome, ChunkUploadOutcome.permanentFailure);
    });

    test('404 → permanent', () {
      final r = VideoUploadNetwork.classifyResponse(404, null);
      expect(r.outcome, ChunkUploadOutcome.permanentFailure);
    });

    test('408 Request Timeout → transient (retryable)', () {
      final r = VideoUploadNetwork.classifyResponse(408, null);
      expect(r.outcome, ChunkUploadOutcome.transientFailure);
    });

    test('429 Too Many Requests → transient', () {
      final r = VideoUploadNetwork.classifyResponse(429, null);
      expect(r.outcome, ChunkUploadOutcome.transientFailure);
    });

    test('500 → transient', () {
      final r = VideoUploadNetwork.classifyResponse(500, null);
      expect(r.outcome, ChunkUploadOutcome.transientFailure);
    });

    test('503 → transient', () {
      final r = VideoUploadNetwork.classifyResponse(503, null);
      expect(r.outcome, ChunkUploadOutcome.transientFailure);
    });
  });
}
