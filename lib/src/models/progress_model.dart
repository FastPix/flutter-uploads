
import 'package:flutter_uploads_sdk/src/core/video_upload_builder.dart';

class ProgressModel {
  /// The current status of the upload process (e.g., uploading, paused, completed).
  String status;

  /// The percentage of upload completion (0.0 to 100.0).
  double uploadPercentage;

  /// The index of the chunk currently being uploaded.
  int currentChunkIndex;

  /// The total number of chunks to be uploaded.
  int totalChunks;

  /// The number of chunks that have been successfully uploaded.
  int chunksUploaded;

  /// Indicates if the upload has been completed successfully.
  bool isCompleted;

  /// Callback function for progress updates
  UploadProgressCallback? onProgress;

  /// Callback function for error updates
  ErrorCallback? onError;

  ProgressModel({
    this.status = '',
    this.uploadPercentage = 0.0,
    this.currentChunkIndex = 0,
    this.totalChunks = 0,
    this.chunksUploaded = 0,
    this.isCompleted = false,
  });

  /// Reset all properties to their initial values
  void reset() {
    status = '';
    uploadPercentage = 0.0;
    currentChunkIndex = 0;
    totalChunks = 0;
    chunksUploaded = 0;
    isCompleted = false;
    // Don't reset callbacks as they might be set by the developer
  }
}
