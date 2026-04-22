import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_lock_provider.dart';
import '../screens/lock_screen.dart';

/// Observes app lifecycle and re-locks after the app has been backgrounded
/// for more than [_kBackgroundTimeout]. Renders [LockScreen] on top of
/// [child] while locked.
class AppLockGate extends ConsumerStatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

const _kBackgroundTimeout = Duration(seconds: 5);

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _pausedAt ??= DateTime.now();
        break;
      case AppLifecycleState.resumed:
        final pausedAt = _pausedAt;
        _pausedAt = null;
        if (pausedAt == null) return;
        if (DateTime.now().difference(pausedAt) >= _kBackgroundTimeout) {
          ref.read(appLockProvider.notifier).lock();
        }
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockProvider.select((s) => s.locked));
    return Stack(
      children: [
        widget.child,
        if (locked) const LockScreen(),
      ],
    );
  }
}
