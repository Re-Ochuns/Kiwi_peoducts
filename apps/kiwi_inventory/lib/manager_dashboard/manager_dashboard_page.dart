import 'package:flutter/material.dart';

import '../core/common_state_view.dart';
import '../orders/order_management_repository.dart';
import '../work_tasks/work_task_repository.dart';
import 'manager_dashboard_repository.dart';

class ManagerDashboardPage extends StatefulWidget {
  const ManagerDashboardPage({
    required this.repository,
    this.currentDate,
    required this.onOpenTask,
    required this.onOpenOrder,
    super.key,
  });

  final ManagerDashboardRepository repository;
  final DateTime? currentDate;
  final ValueChanged<WorkTaskItem> onOpenTask;
  final ValueChanged<OrderItem> onOpenOrder;

  @override
  State<ManagerDashboardPage> createState() => ManagerDashboardPageState();
}

class ManagerDashboardPageState extends State<ManagerDashboardPage> {
  final _priorityKey = GlobalKey();
  final _todayKey = GlobalKey();
  final _upcomingKey = GlobalKey();
  ManagerDashboardData? _data;
  ManagerDashboardFailure? _failure;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final data = await widget.repository.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on ManagerDashboardFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const CommonStateView.loading(title: '予定と警告を読み込んでいます');
    }
    final failure = _failure;
    if (failure != null && _data == null) {
      return CommonStateView.error(
        title: failure.isPermissionDenied ? 'ホームを表示できません' : '予定と警告を読み込めませんでした',
        message: failure.message,
        actionLabel: failure.retryable ? '再試行' : null,
        onAction: failure.retryable ? refresh : null,
      );
    }

    final data = _data!;
    final now = widget.currentDate ?? DateTime.now();
    final today = data.todayTasks(now);
    final upcoming = data.upcomingTasks(now);
    final overdue = data.overdueTasks(now);
    final shortages = data.shortageOrders;
    final syncFailed = data.syncFailedTasks;
    final scheduleWarnings = data.scheduleWarningTasks;

    return RefreshIndicator(
      onRefresh: refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 30, 32, 48),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ホーム',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatDate(now),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF56605A),
                  ),
                ),
                if (failure != null) ...[
                  const SizedBox(height: 18),
                  _ReloadFailureNotice(
                    message: failure.message,
                    onRetry: failure.retryable ? refresh : null,
                  ),
                ],
                const SizedBox(height: 28),
                _SummaryStrip(
                  items: [
                    _SummaryItem(
                      'ToDo',
                      today.length,
                      () => _scrollTo(_todayKey),
                    ),
                    _SummaryItem(
                      '要確認',
                      data.attentionCount(now),
                      () => _scrollTo(_priorityKey),
                    ),
                    _SummaryItem(
                      '7日以内の予定',
                      upcoming.length,
                      () => _scrollTo(_upcomingKey),
                    ),
                    _SummaryItem(
                      '予約不足',
                      shortages.length,
                      () => _scrollTo(_priorityKey),
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                _SectionTitle(key: _priorityKey, label: '優先して確認'),
                const SizedBox(height: 10),
                _PriorityList(
                  overdue: overdue,
                  shortages: shortages,
                  syncFailed: syncFailed,
                  scheduleWarnings: scheduleWarnings,
                  overdueSyncCount: data.syncWarnings.overdueSyncCount,
                  onOpenTask: widget.onOpenTask,
                  onOpenOrder: widget.onOpenOrder,
                ),
                const SizedBox(height: 34),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final todaySection = _ScheduleSection(
                      key: _todayKey,
                      title: 'ToDo',
                      emptyMessage: '本日の予定はありません',
                      tasks: today,
                      showTime: true,
                      onOpen: widget.onOpenTask,
                    );
                    final upcomingSection = _ScheduleSection(
                      key: _upcomingKey,
                      title: '今後7日',
                      emptyMessage: '7日以内の追熟・出荷予定はありません',
                      tasks: upcoming,
                      showTime: false,
                      onOpen: widget.onOpenTask,
                    );
                    if (constraints.maxWidth >= 760) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: todaySection),
                          const SizedBox(width: 32),
                          Expanded(child: upcomingSection),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        todaySection,
                        const SizedBox(height: 32),
                        upcomingSection,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target, duration: Duration.zero);
    }
  }
}

class _ReloadFailureNotice extends StatelessWidget {
  const _ReloadFailureNotice({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFB42318)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        Expanded(child: Text(message)),
        if (onRetry != null) ...[
          const SizedBox(width: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('再試行')),
        ],
      ],
    ),
  );
}

class _SummaryItem {
  const _SummaryItem(this.label, this.count, this.onTap);
  final String label;
  final int count;
  final VoidCallback onTap;
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.items});
  final List<_SummaryItem> items;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(
        top: BorderSide(color: Color(0xFFCBD1CD)),
        bottom: BorderSide(color: Color(0xFFCBD1CD)),
      ),
    ),
    child: Row(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          Expanded(child: _SummaryButton(item: items[index])),
          if (index < items.length - 1)
            const SizedBox(height: 62, child: VerticalDivider(width: 1)),
        ],
      ],
    ),
  );
}

class _SummaryButton extends StatelessWidget {
  const _SummaryButton({required this.item});
  final _SummaryItem item;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${item.label}${item.count}件の一覧を見る',
    button: true,
    excludeSemantics: true,
    child: InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF56605A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.count}件',
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const ExcludeSemantics(
              child: Text('→', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label, super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
  );
}

class _PriorityList extends StatelessWidget {
  const _PriorityList({
    required this.overdue,
    required this.shortages,
    required this.syncFailed,
    required this.scheduleWarnings,
    required this.overdueSyncCount,
    required this.onOpenTask,
    required this.onOpenOrder,
  });

  final List<WorkTaskItem> overdue;
  final List<OrderItem> shortages;
  final List<WorkTaskItem> syncFailed;
  final List<WorkTaskItem> scheduleWarnings;
  final int overdueSyncCount;
  final ValueChanged<WorkTaskItem> onOpenTask;
  final ValueChanged<OrderItem> onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final overdueIds = overdue.map((task) => task.id).toSet();
    final syncRows = syncFailed.where((task) => !overdueIds.contains(task.id));
    final shownIds = {...overdueIds, ...syncRows.map((task) => task.id)};
    final warningRows = scheduleWarnings.where(
      (task) => !shownIds.contains(task.id),
    );
    if (overdue.isEmpty &&
        shortages.isEmpty &&
        syncRows.isEmpty &&
        warningRows.isEmpty &&
        overdueSyncCount == 0) {
      return const _EmptyLine('確認が必要な項目はありません');
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFCBD1CD))),
      ),
      child: Column(
        children: [
          for (final task in overdue)
            _TaskAlertRow(
              task: task,
              title: '${task.type.label}の期限を超過しています',
              status: '期限超過',
              tone: _AlertTone.error,
              onTap: () => onOpenTask(task),
            ),
          for (final order in shortages)
            _OrderAlertRow(order: order, onTap: () => onOpenOrder(order)),
          for (final task in syncRows)
            _TaskAlertRow(
              task: task,
              title: 'Googleカレンダーへ予定を同期できませんでした',
              status: '同期失敗',
              tone: _AlertTone.error,
              onTap: () => onOpenTask(task),
            ),
          for (final task in warningRows)
            _TaskAlertRow(
              task: task,
              title: '予定日時を確認してください',
              status: '要確認',
              tone: _AlertTone.warning,
              onTap: () => onOpenTask(task),
            ),
          if (overdueSyncCount > 0)
            _InformationRow(
              text:
                  'Googleカレンダーの再試行が遅れている予定が$overdueSyncCount件あります。対象予定は自動で再試行されます。',
            ),
        ],
      ),
    );
  }
}

enum _AlertTone { error, warning }

class _TaskAlertRow extends StatelessWidget {
  const _TaskAlertRow({
    required this.task,
    required this.title,
    required this.status,
    required this.tone,
    required this.onTap,
  });
  final WorkTaskItem task;
  final String title;
  final String status;
  final _AlertTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _LinkedRow(
    semanticsLabel: '${task.targetDisplayId}の詳細を見る',
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            _StatusLabel(label: status, tone: tone),
          ],
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            Text(
              task.targetDisplayId,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(task.productLabel),
            if (task.weightHundredths != null)
              Text(formatWorkTaskWeight(task.weightHundredths!)),
            Text('期限 ${_formatDateTime(task.dueAt)}'),
          ],
        ),
      ],
    ),
  );
}

class _OrderAlertRow extends StatelessWidget {
  const _OrderAlertRow({required this.order, required this.onTap});
  final OrderItem order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _LinkedRow(
    semanticsLabel: '${order.number}の詳細を見る',
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                '予約量が不足しています',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            _StatusLabel(label: '予約不足', tone: _AlertTone.error),
          ],
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            Text(
              order.number,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(order.customerDisplayName),
            Text(
              '不足 ${order.shortageWeight.toStringAsFixed(2)} kg',
              style: const TextStyle(
                color: Color(0xFFB42318),
                fontWeight: FontWeight.w700,
              ),
            ),
            Text('出荷予定 ${_formatShortDate(order.scheduledShipOn)}'),
          ],
        ),
      ],
    ),
  );
}

class _LinkedRow extends StatelessWidget {
  const _LinkedRow({
    required this.semanticsLabel,
    required this.onTap,
    required this.child,
  });
  final String semanticsLabel;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    button: true,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 84),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFCBD1CD))),
        ),
        child: Row(
          children: [
            Expanded(child: child),
            const SizedBox(width: 14),
            const ExcludeSemantics(
              child: Text('→', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.label, required this.tone});
  final String label;
  final _AlertTone tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: tone == _AlertTone.error
          ? const Color(0xFFFFE9E7)
          : const Color(0xFFFFF1C7),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: tone == _AlertTone.error
            ? const Color(0xFF8F1D14)
            : const Color(0xFF704E00),
      ),
    ),
  );
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFCBD1CD))),
    ),
    child: Text(text),
  );
}

class _ScheduleSection extends StatelessWidget {
  const _ScheduleSection({
    required this.title,
    required this.emptyMessage,
    required this.tasks,
    required this.showTime,
    required this.onOpen,
    super.key,
  });
  final String title;
  final String emptyMessage;
  final List<WorkTaskItem> tasks;
  final bool showTime;
  final ValueChanged<WorkTaskItem> onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: _SectionTitle(label: title)),
          Text(
            '${tasks.length}件',
            style: const TextStyle(color: Color(0xFF56605A)),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (tasks.isEmpty)
        _EmptyLine(emptyMessage)
      else
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFCBD1CD))),
          ),
          child: Column(
            children: [
              for (final task in tasks)
                _LinkedRow(
                  semanticsLabel: '${task.targetDisplayId}の詳細を見る',
                  onTap: () => onOpen(task),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 78,
                        child: Text(
                          showTime
                              ? _formatTime(task.scheduledAt)
                              : _formatShortDate(task.scheduledAt),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.type.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              task.targetDisplayId,
                              style: const TextStyle(color: Color(0xFF56605A)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 18),
    decoration: const BoxDecoration(
      border: Border(
        top: BorderSide(color: Color(0xFFCBD1CD)),
        bottom: BorderSide(color: Color(0xFFCBD1CD)),
      ),
    ),
    child: Text(text, style: const TextStyle(color: Color(0xFF56605A))),
  );
}

String _formatDate(DateTime value) =>
    '${value.year}年${value.month}月${value.day}日';
String _formatShortDate(DateTime value) => '${value.month}月${value.day}日';
String _formatTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _formatDateTime(DateTime value) =>
    '${_formatShortDate(value)} ${_formatTime(value)}';
