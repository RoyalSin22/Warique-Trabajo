import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:warique_app/core/api_client.dart';
import 'package:warique_app/core/ids.dart';
import 'package:warique_app/models/user.dart';
import 'package:warique_app/state/realtime.dart';
import 'package:warique_app/state/session.dart';
import 'package:warique_app/ui/owner/connect_devices_page.dart';
import 'package:warique_app/ui/waiter/new_order_page.dart';
import 'package:warique_app/ui/waiter/order_detail_page.dart';

import '../support/container.dart';
import '../support/fixtures.dart';

http.Response _json(int status, Object? body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('request ids are UUID v4 and unique', () {
    final ids = {for (var i = 0; i < 500; i++) newRequestId()};
    expect(ids, hasLength(500));
    expect(
      ids.first,
      matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
    );
  });

  Future<void> pumpWith(
    WidgetTester tester,
    Widget page,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSessionProvider.overrideWithValue(testSession(Role.waiter)),
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: testServer, token: 'token', httpClient: MockClient(handler)),
          ),
          realtimeClientProvider.overrideWithValue(FakeRealtime()),
          realtimeConnectedProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<http.Response> menuAndTables(http.Request request) async => switch (request.url.path) {
    '/api/dishes' => _json(200, [dishJson(id: 5), dishJson(id: 6, name: 'Chicha morada', categoryId: 2)]),
    '/api/tables' => _json(200, [
      {'id': 3, 'label': 'Mesa 3', 'isActive': true},
      {'id': 4, 'label': 'Mesa 4', 'isActive': true},
    ]),
    _ => _json(404, {'message': 'Not found'}),
  };

  testWidgets('a retry after a network failure reuses the key; changing the order renews it', (tester) async {
    final keys = <String?>[];
    var postAttempts = 0;
    await pumpWith(tester, const NewOrderPage(initialTableId: 3), (request) async {
      if (request.method != 'POST') return menuAndTables(request);
      keys.add(request.headers['Idempotency-Key']);
      postAttempts++;
      if (postAttempts <= 2) throw http.ClientException('connection reset'); // response lost
      return _json(201, orderJson(id: 9));
    });

    Future<void> send() async {
      await tester.tap(find.text('Revisar y enviar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar a cocina'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Ceviche'));
    await tester.pump();
    await send();
    expect(find.textContaining('no se duplicará'), findsOneWidget);
    await send(); // same order, same key
    expect(keys[0], isNotNull);
    expect(keys[1], keys[0]);

    await tester.tap(find.text('Ceviche')); // the order changes: it is a different order now
    await tester.pump();
    await send();
    expect(keys[2], isNot(keys[0]));
  });

  testWidgets('"Otro pedido para esta mesa" opens a new order for the same table', (tester) async {
    Map<String, dynamic>? posted;
    await pumpWith(tester, const OrderDetailPage(orderId: 1), (request) async {
      if (request.url.path == '/api/orders/1') {
        return _json(200, orderJson(id: 1, status: 'IN_PREPARATION', payments: []));
      }
      if (request.url.path == '/api/orders' && request.method == 'GET') return _json(200, [orderJson(id: 1)]);
      if (request.method == 'POST') {
        posted = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(201, orderJson(id: 2));
      }
      return menuAndTables(request);
    });

    await tester.tap(find.byTooltip('Otro pedido para esta mesa'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Mesa 3')).selected, isTrue);

    await tester.tap(find.text('Ceviche'));
    await tester.pump();
    await tester.tap(find.text('Revisar y enviar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar a cocina'));
    await tester.pumpAndSettle();

    expect(posted, containsPair('tableId', 3));
    expect(find.text('Pedido #2 enviado a cocina'), findsOneWidget);
    expect(find.text('Pedido #1'), findsOneWidget); // back on the original order
  });

  testWidgets('connect devices shows the server address as a QR code', (tester) async {
    await pumpWith(tester, const ConnectDevicesPage(), menuAndTables);
    expect(find.text(testServer), findsOneWidget);
    expect(tester.widget<QrImageView>(find.byType(QrImageView)).semanticsLabel, 'Código QR de $testServer');
  });
}
