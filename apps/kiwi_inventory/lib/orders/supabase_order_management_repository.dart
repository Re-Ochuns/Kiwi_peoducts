import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'order_management_repository.dart';

class SupabaseOrderManagementRepository
    implements OrderManagementRepository, OrderInventoryRepository {
  SupabaseOrderManagementRepository(this._client, {this.currentUserId});

  factory SupabaseOrderManagementRepository.fromInitializedClient() =>
      SupabaseOrderManagementRepository(Supabase.instance.client);

  @override
  Future<List<OrderStock>> loadInventory({
    String search = '',
    String? varietyId,
    String? gradeId,
    int offset = 0,
    String? orderId,
  }) async {
    try {
      final rows = await _client
          .rpc(
            'order_inventory_available',
            params: {
              'search_value': search.trim(),
              'variety_value': varietyId,
              'grade_value': gradeId,
              'offset_value': offset,
              'order_value': orderId,
            },
          )
          .timeout(const Duration(seconds: 10));
      int weight(dynamic value) =>
          (((value as num?)?.toDouble() ?? 0) * 100).round();
      return [
        for (final raw in rows as List)
          OrderStock(
            id: raw['id'] as String,
            displayId: raw['display_id'] as String,
            varietyId: raw['variety_id'] as String,
            gradeId: raw['grade_id'] as String,
            varietyLabel: raw['variety_label'] as String? ?? '',
            gradeLabel: raw['grade_label'] as String? ?? '',
            current: weight(raw['current_weight_kg']),
            reserved: weight(raw['reserved_weight_kg']),
            available: weight(raw['available_weight_kg']),
            ownReserved: weight(raw['own_reserved_weight_kg']),
            origin: raw['origin_label'] as String? ?? '',
            sortedOn: raw['sorted_on'] as String? ?? '',
            location: raw['location_label'] as String? ?? '',
          ),
      ];
    } catch (_) {
      throw const OrderManagementFailure(
        message: '受注用在庫を読み込めませんでした。再試行してください。',
        retryable: true,
      );
    }
  }

  final SupabaseClient _client;
  final String? currentUserId;

  @override
  Future<OrderManagementData> load({
    required OrderListFilter filter,
    String search = '',
    String customerSearch = '',
  }) async {
    try {
      final userId = currentUserId ?? _client.auth.currentUser?.id;
      final orderRequests = filter == OrderListFilter.active
          ? const [
              OrderStatus.draft,
              OrderStatus.confirmed,
              OrderStatus.inProgress,
              OrderStatus.partiallyShipped,
            ].map((status) => _loadOrders(status.value, search))
          : [_loadOrders(filter.status!.value, search)];
      final results = await Future.wait<dynamic>([
        if (userId == null)
          Future<dynamic>.value(null)
        else
          _client
              .from('profiles')
              .select('access_status')
              .eq('id', userId)
              .maybeSingle(),
        if (userId == null)
          Future<dynamic>.value(const <Map<String, dynamic>>[])
        else
          _client.from('user_roles').select('role').eq('user_id', userId),
        _client.rpc(
          'customer_list',
          params: {
            'search_value': customerSearch.trim().isEmpty
                ? null
                : customerSearch.trim(),
            'include_inactive': false,
          },
        ),
        _client
            .from('varieties')
            .select('id,code,name')
            .eq('is_active', true)
            .order('code'),
        _client
            .from('grades')
            .select('id,code')
            .eq('is_active', true)
            .order('display_order'),
        ...orderRequests,
        if (customerSearch.trim().isNotEmpty)
          _client.rpc(
            'customer_list',
            params: {'search_value': null, 'include_inactive': false},
          ),
      ]).timeout(const Duration(seconds: 10));
      final profile = results[0] is Map
          ? Map<String, dynamic>.from(results[0] as Map)
          : const <String, dynamic>{};
      final roles = results[1] is List ? results[1] as List : const [];
      final orders =
          <OrderItem>[
            for (final result
                in results
                    .skip(5)
                    .take(filter == OrderListFilter.active ? 4 : 1))
              for (final row in result as List)
                _orderFromMap(Map<String, dynamic>.from(row as Map)),
          ]..sort((left, right) {
            final date = left.scheduledShipOn.compareTo(right.scheduledShipOn);
            return date != 0 ? date : left.number.compareTo(right.number);
          });
      return OrderManagementData(
        orders: orders,
        customers: [
          for (final row in results[2] as List)
            _customerFromMap(Map<String, dynamic>.from(row as Map)),
        ],
        orderCustomers: [
          for (final row
              in (customerSearch.trim().isEmpty ? results[2] : results.last)
                  as List)
            _customerFromMap(Map<String, dynamic>.from(row as Map)),
        ],
        varieties: [
          for (final row in results[3] as List)
            _referenceFromMap(Map<String, dynamic>.from(row as Map)),
        ],
        grades: [
          for (final row in results[4] as List)
            _referenceFromMap(Map<String, dynamic>.from(row as Map)),
        ],
        canManage:
            profile['access_status'] == 'active' &&
            roles.any((value) => (value as Map)['role'] == 'administrator'),
      );
    } on TimeoutException {
      throw const OrderManagementFailure(
        message: '受注と顧客の読み込みがタイムアウトしました。',
        retryable: true,
      );
    } on PostgrestException catch (error) {
      throw OrderManagementFailure(
        message: error.code == '42501'
            ? '受注と顧客を確認する権限がありません。'
            : '受注と顧客を読み込めませんでした。通信状況を確認してください。',
        code: error.code,
        retryable: error.code != '42501',
      );
    } catch (_) {
      throw const OrderManagementFailure(
        message: '受注と顧客を読み込めませんでした。通信状況を確認してください。',
        retryable: true,
      );
    }
  }

  Future<dynamic> _loadOrders(String status, String search) => _client.rpc(
    'order_list',
    params: {
      'status_value': status,
      'search_value': search.trim().isEmpty ? null : search.trim(),
    },
  );

  @override
  Future<OrderDetail> loadOrder(String id) async {
    try {
      final raw = await _client
          .rpc('order_get', params: {'order_id_value': id})
          .timeout(const Duration(seconds: 10));
      if (raw == null) {
        throw const OrderManagementFailure(message: '受注が見つかりません。');
      }
      return _orderDetailFromMap(Map<String, dynamic>.from(raw as Map));
    } on OrderManagementFailure {
      rethrow;
    } on TimeoutException {
      throw const OrderManagementFailure(
        message: '受注詳細の読み込みがタイムアウトしました。',
        retryable: true,
      );
    } catch (_) {
      throw const OrderManagementFailure(
        message: '受注詳細を読み込めませんでした。',
        retryable: true,
      );
    }
  }

  @override
  Future<CustomerDetail> loadCustomer(String id) async {
    try {
      final raw = await _client
          .rpc('customer_get', params: {'customer_id_value': id})
          .timeout(const Duration(seconds: 10));
      if (raw == null) {
        throw const OrderManagementFailure(message: '顧客が見つかりません。');
      }
      final row = Map<String, dynamic>.from(raw as Map);
      final destinations = row['destinations'] is List
          ? row['destinations'] as List
          : const [];
      return CustomerDetail(
        customer: _customerFromMap(row),
        destinations: [
          for (final destination in destinations)
            _destinationFromMap(Map<String, dynamic>.from(destination as Map)),
        ],
      );
    } on OrderManagementFailure {
      rethrow;
    } on TimeoutException {
      throw const OrderManagementFailure(
        message: '顧客詳細の読み込みがタイムアウトしました。',
        retryable: true,
      );
    } catch (_) {
      throw const OrderManagementFailure(
        message: '顧客詳細を読み込めませんでした。',
        retryable: true,
      );
    }
  }

  @override
  Future<List<ShippingDestination>> loadDestinations(String customerId) async {
    try {
      final rows = await _client
          .rpc(
            'shipping_destination_list',
            params: {
              'customer_id_value': customerId,
              'include_inactive': false,
            },
          )
          .timeout(const Duration(seconds: 10));
      return [
        for (final row in rows as List)
          _destinationFromMap(Map<String, dynamic>.from(row as Map)),
      ];
    } catch (_) {
      throw const OrderManagementFailure(
        message: '配送先を読み込めませんでした。',
        retryable: true,
      );
    }
  }

  @override
  Future<CustomerSummary> registerCustomer(
    CustomerInput input, {
    required String idempotencyKey,
  }) async {
    final data = await _execute(
      'customer_register',
      _customerInput(input),
      idempotencyKey,
    );
    return _customerFromMap(data);
  }

  @override
  Future<CustomerSummary> updateCustomer(
    CustomerSummary customer,
    CustomerInput input, {
    required String reason,
    required String idempotencyKey,
  }) async {
    final data = await _execute('customer_update', {
      'customer_id': customer.id,
      'expected_version': customer.version,
      ..._customerInput(input),
      'reason': reason.trim(),
    }, idempotencyKey);
    return _customerFromMap(data);
  }

  Map<String, Object> _customerInput(CustomerInput input) => {
    'customer_code': input.code.trim(),
    'name': input.name.trim(),
    if (input.nickname.trim().isNotEmpty) 'nickname': input.nickname.trim(),
    'postal_code': input.postalCode.trim(),
    'address': input.address.trim(),
  };

  @override
  Future<ShippingDestination> registerDestination(
    DestinationInput input, {
    required String idempotencyKey,
  }) async {
    final data = await _execute(
      'shipping_destination_register',
      _destinationInput(input),
      idempotencyKey,
    );
    return _destinationFromMap(data);
  }

  @override
  Future<ShippingDestination> updateDestination(
    ShippingDestination destination,
    DestinationInput input, {
    required String reason,
    required String idempotencyKey,
  }) async {
    final data = await _execute('shipping_destination_update', {
      'shipping_destination_id': destination.id,
      'expected_version': destination.version,
      ..._destinationInput(input),
      'reason': reason.trim(),
    }, idempotencyKey);
    return _destinationFromMap(data);
  }

  Map<String, Object> _destinationInput(DestinationInput input) => {
    'customer_id': input.customerId,
    'destination_name': input.name.trim(),
    'recipient_name': input.recipientName.trim(),
    'postal_code': input.postalCode.trim(),
    'address': input.address.trim(),
  };

  @override
  Future<OrderItem> registerOrder(
    OrderInput input, {
    required String idempotencyKey,
  }) async {
    final data = await _execute(
      'order_register',
      _orderInput(input),
      idempotencyKey,
    );
    return (await loadOrder(data['id'] as String)).item;
  }

  @override
  Future<OrderItem> updateOrder(
    OrderDetail order,
    OrderInput input, {
    required String reason,
    required String idempotencyKey,
  }) async {
    final data = await _execute('order_update', {
      'order_id': order.item.id,
      'expected_version': order.item.version,
      ..._orderInput(input),
      'reason': reason.trim(),
    }, idempotencyKey);
    return (await loadOrder(data['id'] as String)).item;
  }

  Map<String, Object> _orderInput(OrderInput input) => {
    'customer_id': input.customerId,
    'shipping_destination_id': input.destinationId,
    'ordered_date': _date(input.orderedOn),
    'scheduled_ship_date': _date(input.scheduledShipOn),
    'variety_id': input.varietyId,
    'grade_id': input.gradeId,
    'ordered_weight_kg': input.orderedWeight,
    if (input.reservations != null)
      'reservations': [for (final r in input.reservations!) r.toJson()],
    if (input.notes.trim().isNotEmpty) 'notes': input.notes.trim(),
  };

  @override
  Future<OrderItem> confirmOrder(
    OrderDetail order, {
    required String reason,
    required String idempotencyKey,
  }) => _transition('order_confirm', order, reason, idempotencyKey);

  @override
  Future<OrderItem> cancelOrder(
    OrderDetail order, {
    required String reason,
    required String idempotencyKey,
  }) => _transition('order_cancel', order, reason, idempotencyKey);

  Future<OrderItem> _transition(
    String functionName,
    OrderDetail order,
    String reason,
    String key,
  ) async {
    final data = await _execute(functionName, {
      'order_id': order.item.id,
      'expected_version': order.item.version,
      'reason': reason.trim(),
    }, key);
    return (await loadOrder(data['id'] as String)).item;
  }

  Future<Map<String, dynamic>> _execute(
    String functionName,
    Map<String, Object> input,
    String key,
  ) async {
    OrderManagementFailure? lastFailure;
    for (var attempt = 0; attempt < 3; attempt++) {
      final correlationId = createOrderIdempotencyKey();
      try {
        final raw = await _client
            .rpc(
              functionName,
              params: {
                'req': {
                  'meta': {
                    'idempotency_key': key,
                    'correlation_id': correlationId,
                  },
                  'input': input,
                },
              },
            )
            .timeout(const Duration(seconds: 10));
        final response = Map<String, dynamic>.from(raw as Map);
        if (response['ok'] == true) {
          return Map<String, dynamic>.from(response['data'] as Map);
        }
        final error = response['error'] is Map
            ? Map<String, dynamic>.from(response['error'] as Map)
            : const <String, dynamic>{};
        final details = error['details'] is Map
            ? Map<String, dynamic>.from(error['details'] as Map)
            : const <String, dynamic>{};
        final failure = OrderManagementFailure(
          message: error['message'] as String? ?? '更新できませんでした。',
          code: error['code'] as String?,
          field: details['field'] as String?,
          correlationId: response['correlation_id'] as String?,
          retryable: error['retryable'] == true,
        );
        if (!failure.retryable) throw failure;
        lastFailure = failure;
      } on OrderManagementFailure catch (failure) {
        if (!failure.retryable) rethrow;
        lastFailure = failure;
      } on TimeoutException {
        lastFailure = OrderManagementFailure(
          message: '更新結果を確認できませんでした。自動で再確認します。',
          correlationId: correlationId,
          retryable: true,
        );
      } on PostgrestException catch (error) {
        if (error.code == 'PGRST202') {
          throw OrderManagementFailure(
            message: '受注管理機能の構成が一致していません。管理者へ連絡してください。',
            code: error.code,
          );
        }
        if (error.code == '42501') {
          throw OrderManagementFailure(
            message: '受注を更新する権限がありません。',
            code: error.code,
          );
        }
        lastFailure = OrderManagementFailure(
          message: '更新処理へ接続できませんでした。自動で再確認します。',
          correlationId: correlationId,
          retryable: true,
        );
      } catch (_) {
        lastFailure = OrderManagementFailure(
          message: '通信に失敗しました。自動で再確認します。',
          correlationId: correlationId,
          retryable: true,
        );
      }
      if (attempt < 2) {
        await Future<void>.delayed(
          Duration(
            seconds: attempt + 1,
            milliseconds: Random.secure().nextInt(251),
          ),
        );
      }
    }
    throw lastFailure ??
        const OrderManagementFailure(
          message: '更新結果を確認できませんでした。',
          retryable: true,
        );
  }
}

CustomerSummary _customerFromMap(Map<String, dynamic> row) => CustomerSummary(
  id: (row['customer_id'] ?? row['id']) as String,
  code: row['customer_code'] as String? ?? '',
  name: row['name'] as String? ?? '',
  nickname: row['nickname'] as String? ?? '',
  postalCode: row['postal_code'] as String? ?? '',
  address: row['address'] as String? ?? '',
  isActive: row['is_active'] == true,
  version: (row['version'] as num?)?.toInt() ?? 1,
  destinationCount: (row['destination_count'] as num?)?.toInt() ?? 0,
);

ShippingDestination _destinationFromMap(Map<String, dynamic> row) =>
    ShippingDestination(
      id: (row['shipping_destination_id'] ?? row['id']) as String,
      customerId: row['customer_id'] as String,
      name: row['destination_name'] as String? ?? '',
      recipientName: row['recipient_name'] as String? ?? '',
      postalCode: row['postal_code'] as String? ?? '',
      address: row['address'] as String? ?? '',
      isActive: row['is_active'] == true,
      version: (row['version'] as num?)?.toInt() ?? 1,
    );

OrderReference _referenceFromMap(Map<String, dynamic> row) => OrderReference(
  id: row['id'] as String,
  code: row['code'] as String? ?? '',
  name: row['name'] as String? ?? '',
);

OrderItem _orderFromMap(Map<String, dynamic> row) {
  final customer = row['customer'] is Map
      ? Map<String, dynamic>.from(row['customer'] as Map)
      : const <String, dynamic>{};
  return OrderItem(
    id: (row['order_id'] ?? row['id']) as String,
    number: row['order_number'] as String? ?? '',
    customerId: row['customer_id'] as String,
    customerName:
        row['customer_name'] as String? ?? customer['name'] as String? ?? '',
    customerNickname:
        row['customer_nickname'] as String? ??
        customer['nickname'] as String? ??
        '',
    orderedOn: DateTime.parse(
      (row['ordered_on'] ?? row['ordered_date']) as String,
    ),
    scheduledShipOn: DateTime.parse(
      (row['scheduled_ship_on'] ?? row['scheduled_ship_date']) as String,
    ),
    varietyId: row['variety_id'] as String,
    gradeId: row['grade_id'] as String,
    orderedWeight: (row['ordered_weight_kg'] as num).toDouble(),
    allocatedWeight: (row['allocated_weight_kg'] as num?)?.toDouble() ?? 0,
    shortageWeight: (row['shortage_weight_kg'] as num?)?.toDouble() ?? 0,
    status: OrderStatusDefinition.fromValue(row['status'] as String),
    version: (row['version'] as num?)?.toInt() ?? 1,
  );
}

OrderDetail _orderDetailFromMap(Map<String, dynamic> row) {
  final snapshot = row['shipping_destination_snapshot'] is Map
      ? Map<String, dynamic>.from(row['shipping_destination_snapshot'] as Map)
      : const <String, dynamic>{};
  final allocations = row['ripening_allocations'] is List
      ? row['ripening_allocations'] as List
      : const [];
  return OrderDetail(
    reservations: _stockReservations(row['reservations']),
    item: _orderFromMap(row),
    shippingDestinationId: row['shipping_destination_id'] as String,
    destinationName: snapshot['destination_name'] as String? ?? '',
    recipientName: snapshot['recipient_name'] as String? ?? '',
    postalCode: snapshot['postal_code'] as String? ?? '',
    address: snapshot['address'] as String? ?? '',
    notes: row['notes'] as String? ?? '',
    allocations: [
      for (final value in allocations)
        OrderAllocation(
          lotId: (value as Map)['ripening_lot_id'] as String,
          weight: (value['allocated_weight_kg'] as num).toDouble(),
        ),
    ],
  );
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

List<OrderStockReservation> _stockReservations(dynamic raw) {
  final totals = <String, int>{}, planned = <String, int>{};
  final labels = <String, String>{};
  for (final row in raw as List? ?? const []) {
    final id = row['container_id'] as String;
    final weight = ((row['reserved_weight_kg'] as num).toDouble() * 100)
        .round();
    totals[id] = (totals[id] ?? 0) + weight;
    labels[id] = row['display_id'] as String? ?? id;
    if (row['ripening_lot_id'] != null) {
      planned[id] = (planned[id] ?? 0) + weight;
    }
  }
  return [
    for (final entry in totals.entries)
      OrderStockReservation(
        containerId: entry.key,
        displayId: labels[entry.key]!,
        weightHundredths: entry.value,
        plannedHundredths: planned[entry.key] ?? 0,
      ),
  ];
}
