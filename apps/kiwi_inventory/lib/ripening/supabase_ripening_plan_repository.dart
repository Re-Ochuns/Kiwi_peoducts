import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'ripening_plan_repository.dart';

class SupabaseRipeningPlanRepository implements RipeningPlanRepository {
  SupabaseRipeningPlanRepository(this._client);

  factory SupabaseRipeningPlanRepository.fromInitializedClient() =>
      SupabaseRipeningPlanRepository(Supabase.instance.client);

  final SupabaseClient _client;

  @override
  Future<RipeningPlanOptions> loadOptions() async {
    try {
      final results = await Future.wait<dynamic>([
        _client.rpc('ripening_inventory_available'),
        _client.rpc('order_list'),
        _client
            .from('varieties')
            .select('id, code, name')
            .eq('is_active', true),
        _client.from('grades').select('id, code').eq('is_active', true),
        _client
            .from('storage_locations')
            .select('id, code, name')
            .eq('is_active', true),
        _client
            .from('workers')
            .select('id, code, display_name')
            .eq('is_active', true),
      ]).timeout(const Duration(seconds: 10));

      final varieties = _labels(results[2], nameKey: 'name');
      final grades = _labels(results[3], nameKey: 'code', includeCode: false);
      final inventories = <RipeningInventoryOption>[];
      for (final raw in results[0] as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final available = _toHundredths(row['available_weight_kg']);
        if (available <= 0) continue;
        final varietyId = row['variety_id'] as String;
        final gradeId = row['grade_id'] as String;
        inventories.add(
          RipeningInventoryOption(
            id: row['container_id'] as String,
            displayId: row['display_id'] as String,
            varietyId: varietyId,
            varietyLabel: varieties[varietyId] ?? '不明',
            gradeId: gradeId,
            gradeLabel: grades[gradeId] ?? '不明',
            availableWeightHundredths: available,
          ),
        );
      }

      final orders = <RipeningOrderOption>[];
      for (final raw in results[1] as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final status = row['status'] as String;
        final available = _toHundredths(row['shortage_weight_kg']);
        if (!const {
              'confirmed',
              'in_progress',
              'partially_shipped',
            }.contains(status) ||
            available <= 0) {
          continue;
        }
        orders.add(
          RipeningOrderOption(
            id: row['order_id'] as String,
            orderNumber: row['order_number'] as String,
            customerLabel:
                (row['customer_nickname'] as String?)?.trim().isNotEmpty == true
                ? row['customer_nickname'] as String
                : row['customer_name'] as String,
            varietyId: row['variety_id'] as String,
            gradeId: row['grade_id'] as String,
            availableWeightHundredths: available,
            scheduledShipDate: DateTime.parse(
              row['scheduled_ship_on'] as String,
            ),
          ),
        );
      }

      return RipeningPlanOptions(
        inventories: inventories,
        orders: orders,
        locations: _options(results[4], nameKey: 'name'),
        workers: _options(results[5], nameKey: 'display_name'),
      );
    } on TimeoutException {
      throw const RipeningPlanFailure(
        message: '追熟計画の選択肢を読み込めませんでした。時間をおいて再試行してください。',
        code: 'TIMEOUT',
        retryable: true,
      );
    } on RipeningPlanFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _referenceFailure(error.code);
    } catch (_) {
      throw const RipeningPlanFailure(
        message: '追熟計画の選択肢を読み込めませんでした。通信状況を確認してください。',
        code: 'NETWORK_FAILED',
        retryable: true,
      );
    }
  }

  @override
  Future<RipeningPlanResult> register({
    required RipeningPlanInput input,
    required String idempotencyKey,
  }) => _execute(
    functionName: 'ripening_plan_register',
    input: input.toRpcInput(),
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<RipeningPlanResult> update({
    required RipeningPlanInput input,
    required String ripeningLotId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  }) => _execute(
    functionName: 'ripening_plan_update',
    input: {
      ...input.toRpcInput(),
      'ripening_lot_id': ripeningLotId,
      'expected_version': expectedVersion,
      'reason': reason.trim(),
    },
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<RipeningPlanResult> confirm({
    required String ripeningLotId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  }) => _execute(
    functionName: 'ripening_plan_confirm',
    input: {
      'ripening_lot_id': ripeningLotId,
      'expected_version': expectedVersion,
      'reason': reason.trim(),
    },
    idempotencyKey: idempotencyKey,
  );

  Future<RipeningPlanResult> _execute({
    required String functionName,
    required Map<String, Object?> input,
    required String idempotencyKey,
  }) async {
    RipeningPlanFailure? lastFailure;
    for (var attempt = 0; attempt < 3; attempt++) {
      final correlationId = _uuidV4();
      try {
        final raw = await _client
            .rpc(
              functionName,
              params: {
                'req': {
                  'meta': {
                    'idempotency_key': idempotencyKey,
                    'correlation_id': correlationId,
                  },
                  'input': input,
                },
              },
            )
            .timeout(const Duration(seconds: 10));
        final response = Map<String, dynamic>.from(raw as Map);
        if (response['ok'] == true) {
          final data = Map<String, dynamic>.from(response['data'] as Map);
          return RipeningPlanResult(
            id: data['id'] as String,
            displayId: data['display_id'] as String,
            status: data['status'] as String,
            version: (data['version'] as num).toInt(),
            plannedEthyleneAt: DateTime.parse(
              data['planned_ethylene_at'] as String,
            ),
            plannedCompletionAt: DateTime.parse(
              data['planned_completion_at'] as String,
            ),
            idempotentReplay: response['idempotent_replay'] == true,
          );
        }
        final error = Map<String, dynamic>.from(response['error'] as Map);
        final details = error['details'] is Map
            ? Map<String, dynamic>.from(error['details'] as Map)
            : const <String, dynamic>{};
        final failure = RipeningPlanFailure(
          message: error['message'] as String? ?? '追熟計画を登録できませんでした。',
          code: error['code'] as String?,
          field: details['field'] as String?,
          reason: details['reason'] as String?,
          correlationId: response['correlation_id'] as String?,
          retryable: error['retryable'] == true,
        );
        if (!failure.retryable) throw failure;
        lastFailure = failure;
      } on RipeningPlanFailure catch (failure) {
        if (!failure.retryable) rethrow;
        lastFailure = failure;
      } on TimeoutException {
        lastFailure = RipeningPlanFailure(
          message: '登録結果を確認できませんでした。自動で再確認します。',
          code: 'TIMEOUT',
          correlationId: correlationId,
          retryable: true,
        );
      } on PostgrestException catch (error) {
        if (error.code == 'PGRST202') {
          throw RipeningPlanFailure(
            message: '追熟計画機能の構成が一致していません。管理者へ連絡してください。',
            code: error.code,
            correlationId: correlationId,
          );
        }
        lastFailure = RipeningPlanFailure(
          message: '追熟計画の登録処理へ接続できませんでした。自動で再確認します。',
          code: error.code,
          correlationId: correlationId,
          retryable: true,
        );
      } catch (_) {
        lastFailure = RipeningPlanFailure(
          message: '通信に失敗しました。自動で再確認します。',
          code: 'NETWORK_FAILED',
          correlationId: correlationId,
          retryable: true,
        );
      }
      if (attempt < 2) {
        final jitter = Random.secure().nextInt(251);
        await Future<void>.delayed(
          Duration(seconds: attempt + 1, milliseconds: jitter),
        );
      }
    }
    throw lastFailure ??
        const RipeningPlanFailure(
          message: '追熟計画の登録結果を確認できませんでした。',
          retryable: true,
        );
  }
}

Map<String, String> _labels(
  dynamic rawRows, {
  required String nameKey,
  bool includeCode = true,
}) => {
  for (final raw in rawRows as List)
    (raw as Map)['id'] as String: includeCode
        ? '${raw['code']}　${raw[nameKey]}'
        : raw[nameKey] as String,
};

List<RipeningReferenceOption> _options(
  dynamic rawRows, {
  required String nameKey,
}) => [
  for (final raw in rawRows as List)
    RipeningReferenceOption(
      id: (raw as Map)['id'] as String,
      label: '${raw['code']}　${raw[nameKey]}',
    ),
];

RipeningPlanFailure _referenceFailure(String? code) {
  if (const {'401', 'PGRST301', 'PGRST302', 'PGRST303'}.contains(code)) {
    return const RipeningPlanFailure(
      message: 'セッションの有効期限が切れています。再ログインしてください。',
      code: 'AUTH_REQUIRED',
    );
  }
  if (const {'403', '42501'}.contains(code)) {
    return const RipeningPlanFailure(
      message: '追熟計画を確認する権限がありません。',
      code: 'AUTH_FORBIDDEN',
    );
  }
  return const RipeningPlanFailure(
    message: '追熟計画の選択肢を読み込めませんでした。通信状況を確認してください。',
    code: 'UNEXPECTED',
    retryable: true,
  );
}

int _toHundredths(dynamic value) => ((value as num).toDouble() * 100).round();

String createRipeningIdempotencyKey() => _uuidV4();

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
