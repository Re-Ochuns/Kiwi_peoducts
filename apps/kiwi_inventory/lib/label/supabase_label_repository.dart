import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import 'label_repository.dart';

class SupabaseLabelRepository implements LabelRepository {
  SupabaseLabelRepository(
    this._client, {
    required this.supabaseUrl,
    required this.supabaseKey,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  factory SupabaseLabelRepository.fromInitializedClient(AppConfig config) =>
      SupabaseLabelRepository(
        Supabase.instance.client,
        supabaseUrl: config.supabaseUrl,
        supabaseKey: config.supabaseKey,
      );

  final SupabaseClient _client;
  final String supabaseUrl;
  final String supabaseKey;
  final http.Client _httpClient;

  @override
  Future<LabelLoadData> load() async {
    try {
      final results = await Future.wait([
        _client
            .from('label_jobs')
            .select(
              'id, status, required_copies, printed_copies, reprint_count, '
              'container:containers!label_jobs_container_id_fkey('
              'id, display_id, original_weight_kg, '
              'grade:grades!containers_grade_id_fkey(code), '
              'variety:varieties!containers_variety_id_fkey(name), '
              'sorting_result:sorting_results!containers_sorting_result_id_fkey('
              'sorted_on, worker:workers!sorting_results_sorted_by_fkey(display_name), '
              'receiving_lot:receiving_lots!sorting_results_receiving_lot_id_fkey(origin_name)'
              ')'
              ')',
            )
            .order('created_at', ascending: false),
        _client
            .from('workers')
            .select('id, code, display_name')
            .eq('is_active', true)
            .order('code'),
        _client
            .from('storage_locations')
            .select('id, code, name')
            .eq('is_active', true)
            .eq('location_type', 'cold_storage')
            .order('code'),
      ]).timeout(const Duration(seconds: 10));

      return LabelLoadData(
        jobs: [
          for (final value in results[0] as List)
            _jobFromRow(Map<String, dynamic>.from(value as Map)),
        ],
        workers: [
          for (final value in results[1] as List)
            _optionFromRow(
              Map<String, dynamic>.from(value as Map),
              'display_name',
            ),
        ],
        locations: [
          for (final value in results[2] as List)
            _optionFromRow(Map<String, dynamic>.from(value as Map), 'name'),
        ],
      );
    } on TimeoutException {
      throw const LabelFailure(
        message: 'ラベル対象の読み込みがタイムアウトしました。',
        code: 'TIMEOUT',
        retryable: true,
      );
    } on LabelFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _failureForPostgrest(error.code, loading: true);
    } catch (_) {
      throw const LabelFailure(
        message: 'ラベル対象を読み込めませんでした。通信状況を確認してください。',
        code: 'NETWORK_FAILED',
        retryable: true,
      );
    }
  }

  @override
  Future<LabelPdf> fetchPdf({required String containerId}) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw const LabelFailure(
        message: 'セッションの有効期限が切れています。再ログインしてください。',
        code: 'AUTH_REQUIRED',
      );
    }
    final correlationId = _uuidV4();
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$supabaseUrl/functions/v1/label-pdf'),
            headers: {
              'Authorization': 'Bearer ${session.accessToken}',
              'apikey': supabaseKey,
              'Content-Type': 'application/json',
              'x-correlation-id': correlationId,
            },
            body: jsonEncode({
              'container_id': containerId,
              'correlation_id': correlationId,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return LabelPdf(
          bytes: Uint8List.fromList(response.bodyBytes),
          filename: '$containerId.pdf',
        );
      }
      throw _failureForPdfResponse(response, correlationId);
    } on TimeoutException {
      throw LabelFailure(
        message: 'ラベルPDFの生成がタイムアウトしました。再試行してください。',
        code: 'TIMEOUT',
        correlationId: correlationId,
        retryable: true,
      );
    } on LabelFailure {
      rethrow;
    } catch (_) {
      throw LabelFailure(
        message: 'ラベルPDFを取得できませんでした。通信状況を確認してください。',
        code: 'NETWORK_FAILED',
        correlationId: correlationId,
        retryable: true,
      );
    }
  }

  @override
  Future<LabelActionResult> markPrinted({
    required String labelJobId,
    required String workerId,
    required int copies,
    required String idempotencyKey,
    String? locationId,
  }) => _execute(
    functionName: 'label_mark_printed',
    input: {
      'label_job_id': labelJobId,
      'worker_id': workerId,
      'copies': copies,
      'location_id': ?locationId,
    },
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<LabelActionResult> markHandwritten({
    required String labelJobId,
    required String workerId,
    required String idempotencyKey,
    String? notes,
    String? locationId,
  }) => _execute(
    functionName: 'label_mark_handwritten',
    input: {
      'label_job_id': labelJobId,
      'worker_id': workerId,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      'location_id': ?locationId,
    },
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<LabelActionResult> reprint({
    required String labelJobId,
    required String workerId,
    required String reason,
    required int copies,
    required String idempotencyKey,
  }) => _execute(
    functionName: 'label_reprint',
    input: {
      'label_job_id': labelJobId,
      'worker_id': workerId,
      'reason': reason.trim(),
      'copies': copies,
    },
    idempotencyKey: idempotencyKey,
  );

  Future<LabelActionResult> _execute({
    required String functionName,
    required Map<String, Object> input,
    required String idempotencyKey,
  }) async {
    LabelFailure? lastFailure;
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
          return _resultFromResponse(response);
        }
        final error = Map<String, dynamic>.from(response['error'] as Map);
        final details = error['details'] is Map
            ? Map<String, dynamic>.from(error['details'] as Map)
            : const <String, dynamic>{};
        final failure = LabelFailure(
          message: error['message'] as String? ?? 'ラベルの状態を更新できませんでした。',
          code: error['code'] as String?,
          field: details['field'] as String?,
          correlationId: response['correlation_id'] as String?,
          retryable: error['retryable'] == true,
          current: details['current'] is Map
              ? Map<String, dynamic>.from(details['current'] as Map)
              : null,
        );
        if (!failure.retryable) throw failure;
        lastFailure = failure;
      } on LabelFailure catch (failure) {
        if (!failure.retryable) rethrow;
        lastFailure = failure;
      } on TimeoutException {
        lastFailure = LabelFailure(
          message: '更新結果を確認できませんでした。自動で再確認します。',
          correlationId: correlationId,
          retryable: true,
        );
      } on PostgrestException catch (error) {
        final failure = _failureForPostgrest(
          error.code,
          correlationId: correlationId,
        );
        if (!failure.retryable) throw failure;
        lastFailure = failure;
      } catch (_) {
        lastFailure = LabelFailure(
          message: '通信に失敗しました。自動で再確認します。',
          correlationId: correlationId,
          retryable: true,
        );
      }
      if (attempt < 2) {
        await Future<void>.delayed(
          Duration(
            seconds: attempt + 1,
            milliseconds: Random.secure().nextInt(251),
          ),
        );
      }
    }
    throw lastFailure ??
        const LabelFailure(message: '更新結果を確認できませんでした。', retryable: true);
  }

  LabelJob _jobFromRow(Map<String, dynamic> row) {
    final container = Map<String, dynamic>.from(row['container'] as Map);
    final grade = Map<String, dynamic>.from(container['grade'] as Map);
    final variety = Map<String, dynamic>.from(container['variety'] as Map);
    final sorting = Map<String, dynamic>.from(
      container['sorting_result'] as Map,
    );
    final worker = Map<String, dynamic>.from(sorting['worker'] as Map);
    final lot = Map<String, dynamic>.from(sorting['receiving_lot'] as Map);
    return LabelJob(
      id: row['id'] as String,
      containerId: container['id'] as String,
      containerDisplayId: container['display_id'] as String,
      status: _statusFromValue(row['status'] as String),
      requiredCopies: (row['required_copies'] as num).toInt(),
      printedCopies: (row['printed_copies'] as num).toInt(),
      reprintCount: (row['reprint_count'] as num).toInt(),
      originName: lot['origin_name'] as String,
      varietyName: variety['name'] as String,
      gradeCode: grade['code'] as String,
      weightHundredths: _toHundredths(container['original_weight_kg']),
      sortedOn: DateTime.parse(sorting['sorted_on'] as String),
      workerName: worker['display_name'] as String,
    );
  }

  LabelOption _optionFromRow(Map<String, dynamic> row, String nameKey) =>
      LabelOption(
        id: row['id'] as String,
        label: '${row['code']}　${row[nameKey]}',
      );

  LabelActionResult _resultFromResponse(Map<String, dynamic> response) {
    final data = Map<String, dynamic>.from(response['data'] as Map);
    return LabelActionResult(
      labelJobId: data['label_job_id'] as String,
      status: _statusFromValue(data['status'] as String),
      printedCopies: (data['printed_copies'] as num).toInt(),
      requiredCopies: (data['required_copies'] as num).toInt(),
      reprintCount: (data['reprint_count'] as num).toInt(),
    );
  }
}

LabelFailure _failureForPdfResponse(
  http.Response response,
  String correlationId,
) {
  try {
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final error = Map<String, dynamic>.from(body['error'] as Map);
    final code = error['code'] as String?;
    return LabelFailure(
      message: error['message'] as String? ?? 'ラベルPDFを生成できませんでした。',
      code: code,
      correlationId: body['correlation_id'] as String? ?? correlationId,
      retryable: response.statusCode >= 500,
    );
  } catch (_) {
    return LabelFailure(
      message: 'ラベルPDFを生成できませんでした。再試行してください。',
      code: 'UNEXPECTED',
      correlationId: correlationId,
      retryable: response.statusCode >= 500,
    );
  }
}

LabelFailure _failureForPostgrest(
  String? code, {
  String? correlationId,
  bool loading = false,
}) {
  if (const {'401', 'PGRST301', 'PGRST302', 'PGRST303'}.contains(code)) {
    return LabelFailure(
      message: 'セッションの有効期限が切れています。再ログインしてください。',
      code: 'AUTH_REQUIRED',
      correlationId: correlationId,
    );
  }
  if (const {'403', '42501'}.contains(code)) {
    return LabelFailure(
      message: 'この操作を行う権限がありません。',
      code: 'AUTH_FORBIDDEN',
      correlationId: correlationId,
    );
  }
  return LabelFailure(
    message: loading
        ? 'ラベル対象を読み込めませんでした。通信状況を確認してください。'
        : 'ラベル処理へ接続できませんでした。自動で再確認します。',
    code: code,
    correlationId: correlationId,
    retryable: true,
  );
}

LabelJobStatus _statusFromValue(String value) => switch (value) {
  'not_printed' => LabelJobStatus.notPrinted,
  'partially_printed' => LabelJobStatus.partiallyPrinted,
  'printed' => LabelJobStatus.printed,
  'handwritten' => LabelJobStatus.handwritten,
  _ => throw FormatException('Unknown label status: $value'),
};

int _toHundredths(dynamic value) => ((value as num).toDouble() * 100).round();

String createLabelIdempotencyKey() => _uuidV4();

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
