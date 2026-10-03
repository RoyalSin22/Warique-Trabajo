import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warique_app/models/admin.dart';
import 'package:warique_app/models/user.dart';
import 'package:warique_app/ui/owner/stats_view.dart';

import '../../support/container.dart';
import '../../support/fixtures.dart';

Map<String, dynamic> summaryJson({String from = '2026-09-04', String to = '2026-10-03', int orders = 6}) {
  final days = <Map<String, dynamic>>[];
  for (
    var d = DateTime.utc(2026, 9, 4);
    !d.isAfter(DateTime.utc(2026, 10, 3));
    d = d.add(const Duration(days: 1))
  ) {
    final date = d.toIso8601String().substring(0, 10);
    days.add({
      'date': date,
      'weekday': d.weekday,
      'sales': date == '2026-10-03' ? '292' : (date == '2026-10-02' ? '120.5' : '0'),
      'orders': date == '2026-10-03' ? 5 : (date == '2026-10-02' ? 1 : 0),
    });
  }
  return {
    'from': from,
    'to': to,
    'totals': {
      'sales': '412.50',
      'orders': orders,
      'averageTicket': '68.75',
      'collected': '83.00',
      'daysWithSales': 2,
      'bestDay': {'date': '2026-10-03', 'sales': '292.00'},
    },
    'days': days,
    'byWeekday': [
      for (var w = 1; w <= 7; w++)
        {
          'weekday': w,
          'openDays': w >= 5 && w <= 6 ? 1 : 0,
          'sales': w == 6 ? '292.00' : (w == 5 ? '120.50' : '0.00'),
          'averageSales': w == 6 ? '292.00' : (w == 5 ? '120.50' : '0.00'),
        },
    ],
    'byHour': [
      {'hour': 12, 'orders': 2, 'sales': '80.00'},
      {'hour': 13, 'orders': 4, 'sales': '332.50'},
    ],
    'topDishes': [
      {'dishName': 'Ceviche', 'quantity': 3, 'revenue': '55.50'},
      {'dishName': 'Lomo saltado', 'quantity': 2, 'revenue': '49.00'},
      {'dishName': 'Seco de res', 'quantity': 1, 'revenue': '80.00'},
    ],
    'byMethod': [
      {'method': 'CASH', 'count': 1, 'amount': '40.00'},
      {'method': 'YAPE', 'count': 1, 'amount': '43.00'},
    ],
  };
}

void main() {
  test('parses the summary', () {
    final s = SalesSummary.fromJson(summaryJson());
    expect(s.days, hasLength(30));
    expect(s.bestDay!.sales.cents, 29200);
    expect(s.byWeekday.firstWhere((w) => w.weekday == 6).averageSales.cents, 29200);
    expect(s.topDishes.first.name, 'Ceviche');
  });

  late RecordingHttp server;

  Future<void> pump(WidgetTester tester, {Size size = const Size(400, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: sessionOverrides(role: Role.owner, http: server, realtime: FakeRealtime()),
        child: MaterialApp(
          home: Scaffold(body: StatsView(today: DateTime(2026, 10, 3))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows KPIs, takeaways and charts for the last 30 days by default', (tester) async {
    server = RecordingHttp((request) => (200, summaryJson()));
    await pump(tester);

    expect(server.requests.single.url.queryParameters, {'from': '2026-09-04', 'to': '2026-10-03'});
    expect(find.text('S/ 412.50'), findsOneWidget);
    expect(find.text('S/ 68.75'), findsOneWidget);
    expect(find.textContaining('El mejor día fue el sáb 3 oct'), findsOneWidget);
    // Spanish plural: "los sábados", "los viernes"
    expect(find.textContaining('Los sábados se vende más: S/ 292.00 en promedio'), findsOneWidget);
    expect(find.byType(BarChart), findsWidgets);

    final page = find.byType(Scrollable).first; // the dashboard list (charts and filters scroll too)
    await tester.scrollUntilVisible(find.textContaining('Hora punta'), 300, scrollable: page);
    expect(find.textContaining('Hora punta: 13:00–14:00 con 4 pedidos'), findsOneWidget);
  });

  testWidgets('range filter requests the new period', (tester) async {
    server = RecordingHttp((request) => (200, summaryJson()));
    await pump(tester);
    await tester.tap(find.text('7 días'));
    await tester.pumpAndSettle();
    expect(server.requests.last.url.queryParameters, {'from': '2026-09-27', 'to': '2026-10-03'});
    await tester.tap(find.text('Este mes'));
    await tester.pumpAndSettle();
    expect(server.requests.last.url.queryParameters, {'from': '2026-10-01', 'to': '2026-10-03'});
  });

  testWidgets('top dishes re-rank by revenue and every chart has a table view', (tester) async {
    server = RecordingHttp((request) => (200, summaryJson()));
    await pump(tester, size: const Size(400, 2600));

    final dishNames = find.descendant(of: find.byType(Tooltip), matching: find.byType(Text));
    String firstDish() => tester.widget<Text>(dishNames.first).data!;
    expect(firstDish(), 'Ceviche');
    await tester.tap(find.text('Ingresos'));
    await tester.pumpAndSettle();
    expect(firstDish(), 'Seco de res');

    // The 100% payment bar must be drawn, not just its legend (40 + 43 → 48 % / 52 %)
    final segments = find.descendant(
      of: find.byTooltip('Efectivo: S/ 40.00'),
      matching: find.byType(ColoredBox),
    );
    final cash = tester.getSize(segments.first);
    final yape = tester.getSize(
      find.descendant(of: find.byTooltip('Yape: S/ 43.00'), matching: find.byType(ColoredBox)).first,
    );
    expect(cash.height, 22);
    expect(cash.width / (cash.width + yape.width), closeTo(40 / 83, 0.02));
    expect(find.textContaining('(48 %)'), findsOneWidget);

    await tester.tap(find.byTooltip('Ver tabla').first);
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('sáb 3 oct'), findsNWidgets(2)); // daily table row + best-day tile
  });

  testWidgets('empty period shows a friendly message', (tester) async {
    server = RecordingHttp((request) => (200, summaryJson(orders: 0)));
    await pump(tester);
    expect(find.text('Sin ventas en este periodo'), findsOneWidget);
  });
}
