import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:warique_app/data/settings_store.dart';
import 'package:warique_app/state/session.dart';
import 'package:warique_app/ui/login_page.dart';

void main() {
  testWidgets('validates required fields and the server address', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: LoginPage()),
      ),
    );

    await tester.tap(find.text('Ingresar'));
    await tester.pump();

    expect(find.text('Ingresa tu usuario'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
    expect(find.text('Ingresa la dirección del servidor'), findsOneWidget);
  });

  test('normalizes typed server addresses', () {
    expect(normalizeServerUrl('192.168.1.50:3000/'), 'http://192.168.1.50:3000');
    expect(normalizeServerUrl('http://pc-caja:3000/api'), 'http://pc-caja:3000');
    expect(validateServerUrl('192.168.1.50:3000'), isNull);
    expect(validateServerUrl('ftp://x'), isNotNull);
  });
}
