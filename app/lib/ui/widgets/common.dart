import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../models/order.dart';
import '../../state/realtime.dart';
import '../../state/session.dart';
import '../owner/users_admin_page.dart' show showChangeOwnPasswordDialog;

String errorMessage(Object error) =>
    error is ApiException ? error.message : 'Ocurrió un error inesperado. Intenta de nuevo.';

void showErrorSnack(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(errorMessage(error)), backgroundColor: Theme.of(context).colorScheme.error),
    );
}

void showInfoSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// "hace 3 min", "hace 1 h 05 min"
String elapsedLabel(DateTime since, DateTime now) {
  final minutes = now.difference(since).inMinutes;
  if (minutes < 1) return 'recién';
  if (minutes < 60) return 'hace $minutes min';
  return 'hace ${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min';
}

String timeLabel(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      OrderStatus.pending => (Colors.orange.shade100, Colors.orange.shade900),
      OrderStatus.inPreparation => (Colors.blue.shade100, Colors.blue.shade900),
      OrderStatus.ready => (Colors.green.shade100, Colors.green.shade900),
      OrderStatus.delivered => (Colors.grey.shade200, Colors.grey.shade800),
      OrderStatus.cancelled => (Colors.red.shade100, Colors.red.shade900),
    };
    return _Pill(label: status.label, background: background, foreground: foreground);
  }
}

class PaymentChip extends StatelessWidget {
  const PaymentChip(this.status, {super.key});

  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      PaymentStatus.unpaid => (Colors.red.shade50, Colors.red.shade800),
      PaymentStatus.partial => (Colors.amber.shade100, Colors.brown.shade800),
      PaymentStatus.paid => (Colors.teal.shade50, Colors.teal.shade800),
    };
    return _Pill(label: status.label, background: background, foreground: foreground);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.background, required this.foreground});

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
    child: Text(
      label,
      style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

/// Green/red dot in the app bar: is the screen receiving live updates?
class ConnectionIndicator extends ConsumerWidget {
  const ConnectionIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(realtimeConnectedProvider).value ?? false;
    return Tooltip(
      message: connected ? 'En línea: actualización automática' : 'Sin conexión en tiempo real',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 12, color: connected ? Colors.green : Colors.red),
            if (!connected) ...[
              const SizedBox(width: 4),
              const Text('Sin conexión', style: TextStyle(fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class LogoutButton extends ConsumerWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return PopupMenuButton<void>(
      icon: const Icon(Icons.account_circle),
      tooltip: user.fullName,
      itemBuilder: (context) => [
        PopupMenuItem(enabled: false, child: Text('${user.fullName} · ${user.role.label}')),
        PopupMenuItem(
          onTap: () => showChangeOwnPasswordDialog(context, ref),
          child: const Row(children: [Icon(Icons.key), SizedBox(width: 8), Text('Cambiar contraseña')]),
        ),
        PopupMenuItem(
          onTap: () => ref.read(sessionProvider.notifier).logout(),
          child: const Row(children: [Icon(Icons.logout), SizedBox(width: 8), Text('Cerrar sesión')]),
        ),
      ],
    );
  }
}

class ErrorRetryView extends StatelessWidget {
  const ErrorRetryView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          Text(errorMessage(error), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 8),
        Text(message, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      ],
    ),
  );
}
