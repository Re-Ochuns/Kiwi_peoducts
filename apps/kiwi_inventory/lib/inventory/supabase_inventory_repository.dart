import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'inventory_repository.dart';

class SupabaseInventoryRepository implements InventoryRepository {
  SupabaseInventoryRepository(this._client);

  factory SupabaseInventoryRepository.fromInitializedClient() =>
      SupabaseInventoryRepository(Supabase.instance.client);

  final SupabaseClient _client;

  static const _itemColumns = '''
    id, display_id, original_weight_kg, current_weight_kg,
    reserved_weight_kg, status, updated_at,
    variety:varieties!containers_variety_id_fkey(name),
    grade:grades!containers_grade_id_fkey(code),
    location:storage_locations!containers_location_id_fkey(code, name)
  ''';

  @override
  Future<InventoryPageData> loadPage(InventoryQuery query) async {
    try {
      var request = _client.from('containers').select(_itemColumns);
      final search = query.search.trim();
      if (search.isNotEmpty) {
        request = request.ilike('display_id', '%$search%');
      }
      if (query.status != null) {
        request = request.eq('status', query.status!.value);
      }

      final sortedRequest = switch (query.sort) {
        InventorySort.updatedDescending =>
          request.order('updated_at', ascending: false).order('display_id'),
        InventorySort.displayIdAscending =>
          request.order('display_id').order('id'),
        InventorySort.currentWeightDescending =>
          request
              .order('current_weight_kg', ascending: false)
              .order('display_id'),
      };

      final start = query.page * query.pageSize;
      final response = await sortedRequest
          .range(start, start + query.pageSize - 1)
          .count(CountOption.exact)
          .timeout(const Duration(seconds: 10));
      final rows = response.data;
      return InventoryPageData(
        items: [
          for (final value in rows)
            _itemFromRow(Map<String, dynamic>.from(value as Map)),
        ],
        totalCount: response.count,
        page: query.page,
        pageSize: query.pageSize,
      );
    } on TimeoutException {
      throw const InventoryFailure(
        message: '在庫一覧の読み込みがタイムアウトしました。',
        code: 'TIMEOUT',
        retryable: true,
      );
    } on InventoryFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw inventoryFailureForPostgrestCode(error.code);
    } catch (_) {
      throw const InventoryFailure(
        message: '在庫一覧を読み込めませんでした。通信状況を確認してください。',
        code: 'NETWORK_FAILED',
        retryable: true,
      );
    }
  }

  @override
  Future<InventoryDetailData> loadDetail(String containerId) async {
    try {
      final results = await Future.wait<dynamic>([
        _loadDetailRow(containerId),
        _loadCanViewHistory(),
      ]).timeout(const Duration(seconds: 10));

      final row = Map<String, dynamic>.from(results[0] as Map);
      final canViewHistory = results[1] as bool;
      final history = canViewHistory
          ? await _loadHistory(containerId).timeout(const Duration(seconds: 10))
          : const <InventoryHistoryEntry>[];
      return InventoryDetailData(
        item: _itemFromRow(row),
        source: _sourceFromRow(row),
        history: history,
        canViewHistory: canViewHistory,
      );
    } on TimeoutException {
      throw const InventoryFailure(
        message: '在庫詳細の読み込みがタイムアウトしました。',
        code: 'TIMEOUT',
        retryable: true,
      );
    } on InventoryFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw inventoryFailureForPostgrestCode(error.code, detail: true);
    } catch (_) {
      throw const InventoryFailure(
        message: '在庫詳細を読み込めませんでした。通信状況を確認してください。',
        code: 'NETWORK_FAILED',
        retryable: true,
      );
    }
  }

  Future<Map<String, dynamic>> _loadDetailRow(String containerId) async {
    final row = await _client
        .from('containers')
        .select('''
          $_itemColumns,
          sorting_result:sorting_results!containers_sorting_result_id_fkey(
            display_id, sorted_on,
            worker:workers!sorting_results_sorted_by_fkey(display_name),
            receiving_lot:receiving_lots!sorting_results_receiving_lot_id_fkey(
              display_id, received_on, source_type, origin_name
            )
          )
        ''')
        .eq('id', containerId)
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<bool> _loadCanViewHistory() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final rows = await _client
        .from('user_roles')
        .select('role')
        .eq('user_id', userId);
    return (rows as List).any(
      (value) => (value as Map)['role'] == 'administrator',
    );
  }

  Future<List<InventoryHistoryEntry>> _loadHistory(String containerId) async {
    final rows = await _client
        .from('change_history')
        .select('''
          operation, reason, changed_at,
          profile:profiles!change_history_changed_by_fkey(display_name)
        ''')
        .eq('entity_type', 'container')
        .eq('entity_id', containerId)
        .order('changed_at', ascending: false);
    return [
      for (final value in rows as List)
        _historyFromRow(Map<String, dynamic>.from(value as Map)),
    ];
  }

  InventoryItem _itemFromRow(Map<String, dynamic> row) {
    final variety = Map<String, dynamic>.from(row['variety'] as Map);
    final grade = Map<String, dynamic>.from(row['grade'] as Map);
    final location = row['location'] is Map
        ? Map<String, dynamic>.from(row['location'] as Map)
        : null;
    return InventoryItem(
      id: row['id'] as String,
      displayId: row['display_id'] as String,
      varietyName: variety['name'] as String,
      gradeCode: grade['code'] as String,
      originalWeightHundredths: _toHundredths(row['original_weight_kg']),
      currentWeightHundredths: _toHundredths(row['current_weight_kg']),
      reservedWeightHundredths: _toHundredths(row['reserved_weight_kg']),
      status: InventoryStatus.fromValue(row['status'] as String),
      locationCode: location?['code'] as String?,
      locationName: location?['name'] as String?,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  InventorySource _sourceFromRow(Map<String, dynamic> row) {
    final sorting = Map<String, dynamic>.from(row['sorting_result'] as Map);
    final worker = Map<String, dynamic>.from(sorting['worker'] as Map);
    final receiving = Map<String, dynamic>.from(
      sorting['receiving_lot'] as Map,
    );
    return InventorySource(
      sortingDisplayId: sorting['display_id'] as String,
      sortedOn: DateTime.parse(sorting['sorted_on'] as String),
      sortingWorkerName: worker['display_name'] as String,
      receivingDisplayId: receiving['display_id'] as String,
      receivedOn: DateTime.parse(receiving['received_on'] as String),
      sourceType: receiving['source_type'] as String,
      originName: receiving['origin_name'] as String,
    );
  }

  InventoryHistoryEntry _historyFromRow(Map<String, dynamic> row) {
    final profile = row['profile'] as Map<String, dynamic>?;
    return InventoryHistoryEntry(
      operation: row['operation'] as String,
      reason: row['reason'] as String,
      changedAt: DateTime.parse(row['changed_at'] as String),
      changedBy: profile?['display_name'] as String? ?? 'システム（自動更新）',
    );
  }
}

int _toHundredths(dynamic value) => ((value as num).toDouble() * 100).round();

InventoryFailure inventoryFailureForPostgrestCode(
  String? errorCode, {
  bool detail = false,
}) {
  if (const {'401', 'PGRST301', 'PGRST302', 'PGRST303'}.contains(errorCode)) {
    return const InventoryFailure(
      message: 'セッションの有効期限が切れています。再ログインしてください。',
      code: 'AUTH_REQUIRED',
    );
  }
  if (const {'403', '42501'}.contains(errorCode)) {
    return const InventoryFailure(
      message: '在庫情報を確認する権限がありません。',
      code: 'AUTH_FORBIDDEN',
    );
  }
  if (errorCode == 'PGRST116') {
    return const InventoryFailure(
      message: '指定した在庫は見つかりませんでした。',
      code: 'NOT_FOUND',
    );
  }
  return InventoryFailure(
    message: detail
        ? '在庫詳細を読み込めませんでした。通信状況を確認してください。'
        : '在庫一覧を読み込めませんでした。通信状況を確認してください。',
    code: 'UNEXPECTED',
    retryable: true,
  );
}
