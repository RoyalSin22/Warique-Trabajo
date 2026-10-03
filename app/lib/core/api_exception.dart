/// Error returned by the API, with a message ready to show to staff (Spanish).
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.details = const {}});

  /// 0 when the server could not be reached.
  final int statusCode;
  final String message;

  /// Raw response body, e.g. `unavailableDishIds` when ordering sold-out dishes.
  final Map<String, dynamic> details;

  bool get isUnauthorized => statusCode == 401;
  bool get isConflict => statusCode == 409;
  bool get isNetwork => statusCode == 0;

  List<int> get unavailableDishIds =>
      (details['unavailableDishIds'] as List?)?.whereType<int>().toList() ?? const [];

  /// Builds the exception from a NestJS error body: `{ statusCode, message, error }`,
  /// where `message` is a string or, for validation errors, a list of strings.
  factory ApiException.fromResponse(int statusCode, Object? body) {
    final details = body is Map<String, dynamic> ? body : <String, dynamic>{};
    final rawMessage = details['message'];
    final serverMessage = rawMessage is List ? rawMessage.join('\n') : rawMessage?.toString();
    return ApiException(statusCode, translateServerMessage(statusCode, serverMessage), details: details);
  }

  @override
  String toString() => message;
}

/// Backend messages are in English (they are also logged); staff sees Spanish.
const _knownMessages = <String, String>{
  'Invalid credentials': 'Usuario o contraseña incorrectos.',
  'Some dishes are not available': 'Algunos platos ya no están disponibles. Se quitaron del pedido.',
  'The order was modified by someone else. Reload and try again':
      'Otra persona modificó este pedido. Se actualizó la información; revisa e intenta de nuevo.',
  'Cannot cancel an order that already has payments': 'No se puede cancelar un pedido que ya tiene pagos.',
  'cancelReason is required to cancel an order': 'Indica el motivo de la cancelación.',
  'The order is already paid': 'El pedido ya está pagado.',
  'Cannot register a payment for a cancelled order': 'El pedido está cancelado.',
  'Yape/Plin payments require the operation number': 'Ingresa el número de operación.',
  'Cash payments require amountReceived >= amount': 'El monto recibido no cubre el pago.',
  'Table does not exist or is inactive': 'La mesa no existe o está desactivada.',
  'Dine-in orders require a tableId': 'Selecciona una mesa.',
  'Order not found': 'El pedido no existe.',
  'Dish not found': 'El plato no existe.',
  'Current password is incorrect': 'La contraseña actual es incorrecta.',
};

String translateServerMessage(int statusCode, String? serverMessage) {
  if (serverMessage != null) {
    final known = _knownMessages[serverMessage];
    if (known != null) return known;
    // "Amount exceeds the pending balance of S/ 12.00"
    final balance = RegExp(r'pending balance of (S/ [\d.]+)').firstMatch(serverMessage);
    if (balance != null) return 'El monto supera el saldo pendiente (${balance.group(1)}).';
    if (serverMessage.startsWith('Cannot change order status')) {
      return 'El pedido ya cambió de estado. Actualiza la lista.';
    }
  }
  return switch (statusCode) {
    0 => 'No hay conexión con el servidor. Verifica el Wi-Fi del local.',
    400 => 'Datos inválidos${serverMessage == null ? '' : ': $serverMessage'}',
    401 => 'Tu sesión expiró. Vuelve a ingresar.',
    403 => 'Tu rol no tiene permiso para esta acción.',
    404 => 'No encontrado.',
    409 => 'Conflicto: los datos cambiaron. Actualiza e intenta de nuevo.',
    429 => 'Demasiados intentos. Espera un minuto.',
    _ => 'Error del servidor ($statusCode). Intenta de nuevo.',
  };
}
