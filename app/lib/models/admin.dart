import '../core/money.dart';
import 'inventory.dart';
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
    this.expensesTotal = Money.zero,
    this.salesMinusExpenses = Money.zero,
    this.expensesByCategory = const [],
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
    expensesTotal: Money.tryParse(json['expensesTotal']) ?? Money.zero,
    salesMinusExpenses: Money.tryParse(json['salesMinusExpenses']) ?? Money.zero,
    expensesByCategory: _expensesByCategory(json['expensesByCategory']),
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

  /// Non-void expenses of the day.
  final Money expensesTotal;

  /// Cash view, not accounting profit: supplies bought today count fully today.
  final Money salesMinusExpenses;
  final List<({ExpenseCategory category, Money amount})> expensesByCategory;

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

/// Owner dashboard for a range of business days (`GET /reports/summary`).
class SalesSummary {
  const SalesSummary({
    required this.from,
    required this.to,
    required this.sales,
    required this.orders,
    required this.averageTicket,
    required this.collected,
    required this.daysWithSales,
    required this.bestDay,
    required this.days,
    required this.byWeekday,
    required this.byHour,
    required this.topDishes,
    required this.byMethod,
    this.expenses = Money.zero,
    this.salesMinusExpenses = Money.zero,
    this.expensesByCategory = const [],
  });

  factory SalesSummary.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'] as Map<String, dynamic>;
    final best = totals['bestDay'] as Map<String, dynamic>?;
    return SalesSummary(
      from: DateTime.parse(json['from'] as String),
      to: DateTime.parse(json['to'] as String),
      sales: Money.parse(totals['sales']),
      orders: totals['orders'] as int,
      averageTicket: Money.parse(totals['averageTicket']),
      collected: Money.parse(totals['collected']),
      daysWithSales: totals['daysWithSales'] as int,
      bestDay: best == null
          ? null
          : (date: DateTime.parse(best['date'] as String), sales: Money.parse(best['sales'])),
      days: [
        for (final row in json['days'] as List)
          (
            date: DateTime.parse(row['date'] as String),
            sales: Money.parse(row['sales']),
            orders: row['orders'] as int,
          ),
      ],
      byWeekday: [
        for (final row in json['byWeekday'] as List)
          (
            weekday: row['weekday'] as int,
            openDays: row['openDays'] as int,
            averageSales: Money.parse(row['averageSales']),
          ),
      ],
      byHour: [
        for (final row in json['byHour'] as List)
          (hour: row['hour'] as int, orders: row['orders'] as int, sales: Money.parse(row['sales'])),
      ],
      topDishes: [
        for (final row in json['topDishes'] as List)
          (
            name: row['dishName'] as String,
            quantity: row['quantity'] as int,
            revenue: Money.parse(row['revenue']),
          ),
      ],
      byMethod: {
        for (final row in json['byMethod'] as List)
          PaymentMethod.fromApi(row['method'] as String): (
            count: row['count'] as int,
            amount: Money.parse(row['amount']),
          ),
      },
      expenses: Money.tryParse(totals['expenses']) ?? Money.zero,
      salesMinusExpenses: Money.tryParse(totals['salesMinusExpenses']) ?? Money.zero,
      expensesByCategory: _expensesByCategory(json['expensesByCategory']),
    );
  }

  final DateTime from;
  final DateTime to;
  final Money sales;
  final int orders;
  final Money averageTicket;
  final Money collected;
  final int daysWithSales;
  final ({DateTime date, Money sales})? bestDay;
  final List<({DateTime date, Money sales, int orders})> days;

  /// ISO weekday (1 = lunes). Average over the days that had sales.
  final List<({int weekday, int openDays, Money averageSales})> byWeekday;
  final List<({int hour, int orders, Money sales})> byHour;
  final List<({String name, int quantity, Money revenue})> topDishes;
  final Map<PaymentMethod, ({int count, Money amount})> byMethod;

  /// Non-void expenses in the range, largest category first.
  final Money expenses;
  final Money salesMinusExpenses;
  final List<({ExpenseCategory category, Money amount})> expensesByCategory;
}

/// Tolerates a server without expenses (older version): empty list.
List<({ExpenseCategory category, Money amount})> _expensesByCategory(Object? rows) => [
  for (final row in rows as List? ?? const [])
    (category: ExpenseCategory.fromApi(row['category'] as String), amount: Money.parse(row['amount'])),
];
