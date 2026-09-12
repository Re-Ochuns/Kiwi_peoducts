import 'package:kiwi_inventory/work_tasks/work_task_repository.dart';

class FakeWorkTaskRepository implements WorkTaskRepository {
  FakeWorkTaskRepository({
    List<WorkTaskItem>? tasks,
    this.loadFailures = 0,
    this.syncWarnings = const WorkTaskSyncWarnings.empty(),
  }) : tasks = tasks ?? testWorkTasks;

  final List<WorkTaskItem> tasks;
  int loadFailures;
  int loadCalls = 0;
  int loadTaskCalls = 0;
  final WorkTaskSyncWarnings syncWarnings;

  @override
  Future<List<WorkTaskItem>> loadTasks() async {
    loadCalls++;
    if (loadFailures > 0) {
      loadFailures--;
      throw const WorkTaskFailure(
        message: 'ToDoを読み込めませんでした。',
        code: 'NETWORK_FAILED',
        retryable: true,
      );
    }
    return tasks;
  }

  @override
  Future<WorkTaskItem?> loadTask(String taskId) async {
    loadTaskCalls++;
    return tasks.cast<WorkTaskItem?>().firstWhere(
      (task) => task?.id == taskId,
      orElse: () => null,
    );
  }

  @override
  Future<WorkTaskSyncWarnings> loadSyncWarnings() async => syncWarnings;
}

final testWorkTasks = [
  WorkTaskItem(
    id: 'task-overdue',
    type: WorkTaskType.ethyleneInjection,
    targetId: 'ripening-1',
    targetDisplayId: '追熟-2026-001',
    scheduledAt: DateTime(2026, 9, 12, 9),
    dueAt: DateTime(2026, 9, 12, 10),
    status: 'pending',
    targetUrl: '/work-tasks/task-overdue',
    variety: 'ヘイワード',
    grade: 'M',
    weightHundredths: 2050,
    location: '第1追熟庫',
  ),
  WorkTaskItem(
    id: 'task-today',
    type: WorkTaskType.labelPrinting,
    targetId: 'label-1',
    targetDisplayId: '選果-2026-0148-1',
    scheduledAt: DateTime(2026, 9, 12, 14),
    dueAt: DateTime(2026, 9, 12, 15),
    status: 'pending',
    targetUrl: '/work-tasks/task-today',
    variety: '香緑',
    grade: 'M',
    weightHundredths: 980,
    location: '第二冷蔵庫',
  ),
  WorkTaskItem(
    id: 'task-upcoming',
    type: WorkTaskType.ripenessCheck,
    targetId: 'ripening-2',
    targetDisplayId: '追熟-2026-002',
    scheduledAt: DateTime(2026, 9, 13, 9),
    dueAt: DateTime(2026, 9, 13, 10),
    status: 'pending',
    targetUrl: '/work-tasks/task-upcoming',
    variety: 'ヘイワード',
    grade: 'L',
    weightHundredths: 1840,
    location: '第2追熟庫',
  ),
];
