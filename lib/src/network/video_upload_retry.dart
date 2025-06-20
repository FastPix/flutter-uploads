import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/error.dart';
import '../models/video_upload_state_model.dart';
import '../utils/logger.dart';
import 'video_upload_progress.dart';

/// Handles retry logic and error handling for video uploads
class VideoUploadRetry {

  /// Handles chunk upload failure with retry logic using chunk-level tracking
  static void handleChunkUploadFailure({
    required VideoUploadState state,
    required String errorMessage,
    required Duration retryDelay,
    required VoidCallback retryCallback,
    required int chunkIndex,
  }) {
    if (state.isPaused || state.isOffline || state.isAborted) {
      return; // Don't retry if paused, offline, or aborted
    }

    // Record retry for this specific chunk
    state.recordChunkRetry(chunkIndex);
    final currentRetries = state.getChunkRetryCount(chunkIndex);
    final remainingAttempts = state.maxRetries - currentRetries;

    if (remainingAttempts > 0) {
      VideoUploadProgress.emitProgress(
          'Retrying chunk $chunkIndex. Attempt $currentRetries/${state.maxRetries}');
      VideoUploadProgress.emitError(UploadError(
          '$errorMessage. Retrying... ($remainingAttempts attempts remaining)'));

      // Log retry attempt
      SDKLogger.logRetryAttempt(
        chunkIndex: chunkIndex,
        attemptNumber: currentRetries,
        maxRetries: state.maxRetries,
        error: errorMessage,
        delay: retryDelay * currentRetries,
      );

      // Retry after a delay (exponential backoff)
      Future.delayed(retryDelay * currentRetries, () {
        if (!state.isPaused && !state.isOffline && !state.isAborted) {
          retryCallback();
        }
      });
    } else {
      // Max retries exceeded for this chunk
      VideoUploadProgress.emitError(UploadError(
          'Upload failed after ${state.maxRetries} attempts for chunk $chunkIndex. $errorMessage'));
    }
  }

  /// Handles Dio exceptions with appropriate error handling
  static void handleDioException({
    required DioException exception,
    required VideoUploadState state,
    required CancelToken cancelToken,
    required VoidCallback onPause,
    required VoidCallback onAbort,
    required VoidCallback retryCallback,
    required Duration retryDelay,
    required int chunkIndex,
  }) {
    if (exception.type == DioExceptionType.connectionTimeout ||
        exception.type == DioExceptionType.receiveTimeout ||
        exception.type == DioExceptionType.sendTimeout ||
        exception.type == DioExceptionType.connectionError) {
      // Network-related error do not do anything
    } else if (exception.type == DioExceptionType.cancel) {
      _handleCancelException(
        state: state,
        cancelToken: cancelToken,
        onPause: onPause,
        onAbort: onAbort,
      );
    } else if (exception.type == DioExceptionType.unknown) {
      return;
    } else {
      handleChunkUploadFailure(
        state: state,
        errorMessage: 'Dio Error: ${exception.message}',
        retryDelay: retryDelay,
        retryCallback: retryCallback,
        chunkIndex: chunkIndex,
      );
    }
  }

  /// Handles cancel exceptions
  static void _handleCancelException({
    required VideoUploadState state,
    required CancelToken cancelToken,
    required VoidCallback onPause,
    required VoidCallback onAbort,
  }) {
    if (state.isPaused && !state.isAborted) {
      VideoUploadProgress.emitError(UploadError("Upload Pause"));
      onPause();
    } else {
      VideoUploadProgress.emitError(UploadError("Upload Aborted"));
      onAbort();
    }
    cancelToken = CancelToken();
  }

  /// Checks if max retries have been exceeded for a specific chunk
  static bool hasChunkExceededMaxRetries(
      VideoUploadState state, int chunkIndex) {
    return state.hasChunkExceededMaxRetries(chunkIndex);
  }

  /// Checks if max retries have been exceeded (legacy method for backward compatibility)
  static bool hasExceededMaxRetries(VideoUploadState state) {
    return state.failedChunkRetried >= state.maxRetries;
  }

  /// Resets retry state for a new upload
  static void resetRetryState(VideoUploadState state) {
    state.failedChunkRetried = 0;
    state.resetAllChunkRetryCounts();
    state.isPaused = false;
    state.isOffline = false;
    state.isInitialized = false;
    state.isAborted = false;
  }

  /// Resets retry count for a specific chunk (useful when chunk upload succeeds)
  static void resetChunkRetryCount(VideoUploadState state, int chunkIndex) {
    state.resetChunkRetryCount(chunkIndex);
  }
}
