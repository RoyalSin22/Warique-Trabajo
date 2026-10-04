import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../models/admin.dart';
import '../../models/inventory.dart';
import '../../models/order.dart';
import '../../state/admin.dart';
import '../widgets/common.dart';

/// Owner dashboard: how sales evolve, which day / dish / hour performs best and how people pay.
class StatsView extends ConsumerStatefulWidget {
  const StatsView({super.key, this.today});

  /// Injectable for tests; defaults to the device's date.
  final DateTime? today;

  @override
  ConsumerState<StatsView> createState() => _StatsViewState();
}

enum StatsRange {
  week('7 días'),
  month('30 días'),
  thisMonth('Este mes'),
  quarter('90 días');

  const StatsRange(this.label);

  final String label;

  ({String from, String to}) resolve(DateTime today) {
    final end = dateOnly(today);
    final start = switch (this) {
      StatsRange.week => end.subtract(const Duration(days: 6)),
      StatsRange.month => end.subtract(const Duration(days: 29)),
      StatsRange.thisMonth => DateTime(end.year, end.month),
      StatsRange.quarter => end.subtract(const Duration(days: 89)),
    };
    return (from: dayKey(start), to: dayKey(end));
  }
}

class _StatsViewState extends ConsumerState<StatsView> {
  StatsRange _range = StatsRange.month;

  @override
  Widget build(BuildContext context) {
    final range = _range.resolve(widget.today ?? DateTime.now());
    final summary = ref.watch(salesSummaryProvider(range));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(salesSummaryProvider(range)),
      child: ListView(
        padding: EdgeInsets.fromLTRB(12 + sideGutter(context), 8, 12 + sideGutter(context), 32),
        children: [
          // Filters in one row above the charts
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<StatsRange>(
              showSelectedIcon: false,
              segments: [for (final r in StatsRange.values) ButtonSegment(value: r, label: Text(r.label))],
              selected: {_range},
              onSelectionChanged: (selection) => setState(() => _range = selection.first),
            ),
          ),
          const SizedBox(height: 12),
          switch (summary) {
            AsyncValue(value: final data?) when data.orders == 0 => const Padding(
              padding: EdgeInsets.only(top: 48),
              child: EmptyView(icon: Icons.insights, message: 'Sin ventas en este periodo'),
            ),
            AsyncValue(value: final data?) => _Dashboard(summary: data),
            AsyncError(:final error) => ErrorRetryView(
              error: error,
              onRetry: () => ref.invalidate(salesSummaryProvider(range)),
            ),
            _ => const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        ],
      ),
    );
  }
}

/// Readable column on tablets and the PC; full width on phones.
double sideGutter(BuildContext context) {
  const maxContentWidth = 760.0;
  final width = MediaQuery.sizeOf(context).width;
  return width > maxContentWidth ? (width - maxContentWidth) / 2 : 0;
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.summary});

  final SalesSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final bestWeekday = s.byWeekday
        .where((w) => w.openDays > 0)
        .fold<({int weekday, Money avg})?>(
          null,
          (best, w) =>
              best == null || w.averageSales > best.avg ? (weekday: w.weekday, avg: w.averageSales) : best,
        );
    final peakHour = s.byHour.isEmpty ? null : s.byHour.reduce((a, b) => b.orders > a.orders ? b : a);
    final topDish = s.topDishes.isEmpty ? null : s.topDishes.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // KPI row: the headline numbers are tiles, not charts
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatTile(
              label: 'Ventas',
              value: s.sales.toString(),
              caption: '${s.daysWithSales} días con ventas',
            ),
            StatTile(label: 'Pedidos', value: '${s.orders}'),
            StatTile(label: 'Ticket promedio', value: s.averageTicket.toString()),
            if (s.bestDay != null)
              StatTile(
                label: 'Mejor día',
                value: s.bestDay!.sales.toString(),
                caption: mediumDayLabel(s.bestDay!.date),
              ),
            if (s.expenses.isPositive) ...[
              StatTile(label: 'Gastos', value: s.expenses.toString()),
              StatTile(
                label: 'Ventas − gastos',
                value: s.salesMinusExpenses.toString(),
                caption: 'No es utilidad contable',
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        ChartCard(
          title: 'Ventas por día (S/)',
          takeaway: s.bestDay == null
              ? null
              : 'El mejor día fue el ${mediumDayLabel(s.bestDay!.date)} con ${s.bestDay!.sales}.',
          chart: s.days.length <= 31 ? _DailyBars(summary: s) : _DailyLine(summary: s),
          table: (
            headers: const ['Día', 'Pedidos', 'Ventas'],
            rows: [
              for (final d in s.days.reversed) [mediumDayLabel(d.date), '${d.orders}', d.sales.toString()],
            ],
          ),
        ),
        ChartCard(
          title: 'Promedio por día de la semana (S/)',
          takeaway: bestWeekday == null
              ? null
              : 'Los ${weekdayPlural(bestWeekday.weekday)} se vende más: '
                    '${bestWeekday.avg} en promedio.',
          chart: _ColumnChart(
            values: [for (final w in s.byWeekday) w.averageSales.cents / 100],
            labels: [for (final w in s.byWeekday) weekdayInitial(w.weekday)],
            highlight: bestWeekday == null ? null : bestWeekday.weekday - 1,
            emphasis: true,
            tooltip: (i) {
              final w = s.byWeekday[i];
              return '${weekdayName(w.weekday)}\n${w.averageSales} promedio\n${w.openDays} día(s) con ventas';
            },
            money: true,
          ),
          table: (
            headers: const ['Día', 'Días con ventas', 'Promedio'],
            rows: [
              for (final w in s.byWeekday)
                [weekdayName(w.weekday), '${w.openDays}', w.averageSales.toString()],
            ],
          ),
        ),
        ChartCard(
          title: 'Platos más vendidos',
          takeaway: topDish == null ? null : '${topDish.name} lidera con ${topDish.quantity} vendidos.',
          chart: _TopDishes(dishes: s.topDishes),
          table: (
            headers: const ['Plato', 'Cantidad', 'Ingresos'],
            rows: [
              for (final d in s.topDishes) [d.name, '${d.quantity}', d.revenue.toString()],
            ],
          ),
        ),
        ChartCard(
          title: 'Pedidos por hora',
          takeaway: peakHour == null
              ? null
              : 'Hora punta: ${_hourRange(peakHour.hour)} con ${peakHour.orders} pedidos.',
          chart: _HourlyChart(summary: s),
          table: (
            headers: const ['Hora', 'Pedidos', 'Ventas'],
            rows: [
              for (final h in s.byHour) [_hourRange(h.hour), '${h.orders}', h.sales.toString()],
            ],
          ),
        ),
        if (s.expensesByCategory.isNotEmpty)
          ChartCard(
            title: 'Gastos por categoría',
            takeaway: _expenseTakeaway(s),
            chart: _ExpenseBars(rows: s.expensesByCategory),
            table: (
              headers: const ['Categoría', 'Monto', '% del gasto'],
              rows: [
                for (final row in s.expensesByCategory)
                  [row.category.label, row.amount.toString(), '${_share(row.amount, s.expenses)} %'],
              ],
            ),
          ),
        ChartCard(
          title: 'Cómo pagan',
          takeaway: s.byMethod.isEmpty ? null : 'Cobrado en el periodo: ${s.collected}.',
          chart: _PaymentSplit(byMethod: s.byMethod),
          table: (
            headers: const ['Método', 'Pagos', 'Monto'],
            rows: [
              for (final e in s.byMethod.entries)
                [e.key.label, '${e.value.count}', e.value.amount.toString()],
            ],
          ),
        ),
      ],
    );
  }
}

int _share(Money part, Money total) => total.isPositive ? (part.cents * 100 / total.cents).round() : 0;

String _expenseTakeaway(SalesSummary s) {
  final top = s.expensesByCategory.first;
  final ofSales = s.sales.isPositive ? ' (${_share(s.expenses, s.sales)} % de lo vendido)' : '';
  return '${top.category.label} es el mayor gasto: ${top.amount}, ${_share(top.amount, s.expenses)} % del total$ofSales.';
}

String _hourRange(int hour) =>
    '${hour.toString().padLeft(2, '0')}:00–${((hour + 1) % 24).toString().padLeft(2, '0')}:00';

/// "1.5k" style axis labels; the currency is in the chart title, so labels stay one line on a
/// phone. The exact value lives in the tooltip and the table.
String _compactSoles(double value) {
  if (value >= 1000) {
    final k = value / 1000;
    return '${k == k.roundToDouble() ? k.round() : k.toStringAsFixed(1)}k';
  }
  return '${value.round()}';
}

/// Rounds the axis maximum to a readable step so gridlines land on round numbers.
({double max, double interval}) _niceAxis(double maxValue) {
  if (maxValue <= 0) return (max: 1, interval: 1);
  final rough = maxValue / 4;
  final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  final step = [1, 2, 2.5, 5, 10].map((m) => m * magnitude).firstWhere((s) => s >= rough);
  return (max: (maxValue / step).ceil() * step, interval: step);
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              Text(value, style: theme.textTheme.headlineSmall),
              if (caption != null) Text(caption!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

typedef ChartTable = ({List<String> headers, List<List<String>> rows});

/// Card with a title, a one-line takeaway, the chart and a table view of the same data
/// (accessibility: the numbers never depend on reading the chart).
class ChartCard extends StatefulWidget {
  const ChartCard({super.key, required this.title, required this.chart, required this.table, this.takeaway});

  final String title;
  final String? takeaway;
  final Widget chart;
  final ChartTable table;

  @override
  State<ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<ChartCard> {
  bool _showTable = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.title, style: theme.textTheme.titleMedium)),
                IconButton(
                  tooltip: _showTable ? 'Ver gráfica' : 'Ver tabla',
                  icon: Icon(_showTable ? Icons.bar_chart : Icons.table_rows_outlined),
                  onPressed: () => setState(() => _showTable = !_showTable),
                ),
              ],
            ),
            if (widget.takeaway != null)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 12),
                child: Text(widget.takeaway!, style: theme.textTheme.bodyMedium),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _showTable ? _DataTableView(table: widget.table) : widget.chart,
            ),
          ],
        ),
      ),
    );
  }
}

class _DataTableView extends StatelessWidget {
  const _DataTableView({required this.table});

  final ChartTable table;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String text, {bool header = false, bool numeric = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(
        text,
        textAlign: numeric ? TextAlign.right : TextAlign.left,
        style: header ? theme.textTheme.labelLarge : theme.textTheme.bodyMedium,
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        child: Table(
          columnWidths: const {0: FlexColumnWidth(2)},
          border: TableBorder(horizontalInside: BorderSide(color: theme.colorScheme.outlineVariant)),
          children: [
            TableRow(
              children: [for (final (i, h) in table.headers.indexed) cell(h, header: true, numeric: i > 0)],
            ),
            for (final row in table.rows)
              TableRow(children: [for (final (i, v) in row.indexed) cell(v, numeric: i > 0)]),
          ],
        ),
      ),
    );
  }
}

/// Column chart with one scale. [emphasis] paints the highlighted column in the brand color and
/// the rest in a neutral gray (the question is "which one is highest"); otherwise every column
/// uses the brand color and the highlight only gets a permanent direct label.
class _ColumnChart extends StatelessWidget {
  const _ColumnChart({
    required this.values,
    required this.labels,
    required this.tooltip,
    this.highlight,
    this.emphasis = false,
    this.money = false,
    this.labelEvery = 1,
  });

  final List<double> values;
  final List<String> labels;
  final String Function(int index) tooltip;
  final int? highlight;
  final bool emphasis;
  final bool money;
  final int labelEvery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final axis = _niceAxis(values.fold(0.0, math.max));
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return SizedBox(
      height: 200,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Thin columns with a visible gap between neighbours
          final slot = (constraints.maxWidth - 48) / math.max(values.length, 1);
          final barWidth = (slot * 0.62).clamp(3.0, 28.0);
          return BarChart(
            BarChartData(
              maxY: axis.max,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: axis.interval,
                getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: axis.interval,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(money ? _compactSoles(value) : '${value.round()}', style: muted),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= labels.length || i % labelEvery != 0) return const SizedBox.shrink();
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(labels[i], style: muted),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => scheme.inverseSurface,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                    tooltip(group.x),
                    TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                  ),
                ),
              ),
              barGroups: [
                for (final (i, v) in values.indexed)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: v,
                        width: barWidth,
                        color: !emphasis || i == highlight
                            ? scheme.primary
                            : scheme.outline.withValues(alpha: 0.45),
                        // 4px rounded data end, square at the baseline
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.summary});

  final SalesSummary summary;

  @override
  Widget build(BuildContext context) {
    final days = summary.days;
    final best = summary.bestDay;
    return _ColumnChart(
      values: [for (final d in days) d.sales.cents / 100],
      labels: [
        for (final d in days)
          days.length <= 7 ? '${weekdayInitial(d.date.weekday)} ${d.date.day}' : '${d.date.day}',
      ],
      labelEvery: days.length <= 7 ? 1 : (days.length / 8).ceil(),
      highlight: best == null ? null : days.indexWhere((d) => d.date == best.date),
      emphasis: true, // answers "which day sold the most" at a glance
      money: true,
      tooltip: (i) => '${mediumDayLabel(days[i].date)}\n${days[i].sales}\n${days[i].orders} pedidos',
    );
  }
}

/// More than a month: a 2px trend line with a crosshair tooltip.
class _DailyLine extends StatelessWidget {
  const _DailyLine({required this.summary});

  final SalesSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = summary.days;
    final axis = _niceAxis(days.fold(0.0, (m, d) => math.max(m, d.sales.cents / 100)));
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final labelEvery = (days.length / 6).ceil();

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: axis.max,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: axis.interval,
            getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: axis.interval,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(_compactSoles(value), style: muted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= days.length || i % labelEvery != 0) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(shortDayLabel(days[i].date), style: muted),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              fitInsideHorizontally: true,
              getTooltipItems: (spots) => [
                for (final spot in spots)
                  LineTooltipItem(
                    '${mediumDayLabel(days[spot.x.toInt()].date)}\n${days[spot.x.toInt()].sales}',
                    TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (final (i, d) in days.indexed) FlSpot(i.toDouble(), d.sales.cents / 100)],
              color: scheme.primary,
              barWidth: 2,
              isCurved: false,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: scheme.primary.withValues(alpha: 0.10)),
            ),
          ],
        ),
      ),
    );
  }
}

class _HourlyChart extends StatelessWidget {
  const _HourlyChart({required this.summary});

  final SalesSummary summary;

  @override
  Widget build(BuildContext context) {
    // Opening hours 11-18 always shown; any order outside them widens the axis
    final byHour = {for (final h in summary.byHour) h.hour: h};
    final first = math.min(11, byHour.keys.fold(23, math.min));
    final last = math.max(17, byHour.keys.fold(0, math.max));
    final hours = [for (var h = first; h <= last; h++) h];
    final peak = summary.byHour.isEmpty
        ? null
        : summary.byHour.reduce((a, b) => b.orders > a.orders ? b : a).hour;

    return _ColumnChart(
      values: [for (final h in hours) (byHour[h]?.orders ?? 0).toDouble()],
      labels: [for (final h in hours) '$h'],
      highlight: peak == null ? null : hours.indexOf(peak),
      emphasis: true,
      tooltip: (i) {
        final row = byHour[hours[i]];
        return '${_hourRange(hours[i])}\n${row?.orders ?? 0} pedidos\n${row?.sales ?? Money.zero}';
      },
    );
  }
}

/// Ranked horizontal bars (long dish names stay readable), with a quantity / revenue toggle.
class _TopDishes extends StatefulWidget {
  const _TopDishes({required this.dishes});

  final List<({String name, int quantity, Money revenue})> dishes;

  @override
  State<_TopDishes> createState() => _TopDishesState();
}

class _TopDishesState extends State<_TopDishes> {
  bool _byRevenue = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [...widget.dishes]
      ..sort(
        (a, b) => _byRevenue ? b.revenue.cents.compareTo(a.revenue.cents) : b.quantity.compareTo(a.quantity),
      );
    final max = rows.fold<int>(1, (m, d) => math.max(m, _byRevenue ? d.revenue.cents : d.quantity));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: false, label: Text('Cantidad')),
            ButtonSegment(value: true, label: Text('Ingresos')),
          ],
          selected: {_byRevenue},
          onSelectionChanged: (s) => setState(() => _byRevenue = s.first),
        ),
        const SizedBox(height: 8),
        for (final d in rows)
          Tooltip(
            message: '${d.name}: ${d.quantity} vendidos · ${d.revenue}',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final value = _byRevenue ? d.revenue.cents : d.quantity;
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: 14,
                            width: math.max(2, c.maxWidth * value / max),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      _byRevenue ? d.revenue.toString() : '${d.quantity}',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Part-to-whole as one 100% bar. Categorical slots 1-3 of the validated reference palette
/// (blue, orange, aqua: all CVD checks pass on this surface); aqua is below 3:1 contrast, so
/// every segment is also named with its amount and share below (never color alone).
const paymentColors = {
  PaymentMethod.cash: Color(0xFF2A78D6),
  PaymentMethod.yape: Color(0xFFEB6834),
  PaymentMethod.plin: Color(0xFF1BAF7A),
};

class _PaymentSplit extends StatelessWidget {
  const _PaymentSplit({required this.byMethod});

  final Map<PaymentMethod, ({int count, Money amount})> byMethod;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Fixed order so a method keeps its color whatever the data
    final present = [
      for (final m in PaymentMethod.values)
        if (byMethod[m] case final row? when row.amount.isPositive) (method: m, row: row),
    ];
    if (present.isEmpty) return const Text('Sin cobros en el periodo.');
    final total = present.fold(0, (sum, p) => sum + p.row.amount.cents);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 22,
            child: Row(
              // Stretch: a ColoredBox has no height of its own and would render 0px tall
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, p) in present.indexed) ...[
                  if (i > 0) const SizedBox(width: 2), // surface gap between segments
                  Expanded(
                    flex: p.row.amount.cents,
                    child: Tooltip(
                      message: '${p.method.label}: ${p.row.amount}',
                      child: ColoredBox(color: paymentColors[p.method]!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final p in present)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: paymentColors[p.method],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${p.method.label} · ${p.row.count} pagos', style: theme.textTheme.bodyMedium),
                ),
                Text(
                  '${p.row.amount}  (${(p.row.amount.cents * 100 / total).round()} %)',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ranked horizontal bars, one color: the question is "where does the money go", so length and
/// the printed amount carry it (no legend needed).
class _ExpenseBars extends StatelessWidget {
  const _ExpenseBars({required this.rows});

  final List<({ExpenseCategory category, Money amount})> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = rows.fold<int>(1, (m, r) => math.max(m, r.amount.cents));
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    row.category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 14,
                        width: math.max(2, c.maxWidth * row.amount.cents / max),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    row.amount.toString(),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
