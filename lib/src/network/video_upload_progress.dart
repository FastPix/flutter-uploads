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

/// Handles progress tracking and callback dispatch for a single upload.
///
/// This used to be a process-wide singleton with static state, which meant
/// two concurrent `FlutterResumableUploads` instances would silently
/// overwrite each other's callbacks. It is now scoped per uploader.
class VideoUploadProgress {
  /// Single progress snapshot mutated in place and re-emitted on each event.
  /// Callers must treat it as a read-only view (they get the same instance
  /// every time — copy if they need to retain).
  final ProgressModel _progressModel = ProgressModel();

  /// Broadcast stream of progress events. Multiple listeners can subscribe;
  /// each receives the same [ProgressModel] reference, snapshotted at the
  /// time of emit. Use this when you need more than one consumer (e.g. UI
  /// + analytics) — `onProgress` callbacks only allow one.
  final StreamController<ProgressModel> _progressController =
      StreamController<ProgressModel>.broadcast();

  /// Broadcast stream of error events.
  final StreamController<UploadError> _errorController =
      StreamController<UploadError>.broadcast();

  ProgressModel get progressModel => _progressModel;

  /// Listen here for progress updates. Survives across pause/resume.
  Stream<ProgressModel> get progressStream => _progressController.stream;

  /// Listen here for error events.
  Stream<UploadError> get errorStream => _errorController.stream;

  /// Convert [UploadStatus] to its display string. Pure function — left
  /// static so callers don't need an instance just to format an enum.
  static String statusToString(UploadStatus status) {
    switch (status) {
      case UploadStatus.splittingChunks:
        return 'Splitting Chunks';
      case UploadStatus.gettingSignedUrls:
        return 'Getting Signed URLs';
      case UploadStatus.uploadingChunks:
        return 'Uploading Chunks';
      case UploadStatus.paused:
        return 'Paused';
      case UploadStatus.completed:
        return 'Completed';
      case UploadStatus.connectionLost:
        return 'Connection Lost';
      case UploadStatus.abort:
        return 'Aborted';
    }
  }

  /// Wires the per-upload callbacks. Replaces any previously-registered
  /// callbacks on the same instance.
  void setupCallbacks({
    required void Function(ProgressModel) onProgress,
    required void Function(UploadError) onError,
  }) {
    _progressModel
      ..onProgress = onProgress
      ..onError = onError;
  }

  /// Emits a progress update. Never throws — a callback that throws will
  /// surface via [emitError] but won't crash the upload pipeline.
  void emitProgress(
    String message, {
    int? currentChunkIndex,
    int? totalChunks,
    double? uploadPercentage,
  }) {
    _progressModel
      ..status = message
      ..currentChunkIndex =
          currentChunkIndex ?? _progressModel.currentChunkIndex
      ..totalChunks = totalChunks ?? _progressModel.totalChunks
      ..uploadPercentage = uploadPercentage ?? _progressModel.uploadPercentage;

    if (currentChunkIndex != null && currentChunkIndex > 0) {
      _progressModel.chunksUploaded = currentChunkIndex - 1;
    }

    // Stream first (can't throw out to the caller — broadcast streams
    // swallow listener errors into the zone), then the legacy callback.
    if (!_progressController.isClosed) {
      _progressController.add(_progressModel);
    }
    try {
      _progressModel.onProgress?.call(_progressModel);
    } catch (e) {
      try {
        _progressModel.onError?.call(
          UploadError('onProgress callback threw: $e'),
        );
      } catch (_) {
        // The error callback itself is broken; give up rather than loop.
      }
    }
  }

  /// Emits an error to the user-supplied error callback. Silently swallows
  /// exceptions from a misbehaving callback — re-throwing would crash the
  /// upload pipeline.
  void emitError(UploadError error) {
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }
    try {
      _progressModel.onError?.call(error);
    } catch (_) {
      // No-op. The user's callback is broken; nothing useful we can do.
    }
  }

  /// Resets the progress model for a fresh upload, but preserves the
  /// configured callbacks so callers don't have to re-register them.
  void reset() {
    _progressModel.reset();
  }

  /// Releases resources. Idempotent.
  void dispose() {
    _progressModel.onProgress = null;
    _progressModel.onError = null;
    if (!_progressController.isClosed) _progressController.close();
    if (!_errorController.isClosed) _errorController.close();
  }

  String get currentStatus => _progressModel.status;
  double get uploadPercentage => _progressModel.uploadPercentage;
  int get currentChunkIndex => _progressModel.currentChunkIndex;
  int get totalChunks => _progressModel.totalChunks;
}
