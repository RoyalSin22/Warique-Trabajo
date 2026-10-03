import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:warique_app/models/user.dart';
import 'package:warique_app/ui/owner/menu_admin_page.dart';
import 'package:warique_app/ui/owner/report_page.dart';
import 'package:warique_app/ui/owner/tables_admin_page.dart';
import 'package:warique_app/ui/owner/users_admin_page.dart';

import '../../support/container.dart';
import '../../support/fixtures.dart';

void main() {
  late RecordingHttp server;

  Future<void> pump(
    WidgetTester tester,
    Widget page,
    (int, Object?) Function(http.Request request) handler, {
    Size size = const Size(400, 800),
  }) async {
    server = RecordingHttp(handler);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: sessionOverrides(role: Role.owner, http: server, realtime: FakeRealtime()),
        child: MaterialApp(
          locale: const Locale('es'),
          supportedLocales: const [Locale('es')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  int requestIndex(String method, String path) =>
      server.requests.lastIndexWhere((r) => r.method == method && r.url.path == path);

  group('Cierre del día', () {
    (int, Object?) reportApi(http.Request request) => switch (request.url.path) {
      '/api/reports/daily' => (
        200,
        {
          'date': request.url.queryParameters['date'],
          'orders': [
            {'status': 'DELIVERED', 'count': 3, 'total': '90.5'},
            {'status': 'PENDING', 'count': 1, 'total': '20'},
            {'status': 'CANCELLED', 'count': 1, 'total': '15'},
          ],
          'sales': '110.50',
          'collectedByMethod': [
            {'method': 'CASH', 'count': 2, 'amount': '50.50'},
            {'method': 'YAPE', 'count': 1, 'amount': '40.00'},
          ],
          'collectedTotal': '90.50',
          'pendingBalance': '20.00',
          'topDishes': [
            {'dishId': 1, 'dishName': 'Ceviche', 'quantity': 5},
          ],
        },
      ),
      '/api/reports/payments' => (
        200,
        {
          'date': request.url.queryParameters['date'],
          'payments': [
            {
              'id': 1,
              'orderId': 3,
              'method': 'YAPE',
              'amount': '40',
              'amountReceived': null,
              'changeGiven': null,
              'operationNumber': '889911',
              'createdAt': '2026-10-03T18:00:00.000Z',
              'registeredBy': 'Rosa Mozo',
              'target': 'Mesa 2',
              'orderType': 'DINE_IN',
            },
            {
              'id': 2,
              'orderId': 4,
              'method': 'CASH',
              'amount': '50.5',
              'amountReceived': '60',
              'changeGiven': '9.5',
              'operationNumber': null,
              'createdAt': '2026-10-03T18:10:00.000Z',
              'registeredBy': 'Rosa Mozo',
              'target': 'Juan',
              'orderType': 'TAKEAWAY',
            },
          ],
        },
      ),
      '/api/reports/backup-status' => (
        200,
        {
          'configured': true,
          'ok': true,
          'needsAttention': true,
          'copied': false,
          'time': '2026-10-03T04:30:00.000Z',
          'ageHours': 8.0,
          'file': 'x.zip',
          'sizeBytes': 2800,
          'error': null,
        },
      ),
      _ => (404, {'message': 'Not found'}),
    };

    testWidgets('shows totals, warns about the backup and filters payments to reconcile', (tester) async {
      // Phone width; tall enough to show the whole closing without fighting nested scrollables
      await pump(tester, const ReportPage(), reportApi, size: const Size(400, 1800));
      // The day's list, not the tab bar or the page view of the tabs
      final dayList = find
          .descendant(of: find.byType(RefreshIndicator), matching: find.byType(Scrollable))
          .first;

      expect(find.text('S/ 110.50'), findsOneWidget); // sales
      expect(find.text('S/ 20.00'), findsOneWidget); // pending
      expect(find.text('4 pedidos'), findsOneWidget); // cancelled excluded
      expect(find.textContaining('NO se copió'), findsOneWidget);
      expect(find.textContaining('Hoy, '), findsOneWidget);

      await tester.scrollUntilVisible(find.widgetWithText(ChoiceChip, 'Yape'), 200, scrollable: dayList);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Yape'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.textContaining('Total (1 pagos)'), 200, scrollable: dayList);
      expect(find.textContaining('Op. 889911'), findsOneWidget);
      expect(find.textContaining('vuelto S/ 9.50'), findsNothing); // cash payment filtered out

      // Previous day loads that date
      await tester.scrollUntilVisible(find.byTooltip('Día anterior'), -200, scrollable: dayList);
      await tester.tap(find.byTooltip('Día anterior'));
      await tester.pumpAndSettle();
      final dates = server.requests
          .where((r) => r.url.path == '/api/reports/daily')
          .map((r) => r.url.queryParameters['date'])
          .toSet();
      expect(dates, hasLength(2));
    });
  });

  group('Menú', () {
    late List<Map<String, dynamic>> dishes;

    (int, Object?) menuApi(http.Request request) => switch ((request.method, request.url.path)) {
      ('GET', '/api/categories') => (
        200,
        [
          {'id': 1, 'name': 'Fondos', 'sortOrder': 1, 'isActive': true},
          {'id': 2, 'name': 'Bebidas', 'sortOrder': 2, 'isActive': true},
        ],
      ),
      ('GET', '/api/dishes') => (200, dishes),
      ('POST', '/api/dishes') => (201, dishJson(id: 9, name: 'Lomo saltado')),
      ('PATCH', '/api/dishes/5/availability') => (200, dishJson(id: 5, isAvailable: false)),
      _ => (404, {'message': 'Not found'}),
    };

    setUp(
      () => dishes = [
        dishJson(id: 5),
        {...dishJson(id: 6, name: 'Seco'), 'isActive': false},
      ],
    );

    testWidgets('lists removed dishes, toggles sold out and creates a dish', (tester) async {
      await pump(tester, const MenuAdminPage(), menuApi);
      expect(server.requests.first.url.queryParameters['includeInactive'], 'true');
      expect(find.text('retirado'), findsOneWidget);
      expect(find.text('Reactivar'), findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(requestIndex('PATCH', '/api/dishes/5/availability'), isNot(-1));
      expect(server.bodyOf(requestIndex('PATCH', '/api/dishes/5/availability')), {'isAvailable': false});

      await tester.tap(find.text('Nuevo plato'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      expect(find.text('Obligatorio'), findsOneWidget);
      expect(find.text('Precio inválido'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Nombre'), ' Lomo saltado ');
      await tester.enterText(find.widgetWithText(TextFormField, 'Precio'), '24,5');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(server.bodyOf(requestIndex('POST', '/api/dishes')), {
        'categoryId': 1,
        'name': 'Lomo saltado',
        'price': 24.5,
      });
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  testWidgets('Mesas: explains why a table with open orders cannot be deactivated', (tester) async {
    await pump(
      tester,
      const TablesAdminPage(),
      (request) => switch (request.method) {
        'GET' => (
          200,
          [
            {'id': 3, 'label': 'Mesa 3', 'isActive': true},
          ],
        ),
        _ => (409, {'statusCode': 409, 'message': 'The table has open orders'}),
      },
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('La mesa tiene pedidos abiertos'), findsOneWidget);
  });

  group('Usuarios', () {
    (int, Object?) usersApi(http.Request request) => switch ((request.method, request.url.path)) {
      ('GET', '/api/users') => (
        200,
        [
          {'id': 1, 'fullName': 'Usuario Dueño', 'username': 'u', 'role': 'OWNER', 'isActive': true},
          {'id': 2, 'fullName': 'Rosa Mozo', 'username': 'rosa', 'role': 'WAITER', 'isActive': false},
        ],
      ),
      ('POST', '/api/users') => (
        201,
        {'id': 3, 'fullName': 'Carlos', 'username': 'carlos', 'role': 'KITCHEN', 'isActive': true},
      ),
      _ => (404, {'message': 'Not found'}),
    };

    testWidgets('creates a kitchen account with validated fields', (tester) async {
      await pump(tester, const UsersAdminPage(), usersApi);
      expect(find.text('desactivado'), findsOneWidget);
      expect(find.text('tú'), findsOneWidget);

      await tester.tap(find.text('Nuevo usuario'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Nombre completo'), 'Carlos');
      await tester.enterText(find.widgetWithText(TextFormField, 'Usuario'), 'Carlos P');
      await tester.enterText(find.widgetWithText(TextFormField, 'Clave inicial'), 'corta');
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      expect(find.textContaining('minúsculas, números'), findsWidgets);
      expect(find.text('Mínimo 8 caracteres'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Usuario'), 'Carlos');
      await tester.enterText(find.widgetWithText(TextFormField, 'Clave inicial'), 'clave-larga-1');
      await tester.tap(find.byType(DropdownButtonFormField<Role>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cocina').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(server.bodyOf(requestIndex('POST', '/api/users')), {
        'fullName': 'Carlos',
        'username': 'carlos',
        'password': 'clave-larga-1',
        'role': 'KITCHEN',
      });
    });

    testWidgets('the owner cannot deactivate or demote themselves', (tester) async {
      await pump(tester, const UsersAdminPage(), usersApi);
      await tester.tap(find.text('Usuario Dueño'));
      await tester.pumpAndSettle();
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.onChanged, isNull);
      expect(find.text('No puedes desactivar tu propia cuenta'), findsOneWidget);
    });
  });
}
