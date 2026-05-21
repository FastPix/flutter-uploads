import 'dart:io';
import 'dart:typed_data';

import 'package:fastpix_resumable_uploader/fastpix_resumable_uploader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoUploadChunker.calculateTotalChunks', () {
    test('exact multiple of chunk size', () {
      // 48 MB file, 16 MB chunks → 3 chunks
      expect(VideoUploadChunker.calculateTotalChunks(48 * 1024 * 1024,
          16 * 1024 * 1024), 3);
    });

    test('rounds up partial last chunk', () {
      // 17 MB file, 16 MB chunks → 2 chunks
      expect(VideoUploadChunker.calculateTotalChunks(17 * 1024 * 1024,
          16 * 1024 * 1024), 2);
    });

    test('file smaller than one chunk', () {
      expect(VideoUploadChunker.calculateTotalChunks(1, 16 * 1024 * 1024), 1);
    });

    test('empty file', () {
      expect(VideoUploadChunker.calculateTotalChunks(0, 16 * 1024 * 1024), 0);
    });
  });

  group('VideoUploadChunker.getChunkEnd', () {
    test('returns start+chunkSize when within file', () {
      expect(VideoUploadChunker.getChunkEnd(0, 1024, 5000), 1024);
    });

    test('clamps to fileSize on last chunk', () {
      expect(VideoUploadChunker.getChunkEnd(4000, 1024, 5000), 5000);
    });

    test('start at EOF returns fileSize', () {
      expect(VideoUploadChunker.getChunkEnd(5000, 1024, 5000), 5000);
    });
  });

  group('VideoUploadChunker.readFileChunk', () {
    late Directory tmp;
    late File f;
    final payload = Uint8List.fromList(
      List<int>.generate(1024, (i) => i & 0xff),
    );

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('chunker_test_');
      f = File('${tmp.path}/data.bin');
      await f.writeAsBytes(payload);
    });

    tearDown(() async {
      await tmp.delete(recursive: true);
    });

    test('reads exact bytes from start of file', () async {
      final chunk =
          await VideoUploadChunker.readFileChunk(file: f, start: 0, end: 64);
      expect(chunk.length, 64);
      expect(chunk.sublist(0, 8), payload.sublist(0, 8));
    });

    test('reads exact bytes from middle of file', () async {
      final chunk = await VideoUploadChunker.readFileChunk(
          file: f, start: 100, end: 200);
      expect(chunk.length, 100);
      expect(chunk[0], payload[100]);
      expect(chunk[99], payload[199]);
    });

    test('throws on inverted range', () async {
      expect(
        () => VideoUploadChunker.readFileChunk(file: f, start: 100, end: 100),
        throwsA(isA<RangeError>()),
      );
    });

    test('throws when end exceeds file length', () async {
      expect(
        () => VideoUploadChunker.readFileChunk(file: f, start: 0, end: 99999),
        throwsA(isA<RangeError>()),
      );
    });
  });
}
