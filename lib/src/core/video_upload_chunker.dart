import 'dart:io';
import 'dart:typed_data';

/// Handles file chunking and reading operations for video uploads.
class VideoUploadChunker {
  /// Reads a specific chunk of data from a file. The returned [Uint8List]
  /// is the buffer Dart's I/O service produced — no extra copy.
  static Future<Uint8List> readFileChunk({
    required File file,
    required int start,
    required int end,
  }) async {
    final fileLength = await file.length();

    if (start < 0 || end > fileLength || start >= end) {
      throw RangeError(
          'Invalid start ($start) or end ($end) range for file of size $fileLength');
    }

    final raf = await file.open();
    try {
      await raf.setPosition(start);
      // RandomAccessFile.read returns a Uint8List directly. The previous
      // implementation wrapped it in Uint8List.fromList which makes a
      // wholesale copy — wasteful at 16 MB per chunk.
      return await raf.read(end - start);
    } finally {
      await raf.close();
    }
  }

  /// Writes a chunk of data to a temporary file.
  static Future<File> writeChunkToFile(List<int> chunkBytes, int index) async {
    final directory = await Directory.systemTemp.createTemp();
    final file = File('${directory.path}/chunk_$index.tmp');
    await file.writeAsBytes(chunkBytes);
    return file;
  }

  /// Calculates the total number of chunks needed for a file.
  static int calculateTotalChunks(int fileSize, int chunkSize) {
    return (fileSize / chunkSize).ceil();
  }

  /// Validates chunk size constraints.
  static bool isValidChunkSize(int chunkSize, int minSize, int maxSize) {
    return chunkSize >= minSize && chunkSize <= maxSize;
  }

  /// Gets the end position for a chunk.
  static int getChunkEnd(int start, int chunkSize, int fileSize) {
    return start + chunkSize > fileSize ? fileSize : start + chunkSize;
  }
}
