import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'receiving_repository.dart';

class SupabaseReceivingRepository implements ReceivingRepository {
  SupabaseReceivingRepository(this._client);

  factory SupabaseReceivingRepository.fromInitializedClient() =>
      SupabaseReceivingRepository(Supabase.instance.client);

  final SupabaseClient _client;

  @override
  Future<ReceivingMasters> loadMasters() async {
    try {
      final results = await Future.wait([
        _client.from('orchards').select('id, code, name').eq('is_active', true),
        _client
            .from('orchard_plots')
            .select('id, orchard_id, code, name')
            .eq('is_active', true),
        _client
            .from('trees')
            .select('id, plot_id, variety_id, code, name')
            .eq('is_active', true),
        _client
            .from('suppliers')
            .select('id, management_code, name')
            .eq('is_active', true),
        _client
            .from('varieties')
            .select('id, code, name')
            .eq('is_active', true),
        _client
            .from('workers')
            .select('id, code, display_name')
            .eq('is_active', true),
      ]).timeout(const Duration(seconds: 10));

      List<MasterOption> options(
        dynamic rows, {
        required String labelKey,
        String? codeKey,
        String? parentKey,
        String? varietyKey,
      }) => [
        for (final row in rows as List)
          MasterOption(
            id: row['id'] as String,
            label: codeKey == null
                ? row[labelKey] as String
                : '${row[codeKey]}　${row[labelKey]}',
            parentId: parentKey == null ? null : row[parentKey] as String,
            varietyId: varietyKey == null ? null : row[varietyKey] as String,
          ),
      ];

      return ReceivingMasters(
        orchards: options(results[0], labelKey: 'name', codeKey: 'code'),
        plots: options(
          results[1],
          labelKey: 'name',
          codeKey: 'code',
          parentKey: 'orchard_id',
        ),
        trees: options(
          results[2],
          labelKey: 'name',
          codeKey: 'code',
          parentKey: 'plot_id',
          varietyKey: 'variety_id',
        ),
        suppliers: options(
          results[3],
          labelKey: 'name',
          codeKey: 'management_code',
        ),
        varieties: options(results[4], labelKey: 'name', codeKey: 'code'),
        workers: options(results[5], labelKey: 'display_name', codeKey: 'code'),
      );
    } on TimeoutException {
      throw const ReceivingFailure(
        message: '選択肢の読み込みがタイムアウトしました。',
        retryable: true,
      );
    } catch (_) {
      throw const ReceivingFailure(
        message: '選択肢を読み込めませんでした。通信状況を確認してください。',
        retryable: true,
      );
    }
  }

  @override
  Future<ReceivingResult> register({
    required ReceivingInput input,
    required String idempotencyKey,
  }) => _execute(
    functionName: 'receiving_register',
    input: input.toRpcInput(),
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<ReceivingResult> correct({
    required ReceivingInput input,
    required String receivingLotId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  }) => _execute(
    functionName: 'receiving_correct',
    input: {
      ...input.toRpcInput(),
      'receiving_lot_id': receivingLotId,
      'expected_version': expectedVersion,
      'reason': reason.trim(),
    },
    idempotencyKey: idempotencyKey,
  );

  Future<ReceivingResult> _execute({
    required String functionName,
    required Map<String, Object> input,
    required String idempotencyKey,
  }) async {
    ReceivingFailure? lastFailure;
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
          return ReceivingResult(
            receivingLotId: data['receiving_lot_id'] as String,
            displayId: data['display_id'] as String,
            receivedDate: data['received_date'] as String,
            sortingDueDate: data['sorting_due_date'] as String,
            version: (data['version'] as num).toInt(),
            idempotentReplay: response['idempotent_replay'] == true,
          );
        }
        final error = Map<String, dynamic>.from(response['error'] as Map);
        final details = error['details'] is Map
            ? Map<String, dynamic>.from(error['details'] as Map)
            : const <String, dynamic>{};
        final failure = ReceivingFailure(
          message: error['message'] as String? ?? '登録できませんでした。',
          field: details['field'] as String?,
          reason: details['reason'] as String?,
          correlationId: response['correlation_id'] as String?,
          retryable: error['retryable'] == true,
        );
        if (!failure.retryable) throw failure;
        lastFailure = failure;
      } on ReceivingFailure catch (failure) {
        if (!failure.retryable) rethrow;
        lastFailure = failure;
      } on TimeoutException {
        lastFailure = ReceivingFailure(
          message: '登録結果を確認できませんでした。自動で再確認します。',
          correlationId: correlationId,
          retryable: true,
        );
      } on PostgrestException catch (error) {
        lastFailure = ReceivingFailure(
          message: '登録処理へ接続できませんでした。自動で再確認します。',
          correlationId: correlationId,
          retryable: true,
        );
        if (error.code == 'PGRST202') {
          throw ReceivingFailure(
            message: '登録機能の構成が一致していません。管理者へ連絡してください。',
            correlationId: correlationId,
          );
        }
      } catch (_) {
        lastFailure = ReceivingFailure(
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
        const ReceivingFailure(message: '登録結果を確認できませんでした。', retryable: true);
  }
}

String createIdempotencyKey() => _uuidV4();

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
