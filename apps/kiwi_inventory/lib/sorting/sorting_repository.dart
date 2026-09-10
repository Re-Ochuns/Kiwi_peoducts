class SortingLot {
  const SortingLot({
    required this.id,
    required this.displayId,
    required this.sourceType,
    required this.receivedOn,
    required this.originName,
    required this.varietyName,
    required this.totalWeightHundredths,
    required this.sortingDueOn,
    required this.version,
  });

  final String id;
  final String displayId;
  final String sourceType;
  final DateTime receivedOn;
  final String originName;
  final String varietyName;
  final int totalWeightHundredths;
  final DateTime sortingDueOn;
  final int version;

  double get totalWeightKg => totalWeightHundredths / 100;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return displayId.toLowerCase().contains(normalized) ||
        varietyName.toLowerCase().contains(normalized) ||
        originName.toLowerCase().contains(normalized);
  }
}

class SortingGrade {
  const SortingGrade({
    required this.id,
    required this.code,
    required this.displayOrder,
  });

  final String id;
  final String code;
  final int displayOrder;
}

class SortingWorker {
  const SortingWorker({
    required this.id,
    required this.code,
    required this.displayName,
  });

  final String id;
  final String code;
  final String displayName;

  String get label => '$code　$displayName';
}

class SortingLoadData {
  const SortingLoadData({
    required this.lots,
    required this.grades,
    required this.workers,
  });

  final List<SortingLot> lots;
  final List<SortingGrade> grades;
  final List<SortingWorker> workers;
}

class SortingContainerInput {
  const SortingContainerInput({
    required this.gradeId,
    required this.weightHundredths,
  });

  final String gradeId;
  final int weightHundredths;

  Map<String, Object> toJson() => {
    'grade_id': gradeId,
    'weight_kg': weightHundredths / 100,
  };
}

class SortingInput {
  const SortingInput({
    required this.receivingLotId,
    required this.sortingDate,
    required this.workerId,
    required this.expectedLotVersion,
    required this.containers,
  });

  final String receivingLotId;
  final String sortingDate;
  final String workerId;
  final int expectedLotVersion;
  final List<SortingContainerInput> containers;

  Map<String, Object> toRpcInput() => {
    'receiving_lot_id': receivingLotId,
    'sorting_date': sortingDate,
    'worker_id': workerId,
    'expected_lot_version': expectedLotVersion,
    'containers': containers.map((container) => container.toJson()).toList(),
  };

  String get signature => toRpcInput().toString();
}

class SortingResultContainer {
  const SortingResultContainer({
    required this.containerId,
    required this.displayId,
    required this.gradeId,
    required this.weightHundredths,
  });

  final String containerId;
  final String displayId;
  final String gradeId;
  final int weightHundredths;
}

class SortingResult {
  const SortingResult({
    required this.sortingResultId,
    required this.displayId,
    required this.inputWeightHundredths,
    required this.outputWeightHundredths,
    required this.lossWeightHundredths,
    required this.containers,
    required this.idempotentReplay,
  });

  final String sortingResultId;
  final String displayId;
  final int inputWeightHundredths;
  final int outputWeightHundredths;
  final int lossWeightHundredths;
  final List<SortingResultContainer> containers;
  final bool idempotentReplay;
}

class SortingFailure implements Exception {
  const SortingFailure({
    required this.message,
    this.code,
    this.field,
    this.reason,
    this.correlationId,
    this.retryable = false,
    this.current,
  });

  final String message;
  final String? code;
  final String? field;
  final String? reason;
  final String? correlationId;
  final bool retryable;
  final Map<String, dynamic>? current;

  bool get isConflict => code == 'CONFLICT_STALE';
}

abstract interface class SortingRepository {
  Future<SortingLoadData> load();

  Future<SortingResult> confirm({
    required SortingInput input,
    required String idempotencyKey,
  });
}

const maxWeightHundredths = 999999999999;

int? parseWeightHundredths(String raw) {
  final value = raw.trim();
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final whole = int.tryParse(parts[0]);
  final fraction = parts.length == 1
      ? 0
      : int.tryParse(parts[1].padRight(2, '0'));
  if (whole == null || fraction == null) return null;
  if (whole > maxWeightHundredths ~/ 100) return null;
  final hundredths = whole * 100 + fraction;
  return hundredths <= maxWeightHundredths ? hundredths : null;
}

String formatWeight(int hundredths) => (hundredths / 100).toStringAsFixed(2);
