import 'package:kiwi_inventory/process_board/process_board_repository.dart';
import 'package:kiwi_inventory/work_tasks/work_task_repository.dart';

class FakeProcessBoardRepository implements ProcessBoardRepository {
  FakeProcessBoardRepository({ProcessBoardData? data, this.loadFailures = 0})
    : data = data ?? testProcessBoardData;

  ProcessBoardData data;
  int loadFailures;
  int loadCalls = 0;

  @override
  Future<ProcessBoardData> load() async {
    loadCalls++;
    if (loadFailures > 0) {
      loadFailures--;
      throw const ProcessBoardFailure(
        message: '工程ボードを読み込めませんでした。',
        code: 'NETWORK_FAILED',
        retryable: true,
      );
    }
    return data;
  }
}

final testProcessBoardData = ProcessBoardData(
  items: [
    ProcessBoardItem(
      id: 'container-sorted',
      displayId: 'CONT-2026-0101',
      stage: ProcessStage.sorted,
      useType: ProcessUseType.unassigned,
      variety: 'ヘイワード',
      grade: 'M',
      weightHundredths: 1825,
      status: 'cold_storage',
      location: 'cold-01　第一冷蔵庫',
      needsReview: false,
      orderIds: const [],
      orderNumbers: const [],
    ),
    ProcessBoardItem(
      id: 'container-ripening',
      displayId: 'CONT-2026-0102',
      stage: ProcessStage.ripening,
      useType: ProcessUseType.order,
      variety: '香緑',
      grade: 'L',
      weightHundredths: 2050,
      status: 'ethylene_processing',
      location: 'ripening-01　第1追熟庫',
      needsReview: false,
      date: DateTime(2026, 9, 18, 10),
      ripeningLotId: 'ripening-1',
      ripeningDisplayId: 'RIP-2026-0031',
      orderIds: const ['order-1'],
      orderNumbers: const ['ORD-2026-0081'],
      nextTask: WorkTaskItem(
        id: 'task-removal',
        type: WorkTaskType.ethyleneRemovalCheck,
        targetId: 'ripening-1',
        targetDisplayId: 'RIP-2026-0031',
        scheduledAt: DateTime(2026, 9, 18, 10),
        dueAt: DateTime(2026, 9, 18, 11),
        status: 'pending',
        targetUrl: '/work-tasks/task-removal',
      ),
    ),
    ProcessBoardItem(
      id: 'container-resting',
      displayId: 'CONT-2026-0103',
      stage: ProcessStage.resting,
      useType: ProcessUseType.reserve,
      variety: 'ヘイワード',
      grade: 'S',
      weightHundredths: 1240,
      status: 'resting',
      location: 'ripening-02　第2追熟庫',
      needsReview: false,
      date: DateTime(2026, 9, 19, 14),
      ripeningLotId: 'ripening-2',
      ripeningDisplayId: 'RIP-2026-0032',
      orderIds: const [],
      orderNumbers: const [],
    ),
    ProcessBoardItem(
      id: 'container-shippable',
      displayId: 'CONT-2026-0104',
      stage: ProcessStage.shippable,
      useType: ProcessUseType.mixed,
      variety: 'レインボーレッド',
      grade: 'M',
      weightHundredths: 1575,
      status: 'shippable',
      location: 'shipping-01　出荷待機場所',
      needsReview: false,
      date: DateTime(2026, 9, 20),
      ripeningLotId: 'ripening-3',
      ripeningDisplayId: 'RIP-2026-0033',
      orderIds: const ['order-1'],
      orderNumbers: const ['ORD-2026-0081'],
    ),
  ],
);
