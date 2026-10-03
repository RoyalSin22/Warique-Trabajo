import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warique_app/models/order.dart';
import 'package:warique_app/models/user.dart';

/// The app copies the backend transition table to decide which buttons to show.
/// This test fails if `backend/src/orders/order-status.ts` changes and the copy does not.
void main() {
  final file = File('../backend/src/orders/order-status.ts');

  test('client transition table matches the backend', () {
    final source = file.readAsStringSync();
    final block = RegExp(r'ORDER_TRANSITIONS[^=]*=\s*\{([\s\S]*?)\n\};').firstMatch(source)!.group(1)!;

    final backend = <String, Map<String, Set<String>>>{};
    String? from;
    for (final line in block.split('\n')) {
      final fromMatch = RegExp(r'^\s{2}\[OrderStatus\.(\w+)\]:\s*\{').firstMatch(line);
      if (fromMatch != null) {
        from = fromMatch.group(1);
        backend[from!] = {};
        continue;
      }
      final toMatch = RegExp(r'^\s{4}\[OrderStatus\.(\w+)\]:\s*\[([^\]]*)\]').firstMatch(line);
      if (toMatch != null && from != null) {
        backend[from]![toMatch.group(1)!] = RegExp(r'Role\.(\w+)')
            .allMatches(toMatch.group(2)!)
            .map((m) => m.group(1)!)
            .toSet();
      }
    }

    final client = {
      for (final entry in orderTransitions.entries)
        entry.key.api: {
          for (final to in entry.value.entries) to.key.api: to.value.map((Role r) => r.api).toSet(),
        },
    };

    expect(backend, hasLength(OrderStatus.values.length));
    expect(client, backend);
  }, skip: file.existsSync() ? false : 'backend sources not available');
}
