import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'csv_export_repository.dart';

class SupabaseCsvExportRepository implements CsvExportRepository {
  SupabaseCsvExportRepository(this._client);

  factory SupabaseCsvExportRepository.fromInitializedClient() =>
      SupabaseCsvExportRepository(Supabase.instance.client);

  final SupabaseClient _client;

  @override
  Future<CsvExportResult> export(CsvExportRequest request) async {
    final correlationId = _uuidV4();
    try {
      final raw = await _client
          .rpc(
            'csv_export',
            params: {
              'req': {
                'meta': {'correlation_id': correlationId},
                'input': request.input,
              },
            },
          )
          .timeout(const Duration(seconds: 10));
      final response = Map<String, dynamic>.from(raw as Map);
      if (response['ok'] == true) {
        return CsvExportResult.fromMap(
          Map<String, dynamic>.from(response['data'] as Map),
        );
      }
      final error = response['error'] is Map
          ? Map<String, dynamic>.from(response['error'] as Map)
          : const <String, dynamic>{};
      throw CsvExportFailure(
        message: error['message'] as String? ?? 'CSVを作成できませんでした。',
        code: error['code'] as String?,
        correlationId: response['correlation_id'] as String?,
        retryable: error['retryable'] == true,
      );
    } on CsvExportFailure {
      rethrow;
    } on TimeoutException {
      throw CsvExportFailure(
        message: 'CSVの作成がタイムアウトしました。条件を絞って再試行してください。',
        code: 'TIMEOUT',
        correlationId: correlationId,
      );
    } on PostgrestException catch (error) {
      if (const {
        '401',
        'PGRST301',
        'PGRST302',
        'PGRST303',
      }.contains(error.code)) {
        throw CsvExportFailure(
          message: 'セッションの有効期限が切れています。再ログインしてください。',
          code: 'AUTH_REQUIRED',
          correlationId: correlationId,
        );
      }
      if (const {'403', '42501'}.contains(error.code)) {
        throw CsvExportFailure(
          message: 'CSVを出力する権限がありません。',
          code: 'AUTH_FORBIDDEN',
          correlationId: correlationId,
        );
      }
      throw CsvExportFailure(
        message: 'CSVを作成できませんでした。通信状況を確認してください。',
        code: 'UNEXPECTED',
        correlationId: correlationId,
        retryable: true,
      );
    } on FormatException {
      throw CsvExportFailure(
        message: 'CSVの応答形式が正しくありません。',
        code: 'UNEXPECTED',
        correlationId: correlationId,
      );
    } catch (_) {
      throw CsvExportFailure(
        message: 'CSVを作成できませんでした。通信状況を確認してください。',
        code: 'NETWORK_FAILED',
        correlationId: correlationId,
        retryable: true,
      );
    }
  }
}

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
