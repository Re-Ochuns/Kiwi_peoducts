import 'dart:math';

class ShippingOrderSummary {
  const ShippingOrderSummary({
    required this.id,
    required this.number,
    required this.customer,
    required this.scheduledShipOn,
    required this.variety,
    required this.grade,
    required this.orderedWeightHundredths,
    required this.shippedWeightHundredths,
    required this.status,
    required this.version,
  });

  final String id;
  final String number;
  final String customer;
  final DateTime scheduledShipOn;
  final String variety;
  final String grade;
  final int orderedWeightHundredths;
  final int shippedWeightHundredths;
  final String status;
  final int version;

  int get remainingWeightHundredths =>
      max(0, orderedWeightHundredths - shippedWeightHundredths);
}

class ShippingOrderDetail {
  const ShippingOrderDetail({
    required this.order,
    required this.destination,
    required this.containers,
    required this.shipments,
    required this.workers,
  });

  final ShippingOrderSummary order;
  final String destination;
  final List<ShippingContainer> containers;
  final List<ShipmentRecord> shipments;
  final List<ShippingWorker> workers;
}

class ShippingContainer {
  const ShippingContainer({
    required this.id,
    required this.displayId,
    required this.ripeningLotId,
    required this.version,
    required this.currentWeightHundredths,
    required this.availableWeightHundredths,
    required this.remainingUseType,
    required this.shippableUntil,
    required this.bestBeforeAt,
  });

  final String id;
  final String displayId;
  final String ripeningLotId;
  final int version;
  final int currentWeightHundredths;
  final int availableWeightHundredths;
  final String remainingUseType;
  final DateTime shippableUntil;
  final DateTime bestBeforeAt;

  String get useLabel => switch (remainingUseType) {
    'order' => '受注分',
    'mixed' => '受注分・予備',
    _ => '予備',
  };
}

class ShippingWorker {
  const ShippingWorker({required this.id, required this.label});

  final String id;
  final String label;
}

class ShipmentLine {
  const ShipmentLine({
    required this.containerId,
    required this.weightHundredths,
  });

  final String containerId;
  final int weightHundredths;
}

class ShipmentRecord {
  const ShipmentRecord({
    required this.id,
    required this.displayId,
    required this.version,
    required this.status,
    required this.shippedAt,
    required this.totalWeightHundredths,
    required this.lines,
    this.cancellationReason,
  });

  final String id;
  final String displayId;
  final int version;
  final String status;
  final DateTime shippedAt;
  final int totalWeightHundredths;
  final List<ShipmentLine> lines;
  final String? cancellationReason;

  bool get canCancel => status == 'confirmed';
}

class ShippingLineInput {
  const ShippingLineInput({
    required this.containerId,
    required this.expectedVersion,
    required this.weightHundredths,
  });

  final String containerId;
  final int expectedVersion;
  final int weightHundredths;

  Map<String, Object> toRpcInput() => {
    'container_id': containerId,
    'expected_version': expectedVersion,
    'shipped_weight_kg': weightHundredths / 100,
  };
}

class ShippingConfirmInput {
  const ShippingConfirmInput({
    required this.orderId,
    required this.expectedOrderVersion,
    required this.shippedAt,
    required this.workerId,
    required this.reason,
    required this.lines,
    this.notes,
  });

  final String orderId;
  final int expectedOrderVersion;
  final DateTime shippedAt;
  final String workerId;
  final String reason;
  final List<ShippingLineInput> lines;
  final String? notes;

  Map<String, Object?> toRpcInput() => {
    'order_id': orderId,
    'expected_order_version': expectedOrderVersion,
    'shipped_at': shippedAt.toUtc().toIso8601String(),
    'worker_id': workerId,
    'checked': true,
    'reason': reason.trim(),
    'lines': [for (final line in lines) line.toRpcInput()],
    'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
  };
}

class ShipmentCompletion {
  const ShipmentCompletion({
    required this.shipment,
    required this.idempotentReplay,
  });

  final ShipmentRecord shipment;
  final bool idempotentReplay;
}

class ShippingFailure implements Exception {
  const ShippingFailure({
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

  bool get isConflict => const {
    'CONFLICT_STALE',
    'INVENTORY_CONFLICT',
    'ORDER_UNAVAILABLE',
    'SHIPMENT_UNAVAILABLE',
  }.contains(code);

  bool get isPermissionDenied =>
      code == 'AUTH_REQUIRED' || code == 'AUTH_FORBIDDEN';
}

abstract interface class ShippingRepository {
  Future<List<ShippingOrderSummary>> loadOrders();

  Future<ShippingOrderDetail> loadOrder(String orderId);

  Future<ShipmentCompletion> confirm({
    required ShippingConfirmInput input,
    required String idempotencyKey,
  });

  Future<ShipmentCompletion> cancel({
    required String shipmentId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  });
}

String createShippingIdempotencyKey() {
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

String formatShippingWeight(int hundredths) =>
    '${(hundredths / 100).toStringAsFixed(2)} kg';
