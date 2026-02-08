import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:isolate';

/// Android-only foreground service used to keep ongoing calls alive
/// when the app goes to background (more reliable audio continuity).
class OngoingCallService {
  static bool _inited = false;

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> _ensureInit() async {
    if (!_isAndroid || _inited) return;
    _inited = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'lualaba_calls',
        channelName: 'Appels',
        channelDescription: 'Notification affichee pendant un appel en cours.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        // Keep it quiet; call sound should come from the in-app ringtone/audio session.
        enableVibration: false,
        playSound: false,
      ),
      // Required by the plugin API even if we only run the service on Android.
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> start({
    required String title,
    required String subtitle,
  }) async {
    if (!_isAndroid) return;
    await _ensureInit();

    // If already running, update the notification content.
    final running = await FlutterForegroundTask.isRunningService;
    if (running == true) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: subtitle,
      );
      return;
    }

    await FlutterForegroundTask.startService(
      notificationTitle: title,
      notificationText: subtitle,
      callback: _startCallback,
    );
  }

  static Future<void> stop() async {
    if (!_isAndroid) return;
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (running == true) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_NoopTaskHandler());
}

class _NoopTaskHandler extends TaskHandler {
  @override
  void onStart(DateTime timestamp, SendPort? sendPort) {}

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {}

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) {}

  @override
  void onNotificationPressed() {
    // Let Android bring the app to foreground (default behavior).
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationButtonPressed(String id) {}
}
