enum WorkTaskType {
  sorting,
  labelPrinting,
  ethyleneInjection,
  ethyleneRemovalCheck,
  ripenessCheck,
  shipping,
  unknown;

  factory WorkTaskType.fromValue(String value) => switch (value) {
    'sorting' => WorkTaskType.sorting,
    'label' => WorkTaskType.labelPrinting,
    'ethylene_injection' => WorkTaskType.ethyleneInjection,
    'ethylene_removal_check' => WorkTaskType.ethyleneRemovalCheck,
    'ripeness_check' => WorkTaskType.ripenessCheck,
    'shipping' => WorkTaskType.shipping,
    _ => WorkTaskType.unknown,
  };

  String get label => switch (this) {
    WorkTaskType.sorting => '選果登録',
    WorkTaskType.labelPrinting => 'ラベル対応',
    WorkTaskType.ethyleneInjection => 'エチレン注入',
    WorkTaskType.ethyleneRemovalCheck => 'エチレン抜き確認',
    WorkTaskType.ripenessCheck => '追熟確認',
    WorkTaskType.shipping => '出荷確認',
    WorkTaskType.unknown => '作業確認',
  };
}

class WorkTaskItem {
  const WorkTaskItem({
    required this.id,
    required this.type,
    required this.targetId,
    required this.targetDisplayId,
    required this.scheduledAt,
    required this.dueAt,
    required this.status,
    required this.targetUrl,
    this.variety,
    this.grade,
    this.weightHundredths,
    this.location,
    this.assignedWorkerId,
    this.scheduleWarning,
  });

  final String id;
  final WorkTaskType type;
  final String targetId;
  final String targetDisplayId;
  final DateTime scheduledAt;
  final DateTime dueAt;
  final String status;
  final String targetUrl;
  final String? variety;
  final String? grade;
  final int? weightHundredths;
  final String? location;
  final String? assignedWorkerId;
  final String? scheduleWarning;

  bool get isPending => status == 'pending';

  String get productLabel {
    final values = [
      variety,
      grade,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
    return values.isEmpty ? '品種・等級未設定' : values.join('・');
  }
}

class WorkTaskGroups {
  const WorkTaskGroups({
    required this.overdue,
    required this.today,
    required this.upcoming,
  });

  factory WorkTaskGroups.fromTasks(
    Iterable<WorkTaskItem> tasks, {
    required DateTime now,
  }) {
    final overdue = <WorkTaskItem>[];
    final today = <WorkTaskItem>[];
    final upcoming = <WorkTaskItem>[];
    final endOfToday = DateTime(now.year, now.month, now.day + 1);

    for (final task in tasks.where((task) => task.isPending)) {
      if (task.dueAt.isBefore(now)) {
        overdue.add(task);
      } else if (task.scheduledAt.isBefore(endOfToday)) {
        today.add(task);
      } else {
        upcoming.add(task);
      }
    }

    int compare(WorkTaskItem left, WorkTaskItem right) {
      final byDue = left.dueAt.compareTo(right.dueAt);
      return byDue != 0 ? byDue : left.id.compareTo(right.id);
    }

    overdue.sort(compare);
    today.sort((left, right) {
      final bySchedule = left.scheduledAt.compareTo(right.scheduledAt);
      return bySchedule != 0 ? bySchedule : compare(left, right);
    });
    upcoming.sort((left, right) {
      final bySchedule = left.scheduledAt.compareTo(right.scheduledAt);
      return bySchedule != 0 ? bySchedule : compare(left, right);
    });
    return WorkTaskGroups(overdue: overdue, today: today, upcoming: upcoming);
  }

  final List<WorkTaskItem> overdue;
  final List<WorkTaskItem> today;
  final List<WorkTaskItem> upcoming;

  bool get isEmpty => overdue.isEmpty && today.isEmpty && upcoming.isEmpty;
}

class WorkTaskFailure implements Exception {
  const WorkTaskFailure({
    required this.message,
    this.code,
    this.retryable = false,
  });

  final String message;
  final String? code;
  final bool retryable;

  bool get isPermissionDenied =>
      code == 'AUTH_REQUIRED' || code == 'AUTH_FORBIDDEN';
}

abstract interface class WorkTaskRepository {
  Future<List<WorkTaskItem>> loadTasks();

  Future<WorkTaskItem?> loadTask(String taskId);
}

String formatWorkTaskWeight(int hundredths) =>
    '${(hundredths / 100).toStringAsFixed(2)} kg';
