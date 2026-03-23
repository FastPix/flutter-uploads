---
name: Bug Report
about: Create a report to help us improve
title: '[BUG] '
labels: bug
assignees: ''
---

## Bug Description

A clear and concise description of what the bug is.

## Reproduction Steps

1. **Setup Environment**

```yaml
fp_resumable_uploads: ^X.X.X
```

2. **Code To Reproduce**

```dart
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
```

3. **Expected Behavior**
```
<!-- A clear and concise description of what you expected to happen.  -->
```

4. **Actual Behavior**
```
<!-- A clear and concise description of what actually happened. -->
```

5. **Environment**

- **SDK Version**: [e.g., 1.2.2]
- **Android Version**: [e.g., Android 12]
- **Min SDK Version**: [e.g., 24]
- **Target SDK Version**: [e.g., 35]
- **Device/Emulator**: [e.g., Pixel 5, Android Emulator]
- **Player**: [e.g., ExoPlayer 2.19.0, VideoView, etc.]
- **Kotlin Version**: [e.g., 2.0.21]

## Code Sample

```dart
// Please provide a minimal code sample that reproduces the issue
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
```

## Logs/Stack Trace

```
Paste relevant logs or stack traces here
```

## Additional Context

Add any other context about the problem here.

## Screenshots

If applicable, add screenshots to help explain your problem.

