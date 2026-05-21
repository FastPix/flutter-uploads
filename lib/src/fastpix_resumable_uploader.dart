import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fastpix_resumable_uploader/fastpix_resumable_uploader.dart';

import 'utils/lifecycle_observer.dart';

class FlutterResumableUploads {
  CancelToken cancelToken = CancelToken();
  final NetworkHandler _networkHandler = NetworkHandler();
  bool _isDisposed = false;

  // Video upload state model instance
  final VideoUploadState _state = VideoUploadState();

  /// Per-upload progress dispatcher. Previously a process-wide singleton —
  /// scoping it to the uploader instance fixes the bug where two
  /// concurrent uploads in the same app would cross-wire callbacks.
  final VideoUploadProgress _progress = VideoUploadProgress();

  /// Per-upload retry controller, owns the pending retry timer so we can
  /// cancel it deterministically on dispose/abort/reset. Routes terminal
  /// failures back here so the in-flight `uploadVideo()` future rejects.
  late final VideoUploadRetry _retry = VideoUploadRetry(
    _progress,
    onTerminalFailure: _rejectCompletion,
  );

  /// Resolved when the upload reaches a terminal state. Null while no
  /// upload is in progress. Distinct per-call so awaiting `uploadVideo()`
  /// returns the *current* attempt's outcome, not a stale one.
  Completer<void>? _completionCompleter;

  /// Terminal-failure flag. `isUploading()` honors this so a permanent
  /// failure isn't reported as "still uploading".
  bool _isTerminallyFailed = false;

  /// Broadcast stream of progress events. Multiple listeners supported.
  Stream<ProgressModel> get progressStream => _progress.progressStream;

  /// Broadcast stream of error events.
  Stream<UploadError> get errorStream => _progress.errorStream;

  // Callback properties
  PauseCallback? onPause;
  AbortCallback? onAbort;
  ErrorCallback? onError;

  /// Optional: called when the signed URL appears to have expired. The
  /// callback's return value replaces [_state.gcsSignedUrl] and the upload
  /// resumes from the server's committed cursor.
  SignedUrlRefreshCallback? onUrlRefresh;

  /// Optional app-lifecycle observer that auto-pauses the upload when the
  /// app goes to the background and resumes when it returns. Attached via
  /// [enableAppLifecycleObserver] (also exposed on the builder).
  UploadLifecycleObserver? _lifecycleObserver;

  /// Attaches a [WidgetsBindingObserver] that auto-pauses on background
  /// and auto-resumes on foreground. Idempotent.
  void enableAppLifecycleObserver() {
    _lifecycleObserver ??= UploadLifecycleObserver(this)..attach();
  }

  /// Removes the lifecycle observer if one is attached. Idempotent.
  void disableAppLifecycleObserver() {
    _lifecycleObserver?.detach();
    _lifecycleObserver = null;
  }

  // Builder configuration properties
  File? _builderFile;
  String? _builderSignedUrl;
  int _builderChunkSize = 16 * 1024 * 1024;
  int? _builderMaxFileSize;
  UploadProgressCallback? _builderOnProgress;
  ErrorCallback? _builderOnError;
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
    _builderRetryDelay = retryDelay;

    // maxRetries lives only on the state — the SDK's single source of
    // truth for the retry policy. The retry controller reads it from there.
    _state.maxRetries = maxRetries;
  }

  /// Kicks off the upload and returns a [Future] that completes when the
  /// upload reaches a terminal state:
  ///
  /// * `Future` resolves normally when the upload finalizes (any 2xx).
  /// * `Future` resolves with an [UploadError] when the upload fails
  ///   permanently — exhausted retries, 4xx, or aborted by the caller.
  ///
  /// Progress events stream through [progressStream] / `onProgress`.
  /// Errors that are *recovered* (transient retries) flow only through the
  /// error stream / callback — they do not reject the returned future.
  Future<void> uploadVideo() async {
    if (_builderFile == null || _builderSignedUrl == null) {
      final err = UploadError(
          'Builder configuration not set. Use FlutterResumableUploadsBuilder '
          'to configure the upload.');
      _progress.emitError(err);
      throw err;
    }

    // Prepare a fresh completer for this attempt. Any pending one from a
    // previous attempt should have been resolved already; if not, complete
    // it with an error so old await-ers don't hang forever.
    final stale = _completionCompleter;
    if (stale != null && !stale.isCompleted) {
      stale.completeError(
        UploadError('Upload superseded by a new uploadVideo() call.'),
      );
    }
    final completer = Completer<void>();
    _completionCompleter = completer;
    _isTerminallyFailed = false;

    _uploadVideoWithParams(
      file: _builderFile!,
      signedUrl: _builderSignedUrl!,
      chunkSize: _builderChunkSize,
      maxFileSize: _builderMaxFileSize,
      onProgress: _builderOnProgress,
      onError: _builderOnError,
    );

    return completer.future;
  }

  /// Internal: resolve the in-flight `uploadVideo()` future successfully.
  void _resolveCompletion() {
    final c = _completionCompleter;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// Internal: reject the in-flight `uploadVideo()` future with [error].
  /// Marks the uploader as terminally failed so `isUploading()` reports
  /// false until the next `uploadVideo()` call.
  void _rejectCompletion(UploadError error) {
    _isTerminallyFailed = true;
    final c = _completionCompleter;
    if (c != null && !c.isCompleted) c.completeError(error);
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
      _progress.emitError(serviceError);
      return;
    }

    // Setup progress callbacks
    _progress.setupCallbacks(
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
      _progress.emitError(validationError);
      return;
    }

    try {
      // Reset retry state for new upload
      _retry.resetRetryState(_state);

      // Enable network health checker
      _enableNetworkHealthChecker();


      // Initialize upload state
      _initializeUploadState(file, signedUrl, chunkSize);

      _progress.emitProgress(
          VideoUploadProgress.statusToString(UploadStatus.uploadingChunks));
      // Start upload process
      _handleChunkStreaming();
    } catch (error) {
      _progress.emitError(
          UploadError("Error Uploading Video: $error"));
    }
  }

  /// Initialize upload state with file and configuration
  void _initializeUploadState(File file, String signedUrl, int chunkSize) {
    // Ensure progress model is completely reset
    _progress.reset();

    _progress.emitProgress(
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
    _progress.emitProgress(
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
      _progress.emitError(
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

      // Empty-trailing-chunk guard: if we've sent every byte locally but
      // never received a terminal 2xx, ask the server for its truth before
      // assuming we're done or trying to PUT a zero-byte range (which would
      // produce an inverted Content-Range).
      if (start >= _state.fileLength) {
        _state.releaseUploadLock();
        await _verifyCompletionFromServer(currentChunkIndex);
        return;
      }

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

      final result = await VideoUploadNetwork.uploadChunk(
        signedUrl: _state.gcsSignedUrl ?? '',
        chunkBytes: chunkToBeUploaded,
        start: start,
        end: end,
        fileLength: _state.fileLength,
        cancelToken: cancelToken,
        onProgress: (progress) {
          _progress.emitProgress(
              "Uploading: ${progress.toStringAsFixed(1)}%",
              uploadPercentage: progress);
        },
      );

      switch (result.outcome) {
        case ChunkUploadOutcome.incomplete:
          // GCS told us exactly how much it actually committed via the
          // `Range:` response header. Trust it — never assume we got all
          // [start..end] in. Partial commits are real on flaky links.
          final serverNext = result.serverNextOffset ?? 0;

          // Server should never claim more than what we just sent.
          if (serverNext > end) {
            _state.releaseUploadLock();
            _progress.emitError(UploadError(
                'Server cursor ($serverNext) is ahead of bytes we sent '
                '($end). Aborting to avoid data corruption.'));
            return;
          }

          if (serverNext < end) {
            SDKLogger.warning(
                'Partial commit on chunk $currentChunkIndex: sent '
                '$start-${end - 1} but server committed only through '
                '${serverNext - 1}. Resuming from $serverNext.');
          }

          _state.nextChunkRangeStart = serverNext;
          _recomputeChunkCountersFromCursor();

          // Reset retry count for this chunk if we fully cleared it.
          if (serverNext >= end) {
            VideoUploadRetry.resetChunkRetryCount(_state, currentChunkIndex);
          }

          _state.releaseUploadLock();

          SDKLogger.debug(
              'Chunk $currentChunkIndex committed to $serverNext / '
              '${_state.fileLength}');

          _progress.emitProgress(
              "Chunk $currentChunkIndex committed. Starting chunk "
              "${_state.successiveChunkCount + 1}/${_state.totalChunks}",
              currentChunkIndex: _state.successiveChunkCount + 1,
              totalChunks: _state.totalChunks);

          // Continue with next chunk
          _handleChunkStreaming();
          break;

        case ChunkUploadOutcome.completed:
          _state.releaseUploadLock();
          _markCompleted();
          break;

        case ChunkUploadOutcome.transientFailure:
          _state.releaseUploadLock();
          SDKLogger.warning(
              'Transient HTTP ${result.statusCode} for chunk $currentChunkIndex');

          SDKLogger.logChunkRetryStatistics(
            chunkRetryCount: _state.chunkRetryCount,
            totalChunks: _state.totalChunks,
            maxRetries: _state.maxRetries,
          );

          // Before retrying, re-sync the cursor from the server. The chunk
          // may have been partially committed before the error response.
          await _resyncCursorFromServer();

          _retry.handleChunkUploadFailure(
            state: _state,
            errorMessage:
                result.errorMessage ?? 'HTTP ${result.statusCode}',
            retryDelay: _builderRetryDelay,
            retryCallback: _handleChunkStreaming,
            chunkIndex: currentChunkIndex,
          );
          break;

        case ChunkUploadOutcome.permanentFailure:
          _state.releaseUploadLock();

          // Signed-URL-expiry path: GCS returns 403 (or sometimes 410)
          // when a resumable session URL has expired. If the caller has
          // wired up onUrlRefresh, give them one chance to mint a new URL
          // and resume from the server's committed cursor.
          if (_isLikelyUrlExpiry(result.statusCode) &&
              onUrlRefresh != null) {
            SDKLogger.warning(
                'Signed URL appears expired (HTTP ${result.statusCode}). '
                'Requesting fresh URL via onUrlRefresh.');
            final refreshed = await _tryRefreshSignedUrl();
            if (refreshed) {
              _handleChunkStreaming();
              break;
            }
          }

          SDKLogger.error(
              'Permanent failure on chunk $currentChunkIndex: '
              '${result.errorMessage}');
          final permErr = UploadError(
              'Upload failed permanently: ${result.errorMessage}. '
              'This is not retryable (HTTP ${result.statusCode}).');
          _progress.emitError(permErr);
          _rejectCompletion(permErr);
          break;
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

      _retry.handleDioException(
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

      _retry.handleChunkUploadFailure(
        state: _state,
        errorMessage: 'General Error: $error',
        retryDelay: _builderRetryDelay,
        retryCallback: _handleChunkStreaming,
        chunkIndex: currentChunkIndex,
      );
    }
  }

  /// Recomputes chunk progress counters from the current cursor. Called
  /// whenever [_state.nextChunkRangeStart] is updated to a server-reported
  /// value, which may not align with chunk boundaries (partial commits).
  void _recomputeChunkCountersFromCursor() {
    if (_state.chunkSize <= 0) return;
    final committedChunks = _state.nextChunkRangeStart ~/ _state.chunkSize;
    _state.successiveChunkCount = committedChunks;
    _state.chunkCount = committedChunks;
    _state.chunkOffset = committedChunks;
  }

  /// Marks the upload as completed, emits the final progress event, and
  /// resolves the `uploadVideo()` future.
  void _markCompleted() {
    _progress.progressModel.isCompleted = true;
    _state.isCompleted = true;
    _state.nextChunkRangeStart = _state.fileLength;
    _state.successiveChunkCount = _state.totalChunks;

    SDKLogger.logUploadCompletion(
      totalChunks: _state.totalChunks,
      totalBytes: _state.fileLength,
      duration: Duration.zero,
    );

    SDKLogger.logChunkRetryStatistics(
      chunkRetryCount: _state.chunkRetryCount,
      totalChunks: _state.totalChunks,
      maxRetries: _state.maxRetries,
    );

    _progress.emitProgress(
        VideoUploadProgress.statusToString(UploadStatus.completed),
        currentChunkIndex: _state.totalChunks,
        totalChunks: _state.totalChunks,
        uploadPercentage: 100.0);
    _retry.resetRetryState(_state);
    _resolveCompletion();
  }

  /// Issues a GCS `Content-Range: bytes */<total>` status query and updates
  /// the local cursor to whatever the server reports. Best-effort: if the
  /// query itself fails (no network, etc.) we fall through and let the
  /// retry policy handle it — the next upload PUT will still use the old
  /// cursor, which is no worse than the pre-fix behavior.
  Future<void> _resyncCursorFromServer() async {
    final url = _state.gcsSignedUrl;
    if (url == null || url.isEmpty || _state.fileLength <= 0) return;

    try {
      final token = cancelToken.isCancelled ? CancelToken() : cancelToken;
      final r = await VideoUploadNetwork.queryUploadStatus(
        signedUrl: url,
        fileLength: _state.fileLength,
        cancelToken: token,
      );

      switch (r.outcome) {
        case ChunkUploadOutcome.completed:
          SDKLogger.info('Resync: server reports session already completed');
          _markCompleted();
          break;
        case ChunkUploadOutcome.incomplete:
          final serverNext = r.serverNextOffset ?? 0;
          if (serverNext != _state.nextChunkRangeStart) {
            SDKLogger.info(
                'Resync: cursor moved from ${_state.nextChunkRangeStart} '
                'to $serverNext');
            _state.nextChunkRangeStart = serverNext;
            _recomputeChunkCountersFromCursor();
          }
          break;
        case ChunkUploadOutcome.permanentFailure:
          // Session is dead (e.g. signed URL expired). Surface and bail.
          _progress.emitError(UploadError(
              'Resumable session is no longer valid: '
              '${r.errorMessage}. A fresh signed URL is required.'));
          break;
        case ChunkUploadOutcome.transientFailure:
          // Will be retried by the normal retry path.
          break;
      }
    } catch (e) {
      SDKLogger.warning('Resync query failed (best-effort): $e');
    }
  }

  /// Returns true for the HTTP statuses that typically indicate the signed
  /// URL has expired and a fresh one is required. We treat 401/403/410 the
  /// same way: they're permanent against the *current* URL but recoverable
  /// against a freshly-minted one.
  bool _isLikelyUrlExpiry(int? status) {
    return status == 401 || status == 403 || status == 410;
  }

  /// Invokes the user-supplied [onUrlRefresh] callback, swaps in the new
  /// URL, and re-syncs the cursor from the server. Returns true on success.
  Future<bool> _tryRefreshSignedUrl() async {
    final cb = onUrlRefresh;
    if (cb == null) return false;
    try {
      final fresh = await cb();
      if (fresh.isEmpty) {
        SDKLogger.error('onUrlRefresh returned an empty URL');
        return false;
      }
      _state.gcsSignedUrl = fresh;
      SDKLogger.info('Signed URL refreshed; resyncing cursor against server.');
      await _resyncCursorFromServer();
      return !_state.isAborted && !_isTerminallyFailed;
    } catch (e) {
      SDKLogger.error('onUrlRefresh threw: $e');
      return false;
    }
  }

  /// Public API: replace the in-flight signed URL with [newUrl] (for
  /// callers that want to refresh proactively rather than waiting for an
  /// expiry response). Re-syncs the cursor from the server against the new
  /// URL before the next chunk is sent.
  Future<void> refreshSignedUrl(String newUrl) async {
    if (_isDisposed) return;
    if (newUrl.isEmpty) {
      _progress.emitError(UploadError('refreshSignedUrl: empty URL'));
      return;
    }
    _state.gcsSignedUrl = newUrl;
    await _resyncCursorFromServer();
  }

  /// Verifies completion when the local cursor reaches EOF but no terminal
  /// 2xx has been seen. Either marks completed (if the server agrees) or
  /// rewinds the cursor to whatever the server actually has.
  Future<void> _verifyCompletionFromServer(int currentChunkIndex) async {
    SDKLogger.info(
        'Cursor at EOF (${_state.nextChunkRangeStart} / '
        '${_state.fileLength}) without terminal 2xx — querying status');
    await _resyncCursorFromServer();
    if (_state.isCompleted) return;
    // Server says there are still bytes outstanding — continue uploading
    // from the corrected cursor.
    if (_state.nextChunkRangeStart < _state.fileLength) {
      _handleChunkStreaming();
    }
  }

  /// Enable network health checker.
  ///
  /// Previously the first connectivity event was swallowed with a "first
  /// time" flag — meaning if the user kicked off an upload while offline,
  /// the SDK could miss the subsequent recovery event. Now every event
  /// flows through the same restored/lost handler; the boolean is only
  /// used to skip the redundant "Network restored" log on first start.
  void _enableNetworkHealthChecker() {
    _networkHandler.startMonitoring(onChange: (isOnline) {
      SDKLogger.logNetworkStatus(isOnline);

      final wasFirst = _state.isFirstTime;
      _state.isFirstTime = false;

      if (isOnline) {
        // On the very first event we mark online but don't trigger a
        // resume — there's nothing to resume yet, the upload may not have
        // even started. Subsequent events do trigger resume.
        _state.isOffline = false;
        if (!wasFirst) _handleNetworkRestored();
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

      _progress.emitProgress('Network restored. Resuming upload...');

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

    _progress.emitProgress(
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

      _progress.emitProgress(
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
      _progress.emitProgress(
          VideoUploadProgress.statusToString(UploadStatus.abort));
      _state.isAborted = true;

      // Cancel any pending retry timer scheduled by the retry policy —
      // otherwise it would fire after reset() and poke the new state.
      _retry.cancelPendingRetry();

      // Release upload lock when aborting
      _state.releaseUploadLock();

      // Reject the in-flight uploadVideo() future before reset() nukes the
      // completer reference.
      _rejectCompletion(UploadError('Upload aborted by user.'));

      reset();
      onAbort?.call();
    }
  }

  /// Whether the upload is currently paused.
  bool isPause() => _state.isPaused;

  /// Whether an upload session is alive — initialized, not finalized, not
  /// aborted, and not in a terminal-failure state. A paused upload still
  /// returns `true` here because the session is recoverable via
  /// [resumeUpload]. For "bytes are flowing right now", use
  /// [isCurrentlyUploading].
  bool isUploading() {
    return _state.isInitialized &&
        !_state.isCompleted &&
        !_state.isAborted &&
        !_isTerminallyFailed;
  }

  /// Whether bytes are actively being transmitted at this instant. False
  /// during pause, during retry backoff, and while offline — even though
  /// the session may still be alive (see [isUploading]).
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
    disableAppLifecycleObserver();
    _networkHandler.dispose();
    if (!cancelToken.isCancelled) {
      cancelToken.cancel();
    }

    // Cancel any pending retry timer so it can't fire after dispose.
    _retry.cancelPendingRetry();

    // Release upload lock when disposing
    _state.releaseUploadLock();

    _progress.dispose();
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
    _progress.reset();

    // Reset retry state
    _retry.resetRetryState(_state);

    // Clear builder configuration
    _builderFile = null;
    _builderSignedUrl = null;
    _builderChunkSize = 16 * 1024 * 1024;
    _builderMaxFileSize = null;
    _builderOnProgress = null;
    _builderOnError = null;
    _builderRetryDelay = const Duration(milliseconds: 2000);

    // Drop the completer so the next uploadVideo() starts a fresh one.
    _completionCompleter = null;
    _isTerminallyFailed = false;

    // Clear callbacks (optional - developer can set them again)
    onPause = null;
    onAbort = null;

    SDKLogger.info('Upload service reset successfully');
  }
}
