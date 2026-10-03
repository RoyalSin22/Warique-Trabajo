import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import '../../state/session.dart';
import '../widgets/common.dart';

/// Whether the release package includes the Android APK (build-release.ps1 -WithApk).
final _apkAvailableProvider = FutureProvider.autoDispose<bool>((ref) async {
  final url = Uri.parse('${ref.watch(currentSessionProvider).serverUrl}/descargas/warique.apk');
  try {
    final response = await http.head(url).timeout(const Duration(seconds: 5));
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
});

/// QR codes so staff phones open the app without typing the PC's IP.
class ConnectDevicesPage extends ConsumerWidget {
  const ConnectDevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(currentSessionProvider).serverUrl;
    final apkAvailable = ref.watch(_apkAvailableProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Conectar celulares')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'El celular debe estar conectado al Wi-Fi del local. Abre la cámara y apunta al código.',
          ),
          const SizedBox(height: 16),
          _QrCard(
            title: 'Abrir en el navegador (Chrome)',
            url: serverUrl,
            hint: 'Luego, en el menú de Chrome: "Agregar a pantalla principal".',
          ),
          if (apkAvailable)
            _QrCard(
              title: 'Instalar la app Android',
              url: '$serverUrl/descargas/warique.apk',
              hint:
                  'Permite "Instalar apps desconocidas" para Chrome. Al abrirla, usa como servidor:\n$serverUrl',
            ),
        ],
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.title, required this.url, required this.hint});

  final String title;
  final String url;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            QrImageView(
              data: url,
              size: 220,
              backgroundColor: Colors.white,
              semanticsLabel: 'Código QR de $url',
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: SelectableText(url, style: theme.textTheme.bodyLarge)),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copiar dirección',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    showInfoSnack(context, 'Dirección copiada');
                  },
                ),
              ],
            ),
            Text(hint, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
