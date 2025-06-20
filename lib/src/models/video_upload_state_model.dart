import 'dart:async';
import 'dart:io';

/// A class representing the state of video upload operation.
class VideoUploadState {
  /// The timer used for checking internet connectivity or other periodic tasks.
  Timer? timer;

  /// The video file to be uploaded.
  File? video;

  int chunkOffset = 0;

  int chunkCount = 0;

  int successiveChunkCount = 0;

  int nextChunkRangeStart = 0;

  int fileLength = 0;

  String? gcsSignedUrl;

  /// The size of each chunk in bytes. Defaults to 5 MB.
  int chunkSize = 5 * 1024 * 1024;

  /// The unique identifier for the upload session.
  String? uploadId;

  /// The name of the object being uploaded.
  String? objectName;

  /// Indicates whether the upload is paused.
  bool isPaused = false;

  bool isOffline = false;

  bool isFirstTime = true;

  bool isAborted = false;

  bool isCompleted = false;

  bool isInitialized = false;

  int failedChunkRetried = 0;

  int maxRetries = 5;

  /// The index of the chunk where the upload was paused, if any.
  int? pausedChunkIndex;

  int totalChunks = 0;

  bool isOnlyChunk = false;

  /// Upload lock to prevent multiple concurrent uploads
  bool _isUploading = false;

  /// Track retries per chunk to avoid sluggishness
  Map<int, int> chunkRetryCount = {};

  /// Getter for upload lock status
  bool get isUploading => _isUploading;

  /// Set upload lock status
  void setUploading(bool uploading) {
    _isUploading = uploading;
  }

  /// Try to acquire upload lock - returns true if successful, false if already locked
  bool tryAcquireUploadLock() {
    if (_isUploading) {
      return false;
    }
    _isUploading = true;
    return true;
  }

  /// Release upload lock
  void releaseUploadLock() {
    _isUploading = false;
  }

  /// Check if a specific chunk should be retried
  bool shouldRetryChunk(int chunkIndex) {
    final retries = chunkRetryCount[chunkIndex] ?? 0;
    return retries < maxRetries;
  }

  /// Record a retry attempt for a specific chunk
  void recordChunkRetry(int chunkIndex) {
    chunkRetryCount[chunkIndex] = (chunkRetryCount[chunkIndex] ?? 0) + 1;
  }

  /// Get the current retry count for a specific chunk
  int getChunkRetryCount(int chunkIndex) {
    return chunkRetryCount[chunkIndex] ?? 0;
  }

  /// Check if a specific chunk has exceeded max retries
  bool hasChunkExceededMaxRetries(int chunkIndex) {
    return getChunkRetryCount(chunkIndex) >= maxRetries;
  }

  /// Reset retry count for a specific chunk
  void resetChunkRetryCount(int chunkIndex) {
    chunkRetryCount.remove(chunkIndex);
  }

  /// Reset all chunk retry counts
  void resetAllChunkRetryCounts() {
    chunkRetryCount.clear();
  }

  /// Creates an instance of [VideoUploadState].
  ///
  /// [signedUrl] - The signed URL for uploading the video.
  /// [timer] - The timer used for periodic tasks.
  /// [video] - The video file to be uploaded.
  /// [chunksSignedUrls] - A list of signed URLs for each chunk.
  /// [chunkSize] - The size of each chunk in bytes. Defaults to 5 MB.
  /// [uploadId] - The unique identifier for the upload session.
  /// [objectName] - The name of the object being uploaded.
  /// [isPaused] - Indicates if the upload is paused.
  /// [pausedChunkIndex] - The index of the chunk where the upload was paused, if any.
  VideoUploadState({
    this.timer,
    this.video,
    this.chunkSize = 5 * 1024 * 1024,
    this.uploadId,
    this.objectName,
    this.isPaused = false,
    this.pausedChunkIndex,
  });

  void clearAll() {
    timer = null;
    uploadId = null;
    objectName = null;
    pausedChunkIndex = null;

    // Reset retry and state variables
    chunkOffset = 0;
    chunkCount = 0;
    successiveChunkCount = 0;
    nextChunkRangeStart = 0;
    gcsSignedUrl = null;
    isPaused = false;
    isOffline = false;
    isFirstTime = true;
    isAborted = false;
    isCompleted = false;
    isInitialized = false;
    failedChunkRetried = 0;
    totalChunks = 0;
    isOnlyChunk = false;

    // Reset chunk retry tracking
    resetAllChunkRetryCounts();

    // Reset upload lock
    releaseUploadLock();
  }
}
