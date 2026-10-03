import '../core/api_client.dart';
import '../core/money.dart';
import '../models/menu.dart';
import '../models/order.dart';
import '../models/user.dart';

typedef Json = Map<String, dynamic>;

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<({String token, AppUser user})> login(String username, String password) async {
    final json = await _api.post('/auth/login', {'username': username, 'password': password}) as Json;
    return (token: json['accessToken'] as String, user: AppUser.fromJson(json['user'] as Json));
  }

  Future<AppUser> me() async => AppUser.fromJson(await _api.get('/auth/me') as Json);
}

class MenuRepository {
  MenuRepository(this._api);

  final ApiClient _api;

  /// Active dishes of active categories, ordered by category and name (server side).
  Future<List<Dish>> dishes() async =>
      [for (final json in await _api.get('/dishes') as List) Dish.fromJson(json as Json)];

  Future<List<DiningTable>> tables() async =>
      [for (final json in await _api.get('/tables') as List) DiningTable.fromJson(json as Json)];

  Future<Dish> setAvailability(int dishId, bool isAvailable) async => Dish.fromJson(
        await _api.patch('/dishes/$dishId/availability', {'isAvailable': isAvailable}) as Json,
      );

  Future<int> resetAvailability() async =>
      (await _api.post('/dishes/availability/reset') as Json)['updated'] as int;
}

class NewOrderItem {
  const NewOrderItem({required this.dishId, required this.quantity, this.notes});

  final int dishId;
  final int quantity;
  final String? notes;

  Json toJson() => {
        'dishId': dishId,
        'quantity': quantity,
        if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
      };
}

class OrdersRepository {
  OrdersRepository(this._api);

  final ApiClient _api;

  /// Today's orders (business day computed by the server), oldest first.
  Future<List<Order>> today({List<OrderStatus>? statuses}) async {
    final json = await _api.get('/orders', query: {
      if (statuses != null && statuses.isNotEmpty) 'status': statuses.map((s) => s.api).join(','),
    }) as List;
    return [for (final order in json) Order.fromJson(order as Json)];
  }

  Future<Order> byId(int id) async => Order.fromJson(await _api.get('/orders/$id') as Json);

  Future<Order> create({
    required OrderType orderType,
    required List<NewOrderItem> items,
    int? tableId,
    String? customerName,
    String? notes,
  }) async {
    final json = await _api.post('/orders', {
      'orderType': orderType.api,
      if (orderType == OrderType.dineIn) 'tableId': tableId,
      if (customerName != null && customerName.trim().isNotEmpty) 'customerName': customerName.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      'items': [for (final item in items) item.toJson()],
    });
    return Order.fromJson(json as Json);
  }

  Future<Order> changeStatus(int id, OrderStatus status, {String? cancelReason}) async {
    final json = await _api.patch('/orders/$id/status', {
      'status': status.api,
      if (cancelReason != null) 'cancelReason': cancelReason.trim(),
    });
    return Order.fromJson(json as Json);
  }

  Future<Order> registerPayment(
    int id, {
    required PaymentMethod method,
    required Money amount,
    Money? amountReceived,
    String? operationNumber,
  }) async {
    final json = await _api.post('/orders/$id/payments', {
      'method': method.api,
      'amount': amount.toJson(),
      if (method == PaymentMethod.cash) 'amountReceived': (amountReceived ?? amount).toJson(),
      if (method != PaymentMethod.cash) 'operationNumber': operationNumber?.trim(),
    });
    return Order.fromJson(json as Json);
  }
}
