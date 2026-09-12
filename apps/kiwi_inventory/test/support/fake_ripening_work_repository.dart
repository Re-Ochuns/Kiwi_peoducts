import 'package:kiwi_inventory/ripening/ripening_work_repository.dart';
import 'package:kiwi_inventory/work_tasks/work_task_repository.dart';

class FakeRipeningWorkRepository implements RipeningWorkRepository {
  FakeRipeningWorkRepository({
    this.type = WorkTaskType.ethyleneInjection,
    this.canComplete = true,
    this.status = 'pending',
  });
  final WorkTaskType type;
  final bool canComplete;
  final String status;
  Future<void>? pendingSave;
  int calls = 0;
  final keys = <String>[];
  final inputs = <RipeningWorkInput>[];
  RipeningWorkFailure? failure;
  RipeningWorkFailure? loadFailure;

  WorkTaskItem get task => WorkTaskItem(
    id: 'task-1',
    type: type,
    targetId: 'plan-1',
    targetDisplayId: 'RIP-2026-0001',
    scheduledAt: DateTime(2026, 9, 13, 9),
    dueAt: DateTime(2026, 9, 13, 10),
    status: status,
    targetUrl: '/work-tasks/task-1',
    variety: 'ヘイワード',
    grade: 'L',
    weightHundredths: 2500,
    location: '第1追熟庫',
    assignedWorkerId: 'worker-1',
  );
  @override
  Future<RipeningWorkDetail> load(String taskId) async {
    if (loadFailure != null) throw loadFailure!;
    return RipeningWorkDetail(
      task: task,
      version: 1,
      workers: const [RipeningWorker('worker-1', '確認担当者')],
      canComplete: canComplete,
      plannedTemperature: 20,
    );
  }

  @override
  Future<void> complete(
    RipeningWorkDetail detail,
    RipeningWorkInput input, {
    required String idempotencyKey,
  }) async {
    calls++;
    keys.add(idempotencyKey);
    inputs.add(input);
    if (pendingSave != null) await pendingSave;
    if (failure != null) throw failure!;
  }
}
