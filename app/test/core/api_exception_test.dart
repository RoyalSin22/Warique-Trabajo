import 'package:flutter_test/flutter_test.dart';
import 'package:warique_app/core/api_exception.dart';

void main() {
  test('translates known backend messages', () {
    final error = ApiException.fromResponse(401, {'statusCode': 401, 'message': 'Invalid credentials'});
    expect(error.message, 'Usuario o contraseña incorrectos.');
    expect(error.isUnauthorized, isTrue);
  });

  test('extracts the balance from the overpayment message', () {
    final error = ApiException.fromResponse(
        400, {'message': 'Amount exceeds the pending balance of S/ 12.00'});
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
    expect(ApiException.fromResponse(400, {'message': ['a', 'b']}).message, contains('a\nb'));
    expect(ApiException.fromResponse(403, null).message, contains('permiso'));
    expect(ApiException.fromResponse(429, null).message, contains('Demasiados intentos'));
    expect(ApiException.fromResponse(500, {'message': 'Internal server error'}).message,
        contains('500'));
  });
}
