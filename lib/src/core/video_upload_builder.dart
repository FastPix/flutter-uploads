import 'dart:io';

import 'package:fastpix_resumable_uploader/fastpix_resumable_uploader.dart';


/// Type alias for progress callback
typedef UploadProgressCallback = void Function(ProgressModel progress);

/// Type alias for error callback
typedef ErrorCallback = void Function(UploadError error);

/// Type alias for pause callback
typedef PauseCallback = void Function();

/// Type alias for abort callback
typedef AbortCallback = void Function();

/// Asynchronous callback the SDK invokes when it detects the signed URL has
/// expired (typically a 403/410 from GCS). The caller is expected to mint a
/// fresh signed URL (usually by hitting their backend) and return it. The
/// SDK then resumes the upload against the new URL from the server's
/// committed cursor.
typedef SignedUrlRefreshCallback = Future<String> Function();

/// Builder class for configuring FlutterResumableUploads
class FlutterResumableUploadsBuilder {
  File? _file;
  String? _signedUrl;
  int _chunkSize = 16 * 1024 * 1024; // 16MB default
  int? _maxFileSize;
  UploadProgressCallback? _onProgress;
  ErrorCallback? _onError;
  PauseCallback? _onPause;
  AbortCallback? _onAbort;
  SignedUrlRefreshCallback? _onUrlRefresh;
  // Default kept in sync with FlutterResumableUploads.configureParams.
  int _maxRetries = 5;
  Duration _retryDelay = const Duration(milliseconds: 2000);

  /// Whether to attach a Flutter `WidgetsBindingObserver` that auto-pauses
  /// the upload on app backgrounding and auto-resumes on foreground.
  bool _observeAppLifecycle = false;

  // Logging parameters
  bool _enableLogging = false;
  LogLevel _logLevel = LogLevel.info;
  String _logTag = '[FlutterResumableUploads]';

  /// Set the video file to upload
  FlutterResumableUploadsBuilder file(File file) {
    _file = file;
    return this;
  }

  /// Set the signed URL for upload
  FlutterResumableUploadsBuilder signedUrl(String signedUrl) {
    _signedUrl = signedUrl;
    return this;
  }

  /// Set the chunk size in bytes (default: 16MB)
  FlutterResumableUploadsBuilder chunkSize(int chunkSize) {
    _chunkSize = chunkSize;
    return this;
  }

  /// Set the maximum file size allowed
  FlutterResumableUploadsBuilder maxFileSize(int maxFileSize) {
    _maxFileSize = maxFileSize;
    return this;
  }

  /// Set the progress callback
  FlutterResumableUploadsBuilder onProgress(UploadProgressCallback onProgress) {
    _onProgress = onProgress;
    return this;
  }

  /// Set the error callback
  FlutterResumableUploadsBuilder onError(ErrorCallback onError) {
    _onError = onError;
    return this;
  }

  /// Set the pause callback
  FlutterResumableUploadsBuilder onPause(PauseCallback onPause) {
    _onPause = onPause;
    return this;
  }

  /// Set the abort callback
  FlutterResumableUploadsBuilder onAbort(AbortCallback onAbort) {
    _onAbort = onAbort;
    return this;
  }

  /// Register a callback the SDK will invoke when the signed URL appears
  /// to have expired (HTTP 403 / 410). Return a freshly-minted URL for the
  /// *same* GCS resumable session; the upload resumes from the server's
  /// committed cursor against the new URL.
  ///
  /// If unset, an expired-URL response surfaces as a permanent failure.
  FlutterResumableUploadsBuilder onUrlRefresh(
      SignedUrlRefreshCallback callback) {
    _onUrlRefresh = callback;
    return this;
  }

  /// Set the maximum number of retry attempts
  FlutterResumableUploadsBuilder maxRetries(int maxRetries) {
    _maxRetries = maxRetries;
    return this;
  }

  /// Set the retry delay duration
  FlutterResumableUploadsBuilder retryDelay(Duration retryDelay) {
    _retryDelay = retryDelay;
    return this;
  }

  /// When enabled, the SDK attaches a `WidgetsBindingObserver` and
  /// auto-pauses the upload when the app is backgrounded (and auto-resumes
  /// on foreground). This does NOT enable true background uploads — it
  /// just leaves the resumable session in a clean state for when the app
  /// returns. Off by default; opt in for a better UX on flaky mobile
  /// foregrounding.
  FlutterResumableUploadsBuilder observeAppLifecycle(
      [bool enabled = true]) {
    _observeAppLifecycle = enabled;
    return this;
  }

  /// Enable logging with default settings (INFO level)
  FlutterResumableUploadsBuilder enableLogging() {
    _enableLogging = true;
    return this;
  }

  /// Enable logging with custom log level
  FlutterResumableUploadsBuilder enableLoggingWithLevel(LogLevel level) {
    _enableLogging = true;
    _logLevel = level;
    return this;
  }

  /// Set custom log tag
  FlutterResumableUploadsBuilder logTag(String tag) {
    _logTag = tag;
    return this;
  }

  /// Build and return a configured FlutterResumableUploads instance
  FlutterResumableUploads build() {
    if (_file == null) {
      throw ArgumentError('File is required. Use file() method to set it.');
    }
    if (_signedUrl == null || _signedUrl!.isEmpty) {
      throw ArgumentError(
          'Signed URL is required. Use signedUrl() method to set it.');
    }

    // Configure logger if enabled
    if (_enableLogging) {
      SDKLogger.setEnabled(true);
      SDKLogger.setLogLevel(_logLevel);
      SDKLogger.setTag(_logTag);
      SDKLogger.logSDKInitialization();
    }

    final uploadService = FlutterResumableUploads();

    // Set callbacks
    uploadService.onPause = _onPause;
    uploadService.onAbort = _onAbort;
    uploadService.onError = _onError;
    uploadService.onUrlRefresh = _onUrlRefresh;

    if (_observeAppLifecycle) {
      uploadService.enableAppLifecycleObserver();
    }

    // Configure the upload service with builder parameters
    uploadService.configureParams(
      file: _file!,
      signedUrl: _signedUrl!,
      chunkSize: _chunkSize,
      maxFileSize: _maxFileSize,
      onProgress: _onProgress,
      onError: _onError,
      maxRetries: _maxRetries,
      retryDelay: _retryDelay,
    );

    return uploadService;
  }

  /// Build and start the upload immediately
  Future<FlutterResumableUploads> buildAndUpload() async {
    final uploadService = build();
    await uploadService.uploadVideo();
    return uploadService;
  }
}
