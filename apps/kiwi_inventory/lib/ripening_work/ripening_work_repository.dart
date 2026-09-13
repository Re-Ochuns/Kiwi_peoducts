import 'dart:math';

enum RipeningWorkType {
  ethyleneInjection,
  ethyleneRemoval,
  ripenessCheck;

  String get rpcName => switch (this) {
    RipeningWorkType.ethyleneInjection =>
      'ripening_ethylene_injection_complete',
    RipeningWorkType.ethyleneRemoval => 'ripening_ethylene_removal_complete',
    RipeningWorkType.ripenessCheck => 'ripening_ripeness_complete',
  };

  String get value => switch (this) {
    RipeningWorkType.ethyleneInjection => 'ethylene_injection',
    RipeningWorkType.ethyleneRemoval => 'ethylene_removal_check',
    RipeningWorkType.ripenessCheck => 'ripeness_check',
  };

  String get label => switch (this) {
    RipeningWorkType.ethyleneInjection => 'エチレン注入',
    RipeningWorkType.ethyleneRemoval => 'エチレン抜き確認',
    RipeningWorkType.ripenessCheck => '追熟確認',
  };

  String get completeLabel => switch (this) {
    RipeningWorkType.ethyleneInjection => '注入完了を記録',
    RipeningWorkType.ethyleneRemoval => '抜き確認と寝かせ開始を記録',
    RipeningWorkType.ripenessCheck => '追熟確認を完了',
  };
}

class RipeningWorkOption {
  const RipeningWorkOption({required this.id, required this.label});

  final String id;
  final String label;
}

class RipeningWorkDetails {
  const RipeningWorkDetails({
    required this.id,
    required this.displayId,
    required this.version,
    required this.status,
    required this.weightHundredths,
    required this.locationId,
    required this.workerId,
    required this.plannedEthyleneAt,
    required this.plannedCompletionAt,
    required this.results,
    required this.tasks,
    required this.locations,
    required this.workers,
  });

  final String id;
  final String displayId;
  final int version;
  final String status;
  final int weightHundredths;
  final String? locationId;
  final String workerId;
  final DateTime plannedEthyleneAt;
  final DateTime plannedCompletionAt;
  final List<RipeningWorkRecord> results;
  final List<RipeningWorkTask> tasks;
  final List<RipeningWorkOption> locations;
  final List<RipeningWorkOption> workers;
}

class RipeningWorkRecord {
  const RipeningWorkRecord({
    required this.type,
    required this.actualAt,
    this.restStartedAt,
  });

  final String type;
  final DateTime actualAt;
  final DateTime? restStartedAt;
}

class RipeningWorkInput {
  const RipeningWorkInput({
    required this.ripeningLotId,
    required this.expectedVersion,
    required this.actualAt,
    required this.actualTemperature,
    required this.locationId,
    required this.workerId,
    this.restStartedAt,
    this.restTemperature,
    this.notes,
  });

  final String ripeningLotId;
  final int expectedVersion;
  final DateTime actualAt;
  final double actualTemperature;
  final String locationId;
  final String workerId;
  final DateTime? restStartedAt;
  final double? restTemperature;
  final String? notes;

  Map<String, Object?> toRpcInput(RipeningWorkType type) => {
    'ripening_lot_id': ripeningLotId,
    'expected_version': expectedVersion,
    'checked': true,
    'actual_at': actualAt.toUtc().toIso8601String(),
    'actual_temperature': actualTemperature,
    'location_id': locationId,
    'performed_by': workerId,
    'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
    if (type == RipeningWorkType.ethyleneRemoval) ...{
      'rest_started_at': restStartedAt!.toUtc().toIso8601String(),
      'rest_temperature': restTemperature,
    },
  };
}

class RipeningWorkCompletion {
  const RipeningWorkCompletion({
    required this.displayId,
    required this.version,
    required this.status,
    required this.actualAt,
    required this.idempotentReplay,
  });

  final String displayId;
  final int version;
  final String status;
  final DateTime actualAt;
  final bool idempotentReplay;
}

class RipeningWorkFailure implements Exception {
  const RipeningWorkFailure({
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
  bool get isPermissionDenied =>
      code == 'AUTH_REQUIRED' || code == 'AUTH_FORBIDDEN';
}

abstract interface class RipeningWorkRepository {
  Future<RipeningWorkDetails> load(String ripeningLotId);

  Future<RipeningWorkCompletion> complete({
    required RipeningWorkType type,
    required RipeningWorkInput input,
    required String idempotencyKey,
  });
}

String createRipeningWorkIdempotencyKey() {
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

String formatRipeningWorkWeight(int hundredths) =>
    '${(hundredths / 100).toStringAsFixed(2)} kg';

class RipeningWorkTask {
  const RipeningWorkTask({
    required this.type,
    required this.productLabel,
    required this.scheduledAt,
    required this.dueAt,
  });

  final String type;
  final String productLabel;
  final DateTime scheduledAt;
  final DateTime dueAt;
}
