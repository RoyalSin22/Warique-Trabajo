import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warique_app/core/alerts.dart';
import 'package:warique_app/data/realtime_client.dart';
import 'package:warique_app/models/user.dart';
import 'package:warique_app/ui/kitchen/kitchen_board_page.dart';

import '../support/container.dart';
import '../support/fixtures.dart';

void main() {
  late FakeRealtime realtime;
  late RecordingHttp http;
  late FakeAlerts alerts;

  Future<void> pumpBoard(WidgetTester tester, {Size size = const Size(1024, 768)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: sessionOverrides(role: Role.kitchen, http: http, realtime: realtime, alerts: alerts),
        child: const MaterialApp(home: KitchenBoardPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    alerts = FakeAlerts();
    realtime = FakeRealtime();
    http = RecordingHttp((request) {
      if (request.method == 'PATCH') {
        return (200, orderJson(id: 1, status: 'IN_PREPARATION', updatedAt: '2026-10-03T15:01:00.000Z'));
      }
      return (200, [orderJson(id: 1), orderJson(id: 2, status: 'READY')]);
    });
  });

  testWidgets('shows the queue with dish notes and starts an order', (tester) async {
    await pumpBoard(tester);

    expect(find.text('Pendientes (1)'), findsOneWidget);
    expect(find.text('En preparación (0)'), findsOneWidget);
    expect(find.byTooltip('1 por recoger'), findsOneWidget);
    expect(find.text('2 × Ceviche'), findsOneWidget);
    expect(find.text('sin ají'), findsOneWidget);

    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();

    final patch = http.requests.last;
    expect(patch.url.path, '/api/orders/1/status');
    expect(http.bodyOf(http.requests.length - 1), {'status': 'IN_PREPARATION'});
    expect(find.text('Pendientes (0)'), findsOneWidget);
    expect(find.text('En preparación (1)'), findsOneWidget);
    expect(find.text('Listo'), findsOneWidget);
  });

  testWidgets('uses tabs on a phone', (tester) async {
    await pumpBoard(tester, size: const Size(400, 800));
    expect(find.byType(TabBar), findsOneWidget);
  });

  testWidgets('warns the kitchen when an order in its queue is cancelled', (tester) async {
    await pumpBoard(tester);

    realtime.emit(
      RealtimeEvent.orderUpdated,
      orderJson(
        id: 1,
        status: 'CANCELLED',
        cancelReason: 'cliente se retiró',
        updatedAt: '2026-10-03T15:03:00.000Z',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pedido cancelado'), findsOneWidget);
    expect(alerts.played.map((p) => p.tone), [AlertTone.cancelled]);
    expect(find.textContaining('Motivo: cliente se retiró'), findsOneWidget);
    expect(find.text('Pendientes (0)'), findsOneWidget);
  });

  testWidgets('keeps the screen on while the board is open', (tester) async {
    await pumpBoard(tester);
    expect(alerts.screenOn, [true]);

    await tester.pumpWidget(const SizedBox());
    expect(alerts.screenOn, [true, false]);
  });

  testWidgets('rings for a new order and again every 30 s until someone starts it', (tester) async {
    await pumpBoard(tester);
    realtime.emit(RealtimeEvent.orderCreated, orderJson(id: 3, createdAt: '2026-10-03T15:05:00.000Z'));
    await tester.pump();
    expect(alerts.played.map((p) => p.tone), [AlertTone.newOrder]);

    await tester.pump(const Duration(seconds: 30));
    expect(alerts.played, hasLength(2));

    http = RecordingHttp(
      (request) => (200, orderJson(id: 3, status: 'IN_PREPARATION', updatedAt: '2026-10-03T15:06:00.000Z')),
    );
    realtime.emit(
      RealtimeEvent.orderUpdated,
      orderJson(id: 3, status: 'IN_PREPARATION', updatedAt: '2026-10-03T15:06:00.000Z'),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(alerts.played, hasLength(2), reason: 'started on another device: no more reminders');
  });

  testWidgets('on the web asks for one tap before sound can play', (tester) async {
    alerts.gestureNeeded = true;
    await pumpBoard(tester);
    expect(find.byType(MaterialBanner), findsOneWidget);

    await tester.tap(find.text('Activar'));
    await tester.pump();
    expect(find.byType(MaterialBanner), findsNothing);
    expect(alerts.played.map((p) => p.tone), [AlertTone.newOrder], reason: 'plays once as a test');
    expect(alerts.screenOn.last, isTrue);
  });
}
