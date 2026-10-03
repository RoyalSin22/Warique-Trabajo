import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:warique_app/core/dates.dart';
import 'package:warique_app/data/realtime_client.dart';
import 'package:warique_app/models/user.dart';
import 'package:warique_app/ui/inventory/supplies_page.dart';
import 'package:warique_app/ui/owner/cash_card.dart';
import 'package:warique_app/ui/owner/expense_form_page.dart';

import '../support/container.dart';
import '../support/fixtures.dart';

Map<String, dynamic> supplyJson({
  int id = 1,
  String name = 'Limón',
  String unit = 'KG',
  String stock = '2.5',
  String minStock = '3',
  bool isLow = true,
  bool isActive = true,
}) => {
  'id': id,
  'name': name,
  'unit': unit,
  'stock': stock,
  'minStock': minStock,
  'isActive': isActive,
  'isLow': isLow,
  'createdAt': '2026-10-03T15:00:00.000Z',
  'updatedAt': '2026-10-03T15:00:00.000Z',
};

void main() {
  late RecordingHttp server;
  late FakeRealtime realtime;

  Future<void> pump(
    WidgetTester tester,
    Widget page,
    Role role,
    (int, Object?) Function(http.Request) handler,
  ) async {
    server = RecordingHttp(handler);
    realtime = FakeRealtime();
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: sessionOverrides(role: role, http: server, realtime: realtime),
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

  group('Insumos (cocina)', () {
    (int, Object?) api(http.Request request) => switch ((request.method, request.url.path)) {
      ('GET', '/api/supplies') => (
        200,
        [
          supplyJson(id: 2, name: 'Aceite', unit: 'L', stock: '4', minStock: '1', isLow: false),
          supplyJson(),
          supplyJson(id: 3, name: 'Huevos', unit: 'UNIDAD', stock: '30', minStock: '0', isLow: false),
        ],
      ),
      ('POST', '/api/supplies/1/movements') => (201, supplyJson(stock: '2')),
      _ => (404, {'message': 'Not found'}),
    };

    testWidgets('shows low stock first and registers waste with an idempotency key', (tester) async {
      await pump(tester, const SuppliesPage(), Role.kitchen, api);

      expect(find.text('Por comprar (1)'), findsOneWidget);
      // Low stock sorted before Aceite ("Limón" also appears in the "Por comprar" card above)
      expect(
        tester.getTopLeft(find.text('Limón').last).dy,
        lessThan(tester.getTopLeft(find.text('Aceite')).dy),
      );
      expect(find.text('2.5 kg'), findsOneWidget);
      expect(find.text('Stock bajo'), findsOneWidget);
      expect(find.byTooltip('Nuevo insumo'), findsNothing); // only the owner creates supplies

      await tester.tap(find.text('Limón').last);
      await tester.pumpAndSettle();
      expect(find.text('Editar nombre o mínimo'), findsNothing);
      await tester.tap(find.text('Registrar merma'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, '¿Cuánto se perdió?'), '3');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Solo hay 2.5 kg'), findsOneWidget); // cannot waste more than the stock

      await tester.enterText(find.widgetWithText(TextFormField, '¿Cuánto se perdió?'), '0,5');
      await tester.enterText(find.widgetWithText(TextFormField, 'Nota'), 'se secaron');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final post = server.requests.last;
      expect(post.url.path, '/api/supplies/1/movements');
      expect(jsonDecode(post.body), {'type': 'WASTE', 'quantity': 0.5, 'note': 'se secaron'});
      expect(post.headers['Idempotency-Key'], hasLength(36));
      expect(find.text('2 kg'), findsOneWidget);
      expect(find.text('Limón: quedan 2 kg'), findsOneWidget);
    });

    testWidgets('whole units reject decimals; live updates from the owner refresh the stock', (tester) async {
      await pump(tester, const SuppliesPage(), Role.kitchen, api);

      await tester.tap(find.text('Huevos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar conteo'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, '¿Cuánto hay ahora?'), '12.5');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Solo números enteros'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // The owner registered a purchase of Huevos on another device
      realtime.emit(
        RealtimeEvent.supplyUpdated,
        supplyJson(id: 3, name: 'Huevos', unit: 'UNIDAD', stock: '60', minStock: '0', isLow: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('60 und.'), findsOneWidget);
    });
  });

  testWidgets('a supply purchase sends its lines and the server-side total is shown first', (tester) async {
    await pump(tester, ExpenseFormPage(day: DateTime(2026, 10, 2)), Role.owner, (request) {
      return switch ((request.method, request.url.path)) {
        ('GET', '/api/supplies') => (
          200,
          [supplyJson(), supplyJson(id: 2, name: 'Pescado', stock: '0', minStock: '2')],
        ),
        ('POST', '/api/expenses') => (
          201,
          {
            'id': 1,
            'businessDate': '2026-10-02',
            'category': 'INSUMOS',
            'description': 'Mercado',
            'amount': '122.3',
            'paidWith': 'CASH',
            'isVoid': false,
            'voidReason': null,
            'createdBy': 'Dueño',
            'createdAt': '2026-10-02T15:00:00.000Z',
            'items': <Object>[],
          },
        ),
        _ => (404, {'message': 'Not found'}),
      };
    });

    expect(find.text('Gasto del 2 oct'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Descripción'), 'Mercado');
    await tester.tap(find.text('Insumo 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pescado').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Cantidad').first, '5.5');
    await tester.enterText(find.widgetWithText(TextFormField, 'Precio pagado').first, '110');

    await tester.tap(find.text('Agregar otro insumo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insumo 2'));
    await tester.pumpAndSettle();
    // Pescado is already in line 1: only Limón is offered
    expect(find.text('Pescado'), findsOneWidget);
    await tester.tap(find.text('Limón').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Cantidad').last, '3');
    await tester.enterText(find.widgetWithText(TextFormField, 'Precio pagado').last, '12.30');
    await tester.pumpAndSettle();
    expect(find.text('S/ 122.30'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Monto'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Guardar gasto'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Guardar gasto'));
    await tester.pumpAndSettle();

    final post = server.requests.lastWhere((r) => r.method == 'POST');
    expect(jsonDecode(post.body), {
      'businessDate': '2026-10-02',
      'category': 'INSUMOS',
      'description': 'Mercado',
      'paidWith': 'CASH',
      'items': [
        {'supplyId': 2, 'quantity': 5.5, 'cost': 110},
        {'supplyId': 1, 'quantity': 3, 'cost': 12.3},
      ],
    });
    expect(post.headers['Idempotency-Key'], isNotEmpty);
  });

  testWidgets('a non-purchase expense asks for the amount', (tester) async {
    await pump(tester, ExpenseFormPage(day: dateOnly(DateTime.now())), Role.owner, (request) {
      return switch ((request.method, request.url.path)) {
        ('GET', '/api/supplies') => (200, <Object>[]),
        _ => (400, {'message': 'x'}),
      };
    });
    await tester.tap(find.text('Insumos').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gas').last);
    await tester.pumpAndSettle();
    expect(find.text('Insumos comprados'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Monto'), findsOneWidget);
  });

  group('Arqueo de caja', () {
    Map<String, dynamic> cashJson({
      Map<String, dynamic>? session,
      String opening = '0',
      String expected = '0',
    }) => {
      'date': '2026-10-03',
      'session': session,
      'live': {
        'openingAmount': opening,
        'cashSales': '250.40',
        'cashExpenses': '35.00',
        'expected': expected,
      },
    };

    Map<String, dynamic> sessionJson({bool closed = false}) => {
      'openingAmount': '100',
      'openedByName': 'Dueño',
      'openedAt': '2026-10-03T15:00:00.000Z',
      'expectedAmount': closed ? '315.4' : null,
      'countedAmount': closed ? '310.4' : null,
      'difference': closed ? '-5' : null,
      'notes': null,
      'closedByName': closed ? 'Dueño' : null,
      'closedAt': closed ? '2026-10-03T23:30:00.000Z' : null,
    };

    Widget card() => const Scaffold(
      body: SingleChildScrollView(child: CashCard(date: '2026-10-03')),
    );

    testWidgets('opens the drawer with the change fund', (tester) async {
      var opened = false;
      await pump(tester, card(), Role.owner, (request) {
        if (request.method == 'POST') opened = true;
        return (
          200,
          opened
              ? cashJson(session: sessionJson(), opening: '100', expected: '315.4')
              : cashJson(expected: '215.4'),
        );
      });

      await tester.tap(find.text('Abrir caja'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Fondo de cambio'), '100');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(jsonDecode(server.requests.firstWhere((r) => r.method == 'POST').body), {
        'date': '2026-10-03',
        'openingAmount': 100,
      });
      expect(find.text('S/ 315.40'), findsOneWidget); // debe haber
      expect(find.text('Cerrar caja'), findsOneWidget);
    });

    testWidgets('a closed count shows the shortage in words, not only color', (tester) async {
      await pump(
        tester,
        card(),
        Role.owner,
        (request) => (200, cashJson(session: sessionJson(closed: true), opening: '100', expected: '315.4')),
      );
      expect(find.text('Faltan S/ 5.00'), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);
      expect(find.text('S/ 310.40'), findsOneWidget);
      expect(find.text('Volver a contar'), findsOneWidget);
      expect(find.textContaining('después del cierre'), findsNothing);
    });

    testWidgets('warns when payments arrived after closing', (tester) async {
      await pump(
        tester,
        card(),
        Role.owner,
        (request) => (200, cashJson(session: sessionJson(closed: true), opening: '100', expected: '330.4')),
      );
      expect(find.textContaining('ahora debería haber S/ 330.40'), findsOneWidget);
    });
  });
}
