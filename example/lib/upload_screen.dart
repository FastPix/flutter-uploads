import 'dart:io';

import 'package:fastpix_resumable_uploader/fastpix_resumable_uploader.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'signed_url_service.dart';

/// Replace these with your own FastPix credentials before running the example.
/// See https://docs.fastpix.com/docs/basic-authentication
const String _kFastPixTokenId = '3d319224-5592-433f-9ab6-e5180e3f3197';
const String _kFastPixSecretKey = 'b6ab7dad-e1f2-4701-a847-ae4f40f12f1d';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final ImagePicker _picker = ImagePicker();
  final SignedUrlService _signedUrlService = SignedUrlService(
    tokenId: _kFastPixTokenId,
    secretKey: _kFastPixSecretKey,
  );

  FlutterResumableUploads? _uploader;

  File? _selectedFile;
  String _status = 'Pick a video to get started.';
  double _progress = 0.0;
  int _currentChunk = 0;
  int _totalChunks = 0;
  bool _isBusy = false;
  bool _isPaused = false;
  bool _isCompleted = false;
  String? _errorMessage;

  @override
  void dispose() {
    _uploader?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() {
      _selectedFile = File(picked.path);
      _status = 'Selected: ${picked.name}';
      _progress = 0.0;
      _currentChunk = 0;
      _totalChunks = 0;
      _isCompleted = false;
      _errorMessage = null;
    });
  }

  Future<void> _startUpload() async {
    final file = _selectedFile;
    if (file == null) return;

    setState(() {
      _isBusy = true;
      _isPaused = false;
      _isCompleted = false;
      _errorMessage = null;
      _status = 'Requesting signed URL…';
    });

    try {
      final signedUrl = await _signedUrlService.generateSignedUrl(
        metadata: {
          'fileName': file.uri.pathSegments.last,
          'uploadedBy': 'flutter_example_app',
        },
      );

      // Dispose any previous run before starting a new one.
      _uploader?.dispose();

      _uploader = FlutterResumableUploads.builder()
          .file(file)
          .signedUrl(signedUrl)
          .chunkSize(16 * 1024 * 1024) // 16 MB
          .maxRetries(5)
          .retryDelay(const Duration(seconds: 2))
          .enableLoggingWithLevel(LogLevel.info)
          .onProgress(_handleProgress)
          .onError(_handleError)
          .onPause(() => _updateStatus('Upload paused'))
          .onAbort(() => _updateStatus('Upload aborted'))
          .build();

      // uploadVideo() now resolves only when the upload reaches a terminal
      // state (completed or permanently failed). Any transient errors
      // surface through onError but the future stays alive.
      try {
        await _uploader!.uploadVideo();
      } catch (e) {
        // Terminal failure — set busy=false here, not in onError.
        if (mounted) {
          setState(() {
            _errorMessage = e is UploadError ? e.message : e.toString();
            _isBusy = false;
            _isPaused = false;
          });
        }
        return;
      }

      // Terminal success.
      if (mounted) {
        setState(() {
          _isBusy = false;
          _isPaused = false;
        });
      }
    } catch (e) {
      // Synchronous setup failure (signed-URL fetch, builder validation).
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isBusy = false;
          _isPaused = false;
        });
      }
    }
  }

  void _handleProgress(ProgressModel progress) {
    if (!mounted) return;
    setState(() {
      _status = progress.status;
      _progress = progress.uploadPercentage;
      _currentChunk = progress.currentChunkIndex;
      _totalChunks = progress.totalChunks;
      _isCompleted = progress.isCompleted;
      if (_isCompleted) {
        _isBusy = false;
        _progress = 100.0;
      }
    });
  }

  void _handleError(UploadError error) {
    if (!mounted) return;
    // The error stream emits both transient ("retrying chunk 3…") and
    // terminal errors. Only update the displayed message here — the
    // session's busy/paused state is driven by the uploadVideo() future
    // (terminal) and the pause/resume buttons (user-initiated).
    setState(() {
      _errorMessage = error.message;
    });
  }

  void _updateStatus(String status) {
    if (!mounted) return;
    setState(() => _status = status);
  }

  void _pauseOrResume() {
    final uploader = _uploader;
    if (uploader == null) return;
    if (_isPaused) {
      uploader.resumeUpload();
      setState(() => _isPaused = false);
    } else {
      uploader.pauseUpload();
      setState(() => _isPaused = true);
    }
  }

  void _abort() {
    _uploader?.abortUpload();
    setState(() {
      _isBusy = false;
      _isPaused = false;
      _progress = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = _selectedFile != null;
    final canControl = _isBusy && !_isCompleted;

    return Scaffold(
      appBar: AppBar(
        title: const Text('FastPix Resumable Uploader'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FileCard(file: _selectedFile),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _isBusy ? null : _pickVideo,
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('Pick video from gallery'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: (hasFile && !_isBusy) ? _startUpload : null,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Upload to FastPix'),
            ),
            const SizedBox(height: 24),
            LinearProgressIndicator(
              value: _progress == 0 ? 0 : (_progress / 100).clamp(0.0, 1.0),
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            Text(
              '${_progress.toStringAsFixed(1)}%'
              '${_totalChunks > 0 ? '   •   chunk $_currentChunk / $_totalChunks' : ''}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              _status,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canControl ? _pauseOrResume : null,
                    icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                    label: Text(_isPaused ? 'Resume' : 'Pause'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canControl ? _abort : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Abort'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
            if (_isCompleted) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Expanded(child: Text('Upload completed successfully.')),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.file});

  final File? file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            file == null ? Icons.movie_outlined : Icons.movie,
            size: 36,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file == null ? 'No file selected' : file!.uri.pathSegments.last,
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  file == null
                      ? 'Pick a video to upload it to FastPix.'
                      : '${(file!.lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
