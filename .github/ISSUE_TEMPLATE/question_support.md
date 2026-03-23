---
name: Question/Support
about: Ask questions or get help with the FastPix Resumable Uploads SDK
title: '[QUESTION] '
labels: ['question', 'needs-triage']
assignees: ''
---

# Question/Support

Thank you for reaching out! We're here to help you with the FastPix Resumable Uploads SDK. Please provide the following information:

## Question Type
- [ ] How to use a specific feature
- [ ] Integration help
- [ ] Configuration question
- [ ] Performance question
- [ ] Troubleshooting help
- [ ] Other: _______________

## Question
**What would you like to know?**

<!-- Please provide a clear, specific question -->

## What You've Tried
**What have you already attempted to solve this?**

```kotlin
import 'package:fp_resumable_uploads/fp_resumable_uploads.dart';
// Your attempted code here
```

## Current Setup
**Describe your current setup:**

## Environment
- **SDK Version**: [e.g., 1.2.2]
- **Android Version**: [e.g., Android 12]
- **Min SDK Version**: [e.g., 24]
- **Target SDK Version**: [e.g., 35]
- **Device/Emulator**: [e.g., Pixel 5, Android Emulator]
- **Player**: [e.g., ExoPlayer 2.19.0, VideoView, etc.]
- **Kotlin Version**: [e.g., 2.0.21]

## Configuration
```dart
// Your current SDK configuration (remove sensitive information)
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

## Expected Outcome
**What are you trying to achieve?**

<!-- Describe your end goal -->

## Error Messages (if any)
```
<!-- If you're getting errors, paste them here -->
```

## Additional Context

### Use Case
**What are you building?**

- [ ] Web application
- [ ] Mobile app (web-based)
- [ ] File upload service
- [ ] Media upload platform
- [ ] Other: _______________


### Timeline
**When do you need this resolved?**

- [ ] ASAP (blocking development)
- [ ] This week
- [ ] This month
- [ ] No rush

### Resources Checked
**What resources have you already checked?**

- [ ] README.md
- [ ] Documentation
- [ ] Examples
- [ ] Stack Overflow
- [ ] GitHub Issues
- [ ] Other: _______________

## Priority
Please indicate the urgency:

- [ ] Critical (Blocking production deployment)
- [ ] High (Blocking development)
- [ ] Medium (Would like to know soon)
- [ ] Low (Just curious)

## Checklist
Before submitting, please ensure:

- [ ] I have provided a clear question
- [ ] I have described what I've tried
- [ ] I have included my current setup
- [ ] I have checked existing documentation
- [ ] I have provided sufficient context

---

**We'll do our best to help you get unstuck! 🚀**

**For urgent issues, please also consider:**
- [FastPix Documentation](https://docs.fastpix.io/)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/fastpix)
- [GitHub Discussions](https://github.com/FastPix/web-uploads-sdk/discussions)
