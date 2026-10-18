import 'package:flutter/services.dart';

bool audioLocked() => false;

/// Not handled here: the Android app plays alerts with audioplayers.
Future<bool?> playTone(String asset) async => null;

void vibrate() => HapticFeedback.vibrate();
