import 'package:flutter_test/flutter_test.dart';
import 'package:warique_app/core/api_client.dart';
import 'package:warique_app/core/api_exception.dart';
import 'package:warique_app/core/money.dart';
import 'package:warique_app/data/repositories.dart';
import 'package:warique_app/models/order.dart';

import '../support/fixtures.dart';

void main() {
  late RecordingHttp http;
  late OrdersRepository repository;
  var unauthorizedCalls = 0;

  setUp(() {
    unauthorizedCalls = 0;
    http = RecordingHttp((request) => (200, orderJson()));
    repository = OrdersRepository(ApiClient(
      baseUrl: 'http://server.test',
      token: 'jwt',
      httpClient: http.client,
      onUnauthorized: () => unauthorizedCalls++,
    ));
  });

  test('sends the bearer token and the /api prefix', () async {
    await repository.byId(1);
    expect(http.requests.single.url.toString(), 'http://server.test/api/orders/1');
    expect(http.requests.single.headers['Authorization'], 'Bearer jwt');
  });

  test('takeaway orders never send tableId; blank texts are omitted', () async {
    await repository.create(
      orderType: OrderType.takeaway,
      tableId: 4,
      customerName: '  ',
      notes: ' sin cubiertos ',
      items: const [NewOrderItem(dishId: 5, quantity: 2)],
    );
    expect(http.bodyOf(0), {
      'orderType': 'TAKEAWAY',
      'notes': 'sin cubiertos',
      'items': [
        {'dishId': 5, 'quantity': 2},
      ],
    });
  });

  test('cash payments send amountReceived as JSON numbers', () async {
    await repository.registerPayment(1,
        method: PaymentMethod.cash, amount: Money.parse('18.50'), amountReceived: Money.parse('20'));
    expect(http.bodyOf(0), {'method': 'CASH', 'amount': 18.5, 'amountReceived': 20});
  });

  test('Yape payments send only the operation number', () async {
    await repository.registerPayment(1,
        method: PaymentMethod.yape, amount: Money.parse('40'), operationNumber: ' 123456 ');
    expect(http.bodyOf(0), {'method': 'YAPE', 'amount': 40, 'operationNumber': '123456'});
  });

  test('cancel sends the reason', () async {
    await repository.changeStatus(1, OrderStatus.cancelled, cancelReason: 'se fue');
    expect(http.requests.single.method, 'PATCH');
    expect(http.bodyOf(0), {'status': 'CANCELLED', 'cancelReason': 'se fue'});
  });

  test('a 401 notifies the session and throws a translated error', () async {
    http = RecordingHttp((request) => (401, {'statusCode': 401, 'message': 'Unauthorized'}));
    repository = OrdersRepository(ApiClient(
      baseUrl: 'http://server.test',
      token: 'jwt',
      httpClient: http.client,
      onUnauthorized: () => unauthorizedCalls++,
    ));
    await expectLater(repository.byId(1), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)));
    expect(unauthorizedCalls, 1);
  });
}
