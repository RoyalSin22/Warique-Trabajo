import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Browsers only play sound (and keep the screen on) after the person touched the page once.
bool userHasInteracted() {
  try {
    return web.window.navigator.userActivation.hasBeenActive;
  } catch (_) {
    return true; // old browser without the API: assume yes, the banner would only confuse
  }
}

void vibrate() {
  try {
    web.window.navigator.vibrate([300.toJS, 150.toJS, 300.toJS].toJS); // Android Chrome; iPhone ignores it
  } catch (_) {}
}
