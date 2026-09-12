import '../work_tasks/work_task_repository.dart';

/// Frontend boundary for Issue #61. The production adapter awaits Issue #62's
/// reviewed RPC contract; this interface does not prescribe database fields.
abstract interface class RipeningWorkRepository {
  Future<RipeningWorkDetail> load(String taskId);
  Future<void> complete(
    RipeningWorkDetail detail,
    RipeningWorkInput input, {
    required String idempotencyKey,
  });
}

class RipeningWorker {
  const RipeningWorker(this.id, this.name);
  final String id;
  final String name;
}

class RipeningWorkDetail {
  const RipeningWorkDetail({
    required this.task,
    required this.version,
    required this.workers,
    required this.canComplete,
    this.plannedTemperature,
  });
  final WorkTaskItem task;
  final int version;
  final List<RipeningWorker> workers;
  final bool canComplete;
  final double? plannedTemperature;
}

class RipeningWorkInput {
  const RipeningWorkInput({
    required this.actualAt,
    required this.temperature,
    required this.workerId,
    required this.notes,
    required this.checked,
  });
  final DateTime actualAt;
  final double temperature;
  final String workerId;
  final String notes;
  final bool checked;
}

class RipeningWorkFailure implements Exception {
  const RipeningWorkFailure(this.message, {this.retryable = false});
  final String message;
  // A retry must use the same input and idempotency key after an ambiguous
  // transport failure. Non-retryable failures require fresh server state.
  final bool retryable;
}

bool isRipeningWork(WorkTaskType type) => switch (type) {
  WorkTaskType.ethyleneInjection ||
  WorkTaskType.ethyleneRemovalCheck ||
  WorkTaskType.ripenessCheck => true,
  _ => false,
};
