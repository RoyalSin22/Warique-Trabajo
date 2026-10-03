import '../core/money.dart';
import 'order.dart';
import 'user.dart';

class Category {
  const Category({required this.id, required this.name, required this.sortOrder, required this.isActive});

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as int,
    name: json['name'] as String,
    sortOrder: json['sortOrder'] as int? ?? 0,
    isActive: json['isActive'] as bool? ?? true,
  );

  final int id;
  final String name;
  final int sortOrder;
  final bool isActive;
}

class ManagedTable {
  const ManagedTable({required this.id, required this.label, required this.isActive});

  factory ManagedTable.fromJson(Map<String, dynamic> json) => ManagedTable(
    id: json['id'] as int,
    label: json['label'] as String,
    isActive: json['isActive'] as bool? ?? true,
  );

  final int id;
  final String label;
  final bool isActive;
}

/// Staff account as returned by `/users` (never includes the password hash).
class StaffUser {
  const StaffUser({
    required this.id,
    required this.fullName,
    required this.username,
    required this.role,
    required this.isActive,
  });

  factory StaffUser.fromJson(Map<String, dynamic> json) => StaffUser(
    id: json['id'] as int,
    fullName: json['fullName'] as String,
    username: json['username'] as String,
    role: Role.fromApi(json['role'] as String),
    isActive: json['isActive'] as bool,
  );

  final int id;
  final String fullName;
  final String username;
  final Role role;
  final bool isActive;
}

class DailyReport {
  const DailyReport({
    required this.date,
    required this.ordersByStatus,
    required this.sales,
    required this.collectedByMethod,
    required this.collectedTotal,
    required this.pendingBalance,
    required this.topDishes,
  });

  factory DailyReport.fromJson(Map<String, dynamic> json) => DailyReport(
    date: json['date'] as String,
    ordersByStatus: {
      for (final row in json['orders'] as List)
        OrderStatus.fromApi(row['status'] as String): (
          count: row['count'] as int,
          total: Money.parse(row['total']),
        ),
    },
    sales: Money.parse(json['sales']),
    collectedByMethod: {
      for (final row in json['collectedByMethod'] as List)
        PaymentMethod.fromApi(row['method'] as String): (
          count: row['count'] as int,
          amount: Money.parse(row['amount']),
        ),
    },
    collectedTotal: Money.parse(json['collectedTotal']),
    pendingBalance: Money.parse(json['pendingBalance']),
    topDishes: [
      for (final row in json['topDishes'] as List)
        (name: row['dishName'] as String, quantity: row['quantity'] as int),
    ],
  );

  final String date;
  final Map<OrderStatus, ({int count, Money total})> ordersByStatus;

  /// Totals of the day's non-cancelled orders.
  final Money sales;
  final Map<PaymentMethod, ({int count, Money amount})> collectedByMethod;
  final Money collectedTotal;

  /// What the day's orders still owe.
  final Money pendingBalance;
  final List<({String name, int quantity})> topDishes;

  int get orderCount => ordersByStatus.entries
      .where((entry) => entry.key != OrderStatus.cancelled)
      .fold(0, (sum, entry) => sum + entry.value.count);
}

class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.orderId,
    required this.method,
    required this.amount,
    required this.createdAt,
    required this.registeredBy,
    required this.orderType,
    this.target,
    this.amountReceived,
    this.changeGiven,
    this.operationNumber,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> json) => PaymentRecord(
    id: json['id'] as int,
    orderId: json['orderId'] as int,
    method: PaymentMethod.fromApi(json['method'] as String),
    amount: Money.parse(json['amount']),
    amountReceived: Money.tryParse(json['amountReceived']),
    changeGiven: Money.tryParse(json['changeGiven']),
    operationNumber: json['operationNumber'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    registeredBy: json['registeredBy'] as String,
    target: json['target'] as String?,
    orderType: OrderType.fromApi(json['orderType'] as String),
  );

  final int id;
  final int orderId;
  final PaymentMethod method;
  final Money amount;
  final Money? amountReceived;
  final Money? changeGiven;
  final String? operationNumber;
  final DateTime createdAt;
  final String registeredBy;
  final String? target;
  final OrderType orderType;

  String get targetLabel => switch (orderType) {
    OrderType.dineIn => target ?? 'Mesa',
    OrderType.takeaway => target == null ? 'Para llevar' : 'Para llevar · $target',
  };
}

class BackupStatus {
  const BackupStatus({
    required this.configured,
    required this.ok,
    required this.needsAttention,
    required this.copied,
    this.time,
    this.ageHours,
    this.file,
    this.error,
  });

  factory BackupStatus.fromJson(Map<String, dynamic> json) => BackupStatus(
    configured: json['configured'] as bool,
    ok: json['ok'] as bool,
    needsAttention: json['needsAttention'] as bool,
    copied: json['copied'] as bool,
    time: json['time'] == null ? null : DateTime.parse(json['time'] as String).toLocal(),
    ageHours: (json['ageHours'] as num?)?.toDouble(),
    file: json['file'] as String?,
    error: json['error'] as String?,
  );

  final bool configured;
  final bool ok;
  final bool needsAttention;
  final bool copied;
  final DateTime? time;
  final double? ageHours;
  final String? file;
  final String? error;
}
