import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_task_repository.dart';

class SupabaseWorkTaskRepository implements WorkTaskRepository {
  SupabaseWorkTaskRepository(this._client);

  factory SupabaseWorkTaskRepository.fromInitializedClient() =>
      SupabaseWorkTaskRepository(Supabase.instance.client);

  final SupabaseClient _client;

  @override
  Future<List<WorkTaskItem>> loadTasks() async {
    try {
      const pageSize = 200;
      final tasks = <WorkTaskItem>[];
      for (var offset = 0; ; offset += pageSize) {
        final raw = await _client
            .rpc('work_task_list')
            .eq('status', 'pending')
            .order('due_at', ascending: true)
            .order('id', ascending: true)
            .range(offset, offset + pageSize - 1)
            .timeout(const Duration(seconds: 10));
        final rows = [
          for (final value in raw as List)
            Map<String, dynamic>.from(value as Map),
        ];
        // Resolve targets per page to keep IN filters within URL size limits.
        final labels = await _loadTargetLabels(rows);
        tasks.addAll(rows.map((row) => _taskFromRow(row, labels)));
        if (rows.length < pageSize) return tasks;
      }
    } on TimeoutException {
      throw const WorkTaskFailure(
        message: 'ToDoを読み込めませんでした。時間をおいて再試行してください。',
        code: 'TIMEOUT',
        retryable: true,
      );
    } on WorkTaskFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _failureForPostgrest(error);
    } catch (_) {
      throw const WorkTaskFailure(
        message: 'ToDoを読み込めませんでした。通信状況を確認してください。',
        code: 'NETWORK_FAILED',
        retryable: true,
      );
    }
  }

  @override
  Future<WorkTaskItem?> loadTask(String taskId) async {
    try {
      final raw = await _client
          .rpc('work_task_get', params: {'task_id_value': taskId})
          .timeout(const Duration(seconds: 10));
      if (raw == null) return null;
      final row = Map<String, dynamic>.from(raw as Map);
      final labels = await _loadTargetLabels([row]);
      return _taskFromRow(row, labels);
    } on TimeoutException {
      throw const WorkTaskFailure(
        message: '作業を読み込めませんでした。時間をおいて再試行してください。',
        code: 'TIMEOUT',
        retryable: true,
      );
    } on WorkTaskFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _failureForPostgrest(error);
    } catch (_) {
      throw const WorkTaskFailure(
        message: '作業を読み込めませんでした。通信状況を確認してください。',
        code: 'NETWORK_FAILED',
        retryable: true,
      );
    }
  }

  Future<Map<String, String>> _loadTargetLabels(
    List<Map<String, dynamic>> rows,
  ) async {
    final receivingIds = _ids(rows, 'receiving_lot_id');
    final labelIds = _ids(rows, 'label_job_id');
    final ripeningIds = _ids(rows, 'ripening_lot_id');
    final orderIds = _ids(rows, 'order_id');

    final results = await Future.wait<List<dynamic>>([
      _loadRows('receiving_lots', 'id, display_id', receivingIds),
      _loadRows('label_jobs', 'id, container_id', labelIds),
      _loadRows('ripening_lots', 'id, display_id', ripeningIds),
      _loadRows('orders', 'id, order_number', orderIds),
    ]).timeout(const Duration(seconds: 10));

    final labels = <String, String>{};
    _addLabels(labels, results[0], 'display_id');
    _addLabels(labels, results[2], 'display_id');
    _addLabels(labels, results[3], 'order_number');

    final labelJobs = [
      for (final value in results[1]) Map<String, dynamic>.from(value as Map),
    ];
    final containerIds = labelJobs
        .map((row) => row['container_id'])
        .whereType<String>()
        .toSet()
        .toList();
    final containers = await _loadRows(
      'containers',
      'id, display_id',
      containerIds,
    ).timeout(const Duration(seconds: 10));
    final containerLabels = <String, String>{};
    _addLabels(containerLabels, containers, 'display_id');
    for (final row in labelJobs) {
      final id = row['id'] as String?;
      final containerId = row['container_id'] as String?;
      final displayId = containerId == null
          ? null
          : containerLabels[containerId];
      if (id != null && displayId != null) labels[id] = displayId;
    }
    return labels;
  }

  Future<List<dynamic>> _loadRows(
    String table,
    String columns,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const [];
    return await _client.from(table).select(columns).inFilter('id', ids)
        as List<dynamic>;
  }
}

List<String> _ids(List<Map<String, dynamic>> rows, String key) => rows
    .map((row) => row[key])
    .whereType<String>()
    .toSet()
    .toList(growable: false);

void _addLabels(
  Map<String, String> labels,
  List<dynamic> rows,
  String labelKey,
) {
  for (final value in rows) {
    final row = Map<String, dynamic>.from(value as Map);
    final id = row['id'] as String?;
    final label = row[labelKey] as String?;
    if (id != null && label != null && label.trim().isNotEmpty) {
      labels[id] = label;
    }
  }
}

WorkTaskItem _taskFromRow(
  Map<String, dynamic> row,
  Map<String, String> targetLabels,
) {
  final details = row['task_details'] is Map
      ? Map<String, dynamic>.from(row['task_details'] as Map)
      : const <String, dynamic>{};
  final targetId = _targetId(row);
  final fallback = targetId.length > 8 ? targetId.substring(0, 8) : targetId;
  return WorkTaskItem(
    id: row['id'] as String,
    type: WorkTaskType.fromValue(row['task_type'] as String? ?? ''),
    targetId: targetId,
    targetDisplayId: targetLabels[targetId] ?? '作業-$fallback',
    scheduledAt: DateTime.parse(row['scheduled_at'] as String).toLocal(),
    dueAt: DateTime.parse(row['due_at'] as String).toLocal(),
    status: row['status'] as String,
    targetUrl: row['target_url'] as String,
    variety: details['variety'] as String?,
    grade: details['grade'] as String?,
    weightHundredths: _toHundredths(details['weight_kg']),
    location: details['location'] as String?,
    assignedWorkerId: row['assigned_worker_id'] as String?,
    scheduleWarning: row['schedule_warning'] as String?,
  );
}

String _targetId(Map<String, dynamic> row) =>
    row['receiving_lot_id'] as String? ??
    row['label_job_id'] as String? ??
    row['ripening_lot_id'] as String? ??
    row['order_id'] as String? ??
    row['id'] as String;

int? _toHundredths(Object? value) {
  if (value == null) return null;
  final number = value is num ? value : num.tryParse(value.toString());
  return number == null ? null : (number * 100).round();
}

WorkTaskFailure _failureForPostgrest(PostgrestException error) {
  if (error.code == '42501') {
    return const WorkTaskFailure(
      message: 'ToDoを表示する権限がありません。管理者へ確認してください。',
      code: 'AUTH_FORBIDDEN',
    );
  }
  if (error.code == 'PGRST202') {
    return WorkTaskFailure(
      message: 'ToDo機能の構成が一致していません。管理者へ連絡してください。',
      code: error.code,
    );
  }
  return WorkTaskFailure(
    message: 'ToDoを読み込めませんでした。通信状況を確認してください。',
    code: error.code,
    retryable: true,
  );
}
