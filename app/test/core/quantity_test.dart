import 'package:flutter_test/flutter_test.dart';
import 'package:warique_app/core/quantity.dart';

void main() {
  test('parses the formats the API and keyboards produce', () {
    expect(Quantity.parse('2.500').milli, 2500);
    expect(Quantity.parse('2,5').milli, 2500);
    expect(Quantity.parse('-0.125').milli, -125);
    expect(Quantity.parse(3).milli, 3000);
    expect(Quantity.tryParse('1.2345'), isNull);
    expect(Quantity.tryParse('abc'), isNull);
  });

  test('adds exactly and prints like people write it', () {
    expect((Quantity.parse('0.1') + Quantity.parse('0.2')).toString(), '0.3');
    expect(Quantity.parse('12.000').toString(), '12');
    expect(Quantity.parse('-0.5').signed, '-0.5');
    expect(Quantity.parse('5.5').signed, '+5.5');
  });

  test('serializes as a JSON number with at most 3 decimals', () {
    expect(Quantity.parse('2.5').toJson(), 2.5);
    expect(Quantity.parse('2').toJson(), 2);
  });
}
