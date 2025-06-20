import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_uploads_sdk/src/utils/logger.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

class NetworkHandler {
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Function(bool isOnline)? onStatusChange;
  bool? _lastStatus;
  bool _isDisposed = false;

  /// Debounce timer to prevent rapid network change callbacks
  Timer? _debounceTimer;

  /// Stability check timer to ensure network is stable before reporting
  Timer? _stabilityTimer;

  /// Minimum time to wait before considering network stable
  static const Duration _stabilityDelay = Duration(seconds: 2);

  /// Debounce delay for network changes
  static const Duration _debounceDelay = Duration(milliseconds: 500);

  /// Reactive notifier for current connectivity status
  /// Start with null to indicate unknown state
  final ValueNotifier<bool?> isConnected = ValueNotifier<bool?>(null);

  /// Initialize and start monitoring network state
  Future<void> startMonitoring(
      {required Function(bool isOnline) onChange}) async {
    onStatusChange = onChange;
    // Check initial connection status
    try {
      final initialStatus = await _checkConnection();
      _updateStatus(initialStatus);
    } catch (e) {
      // If initial check fails, assume offline
      _updateStatus(false);
    }

    // Listen for connectivity changes
    _subscription =
        _connectivity.onConnectivityChanged.listen((connectivityResults) async {
      _handleConnectivityChange();
    }, onError: (error) {
      SDKLogger.error(error);
    });
  }

  /// Handle connectivity changes with debouncing and stability checks
  void _handleConnectivityChange() {
    // Cancel existing timers
    _debounceTimer?.cancel();
    _stabilityTimer?.cancel();

    // Debounce the network check
    _debounceTimer = Timer(_debounceDelay, () async {
      try {
        // Always trigger stability timer for network changes, regardless of status
        // This ensures we don't miss rapid network switches
        _stabilityTimer = Timer(_stabilityDelay, () async {
          // Do a final check to ensure we have the most current status
          try {
            final finalStatus = await _checkConnection();
            _updateStatus(finalStatus, force: true);
          } catch (e) {
            _updateStatus(false, force: true);
          }
        });
      } catch (e) {
        // If check fails, assume offline after stability delay
        _stabilityTimer = Timer(_stabilityDelay, () {
          _updateStatus(false);
        });
      }
    });
  }

  Future<bool> _checkConnection() async {
    try {
      return await InternetConnectionChecker.instance.hasConnection;
    } catch (e) {
      rethrow;
    }
  }

  /// Update status only when it changes
  void _updateStatus(bool currentStatus, {bool force = false}) {
    // Always update if status is null (first time) or if status actually changed
    if (_lastStatus == null || _lastStatus != currentStatus || force) {
      _lastStatus = currentStatus;
      isConnected.value = currentStatus;
      onStatusChange?.call(currentStatus);
    } else {
      ///NetworkHandler: Status unchanged, skipping callback
    }
  }

  /// Stop monitoring and clean up resources
  void stopMonitoring() {
    _subscription?.cancel();
    _subscription = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
    onStatusChange = null; // Clear callback to prevent memory leaks
  }

  /// Dispose of the handler
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    stopMonitoring();
    try {
      isConnected.dispose();
    } catch (e) {
      /// ValueNotifier already disposed, ignore
    }
  }
}
