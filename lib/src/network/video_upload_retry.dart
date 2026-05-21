import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/error.dart';
import '../models/video_upload_state_model.dart';
import '../utils/logger.dart';
import 'video_upload_progress.dart';

/// Classifies network-level (Dio) failures into retry buckets without
/// touching the response classification (which is done in
/// [video_upload_network.dart] via `ChunkUploadResult`).
enum _NetworkFailureClass {
  /// Transient — safe to retry after backoff (timeouts, connection errors,
  /// unknown transport-level faults like TLS hiccups).
  transient,

  /// User-initiated — pause or abort. No retry.
  cancelled,

  /// Permanent — surface to the caller, don't retry.
  permanent,
}

/// Per-upload retry controller. Owns the pending retry [Timer] so the
/// owning uploader can cancel it on dispose/abort/reset and prevent stray
/// callbacks from firing into stale state.
class VideoUploadRetry {
  VideoUploadRetry(this._progress, {this.onTerminalFailure});

  final VideoUploadProgress _progress;

  /// Called when a chunk exhausts its retry budget OR when a permanent
  /// network failure is encountered. The owning uploader uses this to
  /// reject its in-flight `uploadVideo()` future.
  final void Function(UploadError)? onTerminalFailure;

  /// Currently-pending retry timer, if any.
  Timer? _pendingRetryTimer;

  /// Default cap on the exponential backoff window so we don't sit idle
  /// for minutes on the high end of `2^maxRetries * delay`.
  static const Duration _maxBackoff = Duration(seconds: 30);

  /// Cancels any pending retry timer. Idempotent.
  void cancelPendingRetry() {
    _pendingRetryTimer?.cancel();
    _pendingRetryTimer = null;
  }

  /// Computes the next backoff: `min(base * 2^(attempt-1), cap)` with
  /// up to ±25% jitter applied. Jitter prevents thundering-herd when many
  /// clients fail simultaneously against the same backend.
  @visibleForTesting
  static Duration computeBackoff(
    Duration base,
    int attempt, {
    Duration cap = _maxBackoff,
    math.Random? random,
  }) {
    if (attempt < 1) attempt = 1;
    // Avoid pow() blowing up int math for huge attempts.
    final exponent = attempt - 1 > 20 ? 20 : attempt - 1;
    final raw = base.inMilliseconds * (1 << exponent);
    final capped = raw > cap.inMilliseconds ? cap.inMilliseconds : raw;
    final rng = random ?? math.Random();
    // ±25% jitter centered on the capped value.
    final jitter = (capped * (rng.nextDouble() * 0.5 - 0.25)).round();
    final withJitter = capped + jitter;
    return Duration(milliseconds: withJitter < 0 ? 0 : withJitter);
  }

  /// Schedules a retry of `retryCallback` after the chunk-aware backoff,
  /// or surfaces a terminal error if the chunk has exhausted its retries.
  void handleChunkUploadFailure({
    required VideoUploadState state,
    required String errorMessage,
    required Duration retryDelay,
    required VoidCallback retryCallback,
    required int chunkIndex,
  }) {
    if (state.isPaused || state.isOffline || state.isAborted) {
      return;
    }

    state.recordChunkRetry(chunkIndex);
    final currentRetries = state.getChunkRetryCount(chunkIndex);
    final remainingAttempts = state.maxRetries - currentRetries;

    if (remainingAttempts <= 0) {
      final terminal = UploadError(
          'Upload failed after ${state.maxRetries} attempts for chunk '
          '$chunkIndex. $errorMessage');
      _progress.emitError(terminal);
      onTerminalFailure?.call(terminal);
      return;
    }

    final delay = computeBackoff(retryDelay, currentRetries);

    _progress.emitProgress(
        'Retrying chunk $chunkIndex in ${delay.inMilliseconds}ms. '
        'Attempt $currentRetries/${state.maxRetries}');
    _progress.emitError(UploadError(
        '$errorMessage. Retrying… ($remainingAttempts attempts remaining)'));

    SDKLogger.logRetryAttempt(
      chunkIndex: chunkIndex,
      attemptNumber: currentRetries,
      maxRetries: state.maxRetries,
      error: errorMessage,
      delay: delay,
    );

    // Cancel any prior timer before scheduling a new one — guards against
    // overlapping retries when multiple failure paths fire close together.
    cancelPendingRetry();
    _pendingRetryTimer = Timer(delay, () {
      _pendingRetryTimer = null;
      if (!state.isPaused && !state.isOffline && !state.isAborted) {
        retryCallback();
      }
    });
  }

  /// Maps a [DioException] to a [_NetworkFailureClass] and dispatches.
  void handleDioException({
    required DioException exception,
    required VideoUploadState state,
    required CancelToken cancelToken,
    required VoidCallback onPause,
    required VoidCallback onAbort,
    required VoidCallback retryCallback,
    required Duration retryDelay,
    required int chunkIndex,
  }) {
    final classification = _classifyDioException(exception);

    switch (classification) {
      case _NetworkFailureClass.cancelled:
        _handleCancelException(
          state: state,
          onPause: onPause,
          onAbort: onAbort,
        );
        break;

      case _NetworkFailureClass.transient:
        handleChunkUploadFailure(
          state: state,
          errorMessage:
              'Network error (${exception.type.name}): ${exception.message}',
          retryDelay: retryDelay,
          retryCallback: retryCallback,
          chunkIndex: chunkIndex,
        );
        break;

      case _NetworkFailureClass.permanent:
        final err = UploadError(
            'Permanent network failure (${exception.type.name}): '
            '${exception.message}. Not retrying.');
        _progress.emitError(err);
        onTerminalFailure?.call(err);
        break;
    }
  }

  static _NetworkFailureClass _classifyDioException(DioException ex) {
    switch (ex.type) {
      case DioExceptionType.cancel:
        return _NetworkFailureClass.cancelled;

      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        // `unknown` covers TLS hiccups, platform IO faults, and assorted
        // transient transport issues — treating these as retryable is the
        // pragmatic choice for an upload SDK over mobile networks.
        return _NetworkFailureClass.transient;

      case DioExceptionType.badCertificate:
        // Cert pinning / MITM situations — not retryable, surface loudly.
        return _NetworkFailureClass.permanent;

      case DioExceptionType.badResponse:
        // The network layer uses validateStatus: (_) => true so 4xx/5xx
        // don't normally come through here. If they do, treat as permanent.
        return _NetworkFailureClass.permanent;
    }
  }

  void _handleCancelException({
    required VideoUploadState state,
    required VoidCallback onPause,
    required VoidCallback onAbort,
  }) {
    // Pause and abort are explicit user actions, not errors — they have
    // dedicated callbacks (`onPause` / `onAbort`) and the public
    // `pauseUpload()` / `abortUpload()` methods already emit a progress
    // event with the appropriate status. Emitting them through the error
    // stream would lead consumers to mistreat pause as a failure.
    if (state.isPaused && !state.isAborted) {
      onPause();
    } else if (state.isAborted) {
      onAbort();
    }
    // Otherwise it was a network-loss cancel; the network handler will
    // re-trigger upload on recovery.
  }

  static bool hasChunkExceededMaxRetries(
      VideoUploadState state, int chunkIndex) {
    return state.hasChunkExceededMaxRetries(chunkIndex);
  }

  static bool hasExceededMaxRetries(VideoUploadState state) {
    return state.failedChunkRetried >= state.maxRetries;
  }

  /// Resets retry state for a new upload. Also cancels any pending timer.
  void resetRetryState(VideoUploadState state) {
    cancelPendingRetry();
    state.failedChunkRetried = 0;
    state.resetAllChunkRetryCounts();
    state.isPaused = false;
    state.isOffline = false;
    state.isInitialized = false;
    state.isAborted = false;
  }

  static void resetChunkRetryCount(VideoUploadState state, int chunkIndex) {
    state.resetChunkRetryCount(chunkIndex);
  }
}
