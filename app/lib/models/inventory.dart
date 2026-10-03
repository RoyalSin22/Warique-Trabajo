import '../core/money.dart';
import '../core/quantity.dart';

enum SupplyUnit {
  kg('KG', 'Kilogramo', 'kg'),
  l('L', 'Litro', 'L'),
  unidad('UNIDAD', 'Unidad', 'und.'),
  atado('ATADO', 'Atado', 'atado'),
  paquete('PAQUETE', 'Paquete', 'paq.');

  const SupplyUnit(this.api, this.label, this.short);

  final String api;
  final String label;
  final String short;

  static SupplyUnit fromApi(String value) => values.firstWhere((unit) => unit.api == value);

  /// Whole pieces cannot be split in a count; kilos and litres can.
  bool get allowsDecimals => this == kg || this == l;
}

class Supply {
  const Supply({
    required this.id,
    required this.name,
    required this.unit,
    required this.stock,
    required this.minStock,
    required this.isActive,
    required this.isLow,
  });

  factory Supply.fromJson(Map<String, dynamic> json) => Supply(
    id: json['id'] as int,
    name: json['name'] as String,
    unit: SupplyUnit.fromApi(json['unit'] as String),
    stock: Quantity.parse(json['stock']),
    minStock: Quantity.parse(json['minStock']),
    isActive: json['isActive'] as bool? ?? true,
    isLow: json['isLow'] as bool? ?? false,
  );

  final int id;
  final String name;
  final SupplyUnit unit;
  final Quantity stock;

  /// "Stock bajo" threshold; zero means no alert.
  final Quantity minStock;
  final bool isActive;
  final bool isLow;

  String amount(Quantity quantity) => '$quantity ${unit.short}';
}

enum MovementType {
  purchase('PURCHASE', 'Compra'),
  count('COUNT', 'Conteo'),
  waste('WASTE', 'Merma'),
  use('USE', 'Uso'),
  voided('VOID', 'Compra anulada');

  const MovementType(this.api, this.label);

  final String api;
  final String label;

  static MovementType fromApi(String value) => values.firstWhere((type) => type.api == value);
}

class SupplyMovement {
  const SupplyMovement({
    required this.id,
    required this.type,
    required this.quantity,
    required this.stockAfter,
    required this.createdAt,
    required this.createdBy,
    this.expenseId,
    this.note,
  });

  factory SupplyMovement.fromJson(Map<String, dynamic> json) => SupplyMovement(
    id: json['id'] as int,
    type: MovementType.fromApi(json['type'] as String),
    quantity: Quantity.parse(json['quantity']),
    stockAfter: Quantity.parse(json['stockAfter']),
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    createdBy: json['createdBy'] as String,
    expenseId: json['expenseId'] as int?,
    note: json['note'] as String?,
  );

  final int id;
  final MovementType type;

  /// Signed change: + in, - out.
  final Quantity quantity;
  final Quantity stockAfter;
  final DateTime createdAt;
  final String createdBy;
  final int? expenseId;
  final String? note;
}

enum ExpenseCategory {
  insumos('INSUMOS', 'Insumos'),
  gas('GAS', 'Gas'),
  servicios('SERVICIOS', 'Luz, agua, internet'),
  sueldos('SUELDOS', 'Sueldos'),
  alquiler('ALQUILER', 'Alquiler'),
  transporte('TRANSPORTE', 'Transporte'),
  otros('OTROS', 'Otros');

  const ExpenseCategory(this.api, this.label);

  final String api;
  final String label;

  static ExpenseCategory fromApi(String value) => values.firstWhere((category) => category.api == value);
}

enum PaidWith {
  cash('CASH', 'Efectivo de la caja'),
  other('OTHER', 'Otro medio');

  const PaidWith(this.api, this.label);

  final String api;
  final String label;

  static PaidWith fromApi(String value) => values.firstWhere((paidWith) => paidWith.api == value);
}

class ExpenseItem {
  const ExpenseItem({
    required this.supplyId,
    required this.supplyName,
    required this.unit,
    required this.quantity,
    required this.cost,
  });

  factory ExpenseItem.fromJson(Map<String, dynamic> json) => ExpenseItem(
    supplyId: json['supplyId'] as int,
    supplyName: json['supplyName'] as String,
    unit: SupplyUnit.fromApi(json['unit'] as String),
    quantity: Quantity.parse(json['quantity']),
    cost: Money.parse(json['cost']),
  );

  final int supplyId;
  final String supplyName;
  final SupplyUnit unit;
  final Quantity quantity;

  /// Line total paid.
  final Money cost;
}

class Expense {
  const Expense({
    required this.id,
    required this.businessDate,
    required this.category,
    required this.description,
    required this.amount,
    required this.paidWith,
    required this.isVoid,
    required this.createdBy,
    required this.createdAt,
    required this.items,
    this.voidReason,
  });

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: json['id'] as int,
    businessDate: json['businessDate'] as String,
    category: ExpenseCategory.fromApi(json['category'] as String),
    description: json['description'] as String,
    amount: Money.parse(json['amount']),
    paidWith: PaidWith.fromApi(json['paidWith'] as String),
    isVoid: json['isVoid'] as bool,
    voidReason: json['voidReason'] as String?,
    createdBy: json['createdBy'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    items: [
      for (final row in json['items'] as List? ?? const []) ExpenseItem.fromJson(row as Map<String, dynamic>),
    ],
  );

  final int id;

  /// Business day `YYYY-MM-DD`.
  final String businessDate;
  final ExpenseCategory category;
  final String description;
  final Money amount;
  final PaidWith paidWith;
  final bool isVoid;
  final String? voidReason;
  final String createdBy;
  final DateTime createdAt;
  final List<ExpenseItem> items;
}

/// `GET /expenses?date=`: voided expenses are listed but excluded from the totals.
class ExpenseDay {
  const ExpenseDay({
    required this.date,
    required this.total,
    required this.cashTotal,
    required this.expenses,
  });

  factory ExpenseDay.fromJson(Map<String, dynamic> json) => ExpenseDay(
    date: json['date'] as String,
    total: Money.parse(json['total']),
    cashTotal: Money.parse(json['cashTotal']),
    expenses: [for (final row in json['expenses'] as List) Expense.fromJson(row as Map<String, dynamic>)],
  );

  final String date;
  final Money total;
  final Money cashTotal;
  final List<Expense> expenses;
}

/// A purchase line being typed in the expense form.
typedef PurchaseLine = ({int supplyId, Quantity quantity, Money cost});

/// Snapshot taken when the cash count was closed.
class CashSession {
  const CashSession({
    required this.openingAmount,
    required this.openedBy,
    required this.openedAt,
    this.expectedAmount,
    this.countedAmount,
    this.difference,
    this.notes,
    this.closedBy,
    this.closedAt,
  });

  factory CashSession.fromJson(Map<String, dynamic> json) => CashSession(
    openingAmount: Money.parse(json['openingAmount']),
    openedBy: json['openedByName'] as String,
    openedAt: DateTime.parse(json['openedAt'] as String).toLocal(),
    expectedAmount: Money.tryParse(json['expectedAmount']),
    countedAmount: Money.tryParse(json['countedAmount']),
    difference: Money.tryParse(json['difference']),
    notes: json['notes'] as String?,
    closedBy: json['closedByName'] as String?,
    closedAt: json['closedAt'] == null ? null : DateTime.parse(json['closedAt'] as String).toLocal(),
  );

  final Money openingAmount;
  final String openedBy;
  final DateTime openedAt;
  final Money? expectedAmount;
  final Money? countedAmount;

  /// Counted - expected: negative = cash missing.
  final Money? difference;
  final String? notes;
  final String? closedBy;
  final DateTime? closedAt;

  bool get isClosed => closedAt != null;
}

/// `GET /cash?date=`: [session] is null until the change fund is registered.
class CashDay {
  const CashDay({
    required this.date,
    required this.session,
    required this.openingAmount,
    required this.cashSales,
    required this.cashExpenses,
    required this.expected,
  });

  factory CashDay.fromJson(Map<String, dynamic> json) {
    final live = json['live'] as Map<String, dynamic>;
    final session = json['session'] as Map<String, dynamic>?;
    return CashDay(
      date: json['date'] as String,
      session: session == null ? null : CashSession.fromJson(session),
      openingAmount: Money.parse(live['openingAmount']),
      cashSales: Money.parse(live['cashSales']),
      cashExpenses: Money.parse(live['cashExpenses']),
      expected: Money.parse(live['expected']),
    );
  }

  final String date;
  final CashSession? session;
  final Money openingAmount;

  /// Cash payments applied to orders (the change handed back is not included).
  final Money cashSales;
  final Money cashExpenses;

  /// Fund + cash sales - cash expenses, recomputed now.
  final Money expected;
}
