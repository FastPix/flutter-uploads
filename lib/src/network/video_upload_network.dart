import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Classification of a single PUT against a GCS resumable session.
///
/// GCS returns:
///   • 200 / 201 → session is finalized
///   • 308       → "Resume Incomplete", with a `Range:` header naming the
///                 byte range the server has actually committed
///   • 4xx       → permanent failure (except 408/429)
///   • 5xx / network drop / timeout → transient, safe to retry after backoff
enum ChunkUploadOutcome {
  /// Any 2xx — the resumable session is finalized. Stop uploading.
  completed,

  /// 308 — server committed bytes up through `serverNextOffset - 1`.
  /// May be less than what we sent (partial commit on flaky links).
  incomplete,

  /// 408 / 429 / 5xx / timeout / connection error — retry after backoff.
  transientFailure,

  /// 4xx (other than 408/429) — do not retry, surface to caller.
  permanentFailure,
}

/// Typed result of an upload PUT or status-query against a GCS resumable
/// session. Replaces the old `Response?` return type so the main uploader
/// doesn't have to peek at status codes / headers itself.
class ChunkUploadResult {
  /// Classification of the response.
  final ChunkUploadOutcome outcome;

  /// On [ChunkUploadOutcome.incomplete], the next byte offset the server
  /// expects (i.e. one past the last byte it has committed). `null` when the
  /// outcome is not `incomplete`. When the server returns 308 with no
  /// `Range:` header it means it has nothing yet, encoded here as `0`.
  final int? serverNextOffset;

  /// HTTP status code (if any).
  final int? statusCode;

  /// Human-readable error description for failure outcomes.
  final String? errorMessage;

  const ChunkUploadResult({
    required this.outcome,
    this.serverNextOffset,
    this.statusCode,
    this.errorMessage,
  });

  @override
  String toString() =>
      'ChunkUploadResult(outcome: $outcome, status: $statusCode, '
      'serverNextOffset: $serverNextOffset, error: $errorMessage)';
}

/// Handles network communication for video uploads against a GCS resumable
/// signed URL.
class VideoUploadNetwork {
  /// PUTs one chunk to the signed URL with the appropriate `Content-Range`
  /// header. Returns a typed [ChunkUploadResult]; throws [DioException] only
  /// for transport-level errors (cancel, timeout, connection error) so the
  /// caller's retry path can classify those.
  static Future<ChunkUploadResult> uploadChunk({
    required String signedUrl,
    required Uint8List chunkBytes,
    required int start,
    required int end,
    required int fileLength,
    required CancelToken cancelToken,
    required void Function(double) onProgress,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration sendTimeout = const Duration(seconds: 120),
    Duration receiveTimeout = const Duration(seconds: 30),
  }) async {
    final dio = Dio()
      ..options.connectTimeout = connectTimeout
      ..options.sendTimeout = sendTimeout
      ..options.receiveTimeout = receiveTimeout;

    final contentRange = 'bytes $start-${end - 1}/$fileLength';

    final response = await dio.put(
      signedUrl,
      data: _buildProgressStream(
        chunkBytes: chunkBytes,
        fileSize: fileLength,
        uploadedBeforeChunk: start,
        onProgress: onProgress,
      ),
      options: Options(
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Range': contentRange,
          'Content-Length': chunkBytes.length,
        },
        // Classify ourselves — we want 4xx/5xx as a Response, not an
        // exception, so the caller can distinguish transient vs permanent.
        validateStatus: (_) => true,
      ),
      cancelToken: cancelToken,
    );
    return _classify(response);
  }

  /// Issues a `PUT` with `Content-Range: bytes */<total>` and an empty body
  /// to ask GCS what bytes it has actually committed for this resumable
  /// session. Used to re-sync the client cursor after any failure/timeout
  /// before re-uploading, so we never resend data the server has already
  /// committed (or worse, skip data it hasn't).
  ///
  /// Returns:
  ///   • [ChunkUploadOutcome.completed] — upload is already finalized
  ///   • [ChunkUploadOutcome.incomplete] — `serverNextOffset` is the cursor
  ///   • [ChunkUploadOutcome.permanentFailure] — session is dead (4xx)
  ///   • [ChunkUploadOutcome.transientFailure] — retry the query
  static Future<ChunkUploadResult> queryUploadStatus({
    required String signedUrl,
    required int fileLength,
    required CancelToken cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final dio = Dio()
      ..options.connectTimeout = timeout
      ..options.sendTimeout = timeout
      ..options.receiveTimeout = timeout;

    final response = await dio.put(
      signedUrl,
      data: const <int>[],
      options: Options(
        headers: {
          'Content-Length': 0,
          'Content-Range': 'bytes */$fileLength',
        },
        validateStatus: (_) => true,
      ),
      cancelToken: cancelToken,
    );
    return _classify(response);
  }

  /// Converts a raw Dio [Response] into a typed [ChunkUploadResult].
  static ChunkUploadResult _classify(Response response) {
    final rangeHeader = _headerValue(response.headers.map, 'range');
    return classifyResponse(response.statusCode ?? 0, rangeHeader);
  }

  /// Pure-function classifier: given an HTTP status code and the value of
  /// the `Range:` response header (or null), returns the typed outcome.
  /// Exposed for unit testing without needing to fake a [Response].
  @visibleForTesting
  static ChunkUploadResult classifyResponse(int status, String? rangeHeader) {
    if (status >= 200 && status < 300) {
      return ChunkUploadResult(
        outcome: ChunkUploadOutcome.completed,
        statusCode: status,
      );
    }

    if (status == 308) {
      // GCS encodes the committed cursor in the `Range:` response header
      // as `bytes=0-<lastCommittedInclusive>`. When the header is absent it
      // means nothing has been committed yet, i.e. next offset = 0.
      final committedEndInclusive = parseRangeHeader(rangeHeader);
      final serverNextOffset =
          committedEndInclusive == null ? 0 : committedEndInclusive + 1;
      return ChunkUploadResult(
        outcome: ChunkUploadOutcome.incomplete,
        statusCode: status,
        serverNextOffset: serverNextOffset,
      );
    }

    // 408 Request Timeout and 429 Too Many Requests are explicitly
    // retryable per spec, as is any 5xx.
    final isTransient =
        status == 408 || status == 429 || (status >= 500 && status < 600);
    return ChunkUploadResult(
      outcome: isTransient
          ? ChunkUploadOutcome.transientFailure
          : ChunkUploadOutcome.permanentFailure,
      statusCode: status,
      errorMessage: 'HTTP $status',
    );
  }

  /// Case-insensitive lookup of a single header value.
  static String? _headerValue(
      Map<String, List<String>> headers, String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value.isEmpty ? null : entry.value.first;
      }
    }
    return null;
  }

  /// Parses a `Range:` header like `bytes=0-1572863` and returns the last
  /// committed byte (inclusive). Returns `null` if the header is missing or
  /// malformed.
  @visibleForTesting
  static int? parseRangeHeader(String? header) {
    if (header == null || header.isEmpty) return null;
    final match = RegExp(r'bytes\s*=\s*(\d+)\s*-\s*(\d+)').firstMatch(header);
    if (match == null) return null;
    return int.tryParse(match.group(2)!);
  }

  /// Builds a progress stream for chunk upload. Slices into 4 KB sub-chunks
  /// purely for progress granularity.
  static Stream<List<int>> _buildProgressStream({
    required Uint8List chunkBytes,
    required int fileSize,
    required int uploadedBeforeChunk,
    required void Function(double) onProgress,
  }) async* {
    final chunkLength = chunkBytes.length;
    const subChunkSize = 4096;
    int uploadedInThisChunk = 0;

    for (int i = 0; i < chunkLength; i += subChunkSize) {
      final end =
          (i + subChunkSize < chunkLength) ? i + subChunkSize : chunkLength;
      // sublistView is zero-copy — important for very large chunks.
      final subChunk = Uint8List.sublistView(chunkBytes, i, end);

      uploadedInThisChunk += subChunk.length;
      final totalUploaded = uploadedBeforeChunk + uploadedInThisChunk;
      final progress = (totalUploaded / fileSize * 100).clamp(0, 100);

      onProgress(progress.toDouble());

      yield subChunk;
    }
  }
}
