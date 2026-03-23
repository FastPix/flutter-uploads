# FastPix Resumable Uploads SDK - Documentation PR

## Documentation Changes

### What Changed
- [ ] New documentation added
- [ ] Existing documentation updated
- [ ] Documentation errors fixed
- [ ] Code examples updated
- [ ] Links and references updated

### Files Modified
- [ ] README.md
- [ ] docs/ files
- [ ] USAGE.md
- [ ] CONTRIBUTING.md
- [ ] Other: _______________

### Summary
**Brief description of changes:**

<!-- What documentation was added, updated, or fixed? -->

### Code Examples
```dart 
// If you added/updated code examples, include them here
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

### Testing
- [ ] All code examples tested
- [ ] Links verified
- [ ] Grammar checked
- [ ] Formatting consistent

### Review Checklist
- [ ] Content is accurate
- [ ] Code examples work
- [ ] Links are working
- [ ] Grammar is correct
- [ ] Formatting is consistent

---

**Ready for review!**
