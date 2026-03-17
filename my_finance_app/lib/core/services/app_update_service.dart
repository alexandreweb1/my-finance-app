import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Data returned by [appUpdateProvider].
class AppUpdateInfo {
  final bool hasUpdate;
  final String storeUrl;

  const AppUpdateInfo({required this.hasUpdate, required this.storeUrl});
}

/// Checks Firestore `app_config/latest_version` and compares with the
/// installed version. Returns [AppUpdateInfo] with [hasUpdate] = true
/// and the appropriate store URL when a newer version is available.
///
/// Firestore document shape:
/// ```json
/// {
///   "version":     "1.1.0",
///   "android_url": "https://play.google.com/store/apps/details?id=com.example.myfinanceapp",
///   "ios_url":     "https://apps.apple.com/app/id..."
/// }
/// ```
final appUpdateProvider = FutureProvider<AppUpdateInfo>((ref) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('app_config')
        .doc('latest_version')
        .get();

    if (!doc.exists) {
      return const AppUpdateInfo(hasUpdate: false, storeUrl: '');
    }

    final data = doc.data()!;
    final latestVersion = (data['version'] as String?)?.trim() ?? '';
    final androidUrl = (data['android_url'] as String?) ?? '';
    final iosUrl = (data['ios_url'] as String?) ?? '';

    if (latestVersion.isEmpty) {
      return const AppUpdateInfo(hasUpdate: false, storeUrl: '');
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();

    final hasUpdate = _isNewer(latestVersion, currentVersion);
    final storeUrl =
        defaultTargetPlatform == TargetPlatform.iOS ? iosUrl : androidUrl;

    return AppUpdateInfo(hasUpdate: hasUpdate, storeUrl: storeUrl);
  } catch (_) {
    return const AppUpdateInfo(hasUpdate: false, storeUrl: '');
  }
});

/// Returns true when [latest] is strictly newer than [current].
/// Compares up to 3 numeric segments (major.minor.patch).
bool _isNewer(String latest, String current) {
  List<int> parse(String v) => v
      .split('.')
      .take(3)
      .map((s) => int.tryParse(s) ?? 0)
      .toList();

  final l = parse(latest);
  final c = parse(current);

  for (var i = 0; i < 3; i++) {
    final lv = i < l.length ? l[i] : 0;
    final cv = i < c.length ? c[i] : 0;
    if (lv > cv) return true;
    if (lv < cv) return false;
  }
  return false;
}
