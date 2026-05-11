import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_notifications_service.dart';

class PushNotificationService {
  PushNotificationService._();

  static Future<void> setup() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      debugPrint('FCM setup: no logged-in user, skipping');
      return;
    }
    debugPrint('FCM setup: starting for user ${user.id}');

    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM setup: permission=${settings.authorizationStatus}');

    final token = await messaging.getToken();
    if (token == null) {
      debugPrint('FCM setup: getToken() returned null');
      return;
    }
    debugPrint('FCM setup: got token (${token.length} chars)');

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
      // .select() forces PostgREST to return the updated rows so we can detect
      // RLS-induced 0-row updates (which otherwise look identical to success).
      final rows = await Supabase.instance.client
          .from('admin')
          .update({
            'fcm_token': token,
            'fcm_token_updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId)
          .select('user_id');
      if (rows.isEmpty) {
        debugPrint(
          'FCM token NOT saved: 0 admin rows matched user_id=$userId. '
          'Either no admin row exists for this user, or RLS on public.admin '
          'is blocking the UPDATE.',
        );
      } else {
        debugPrint('FCM token saved for admin $userId (${rows.length} row)');
      }
    } catch (e) {
      debugPrint('FCM token save failed: $e');
    }
  }
}
