import 'package:flutter/foundation.dart';

/// Log levels for the SDK logger
enum LogLevel {
  /// No logging
  none,

  /// Only errors
  error,

  /// Errors and warnings
  warning,

  /// Errors, warnings, and info messages
  info,

  /// All messages including debug
  debug,

  /// All messages including verbose debug
  verbose,
}

/// A comprehensive logger for the Flutter Resumable Uploads SDK
class SDKLogger {
  static LogLevel _logLevel = LogLevel.none;
  static bool _isEnabled = false;
  static String _tag = '[FlutterResumableUploads]';

  /// Enable or disable logging
  static void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  /// Set the log level
  static void setLogLevel(LogLevel level) {
    _logLevel = level;
  }

  /// Set a custom tag for log messages
  static void setTag(String tag) {
    _tag = tag;
  }

  /// Get current log level
  static LogLevel get logLevel => _logLevel;

  /// Check if logging is enabled
  static bool get isEnabled => _isEnabled;

  /// Log an error message
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (!_isEnabled || _logLevel == LogLevel.none) return;

    final logMessage = '$_tag ERROR: $message';

    if (kDebugMode) {
      print(logMessage);
      if (error != null) {
        print('$_tag Error details: $error');
      }
      if (stackTrace != null) {
        print('$_tag Stack trace: $stackTrace');
      }
    }
  }

  /// Log a warning message
  static void warning(String message) {
    if (!_isEnabled || _logLevel.index < LogLevel.warning.index) return;

    final logMessage = '$_tag WARNING: $message';

    if (kDebugMode) {
      print(logMessage);
    }
  }

  /// Log an info message
  static void info(String message) {
    if (!_isEnabled || _logLevel.index < LogLevel.info.index) return;

    final logMessage = '$_tag INFO: $message';

    if (kDebugMode) {
      print(logMessage);
    }
  }

  /// Log a debug message
  static void debug(String message) {
    if (!_isEnabled || _logLevel.index < LogLevel.debug.index) return;

    final logMessage = '$_tag DEBUG: $message';

    if (kDebugMode) {
      print(logMessage);
    }
  }

  /// Log a verbose debug message
  static void verbose(String message) {
    if (!_isEnabled || _logLevel.index < LogLevel.verbose.index) return;

    final logMessage = '$_tag VERBOSE: $message';

    if (kDebugMode) {
      print(logMessage);
    }
  }

  /// Log upload configuration details
  static void logUploadConfig({
    required String filePath,
    required int fileSize,
    required int chunkSize,
    required int totalChunks,
    required int maxRetries,
    required Duration retryDelay,
    String? signedUrl,
  }) {
    if (!_isEnabled || _logLevel.index < LogLevel.info.index) return;

    if (kDebugMode) {
      print('$_tag INFO: Upload Configuration:');
      print('$_tag INFO:   File: $filePath');
      print('$_tag INFO:   File Size: ${_formatBytes(fileSize)}');
      print('$_tag INFO:   Chunk Size: ${_formatBytes(chunkSize)}');
      print('$_tag INFO:   Total Chunks: $totalChunks');
      print('$_tag INFO:   Max Retries: $maxRetries');
      print('$_tag INFO:   Retry Delay: ${retryDelay.inMilliseconds}ms');
      if (signedUrl != null) {
        print(
            '$_tag VERBOSE:   Signed URL: ${signedUrl.substring(0, signedUrl.length > 100 ? 100 : signedUrl.length)}${signedUrl.length > 100 ? '...' : ''}');
      }
    }
  }

  /// Log chunk upload details
  static void logChunkUpload({
    required int chunkIndex,
    required int totalChunks,
    required int chunkSize,
    required int startByte,
    required int endByte,
    required double progress,
  }) {
    if (!_isEnabled || _logLevel.index < LogLevel.debug.index) return;

    if (kDebugMode) {
      print('$_tag DEBUG: Chunk Upload: $chunkIndex/$totalChunks');
      print('$_tag DEBUG:   Range: $startByte - $endByte');
      print('$_tag DEBUG:   Size: ${_formatBytes(chunkSize)}');
      print('$_tag DEBUG:   Progress: ${progress.toStringAsFixed(1)}%');
    }
  }

  /// Log network status changes
  static void logNetworkStatus(bool isOnline) {
    if (!_isEnabled || _logLevel.index < LogLevel.info.index) return;

    if (kDebugMode) {
      print('$_tag INFO: Network Status: ${isOnline ? 'ONLINE' : 'OFFLINE'}');
    }
  }

  /// Log upload state changes
  static void logUploadState({
    required bool isPaused,
    required bool isAborted,
    required bool isCompleted,
    required bool isOffline,
    required int currentChunk,
    required int totalChunks,
  }) {
    if (!_isEnabled || _logLevel.index < LogLevel.debug.index) return;

    if (kDebugMode) {
      print('$_tag DEBUG: Upload State:');
      print('$_tag DEBUG:   Paused: $isPaused');
      print('$_tag DEBUG:   Aborted: $isAborted');
      print('$_tag DEBUG:   Completed: $isCompleted');
      print('$_tag DEBUG:   Offline: $isOffline');
      print('$_tag DEBUG:   Progress: $currentChunk/$totalChunks');
    }
  }

  /// Log retry attempts
  static void logRetryAttempt({
    required int chunkIndex,
    required int attemptNumber,
    required int maxRetries,
    required String error,
    required Duration delay,
  }) {
    if (!_isEnabled || _logLevel.index < LogLevel.warning.index) return;

    if (kDebugMode) {
      print(
          '$_tag WARNING: Retry Attempt: Chunk $chunkIndex, Attempt $attemptNumber/$maxRetries');
      print('$_tag WARNING:   Error: $error');
      print('$_tag WARNING:   Retry Delay: ${delay.inMilliseconds}ms');
    }
  }

  /// Log chunk retry statistics
  static void logChunkRetryStatistics({
    required Map<int, int> chunkRetryCount,
    required int totalChunks,
    required int maxRetries,
  }) {
    if (!_isEnabled || _logLevel.index < LogLevel.debug.index) return;

    if (kDebugMode) {
      print('$_tag DEBUG: Chunk Retry Statistics:');
      print('$_tag DEBUG:   Total Chunks: $totalChunks');
      print('$_tag DEBUG:   Max Retries: $maxRetries');

      if (chunkRetryCount.isEmpty) {
        print('$_tag DEBUG:   No chunks have been retried');
        return;
      }

      final retriedChunks = chunkRetryCount.keys.toList()..sort();
      print('$_tag DEBUG:   Retried Chunks: ${retriedChunks.length}');

      for (final chunkIndex in retriedChunks) {
        final retryCount = chunkRetryCount[chunkIndex]!;
        final status = retryCount >= maxRetries ? 'FAILED' : 'RETRYING';
        print(
            '$_tag DEBUG:     Chunk $chunkIndex: $retryCount/$maxRetries attempts ($status)');
      }
    }
  }

  /// Log upload completion
  static void logUploadCompletion({
    required int totalChunks,
    required int totalBytes,
    required Duration duration,
  }) {
    if (!_isEnabled || _logLevel.index < LogLevel.info.index) return;

    if (kDebugMode) {
      print('$_tag INFO: Upload Completed Successfully!');
      print('$_tag INFO: Total Chunks: $totalChunks');
      print('$_tag INFO: Total Bytes: ${_formatBytes(totalBytes)}');
      print('$_tag INFO: Duration: ${_formatDuration(duration)}');
    }
  }

  /// Log upload failure
  static void logUploadFailure({
    required String error,
    required int currentChunk,
    required int totalChunks,
    Object? exception,
  }) {
    if (!_isEnabled || _logLevel.index < LogLevel.error.index) return;

    if (kDebugMode) {
      print('$_tag ERROR: Upload Failed!');
      print('$_tag ERROR: Error: $error');
      print('$_tag ERROR: Failed at chunk: $currentChunk/$totalChunks');
      if (exception != null) {
        print('$_tag ERROR: Exception: $exception');
      }
    }
  }

  /// Log performance metrics
  static void logPerformance({
    required String operation,
    required Duration duration,
    Map<String, dynamic>? additionalData,
  }) {
    if (!_isEnabled || _logLevel.index < LogLevel.debug.index) return;

    if (kDebugMode) {
      print(
          '$_tag DEBUG: Performance: $operation took ${_formatDuration(duration)}');
      if (additionalData != null) {
        additionalData.forEach((key, value) {
          print('$_tag DEBUG:   $key: $value');
        });
      }
    }
  }

  /// Format bytes to human readable format
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Format duration to human readable format
  static String _formatDuration(Duration duration) {
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}s';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inHours}h ${duration.inMinutes % 60}m ${duration.inSeconds % 60}s';
    }
  }

  /// Log memory usage (if available)
  static void logMemoryUsage() {
    if (!_isEnabled || _logLevel.index < LogLevel.verbose.index) return;

    if (kDebugMode) {
      print(
          '$_tag VERBOSE: Memory usage logging not implemented in this version');
    }
  }

  /// Log SDK initialization
  static void logSDKInitialization() {
    if (!_isEnabled || _logLevel.index < LogLevel.info.index) return;

    if (kDebugMode) {
      print('$_tag INFO: Flutter Resumable Uploads SDK initialized');
      print('$_tag INFO: Log Level: $_logLevel');
      print('$_tag INFO: Debug Mode: $kDebugMode');
    }
  }
}
