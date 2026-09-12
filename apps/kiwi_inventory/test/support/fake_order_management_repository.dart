import 'package:kiwi_inventory/orders/order_management_repository.dart';

class FakeOrderManagementRepository implements OrderManagementRepository {
  FakeOrderManagementRepository({this.canManage = true});

  final bool canManage;
  int loadCalls = 0;
  int registerOrderCalls = 0;
  int registerCustomerCalls = 0;
  int registerDestinationCalls = 0;
  int confirmCalls = 0;
  int cancelCalls = 0;
  OrderListFilter lastFilter = OrderListFilter.active;
  String lastSearch = '';
  OrderInput? lastOrderInput;
  OrderManagementFailure? nextFailure;

  final customer = const CustomerSummary(
    id: 'customer-1',
    code: 'C-001',
    name: '青果店株式会社',
    nickname: '青果店',
    postalCode: '100-0001',
    address: '東京都千代田区1-1',
    isActive: true,
    version: 1,
    destinationCount: 1,
  );

  final destination = const ShippingDestination(
    id: 'destination-1',
    customerId: 'customer-1',
    name: '本店',
    recipientName: '受取担当者',
    postalCode: '100-0001',
    address: '東京都千代田区1-1',
    isActive: true,
    version: 1,
  );

  late final OrderItem order = OrderItem(
    id: 'order-1',
    number: '受注-2026-001',
    customerId: customer.id,
    customerName: customer.name,
    customerNickname: customer.nickname,
    orderedOn: DateTime(2026, 9, 12),
    scheduledShipOn: DateTime(2026, 9, 15),
    varietyId: 'variety-1',
    gradeId: 'grade-1',
    orderedWeight: 20,
    allocatedWeight: 12.5,
    shortageWeight: 7.5,
    status: OrderStatus.draft,
    version: 1,
  );

  @override
  Future<OrderManagementData> load({
    required OrderListFilter filter,
    String search = '',
    String customerSearch = '',
  }) async {
    loadCalls++;
    lastFilter = filter;
    lastSearch = search;
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) throw failure;
    return OrderManagementData(
      orders: [order],
      customers: [customer],
      varieties: const [
        OrderReference(id: 'variety-1', code: 'hayward', name: 'ヘイワード'),
      ],
      grades: const [OrderReference(id: 'grade-1', code: 'L', name: '')],
      canManage: canManage,
    );
  }

  @override
  Future<OrderDetail> loadOrder(String id) async => OrderDetail(
    item: order,
    shippingDestinationId: destination.id,
    destinationName: destination.name,
    recipientName: destination.recipientName,
    postalCode: destination.postalCode,
    address: destination.address,
    notes: '午前着',
    allocations: const [OrderAllocation(lotId: 'ripening-1', weight: 12.5)],
  );

  @override
  Future<CustomerDetail> loadCustomer(String id) async =>
      CustomerDetail(customer: customer, destinations: [destination]);

  @override
  Future<List<ShippingDestination>> loadDestinations(String customerId) async =>
      [destination];

  @override
  Future<CustomerSummary> registerCustomer(
    CustomerInput input, {
    required String idempotencyKey,
  }) async {
    registerCustomerCalls++;
    return customer;
  }

  @override
  Future<CustomerSummary> updateCustomer(
    CustomerSummary customer,
    CustomerInput input, {
    required String reason,
    required String idempotencyKey,
  }) async => customer;

  @override
  Future<ShippingDestination> registerDestination(
    DestinationInput input, {
    required String idempotencyKey,
  }) async {
    registerDestinationCalls++;
    return destination;
  }

  @override
  Future<ShippingDestination> updateDestination(
    ShippingDestination destination,
    DestinationInput input, {
    required String reason,
    required String idempotencyKey,
  }) async => destination;

  @override
  Future<OrderItem> registerOrder(
    OrderInput input, {
    required String idempotencyKey,
  }) async {
    registerOrderCalls++;
    lastOrderInput = input;
    return order;
  }

  @override
  Future<OrderItem> updateOrder(
    OrderDetail order,
    OrderInput input, {
    required String reason,
    required String idempotencyKey,
  }) async {
    lastOrderInput = input;
    return this.order;
  }

  @override
  Future<OrderItem> confirmOrder(
    OrderDetail order, {
    required String reason,
    required String idempotencyKey,
  }) async {
    confirmCalls++;
    return this.order;
  }

  @override
  Future<OrderItem> cancelOrder(
    OrderDetail order, {
    required String reason,
    required String idempotencyKey,
  }) async {
    cancelCalls++;
    return this.order;
  }
}
