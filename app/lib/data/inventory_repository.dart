import '../core/api_client.dart';
import '../core/money.dart';
import '../core/quantity.dart';
import '../models/inventory.dart';

typedef _Json = Map<String, dynamic>;

/// Supplies (owner and kitchen), expenses and the cash count (owner only).
class InventoryRepository {
  InventoryRepository(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------- Supplies
  Future<List<Supply>> supplies({bool includeInactive = false}) async => [
    for (final json
        in await _api.get('/supplies', query: includeInactive ? {'includeInactive': 'true'} : null) as List)
      Supply.fromJson(json as _Json),
  ];

  Future<Supply> createSupply({
    required String name,
    required SupplyUnit unit,
    required Quantity minStock,
  }) async => Supply.fromJson(
    await _api.post('/supplies', {'name': name.trim(), 'unit': unit.api, 'minStock': minStock.toJson()})
        as _Json,
  );

  Future<Supply> updateSupply(
    int id, {
    String? name,
    SupplyUnit? unit,
    Quantity? minStock,
    bool? isActive,
  }) async => Supply.fromJson(
    await _api.patch('/supplies/$id', {
          if (name != null) 'name': name.trim(),
          if (unit != null) 'unit': unit.api,
          if (minStock != null) 'minStock': minStock.toJson(),
          'isActive': ?isActive,
        })
        as _Json,
  );

  /// COUNT: [quantity] is what was counted. WASTE/USE: how much went out.
  /// [requestId] makes a retried save harmless (Idempotency-Key).
  Future<Supply> addMovement(
    int supplyId, {
    required MovementType type,
    required Quantity quantity,
    String? note,
    required String requestId,
  }) async => Supply.fromJson(
    await _api.post(
          '/supplies/$supplyId/movements',
          {
            'type': type.api,
            'quantity': quantity.toJson(),
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          },
          {'Idempotency-Key': requestId},
        )
        as _Json,
  );

  Future<({Supply supply, List<SupplyMovement> movements})> movements(int supplyId) async {
    final json = await _api.get('/supplies/$supplyId/movements') as _Json;
    return (
      supply: Supply.fromJson(json['supply'] as _Json),
      movements: [for (final row in json['movements'] as List) SupplyMovement.fromJson(row as _Json)],
    );
  }

  // ---------------------------------------------------------------- Expenses
  Future<ExpenseDay> expenses(String date) async =>
      ExpenseDay.fromJson(await _api.get('/expenses', query: {'date': date}) as _Json);

  /// With [items] it is a supply purchase: the server sums the lines and adds the stock.
  Future<Expense> createExpense({
    required String businessDate,
    required ExpenseCategory category,
    required String description,
    required PaidWith paidWith,
    Money? amount,
    List<PurchaseLine> items = const [],
    required String requestId,
  }) async => Expense.fromJson(
    await _api.post(
          '/expenses',
          {
            'businessDate': businessDate,
            'category': category.api,
            'description': description.trim(),
            'paidWith': paidWith.api,
            if (items.isEmpty && amount != null) 'amount': amount.toJson(),
            if (items.isNotEmpty)
              'items': [
                for (final item in items)
                  {'supplyId': item.supplyId, 'quantity': item.quantity.toJson(), 'cost': item.cost.toJson()},
              ],
          },
          {'Idempotency-Key': requestId},
        )
        as _Json,
  );

  Future<Expense> voidExpense(int id, String reason) async =>
      Expense.fromJson(await _api.patch('/expenses/$id/void', {'reason': reason.trim()}) as _Json);

  // ---------------------------------------------------------------- Cash count
  Future<CashDay> cashDay(String date) async =>
      CashDay.fromJson(await _api.get('/cash', query: {'date': date}) as _Json);

  Future<CashDay> openCash(String date, Money openingAmount) async => CashDay.fromJson(
    await _api.post('/cash/open', {'date': date, 'openingAmount': openingAmount.toJson()}) as _Json,
  );

  Future<CashDay> closeCash(String date, Money countedAmount, {String? notes}) async => CashDay.fromJson(
    await _api.post('/cash/close', {
          'date': date,
          'countedAmount': countedAmount.toJson(),
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        })
        as _Json,
  );
}
