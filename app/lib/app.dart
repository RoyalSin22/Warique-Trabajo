import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/session.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';
import 'ui/widgets/common.dart';

class WariqueApp extends StatelessWidget {
  const WariqueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Warique',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFB23A1E), // ají panca
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
      ),
      // Spanish for Material texts (date picker, tooltips, copy/paste menu)
      locale: const Locale('es', 'PE'),
      supportedLocales: const [Locale('es', 'PE'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _SessionGate(),
    );
  }
}

class _SessionGate extends ConsumerWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return switch (session) {
      AsyncData(value: null) => const LoginPage(),
      // The key rebuilds every screen (and its providers' consumers) for a new user
      AsyncData(value: final active?) => HomePage(key: ValueKey(active.token)),
      AsyncError(:final error) => Scaffold(
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ErrorRetryView(error: error, onRetry: ref.read(sessionProvider.notifier).retry),
            TextButton(
              onPressed: ref.read(sessionProvider.notifier).logout,
              child: const Text('Cambiar servidor o usuario'),
            ),
          ],
        ),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}
