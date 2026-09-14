import '../process_board/process_board_repository.dart';

class BoardOrderOption {
  const BoardOrderOption(this.id, this.label);
  final String id;
  final String label;
}

class BoardOrderOptions {
  const BoardOrderOptions({
    required this.varieties,
    required this.grades,
    required this.customers,
    required this.locations,
    required this.workers,
  });
  final List<BoardOrderOption> varieties, grades, customers, locations, workers;
}

class BoardOrderCriteria {
  const BoardOrderCriteria({
    required this.shipDate,
    required this.varietyId,
    required this.gradeId,
    required this.weightHundredths,
  });
  final String shipDate, varietyId, gradeId;
  final int weightHundredths;
  Map<String, Object?> toJson() => {
    'scheduled_ship_date': shipDate,
    'variety_id': varietyId,
    'grade_id': gradeId,
    'ordered_weight_kg': weightHundredths / 100,
  };
}

class BoardOrderCandidate {
  const BoardOrderCandidate({
    required this.id,
    required this.kind,
    required this.displayId,
    required this.stage,
    required this.availableHundredths,
    required this.start,
    required this.completion,
    required this.version,
    required this.containerIds,
    this.locationId,
    this.useType,
  });
  final String id, kind, displayId, version, containerIds;
  final ProcessStage stage;
  final int availableHundredths;
  final DateTime start, completion;
  final String? locationId;
  final ProcessUseType? useType;
  String get key => '$kind:$id';
  ProcessBoardItem item(String variety, String grade) => ProcessBoardItem(
    id: key,
    displayId: displayId,
    stage: stage,
    useType:
        useType ??
        (kind == 'lot' ? ProcessUseType.reserve : ProcessUseType.unassigned),
    variety: variety,
    grade: grade,
    weightHundredths: availableHundredths,
    status: stage.name,
    location: '',
    needsReview: false,
    orderIds: const [],
    orderNumbers: const [],
    date: completion,
  );
}

class BoardOrderDraft {
  String? customerId, destinationId, locationId, workerId;
}

class BoardOrderResult {
  const BoardOrderResult(this.orderNumber, this.planNumber, this.existingPlan);
  final String orderNumber, planNumber;
  final bool existingPlan;
}

class BoardOrderFailure implements Exception {
  const BoardOrderFailure(
    this.message, {
    this.code = '',
    this.uncertain = false,
  });
  final String message, code;
  final bool uncertain;
}

abstract interface class BoardOrderRepository {
  Future<BoardOrderOptions> loadOptions();
  Future<List<BoardOrderOption>> destinations(String customerId);
  Future<List<BoardOrderCandidate>> candidates(BoardOrderCriteria criteria);
  Future<BoardOrderResult> confirm(Map<String, Object?> input, String key);
}
