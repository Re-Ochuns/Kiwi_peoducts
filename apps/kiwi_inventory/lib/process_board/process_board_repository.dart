import '../work_tasks/work_task_repository.dart';

enum ProcessStage {
  sorted('選果済み', '保管期限'),
  ripening('追熟', '終了予定'),
  resting('寝かせ', '終了予定'),
  shippable('出荷可能', '出荷日時');

  const ProcessStage(this.label, this.dateLabel);

  final String label;
  final String dateLabel;
}

enum ProcessUseType {
  unassigned('用途未確定', ''),
  reserve('予備', '○'),
  order('受注', '●'),
  mixed('複合', '⊙');

  const ProcessUseType(this.label, this.symbol);

  final String label;
  final String symbol;

  factory ProcessUseType.fromValue(String? value) => switch (value) {
    'reserve' => ProcessUseType.reserve,
    'order' => ProcessUseType.order,
    'mixed' => ProcessUseType.mixed,
    _ => ProcessUseType.unassigned,
  };
}

class ProcessBoardItem {
  const ProcessBoardItem({
    required this.id,
    required this.displayId,
    required this.stage,
    required this.useType,
    required this.variety,
    required this.grade,
    required this.weightHundredths,
    required this.status,
    required this.location,
    required this.needsReview,
    required this.orderIds,
    required this.orderNumbers,
    this.date,
    this.ripeningLotId,
    this.ripeningDisplayId,
    this.nextTask,
    this.plans = const [],
    this.inventoryBalance,
  });

  final String id;
  final String displayId;
  final ProcessStage stage;
  final ProcessUseType useType;
  final String variety;
  final String grade;
  final int weightHundredths;
  final String status;
  final String location;
  final bool needsReview;
  final DateTime? date;
  final String? ripeningLotId;
  final String? ripeningDisplayId;
  final List<String> orderIds;
  final List<String> orderNumbers;
  final WorkTaskItem? nextTask;

  final List<ProcessBoardPlan> plans;
  final ProcessBoardInventoryBalance? inventoryBalance;

  ProcessBoardItem forPlan(String? planId) {
    if (plans.isEmpty) return this;
    final plan =
        plans.where((plan) => plan.id == planId).firstOrNull ?? plans.first;
    return ProcessBoardItem(
      id: id,
      displayId: displayId,
      stage: stage,
      useType: plan.useType,
      variety: variety,
      grade: grade,
      weightHundredths: weightHundredths,
      status: status,
      location: location,
      needsReview: needsReview,
      date: date,
      ripeningLotId: plan.id,
      ripeningDisplayId: plan.displayId,
      orderIds: plan.orderIds,
      orderNumbers: plan.orderNumbers,
      nextTask: plan.nextTask,
      plans: plans,
      inventoryBalance: inventoryBalance,
    );
  }

  String get productLabel => '$variety・$grade';
}

class ProcessBoardPlan {
  const ProcessBoardPlan({
    required this.id,
    required this.displayId,
    required this.useType,
    required this.orderIds,
    required this.orderNumbers,
    this.nextTask,
  });

  final String id;
  final String displayId;
  final ProcessUseType useType;
  final List<String> orderIds;
  final List<String> orderNumbers;
  final WorkTaskItem? nextTask;
}

class ProcessBoardInventoryBalance {
  const ProcessBoardInventoryBalance({
    required this.totalHundredths,
    required this.orderHundredths,
    required this.containerDisplayIds,
    required this.isLot,
  });

  final int totalHundredths;
  final int orderHundredths;
  final List<String> containerDisplayIds;
  final bool isLot;
}

class ProcessBoardData {
  const ProcessBoardData({required this.items, this.inventoryItems});

  final List<ProcessBoardItem> items;
  final List<ProcessBoardItem>? inventoryItems;

  List<ProcessBoardItem> itemsFor(ProcessStage stage) =>
      items.where((item) => item.stage == stage).toList(growable: false);

  int weightFor(ProcessStage stage) =>
      itemsFor(stage).fold(0, (total, item) => total + item.weightHundredths);
}

class ProcessBoardFailure implements Exception {
  const ProcessBoardFailure({
    required this.message,
    this.code,
    this.retryable = false,
  });

  final String message;
  final String? code;
  final bool retryable;
}

abstract interface class ProcessBoardRepository {
  Future<ProcessBoardData> load();
}

String formatProcessBoardWeight(int hundredths) =>
    '${(hundredths / 100).toStringAsFixed(2)} kg';
