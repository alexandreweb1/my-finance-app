import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/providers/navigation_provider.dart';
import '../../../../core/services/local_notification_service.dart';
import '../../../../core/services/notification_listener_service.dart';
import '../../../../core/services/notification_permission_dialog.dart';
import '../../../../core/services/notification_providers.dart';
import '../../../../core/services/notification_suggestion.dart';
import '../../../budget/presentation/screens/planning_screen.dart';
import '../../../categories/presentation/providers/categories_provider.dart';
import '../../../reports/presentation/screens/reports_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';
import '../../../wallets/presentation/providers/wallets_provider.dart';
import '../../../transactions/presentation/screens/transactions_screen.dart';
import '../../../transactions/presentation/widgets/add_transaction_dialog.dart';
import '../widgets/update_banner.dart';
import 'dashboard_screen.dart';

const _kGreen = Color(0xFF00D887);


class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentIndex = 0;

  static const _mobileScreens = [
    DashboardScreen(),
    TransactionsScreen(),
    PlanningScreen(),
    ReportsScreen(),
  ];

  static const _webScreens = [
    DashboardScreen(),
    TransactionsScreen(),
    PlanningScreen(),
    ReportsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initNotificationFeature();
  }

  Future<void> _initNotificationFeature() async {
    // Initialize local notifications and wire the tap handler
    await LocalNotificationService.instance.init(
      onSuggestionTap: (suggestion) {
        ref.read(pendingSuggestionProvider.notifier).state = suggestion;
      },
    );

    // Only proceed if the feature is enabled in settings
    final enabled = ref.read(notificationDetectionEnabledProvider);
    if (!enabled) return;

    // Ask for Notification Access permission after a short delay
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) {
      await showNotificationPermissionDialogIfNeeded(context);
    }

    _startListening();
  }

  void _startListening() {
    NotificationListenerBridge.suggestionStream.listen((suggestion) {
      // Check again in case user disabled while app was open
      if (!ref.read(notificationDetectionEnabledProvider)) return;
      LocalNotificationService.instance.showSuggestion(suggestion);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(categoriesSeedProvider);
    ref.watch(walletsSeedProvider);
    ref.watch(iapInitProvider); // inicializa IAP e restaura compras ao logar
    final l10n = AppLocalizations.of(context);

    // Listen for external navigation (e.g. from dashboard cards)
    ref.listen<int>(mainTabIndexProvider, (_, next) {
      if (next != _currentIndex) setState(() => _currentIndex = next);
    });

    // Open AddTransactionDialog when a notification suggestion is tapped
    ref.listen<NotificationSuggestion?>(pendingSuggestionProvider,
        (_, suggestion) {
      if (suggestion == null) return;
      ref.read(pendingSuggestionProvider.notifier).state = null;
      showDialog<void>(
        context: context,
        builder: (_) => AddTransactionDialog(
          initialAmount: suggestion.amount,
          initialType: suggestion.type,
        ),
      );
    });

    if (kIsWeb) {
      return Scaffold(
        body: Column(
          children: [
            const UpdateBanner(),
            Expanded(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: (i) {
                      setState(() => _currentIndex = i);
                      ref.read(mainTabIndexProvider.notifier).state = i;
                    },
                    labelType: NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: FloatingActionButton(
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => const AddTransactionDialog(),
                        ),
                        backgroundColor: _kGreen,
                        tooltip: l10n.newTransaction,
                        child: const Icon(Icons.add, color: Colors.white),
                      ),
                    ),
                    destinations: [
                      NavigationRailDestination(
                        icon: const Icon(Icons.home_outlined),
                        selectedIcon: const Icon(Icons.home_rounded),
                        label: Text(l10n.navHome),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.receipt_long_outlined),
                        selectedIcon: const Icon(Icons.receipt_long_rounded),
                        label: Text(l10n.navStatement),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.pie_chart_outline),
                        selectedIcon: const Icon(Icons.pie_chart_rounded),
                        label: Text(l10n.navPlanning),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.bar_chart_outlined),
                        selectedIcon: const Icon(Icons.bar_chart_rounded),
                        label: Text(l10n.navReports),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.settings_outlined),
                        selectedIcon: const Icon(Icons.settings_rounded),
                        label: Text(l10n.settings),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(
                    child: IndexedStack(
                      index: _currentIndex,
                      children: _webScreens,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── Mobile layout ────────────────────────────────────────────────────────
    return Scaffold(
      body: Column(
        children: [
          const UpdateBanner(),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _mobileScreens,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const AddTransactionDialog(),
        ),
        backgroundColor: _kGreen,
        tooltip: l10n.newTransaction,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Theme.of(context).colorScheme.surface,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: l10n.navHome,
              index: 0,
              currentIndex: _currentIndex,
              onTap: (i) {
                setState(() => _currentIndex = i);
                ref.read(mainTabIndexProvider.notifier).state = i;
              },
            ),
            _NavItem(
              icon: Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long_rounded,
              label: l10n.navStatement,
              index: 1,
              currentIndex: _currentIndex,
              onTap: (i) {
                setState(() => _currentIndex = i);
                ref.read(mainTabIndexProvider.notifier).state = i;
              },
            ),
            const SizedBox(width: 56),
            _NavItem(
              icon: Icons.pie_chart_outline,
              activeIcon: Icons.pie_chart_rounded,
              label: l10n.navPlanning,
              index: 2,
              currentIndex: _currentIndex,
              onTap: (i) {
                setState(() => _currentIndex = i);
                ref.read(mainTabIndexProvider.notifier).state = i;
              },
            ),
            _NavItem(
              icon: Icons.bar_chart_outlined,
              activeIcon: Icons.bar_chart_rounded,
              label: l10n.navReports,
              index: 3,
              currentIndex: _currentIndex,
              onTap: (i) {
                setState(() => _currentIndex = i);
                ref.read(mainTabIndexProvider.notifier).state = i;
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentIndex;
    final colorScheme = Theme.of(context).colorScheme;
    final color = isActive ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 360;

    return InkWell(
      onTap: () => onTap(index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isActive ? activeIcon : icon,
                key: ValueKey(isActive),
                color: color,
                size: compact ? 20 : 24,
              ),
            ),
            const SizedBox(height: 2),
            if (!compact)
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 3,
              width: isActive ? 16 : 0,
              decoration: BoxDecoration(
                color: _kGreen,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
