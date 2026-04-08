import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'notification_suggestion.dart';

class NotificationListenerBridge {
  static const _eventChannel =
      EventChannel('com.alexdev.myfinanceapp/notifications');
  static const _methodChannel =
      MethodChannel('com.alexdev.myfinanceapp/notification_permission');

  /// Cached broadcast stream — must only call receiveBroadcastStream() once.
  static Stream<String>? _rawStream;

  /// Returns a single, cached stream of suggestions from the native service.
  /// Safe to call multiple times (e.g. after hot-reload) — always returns
  /// the same underlying broadcast stream.
  ///
  /// Individual events that fail JSON parsing are skipped (not fatal).
  static Stream<NotificationSuggestion> get suggestionStream {
    if (!_isAndroid) return const Stream.empty();

    _rawStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => event as String)
        .asBroadcastStream();

    return _rawStream!.transform(
      StreamTransformer<String, NotificationSuggestion>.fromHandlers(
        handleData: (data, sink) {
          try {
            final map = jsonDecode(data) as Map<String, dynamic>;
            sink.add(NotificationSuggestion.fromJson(map));
          } catch (e) {
            debugPrint('[NotifBridge] Failed to parse event: $e');
            // Skip this event — do NOT close the stream.
          }
        },
        handleError: (error, stackTrace, sink) {
          debugPrint('[NotifBridge] Stream error: $error');
          // Forward the error so the listener can handle/retry,
          // but don't break the transformer.
          sink.addError(error, stackTrace);
        },
      ),
    );
  }

  /// Resets the cached stream. Call this if the EventChannel needs to be
  /// re-established (e.g. after the native activity is recreated).
  static void resetStream() {
    _rawStream = null;
  }

  static Future<bool> isPermissionGranted() async {
    if (!_isAndroid) return false;
    try {
      return await _methodChannel.invokeMethod<bool>('isPermissionGranted') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openPermissionSettings() async {
    if (!_isAndroid) return;
    try {
      await _methodChannel.invokeMethod('openPermissionSettings');
    } catch (_) {}
  }

  static bool get _isAndroid =>
      defaultTargetPlatform == TargetPlatform.android;
}
