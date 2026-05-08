import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationsService {
  LocalNotificationsService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static int _idCounter = 0;

  static const String _liveRequestsChannelId = 'orders_live_requests';
  static const String _quickTripsChannelId = 'orders_quick_trips';

  /// Initialize the plugin and request runtime permissions. Safe to call
  /// multiple times.
  static Future<void> init() async {
    if (_initialized) return;

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    await _plugin.initialize(settings: initSettings);
    debugPrint('🔔 local notifications plugin initialized');

    // Android 13+ runtime permission.
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      final granted = await android?.requestNotificationsPermission();
      debugPrint('🔔 POST_NOTIFICATIONS permission granted=$granted');
    } catch (e) {
      debugPrint('🔔 Notification permission request failed: $e');
    }

    _initialized = true;
  }

  static Future<void> showLiveRequest({
    required String title,
    required String body,
  }) async {
    await _show(
      channelId: _liveRequestsChannelId,
      channelName: 'New Live Requests',
      title: title,
      body: body,
    );
  }

  static Future<void> showQuickTrip({
    required String title,
    required String body,
  }) async {
    await _show(
      channelId: _quickTripsChannelId,
      channelName: 'New Quick Trips',
      title: title,
      body: body,
    );
  }

  static Future<void> _show({
    required String channelId,
    required String channelName,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Alerts for new $channelName',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: title,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.message,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    _idCounter = (_idCounter + 1) & 0x7fffffff;
    try {
      await _plugin.show(
        id: _idCounter,
        title: title,
        body: body,
        notificationDetails: details,
      );
      debugPrint('🔔 system notification shown: $title');
    } catch (e, st) {
      debugPrint('🔔 Failed to show local notification: $e\n$st');
    }
  }
}
