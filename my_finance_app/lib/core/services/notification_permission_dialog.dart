import 'package:flutter/material.dart';

import 'notification_listener_service.dart';

/// Shows an explanation dialog and redirects to Android's Notification Access
/// settings when the user hasnds't granted the permission yet.
Future<void> showNotificationPermissionDialogIfNeeded(
    BuildContext context) async {
  final granted = await NotificationListenerBridge.isPermissionGranted();
  if (granted) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => const _NotificationPermissionDialog(),
  );
}

class _NotificationPermissionDialog extends StatelessWidget {
  const _NotificationPermissionDialog();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(Icons.notifications_active_outlined,
          size: 40, color: cs.primary),
      title: const Text('Detectar transações automáticamente'),
      content: const Text(
        'Permita que o app leia suas notificações para identificar '
        'valores de cobranças e pagamentos e sugerir o lançamento '
        'automaticamente.\n\n'
        'Nenhuma notificação é armazenada ou enviada para servidores.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Agora não'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.settings_outlined, size: 18),
          label: const Text('Ativar'),
          onPressed: () async {
            Navigator.of(context).pop();
            await NotificationListenerBridge.openPermissionSettings();
          },
        ),
      ],
    );
  }
}
