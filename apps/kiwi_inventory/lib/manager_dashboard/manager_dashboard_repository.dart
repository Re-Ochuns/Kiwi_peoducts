import '../orders/order_management_repository.dart';
import '../work_tasks/work_task_repository.dart';

class ManagerDashboardData {
  const ManagerDashboardData({
    required this.tasks,
    required this.orders,
    required this.syncWarnings,
  });

  final List<WorkTaskItem> tasks;
  final OrderManagementData orders;
  final WorkTaskSyncWarnings syncWarnings;

  List<WorkTaskItem> overdueTasks(DateTime now) => _sortedTasks(
    tasks.where((task) => task.isPending && task.dueAt.isBefore(now)),
  );

  List<WorkTaskItem> todayTasks(DateTime now) {
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return _sortedTasks(
      tasks.where(
        (task) =>
            task.isPending &&
            !task.scheduledAt.isBefore(start) &&
            task.scheduledAt.isBefore(end),
      ),
      bySchedule: true,
    );
  }

  List<WorkTaskItem> upcomingTasks(DateTime now) {
    final start = DateTime(now.year, now.month, now.day + 1);
    final end = start.add(const Duration(days: 7));
    return _sortedTasks(
      tasks.where(
        (task) =>
            task.isPending &&
            !task.scheduledAt.isBefore(start) &&
            task.scheduledAt.isBefore(end) &&
            _isRipeningOrShipping(task.type),
      ),
      bySchedule: true,
    );
  }

  List<WorkTaskItem> get syncFailedTasks => _sortedTasks(
    tasks.where(
      (task) => task.isPending && task.calendarSyncStatus == 'failed',
    ),
  );

  List<WorkTaskItem> get scheduleWarningTasks => _sortedTasks(
    tasks.where(
      (task) => task.isPending && task.scheduleWarning?.isNotEmpty == true,
    ),
  );

  List<OrderItem> get shortageOrders =>
      orders.orders.where((order) => order.shortageWeight > 0).toList()
        ..sort((left, right) {
          final byDate = left.scheduledShipOn.compareTo(right.scheduledShipOn);
          return byDate != 0 ? byDate : left.number.compareTo(right.number);
        });

  int attentionCount(DateTime now) {
    final taskIds = <String>{
      ...overdueTasks(now).map((task) => task.id),
      ...syncFailedTasks.map((task) => task.id),
      ...scheduleWarningTasks.map((task) => task.id),
    };
    return taskIds.length +
        shortageOrders.length +
        syncWarnings.overdueSyncCount;
  }
}

abstract interface class ManagerDashboardRepository {
  Future<ManagerDashboardData> load();
}

class DefaultManagerDashboardRepository implements ManagerDashboardRepository {
  const DefaultManagerDashboardRepository({
    required this.workTaskRepository,
    required this.orderManagementRepository,
  });

  final WorkTaskRepository workTaskRepository;
  final OrderManagementRepository orderManagementRepository;

  @override
  Future<ManagerDashboardData> load() async {
    try {
      final results = await Future.wait<Object>([
        workTaskRepository.loadTasks(),
        workTaskRepository.loadSyncWarnings(),
        orderManagementRepository.load(filter: OrderListFilter.active),
      ]);
      return ManagerDashboardData(
        tasks: results[0] as List<WorkTaskItem>,
        syncWarnings: results[1] as WorkTaskSyncWarnings,
        orders: results[2] as OrderManagementData,
      );
    } on WorkTaskFailure catch (failure) {
      throw ManagerDashboardFailure(
        message: failure.message,
        retryable: failure.retryable,
        isPermissionDenied: failure.isPermissionDenied,
      );
    } on OrderManagementFailure catch (failure) {
      throw ManagerDashboardFailure(
        message: failure.message,
        retryable: failure.retryable,
        isPermissionDenied: failure.isPermissionDenied,
      );
    } catch (_) {
      throw const ManagerDashboardFailure(
        message: '予定と警告を読み込めませんでした。通信状況を確認してください。',
        retryable: true,
      );
    }
  }
}

class ManagerDashboardFailure implements Exception {
  const ManagerDashboardFailure({
    required this.message,
    this.retryable = false,
    this.isPermissionDenied = false,
  });

  final String message;
  final bool retryable;
  final bool isPermissionDenied;
}

List<WorkTaskItem> _sortedTasks(
  Iterable<WorkTaskItem> tasks, {
  bool bySchedule = false,
}) {
  final result = tasks.toList();
  result.sort((left, right) {
    final byDate = (bySchedule ? left.scheduledAt : left.dueAt).compareTo(
      bySchedule ? right.scheduledAt : right.dueAt,
    );
    return byDate != 0 ? byDate : left.id.compareTo(right.id);
  });
  return result;
}

bool _isRipeningOrShipping(WorkTaskType type) => switch (type) {
  WorkTaskType.ethyleneInjection ||
  WorkTaskType.ethyleneRemovalCheck ||
  WorkTaskType.ripenessCheck ||
  WorkTaskType.shipping => true,
  _ => false,
};
