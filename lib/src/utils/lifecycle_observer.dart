import 'package:flutter/widgets.dart';

import '../fastpix_resumable_uploader.dart';
import 'logger.dart';

/// Bridges Flutter's app lifecycle (foreground / background) to the
/// uploader so that going to the background pauses the upload and returning
/// to the foreground resumes it.
///
/// Why: on iOS, when the app is backgrounded the OS suspends the Dart
/// isolate within ~30 seconds. An in-flight `Dio.put()` will be killed and
/// the SDK has no way to learn about it — it just looks like a hang. By
/// proactively pausing on `AppLifecycleState.paused` we leave the upload
/// session in a clean resumable state, then re-issue the chunk PUT when
/// the user comes back. The same logic helps on Android when the process
/// is throttled or moved to cached state.
///
/// This does NOT enable true background uploads (URLSession background
/// config on iOS, WorkManager on Android) — those require platform-level
/// integration outside the scope of a pure-Dart SDK. Opt in if you want
/// the SDK to gracefully pause on backgrounding; otherwise the upload
/// will fail / time out and rely on retries on resume.
class UploadLifecycleObserver with WidgetsBindingObserver {
  UploadLifecycleObserver(this._uploader);

  final FlutterResumableUploads _uploader;

  /// True only when the observer itself triggered the pause — used so we
  /// don't resume an upload the user paused manually before backgrounding.
  bool _autoPaused = false;

  bool _attached = false;

  /// Attaches to [WidgetsBinding]. Safe to call before `runApp()` runs —
  /// in that (unusual) case we log and no-op rather than throw.
  void attach() {
    if (_attached) return;
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    _attached = true;
    SDKLogger.debug('UploadLifecycleObserver attached');
  }

  /// Detaches from [WidgetsBinding]. Idempotent.
  void detach() {
    if (!_attached) return;
    WidgetsBinding.instance.removeObserver(this);
    _attached = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // We only auto-pause an upload that is *currently* active and not
        // already paused — otherwise we'd flip `_autoPaused = true` for an
        // already-paused state and incorrectly resume it on foreground.
        if (_uploader.isUploading() && !_uploader.isPause()) {
          SDKLogger.info(
              'App backgrounded — auto-pausing upload (lifecycle: $state)');
          _autoPaused = true;
          _uploader.pauseUpload();
        }
        break;

      case AppLifecycleState.resumed:
        if (_autoPaused) {
          SDKLogger.info('App foregrounded — resuming auto-paused upload');
          _autoPaused = false;
          _uploader.resumeUpload();
        }
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // No action — `inactive` fires for transient interruptions (e.g.
        // phone call sheet) and pausing on that is too aggressive.
        // `detached` means the engine is about to be destroyed; the
        // uploader will be disposed by the owning code anyway.
        break;
    }
  }
}
