import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fastpix_resumable_uploader/fastpix_resumable_uploader.dart';

class FlutterResumableUploads {
  CancelToken cancelToken = CancelToken();
  final NetworkHandler _networkHandler = NetworkHandler();
  bool _isDisposed = false;

  // Video upload state model instance
  final VideoUploadState _state = VideoUploadState();

  // Callback properties
  PauseCallback? onPause;
  AbortCallback? onAbort;
  ErrorCallback? onError;

  // Builder configuration properties
  File? _builderFile;
  String? _builderSignedUrl;
  int _builderChunkSize = 16 * 1024 * 1024;
  int? _builderMaxFileSize;
  UploadProgressCallback? _builderOnProgress;
  ErrorCallback? _builderOnError;
  int _builderMaxRetries = 5;
  Duration _builderRetryDelay = const Duration(milliseconds: 2000);

  /// Static method to create a builder for configuring uploads
  static FlutterResumableUploadsBuilder builder() {
    return FlutterResumableUploadsBuilder();
  }

  /// Configure the upload service from builder parameters
  void configureParams({
    required File file,
    required String signedUrl,
    int chunkSize = 16 * 1024 * 1024,
    int? maxFileSize,
    UploadProgressCallback? onProgress,
    ErrorCallback? onError,
    int maxRetries = 5,
    Duration retryDelay = const Duration(milliseconds: 2000),
  }) {
    _builderFile = file;
    _builderSignedUrl = signedUrl;
    _builderChunkSize = chunkSize;
    _builderMaxFileSize = maxFileSize;
    _builderOnProgress = onProgress;
    _builderOnError = onError;
    _builderMaxRetries = maxRetries;
    _builderRetryDelay = retryDelay;

    // Set max retries in state
    _state.maxRetries = maxRetries;
  }

  /// Upload video using builder configuration
  Future<void> uploadVideo() async {
    if (_builderFile == null || _builderSignedUrl == null) {
      VideoUploadProgress.emitError(UploadError(
          "Builder configuration not set. Use FlutterResumableUploadsBuilder to configure the upload."));
      return;
    }

    await _uploadVideoWithParams(
      file: _builderFile!,
      signedUrl: _builderSignedUrl!,
      chunkSize: _builderChunkSize,
      maxFileSize: _builderMaxFileSize,
      onProgress: _builderOnProgress,
      onError: _builderOnError,
    );
  }

  /// Uploads a video file in chunks
  Future<void> _uploadVideoWithParams({
    required File file,
    required String signedUrl,
    int chunkSize = 16 * 1024 * 1024,
    int? maxFileSize,
    UploadProgressCallback? onProgress,
    ErrorCallback? onError,
  }) async {
    // Validate service state
    final serviceError = VideoUploadValidator.validateServiceReady(
      isDisposed: _isDisposed,
      hasActiveUpload: _state.video != null,
      isAborted: _state.isAborted,
    );
    if (serviceError != null) {
      VideoUploadProgress.emitError(serviceError);
      return;
    }

    // Setup progress callbacks
    VideoUploadProgress.setupCallbacks(
      onProgress: onProgress ?? (progress) {},
      onError: onError ?? (error) {},
    );

    // Validate upload parameters
    final validationError = VideoUploadValidator.validateUploadParams(
      file: file,
      signedUrl: signedUrl,
      chunkSize: chunkSize,
      maxFileSize: maxFileSize,
    );
    if (validationError != null) {
      VideoUploadProgress.emitError(validationError);
      return;
    }

    try {
      // Reset retry state for new upload
      VideoUploadRetry.resetRetryState(_state);

      // Enable network health checker
      _enableNetworkHealthChecker();


      // Initialize upload state
      _initializeUploadState(file, signedUrl, chunkSize);

      VideoUploadProgress.emitProgress(
          VideoUploadProgress.statusToString(UploadStatus.uploadingChunks));
      // Start upload process
      _handleChunkStreaming();
    } catch (error) {
      VideoUploadProgress.emitError(
          UploadError("Error Uploading Video: $error"));
    }
  }

  /// Initialize upload state with file and configuration
  void _initializeUploadState(File file, String signedUrl, int chunkSize) {
    // Ensure progress model is completely reset
    VideoUploadProgress.reset();

    VideoUploadProgress.emitProgress(
        VideoUploadProgress.statusToString(UploadStatus.splittingChunks));

    _state.chunkSize = chunkSize;
    _state.gcsSignedUrl = signedUrl;
    _state.video = file;
    _state.totalChunks =
        VideoUploadChunker.calculateTotalChunks(file.lengthSync(), chunkSize);
    _state.fileLength = file.lengthSync();
    if (_state.totalChunks == 1) {
      _state.isOnlyChunk = true;
    }
    _state.isInitialized = true;

    // Log upload configuration
    SDKLogger.logUploadConfig(
      filePath: file.path,
      fileSize: file.lengthSync(),
      chunkSize: chunkSize,
      totalChunks: _state.totalChunks,
      maxRetries: _state.maxRetries,
      retryDelay: _builderRetryDelay,
      signedUrl: signedUrl,
    );

    // Emit initial progress with total chunks information
    VideoUploadProgress.emitProgress(
        "Starting upload. Total chunks: ${_state.totalChunks}",
        totalChunks: _state.totalChunks,
        currentChunkIndex: 1,
        uploadPercentage: 0.0);
  }

  /// Handle chunk streaming and upload
  void _handleChunkStreaming() async {
    // Check if we should proceed with upload
    if (_state.isOffline ||
        _state.isPaused ||
        _state.isAborted ||
        _state.isCompleted) {
      SDKLogger.debug(
          'Upload blocked - offline: ${_state.isOffline}, paused: ${_state.isPaused}, aborted: ${_state.isAborted}, completed: ${_state.isCompleted}');
      return;
    }

    // Try to acquire upload lock to prevent multiple concurrent uploads
    if (!_state.tryAcquireUploadLock()) {
      SDKLogger.debug('Upload already in progress, skipping duplicate call');
      return;
    }

    // Get current chunk index for retry tracking
    final currentChunkIndex = _state.successiveChunkCount + 1;

    // Check if we should retry the current chunk using chunk-level tracking
    if (VideoUploadRetry.hasChunkExceededMaxRetries(
        _state, currentChunkIndex)) {
      _state.releaseUploadLock();
      VideoUploadProgress.emitError(
          UploadError('Upload failed after ${_state.maxRetries} attempts. '
              'Chunk $currentChunkIndex could not be uploaded.'));
      return;
    }

    // Create new CancelToken if needed
    if (cancelToken.isCancelled) {
      cancelToken = CancelToken();
    }

    try {
      final start = _state.nextChunkRangeStart;
      final end = VideoUploadChunker.getChunkEnd(
          start, _state.chunkSize, _state.fileLength);

      final chunkToBeUploaded = await VideoUploadChunker.readFileChunk(
        file: _state.video!,
        start: start,
        end: end,
      );

      // Log chunk upload details
      SDKLogger.logChunkUpload(
        chunkIndex: currentChunkIndex,
        totalChunks: _state.totalChunks,
        chunkSize: chunkToBeUploaded.length,
        startByte: start,
        endByte: end,
        progress: ((_state.successiveChunkCount / _state.totalChunks) * 100),
      );

      final response = await VideoUploadNetwork.uploadChunk(
        signedUrl: _state.gcsSignedUrl ?? '',
        chunkBytes: chunkToBeUploaded,
        start: start,
        end: end,
        fileLength: _state.fileLength,
        cancelToken: cancelToken,
        onProgress: (progress) {
          VideoUploadProgress.emitProgress(
              "Uploading: ${progress.toStringAsFixed(1)}%",
              uploadPercentage: progress);
        },
      );

      if (response?.statusCode == 308) {
        // Success - move to next chunk
        _state.chunkCount++;
        _state.successiveChunkCount++;
        _state.chunkOffset++;
        _state.nextChunkRangeStart = end;

        // Reset retry count for this chunk since it succeeded
        VideoUploadRetry.resetChunkRetryCount(_state, currentChunkIndex);

        // Release lock before continuing with next chunk
        _state.releaseUploadLock();

        // Log successful chunk upload
        SDKLogger.debug('Chunk $currentChunkIndex uploaded successfully');

        // Emit progress with updated chunk information
        VideoUploadProgress.emitProgress(
            "Chunk $currentChunkIndex completed. Starting chunk ${currentChunkIndex + 1}/${_state.totalChunks}",
            currentChunkIndex: currentChunkIndex + 1,
            totalChunks: _state.totalChunks);

        // Continue with next chunk
        _handleChunkStreaming();
      } else if (response?.statusCode == 200) {
        // Final chunk uploaded successfully
        _state.releaseUploadLock();
        VideoUploadProgress.progressModel.isCompleted = true;
        _state.isCompleted = true;

        // Log upload completion
        SDKLogger.logUploadCompletion(
          totalChunks: _state.totalChunks,
          totalBytes: _state.fileLength,
          duration: Duration.zero, // TODO: Track actual duration
        );

        // Log final chunk retry statistics
        SDKLogger.logChunkRetryStatistics(
          chunkRetryCount: _state.chunkRetryCount,
          totalChunks: _state.totalChunks,
          maxRetries: _state.maxRetries,
        );

        VideoUploadProgress.emitProgress(
            VideoUploadProgress.statusToString(UploadStatus.completed),
            currentChunkIndex: _state.totalChunks,
            totalChunks: _state.totalChunks,
            uploadPercentage: 100.0);
        VideoUploadRetry.resetRetryState(_state);
      } else {
        _state.releaseUploadLock();
        SDKLogger.warning(
            'HTTP Error: ${response?.statusCode} for chunk $currentChunkIndex');

        // Log chunk retry statistics before attempting retry
        SDKLogger.logChunkRetryStatistics(
          chunkRetryCount: _state.chunkRetryCount,
          totalChunks: _state.totalChunks,
          maxRetries: _state.maxRetries,
        );

        VideoUploadRetry.handleChunkUploadFailure(
          state: _state,
          errorMessage: 'HTTP Error: ${response?.statusCode}',
          retryDelay: _builderRetryDelay,
          retryCallback: _handleChunkStreaming,
          chunkIndex: currentChunkIndex,
        );
      }
    } on DioException catch (ex) {
      _state.releaseUploadLock();
      SDKLogger.error('DioException during chunk upload', ex);

      // Log chunk retry statistics before attempting retry
      SDKLogger.logChunkRetryStatistics(
        chunkRetryCount: _state.chunkRetryCount,
        totalChunks: _state.totalChunks,
        maxRetries: _state.maxRetries,
      );

      VideoUploadRetry.handleDioException(
        exception: ex,
        state: _state,
        cancelToken: cancelToken,
        onPause: () => onPause?.call(),
        onAbort: () => onAbort?.call(),
        retryCallback: _handleChunkStreaming,
        retryDelay: _builderRetryDelay,
        chunkIndex: currentChunkIndex,
      );
    } catch (error) {
      _state.releaseUploadLock();
      SDKLogger.error('General error during chunk upload', error);

      // Log chunk retry statistics before attempting retry
      SDKLogger.logChunkRetryStatistics(
        chunkRetryCount: _state.chunkRetryCount,
        totalChunks: _state.totalChunks,
        maxRetries: _state.maxRetries,
      );

      VideoUploadRetry.handleChunkUploadFailure(
        state: _state,
        errorMessage: 'General Error: $error',
        retryDelay: _builderRetryDelay,
        retryCallback: _handleChunkStreaming,
        chunkIndex: currentChunkIndex,
      );
    }
  }

  /// Enable network health checker
  void _enableNetworkHealthChecker() {
    _networkHandler.startMonitoring(onChange: (isOnline) {
      SDKLogger.logNetworkStatus(isOnline);

      // Handle first-time initialization
      if (_state.isFirstTime) {
        _state.isFirstTime = false;
        _state.isOffline = !isOnline;
        return;
      }

      if (isOnline) {
        _handleNetworkRestored();
      } else {
        _handleNetworkLost();
      }
    });
  }

  /// Handle network restoration
  void _handleNetworkRestored() {
    _state.isOffline = false;

    // Only resume if upload is active and not paused/aborted
    if (!_state.isPaused &&
        !_state.isAborted &&
        !_state.isCompleted &&
        _state.isInitialized &&
        _state.totalChunks != _state.successiveChunkCount) {
      // Check if upload is already in progress
      if (_state.isUploading) {
        SDKLogger.debug(
            'Upload already in progress, skipping network restoration');
        return;
      }

      VideoUploadProgress.emitProgress('Network restored. Resuming upload...');

      // Add a small delay to ensure network is stable
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_state.isOffline &&
            !_state.isPaused &&
            !_state.isAborted &&
            !_state.isUploading) {
          _handleChunkStreaming();
        }
      });
    }
  }

  /// Handle network loss
  void _handleNetworkLost() {
    SDKLogger.info('Network lost');

    VideoUploadProgress.emitProgress(
        VideoUploadProgress.statusToString(UploadStatus.connectionLost));
    _state.isOffline = true;

    // Cancel current upload operation
    if (!cancelToken.isCancelled) {
      cancelToken.cancel();
      // Don't create new CancelToken here - it will be created when needed
    }
  }

  /// Resume the upload process from the last uploaded chunk
  void resumeUpload() {
    if (_isDisposed) return;

    if (_state.isPaused &&
        !_state.isOffline &&
        !_state.isAborted &&
        _state.isInitialized &&
        _state.totalChunks != _state.successiveChunkCount &&
        !_state.isCompleted) {
      // Check if upload is already in progress
      if (_state.isUploading) {
        SDKLogger.debug('Upload already in progress, skipping manual resume');
        return;
      }

      _state.isPaused = false;

      SDKLogger.info('Manual resume triggered');

      // Add a small delay to ensure state is properly updated
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_state.isPaused &&
            !_state.isOffline &&
            !_state.isAborted &&
            !_state.isUploading) {
          _handleChunkStreaming();
        }
      });
    }
  }

  /// Pause the upload process
  void pauseUpload() {
    if (_isDisposed) return;

    if (!_state.isOffline &&
        !_state.isPaused &&
        !_state.isAborted &&
        !_state.isCompleted &&
        _state.isInitialized) {
      _state.isPaused = true;

      SDKLogger.info('Manual pause triggered');

      if (!cancelToken.isCancelled) {
        cancelToken.cancel();
      }

      // Release upload lock when pausing
      _state.releaseUploadLock();

      VideoUploadProgress.emitProgress(
          VideoUploadProgress.statusToString(UploadStatus.paused));
      onPause?.call();
    }
  }

  /// Abort the upload process
  void abortUpload() {
    if (_isDisposed) return;

    if (!cancelToken.isCancelled) {
      cancelToken.cancel();
    }
    if (!_state.isAborted) {
      SDKLogger.info('Upload aborted by user');
      VideoUploadProgress.emitProgress(
          VideoUploadProgress.statusToString(UploadStatus.abort));
      _state.isAborted = true;

      // Release upload lock when aborting
      _state.releaseUploadLock();

      reset();
      onAbort?.call();
    }
  }

  /// Check if upload is paused
  bool isPause() => _state.isPaused;

  /// Check if upload is in progress
  bool isUploading() {
    return !_state.isCompleted && !_state.isAborted && _state.isInitialized;
  }

  /// Check if upload is currently actively uploading (lock is acquired)
  bool isCurrentlyUploading() {
    return _state.isUploading;
  }

  /// Check if network is stable and ready for upload
  bool isNetworkStable() {
    return !_state.isOffline && _networkHandler.isConnected.value == true;
  }

  /// Get current upload state for debugging
  Map<String, dynamic> getUploadState() {
    return {
      'isOffline': _state.isOffline,
      'isPaused': _state.isPaused,
      'isAborted': _state.isAborted,
      'isCompleted': _state.isCompleted,
      'isInitialized': _state.isInitialized,
      'isUploading': _state.isUploading,
      'currentChunk': _state.successiveChunkCount,
      'totalChunks': _state.totalChunks,
      'networkConnected': _networkHandler.isConnected.value,
    };
  }

  /// Clean up resources when the upload service is no longer needed
  void dispose() {
    _networkHandler.dispose();
    if (!cancelToken.isCancelled) {
      cancelToken.cancel();
    }

    // Release upload lock when disposing
    _state.releaseUploadLock();

    VideoUploadProgress.dispose();
    _isDisposed = true;
  }

  /// Reset the upload service to allow reusing the same instance
  void reset() {
    if (_isDisposed) {
      throw StateError('Cannot reset a disposed upload service');
    }

    // Cancel any ongoing operations
    if (!cancelToken.isCancelled) {
      cancelToken.cancel();
      cancelToken = CancelToken();
    }

    // Clear all state
    _state.clearAll();
    VideoUploadProgress.reset();

    // Reset retry state
    VideoUploadRetry.resetRetryState(_state);

    // Clear builder configuration
    _builderFile = null;
    _builderSignedUrl = null;
    _builderChunkSize = 16 * 1024 * 1024;
    _builderMaxFileSize = null;
    _builderOnProgress = null;
    _builderOnError = null;
    _builderMaxRetries = 5;
    _builderRetryDelay = const Duration(milliseconds: 2000);

    // Clear callbacks (optional - developer can set them again)
    onPause = null;
    onAbort = null;

    SDKLogger.info('Upload service reset successfully');
  }
}
