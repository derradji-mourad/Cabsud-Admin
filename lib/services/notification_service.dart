import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../theme/app_colors.dart';
import '../widgets/in_app_notification.dart';

class NotificationService {
  NotificationService._();

  static OverlayEntry? _current;
  static final AudioPlayer _audio = AudioPlayer();
  static bool _audioConfigured = false;

  /// Show a slide-in banner anchored to the top of the screen. Replaces any
  /// banner that's already visible.
  static void show({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    bool playSound = true,
    Duration duration = const Duration(seconds: 5),
  }) {
    // Sound is independent of the banner — play first so the user is
    // notified even if the overlay can't be inserted for any reason.
    if (playSound) {
      _playSound();
    }

    // navigatorKey.currentContext is the Navigator widget itself, which sits
    // ABOVE the Overlay — Overlay.maybeOf would walk the wrong direction. The
    // NavigatorState exposes the OverlayState directly.
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      debugPrint('🔔 banner skipped: navigator has no overlay yet');
      return;
    }

    _removeCurrent();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => InAppNotification(
        icon: icon,
        iconColor: iconColor,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        duration: duration,
        onDismiss: () {
          if (identical(_current, entry)) _current = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
    debugPrint('🔔 banner shown: $title');
  }

  /// Pop a centered AlertDialog. Use for "must-acknowledge" alerts on top of
  /// the slide-in banner.
  static void showAlert({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
  }) {
    final navContext = navigatorKey.currentContext;
    if (navContext == null) {
      debugPrint('🔔 alert skipped: navigator has no context');
      return;
    }
    showDialog<void>(
      context: navContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.secondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    debugPrint('🔔 alert dialog shown: $title');
  }

  static void _removeCurrent() {
    final c = _current;
    _current = null;
    if (c != null && c.mounted) c.remove();
  }

  static Future<void> _ensureAudioConfigured() async {
    if (_audioConfigured) return;
    try {
      // Route the chime through the notification audio stream — separate
      // volume slider from media on Android, ducks other audio on iOS.
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: const {AVAudioSessionOptions.duckOthers},
          ),
        ),
      );
      _audioConfigured = true;
    } catch (e) {
      debugPrint('🔔 audio context setup failed: $e');
    }
  }

  static Future<void> _playSound() async {
    try {
      await _ensureAudioConfigured();
      await _audio.stop();
      await _audio.setVolume(1.0);
      await _audio.play(AssetSource('notification.mp3'));
      debugPrint('🔔 sound play() returned');
    } catch (e, st) {
      debugPrint('🔔 Error playing notification sound: $e\n$st');
    }
  }
}
