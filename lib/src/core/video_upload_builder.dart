import 'dart:io';

import 'package:fastpix_uploads/src/models/error.dart';
import 'package:fastpix_uploads/src/models/progress_model.dart';
import 'package:fastpix_uploads/src/utils/logger.dart';
import 'package:fastpix_uploads/src/flutter_uploads_sdk.dart';


/// Type alias for progress callback
typedef UploadProgressCallback = void Function(ProgressModel progress);

/// Type alias for error callback
typedef ErrorCallback = void Function(UploadError error);

/// Type alias for pause callback
typedef PauseCallback = void Function();

/// Type alias for abort callback
typedef AbortCallback = void Function();

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
  int _maxRetries = 3;
  Duration _retryDelay = const Duration(milliseconds: 2000);

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
