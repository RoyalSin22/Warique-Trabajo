import 'package:flutter_test/flutter_test.dart';
import 'package:warique_app/core/api_exception.dart';

void main() {
  test('translates known backend messages', () {
    final error = ApiException.fromResponse(401, {'statusCode': 401, 'message': 'Invalid credentials'});
    expect(error.message, 'Usuario o contraseña incorrectos.');
    expect(error.isUnauthorized, isTrue);
  });

  test('extracts the balance from the overpayment message', () {
    final error = ApiException.fromResponse(400, {
      'message': 'Amount exceeds the pending balance of S/ 12.00',
    });
    expect(error.message, 'El monto supera el saldo pendiente (S/ 12.00).');
  });

  test('exposes unavailable dish ids', () {
    final error = ApiException.fromResponse(400, {
      'message': 'Some dishes are not available',
      'unavailableDishIds': [4, 9],
    });
    expect(error.unavailableDishIds, [4, 9]);
  });

  test('joins validation message lists and falls back by status code', () {
    expect(
      ApiException.fromResponse(400, {
        'message': ['a', 'b'],
      }).message,
      contains('a\nb'),
    );
    expect(ApiException.fromResponse(403, null).message, contains('permiso'));
    expect(ApiException.fromResponse(429, null).message, contains('Demasiados intentos'));
    expect(ApiException.fromResponse(500, {'message': 'Internal server error'}).message, contains('500'));
  });

  test('translates stock conflicts with the numbers people use', () {
    expect(
      ApiException.fromResponse(409, {
        'message': 'Only 2.500 in stock; register a count if the real amount is different',
      }).message,
      'Solo hay 2.5 en stock. Si hay otra cantidad, registra un conteo.',
    );
    expect(
      ApiException.fromResponse(409, {
        'message': 'Cannot void: Limón has 3.000 left of the 10.000 bought; register a count first',
      }).message,
      'No se puede anular: de Limón quedan 3 de los 10 comprados. Registra un conteo primero.',
    );
  });
}
