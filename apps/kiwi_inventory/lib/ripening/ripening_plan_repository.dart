import 'dart:convert';

class RipeningReferenceOption {
  const RipeningReferenceOption({required this.id, required this.label});

  final String id;
  final String label;
}

class RipeningInventoryOption {
  const RipeningInventoryOption({
    required this.id,
    required this.displayId,
    required this.varietyId,
    required this.varietyLabel,
    required this.gradeId,
    required this.gradeLabel,
    required this.harvestMonth,
    required this.availableWeightHundredths,
  });

  final String id;
  final String displayId;
  final String varietyId;
  final String varietyLabel;
  final String gradeId;
  final String gradeLabel;
  final int harvestMonth;
  final int availableWeightHundredths;
}

class RipeningOrderOption {
  const RipeningOrderOption({
    required this.id,
    required this.orderNumber,
    required this.customerLabel,
    required this.varietyId,
    required this.gradeId,
    required this.availableWeightHundredths,
    required this.scheduledShipDate,
  });

  final String id;
  final String orderNumber;
  final String customerLabel;
  final String varietyId;
  final String gradeId;
  final int availableWeightHundredths;
  final DateTime scheduledShipDate;
}

class RipeningRuleOption {
  const RipeningRuleOption({
    required this.harvestMonth,
    required this.varietyId,
    required this.ethyleneHours,
    required this.restDays,
  });

  final int harvestMonth;
  final String varietyId;
  final double ethyleneHours;
  final double restDays;
}

class RipeningPlanOptions {
  const RipeningPlanOptions({
    required this.inventories,
    required this.orders,
    required this.locations,
    required this.workers,
    required this.rules,
  });

  final List<RipeningInventoryOption> inventories;
  final List<RipeningOrderOption> orders;
  final List<RipeningReferenceOption> locations;
  final List<RipeningReferenceOption> workers;
  final List<RipeningRuleOption> rules;
}

enum RipeningAllocationType { order, reserve }

class RipeningAllocationInput {
  const RipeningAllocationInput({
    required this.type,
    required this.weightHundredths,
    this.orderId,
  });

  final RipeningAllocationType type;
  final String? orderId;
  final int weightHundredths;

  Map<String, Object?> toRpcInput() => {
    'allocation_type': type == RipeningAllocationType.order
        ? 'order'
        : 'reserve',
    'order_id': type == RipeningAllocationType.order ? orderId : null,
    'allocated_weight_kg': weightHundredths / 100,
  };
}

class RipeningPlanInput {
  const RipeningPlanInput({
    required this.inventory,
    required this.totalWeightHundredths,
    required this.locationId,
    required this.plannedEthyleneAt,
    required this.plannedCompletionAt,
    required this.workerId,
    required this.allocations,
    this.notes,
  });

  final RipeningInventoryOption inventory;
  final int totalWeightHundredths;
  final String locationId;
  final DateTime plannedEthyleneAt;
  final DateTime plannedCompletionAt;
  final String workerId;
  final List<RipeningAllocationInput> allocations;
  final String? notes;

  Map<String, Object?> toRpcInput() => {
    'variety_id': inventory.varietyId,
    'grade_id': inventory.gradeId,
    'total_weight_kg': totalWeightHundredths / 100,
    'storage_location_id': locationId,
    'planned_ethylene_at': plannedEthyleneAt.toUtc().toIso8601String(),
    'planned_completion_at': plannedCompletionAt.toUtc().toIso8601String(),
    'assigned_worker_id': workerId,
    'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
    'allocations': [
      for (final allocation in allocations) allocation.toRpcInput(),
    ],
    'reservations': [
      {
        'container_id': inventory.id,
        'reserved_weight_kg': totalWeightHundredths / 100,
      },
    ],
  };

  String get signature => jsonEncode(toRpcInput());
}

class RipeningPlanResult {
  const RipeningPlanResult({
    required this.id,
    required this.displayId,
    required this.status,
    required this.version,
    required this.plannedEthyleneAt,
    required this.plannedCompletionAt,
    required this.idempotentReplay,
  });

  final String id;
  final String displayId;
  final String status;
  final int version;
  final DateTime plannedEthyleneAt;
  final DateTime plannedCompletionAt;
  final bool idempotentReplay;
}

class RipeningPlanFailure implements Exception {
  const RipeningPlanFailure({
    required this.message,
    this.code,
    this.field,
    this.reason,
    this.correlationId,
    this.retryable = false,
  });

  final String message;
  final String? code;
  final String? field;
  final String? reason;
  final String? correlationId;
  final bool retryable;

  bool get isPermissionDenied =>
      code == 'AUTH_REQUIRED' || code == 'AUTH_FORBIDDEN';
}

abstract interface class RipeningPlanRepository {
  Future<RipeningPlanOptions> loadOptions();

  Future<RipeningPlanResult> register({
    required RipeningPlanInput input,
    required String idempotencyKey,
  });

  Future<RipeningPlanResult> update({
    required RipeningPlanInput input,
    required String ripeningLotId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  });

  Future<RipeningPlanResult> confirm({
    required String ripeningLotId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  });
}

String formatRipeningWeight(int hundredths) =>
    (hundredths / 100).toStringAsFixed(2);
