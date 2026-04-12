import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/bank_filter_provider.dart';
import '../../../notification_backlog/presentation/providers/backlog_provider.dart';

class BankFilterScreen extends ConsumerWidget {
  const BankFilterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedBankPackagesProvider);
    final cs = Theme.of(context).colorScheme;

    // Collect unique sourceApps from backlog (detected apps)
    final backlogItems = ref.watch(backlogItemsStreamProvider).valueOrNull ?? [];
    final detectedPackages = <String>{};
    for (final item in backlogItems) {
      if (item.sourceApp.isNotEmpty) detectedPackages.add(item.sourceApp);
    }

    // Merge known banks + detected apps (detected first if not in known)
    final allPackages = <String>{...knownBankApps.keys, ...detectedPackages};
    final knownList =
        allPackages.where((p) => knownBankApps.containsKey(p)).toList()
          ..sort((a, b) => knownBankApps[a]!.compareTo(knownBankApps[b]!));
    final otherList =
        allPackages.where((p) => !knownBankApps.containsKey(p)).toList()
          ..sort((a, b) => bankDisplayName(a).compareTo(bankDisplayName(b)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bancos Monitorados'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
        children: [
          // Explanation
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Selecione os aplicativos que deseja monitorar. '
              'Apenas notificações dos apps ativos serão detectadas.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),

          // Known banks section
          if (knownList.isNotEmpty) ...[
            _SectionHeader(title: 'Bancos conhecidos', color: cs),
            ...knownList.map((pkg) => _BankTile(
                  packageName: pkg,
                  displayName: knownBankApps[pkg]!,
                  isBlocked: blocked.contains(pkg),
                  isDetected: detectedPackages.contains(pkg),
                  onToggle: () =>
                      ref.read(blockedBankPackagesProvider.notifier).toggle(pkg),
                )),
          ],

          // Other detected apps
          if (otherList.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SectionHeader(title: 'Outros apps detectados', color: cs),
            ...otherList.map((pkg) => _BankTile(
                  packageName: pkg,
                  displayName: bankDisplayName(pkg),
                  isBlocked: blocked.contains(pkg),
                  isDetected: true,
                  onToggle: () =>
                      ref.read(blockedBankPackagesProvider.notifier).toggle(pkg),
                )),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final ColorScheme color;
  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _BankTile extends StatelessWidget {
  final String packageName;
  final String displayName;
  final bool isBlocked;
  final bool isDetected;
  final VoidCallback onToggle;

  const _BankTile({
    required this.packageName,
    required this.displayName,
    required this.isBlocked,
    required this.isDetected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SwitchListTile(
      value: !isBlocked,
      onChanged: (_) => onToggle(),
      title: Text(displayName),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              packageName,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isDetected) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'detectado',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade700,
                ),
              ),
            ),
          ],
        ],
      ),
      secondary: CircleAvatar(
        radius: 18,
        backgroundColor: isBlocked
            ? cs.surfaceContainerHighest
            : cs.primaryContainer,
        child: Text(
          displayName.isNotEmpty ? displayName[0] : '?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isBlocked ? cs.onSurfaceVariant : cs.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
