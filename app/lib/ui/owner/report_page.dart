import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/realtime_client.dart';
import '../../models/admin.dart';
import '../../models/order.dart';
import '../../state/admin.dart';
import '../../state/inventory.dart';
import '../../state/realtime.dart';
import '../widgets/common.dart';
import '../widgets/day_navigator.dart';
import 'cash_card.dart';
import 'expenses_page.dart';
import 'export_sheet.dart';
import 'stats_view.dart';

/// Daily closing: sales, collections per method, payments to reconcile and backup health.
class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key});

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  DateTime _day = dateOnly(DateTime.now());
  PaymentMethod? _methodFilter;
  StreamSubscription<RealtimeMessage>? _liveUpdates;
  Timer? _debounce;

  bool get _isToday => _day == dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    // Today's figures follow the service live; a burst of events triggers a single reload
    _liveUpdates = ref.read(realtimeClientProvider).messages.listen((message) {
      if (!_isToday || !message.event.startsWith('order.')) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), _refresh);
    });
  }

  @override
  void dispose() {
    _liveUpdates?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    final key = dayKey(_day);
    ref.invalidate(dailyReportProvider(key));
    ref.invalidate(paymentsReportProvider(key));
    ref.invalidate(backupStatusProvider);
    ref.invalidate(cashDayProvider(key));
    ref.invalidate(expensesProvider(key));
    ref.invalidate(salesSummaryProvider); // every range of the Estadísticas tab
  }

  @override
  Widget build(BuildContext context) {
    final key = dayKey(_day);
    final report = ref.watch(dailyReportProvider(key));
    final payments = ref.watch(paymentsReportProvider(key));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cierre'),
          actions: [
            const ConnectionIndicator(),
            IconButton(
              onPressed: () => showExportSheet(context),
              icon: const Icon(Icons.download),
              tooltip: 'Exportar para el contador',
            ),
            IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
            const LogoutButton(),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.today), text: 'Cierre del día'),
              Tab(icon: Icon(Icons.insights), text: 'Estadísticas'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView(
                // Readable column on tablets and the PC; full width on phones
                padding: EdgeInsets.fromLTRB(12 + _sideGutter(context), 4, 12 + _sideGutter(context), 24),
                children: [
                  DayNavigator(day: _day, onChanged: (day) => setState(() => _day = day)),
                  const _BackupCard(),
                  const SizedBox(height: 8),
                  switch (report) {
                    AsyncValue(value: final data?) => _ReportBody(
                      report: data,
                      cash: CashCard(date: key),
                      onExpenses: () async {
                        await Navigator.of(
                          context,
                        ).push(MaterialPageRoute(builder: (_) => ExpensesPage(initialDay: _day)));
                        _refresh();
                      },
                    ),
                    AsyncError(:final error) => ErrorRetryView(error: error, onRetry: _refresh),
                    _ => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  },
                  const SizedBox(height: 16),
                  switch (payments) {
                    AsyncValue(value: final list?) => _PaymentsSection(
                      payments: list,
                      filter: _methodFilter,
                      onFilter: (method) => setState(() => _methodFilter = method),
                    ),
                    AsyncError(:final error) => ErrorRetryView(error: error, onRetry: _refresh),
                    _ => const SizedBox.shrink(),
                  },
                ],
              ),
            ),
            const StatsView(),
          ],
        ),
      ),
    );
  }
}

double _sideGutter(BuildContext context) {
  const maxContentWidth = 720.0;
  final width = MediaQuery.sizeOf(context).width;
  return width > maxContentWidth ? (width - maxContentWidth) / 2 : 0;
}

class _BackupCard extends ConsumerWidget {
  const _BackupCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(backupStatusProvider).value;
    if (status == null || !status.configured) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final String message;
    if (!status.ok) {
      message = status.time == null
          ? 'Aún no hay respaldos registrados.'
          : 'El último respaldo FALLÓ (${ageLabel(status.ageHours ?? 0)}). Avisa a soporte.';
    } else if ((status.ageHours ?? 999) > 26) {
      message = 'El último respaldo es de ${ageLabel(status.ageHours!)}. ¿La PC estuvo apagada?';
    } else if (!status.copied) {
      message = 'Respaldo hecho ${ageLabel(status.ageHours!)}, pero NO se copió a Google Drive.';
    } else {
      message = 'Respaldo al día: ${ageLabel(status.ageHours!)}, con copia externa.';
    }

    // Explicit green/red: the theme's container colors are too similar with this seed color
    final attention = status.needsAttention;
    return Card(
      color: attention ? scheme.errorContainer : Colors.green.shade50,
      child: ListTile(
        leading: Icon(
          attention ? Icons.warning_amber : Icons.cloud_done,
          color: attention ? scheme.onErrorContainer : Colors.green.shade800,
        ),
        title: Text(
          message,
          style: TextStyle(color: attention ? scheme.onErrorContainer : Colors.green.shade900),
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report, required this.cash, required this.onExpenses});

  final DailyReport report;

  /// Right below the headline numbers: closing the drawer is the next step of the day.
  final Widget cash;
  final VoidCallback onExpenses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cancelled = report.ordersByStatus[OrderStatus.cancelled];
    final open = [
      OrderStatus.pending,
      OrderStatus.inPreparation,
      OrderStatus.ready,
    ].fold(0, (sum, status) => sum + (report.ordersByStatus[status]?.count ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Kpi(label: 'Ventas', value: report.sales, caption: '${report.orderCount} pedidos'),
            _Kpi(label: 'Cobrado', value: report.collectedTotal),
            _Kpi(label: 'Por cobrar', value: report.pendingBalance, warn: report.pendingBalance.isPositive),
            _Kpi(label: 'Gastos', value: report.expensesTotal, onTap: onExpenses, caption: 'Ver / registrar'),
            _Kpi(
              label: 'Ventas − gastos',
              value: report.salesMinusExpenses,
              warn: report.salesMinusExpenses.cents < 0,
            ),
          ],
        ),
        if (open > 0 || cancelled != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              [
                if (open > 0) '$open pedido(s) aún abiertos',
                if (cancelled != null) '${cancelled.count} cancelado(s) por ${cancelled.total}',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ),
        cash,
        const SizedBox(height: 16),
        Text('Cobrado por método', style: theme.textTheme.titleMedium),
        if (report.collectedByMethod.isEmpty) const Text('Sin cobros.'),
        for (final method in PaymentMethod.values)
          if (report.collectedByMethod[method] case final row?)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(method == PaymentMethod.cash ? Icons.payments : Icons.qr_code_2),
              title: Text(method.label),
              subtitle: Text('${row.count} pago(s)'),
              trailing: Text(row.amount.toString(), style: theme.textTheme.titleMedium),
            ),
        const SizedBox(height: 8),
        Text('Más vendidos', style: theme.textTheme.titleMedium),
        if (report.topDishes.isEmpty) const Text('Sin ventas.'),
        for (final (index, dish) in report.topDishes.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(width: 28, child: Text('${index + 1}.')),
                Expanded(child: Text(dish.name)),
                Text('${dish.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, this.caption, this.warn = false, this.onTap});

  final String label;
  final Money value;
  final String? caption;
  final bool warn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: theme.textTheme.labelLarge),
                Text(
                  value.toString(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: warn ? theme.colorScheme.error : null,
                  ),
                ),
                if (caption != null)
                  Text(
                    caption!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onTap == null ? null : theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentsSection extends StatelessWidget {
  const _PaymentsSection({required this.payments, required this.filter, required this.onFilter});

  final List<PaymentRecord> payments;
  final PaymentMethod? filter;
  final ValueChanged<PaymentMethod?> onFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = filter == null ? payments : payments.where((p) => p.method == filter).toList();
    final total = shown.fold(Money.zero, (sum, p) => sum + p.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pagos del día', style: theme.textTheme.titleMedium),
        Text(
          'Concilia cada N.° de operación Yape/Plin con tu app del banco.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            ChoiceChip(
              label: const Text('Todos'),
              selected: filter == null,
              onSelected: (_) => onFilter(null),
            ),
            for (final method in PaymentMethod.values)
              ChoiceChip(
                label: Text(method.label),
                selected: filter == method,
                onSelected: (_) => onFilter(method),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (shown.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('Sin pagos.'))
        else ...[
          for (final payment in shown)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(payment.method == PaymentMethod.cash ? Icons.payments : Icons.qr_code_2),
              title: Text('${payment.method.label} · ${payment.amount}'),
              subtitle: Text(
                [
                  '${timeLabel(payment.createdAt)} · #${payment.orderId} ${payment.targetLabel}',
                  if (payment.operationNumber != null) 'Op. ${payment.operationNumber}',
                  if (payment.changeGiven != null && payment.changeGiven!.isPositive)
                    'recibido ${payment.amountReceived} · vuelto ${payment.changeGiven}',
                  'Registró: ${payment.registeredBy}',
                ].join('\n'),
              ),
              isThreeLine: true,
              trailing: payment.operationNumber == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Copiar N.° de operación',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: payment.operationNumber!));
                        showInfoSnack(context, 'Copiado: ${payment.operationNumber}');
                      },
                    ),
            ),
          const Divider(),
          Row(
            children: [
              Expanded(child: Text('Total (${shown.length} pagos)', style: theme.textTheme.titleSmall)),
              Text(total.toString(), style: theme.textTheme.titleMedium),
            ],
          ),
        ],
      ],
    );
  }
}
