import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warique_app/data/realtime_client.dart';
import 'package:warique_app/models/user.dart';
import 'package:warique_app/ui/waiter/order_detail_page.dart';
import 'package:warique_app/ui/waiter/waiter_orders_page.dart';

import '../support/container.dart';
import '../support/fixtures.dart';

void main() {
  late FakeRealtime realtime;
  late RecordingHttp http;

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(400, 800); // phone
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: sessionOverrides(role: Role.waiter, http: http, realtime: realtime),
        child: MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => realtime = FakeRealtime());

  testWidgets('creates a dine-in order', (tester) async {
    http = RecordingHttp(
      (request) => switch ((request.method, request.url.path)) {
        ('GET', '/api/orders') => (200, <Object>[]),
        ('GET', '/api/dishes') => (
          200,
          [
            dishJson(id: 5),
            dishJson(id: 6, name: 'Chicha morada', categoryId: 2),
            dishJson(id: 7, name: 'Arroz con pato', isAvailable: false),
          ],
        ),
        ('GET', '/api/tables') => (
          200,
          [
            {'id': 3, 'label': 'Mesa 3', 'isActive': true},
          ],
        ),
        ('POST', '/api/orders') => (201, orderJson(id: 9)),
        _ => (404, {'message': 'Not found'}),
      },
    );
    await pump(tester, const WaiterOrdersPage());
    expect(find.text('Nada pendiente por ahora'), findsOneWidget);

    await tester.tap(find.text('Nuevo pedido'));
    await tester.pumpAndSettle();

    // Sold-out dish is visible but cannot be added
    expect(find.textContaining('AGOTADO'), findsOneWidget);

    await tester.tap(find.text('Ceviche'));
    await tester.tap(find.text('Ceviche'));
    await tester.pump();
    expect(find.text('S/ 37.00'), findsOneWidget);

    // Table is required
    await tester.tap(find.text('Revisar y enviar'));
    await tester.pump();
    expect(find.text('Selecciona una mesa'), findsOneWidget);

    await tester.tap(find.text('Mesa 3'));
    await tester.pump();
    await tester.tap(find.text('Revisar y enviar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar a cocina'));
    await tester.pumpAndSettle();

    final post = http.requests.indexWhere((r) => r.method == 'POST');
    expect(http.bodyOf(post), {
      'orderType': 'DINE_IN',
      'tableId': 3,
      'items': [
        {'dishId': 5, 'quantity': 2},
      ],
    });
    expect(find.text('Pedido #9 enviado a cocina'), findsOneWidget);
    expect(find.text('#9 · Mesa 3'), findsOneWidget);
  });

  testWidgets('registers a cash payment and shows the change', (tester) async {
    http = RecordingHttp(
      (request) => switch ((request.method, request.url.path)) {
        ('GET', '/api/orders') => (200, [orderJson(id: 4, status: 'DELIVERED')]),
        ('GET', '/api/orders/4') => (200, orderJson(id: 4, status: 'DELIVERED', payments: [])),
        ('POST', '/api/orders/4/payments') => (
          201,
          orderJson(
            id: 4,
            status: 'DELIVERED',
            paymentStatus: 'PAID',
            updatedAt: '2026-10-03T15:30:00.000Z',
            payments: [
              {
                'id': 1,
                'method': 'CASH',
                'amount': '40',
                'amountReceived': '50',
                'changeGiven': '10',
                'operationNumber': null,
                'createdAt': '2026-10-03T15:30:00.000Z',
              },
            ],
          ),
        ),
        _ => (404, {'message': 'Not found'}),
      },
    );
    await pump(tester, const OrderDetailPage(orderId: 4));

    expect(find.text('Cobrar S/ 40.00'), findsOneWidget);
    expect(find.text('Entregar'), findsNothing); // already delivered
    await tester.tap(find.text('Cobrar S/ 40.00'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('S/ 50'));
    await tester.pump();
    expect(find.text('S/ 10.00'), findsOneWidget); // change

    await tester.tap(find.text('Registrar S/ 40.00'));
    await tester.pumpAndSettle();

    final post = http.requests.indexWhere((r) => r.method == 'POST');
    expect(http.bodyOf(post), {'method': 'CASH', 'amount': 40, 'amountReceived': 50});
    expect(find.text('Pedido #4 pagado'), findsOneWidget);
    expect(find.textContaining('Cobrar'), findsNothing);
  });

  testWidgets('Yape requires a valid operation number', (tester) async {
    http = RecordingHttp(
      (request) => switch ((request.method, request.url.path)) {
        ('GET', '/api/orders') => (200, <Object>[]),
        ('GET', '/api/orders/4') => (200, orderJson(id: 4, status: 'READY', payments: [])),
        _ => (404, {'message': 'Not found'}),
      },
    );
    await pump(tester, const OrderDetailPage(orderId: 4));

    expect(find.text('Entregar'), findsOneWidget);
    await tester.tap(find.text('Cobrar S/ 40.00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yape'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).last, '12');
    await tester.tap(find.text('Registrar S/ 40.00'));
    await tester.pump();

    expect(find.text('Entre 4 y 30 letras o dígitos'), findsOneWidget);
    expect(http.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('alerts the waiter when the kitchen marks an order ready', (tester) async {
    http = RecordingHttp((request) => (200, [orderJson(id: 1, status: 'IN_PREPARATION')]));
    await pump(tester, const WaiterOrdersPage());

    realtime.emit(
      RealtimeEvent.orderUpdated,
      orderJson(id: 1, status: 'READY', updatedAt: '2026-10-03T15:20:00.000Z'),
    );
    await tester.pumpAndSettle();

    expect(find.text('¡Listo para entregar! #1 · Mesa 3'), findsOneWidget);
    expect(find.text('Listos para entregar (1)'), findsOneWidget);
  });
}
