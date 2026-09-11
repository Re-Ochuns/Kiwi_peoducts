import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'master_repository.dart';

class SupabaseMasterRepository implements MasterRepository {
  SupabaseMasterRepository(this._client, {this.currentUserId});

  factory SupabaseMasterRepository.fromInitializedClient() =>
      SupabaseMasterRepository(Supabase.instance.client);

  final SupabaseClient _client;
  final String? currentUserId;

  @override
  Future<MasterCatalog> loadCatalog() async {
    try {
      final userId = currentUserId ?? _client.auth.currentUser?.id;
      final requests = <Future<dynamic>>[
        if (userId == null)
          Future<dynamic>.value(null)
        else
          _client
              .from('profiles')
              .select('access_status')
              .eq('id', userId)
              .maybeSingle(),
        if (userId == null)
          Future<dynamic>.value(const <Map<String, dynamic>>[])
        else
          _client.from('user_roles').select('role').eq('user_id', userId),
        for (final type in MasterType.values)
          _client.from(type.tableName).select(type.selectColumns),
      ];
      final results = await Future.wait(requests)
          .timeout(const Duration(seconds: 10));
      final profile = results.first is Map
          ? Map<String, dynamic>.from(results.first as Map)
          : const <String, dynamic>{};
      final roles = results[1] is List ? results[1] as List : const [];
      final records = <MasterType, List<MasterRecord>>{};
      for (var index = 0; index < MasterType.values.length; index++) {
        final type = MasterType.values[index];
        final rows = results[index + 2] as List;
        final decoded = [
          for (final row in rows)
            _recordFromMap(type, Map<String, dynamic>.from(row as Map)),
        ]..sort((left, right) => _compareRecords(left, right));
        records[type] = decoded;
      }
      return MasterCatalog(
        records: records,
        canManage:
            profile['access_status'] == 'active' &&
            roles.any((value) => (value as Map)['role'] == 'administrator'),
      );
    } on TimeoutException {
      throw const MasterFailure(
        message: 'マスターの読み込みがタイムアウトしました。',
        retryable: true,
      );
    } on PostgrestException catch (error) {
      throw MasterFailure(
        message: error.code == '42501'
            ? 'マスターを確認する権限がありません。'
            : 'マスターを読み込めませんでした。通信状況を確認してください。',
        code: error.code,
        retryable: error.code != '42501',
      );
    } catch (_) {
      throw const MasterFailure(
        message: 'マスターを読み込めませんでした。通信状況を確認してください。',
        retryable: true,
      );
    }
  }

  @override
  Future<MasterMutationResult> register({
    required MasterType type,
    required Map<String, Object> values,
    required String reason,
    required String idempotencyKey,
  }) {
    final input = <String, Object>{'master_type': type.rpcValue, ...values};
    if (reason.trim().isNotEmpty) input['reason'] = reason.trim();
    return _execute(
      functionName: 'master_register',
      type: type,
      input: input,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<MasterMutationResult> update({
    required MasterRecord record,
    required Map<String, Object> values,
    required String reason,
    required String idempotencyKey,
  }) => _execute(
    functionName: 'master_update',
    type: record.type,
    input: {
      'master_type': record.type.rpcValue,
      'master_id': record.id,
      'expected_version': record.version,
      'reason': reason.trim(),
      ...values,
    },
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<MasterMutationResult> setActive({
    required MasterRecord record,
    required bool active,
    required String reason,
    required String idempotencyKey,
  }) => _execute(
    functionName: active ? 'master_activate' : 'master_deactivate',
    type: record.type,
    input: {
      'master_type': record.type.rpcValue,
      'master_id': record.id,
      'expected_version': record.version,
      'reason': reason.trim(),
    },
    idempotencyKey: idempotencyKey,
  );

  Future<MasterMutationResult> _execute({
    required String functionName,
    required MasterType type,
    required Map<String, Object> input,
    required String idempotencyKey,
  }) async {
    MasterFailure? lastFailure;
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
          return MasterMutationResult(
            record: _recordFromMap(type, data),
            idempotentReplay: response['idempotent_replay'] == true,
          );
        }
        final error = response['error'] is Map
            ? Map<String, dynamic>.from(response['error'] as Map)
            : const <String, dynamic>{};
        final details = error['details'] is Map
            ? Map<String, dynamic>.from(error['details'] as Map)
            : const <String, dynamic>{};
        final failure = MasterFailure(
          message: error['message'] as String? ?? 'マスターを更新できませんでした。',
          code: error['code'] as String?,
          field: details['field'] as String?,
          reason: details['reason'] as String?,
          correlationId: response['correlation_id'] as String?,
          retryable: error['retryable'] == true,
        );
        if (!failure.retryable) throw failure;
        lastFailure = failure;
      } on MasterFailure catch (failure) {
        if (!failure.retryable) rethrow;
        lastFailure = failure;
      } on TimeoutException {
        lastFailure = MasterFailure(
          message: '更新結果を確認できませんでした。自動で再確認します。',
          correlationId: correlationId,
          retryable: true,
        );
      } on PostgrestException catch (error) {
        if (error.code == 'PGRST202') {
          throw MasterFailure(
            message: 'マスター更新機能の構成が一致していません。管理者へ連絡してください。',
            correlationId: correlationId,
          );
        }
        lastFailure = MasterFailure(
          message: '更新処理へ接続できませんでした。自動で再確認します。',
          correlationId: correlationId,
          retryable: true,
        );
      } catch (_) {
        lastFailure = MasterFailure(
          message: '通信に失敗しました。自動で再確認します。',
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
        const MasterFailure(message: '更新結果を確認できませんでした。', retryable: true);
  }
}

MasterRecord _recordFromMap(MasterType type, Map<String, dynamic> row) {
  final values = <String, Object?>{};
  for (final entry in row.entries) {
    if (!const {
      'id',
      'master_id',
      'master_type',
      'is_active',
      'version',
      'updated_at',
      'created_at',
      'created_by',
      'updated_by',
    }.contains(entry.key)) {
      values[entry.key] = entry.value;
    }
  }
  return MasterRecord(
    type: type,
    id: (row['master_id'] ?? row['id']) as String,
    values: values,
    isActive: row['is_active'] == true,
    version: (row['version'] as num?)?.toInt() ?? 1,
    updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
  );
}

int _compareRecords(MasterRecord left, MasterRecord right) {
  if (left.type == MasterType.grade) {
    return int.parse(left.value('display_order'))
        .compareTo(int.parse(right.value('display_order')));
  }
  if (left.type == MasterType.sortingDeadlineRule) {
    final leftValue =
        '${left.value('harvest_year')}-${left.value('harvest_month').padLeft(2, '0')}-${left.value('variety_id')}';
    final rightValue =
        '${right.value('harvest_year')}-${right.value('harvest_month').padLeft(2, '0')}-${right.value('variety_id')}';
    return leftValue.compareTo(rightValue);
  }
  return left.primaryText.compareTo(right.primaryText);
}

String createMasterIdempotencyKey() => _uuidV4();

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
