import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'ripening_work_repository.dart';

class SupabaseRipeningWorkRepository implements RipeningWorkRepository {
  SupabaseRipeningWorkRepository(this._client);

  factory SupabaseRipeningWorkRepository.fromInitializedClient() =>
      SupabaseRipeningWorkRepository(Supabase.instance.client);

  final SupabaseClient _client;

  @override
  Future<RipeningWorkDetails> load(String ripeningLotId) async {
    try {
      final values = await Future.wait<dynamic>([
        _client.rpc(
          'ripening_work_get',
          params: {'ripening_lot_id_value': ripeningLotId},
        ),
        _client
            .from('storage_locations')
            .select('id, code, name')
            .eq('is_active', true)
            .order('code'),
        _client
            .from('workers')
            .select('id, code, display_name')
            .eq('is_active', true)
            .order('code'),
      ]).timeout(const Duration(seconds: 10));
      if (values[0] == null) {
        throw const RipeningWorkFailure(
          message: '追熟計画が見つかりません。ToDoを更新してください。',
          code: 'NOT_FOUND',
        );
      }
      final row = Map<String, dynamic>.from(values[0] as Map);
      return RipeningWorkDetails(
        id: row['id'] as String,
        displayId: row['display_id'] as String,
        version: (row['version'] as num).toInt(),
        status: row['status'] as String,
        weightHundredths: _toHundredths(row['total_weight_kg']),
        locationId: row['storage_location_id'] as String,
        workerId: row['assigned_worker_id'] as String,
        plannedEthyleneAt: DateTime.parse(row['planned_ethylene_at'] as String)
            .toLocal(),
        plannedCompletionAt: DateTime.parse(
          row['planned_completion_at'] as String,
        ).toLocal(),
        results: [
          for (final raw in row['results'] as List? ?? const [])
            RipeningWorkRecord(
              type: (raw as Map)['work_type'] as String,
              actualAt: DateTime.parse(raw['actual_at'] as String).toLocal(),
              restStartedAt: raw['rest_started_at'] == null
                  ? null
                  : DateTime.parse(raw['rest_started_at'] as String).toLocal(),
            ),
        ],
        locations: _options(values[1], nameKey: 'name'),
        workers: _options(values[2], nameKey: 'display_name'),
      );
    } on TimeoutException {
      throw const RipeningWorkFailure(
        message: '追熟作業を読み込めませんでした。時間をおいて再試行してください。',
        code: 'TIMEOUT',
        retryable: true,
      );
    } on RipeningWorkFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _postgrestFailure(error);
    } catch (_) {
      throw const RipeningWorkFailure(
        message: '追熟作業を読み込めませんでした。通信状況を確認してください。',
        code: 'NETWORK_FAILED',
        retryable: true,
      );
    }
  }

  @override
  Future<RipeningWorkCompletion> complete({
    required RipeningWorkType type,
    required RipeningWorkInput input,
    required String idempotencyKey,
  }) async {
    RipeningWorkFailure? lastFailure;
    for (var attempt = 0; attempt < 3; attempt++) {
      final correlationId = createRipeningWorkIdempotencyKey();
      try {
        final raw = await _client
            .rpc(
              type.rpcName,
              params: {
                'req': {
                  'meta': {
                    'idempotency_key': idempotencyKey,
                    'correlation_id': correlationId,
                  },
                  'input': input.toRpcInput(type),
                },
              },
            )
            .timeout(const Duration(seconds: 10));
        final response = Map<String, dynamic>.from(raw as Map);
        if (response['ok'] == true) {
          final data = Map<String, dynamic>.from(response['data'] as Map);
          final results = [
            for (final value in data['results'] as List? ?? const [])
              Map<String, dynamic>.from(value as Map),
          ];
          final recorded = results.lastWhere(
            (result) => result['work_type'] == type.value,
          );
          return RipeningWorkCompletion(
            displayId: data['display_id'] as String,
            version: (data['version'] as num).toInt(),
            status: data['status'] as String,
            actualAt: DateTime.parse(recorded['actual_at'] as String).toLocal(),
            idempotentReplay: response['idempotent_replay'] == true,
          );
        }
        final error = Map<String, dynamic>.from(response['error'] as Map);
        final details = error['details'] is Map
            ? Map<String, dynamic>.from(error['details'] as Map)
            : const <String, dynamic>{};
        final failure = RipeningWorkFailure(
          message: error['message'] as String? ?? '追熟作業を完了できませんでした。',
          code: error['code'] as String?,
          field: details['field'] as String?,
          correlationId: response['correlation_id'] as String?,
          retryable: error['retryable'] == true,
        );
        if (!failure.retryable) throw failure;
        lastFailure = failure;
      } on RipeningWorkFailure catch (failure) {
        if (!failure.retryable) rethrow;
        lastFailure = failure;
      } on TimeoutException {
        lastFailure = RipeningWorkFailure(
          message: '完了結果を確認できませんでした。自動で再確認します。',
          code: 'TIMEOUT',
          correlationId: correlationId,
          retryable: true,
        );
      } on PostgrestException catch (error) {
        if (error.code == 'PGRST202') {
          throw RipeningWorkFailure(
            message: '追熟作業機能の構成が一致していません。管理者へ連絡してください。',
            code: error.code,
            correlationId: correlationId,
          );
        }
        final failure = _postgrestFailure(error);
        if (failure.isPermissionDenied) throw failure;
        lastFailure = RipeningWorkFailure(
          message: '追熟作業の完了処理へ接続できませんでした。自動で再確認します。',
          code: error.code,
          correlationId: correlationId,
          retryable: true,
        );
      } catch (_) {
        lastFailure = RipeningWorkFailure(
          message: '通信に失敗しました。自動で再確認します。',
          code: 'NETWORK_FAILED',
          correlationId: correlationId,
          retryable: true,
        );
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(seconds: attempt + 1));
      }
    }
    throw lastFailure ??
        const RipeningWorkFailure(
          message: '追熟作業の完了結果を確認できませんでした。',
          retryable: true,
        );
  }
}

List<RipeningWorkOption> _options(dynamic rows, {required String nameKey}) => [
  for (final raw in rows as List)
    RipeningWorkOption(
      id: (raw as Map)['id'] as String,
      label: '${raw['code']}　${raw[nameKey]}',
    ),
];

int _toHundredths(Object? value) =>
    (((value as num?)?.toDouble() ?? 0) * 100).round();

RipeningWorkFailure _postgrestFailure(PostgrestException error) {
  if (const {'401', 'PGRST301', 'PGRST302', 'PGRST303'}.contains(error.code)) {
    return const RipeningWorkFailure(
      message: 'セッションの有効期限が切れています。再ログインしてください。',
      code: 'AUTH_REQUIRED',
    );
  }
  if (const {'403', '42501'}.contains(error.code)) {
    return const RipeningWorkFailure(
      message: '追熟作業を確認する権限がありません。',
      code: 'AUTH_FORBIDDEN',
    );
  }
  return RipeningWorkFailure(
    message: '追熟作業を読み込めませんでした。通信状況を確認してください。',
    code: error.code,
    retryable: true,
  );
}
