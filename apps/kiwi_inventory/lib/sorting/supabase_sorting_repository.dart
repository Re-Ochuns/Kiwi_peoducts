import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'sorting_repository.dart';

class SupabaseSortingRepository implements SortingRepository {
  SupabaseSortingRepository(this._client);

  factory SupabaseSortingRepository.fromInitializedClient() =>
      SupabaseSortingRepository(Supabase.instance.client);

  final SupabaseClient _client;

  @override
  Future<SortingLoadData> load() async {
    try {
      final results = await Future.wait([
        _client
            .from('receiving_lots')
            .select(
              'id, display_id, source_type, received_on, origin_name, '
              'total_weight_kg, sorting_due_on, version, '
              'variety:varieties!receiving_lots_variety_id_fkey(name)',
            )
            .eq('status', 'awaiting_sorting')
            .order('sorting_due_on')
            .order('display_id'),
        _client
            .from('grades')
            .select('id, code, display_order')
            .eq('is_active', true)
            .order('display_order'),
        _client
            .from('workers')
            .select('id, code, display_name')
            .eq('is_active', true)
            .order('code'),
      ]).timeout(const Duration(seconds: 10));

      final lotRows = results[0] as List;
      final gradeRows = results[1] as List;
      final workerRows = results[2] as List;
      return SortingLoadData(
        lots: [
          for (final value in lotRows)
            _lotFromRow(Map<String, dynamic>.from(value as Map)),
        ],
        grades: [
          for (final value in gradeRows)
            _gradeFromRow(Map<String, dynamic>.from(value as Map)),
        ],
        workers: [
          for (final value in workerRows)
            _workerFromRow(Map<String, dynamic>.from(value as Map)),
        ],
      );
    } on TimeoutException {
      throw const SortingFailure(
        message: '選果対象の読み込みがタイムアウトしました。',
        code: 'TIMEOUT',
        retryable: true,
      );
    } on SortingFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw sortingFailureForPostgrestCode(error.code, loading: true);
    } catch (_) {
      throw const SortingFailure(
        message: '選果対象を読み込めませんでした。通信状況を確認してください。',
        code: 'NETWORK_FAILED',
        retryable: true,
      );
    }
  }

  @override
  Future<SortingResult> confirm({
    required SortingInput input,
    required String idempotencyKey,
  }) async {
    SortingFailure? lastFailure;
    for (var attempt = 0; attempt < 3; attempt++) {
      final correlationId = _uuidV4();
      try {
        final raw = await _client
            .rpc(
              'sorting_confirm',
              params: {
                'req': {
                  'meta': {
                    'idempotency_key': idempotencyKey,
                    'correlation_id': correlationId,
                  },
                  'input': input.toRpcInput(),
                },
              },
            )
            .timeout(const Duration(seconds: 10));
        final response = Map<String, dynamic>.from(raw as Map);
        if (response['ok'] == true) {
          return _resultFromResponse(response);
        }

        final error = Map<String, dynamic>.from(response['error'] as Map);
        final details = error['details'] is Map
            ? Map<String, dynamic>.from(error['details'] as Map)
            : const <String, dynamic>{};
        final current = details['current'] is Map
            ? Map<String, dynamic>.from(details['current'] as Map)
            : null;
        final failure = SortingFailure(
          message: error['message'] as String? ?? '選果を確定できませんでした。',
          code: error['code'] as String?,
          field: details['field'] as String?,
          reason: details['reason'] as String?,
          correlationId: response['correlation_id'] as String?,
          retryable: error['retryable'] == true,
          current: current,
        );
        if (!failure.retryable) throw failure;
        lastFailure = failure;
      } on SortingFailure catch (failure) {
        if (!failure.retryable) rethrow;
        lastFailure = failure;
      } on TimeoutException {
        lastFailure = SortingFailure(
          message: '確定結果を確認できませんでした。自動で再確認します。',
          correlationId: correlationId,
          retryable: true,
        );
      } on PostgrestException catch (error) {
        final failure = sortingFailureForPostgrestCode(
          error.code,
          correlationId: correlationId,
        );
        if (!failure.retryable) throw failure;
        lastFailure = failure;
      } catch (_) {
        lastFailure = SortingFailure(
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
        const SortingFailure(message: '確定結果を確認できませんでした。', retryable: true);
  }

  SortingLot _lotFromRow(Map<String, dynamic> row) {
    final variety = Map<String, dynamic>.from(row['variety'] as Map);
    return SortingLot(
      id: row['id'] as String,
      displayId: row['display_id'] as String,
      sourceType: row['source_type'] as String,
      receivedOn: DateTime.parse(row['received_on'] as String),
      originName: row['origin_name'] as String,
      varietyName: variety['name'] as String,
      totalWeightHundredths: _toHundredths(row['total_weight_kg']),
      sortingDueOn: DateTime.parse(row['sorting_due_on'] as String),
      version: (row['version'] as num).toInt(),
    );
  }

  SortingGrade _gradeFromRow(Map<String, dynamic> row) => SortingGrade(
    id: row['id'] as String,
    code: row['code'] as String,
    displayOrder: (row['display_order'] as num).toInt(),
  );

  SortingWorker _workerFromRow(Map<String, dynamic> row) => SortingWorker(
    id: row['id'] as String,
    code: row['code'] as String,
    displayName: row['display_name'] as String,
  );

  SortingResult _resultFromResponse(Map<String, dynamic> response) {
    final data = Map<String, dynamic>.from(response['data'] as Map);
    final containerRows = data['containers'] as List;
    return SortingResult(
      sortingResultId: data['sorting_result_id'] as String,
      displayId: data['display_id'] as String,
      inputWeightHundredths: _toHundredths(data['input_weight_kg']),
      outputWeightHundredths: _toHundredths(data['output_weight_kg']),
      lossWeightHundredths: _toHundredths(data['loss_weight_kg']),
      containers: [
        for (final value in containerRows)
          _resultContainerFromRow(Map<String, dynamic>.from(value as Map)),
      ],
      idempotentReplay: response['idempotent_replay'] == true,
    );
  }

  SortingResultContainer _resultContainerFromRow(Map<String, dynamic> row) =>
      SortingResultContainer(
        containerId: row['container_id'] as String,
        displayId: row['display_id'] as String,
        gradeId: row['grade_id'] as String,
        weightHundredths: _toHundredths(row['weight_kg']),
      );
}

int _toHundredths(dynamic value) => ((value as num).toDouble() * 100).round();

SortingFailure sortingFailureForPostgrestCode(
  String? errorCode, {
  String? correlationId,
  bool loading = false,
}) {
  if (const {'401', 'PGRST301', 'PGRST302', 'PGRST303'}.contains(errorCode)) {
    return SortingFailure(
      message: 'セッションの有効期限が切れています。再ログインしてください。',
      code: 'AUTH_REQUIRED',
      correlationId: correlationId,
    );
  }
  if (const {'403', '42501'}.contains(errorCode)) {
    return SortingFailure(
      message: 'この操作を行う権限がありません。',
      code: 'AUTH_FORBIDDEN',
      correlationId: correlationId,
    );
  }
  if (errorCode == 'PGRST202') {
    return SortingFailure(
      message: '選果機能の構成が一致していません。管理者へ連絡してください。',
      code: 'CONTRACT_MISMATCH',
      correlationId: correlationId,
    );
  }
  final serverUnavailable =
      errorCode != null && RegExp(r'^5\d\d$').hasMatch(errorCode);
  return SortingFailure(
    message: loading
        ? '選果対象を読み込めませんでした。通信状況を確認してください。'
        : '選果処理へ接続できませんでした。自動で再確認します。',
    code: serverUnavailable ? 'SERVER_UNAVAILABLE' : 'UNEXPECTED',
    correlationId: correlationId,
    retryable: true,
  );
}

String createSortingIdempotencyKey() => _uuidV4();

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
