import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_inventory/master/master_repository.dart';
import 'package:kiwi_inventory/master/supabase_master_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('profilesとuser_rolesを分けて管理者権限を読み込む', () async {
    final requests = <http.Request>[];
    final client = _client(requests: requests, role: 'administrator');
    final repository = SupabaseMasterRepository(client, currentUserId: _userId);

    final catalog = await repository.loadCatalog();

    expect(catalog.canManage, isTrue);
    final profileRequest = requests.singleWhere(
      (request) => request.url.path.endsWith('/profiles'),
    );
    expect(profileRequest.url.queryParameters['select'], 'access_status');
    expect(profileRequest.url.queryParameters['id'], 'eq.$_userId');
    final roleRequest = requests.singleWhere(
      (request) => request.url.path.endsWith('/user_roles'),
    );
    expect(roleRequest.url.queryParameters['select'], 'role');
    expect(roleRequest.url.queryParameters['user_id'], 'eq.$_userId');
    expect(
      MasterType.values.every(
        (type) => requests.any(
          (request) => request.url.path.endsWith('/${type.tableName}'),
        ),
      ),
      isTrue,
    );
    await client.dispose();
  });

  test('activeなmemberには更新権限を付与しない', () async {
    final client = _client(requests: [], role: 'member');
    final repository = SupabaseMasterRepository(client, currentUserId: _userId);

    final catalog = await repository.loadCatalog();

    expect(catalog.canManage, isFalse);
    await client.dispose();
  });

  test('1000件を超えるマスターをページングしてすべて読み込む', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.test',
      'test',
      httpClient: MockClient((request) async {
        requests.add(request);
        final resource = request.url.pathSegments.last;
        Object body;
        if (resource == 'profiles') {
          body = {'access_status': 'active'};
        } else if (resource == 'user_roles') {
          body = [
            {'role': 'administrator'},
          ];
        } else if (resource == 'varieties') {
          final start = int.parse(request.url.queryParameters['offset'] ?? '0');
          body = [
            for (
              var index = start;
              index < 1001 && index < start + 1000;
              index++
            )
              {
                'id': 'variety-$index',
                'code': 'code-$index',
                'name': '品種$index',
                'is_active': true,
                'version': 1,
              },
          ];
        } else {
          body = const <Object>[];
        }
        return http.Response(
          jsonEncode(body),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final repository = SupabaseMasterRepository(client, currentUserId: _userId);

    final catalog = await repository.loadCatalog();

    expect(catalog.of(MasterType.variety), hasLength(1001));
    expect(
      requests.where((request) => request.url.path.endsWith('/varieties')),
      hasLength(2),
    );
    await client.dispose();
  });

  test('登録RPCへ共通封筒を送り成功応答をMasterRecordへ変換する', () async {
    late Map<String, dynamic> requestBody;
    final client = SupabaseClient(
      'https://example.test',
      'test',
      httpClient: MockClient((request) async {
        expect(request.url.path, endsWith('/rpc/master_register'));
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'ok': true,
            'correlation_id': '69000000-0000-4000-8000-000000000001',
            'idempotent_replay': false,
            'data': {
              'master_type': 'variety',
              'master_id': 'a1000000-0000-0000-0000-000000000001',
              'code': 'hayward',
              'name': 'ヘイワード',
              'is_active': true,
              'version': 1,
            },
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final repository = SupabaseMasterRepository(client);

    final result = await repository.register(
      type: MasterType.variety,
      values: const {'code': 'hayward', 'name': 'ヘイワード'},
      reason: '',
      idempotencyKey: '6c000000-0000-4000-8000-000000000001',
    );

    final req = requestBody['req'] as Map<String, dynamic>;
    final meta = req['meta'] as Map<String, dynamic>;
    final input = req['input'] as Map<String, dynamic>;
    expect(meta['idempotency_key'], '6c000000-0000-4000-8000-000000000001');
    expect(meta['correlation_id'], matches(_uuidV4Pattern));
    expect(input, {
      'master_type': 'variety',
      'code': 'hayward',
      'name': 'ヘイワード',
    });
    expect(result.record.id, 'a1000000-0000-0000-0000-000000000001');
    expect(result.record.primaryText, 'hayward');
    expect(result.record.secondaryText, 'ヘイワード');
    expect(result.record.isActive, isTrue);
    expect(result.record.version, 1);
    expect(result.idempotentReplay, isFalse);
    await client.dispose();
  });

  test('RPCの項目エラーと相関IDを画面用失敗へ変換する', () async {
    final client = SupabaseClient(
      'https://example.test',
      'test',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'ok': false,
            'correlation_id': '69000000-0000-4000-8000-000000000002',
            'error': {
              'code': 'MASTER_DUPLICATE',
              'message': 'このコードは登録済みです。',
              'retryable': false,
              'details': {'field': 'code', 'reason': 'duplicate'},
            },
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final repository = SupabaseMasterRepository(client);

    await expectLater(
      repository.register(
        type: MasterType.variety,
        values: const {'code': 'hayward', 'name': '別品種'},
        reason: '',
        idempotencyKey: '6c000000-0000-4000-8000-000000000002',
      ),
      throwsA(
        isA<MasterFailure>()
            .having((error) => error.code, 'code', 'MASTER_DUPLICATE')
            .having((error) => error.field, 'field', 'code')
            .having((error) => error.reason, 'reason', 'duplicate')
            .having(
              (error) => error.correlationId,
              'correlationId',
              '69000000-0000-4000-8000-000000000002',
            ),
      ),
    );
    await client.dispose();
  });
}

const _userId = '60000000-0000-0000-0000-000000000003';
final _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

SupabaseClient _client({
  required List<http.Request> requests,
  required String role,
}) => SupabaseClient(
  'https://example.test',
  'test',
  httpClient: MockClient((request) async {
    requests.add(request);
    final body = switch (request.url.pathSegments.last) {
      'profiles' => {'access_status': 'active'},
      'user_roles' => [
        {'role': role},
      ],
      _ => const <Object>[],
    };
    return http.Response(
      jsonEncode(body),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }),
);
