import 'dart:math';

enum OrderStatus {
  draft,
  confirmed,
  inProgress,
  partiallyShipped,
  shipped,
  cancelled,
}

extension OrderStatusDefinition on OrderStatus {
  String get value => switch (this) {
    OrderStatus.draft => 'draft',
    OrderStatus.confirmed => 'confirmed',
    OrderStatus.inProgress => 'in_progress',
    OrderStatus.partiallyShipped => 'partially_shipped',
    OrderStatus.shipped => 'shipped',
    OrderStatus.cancelled => 'cancelled',
  };

  String get label => switch (this) {
    OrderStatus.draft => '下書き',
    OrderStatus.confirmed => '確定',
    OrderStatus.inProgress => '進行中',
    OrderStatus.partiallyShipped => '一部出荷',
    OrderStatus.shipped => '出荷済み',
    OrderStatus.cancelled => 'キャンセル',
  };

  static OrderStatus fromValue(String value) => OrderStatus.values.firstWhere(
    (status) => status.value == value,
    orElse: () => OrderStatus.draft,
  );
}

enum OrderListFilter {
  active,
  draft,
  confirmed,
  inProgress,
  partiallyShipped,
  shipped,
  cancelled,
}

extension OrderListFilterDefinition on OrderListFilter {
  String get label => switch (this) {
    OrderListFilter.active => '未出荷',
    OrderListFilter.draft => '下書き',
    OrderListFilter.confirmed => '確定',
    OrderListFilter.inProgress => '進行中',
    OrderListFilter.partiallyShipped => '一部出荷',
    OrderListFilter.shipped => '出荷済み',
    OrderListFilter.cancelled => 'キャンセル',
  };

  OrderStatus? get status => switch (this) {
    OrderListFilter.active => null,
    OrderListFilter.draft => OrderStatus.draft,
    OrderListFilter.confirmed => OrderStatus.confirmed,
    OrderListFilter.inProgress => OrderStatus.inProgress,
    OrderListFilter.partiallyShipped => OrderStatus.partiallyShipped,
    OrderListFilter.shipped => OrderStatus.shipped,
    OrderListFilter.cancelled => OrderStatus.cancelled,
  };
}

class CustomerSummary {
  const CustomerSummary({
    required this.id,
    required this.code,
    required this.name,
    required this.nickname,
    required this.postalCode,
    required this.address,
    required this.isActive,
    required this.version,
    required this.destinationCount,
  });

  final String id;
  final String code;
  final String name;
  final String nickname;
  final String postalCode;
  final String address;
  final bool isActive;
  final int version;
  final int destinationCount;

  String get displayName => nickname.isEmpty ? name : nickname;
}

class ShippingDestination {
  const ShippingDestination({
    required this.id,
    required this.customerId,
    required this.name,
    required this.recipientName,
    required this.postalCode,
    required this.address,
    required this.isActive,
    required this.version,
  });

  final String id;
  final String customerId;
  final String name;
  final String recipientName;
  final String postalCode;
  final String address;
  final bool isActive;
  final int version;
}

class CustomerDetail {
  const CustomerDetail({required this.customer, required this.destinations});

  final CustomerSummary customer;
  final List<ShippingDestination> destinations;
}

class OrderItem {
  const OrderItem({
    required this.id,
    required this.number,
    required this.customerId,
    required this.customerName,
    required this.customerNickname,
    required this.orderedOn,
    required this.scheduledShipOn,
    required this.varietyId,
    required this.gradeId,
    required this.orderedWeight,
    required this.allocatedWeight,
    required this.shortageWeight,
    required this.status,
    required this.version,
  });

  final String id;
  final String number;
  final String customerId;
  final String customerName;
  final String customerNickname;
  final DateTime orderedOn;
  final DateTime scheduledShipOn;
  final String varietyId;
  final String gradeId;
  final double orderedWeight;
  final double allocatedWeight;
  final double shortageWeight;
  final OrderStatus status;
  final int version;

  String get customerDisplayName =>
      customerNickname.isEmpty ? customerName : customerNickname;
}

class OrderDetail {
  const OrderDetail({
    required this.item,
    required this.shippingDestinationId,
    required this.destinationName,
    required this.recipientName,
    required this.postalCode,
    required this.address,
    required this.notes,
    required this.allocations,
  });

  final OrderItem item;
  final String shippingDestinationId;
  final String destinationName;
  final String recipientName;
  final String postalCode;
  final String address;
  final String notes;
  final List<OrderAllocation> allocations;
}

class OrderAllocation {
  const OrderAllocation({required this.lotId, required this.weight});
  final String lotId;
  final double weight;
}

class OrderReference {
  const OrderReference({
    required this.id,
    required this.code,
    required this.name,
  });
  final String id;
  final String code;
  final String name;
  String get label => name.isEmpty ? code : '$code　$name';
}

class OrderManagementData {
  const OrderManagementData({
    required this.orders,
    required this.customers,
    required this.varieties,
    required this.grades,
    required this.canManage,
  });

  final List<OrderItem> orders;
  final List<CustomerSummary> customers;
  final List<OrderReference> varieties;
  final List<OrderReference> grades;
  final bool canManage;

  String varietyLabel(String id) =>
      varieties
          .where((item) => item.id == id)
          .map((item) => item.name.isEmpty ? item.code : item.name)
          .firstOrNull ??
      '不明';

  String gradeLabel(String id) =>
      grades
          .where((item) => item.id == id)
          .map((item) => item.code)
          .firstOrNull ??
      '不明';
}

class CustomerInput {
  const CustomerInput({
    required this.code,
    required this.name,
    required this.nickname,
    required this.postalCode,
    required this.address,
  });
  final String code;
  final String name;
  final String nickname;
  final String postalCode;
  final String address;
}

class DestinationInput {
  const DestinationInput({
    required this.customerId,
    required this.name,
    required this.recipientName,
    required this.postalCode,
    required this.address,
  });
  final String customerId;
  final String name;
  final String recipientName;
  final String postalCode;
  final String address;
}

class OrderInput {
  const OrderInput({
    required this.customerId,
    required this.destinationId,
    required this.orderedOn,
    required this.scheduledShipOn,
    required this.varietyId,
    required this.gradeId,
    required this.orderedWeight,
    required this.notes,
  });
  final String customerId;
  final String destinationId;
  final DateTime orderedOn;
  final DateTime scheduledShipOn;
  final String varietyId;
  final String gradeId;
  final double orderedWeight;
  final String notes;
}

class OrderManagementFailure implements Exception {
  const OrderManagementFailure({
    required this.message,
    this.code,
    this.field,
    this.correlationId,
    this.retryable = false,
  });
  final String message;
  final String? code;
  final String? field;
  final String? correlationId;
  final bool retryable;
  bool get isConflict => code == 'CONFLICT_STALE';
  bool get isPermissionDenied => code == '42501';
}

abstract interface class OrderManagementRepository {
  Future<OrderManagementData> load({
    required OrderListFilter filter,
    String search = '',
    String customerSearch = '',
  });
  Future<OrderDetail> loadOrder(String id);
  Future<CustomerDetail> loadCustomer(String id);
  Future<List<ShippingDestination>> loadDestinations(String customerId);
  Future<CustomerSummary> registerCustomer(
    CustomerInput input, {
    required String idempotencyKey,
  });
  Future<CustomerSummary> updateCustomer(
    CustomerSummary customer,
    CustomerInput input, {
    required String reason,
    required String idempotencyKey,
  });
  Future<ShippingDestination> registerDestination(
    DestinationInput input, {
    required String idempotencyKey,
  });
  Future<ShippingDestination> updateDestination(
    ShippingDestination destination,
    DestinationInput input, {
    required String reason,
    required String idempotencyKey,
  });
  Future<OrderItem> registerOrder(
    OrderInput input, {
    required String idempotencyKey,
  });
  Future<OrderItem> updateOrder(
    OrderDetail order,
    OrderInput input, {
    required String reason,
    required String idempotencyKey,
  });
  Future<OrderItem> confirmOrder(
    OrderDetail order, {
    required String reason,
    required String idempotencyKey,
  });
  Future<OrderItem> cancelOrder(
    OrderDetail order, {
    required String reason,
    required String idempotencyKey,
  });
}

String createOrderIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
