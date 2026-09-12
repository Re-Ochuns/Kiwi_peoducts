import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'work_task_repository.dart';

typedef WorkTaskTargetPageBuilder = Widget? Function(WorkTaskItem task);

class WorkerTodoSections extends StatefulWidget {
  const WorkerTodoSections({
    required this.repository,
    required this.onOpenTask,
    this.currentDate,
    super.key,
  });

  final WorkTaskRepository repository;
  final ValueChanged<WorkTaskItem> onOpenTask;
  final DateTime? currentDate;

  @override
  State<WorkerTodoSections> createState() => WorkerTodoSectionsState();
}

class WorkerTodoSectionsState extends State<WorkerTodoSections> {
  late Future<List<WorkTaskItem>> _tasks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WorkerTodoSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) _load();
  }

  void _load() {
    _tasks = widget.repository.loadTasks();
  }

  Future<void> refresh() async {
    setState(_load);
    try {
      await _tasks;
    } catch (_) {
      /* FutureBuilder displays the failure. */
    }
  }

  void _retry() {
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WorkTaskItem>>(
      future: _tasks,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _InlineState(
            key: Key('todo-loading'),
            message: 'ToDoを読み込んでいます',
            loading: true,
          );
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          return _InlineState(
            key: const Key('todo-error'),
            message: error is WorkTaskFailure
                ? error.message
                : 'ToDoを読み込めませんでした。通信状況を確認してください。',
            actionLabel: '再試行',
            onAction: _retry,
          );
        }

        final groups = WorkTaskGroups.fromTasks(
          snapshot.data ?? const [],
          now: widget.currentDate ?? DateTime.now(),
        );
        if (groups.isEmpty) {
          return const _InlineState(
            key: Key('todo-empty'),
            message: '予定されている作業はありません',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (groups.overdue.isNotEmpty) ...[
              _TaskSection(
                title: '期限超過',
                tasks: groups.overdue,
                tone: _TaskTone.error,
                onOpenTask: widget.onOpenTask,
              ),
              const SizedBox(height: 28),
            ],
            if (groups.today.isNotEmpty) ...[
              _TaskSection(
                title: '本日の予定',
                tasks: groups.today,
                tone: _TaskTone.progress,
                onOpenTask: widget.onOpenTask,
              ),
              const SizedBox(height: 28),
            ],
            if (groups.upcoming.isNotEmpty)
              _TaskSection(
                title: '今後の作業',
                tasks: groups.upcoming,
                tone: _TaskTone.neutral,
                onOpenTask: widget.onOpenTask,
              ),
          ],
        );
      },
    );
  }
}

class _TaskSection extends StatelessWidget {
  const _TaskSection({
    required this.title,
    required this.tasks,
    required this.tone,
    required this.onOpenTask,
  });

  final String title;
  final List<WorkTaskItem> tasks;
  final _TaskTone tone;
  final ValueChanged<WorkTaskItem> onOpenTask;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${tasks.length}件',
              style: const TextStyle(fontSize: 14, color: AppColors.mutedText),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Column(
            children: [
              for (final task in tasks)
                _WorkTaskRow(
                  task: task,
                  tone: tone,
                  onTap: () => onOpenTask(task),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkTaskRow extends StatelessWidget {
  const _WorkTaskRow({
    required this.task,
    required this.tone,
    required this.onTap,
  });

  final WorkTaskItem task;
  final _TaskTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final warning = task.scheduleWarning;
    return Semantics(
      label: '${task.targetDisplayId}の${task.type.label}を確認する',
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 106),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            task.type.label,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _TaskStatusLabel(tone: tone),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      task.targetDisplayId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 12,
                      runSpacing: 3,
                      children: [
                        Text(
                          task.productLabel,
                          style: const TextStyle(fontSize: 14),
                        ),
                        if (task.weightHundredths != null)
                          Text(
                            formatWorkTaskWeight(task.weightHundredths!),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '予定 ${_formatDateTime(task.scheduledAt)}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      '期限 ${_formatDateTime(task.dueAt)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: tone == _TaskTone.error
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: tone == _TaskTone.error
                            ? AppColors.error
                            : AppColors.mutedText,
                      ),
                    ),
                    if (task.location?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(
                        '場所 ${task.location}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.mutedText,
                        ),
                      ),
                    ],
                    if (warning?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 5),
                      Text(
                        '要確認：${_warningLabel(warning!)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const ExcludeSemantics(
                child: Text(
                  '→',
                  style: TextStyle(fontSize: 20, color: Color(0xFF35413A)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TaskTone { error, progress, neutral }

class _TaskStatusLabel extends StatelessWidget {
  const _TaskStatusLabel({required this.tone});

  final _TaskTone tone;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = switch (tone) {
      _TaskTone.error => (
        '期限超過',
        const Color(0xFFFFE9E7),
        const Color(0xFF8D1C16),
      ),
      _TaskTone.progress => (
        '本日',
        const Color(0xFFE7F0FA),
        const Color(0xFF174D7D),
      ),
      _TaskTone.neutral => (
        '今後',
        const Color(0xFFEDF0EE),
        const Color(0xFF3F4943),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class WorkTaskDetailPage extends StatelessWidget {
  const WorkTaskDetailPage({
    required this.task,
    this.onOpenTarget,
    this.currentDate,
    this.backLabel = '← ToDoへ戻る',
    this.showCalendarSyncStatus = false,
    super.key,
  });

  final WorkTaskItem task;
  final VoidCallback? onOpenTarget;
  final DateTime? currentDate;
  final String backLabel;
  final bool showCalendarSyncStatus;

  @override
  Widget build(BuildContext context) {
    final overdue =
        task.isPending && task.dueAt.isBefore(currentDate ?? DateTime.now());
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 8,
        title: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.green,
            minimumSize: const Size(48, 48),
          ),
          child: Text(backLabel, style: const TextStyle(fontSize: 16)),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 48),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '作業確認',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    task.type.label,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '対象ID',
                    style: TextStyle(fontSize: 14, color: AppColors.mutedText),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    task.targetDisplayId,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(height: 1),
                  if (task.weightHundredths != null)
                    _DetailValue(
                      label: '重量',
                      value: formatWorkTaskWeight(task.weightHundredths!),
                      prominent: true,
                    ),
                  _DetailValue(label: '品種・等級', value: task.productLabel),
                  if (showCalendarSyncStatus)
                    _DetailValue(
                      label: '作業状態',
                      value: _workTaskStatusLabel(task.status),
                      error: task.status == 'cancelled',
                    ),
                  _DetailValue(
                    label: '予定',
                    value: _formatDateTime(task.scheduledAt),
                  ),
                  _DetailValue(
                    label: overdue ? '期限超過' : '期限',
                    value: _formatDateTime(task.dueAt),
                    error: overdue,
                  ),
                  if (task.location?.trim().isNotEmpty == true)
                    _DetailValue(label: '場所', value: task.location!),
                  if (task.scheduleWarning?.trim().isNotEmpty == true)
                    _DetailValue(
                      label: '要確認',
                      value: _warningLabel(task.scheduleWarning!),
                      error: true,
                    ),
                  if (showCalendarSyncStatus &&
                      task.calendarSyncStatus != 'not_required')
                    _DetailValue(
                      label: 'Googleカレンダー',
                      value: _calendarSyncLabel(task.calendarSyncStatus),
                      error: task.calendarSyncStatus == 'failed',
                    ),
                  if (onOpenTarget != null) ...[
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: onOpenTarget,
                      child: Text('${task.type.label}へ進む'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _calendarSyncLabel(String status) => switch (status) {
  'pending' => '同期待ち',
  'synced' => '同期済み',
  'failed' => '同期失敗・自動再試行',
  _ => '同期対象外',
};

String _workTaskStatusLabel(String status) => switch (status) {
  'pending' => '未完了',
  'completed' => '完了',
  'cancelled' => '中止',
  _ => '要確認',
};

class WorkTaskRoutePage extends StatefulWidget {
  const WorkTaskRoutePage({
    required this.repository,
    required this.taskId,
    required this.targetPageBuilder,
    this.currentDate,
    super.key,
  });

  final WorkTaskRepository repository;
  final String taskId;
  final WorkTaskTargetPageBuilder targetPageBuilder;
  final DateTime? currentDate;

  @override
  State<WorkTaskRoutePage> createState() => _WorkTaskRoutePageState();
}

class _WorkTaskRoutePageState extends State<WorkTaskRoutePage> {
  late Future<WorkTaskItem?> _task;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _task = widget.repository.loadTask(widget.taskId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorkTaskItem?>(
      future: _task,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: SafeArea(
              child: _InlineState(message: '作業を読み込んでいます', loading: true),
            ),
          );
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          return Scaffold(
            body: SafeArea(
              child: _InlineState(
                message: error is WorkTaskFailure
                    ? error.message
                    : '作業を読み込めませんでした。通信状況を確認してください。',
                actionLabel: '再試行',
                onAction: () => setState(_load),
              ),
            ),
          );
        }
        final task = snapshot.data;
        if (task == null || !task.isPending) {
          return Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('← ToDoへ戻る'),
              ),
            ),
            body: const SafeArea(
              child: _InlineState(message: 'この作業は完了または中止されています'),
            ),
          );
        }
        final targetPage = widget.targetPageBuilder(task);
        return WorkTaskDetailPage(
          task: task,
          currentDate: widget.currentDate,
          onOpenTarget: targetPage == null
              ? null
              : () => Navigator.of(context).push(
                  PageRouteBuilder<void>(
                    pageBuilder: (_, _, _) => targetPage,
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                ),
        );
      },
    );
  }
}

class _DetailValue extends StatelessWidget {
  const _DetailValue({
    required this.label,
    required this.value,
    this.prominent = false,
    this.error = false,
  });

  final String label;
  final String value;
  final bool prominent;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: error ? AppColors.error : AppColors.mutedText,
              fontWeight: error ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: prominent ? 24 : 16,
              fontWeight: prominent || error
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: error ? AppColors.error : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineState extends StatelessWidget {
  const _InlineState({
    required this.message,
    this.loading = false,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: loading || onAction != null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (loading) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Text(message, style: const TextStyle(fontSize: 16)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

String? workTaskIdFromRoute(String? routeName) {
  if (routeName == null) return null;
  final match = RegExp(r'^/work-tasks/([^/?#]+)$').firstMatch(routeName);
  return match == null ? null : Uri.decodeComponent(match.group(1)!);
}

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.month}月${value.day}日 ${two(value.hour)}:${two(value.minute)}';
}

String _warningLabel(String warning) => switch (warning) {
  'COMPLETION_BEFORE_REMOVAL' => '追熟完了予定がエチレン抜き確認より前です',
  _ => warning,
};

// DB links use a path; Flutter Web otherwise only reads the hash at startup.
// Retain hash links used by OAuth and existing browser navigation as well.
String? workTaskInitialRoute(Uri uri) {
  final route = uri.fragment.startsWith('/') ? uri.fragment : uri.path;
  return workTaskIdFromRoute(route) == null ? null : route;
}
