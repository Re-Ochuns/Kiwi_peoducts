import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../orders/order_management_repository.dart';
import '../process_board/process_board_repository.dart';
import 'board_order_repository.dart';

class SupabaseBoardOrderRepository implements BoardOrderRepository {
  SupabaseBoardOrderRepository(this.client);
  factory SupabaseBoardOrderRepository.fromInitializedClient() =>
      SupabaseBoardOrderRepository(Supabase.instance.client);
  final SupabaseClient client;

  Future<T> _read<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      throw BoardOrderFailure(
        e.hint ?? '情報を取得できませんでした。再試行してください。',
        code: e.code ?? '',
      );
    } on BoardOrderFailure {
      rethrow;
    } catch (_) {
      throw const BoardOrderFailure('通信に失敗しました。再試行してください。');
    }
  }

  List<BoardOrderOption> _options(dynamic rows, String label) => [
    for (final row in rows as List)
      BoardOrderOption(row['id'] as String, row[label] as String),
  ];

  @override
  Future<BoardOrderOptions> loadOptions() => _read(() async {
    final data = await Future.wait<dynamic>([
      client
          .from('varieties')
          .select('id,name')
          .eq('is_active', true)
          .order('code'),
      client
          .from('grades')
          .select('id,code')
          .eq('is_active', true)
          .order('display_order'),
      client.rpc('customer_list', params: {'include_inactive': false}),
      client
          .from('storage_locations')
          .select('id,name')
          .eq('is_active', true)
          .order('code'),
      client
          .from('workers')
          .select('id,display_name')
          .eq('is_active', true)
          .order('display_name'),
    ]);
    return BoardOrderOptions(
      varieties: _options(data[0], 'name'),
      grades: _options(data[1], 'code'),
      customers: _options(data[2], 'name'),
      locations: _options(data[3], 'name'),
      workers: _options(data[4], 'display_name'),
    );
  });

  @override
  Future<List<BoardOrderOption>> destinations(String customerId) => _read(
    () async => _options(
      await client.rpc(
        'shipping_destination_list',
        params: {'customer_id_value': customerId, 'include_inactive': false},
      ),
      'destination_name',
    ),
  );

  @override
  Future<List<BoardOrderCandidate>> candidates(BoardOrderCriteria criteria) =>
      _read(() async {
        final rows = await client.rpc(
          'board_order_candidates',
          params: {'input_value': criteria.toJson()},
        );
        return [
          for (final row in rows as List)
            BoardOrderCandidate(
              id: row['id'] as String,
              kind: row['kind'] as String,
              displayId: row['display_id'] as String,
              stage: ProcessStage.values.byName(row['stage'] as String),
              availableHundredths: ((row['available_weight_kg'] as num) * 100)
                  .round(),
              start: DateTime.parse(row['planned_ethylene_at'] as String)
                  .toLocal(),
              completion: DateTime.parse(row['planned_completion_at'] as String)
                  .toLocal(),
              locationId: row['location_id'] as String?,
              version: row['version'] as String,
              containerIds: row['container_ids'] as String? ?? '',
            ),
        ];
      });

  @override
  Future<BoardOrderResult> confirm(
    Map<String, Object?> input,
    String key,
  ) async {
    try {
      final response = await client
          .rpc(
            'board_order_confirm',
            params: {
              'req': {
                'meta': {
                  'idempotency_key': key,
                  'correlation_id': createOrderIdempotencyKey(),
                },
                'input': input,
              },
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response['ok'] != true) {
        final error = response['error'] as Map;
        throw BoardOrderFailure(
          error['message'] as String? ?? '登録できませんでした。',
          code: error['code'] as String? ?? '',
        );
      }
      final data = response['data'] as Map;
      return BoardOrderResult(
        data['order_number'] as String,
        data['ripening_display_id'] as String,
        data['existing_plan'] == true,
      );
    } on BoardOrderFailure {
      rethrow;
    } on PostgrestException catch (error) {
      if (const {
        '401',
        '403',
        '42501',
        'PGRST301',
        'PGRST302',
        'PGRST303',
      }.contains(error.code)) {
        throw const BoardOrderFailure(
          '権限とログイン状態を確認してください。',
          code: 'AUTH_REQUIRED',
        );
      }
      throw const BoardOrderFailure(
        '登録結果を確認できません。同じ内容で再試行してください。',
        uncertain: true,
      );
    } catch (_) {
      throw const BoardOrderFailure(
        '登録結果を確認できません。同じ内容で再試行してください。',
        uncertain: true,
      );
    }
  }
}
