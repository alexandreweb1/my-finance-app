import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'notification_suggestion.dart';

class NotificationListenerBridge {
  static const _eventChannel =
      EventChannel('com.alexdev.myfinanceapp/notifications');
  static const _methodChannel =
      MethodChannel('com.alexdev.myfinanceapp/notification_permission');

  /// Stream of suggestions detected from other apps' notifications.
  /// Only active on Android; emits nothing on other platforms.
  static Stream<NotificationSuggestion> get suggestionStream {
    if (!_isAndroid) return const Stream.empty();
    return _eventChannel.receiveBroadcastStream().map((event) {
      final map = jsonDecode(event as String) as Map<String, dynamic>;
      return NotificationSuggestion.fromJson(map);
    });
  }

  /// Returns true if the app has Notification Listener access granted.
  static Future<bool> isPermissionGranted() async {
    if (!_isAndroid) return false;
    try {
      return await _methodChannel.invokeMethod<bool>('isPermissionGranted') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system Notification Access settings screen.
  static Future<void> openPermissionSettings() async {
    if (!_isAndroid) return;
    try {
      await _methodChannel.invokeMethod('openPermissionSettings');
    } catch (_) {}
  }

  /// Sends the list of allowed bank package names to the native service.
  static Future<void> setAllowedPackages(List<String> packages) async {
    if (!_isAndroid) return;
    try {
      await _methodChannel.invokeMethod('setAllowedPackages', {
        'packages': packages,
      });
    } catch (_) {}
  }

  static bool get _isAndroid =>
      defaultTargetPlatform == TargetPlatform.android;
}
