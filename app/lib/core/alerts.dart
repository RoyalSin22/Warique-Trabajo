import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'device_io.dart' if (dart.library.js_interop) 'device_web.dart' as device;

enum AlertTone {
  newOrder('sounds/nuevo_pedido.wav'),
  ready('sounds/pedido_listo.wav'),
  cancelled('sounds/pedido_cancelado.wav');

  const AlertTone(this.asset);

  final String asset;
}

/// Sounds, vibration and "keep the screen on" for the kitchen board and the waiter's phone.
/// Every call swallows platform errors: an alert that cannot play must never break the screen.
class Alerts {
  AudioPlayer? _player;

  /// On the web nothing plays until the page was touched once (browser autoplay rule).
  bool get needsUserGesture => kIsWeb && !device.userHasInteracted();

  Future<void> play(AlertTone tone, {bool vibrate = false}) async {
    if (vibrate) device.vibrate();
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.play(AssetSource(tone.asset));
    } catch (error) {
      debugPrint('Alert sound failed: $error');
    }
  }

  /// Kitchen tablet: the screen must not lock while orders can arrive.
  Future<void> keepScreenOn(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (error) {
      debugPrint('Wakelock failed: $error');
    }
  }

  void dispose() => _player?.dispose();
}

final alertsProvider = Provider<Alerts>((ref) {
  final alerts = Alerts();
  ref.onDispose(alerts.dispose);
  return alerts;
});
