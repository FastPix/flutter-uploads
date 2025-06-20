# Flutter Resumable Uploads SDK

A robust Flutter package for uploading large video and audio files with advanced features like
chunked uploads, pause/resume functionality, network resilience, comprehensive progress tracking,
and detailed logging. Built for reliability and user experience.

## 🚀 Features

### Core Functionality

- **Chunked Uploads**: Automatically splits large video and audio files into manageable chunks (
  configurable size)
- **Resumable Uploads**: Pause and resume uploads from where they left off
- **Network Resilience**: Automatic retry mechanism with configurable retry attempts and delays
- **Chunk-Level Retry Tracking**: Advanced retry system that tracks retries per individual chunk,
  preventing sluggishness and improving upload reliability
- **Real-time Progress Tracking**: Detailed progress updates with chunk-level information
- **Network Monitoring**: Automatic detection of network connectivity changes
- **Error Handling**: Comprehensive error handling with specific error codes and messages
- **Advanced Logging**: Configurable logging system with multiple log levels for debugging and
  monitoring

### Chunk-Level Retry System

The SDK implements an advanced chunk-level retry tracking system that provides several benefits over
traditional global retry counters:

#### Benefits

- **Prevents App Sluggishness**: Each chunk maintains its own retry count, preventing one
  problematic chunk from affecting others
- **Better Error Isolation**: Failed chunks don't impact the retry limits of successful chunks
- **Improved Reliability**: Individual chunk retry tracking allows for more precise error handling
- **Enhanced Monitoring**: Detailed retry statistics per chunk for better debugging

#### How It Works

```dart
// Each chunk maintains its own retry count
Map<int, int> chunkRetryCount = {}; // Track retries per chunk

// Check if a specific chunk should be retried
bool shouldRetryChunk(int chunkIndex) {
  final retries = chunkRetryCount[chunkIndex] ?? 0;
  return retries < maxRetries;
}

// Record a retry attempt for a specific chunk
void recordChunkRetry(int chunkIndex) {
  chunkRetryCount[chunkIndex] = (chunkRetryCount[chunkIndex] ?? 0) + 1;
}
```

#### Retry Statistics

The SDK provides detailed logging of chunk retry statistics:

```
[SDK] DEBUG: Chunk Retry Statistics:
[SDK] DEBUG:   Total Chunks: 16
[SDK] DEBUG:   Max Retries: 5
[SDK] DEBUG:   Retried Chunks: 2
[SDK] DEBUG:     Chunk 3: 2/3 attempts (RETRYING)
[SDK] DEBUG:     Chunk 7: 1/3 attempts (RETRYING)
```

## 📋 Prerequisites

To get started with SDK, you will need a signed URL.
To make API requests, you'll need a valid Access Token and Secret Key. See
the [Basic Authentication](https://docs.fastpix.io/docs/basic-authentication)
Guide for details on retrieving these credentials.

Once you have your credentials, use the [Upload media from device](https://docs.fastpix.io/reference/direct-upload-video-media) API to generate a signed URL for uploading media.

### What is a Signed URL?

A signed URL is a pre-authenticated URL that allows secure, direct uploads to cloud storage
services (like AWS S3, Google Cloud Storage, Azure Blob Storage, etc.) without exposing your storage
credentials in your mobile app.

### Sample Code: Generating Signed URLs

Here are examples of how to generate signed URLs using different backend services:

#### Example 1: Using FastPix API (as shown in the example)

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class SignedUrlService {
  static const String TOKEN_ID = "your_token_id";
  static const String SECRET_KEY = "your_secret_key";
  static const String API_BASE_URL = "https://api.fastpix.app/v1/on-demand/upload";

  Future<String> generateSignedUrl({
    String? corsOrigin = "*",
    Map<String, dynamic>? metadata,
    String accessPolicy = "public",
    String maxResolution = "1080p",
  }) async {
    try {
      // Prepare authentication
      final credentials = '$TOKEN_ID:$SECRET_KEY';
      final auth = 'Basic ${base64.encode(utf8.encode(credentials))}';

      // Prepare request body
      final requestBody = {
        "corsOrigin": corsOrigin,
        "pushMediaSettings": {
          "metadata": metadata ?? {"uploadedBy": "flutter_app"},
          "accessPolicy": accessPolicy,
          "maxResolution": maxResolution,
        },
      };

      // Make API request
      final response = await http.post(
        Uri.parse(API_BASE_URL),
        headers: {
          'Authorization': auth,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 201) {
        return response.body;
      } else {
        throw Exception('Failed to generate signed URL: ${response.reasonPhrase}');
      }
    } catch (e) {
      throw Exception('Error generating signed URL: $e');
    }
  }
}
```

### Integration with Flutter App

Here's how to integrate signed URL generation with the Flutter Resumable Uploads SDK:

```dart
import 'dart:io';
import 'package:fp_resumable_uploads/fp_resumable_uploads.dart';

class UploadService {
  final SignedUrlService _signedUrlService = SignedUrlService();

  Future<void> uploadVideo(File videoFile) async {
    try {
      // Step 1: Generate signed URL
      final signedUrl = await _signedUrlService.generateSignedUrl(
        metadata: {
          'uploadedBy': 'flutter_app',
          'fileType': 'video',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      // Step 2: Configure and start upload
      final uploadService = FlutterResumableUploads.builder()
          .file(videoFile)
          .signedUrl(signedUrl)
          .chunkSize(16 * 1024 * 1024) // 16MB chunks
          .maxRetries(3)
          .enableLogging()
          .onProgress((progress) {
        print('Upload Progress: ${progress.uploadPercentage}%');
      })
          .onError((error) {
        print('Upload Error: ${error.message}');
      })
          .build();

      // Step 3: Start upload
      await uploadService.uploadVideo();
    } catch (e) {
      print('Failed to upload video: $e');
    }
  }
}
```

## 📖 Usage

### Basic Usage with Builder Pattern

```dart
import 'dart:io';
import 'package:fp_resumable_uploads/fp_resumable_uploads.dart';

void uploadVideo() async {
  final uploadService = FlutterResumableUploads.builder()
      .file(File('path/to/video.mp4'))
      .signedUrl('your_signed_url_here')
      .chunkSize(16 * 1024 * 1024) // 16MB chunks
      .maxRetries(3)
      .retryDelay(Duration(milliseconds: 2000))
      .enableLogging() // Enable logging with default settings
      .onProgress((progress) {
    print('Upload Progress: ${progress.uploadPercentage}%');
    print('Current Chunk: ${progress.currentChunkIndex}/${progress.totalChunks}');
    print('Status: ${progress.status}');
  })
      .onError((error) {
    print('Upload Error: ${error.message} (Code: ${error.code})');
  })
      .onPause(() {
    print('Upload paused');
  })
      .onAbort(() {
    print('Upload aborted');
  })
      .build();

  await uploadService.uploadVideo();
}
```

### Advanced Configuration with Custom Logging

```dart
import 'dart:io';
import 'package:fp_resumable_uploads/fp_resumable_uploads.dart';

void advancedUploadExample() async {
  final uploadService = FlutterResumableUploads.builder()
      .file(File('path/to/large_video.mp4'))
      .signedUrl('your_signed_url_here')
      .chunkSize(32 * 1024 * 1024) // 32MB chunks for faster upload
      .maxFileSize(2 * 1024 * 1024 * 1024) // 2GB max file size
      .maxRetries(5) // More retries for unstable connections
      .retryDelay(Duration(seconds: 5)) // Longer delay between retries
      .enableLoggingWithLevel(LogLevel.debug) // Enable debug logging
      .logTag('[MyApp]') // Custom log tag
      .onProgress((progress) {
    // Custom progress handling
    updateUI(progress);
  })
      .onError((error) {
    // Custom error handling
    handleUploadError(error);
  })
      .build();

  // Start upload
  await uploadService.uploadVideo();

  // Control upload flow
  if (uploadService.isPause()) {
    uploadService.pauseUpload();
  }

  // Resume when ready
  uploadService.resumeUpload();

  // Abort if needed
  uploadService.abortUpload();

  // Check upload status
  print('Upload Status: ${uploadService.currentStatus}');
  print('Is Uploading: ${uploadService.isUploading()}');
  print('Is Ready: ${uploadService.isReadyForUpload}');

  // Clean up when done
  uploadService.dispose();
}
```

## 🔍 Logging System

The SDK includes a comprehensive logging system that helps developers debug upload issues and
monitor upload performance.

### Log Levels

The SDK supports multiple log levels to control the verbosity of logging:

| Log Level          | Description                    | Use Case                   |
|--------------------|--------------------------------|----------------------------|
| `LogLevel.none`    | No logging                     | Production builds          |
| `LogLevel.error`   | Only errors                    | Basic error tracking       |
| `LogLevel.warning` | Errors and warnings            | Error and warning tracking |
| `LogLevel.info`    | Errors, warnings, and info     | General monitoring         |
| `LogLevel.debug`   | All messages including debug   | Development debugging      |
| `LogLevel.verbose` | All messages including verbose | Detailed debugging         |

### Enabling Logging

#### Method 1: Using Builder Pattern (Recommended)

```dart

final uploadService = FlutterResumableUploads.builder()
    .file(File('path/to/video.mp4'))
    .signedUrl('your_signed_url_here')
    .enableLogging() // Enable with default INFO level
    .build();
```

#### Method 2: Custom Log Level

```dart

final uploadService = FlutterResumableUploads.builder()
    .file(File('path/to/video.mp4'))
    .signedUrl('your_signed_url_here')
    .enableLoggingWithLevel(LogLevel.debug) // Enable with DEBUG level
    .logTag('[VideoUpload]') // Custom log tag
    .build();
```

#### Method 3: Manual Configuration

```dart
// Configure logger globally
SDKLogger.setEnabled(true);
SDKLogger.setLogLevel(LogLevel.debug);
SDKLogger.setTag('[MyApp]');

// Then use the upload service normally
final uploadService = FlutterResumableUploads.builder()
    .file(File('path/to/video.mp4'))
    .signedUrl('your_signed_url_here'
)
.
build
(
);
```

### What Gets Logged

The logging system provides detailed information about various aspects of the upload process:

#### Upload Configuration

- File path and size
- Chunk size and total chunks
- Retry settings
- Signed URL (truncated for security)

#### Network Status

- Network connectivity changes
- Online/offline status transitions

#### Upload Progress

- Individual chunk upload details
- Byte ranges and progress percentages
- Success/failure status for each chunk

#### Error Handling

- Detailed error messages with stack traces
- Retry attempts and delays
- HTTP status codes and error responses

#### Upload State Changes

- Pause/resume events
- Abort operations
- Upload completion

#### Performance Metrics

- Upload duration
- Average upload speed
- Memory usage (when available)

### Example Log Output

When logging is enabled, you'll see output like this:

```
[MyApp] INFO: Flutter Resumable Uploads SDK initialized
[MyApp] INFO:   Log Level: LogLevel.debug
[MyApp] INFO:   Debug Mode: true
[MyApp] INFO: Upload Configuration:
[MyApp] INFO:   File: /path/to/video.mp4
[MyApp] INFO:   File Size: 256.5 MB
[MyApp] INFO:   Chunk Size: 16.0 MB
[MyApp] INFO:   Total Chunks: 16
[MyApp] INFO:   Max Retries: 3
[MyApp] INFO:   Retry Delay: 2000ms
[MyApp] DEBUG: Chunk Upload: 1/16
[MyApp] DEBUG:   Range: 0 - 16777216
[MyApp] DEBUG:   Size: 16.0 MB
[MyApp] DEBUG:   Progress: 0.0%
[MyApp] DEBUG: Chunk 1 uploaded successfully
[MyApp] INFO: Network Status: ONLINE
[MyApp] INFO: Upload Completed Successfully!
[MyApp] INFO:   Total Chunks: 16
[MyApp] INFO:   Total Bytes: 268.4 MB
[MyApp] INFO:   Duration: 2m 15s
[MyApp] INFO:   Average Speed: 2.0 MB/s
```

### Logger API Reference

#### SDKLogger Class

| Method                        | Description                 |
|-------------------------------|-----------------------------|
| `setEnabled(bool enabled)`    | Enable or disable logging   |
| `setLogLevel(LogLevel level)` | Set the log level           |
| `setTag(String tag)`          | Set custom log tag          |
| `get logLevel`                | Get current log level       |
| `get isEnabled`               | Check if logging is enabled |

#### Logging Methods

| Method                                                           | Description          |
|------------------------------------------------------------------|----------------------|
| `error(String message, [Object? error, StackTrace? stackTrace])` | Log error messages   |
| `warning(String message)`                                        | Log warning messages |
| `info(String message)`                                           | Log info messages    |
| `debug(String message)`                                          | Log debug messages   |
| `verbose(String message)`                                        | Log verbose messages |

#### Specialized Logging Methods

| Method                            | Description                      |
|-----------------------------------|----------------------------------|
| `logUploadConfig(...)`            | Log upload configuration details |
| `logChunkUpload(...)`             | Log chunk upload details         |
| `logNetworkStatus(bool isOnline)` | Log network status changes       |
| `logUploadState(...)`             | Log upload state changes         |
| `logRetryAttempt(...)`            | Log retry attempts               |
| `logUploadCompletion(...)`        | Log upload completion            |
| `logUploadFailure(...)`           | Log upload failures              |
| `logPerformance(...)`             | Log performance metrics          |
| `logSDKInitialization()`          | Log SDK initialization           |

### Best Practices

1. **Development**: Use `LogLevel.debug` or `LogLevel.verbose` for detailed debugging
2. **Testing**: Use `LogLevel.info` to monitor upload behavior
3. **Production**: Use `LogLevel.error` or `LogLevel.none` to minimize overhead
4. **Custom Tags**: Use meaningful tags to identify different upload sessions
5. **Error Handling**: Always check logs when uploads fail for detailed error information

## 🏗️ API Reference

### FlutterResumableUploadsBuilder

The builder class provides a fluent API for configuring uploads:

#### Configuration Methods

| Method                       | Description                   | Default   |
|------------------------------|-------------------------------|-----------|
| `file(File file)`            | Set the video file to upload  | Required  |
| `signedUrl(String url)`      | Set the signed URL for upload | Required  |
| `chunkSize(int bytes)`       | Set chunk size in bytes       | 16MB      |
| `maxFileSize(int bytes)`     | Set maximum allowed file size | No limit  |
| `maxRetries(int count)`      | Set maximum retry attempts    | 3         |
| `retryDelay(Duration delay)` | Set delay between retries     | 2 seconds |

#### Logging Methods

| Method                                   | Description                            |
|------------------------------------------|----------------------------------------|
| `enableLogging()`                        | Enable logging with default INFO level |
| `enableLoggingWithLevel(LogLevel level)` | Enable logging with custom level       |
| `logTag(String tag)`                     | Set custom log tag                     |

#### Callback Methods

| Method                               | Description              |
|--------------------------------------|--------------------------|
| `onProgress(UploadProgressCallback)` | Progress update callback |
| `onError(ErrorCallback)`             | Error handling callback  |
| `onPause(PauseCallback)`             | Pause event callback     |
| `onAbort(AbortCallback)`             | Abort event callback     |

#### Build Methods

| Method             | Description                        |
|--------------------|------------------------------------|
| `build()`          | Create configured upload service   |
| `buildAndUpload()` | Build and start upload immediately |

### FlutterResumableUploads

The main upload service class:

#### Upload Methods

| Method                       | Description                              |
|------------------------------|------------------------------------------|
| `uploadVideo()`              | Start upload using builder configuration |
| `uploadVideoWithParams(...)` | Start upload with direct parameters      |

#### Control Methods

| Method           | Description              |
|------------------|--------------------------|
| `pauseUpload()`  | Pause the current upload |
| `resumeUpload()` | Resume a paused upload   |
| `abortUpload()`  | Abort the current upload |
| `dispose()`      | Clean up resources       |

#### Status Methods

| Method             | Description                    |
|--------------------|--------------------------------|
| `isUploading()`    | Check if upload is in progress |
| `isPause()`        | Check if upload is paused      |
| `isReadyForUpload` | Check if ready to start upload |
| `currentStatus`    | Get current upload status      |

### ProgressModel

The progress model provides detailed upload information:

| Property            | Type   | Description                              |
|---------------------|--------|------------------------------------------|
| `status`            | String | Current upload status                    |
| `uploadPercentage`  | double | Upload completion percentage (0.0-100.0) |
| `currentChunkIndex` | int    | Index of current chunk being uploaded    |
| `totalChunks`       | int    | Total number of chunks                   |
| `chunksUploaded`    | int    | Number of successfully uploaded chunks   |
| `isCompleted`       | bool   | Whether upload is completed              |

### UploadError

Error model with detailed error information:

| Property  | Type   | Description                  |
|-----------|--------|------------------------------|
| `code`    | int    | Error code (100-500)         |
| `message` | String | Human-readable error message |

## 🎯 Benefits

### 1. **Reliability**

- **Automatic Retry**: Built-in retry mechanism handles network failures
- **Network Monitoring**: Detects connectivity changes and adapts accordingly
- **Error Recovery**: Comprehensive error handling with specific error codes
- **State Persistence**: Maintains upload state across app restarts

### 2. **User Experience**

- **Real-time Progress**: Detailed progress updates with chunk-level information
- **Pause/Resume**: Users can pause and resume uploads at any time
- **Background Uploads**: Uploads continue even when app is in background
- **Memory Efficient**: Streams files without loading entire content into memory

### 3. **Developer Experience**

- **Builder Pattern**: Clean, fluent API for easy configuration
- **Type Safety**: Full TypeScript support with proper type definitions
- **Comprehensive Callbacks**: Detailed progress and error callbacks
- **Easy Integration**: Simple setup with minimal configuration required

### 4. **Performance**

- **Chunked Uploads**: Efficient handling of large files
- **Configurable Chunk Size**: Optimize for different network conditions
- **Streaming**: Memory-efficient file processing
- **Concurrent Uploads**: Support for multiple simultaneous uploads

### 5. **Cross-Platform**

- **iOS Support**: Native iOS implementation
- **Android Support**: Native Android implementation
- **Web Support**: Web-compatible implementation
- **Consistent API**: Same API across all platforms

## 📱 Platform Support

- ✅ iOS 12.0+
- ✅ Android API 21+
- ✅ Flutter 1.17.0+

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

If you encounter any issues or have questions:

1. Check the [Issues](https://github.com/FastPix/flutter-uploads/issues) page
2. Create a new issue with detailed information
3. Include your Flutter version, platform, and error logs

## 🔄 Changelog

See [CHANGELOG.md](CHANGELOG.md) for a complete list of changes and version history.
