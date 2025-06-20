import 'dart:io';
import 'dart:typed_data';

/// Handles file chunking and reading operations for video uploads
class VideoUploadChunker {
  /// Reads a specific chunk of data from a file
  static Future<Uint8List> readFileChunk({
    required File file,
    required int start,
    required int end,
  }) async {
    final fileLength = await file.length();

    if (start < 0 || end > fileLength || start >= end) {
      throw RangeError(
          "Invalid start ($start) or end ($end) range for file of size $fileLength");
    }

    final raf = await file.open(); // open for reading
    await raf.setPosition(start);
    final length = end - start;

    final bytes = await raf.read(length);
    await raf.close();

    return Uint8List.fromList(bytes);
  }

  /// Writes a chunk of data to a temporary file
  static Future<File> writeChunkToFile(List<int> chunkBytes, int index) async {
    final directory = await Directory.systemTemp.createTemp();
    final file = File('${directory.path}/chunk_$index.tmp');
    await file.writeAsBytes(chunkBytes);
    return file;
  }

  /// Calculates the total number of chunks needed for a file
  static int calculateTotalChunks(int fileSize, int chunkSize) {
    return (fileSize / chunkSize).ceil();
  }

  /// Validates chunk size constraints
  static bool isValidChunkSize(int chunkSize, int minSize, int maxSize) {
    return chunkSize >= minSize && chunkSize <= maxSize;
  }

  /// Gets the end position for a chunk
  static int getChunkEnd(int start, int chunkSize, int fileSize) {
    return start + chunkSize > fileSize ? fileSize : start + chunkSize;
  }
}
