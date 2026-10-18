import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

// One Web Audio context for the whole app: once a tap unlocks it, it can play any number of
// alerts without another gesture. A new <audio> element per alert is blocked by strict autoplay
// policies (some Android browsers) after the first one.
web.AudioContext? _context;
final _buffers = <String, web.AudioBuffer>{};

web.AudioContext _audio() {
  final existing = _context;
  if (existing != null) return existing;
  final context = web.AudioContext();
  // Any tap or key anywhere in the app unlocks sound
  void unlock(web.Event _) => context.resume();
  web.document.addEventListener('pointerdown', unlock.toJS);
  web.document.addEventListener('keydown', unlock.toJS);
  return _context = context;
}

/// True until the page is touched once (browsers keep sound off until then).
bool audioLocked() {
  try {
    return _audio().state != 'running';
  } catch (_) {
    return false; // no Web Audio: nothing a tap could fix, do not show the banner
  }
}

/// Plays a bundled asset ('assets/sounds/x.wav'). Returns false when the browser refused it.
Future<bool?> playTone(String asset) async {
  try {
    final context = _audio();
    if (context.state != 'running') {
      // Allowed only inside a tap (the "Activar" button): give it a moment, never hang
      await context.resume().toDart.timeout(const Duration(seconds: 1));
      if (context.state != 'running') return false;
    }
    final buffer = _buffers[asset] ??= await _load(context, asset);
    final source = context.createBufferSource()..buffer = buffer;
    source.connect(context.destination);
    source.start();
    return true;
  } catch (error) {
    debugPrint('Alert sound failed: $error');
    return false;
  }
}

Future<web.AudioBuffer> _load(web.AudioContext context, String asset) async {
  final response = await web.window.fetch(ui_web.assetManager.getAssetUrl(asset).toJS).toDart;
  final bytes = await response.arrayBuffer().toDart;
  return context.decodeAudioData(bytes).toDart;
}

void vibrate() {
  try {
    web.window.navigator.vibrate([300.toJS, 150.toJS, 300.toJS].toJS); // Android Chrome; iPhone ignores it
  } catch (_) {}
}
