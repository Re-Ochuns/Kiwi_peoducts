import 'dart:typed_data';

enum LabelJobStatus { notPrinted, partiallyPrinted, printed, handwritten }

class LabelJob {
  const LabelJob({
    required this.id,
    required this.containerId,
    required this.containerDisplayId,
    required this.status,
    required this.requiredCopies,
    required this.printedCopies,
    required this.reprintCount,
    required this.originName,
    required this.varietyName,
    required this.gradeCode,
    required this.weightHundredths,
    required this.sortedOn,
    required this.workerName,
  });

  final String id;
  final String containerId;
  final String containerDisplayId;
  final LabelJobStatus status;
  final int requiredCopies;
  final int printedCopies;
  final int reprintCount;
  final String originName;
  final String varietyName;
  final String gradeCode;
  final int weightHundredths;
  final DateTime sortedOn;
  final String workerName;

  bool get isPending =>
      status == LabelJobStatus.notPrinted ||
      status == LabelJobStatus.partiallyPrinted;

  bool get canReprint => status == LabelJobStatus.printed;

  int get remainingCopies =>
      (requiredCopies - printedCopies).clamp(1, requiredCopies).toInt();

  String get statusLabel => switch (status) {
    LabelJobStatus.notPrinted => '未印刷',
    LabelJobStatus.partiallyPrinted => '一部印刷',
    LabelJobStatus.printed => '印刷済み',
    LabelJobStatus.handwritten => '手書き対応済み',
  };
}

class LabelOption {
  const LabelOption({required this.id, required this.label});

  final String id;
  final String label;
}

class LabelCursor {
  const LabelCursor({required this.createdAt, required this.id});
  final String createdAt;
  final String id;
}

class LabelLoadData {
  const LabelLoadData({
    required this.jobs,
    required this.workers,
    required this.locations,
    this.nextCursor,
  });

  final List<LabelJob> jobs;
  final List<LabelOption> workers;
  final List<LabelOption> locations;
  final LabelCursor? nextCursor;
}

class LabelPdf {
  const LabelPdf({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

class LabelActionResult {
  const LabelActionResult({
    required this.labelJobId,
    required this.status,
    required this.printedCopies,
    required this.requiredCopies,
    required this.reprintCount,
  });

  final String labelJobId;
  final LabelJobStatus status;
  final int printedCopies;
  final int requiredCopies;
  final int reprintCount;
}

class LabelFailure implements Exception {
  const LabelFailure({
    required this.message,
    this.code,
    this.field,
    this.correlationId,
    this.retryable = false,
    this.current,
  });

  final String message;
  final String? code;
  final String? field;
  final String? correlationId;
  final bool retryable;
  final Map<String, dynamic>? current;

  bool get isConflict =>
      code == 'CONFLICT_STALE' || code == 'LABEL_NOT_REPRINTABLE';
}

abstract interface class LabelRepository {
  Future<LabelLoadData> load({bool completed = false, LabelCursor? after});

  Future<LabelPdf> fetchPdf({required String containerId});

  Future<LabelActionResult> markPrinted({
    required String labelJobId,
    required String workerId,
    required int copies,
    required String idempotencyKey,
    String? locationId,
  });

  Future<LabelActionResult> markHandwritten({
    required String labelJobId,
    required String workerId,
    required String idempotencyKey,
    String? notes,
    String? locationId,
  });

  Future<LabelActionResult> reprint({
    required String labelJobId,
    required String workerId,
    required String reason,
    required int copies,
    required String idempotencyKey,
  });
}

String formatLabelWeight(int hundredths) =>
    (hundredths / 100).toStringAsFixed(2);
