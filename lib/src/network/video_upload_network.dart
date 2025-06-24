import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Handles network communication for video uploads
class VideoUploadNetwork {
  /// Uploads a chunk to the signed URL
  static Future<Response?> uploadChunk({
    required String signedUrl,
    required Uint8List chunkBytes,
    required int start,
    required int end,
    required int fileLength,
    required CancelToken cancelToken,
    required Function(double) onProgress,
  }) async {
    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.sendTimeout = const Duration(seconds: 60);
      dio.options.receiveTimeout = const Duration(seconds: 30);
      final progressStream = _buildProgressStream(
        chunkBytes: chunkBytes,
        fileSize: fileLength,
        uploadedBeforeChunk: start,
        onProgress: onProgress,
      );

      final contentRange = 'bytes $start-${end - 1}/$fileLength';

      final response = await dio.put(
        signedUrl,
        data: progressStream,
        options: Options(
          headers: {
            'Content-Type': 'application/octet-stream',
            'Content-Range': contentRange,
          },
          validateStatus: (status) {
            return status != null &&
                (status >= 200 && status < 300 || status == 308);
          },
        ),
        cancelToken: cancelToken,
      );
      return response;
    } catch (error) {
      rethrow;
    }
  }

  /// Builds a progress stream for chunk upload
  static Stream<List<int>> _buildProgressStream({
    required List<int> chunkBytes,
    required int fileSize,
    required int uploadedBeforeChunk,
    required void Function(double) onProgress,
  }) async* {
    final chunkLength = chunkBytes.length;
    const subChunkSize = 4096;
    int uploadedInThisChunk = 0;

    for (int i = 0; i < chunkLength; i += subChunkSize) {
      final end =
          (i + subChunkSize < chunkLength) ? i + subChunkSize : chunkLength;
      final subChunk = chunkBytes.sublist(i, end);

      uploadedInThisChunk += subChunk.length;
      final totalUploaded = uploadedBeforeChunk + uploadedInThisChunk;
      final progress = (totalUploaded / fileSize * 100).clamp(0, 100);

      onProgress(progress.toDouble());

      yield subChunk;
    }
  }
}
