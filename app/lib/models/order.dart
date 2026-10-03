import '../core/money.dart';
import 'user.dart';

enum OrderType {
  dineIn('DINE_IN', 'Mesa'),
  takeaway('TAKEAWAY', 'Para llevar');

  const OrderType(this.api, this.label);

  final String api;
  final String label;

  static OrderType fromApi(String value) => values.firstWhere((type) => type.api == value);
}

enum OrderStatus {
  pending('PENDING', 'Pendiente'),
  inPreparation('IN_PREPARATION', 'En preparación'),
  ready('READY', 'Listo'),
  delivered('DELIVERED', 'Entregado'),
  cancelled('CANCELLED', 'Cancelado');

  const OrderStatus(this.api, this.label);

  final String api;
  final String label;

  static OrderStatus fromApi(String value) => values.firstWhere((status) => status.api == value);

  bool get isOpen => this != delivered && this != cancelled;
}

enum PaymentStatus {
  unpaid('UNPAID', 'Sin pagar'),
  partial('PARTIAL', 'Pago parcial'),
  paid('PAID', 'Pagado');

  const PaymentStatus(this.api, this.label);

  final String api;
  final String label;

  static PaymentStatus fromApi(String value) => values.firstWhere((status) => status.api == value);
}

enum PaymentMethod {
  cash('CASH', 'Efectivo'),
  yape('YAPE', 'Yape'),
  plin('PLIN', 'Plin');

  const PaymentMethod(this.api, this.label);

  final String api;
  final String label;

  static PaymentMethod fromApi(String value) => values.firstWhere((method) => method.api == value);
}

/// Allowed transitions per role. Mirrors `backend/src/orders/order-status.ts`, which remains the
/// authority: this copy only decides which buttons to show.
const Map<OrderStatus, Map<OrderStatus, Set<Role>>> orderTransitions = {
  OrderStatus.pending: {
    OrderStatus.inPreparation: {Role.kitchen, Role.owner},
    OrderStatus.cancelled: {Role.waiter, Role.owner},
  },
  OrderStatus.inPreparation: {
    OrderStatus.ready: {Role.kitchen, Role.owner},
    OrderStatus.cancelled: {Role.owner},
  },
  OrderStatus.ready: {
    OrderStatus.delivered: {Role.waiter, Role.owner},
    OrderStatus.cancelled: {Role.owner},
  },
  OrderStatus.delivered: {},
  OrderStatus.cancelled: {},
};

class OrderItem {
  const OrderItem({
    required this.id,
    required this.dishId,
    required this.dishName,
    required this.unitPrice,
    required this.quantity,
    required this.subtotal,
    this.notes,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final unitPrice = Money.parse(json['unitPrice']);
    final quantity = json['quantity'] as int;
    return OrderItem(
      id: json['id'] as int,
      dishId: json['dishId'] as int,
      dishName: json['dishName'] as String,
      unitPrice: unitPrice,
      quantity: quantity,
      // Generated column; computed locally if the driver did not return it
      subtotal: Money.tryParse(json['subtotal']) ?? unitPrice * quantity,
      notes: json['notes'] as String?,
    );
  }

  final int id;
  final int dishId;
  final String dishName;
  final Money unitPrice;
  final int quantity;
  final Money subtotal;
  final String? notes;
}

class Payment {
  const Payment({
    required this.id,
    required this.method,
    required this.amount,
    required this.createdAt,
    this.amountReceived,
    this.changeGiven,
    this.operationNumber,
  });

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as int,
        method: PaymentMethod.fromApi(json['method'] as String),
        amount: Money.parse(json['amount']),
        amountReceived: Money.tryParse(json['amountReceived']),
        changeGiven: Money.tryParse(json['changeGiven']),
        operationNumber: json['operationNumber'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      );

  final int id;
  final PaymentMethod method;
  final Money amount;
  final Money? amountReceived;
  final Money? changeGiven;
  final String? operationNumber;
  final DateTime createdAt;
}

class Order {
  const Order({
    required this.id,
    required this.orderType,
    required this.status,
    required this.paymentStatus,
    required this.total,
    required this.items,
    required this.waiterName,
    required this.createdAt,
    required this.updatedAt,
    this.tableId,
    this.tableLabel,
    this.customerName,
    this.notes,
    this.cancelReason,
    this.payments,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final table = json['table'] as Map<String, dynamic>?;
    final waiter = json['waiter'] as Map<String, dynamic>?;
    final payments = json['payments'] as List?;
    return Order(
      id: json['id'] as int,
      orderType: OrderType.fromApi(json['orderType'] as String),
      tableId: table?['id'] as int?,
      tableLabel: table?['label'] as String?,
      customerName: json['customerName'] as String?,
      waiterName: waiter?['fullName'] as String? ?? '',
      status: OrderStatus.fromApi(json['status'] as String),
      paymentStatus: PaymentStatus.fromApi(json['paymentStatus'] as String),
      total: Money.parse(json['total']),
      notes: json['notes'] as String?,
      cancelReason: json['cancelReason'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
      items: [
        for (final item in json['items'] as List) OrderItem.fromJson(item as Map<String, dynamic>),
      ],
      payments: payments == null
          ? null
          : [for (final payment in payments) Payment.fromJson(payment as Map<String, dynamic>)],
    );
  }

  final int id;
  final OrderType orderType;
  final int? tableId;
  final String? tableLabel;
  final String? customerName;
  final String waiterName;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final Money total;
  final String? notes;
  final String? cancelReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<OrderItem> items;

  /// Only present in detail responses (`GET /orders/:id`, realtime events, mutations).
  final List<Payment>? payments;

  /// "Mesa 3" or "Para llevar · Juan"
  String get target => switch (orderType) {
        OrderType.dineIn => tableLabel ?? 'Mesa',
        OrderType.takeaway =>
          customerName == null || customerName!.isEmpty ? 'Para llevar' : 'Para llevar · $customerName',
      };

  Money get paid => (payments ?? const <Payment>[]).fold(Money.zero, (sum, p) => sum + p.amount);

  /// Null when payments were not loaded (list responses) and the order is partially paid.
  Money? get balance => switch (paymentStatus) {
        PaymentStatus.paid => Money.zero,
        PaymentStatus.unpaid => total,
        PaymentStatus.partial => payments == null ? null : total - paid,
      };

  bool get canReceivePayment =>
      status != OrderStatus.cancelled && paymentStatus != PaymentStatus.paid;

  /// Waiter still has something to do: deliver it or collect it.
  bool get needsAttention =>
      status.isOpen || (status == OrderStatus.delivered && paymentStatus != PaymentStatus.paid);

  bool canTransition(OrderStatus to, Role role) =>
      orderTransitions[status]?[to]?.contains(role) ?? false;

  /// Cancelling with payments needs a refund flow the backend does not have.
  bool canCancel(Role role) =>
      canTransition(OrderStatus.cancelled, role) && paymentStatus == PaymentStatus.unpaid;

  /// Keeps already-loaded payments when an update without them (list refresh) arrives.
  Order mergeWith(Order newer) {
    if (newer.payments != null || payments == null) return newer;
    // Any change (a payment also updates the order row) makes the cached payments stale
    if (newer.paymentStatus != paymentStatus || newer.updatedAt != updatedAt) return newer;
    return Order(
      id: newer.id,
      orderType: newer.orderType,
      tableId: newer.tableId,
      tableLabel: newer.tableLabel,
      customerName: newer.customerName,
      waiterName: newer.waiterName,
      status: newer.status,
      paymentStatus: newer.paymentStatus,
      total: newer.total,
      notes: newer.notes,
      cancelReason: newer.cancelReason,
      createdAt: newer.createdAt,
      updatedAt: newer.updatedAt,
      items: newer.items,
      payments: payments,
    );
  }
}
