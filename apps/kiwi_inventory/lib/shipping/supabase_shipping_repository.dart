import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'shipping_repository.dart';

class SupabaseShippingRepository implements ShippingRepository {
  SupabaseShippingRepository(this._client);

  factory SupabaseShippingRepository.fromInitializedClient() =>
      SupabaseShippingRepository(Supabase.instance.client);

  final SupabaseClient _client;

  @override
  Future<List<ShippingOrderSummary>> loadOrders() async {
    try {
      final values = await Future.wait<dynamic>([
        for (final status in const [
          'confirmed',
          'in_progress',
          'partially_shipped',
          'shipped',
        ])
          _client.rpc(
            'order_list',
            params: {'status_value': status, 'search_value': null},
          ),
        _client
            .from('varieties')
            .select('id, code, name')
            .eq('is_active', true),
        _client.from('grades').select('id, code').eq('is_active', true),
      ]).timeout(const Duration(seconds: 10));
      final varieties = _labels(values[4], nameKey: 'name');
      final grades = _labels(values[5]);
      final orders =
          <ShippingOrderSummary>[
            for (final source in values.take(4))
              for (final raw in source as List)
                _orderSummary(
                  Map<String, dynamic>.from(raw as Map),
                  varieties: varieties,
                  grades: grades,
                ),
          ]..sort((left, right) {
            final date = left.scheduledShipOn.compareTo(right.scheduledShipOn);
            return date != 0 ? date : left.number.compareTo(right.number);
          });
      return orders;
    } on TimeoutException {
      throw const ShippingFailure(
        message: '出荷予定の読み込みがタイムアウトしました。',
        code: 'TIMEOUT',
        retryable: true,
      );
    } on PostgrestException catch (error) {
      throw _postgrestFailure(error, action: '出荷予定を読み込めませんでした。');
    } catch (_) {
      throw const ShippingFailure(
        message: '出荷予定を読み込めませんでした。通信状況を確認してください。',
        code: 'NETWORK_FAILED',
        retryable: true,
      );
    }
  }

  @override
  Future<ShippingOrderDetail> loadOrder(String orderId) async {
    try {
      final values = await Future.wait<dynamic>([
        _client.rpc('order_get', params: {'order_id_value': orderId}),
        _client.rpc(
          'shipment_container_list',
          params: {'order_id_value': orderId},
        ),
        _client.rpc('shipment_list', params: {'order_id_value': orderId}),
        _client
            .from('workers')
            .select('id, code, display_name')
            .eq('is_active', true)
            .order('code'),
        _client
            .from('varieties')
            .select('id, code, name')
            .eq('is_active', true),
        _client.from('grades').select('id, code').eq('is_active', true),
      ]).timeout(const Duration(seconds: 10));
      if (values[0] == null) {
        throw const ShippingFailure(
          message: '受注が見つかりません。出荷予定を更新してください。',
          code: 'NOT_FOUND',
        );
      }
      final shipmentHeaders = values[2] as List;
      final shipmentRows = await Future.wait<dynamic>([
        for (final raw in shipmentHeaders)
          _client.rpc(
            'shipment_get',
            params: {'shipment_id_value': (raw as Map)['id']},
          ),
      ]).timeout(const Duration(seconds: 10));
      final shipments = [
        for (final raw in shipmentRows)
          _shipment(Map<String, dynamic>.from(raw as Map)),
      ];
      // Historical containers may no longer be shippable, so the candidate
      // list alone cannot identify the lot of every active shipment line.
      final activeLines = shipments
          .where((s) => s.status == 'confirmed')
          .expand((s) => s.lines)
          .toList();
      final containerIds = activeLines
          .map((line) => line.containerId)
          .toSet()
          .toList();
      final historicalContainers = containerIds.isEmpty
          ? const <dynamic>[]
          : await _client
                .from('containers')
                .select('id, ripening_lot_id')
                .inFilter('id', containerIds)
                .timeout(const Duration(seconds: 10));
      final lotByContainer = {
        for (final raw in historicalContainers)
          raw['id'] as String: raw['ripening_lot_id'] as String,
      };
      final remainingAllocations = <String, int>{};
      for (final raw
          in (values[0] as Map)['ripening_allocations'] as List? ?? const []) {
        final lotId = (raw as Map)['ripening_lot_id'] as String;
        remainingAllocations.update(
          lotId,
          (weight) => weight + _toHundredths(raw['allocated_weight_kg']),
          ifAbsent: () => _toHundredths(raw['allocated_weight_kg']),
        );
      }
      for (final line in activeLines) {
        final lotId = lotByContainer[line.containerId];
        if (lotId == null) {
          throw const ShippingFailure(
            message: '出荷実績のコンテナ情報を確認できません。再読み込みしてください。',
            retryable: true,
          );
        }
        remainingAllocations.update(
          lotId,
          (weight) => weight - line.weightHundredths,
          ifAbsent: () => -line.weightHundredths,
        );
      }
      final orderRow = Map<String, dynamic>.from(values[0] as Map);
      final confirmedWeight = shipments
          .where((shipment) => shipment.status == 'confirmed')
          .fold<int>(
            0,
            (sum, shipment) => sum + shipment.totalWeightHundredths,
          );
      return ShippingOrderDetail(
        order: _orderSummary(
          orderRow,
          varieties: _labels(values[4], nameKey: 'name'),
          grades: _labels(values[5]),
          shippedWeightHundredths: confirmedWeight,
        ),
        destination: _destination(orderRow['shipping_destination_snapshot']),
        remainingAllocationHundredths: remainingAllocations,
        containers: [
          for (final raw in values[1] as List)
            _container(Map<String, dynamic>.from(raw as Map)),
        ],
        shipments: shipments,
        workers: [
          for (final raw in values[3] as List)
            ShippingWorker(
              id: (raw as Map)['id'] as String,
              label: '${raw['code']}　${raw['display_name']}',
            ),
        ],
      );
    } on ShippingFailure {
      rethrow;
    } on TimeoutException {
      throw const ShippingFailure(
        message: '出荷詳細の読み込みがタイムアウトしました。',
        code: 'TIMEOUT',
        retryable: true,
      );
    } on PostgrestException catch (error) {
      throw _postgrestFailure(error, action: '出荷詳細を読み込めませんでした。');
    } catch (_) {
      throw const ShippingFailure(
        message: '出荷詳細を読み込めませんでした。通信状況を確認してください。',
        code: 'NETWORK_FAILED',
        retryable: true,
      );
    }
  }

  @override
  Future<ShipmentCompletion> confirm({
    required ShippingConfirmInput input,
    required String idempotencyKey,
  }) => _update(
    functionName: 'shipment_confirm',
    input: input.toRpcInput(),
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<ShipmentCompletion> cancel({
    required String shipmentId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  }) => _update(
    functionName: 'shipment_cancel',
    input: {
      'shipment_id': shipmentId,
      'expected_version': expectedVersion,
      'reason': reason.trim(),
    },
    idempotencyKey: idempotencyKey,
  );

  Future<ShipmentCompletion> _update({
    required String functionName,
    required Map<String, Object?> input,
    required String idempotencyKey,
  }) async {
    ShippingFailure? lastFailure;
    for (var attempt = 0; attempt < 3; attempt++) {
      final correlationId = createShippingIdempotencyKey();
      try {
        final raw = await _client
            .rpc(
              functionName,
              params: {
                'req': {
                  'meta': {
                    'idempotency_key': idempotencyKey,
                    'correlation_id': correlationId,
                  },
                  'input': input,
                },
              },
            )
            .timeout(const Duration(seconds: 10));
        final response = Map<String, dynamic>.from(raw as Map);
        if (response['ok'] == true) {
          return ShipmentCompletion(
            shipment: _shipment(
              Map<String, dynamic>.from(response['data'] as Map),
            ),
            idempotentReplay: response['idempotent_replay'] == true,
          );
        }
        final error = Map<String, dynamic>.from(response['error'] as Map);
        final details = error['details'] is Map
            ? Map<String, dynamic>.from(error['details'] as Map)
            : const <String, dynamic>{};
        final failure = ShippingFailure(
          message: error['message'] as String? ?? '出荷処理を完了できませんでした。',
          code: error['code'] as String?,
          field: details['field'] as String?,
          correlationId: response['correlation_id'] as String?,
          retryable: error['retryable'] == true,
        );
        if (!failure.retryable) throw failure;
        lastFailure = failure;
      } on ShippingFailure catch (failure) {
        if (!failure.retryable) rethrow;
        lastFailure = failure;
      } on TimeoutException {
        lastFailure = ShippingFailure(
          message: '処理結果を確認できませんでした。自動で再確認します。',
          code: 'TIMEOUT',
          correlationId: correlationId,
          retryable: true,
        );
      } on PostgrestException catch (error) {
        final failure = _postgrestFailure(error, action: '出荷処理へ接続できませんでした。');
        if (!failure.retryable) throw failure;
        lastFailure = failure;
      } catch (_) {
        lastFailure = ShippingFailure(
          message: '通信に失敗しました。自動で再確認します。',
          code: 'NETWORK_FAILED',
          correlationId: correlationId,
          retryable: true,
        );
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(seconds: attempt + 1));
      }
    }
    throw lastFailure ??
        const ShippingFailure(message: '出荷処理の結果を確認できませんでした。', retryable: true);
  }
}

Map<String, String> _labels(dynamic rows, {String? nameKey}) => {
  for (final raw in rows as List)
    (raw as Map)['id'] as String: nameKey == null || '${raw[nameKey]}'.isEmpty
        ? '${raw['code']}'
        : '${raw[nameKey]}',
};

ShippingOrderSummary _orderSummary(
  Map<String, dynamic> row, {
  required Map<String, String> varieties,
  required Map<String, String> grades,
  int shippedWeightHundredths = 0,
}) {
  final customer = row['customer'] is Map
      ? Map<String, dynamic>.from(row['customer'] as Map)
      : row;
  final nickname =
      (customer['nickname'] ?? customer['customer_nickname']) as String?;
  final name = (customer['name'] ?? customer['customer_name']) as String?;
  final varietyId = row['variety_id'] as String;
  final gradeId = row['grade_id'] as String;
  return ShippingOrderSummary(
    id: (row['id'] ?? row['order_id']) as String,
    number: (row['order_number'] ?? '') as String,
    customer: nickname?.trim().isNotEmpty == true ? nickname! : name ?? '不明',
    scheduledShipOn: DateTime.parse(row['scheduled_ship_on'] as String),
    variety: varieties[varietyId] ?? '不明',
    grade: grades[gradeId] ?? '不明',
    orderedWeightHundredths: _toHundredths(row['ordered_weight_kg']),
    shippedWeightHundredths: shippedWeightHundredths,
    status: row['status'] as String,
    version: (row['version'] as num).toInt(),
  );
}

ShippingContainer _container(Map<String, dynamic> row) => ShippingContainer(
  id: row['id'] as String,
  displayId: row['display_id'] as String,
  ripeningLotId: row['ripening_lot_id'] as String,
  version: (row['version'] as num).toInt(),
  currentWeightHundredths: _toHundredths(row['current_weight_kg']),
  availableWeightHundredths: _toHundredths(row['available_weight_kg']),
  remainingUseType: row['remaining_use_type'] as String,
  shippableUntil: DateTime.parse(row['shippable_until'] as String).toLocal(),
  bestBeforeAt: DateTime.parse(row['best_before_at'] as String).toLocal(),
);

ShipmentRecord _shipment(Map<String, dynamic> row) => ShipmentRecord(
  id: row['id'] as String,
  displayId: row['display_id'] as String,
  version: (row['version'] as num).toInt(),
  status: row['status'] as String,
  shippedAt: DateTime.parse(row['shipped_at'] as String).toLocal(),
  totalWeightHundredths: _toHundredths(row['total_weight_kg']),
  lines: [
    for (final raw in row['lines'] as List? ?? const [])
      ShipmentLine(
        containerId: (raw as Map)['container_id'] as String,
        weightHundredths: _toHundredths(raw['shipped_weight_kg']),
      ),
  ],
  cancellationReason: row['cancellation_reason'] as String?,
);

String _destination(Object? raw) {
  if (raw is! Map) return '配送先未設定';
  final row = Map<String, dynamic>.from(raw);
  return [
    row['destination_name'],
    row['recipient_name'],
    row['postal_code'] == null ? null : '〒${row['postal_code']}',
    row['address'],
  ].whereType<String>().where((value) => value.trim().isNotEmpty).join('　');
}

int _toHundredths(Object? value) =>
    (((value as num?)?.toDouble() ?? 0) * 100).round();

ShippingFailure _postgrestFailure(
  PostgrestException error, {
  required String action,
}) {
  if (const {'401', 'PGRST301', 'PGRST302', 'PGRST303'}.contains(error.code)) {
    return const ShippingFailure(
      message: 'セッションの有効期限が切れています。再ログインしてください。',
      code: 'AUTH_REQUIRED',
    );
  }
  if (const {'403', '42501'}.contains(error.code)) {
    return const ShippingFailure(
      message: '出荷情報を確認・更新する権限がありません。',
      code: 'AUTH_FORBIDDEN',
    );
  }
  if (error.code == 'PGRST202') {
    return ShippingFailure(message: '$action 管理者へ連絡してください。', code: error.code);
  }
  return ShippingFailure(
    message: '$action 通信状況を確認してください。',
    code: error.code,
    retryable: true,
  );
}
