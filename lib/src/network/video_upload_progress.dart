import 'dart:async';

import '../models/error.dart';
import '../models/progress_model.dart';

/// Enum to represent the status of the upload process
enum UploadStatus {
  splittingChunks,
  gettingSignedUrls,
  uploadingChunks,
  paused,
  completed,
  connectionLost,
  abort
}

/// Handles progress tracking and callback management for video uploads
class VideoUploadProgress {
  // Progress model instance
  static final ProgressModel _progressModel = ProgressModel();

  // Stream controller to broadcast internet connectivity status
  static final StreamController<bool> _internetController =
      StreamController<bool>.broadcast();

  // Stream to listen for internet connectivity status
  static Stream<bool> get internetStream => _internetController.stream;

  // Getter for ProgressModel instance
  static ProgressModel get progressModel => _progressModel;

  /// Emits progress updates to the registered callback
  static void emitProgress(String message,
      {int? currentChunkIndex, int? totalChunks, double? uploadPercentage}) {
    try {
      _progressModel
        ..status = message
        ..currentChunkIndex =
            currentChunkIndex ?? _progressModel.currentChunkIndex
        ..totalChunks = totalChunks ?? _progressModel.totalChunks
        ..uploadPercentage =
            uploadPercentage ?? _progressModel.uploadPercentage;

      // Update chunksUploaded based on currentChunkIndex
      if (currentChunkIndex != null && currentChunkIndex > 0) {
        _progressModel.chunksUploaded = currentChunkIndex -
            1; // -1 because currentChunkIndex is the chunk being uploaded
      }

      _progressModel.onProgress?.call(_progressModel);
    } catch (error) {
      emitError(UploadError('Error Emitting Progress: $error'));
    }
  }

  /// Emits error updates to the registered callback
  static void emitError(UploadError error) {
    try {
      _progressModel.onError?.call(error);
    } catch (e) {
      throw UploadError('Error Emitting Error: $e');
    }
  }

  /// Converts UploadStatus enum to string
  static String statusToString(UploadStatus status) {
    switch (status) {
      case UploadStatus.splittingChunks:
        return "Splitting Chunks";
      case UploadStatus.gettingSignedUrls:
        return "Getting Signed URLs";
      case UploadStatus.uploadingChunks:
        return "Uploading Chunks";
      case UploadStatus.paused:
        return "Paused";
      case UploadStatus.completed:
        return "Completed";
      case UploadStatus.connectionLost:
        return "Connection Lost";
      case UploadStatus.abort:
        return "Aborted";
    }
  }

  /// Sets up progress callbacks
  static void setupCallbacks({
    required Function(ProgressModel) onProgress,
    required Function(UploadError) onError,
  }) {
    _progressModel
      ..onProgress = onProgress
      ..onError = onError;
  }

  /// Resets the progress model
  static void reset() {
    _progressModel.reset();
  }

  /// Closes the internet controller stream
  static void dispose() {
    _internetController.close();
  }

  /// Gets the current progress status
  static String get currentStatus => _progressModel.status;

  /// Gets the current upload percentage
  static double get uploadPercentage => _progressModel.uploadPercentage;

  /// Gets the current chunk index
  static int get currentChunkIndex => _progressModel.currentChunkIndex;

  /// Gets the total number of chunks
  static int get totalChunks => _progressModel.totalChunks;
}
