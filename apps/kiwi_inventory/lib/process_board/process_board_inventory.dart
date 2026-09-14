import 'process_board_repository.dart';

// Allocations belong to lots. Never apportion them to individual containers.
List<ProcessBoardItem> buildProcessBoardInventory({
  required List<ProcessBoardItem> items,
  required List<Map<String, dynamic>> reservations,
  required List<Map<String, dynamic>> allocations,
  required Map<String, Map<String, dynamic>> orders,
}) {
  final result = <ProcessBoardItem>[];
  final groups = <String, List<ProcessBoardItem>>{};
  final reservedByLot = <String, int>{};
  for (final item in items) {
    if (item.stage != ProcessStage.sorted) {
      final lotId = item.ripeningLotId;
      if (lotId != null) {
        groups.putIfAbsent(lotId, () => []).add(item);
      } else if (item.useType == ProcessUseType.unassigned ||
          item.useType == ProcessUseType.reserve) {
        result.add(item);
      }
      continue;
    }
    final active = reservations.where((row) => row['container_id'] == item.id);
    var reserved = 0;
    var known = true;
    for (final row in active) {
      final weight = _weight(row['reserved_weight_kg']);
      if (weight == null) {
        known = false;
        continue;
      }
      reserved += weight;
      final lotId = row['ripening_lot_id'] as String;
      reservedByLot.update(
        lotId,
        (value) => value + weight,
        ifAbsent: () => weight,
      );
      groups.putIfAbsent(lotId, () => []).add(item.forPlan(lotId));
    }
    if (known && item.weightHundredths > reserved) {
      result.add(
        _inventoryItem(
          item,
          id: item.id,
          displayId: item.displayId,
          total: item.weightHundredths - reserved,
          order: 0,
          containers: [item.displayId],
          lot: false,
        ),
      );
    }
  }
  for (final entry in groups.entries) {
    final lotId = entry.key;
    final members = entry.value;
    final first = members.first;
    final total =
        reservedByLot[lotId] ??
        members.fold<int>(0, (sum, item) => sum + item.weightHundredths);
    var orderRemaining = 0;
    var known = true;
    for (final allocation in allocations.where(
      (row) =>
          row['ripening_lot_id'] == lotId && row['allocation_type'] == 'order',
    )) {
      final order = orders[allocation['order_id']];
      final allocated = _weight(allocation['allocated_weight_kg']);
      if (order == null || allocated == null) {
        known = false;
        break;
      }
      if (order['status'] == 'cancelled' || order['status'] == 'shipped') {
        continue;
      }
      var shipped = 0;
      for (final shipment in (order['shipments'] as List? ?? const [])) {
        if (shipment['status'] != 'confirmed') continue;
        for (final line in (shipment['shipment_lines'] as List? ?? const [])) {
          if (line['container']?['ripening_lot_id'] != lotId) continue;
          final weight = _weight(line['shipped_weight_kg']);
          if (weight == null) {
            known = false;
          } else {
            shipped += weight;
          }
        }
      }
      orderRemaining += (allocated - shipped).clamp(0, allocated);
    }
    if (!known || total <= orderRemaining) continue;
    result.add(
      _inventoryItem(
        first,
        id: 'inventory-lot-$lotId',
        displayId: first.ripeningDisplayId ?? lotId,
        total: total,
        order: orderRemaining,
        containers: members.map((item) => item.displayId).toSet().toList()
          ..sort(),
        lot: true,
        location: members.map((item) => item.location).toSet().join(' / '),
        needsReview: members.any((item) => item.needsReview),
      ),
    );
  }
  result.sort((a, b) => a.displayId.compareTo(b.displayId));
  return result;
}

int? _weight(Object? value) => value is num ? (value * 100).round() : null;

ProcessBoardItem _inventoryItem(
  ProcessBoardItem source, {
  required String id,
  required String displayId,
  required int total,
  required int order,
  required List<String> containers,
  required bool lot,
  String? location,
  bool? needsReview,
}) => ProcessBoardItem(
  id: id,
  displayId: displayId,
  stage: source.stage,
  useType: lot
      ? (order > 0 ? ProcessUseType.mixed : ProcessUseType.reserve)
      : ProcessUseType.unassigned,
  variety: source.variety,
  grade: source.grade,
  weightHundredths: total - order,
  status: source.status,
  location: location ?? source.location,
  needsReview: needsReview ?? source.needsReview,
  date: source.date,
  ripeningLotId: lot ? source.ripeningLotId : null,
  ripeningDisplayId: lot ? source.ripeningDisplayId : null,
  orderIds: const [],
  orderNumbers: const [],
  inventoryBalance: ProcessBoardInventoryBalance(
    totalHundredths: total,
    orderHundredths: order,
    containerDisplayIds: containers,
    isLot: lot,
  ),
);
