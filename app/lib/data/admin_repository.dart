import '../core/api_client.dart';
import '../core/money.dart';
import '../models/admin.dart';
import '../models/menu.dart';
import '../models/user.dart';

typedef _Json = Map<String, dynamic>;

/// OWNER-only endpoints: menu, tables, staff accounts and reports.
class AdminRepository {
  AdminRepository(this._api);

  final ApiClient _api;

  static const _withInactive = {'includeInactive': 'true'};

  // ---------------------------------------------------------------- Menu
  Future<List<Category>> categories() async => [
    for (final json in await _api.get('/categories', query: _withInactive) as List)
      Category.fromJson(json as _Json),
  ];

  Future<Category> createCategory({required String name, int? sortOrder}) async => Category.fromJson(
    await _api.post('/categories', {'name': name.trim(), 'sortOrder': ?sortOrder}) as _Json,
  );

  Future<Category> updateCategory(int id, {String? name, int? sortOrder, bool? isActive}) async =>
      Category.fromJson(
        await _api.patch('/categories/$id', {
              if (name != null) 'name': name.trim(),
              'sortOrder': ?sortOrder,
              'isActive': ?isActive,
            })
            as _Json,
      );

  /// Includes removed dishes and dishes of inactive categories.
  Future<List<Dish>> dishes() async => [
    for (final json in await _api.get('/dishes', query: _withInactive) as List) Dish.fromJson(json as _Json),
  ];

  Future<Dish> createDish({
    required int categoryId,
    required String name,
    required Money price,
    String? description,
  }) async => Dish.fromJson(
    await _api.post('/dishes', {
          'categoryId': categoryId,
          'name': name.trim(),
          'price': price.toJson(),
          if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
        })
        as _Json,
  );

  Future<Dish> updateDish(
    int id, {
    int? categoryId,
    String? name,
    Money? price,
    String? description,
    bool? isActive,
  }) async => Dish.fromJson(
    await _api.patch('/dishes/$id', {
          'categoryId': ?categoryId,
          if (name != null) 'name': name.trim(),
          if (price != null) 'price': price.toJson(),
          if (description != null) 'description': description.trim(),
          'isActive': ?isActive,
        })
        as _Json,
  );

  // ---------------------------------------------------------------- Tables
  Future<List<ManagedTable>> tables() async => [
    for (final json in await _api.get('/tables', query: _withInactive) as List)
      ManagedTable.fromJson(json as _Json),
  ];

  Future<ManagedTable> createTable(String label) async =>
      ManagedTable.fromJson(await _api.post('/tables', {'label': label.trim()}) as _Json);

  Future<ManagedTable> updateTable(int id, {String? label, bool? isActive}) async => ManagedTable.fromJson(
    await _api.patch('/tables/$id', {if (label != null) 'label': label.trim(), 'isActive': ?isActive})
        as _Json,
  );

  // ---------------------------------------------------------------- Staff
  Future<List<StaffUser>> users() async => [
    for (final json in await _api.get('/users', query: _withInactive) as List)
      StaffUser.fromJson(json as _Json),
  ];

  Future<StaffUser> createUser({
    required String fullName,
    required String username,
    required String password,
    required Role role,
  }) async => StaffUser.fromJson(
    await _api.post('/users', {
          'fullName': fullName.trim(),
          'username': username.trim().toLowerCase(),
          'password': password,
          'role': role.api,
        })
        as _Json,
  );

  Future<StaffUser> updateUser(int id, {String? fullName, Role? role, bool? isActive}) async =>
      StaffUser.fromJson(
        await _api.patch('/users/$id', {
              if (fullName != null) 'fullName': fullName.trim(),
              if (role != null) 'role': role.api,
              'isActive': ?isActive,
            })
            as _Json,
      );

  Future<void> resetPassword(int id, String password) =>
      _api.patch('/users/$id/password', {'password': password});

  // ---------------------------------------------------------------- Reports
  Future<DailyReport> dailyReport(String date) async =>
      DailyReport.fromJson(await _api.get('/reports/daily', query: {'date': date}) as _Json);

  Future<List<PaymentRecord>> payments(String date) async {
    final json = await _api.get('/reports/payments', query: {'date': date}) as _Json;
    return [for (final row in json['payments'] as List) PaymentRecord.fromJson(row as _Json)];
  }

  Future<SalesSummary> summary(String from, String to) async =>
      SalesSummary.fromJson(await _api.get('/reports/summary', query: {'from': from, 'to': to}) as _Json);

  Future<BackupStatus> backupStatus() async =>
      BackupStatus.fromJson(await _api.get('/reports/backup-status') as _Json);

  /// Signed download link (valid 2 minutes) for a CSV; the browser downloads it without the session.
  Future<({String url, String fileName})> exportLink(
    ExportKind kind, {
    required String from,
    required String to,
  }) async {
    final json = await _api.post('/reports/export-link', {'kind': kind.api, 'from': from, 'to': to}) as _Json;
    return (url: json['url'] as String, fileName: json['fileName'] as String);
  }
}
