import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_notifications_service.dart';

class PushNotificationService {
  PushNotificationService._();

  static Future<void> setup() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await messaging.getToken();
    if (token == null) {
      debugPrint('FCM: no token available');
      return;
    }

    await _saveToken(token, userId: user.id);

    messaging.onTokenRefresh.listen((newToken) {
      _saveToken(newToken, userId: user.id);
    });

    // Show a local notification for messages received while the app is open.
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM foreground message: ${message.messageId}');
      final title = message.notification?.title ?? 'New notification';
      final body = message.notification?.body ?? '';
      LocalNotificationsService.showLiveRequest(title: title, body: body);
    });

    // Log when a notification tap brings the app to the foreground.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('FCM opened from notification: ${message.messageId}');
    });

    // Handle the notification that launched a terminated app.
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      debugPrint('FCM launched app: ${initial.messageId}');
    }
  }

  static Future<void> _saveToken(String token, {required String userId}) async {
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId);
      debugPrint('FCM token saved for user $userId');
    } catch (e) {
      debugPrint('FCM token save failed: $e');
    }
  }
}
