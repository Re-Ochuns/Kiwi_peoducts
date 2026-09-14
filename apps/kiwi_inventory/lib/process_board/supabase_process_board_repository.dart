import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../work_tasks/work_task_repository.dart';
import 'process_board_repository.dart';

// Initial production rule until a dedicated cold-storage master is introduced.
const _defaultColdStoragePeriod = Duration(days: 30);

class SupabaseProcessBoardRepository implements ProcessBoardRepository {
  SupabaseProcessBoardRepository(this._client);

  factory SupabaseProcessBoardRepository.fromInitializedClient() =>
      SupabaseProcessBoardRepository(Supabase.instance.client);

  final SupabaseClient _client;

  static const _boardStatuses = [
    'cold_storage',
    'ethylene_processing',
    'resting',
    'awaiting_ripeness_check',
    'shippable',
  ];

  @override
  Future<ProcessBoardData> load() async {
    try {
      final initial = await Future.wait<dynamic>([
        _client
            .from('containers')
            .select('''
              id, display_id, current_weight_kg, status, needs_review,
              ripening_lot_id, shippable_from, shippable_until,
              sorting_result:sorting_results!containers_sorting_result_id_fkey(sorted_on),
              variety:varieties!containers_variety_id_fkey(name),
              grade:grades!containers_grade_id_fkey(code),
              location:storage_locations!containers_location_id_fkey(code, name)
            ''')
            .inFilter('status', _boardStatuses)
            .order('display_id'),
        _client.rpc('shipment_inventory_list'),
      ]).timeout(const Duration(seconds: 10));

      final containers = [
        for (final raw in initial[0] as List)
          Map<String, dynamic>.from(raw as Map),
      ];
      final coldIds = containers
          .where((row) => row['status'] == 'cold_storage')
          .map((row) => row['id'] as String)
          .toList();
      final directLotIds = containers
          .map((row) => row['ripening_lot_id'])
          .whereType<String>()
          .toSet();
      final reservations = coldIds.isEmpty
          ? const <dynamic>[]
          : await _client
                .from('inventory_reservations')
                .select('container_id, ripening_lot_id')
                .inFilter('container_id', coldIds)
                .eq('status', 'active')
                .timeout(const Duration(seconds: 10));
      final reservedLotsByContainer = <String, Set<String>>{};
      for (final raw in reservations) {
        reservedLotsByContainer
            .putIfAbsent(raw['container_id'] as String, () => {})
            .add(raw['ripening_lot_id'] as String);
      }
      final lotIds = {
        ...directLotIds,
        ...reservedLotsByContainer.values.expand((ids) => ids),
      }.toList();
      final supplemental = await Future.wait<dynamic>([
        if (lotIds.isEmpty)
          Future.value(const <dynamic>[])
        else
          _client
              .from('ripening_lots')
              .select('''
                id, display_id, use_type, planned_completion_at,
                calculated_removal_at, calculated_rest_end_at
              ''')
              .inFilter('id', lotIds),
        if (lotIds.isEmpty)
          Future.value(const <dynamic>[])
        else
          _client
              .from('ripening_allocations')
              .select('ripening_lot_id, allocation_type, order_id')
              .inFilter('ripening_lot_id', lotIds),
        if (lotIds.isEmpty)
          Future.value(const <dynamic>[])
        else
          _client
              .from('work_tasks')
              .select('''
                id, task_type, ripening_lot_id, scheduled_at, due_at,
                status, target_url, assigned_worker_id, schedule_warning,
                calendar_sync_status, calendar_sync_error
              ''')
              .inFilter('ripening_lot_id', lotIds)
              .eq('status', 'pending'),
      ]).timeout(const Duration(seconds: 10));

      final lots = {
        for (final raw in supplemental[0] as List)
          (raw as Map)['id'] as String: Map<String, dynamic>.from(raw),
      };
      final allocations = [
        for (final raw in supplemental[1] as List)
          Map<String, dynamic>.from(raw as Map),
      ];
      final orderIds = allocations
          .map((row) => row['order_id'])
          .whereType<String>()
          .toSet()
          .toList();
      final orderRows = orderIds.isEmpty
          ? const <dynamic>[]
          : await _client
                .from('orders')
                .select('id, order_number, scheduled_ship_on, status')
                .inFilter('id', orderIds)
                .timeout(const Duration(seconds: 10));
      final orders = {
        for (final raw in orderRows)
          (raw as Map)['id'] as String: Map<String, dynamic>.from(raw),
      };
      // Use the same remaining-allocation and deadline rules as shipping.
      final shippableLots = containers
          .where((row) => row['status'] == 'shippable')
          .map((row) => row['ripening_lot_id'])
          .whereType<String>()
          .toSet();
      final shippingOrderIds = allocations
          .where((row) => shippableLots.contains(row['ripening_lot_id']))
          .map((row) => row['order_id'])
          .whereType<String>()
          .where(
            (id) => const {
              'confirmed',
              'in_progress',
              'partially_shipped',
            }.contains(orders[id]?['status']),
          )
          .toSet()
          .toList();
      final shippingCandidates = await Future.wait<dynamic>([
        for (final id in shippingOrderIds)
          _client.rpc(
            'shipment_container_list',
            params: {'order_id_value': id},
          ),
      ]).timeout(const Duration(seconds: 10));
      final eligibleOrdersByContainer = <String, Set<String>>{};
      for (var index = 0; index < shippingOrderIds.length; index++) {
        for (final raw in shippingCandidates[index] as List) {
          if (_toHundredths(raw['available_weight_kg']) <= 0) continue;
          eligibleOrdersByContainer
              .putIfAbsent(raw['id'] as String, () => {})
              .add(shippingOrderIds[index]);
        }
      }
      final tasksByLot = <String, List<Map<String, dynamic>>>{};
      for (final raw in supplemental[2] as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        tasksByLot
            .putIfAbsent(row['ripening_lot_id'] as String, () => [])
            .add(row);
      }
      final remainingUse = {
        for (final raw in initial[1] as List)
          (raw as Map)['id'] as String: raw['remaining_use_type'] as String?,
      };

      return ProcessBoardData(
        items: [
          for (final container in containers)
            _containerItem(
              container,
              lotIds: container['ripening_lot_id'] is String
                  ? [container['ripening_lot_id'] as String]
                  : (reservedLotsByContainer[container['id']] ?? {}).toList(),
              eligibleOrderIds:
                  eligibleOrdersByContainer[container['id']] ?? {},
              lots: lots,
              allocations: allocations,
              orders: orders,
              tasksByLot: tasksByLot,
              remainingUse: remainingUse,
            ),
        ],
      );
    } on TimeoutException {
      throw const ProcessBoardFailure(
        message: '工程ボードの読み込みがタイムアウトしました。',
        code: 'TIMEOUT',
        retryable: true,
      );
    } on ProcessBoardFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _postgrestFailure(error);
    } catch (_) {
      throw const ProcessBoardFailure(
        message: '工程ボードを読み込めませんでした。通信状況を確認してください。',
        code: 'NETWORK_FAILED',
        retryable: true,
      );
    }
  }
}

ProcessBoardItem _containerItem(
  Map<String, dynamic> row, {
  required List<String> lotIds,
  required Set<String> eligibleOrderIds,
  required Map<String, Map<String, dynamic>> lots,
  required List<Map<String, dynamic>> allocations,
  required Map<String, Map<String, dynamic>> orders,
  required Map<String, List<Map<String, dynamic>>> tasksByLot,
  required Map<String, String?> remainingUse,
}) {
  final filteredOrders = row['status'] == 'shippable'
      ? Map<String, Map<String, dynamic>>.fromEntries(
          orders.entries.where((entry) => eligibleOrderIds.contains(entry.key)),
        )
      : orders;
  ProcessBoardItem itemFor(String? lotId) => _item(
    row,
    lotId: lotId,
    lots: lots,
    allocations: allocations,
    orders: filteredOrders,
    tasksByLot: tasksByLot,
    remainingUse: remainingUse,
  );
  if (row['status'] != 'cold_storage' || lotIds.isEmpty) {
    return itemFor(lotIds.firstOrNull);
  }
  lotIds.sort(
    (a, b) => (lots[a]?['display_id'] as String? ?? a).compareTo(
      lots[b]?['display_id'] as String? ?? b,
    ),
  );
  final items = lotIds.map(itemFor).toList();
  final first = items.first;
  final types = items.map((item) => item.useType).toSet();
  final orderNumbers = <String, String>{};
  for (final item in items) {
    for (var i = 0; i < item.orderIds.length; i++) {
      orderNumbers[item.orderIds[i]] = item.orderNumbers[i];
    }
  }
  return ProcessBoardItem(
    id: first.id,
    displayId: first.displayId,
    stage: first.stage,
    useType: types.length == 1 ? types.single : ProcessUseType.mixed,
    variety: first.variety,
    grade: first.grade,
    weightHundredths: first.weightHundredths,
    status: first.status,
    location: first.location,
    needsReview: first.needsReview,
    date: first.date,
    ripeningLotId: first.ripeningLotId,
    ripeningDisplayId: first.ripeningDisplayId,
    nextTask: first.nextTask,
    orderIds: orderNumbers.keys.toList(),
    orderNumbers: orderNumbers.values.toList(),
    plans: [
      for (final item in items)
        ProcessBoardPlan(
          id: item.ripeningLotId!,
          displayId: item.ripeningDisplayId ?? item.ripeningLotId!,
          useType: item.useType,
          orderIds: item.orderIds,
          orderNumbers: item.orderNumbers,
          nextTask: item.nextTask,
        ),
    ],
  );
}

ProcessBoardItem _item(
  Map<String, dynamic> row, {
  required String? lotId,
  required Map<String, Map<String, dynamic>> lots,
  required List<Map<String, dynamic>> allocations,
  required Map<String, Map<String, dynamic>> orders,
  required Map<String, List<Map<String, dynamic>>> tasksByLot,
  required Map<String, String?> remainingUse,
}) {
  final stage = _stage(row['status'] as String);
  final lot = lotId == null ? null : lots[lotId];
  final orderRows = allocations
      .where(
        (allocation) =>
            allocation['ripening_lot_id'] == lotId &&
            allocation['allocation_type'] == 'order' &&
            orders.containsKey(allocation['order_id']),
      )
      .map((allocation) => orders[allocation['order_id']]!)
      .where(
        (order) =>
            order['status'] != 'cancelled' && order['status'] != 'shipped',
      )
      .toList();
  orderRows.sort(
    (left, right) => '${left['scheduled_ship_on']}'.compareTo(
      '${right['scheduled_ship_on']}',
    ),
  );
  final taskType = switch (stage) {
    ProcessStage.sorted when lotId != null => 'ethylene_injection',
    ProcessStage.ripening => 'ethylene_removal_check',
    ProcessStage.resting => 'ripeness_check',
    _ => null,
  };
  final taskRow = taskType == null
      ? null
      : (tasksByLot[lotId] ?? const <Map<String, dynamic>>[])
            .where((task) => task['task_type'] == taskType)
            .firstOrNull;
  final variety = Map<String, dynamic>.from(row['variety'] as Map);
  final grade = Map<String, dynamic>.from(row['grade'] as Map);
  final location = row['location'] is Map
      ? Map<String, dynamic>.from(row['location'] as Map)
      : null;
  final displayId = row['display_id'] as String;
  final weight = _toHundredths(row['current_weight_kg']);
  return ProcessBoardItem(
    id: row['id'] as String,
    displayId: displayId,
    stage: stage,
    useType: stage == ProcessStage.shippable
        ? ProcessUseType.fromValue(remainingUse[row['id']])
        : ProcessUseType.fromValue(lot?['use_type'] as String?),
    variety: variety['name'] as String,
    grade: grade['code'] as String,
    weightHundredths: weight,
    status: row['status'] as String,
    location: location == null
        ? '未設定'
        : '${location['code']}　${location['name']}',
    needsReview: row['needs_review'] == true,
    date: _dateFor(stage, row: row, lot: lot, orders: orderRows),
    ripeningLotId: lotId,
    ripeningDisplayId: lot?['display_id'] as String?,
    orderIds: [for (final order in orderRows) order['id'] as String],
    orderNumbers: [
      for (final order in orderRows) order['order_number'] as String,
    ],
    nextTask: taskRow == null
        ? null
        : WorkTaskItem(
            id: taskRow['id'] as String,
            type: WorkTaskType.fromValue(taskRow['task_type'] as String),
            targetId: lotId!,
            targetDisplayId: lot?['display_id'] as String? ?? displayId,
            scheduledAt: DateTime.parse(taskRow['scheduled_at'] as String)
                .toLocal(),
            dueAt: DateTime.parse(taskRow['due_at'] as String).toLocal(),
            status: taskRow['status'] as String,
            targetUrl: taskRow['target_url'] as String,
            variety: variety['name'] as String,
            grade: grade['code'] as String,
            weightHundredths: weight,
            location: location == null
                ? null
                : '${location['code']}　${location['name']}',
            assignedWorkerId: taskRow['assigned_worker_id'] as String?,
            scheduleWarning: taskRow['schedule_warning'] as String?,
            calendarSyncStatus:
                taskRow['calendar_sync_status'] as String? ?? 'not_required',
            calendarSyncError: taskRow['calendar_sync_error'] as String?,
          ),
  );
}

ProcessStage _stage(String status) => switch (status) {
  'cold_storage' => ProcessStage.sorted,
  'ethylene_processing' => ProcessStage.ripening,
  'resting' || 'awaiting_ripeness_check' => ProcessStage.resting,
  'shippable' => ProcessStage.shippable,
  _ => throw const ProcessBoardFailure(
    message: '未対応のコンテナ状態が含まれています。',
    code: 'UNSUPPORTED_STATUS',
  ),
};

DateTime? _dateFor(
  ProcessStage stage, {
  required Map<String, dynamic> row,
  required Map<String, dynamic>? lot,
  required List<Map<String, dynamic>> orders,
}) => switch (stage) {
  ProcessStage.sorted => _tryDate(
    (row['sorting_result'] as Map<String, dynamic>?)?['sorted_on'],
  )?.add(_defaultColdStoragePeriod),
  ProcessStage.ripening => _tryDate(
    lot?['calculated_removal_at'] ?? lot?['planned_completion_at'],
  ),
  ProcessStage.resting => _tryDate(
    lot?['calculated_rest_end_at'] ?? lot?['planned_completion_at'],
  ),
  ProcessStage.shippable =>
    orders.isEmpty
        ? _tryDate(row['shippable_until'])
        : _tryDate(orders.first['scheduled_ship_on']),
};

DateTime? _tryDate(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toLocal() : null;

int _toHundredths(Object? value) =>
    (((value as num?)?.toDouble() ?? 0) * 100).round();

ProcessBoardFailure _postgrestFailure(PostgrestException error) {
  if (const {'401', 'PGRST301', 'PGRST302', 'PGRST303'}.contains(error.code)) {
    return const ProcessBoardFailure(
      message: 'セッションの有効期限が切れています。再ログインしてください。',
      code: 'AUTH_REQUIRED',
    );
  }
  if (const {'403', '42501'}.contains(error.code)) {
    return const ProcessBoardFailure(
      message: '工程ボードを確認する権限がありません。',
      code: 'AUTH_FORBIDDEN',
    );
  }
  return ProcessBoardFailure(
    message: '工程ボードを読み込めませんでした。通信状況を確認してください。',
    code: error.code,
    retryable: true,
  );
}
