import 'package:flutter_test/flutter_test.dart';
import 'package:warique_app/core/money.dart';
import 'package:warique_app/models/menu.dart';
import 'package:warique_app/ui/waiter/cart.dart';

import '../support/fixtures.dart';

void main() {
  final ceviche = Dish.fromJson(dishJson(id: 5));
  final chicha = Dish.fromJson(dishJson(id: 6, name: 'Chicha', categoryId: 2));
  final menu = {ceviche.id: ceviche, chicha.id: chicha};

  test('adds, removes and totals in exact cents', () {
    final cart = Cart()
      ..add(5)
      ..add(5)
      ..add(6)
      ..remove(6);
    expect(cart.quantityOf(5), 2);
    expect(cart.quantityOf(6), 0);
    expect(cart.total(menu), Money.parse('37.00'));
    expect(cart.unitCount, 2);
  });

  test('notes are trimmed, cleared when empty and removed with the line', () {
    final cart = Cart()..add(5);
    cart.setNote(5, '  sin ají ');
    expect(cart.noteOf(5), 'sin ají');
    expect(cart.toItems().single.toJson(), {'dishId': 5, 'quantity': 1, 'notes': 'sin ají'});
    cart.remove(5);
    expect(cart.noteOf(5), isNull);
    expect(cart.isEmpty, isTrue);
  });

  test('respects backend limits', () {
    final cart = Cart();
    for (var i = 0; i < Cart.maxQuantity; i++) {
      expect(cart.add(5), isTrue);
    }
    expect(cart.add(5), isFalse);
  });

  test('flags dishes that became sold out or left the menu', () {
    final cart = Cart()
      ..add(5)
      ..add(99);
    final soldOut = {5: ceviche.copyWith(isAvailable: false)};
    expect(cart.unavailable(soldOut), [5, 99]);
  });
}
