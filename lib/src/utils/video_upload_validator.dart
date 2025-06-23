import 'dart:io';

import 'package:fastpix_uploads/src/core/video_upload_chunker.dart';
import 'package:fastpix_uploads/src/models/error.dart';
import 'package:fastpix_uploads/src/utils/constants.dart';



/// Handles validation logic for video upload parameters
class VideoUploadValidator {
  /// Validates all upload parameters and returns an error if validation fails
  static UploadError? validateUploadParams({
    required File file,
    required String signedUrl,
    required int chunkSize,
    int? maxFileSize,
  }) {
    // Validate file
    if (!file.existsSync()) {
      return UploadError(
          "We didn't get the file. Did you forget to pass the file to SDK?");
    }

    if (file.lengthSync() <= 0) {
      return UploadError(
          "File is not seems to be readable. Can you check once?");
    }

    // Validate signed URL
    if (signedUrl.isEmpty) {
      return UploadError(
          "We didn't get the signed url. Are you forget to pass the signed url to SDK?");
    }

    // Validate chunk size
    if (!VideoUploadChunker.isValidChunkSize(chunkSize,
        Constants.MINIMUM_CHUNK_SIZE, Constants.MAXIMUM_CHUNK_SIZE)) {
      return UploadError("Chunk size should be between 5mbs and 500mbs.");
    }

    // Validate max file size
    if (maxFileSize != null && maxFileSize < file.lengthSync()) {
      return UploadError("File is larger than provided configuration. "
          "Adjust the file size then try uploading.");
    }

    return null; // No validation errors
  }

  /// Validates that the service is ready for upload
  static UploadError? validateServiceReady({
    required bool isDisposed,
    required bool hasActiveUpload,
    required bool isAborted,
  }) {
    if (isDisposed) {
      return UploadError("Upload service has been disposed");
    }

    if (hasActiveUpload && !isAborted) {
      return UploadError(
          "Upload already in progress. "
              "Call reset() first or abort the current upload.");
    }
    return null; // Service is ready
  }
}
