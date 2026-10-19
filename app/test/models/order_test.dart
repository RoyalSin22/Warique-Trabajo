import 'package:flutter_test/flutter_test.dart';
import 'package:warique_app/core/money.dart';
import 'package:warique_app/models/order.dart';
import 'package:warique_app/models/user.dart';

import '../support/fixtures.dart';

void main() {
  test('parses a detail response from the backend', () {
    final order = Order.fromJson(
      orderJson(
        payments: [
          {
            'id': 1,
            'method': 'CASH',
            'amount': '20',
            'amountReceived': '50',
            'changeGiven': '30',
            'operationNumber': null,
            'createdAt': '2026-10-03T15:05:00.000Z',
          },
        ],
        paymentStatus: 'PARTIAL',
      ),
    );

    expect(order.target, 'Mesa 3');
    expect(order.total, Money.parse('40'));
    expect(order.items.first.unitPrice.cents, 1850);
    expect(order.items.first.subtotal.cents, 3700);
    expect(order.payments!.single.changeGiven, Money.parse('30'));
    expect(order.paid, Money.parse('20'));
    expect(order.balance, Money.parse('20'));
    expect(order.createdAt.isUtc, isFalse); // converted to device time for display
  });

  test('a voided payment is listed but does not count as paid', () {
    final order = Order.fromJson(
      orderJson(
        paymentStatus: 'PARTIAL',
        payments: [
          for (final (id, voidedAt) in [(1, '2026-10-03T15:10:00.000Z'), (2, null)])
            {
              'id': id,
              'method': 'YAPE',
              'amount': '15',
              'amountReceived': null,
              'changeGiven': null,
              'operationNumber': '12345$id',
              'createdAt': '2026-10-03T15:05:00.000Z',
              'voidedAt': voidedAt,
              'voidReason': voidedAt == null ? null : 'monto equivocado',
            },
        ],
      ),
    );

    expect(order.payments!.first.isVoid, isTrue);
    expect(order.payments!.first.voidReason, 'monto equivocado');
    expect(order.paid, Money.parse('15'));
    expect(order.balance, Money.parse('25'));
  });

  test('balance is unknown for a partially paid order loaded from the list', () {
    final order = Order.fromJson(orderJson(paymentStatus: 'PARTIAL'));
    expect(order.payments, isNull);
    expect(order.balance, isNull);
    expect(Order.fromJson(orderJson()).balance, Money.parse('40'));
    expect(Order.fromJson(orderJson(paymentStatus: 'PAID')).balance, Money.zero);
  });

  test('computes the subtotal when the generated column is missing', () {
    final json = orderJson();
    (json['items'] as List).first['subtotal'] = null;
    expect(Order.fromJson(json).items.first.subtotal.cents, 3700);
  });

  test('takeaway label includes the customer name', () {
    expect(Order.fromJson(orderJson(orderType: 'TAKEAWAY')).target, 'Para llevar · Juan');
  });

  group('permissions mirror the backend state machine', () {
    test('kitchen starts and finishes; waiter delivers', () {
      final pending = Order.fromJson(orderJson());
      expect(pending.canTransition(OrderStatus.inPreparation, Role.kitchen), isTrue);
      expect(pending.canTransition(OrderStatus.inPreparation, Role.waiter), isFalse);
      final ready = Order.fromJson(orderJson(status: 'READY'));
      expect(ready.canTransition(OrderStatus.delivered, Role.waiter), isTrue);
      expect(ready.canTransition(OrderStatus.delivered, Role.kitchen), isFalse);
    });

    test('waiter cancels only their own pending and unpaid orders', () {
      expect(Order.fromJson(orderJson()).canCancel(Role.waiter, userId: 2), isTrue); // fixture waiter id 2
      expect(Order.fromJson(orderJson()).canCancel(Role.waiter, userId: 9), isFalse, reason: "a colleague's");
      expect(Order.fromJson(orderJson()).canCancel(Role.owner, userId: 1), isTrue);
      expect(Order.fromJson(orderJson(status: 'IN_PREPARATION')).canCancel(Role.waiter), isFalse);
      expect(Order.fromJson(orderJson(status: 'IN_PREPARATION')).canCancel(Role.owner), isTrue);
      expect(Order.fromJson(orderJson(paymentStatus: 'PARTIAL')).canCancel(Role.owner), isFalse);
      expect(Order.fromJson(orderJson(status: 'PENDING')).canCancel(Role.kitchen), isFalse);
    });
  });

  group('mergeWith', () {
    final withPayments = Order.fromJson(orderJson(paymentStatus: 'PARTIAL', payments: []));

    test('keeps loaded payments when the same version arrives without them', () {
      final listCopy = Order.fromJson(orderJson(paymentStatus: 'PARTIAL'));
      expect(withPayments.mergeWith(listCopy).payments, isNotNull);
    });

    test('drops cached payments when the order changed', () {
      final newer = Order.fromJson(
        orderJson(paymentStatus: 'PARTIAL', updatedAt: '2026-10-03T15:10:00.000Z'),
      );
      expect(withPayments.mergeWith(newer).payments, isNull);
    });
  });
}
