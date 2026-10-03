import 'package:flutter_test/flutter_test.dart';
import 'package:warique_app/core/money.dart';

void main() {
  group('Money.tryParse', () {
    test('parses the formats the API returns', () {
      expect(Money.parse('18.50').cents, 1850);
      expect(Money.parse('18.5').cents, 1850); // Prisma Decimal drops trailing zeros
      expect(Money.parse('18').cents, 1800);
      expect(Money.parse('0.05').cents, 5);
      expect(Money.parse(18.5).cents, 1850);
      expect(Money.parse(7).cents, 700);
    });

    test('accepts a comma as decimal separator (Peruvian keyboards)', () {
      expect(Money.parse('12,30').cents, 1230);
    });

    test('rejects non-money input', () {
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('1.234'), isNull); // more than 2 decimals
      expect(Money.tryParse(null), isNull);
      expect(Money.tryParse(double.nan), isNull);
    });
  });

  test('arithmetic is exact in cents', () {
    // 0.1 + 0.2 != 0.3 with doubles
    expect(Money.parse('0.1') + Money.parse('0.2'), Money.parse('0.3'));
    expect(Money.parse('18.50') * 2 + Money.parse('3'), Money.parse('40.00'));
  });

  test('formats for display and JSON', () {
    expect(Money.parse('40').toString(), 'S/ 40.00');
    expect(Money.parse('0.5').plain, '0.50');
    expect(const Money(-250).plain, '-2.50');
    expect(Money.parse('18.50').toJson(), 18.5);
    expect(Money.parse('20').toJson(), 20);
    expect(const Money(1999).toJson().toString(), '19.99');
  });
}
