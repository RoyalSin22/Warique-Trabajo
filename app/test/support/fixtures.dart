import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:warique_app/data/realtime_client.dart';

/// Shape of `ORDER_DETAIL_INCLUDE` as serialized by NestJS (Prisma Decimal -> string).
Map<String, dynamic> orderJson({
  int id = 1,
  String status = 'PENDING',
  String paymentStatus = 'UNPAID',
  String orderType = 'DINE_IN',
  String total = '40',
  String updatedAt = '2026-10-03T15:00:00.000Z',
  String createdAt = '2026-10-03T15:00:00.000Z',
  List<Map<String, dynamic>>? payments,
  String? cancelReason,
}) => {
  'id': id,
  'orderType': orderType,
  'tableId': orderType == 'DINE_IN' ? 3 : null,
  'customerName': orderType == 'TAKEAWAY' ? 'Juan' : null,
  'waiterId': 2,
  'status': status,
  'paymentStatus': paymentStatus,
  'total': total,
  'notes': null,
  'cancelReason': cancelReason,
  'createdAt': createdAt,
  'updatedAt': updatedAt,
  'paidAt': null,
  'table': orderType == 'DINE_IN' ? {'id': 3, 'label': 'Mesa 3'} : null,
  'waiter': {'id': 2, 'fullName': 'Rosa Mozo'},
  'items': <Map<String, dynamic>>[
    {
      'id': 10,
      'dishId': 5,
      'dishName': 'Ceviche',
      'unitPrice': '18.5',
      'quantity': 2,
      'subtotal': '37',
      'notes': 'sin ají',
    },
    {
      'id': 11,
      'dishId': 6,
      'dishName': 'Chicha morada',
      'unitPrice': '3',
      'quantity': 1,
      'subtotal': '3',
      'notes': null,
    },
  ],
  'payments': ?payments,
};

Map<String, dynamic> dishJson({
  int id = 5,
  String name = 'Ceviche',
  bool isAvailable = true,
  int categoryId = 1,
}) => {
  'id': id,
  'categoryId': categoryId,
  'name': name,
  'description': null,
  'price': '18.5',
  'isAvailable': isAvailable,
  'isActive': true,
  'category': {'id': categoryId, 'name': categoryId == 1 ? 'Fondos' : 'Bebidas'},
};

class FakeRealtime implements RealtimeClient {
  final messagesController = StreamController<RealtimeMessage>.broadcast();
  final connectedController = StreamController<bool>.broadcast();

  @override
  Stream<RealtimeMessage> get messages => messagesController.stream;

  @override
  Stream<bool> get connected => connectedController.stream;

  @override
  void connect() {}

  @override
  void dispose() {
    messagesController.close();
    connectedController.close();
  }

  void emit(String event, Object? payload) => messagesController.add(RealtimeMessage(event, payload));
}

/// Records requests and answers with [handler].
class RecordingHttp {
  RecordingHttp(this.handler);

  final FutureOr<(int, Object?)> Function(http.Request request) handler;
  final requests = <http.Request>[];

  late final client = MockClient((request) async {
    requests.add(request);
    final (status, body) = await handler(request);
    return http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  Map<String, dynamic> bodyOf(int index) => jsonDecode(requests[index].body) as Map<String, dynamic>;
}
