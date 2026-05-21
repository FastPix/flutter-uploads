## 2.0.0

### 🚨 Spec correctness — GCS resumable protocol compliance

- **Parse the `Range:` response header on 308 responses.** The client now
  resyncs its cursor to the byte offset GCS actually committed instead of
  blindly advancing to the end of the chunk it sent. Fixes silent data
  corruption on flaky networks where the server partially commits a chunk
  before returning 308.
- **Status-query path (`Content-Range: bytes */<total>`).** After any
  transient failure / timeout / network loss / signed-URL refresh, the SDK
  now asks GCS for its true cursor before re-uploading. Available as
  `_resyncCursorFromServer()` internally and via `refreshSignedUrl(...)`
  publicly.
- **Any 2xx is now terminal success.** Previously only HTTP 200 finalized
  the upload; 201 / 204 fell through to the retry path.
- **Empty trailing chunk guard.** When the local cursor reaches EOF but no
  terminal 2xx has been observed, the SDK queries the server rather than
  PUT-ing a zero-byte (and inverted-Range) request.

### 🔁 Retry policy

- **Real exponential backoff with jitter.** `2s, 4s, 8s, 16s, 30s (cap)`
  with ±25% jitter. Previously linear (`2s, 4s, 6s…`) with no jitter —
  no longer prone to thundering-herd on shared-backend incidents.
- **HTTP-status-aware retry classification.** 4xx (other than 408/429) is
  no longer retried. 408/429/5xx are retried; everything else surfaces as
  a permanent failure.
- **Stop swallowing timeouts and `DioExceptionType.unknown`.** Connection
  errors, send/receive timeouts, and unknown transport faults are now
  classified as transient and routed through the retry path.
- **Retry timers are tracked and cancelled** on `dispose()`, `abortUpload()`,
  and `reset()`. Stray retry callbacks no longer fire into stale state.
- **`DioExceptionType.badCertificate`** is treated as permanent (cert
  pinning / MITM situations should not be retried).

### 🧠 Concurrency / state

- **Pause and abort no longer surface through the error stream.**
  Previously the SDK emitted `UploadError('Upload Paused')` and
  `UploadError('Upload Aborted')` via `onError`, which led consumers to
  treat user-initiated pause as a failure (and disable the Resume button).
  Pause and abort are now communicated only through the dedicated
  `onPause` / `onAbort` callbacks and the progress event with the
  appropriate `UploadStatus`.
- **De-singletoned `VideoUploadProgress`.** Was a process-wide static class
  whose callbacks were overwritten by every new uploader — two concurrent
  uploads in the same app would cross-wire their callbacks. Now per-instance.
- **De-singletoned `VideoUploadRetry`.** Per-instance retry controller
  owns its own pending timer.
- **First-network-event swallow fixed.** The `_isFirstTime` flag no
  longer drops the first connectivity event, so an upload kicked off while
  offline can be auto-resumed when the network returns.

### 📐 API surface (breaking changes — see "Migration" below)

- **`uploadVideo()` now returns a `Future<void>` that actually resolves
  when the upload finalizes** (or rejects with `UploadError` on permanent
  failure / abort). Previously the future resolved immediately after the
  first chunk was scheduled.
- **`progressStream` and `errorStream`** — broadcast streams on the
  uploader for callers that want more than one listener or prefer streams
  over callbacks. The legacy `onProgress` / `onError` callbacks still work.
- **`isUploading()` now honors terminal failure state** — returns false
  after a permanent failure instead of staying true forever.
- **`onUrlRefresh: Future<String> Function()`** — builder hook called
  automatically when the SDK detects an expired signed URL (HTTP
  401 / 403 / 410). Mint a fresh URL and the upload resumes from the
  server's committed cursor against the new URL.
- **`refreshSignedUrl(String)`** — manual / proactive URL replacement on
  the uploader.
- **`.observeAppLifecycle()`** — opt-in builder flag. Attaches a
  `WidgetsBindingObserver` that auto-pauses on background and resumes
  on foreground. Does NOT enable true background uploads (that needs
  platform-level integration), but leaves the resumable session in a
  clean state for when the user returns.
- Builder default `maxRetries` reconciled with the uploader default (both
  now 5). Removed the dead `_builderMaxRetries` field.

### 🧠 Memory / performance

- **Killed the double-copy in `VideoUploadChunker.readFileChunk`.**
  `Uint8List.fromList(raf.read(...))` is replaced with the direct
  `raf.read(...)` return — saves a 16 MB copy per chunk.
- **`Uint8List.sublistView` in the progress stream** in place of
  `sublist`. For a 4 GB upload that's ~1M fewer heap allocations.

### ✅ Tests

- 32 unit tests covering chunker math, file-chunk read edge cases,
  exponential-backoff math (doubling, cap, jitter bounds, never-negative),
  GCS `Range:` header parsing, and HTTP-status classification
  (200 / 201 / 204 / 308 / 308-with-Range / 400 / 403 / 408 / 429 / 500).

### Migration from 1.x

```diff
- final uploader = FlutterResumableUploads.builder()
-     .file(file)
-     .signedUrl(url)
-     .onProgress((p) => ...)
-     .build();
- // upload was fire-and-forget; this returned immediately
- await uploader.uploadVideo();
+ final uploader = FlutterResumableUploads.builder()
+     .file(file)
+     .signedUrl(url)
+     .onProgress((p) => ...)
+     .onUrlRefresh(() => myBackend.mintSignedUrl())  // optional
+     .observeAppLifecycle()                          // optional
+     .build();
+ try {
+   // now actually awaits completion
+   await uploader.uploadVideo();
+ } on UploadError catch (e) {
+   // permanent failure / abort / exhausted retries
+ }
```

- If your code relied on the static `VideoUploadProgress.emitProgress(...)`
  / `VideoUploadProgress.setupCallbacks(...)` access path, switch to
  per-instance methods on `FlutterResumableUploads` (or use the new
  `progressStream` / `errorStream`).

## 1.0.1

### 🔗 Documentation & Homepage URL Update

- Updated `homepage` in `pubspec.yaml` from `https://www.fastpix.io/` to `https://www.fastpix.com/`.
- Updated documentation links in `README.md` (Basic Authentication, Upload media from device) from `docs.fastpix.io` to `docs.fastpix.com`.
- Updated documentation link in the GitHub issue template (`.github/ISSUE_TEMPLATE/question_support.md`) from `docs.fastpix.io` to `docs.fastpix.com`.

## 1.0.0

### 🎉 Initial Release - Flutter Resumable Uploads SDK

A robust Flutter package for uploading large video and audio files with enterprise-grade features.

#### ✨ Core Features

- **Chunked Upload System**: Automatically splits large files into configurable chunks (default 16MB) for reliable uploads
- **Resumable Uploads**: Pause and resume functionality with state persistence across app sessions
- **Network Resilience**: Automatic retry mechanism with configurable retry attempts and delays
- **Advanced Chunk-Level Retry Tracking**: Individual retry tracking per chunk to prevent app sluggishness
- **Real-time Progress Tracking**: Detailed progress updates with chunk-level information and percentage completion
- **Network Monitoring**: Automatic detection of network connectivity changes with smart resume logic
- **Comprehensive Error Handling**: Detailed error reporting with specific error codes and messages
- **Advanced Logging System**: Configurable logging with multiple levels (DEBUG, INFO, WARNING, ERROR)

#### 🏗️ Architecture & Design

- **Builder Pattern**: Clean, fluent API for easy configuration and setup
- **State Management**: Robust state tracking for upload progress, network status, and retry attempts
- **Modular Design**: Well-organized codebase with separate modules for core, network, models, and utilities
- **Memory Efficient**: Proper resource management with dispose and reset capabilities
- **Thread Safe**: Upload lock mechanism to prevent concurrent upload conflicts

#### 🔧 Technical Capabilities

- **File Validation**: Comprehensive file size and format validation
- **Signed URL Support**: Secure uploads using pre-authenticated URLs
- **HTTP Status Handling**: Proper handling of 308 (Partial Content) and 200 (Complete) responses
- **Cancel Token Integration**: Dio-based cancellation for clean upload termination
- **Upload Statistics**: Detailed logging of upload metrics and retry statistics
- **Network Health Monitoring**: Real-time network connectivity monitoring using connectivity_plus

#### 📱 Developer Experience

- **Fluent API**: Easy-to-use builder pattern for configuration
- **Callback System**: Comprehensive callback support for progress, errors, pause, and abort events
- **Debug Information**: Rich debugging capabilities with detailed state information
- **Error Recovery**: Intelligent error handling with automatic retry and manual recovery options
- **Documentation**: Comprehensive documentation with usage examples and best practices

#### 🛠️ Configuration Options

- **Chunk Size**: Configurable chunk size (default: 16MB)
- **Retry Settings**: Customizable retry attempts and delay intervals
- **File Size Limits**: Optional maximum file size validation
- **Logging Control**: Enable/disable logging with custom log levels and tags
- **Network Timeouts**: Configurable network timeout settings

#### 🔒 Security & Reliability

- **Secure Uploads**: Signed URL-based authentication
- **Data Integrity**: Proper chunk validation and error checking
- **Resource Management**: Automatic cleanup and memory management
- **State Persistence**: Upload state tracking for reliable resume functionality

#### 📦 Dependencies

- **dio**: ^5.8.0+1 - HTTP client for network operations
- **connectivity_plus**: ^6.1.4 - Network connectivity monitoring
- **internet_connection_checker**: ^3.0.1 - Internet connection validation

#### 🎯 Use Cases

- Large video file uploads in mobile applications
- Audio file uploads with progress tracking
- Media uploads requiring pause/resume functionality
- Applications requiring network resilience
- Enterprise applications needing detailed upload analytics
