import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warique_app/models/user.dart';
import 'package:warique_app/ui/owner/export_sheet.dart';

import '../../support/container.dart';
import '../../support/fixtures.dart';

void main() {
  late RecordingHttp server;
  late List<Uri> opened;

  Future<void> pump(WidgetTester tester, DateTime today) async {
    opened = [];
    server = RecordingHttp(
      (request) => (
        200,
        {
          'url': '/api/reports/export/signed-token',
          'fileName': 'warique-gastos.csv',
          'expiresInSeconds': 120,
        },
      ),
    );
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...sessionOverrides(role: Role.owner, http: server, realtime: FakeRealtime()),
          downloadOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: MaterialApp(
          locale: const Locale('es'),
          supportedLocales: const [Locale('es')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: ExportSheet(today: today)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('downloads last month by default through a signed link', (tester) async {
    await pump(tester, DateTime(2026, 10, 3));
    expect(find.text('Del 1 set 2026 al 30 set 2026'), findsOneWidget);

    await tester.tap(find.text('Gastos'));
    await tester.pumpAndSettle();

    expect(jsonDecode(server.requests.single.body), {
      'kind': 'gastos',
      'from': '2026-09-01',
      'to': '2026-09-30',
    });
    expect(opened.single.toString(), '$testServer/api/reports/export/signed-token');
    expect(find.text('Descargando warique-gastos.csv'), findsOneWidget);
  });

  testWidgets('"mes anterior" in January is December of the previous year; "este mes" ends today', (
    tester,
  ) async {
    await pump(tester, DateTime(2026, 1, 15));
    expect(find.text('Del 1 dic 2025 al 31 dic 2025'), findsOneWidget);
    await tester.tap(find.text('Este mes'));
    await tester.pumpAndSettle();
    expect(find.text('Del 1 ene 2026 al 15 ene 2026'), findsOneWidget);
  });
}
