import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kiwi_inventory/orders/order_management_repository.dart';
import 'package:kiwi_inventory/ripening/ripening_plan_repository.dart';
import 'package:kiwi_inventory/ripening/supabase_ripening_plan_repository.dart';
import 'package:kiwi_inventory/work_tasks/supabase_work_task_repository.dart';
import 'package:kiwi_inventory/manager_dashboard/manager_dashboard_repository.dart';
import 'package:kiwi_inventory/orders/supabase_order_management_repository.dart';

class LostResponseClient extends http.BaseClient {
  final inner = http.Client();
  bool dropNext = false;
  int drops = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    if (dropNext && request.url.path.endsWith('/order_register')) {
      dropNext = false;
      await response.stream.drain<void>();
      drops++;
      throw const SocketException('Injected response loss after real commit');
    }
    return response;
  }

  @override
  void close() => inner.close();
}

// Local integration suite; default CI reports it as skipped without credentials.
void main() {
  const configPath = String.fromEnvironment('STAGE2_AUTH_FILE');
  if (configPath.isEmpty) {
    test(
      '実API受入は専用環境の認証ファイル指定時に実行',
      () {},
      skip: 'STAGE2_AUTH_FILE is required',
    );
    return;
  }
  final config = jsonDecode(File(configPath).readAsStringSync()) as Map;
  if (config['url'] != 'http://127.0.0.1:58321') {
    throw StateError('Refusing non-S2-verification endpoint');
  }
  final clients = <SupabaseClient>[];
  final network = LostResponseClient();
  SupabaseOrderManagementRepository repo(String? role, {bool fault = false}) {
    final user = role == null ? null : config[role] as Map;
    final c = SupabaseClient(
      config['url'] as String,
      config['key'] as String,
      headers: user == null ? {} : {'Authorization': 'Bearer ${user['token']}'},
      httpClient: fault ? network : null,
    );
    clients.add(c);
    return SupabaseOrderManagementRepository(
      c,
      currentUserId: user?['id'] as String?,
    );
  }

  tearDownAll(() async {
    for (final c in clients) {
      await c.dispose();
    }
    network.close();
  });
  test('実Auth・RLS・Repository: CRUD、競合、再送、権限', () async {
    final admin = repo('administrator', fault: true);
    final member = repo('member');
    final pending = repo('pending');
    final anon = repo(null);
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final input = CustomerInput(
      code: 'LIVE-$suffix',
      name: '架空顧客',
      nickname: '',
      postalCode: '000-0000',
      address: '検証専用',
    );
    final customer = await admin.registerCustomer(
      input,
      idempotencyKey: createOrderIdempotencyKey(),
    );
    expect(customer.id, isNotEmpty);
    final updated = await admin.updateCustomer(
      customer,
      input,
      reason: '実API検証',
      idempotencyKey: createOrderIdempotencyKey(),
    );
    expect(updated.version, customer.version + 1);
    await expectLater(
      admin.updateCustomer(
        customer,
        input,
        reason: '競合',
        idempotencyKey: createOrderIdempotencyKey(),
      ),
      throwsA(
        isA<OrderManagementFailure>().having(
          (e) => e.code,
          'code',
          'CONFLICT_STALE',
        ),
      ),
    );
    for (final restricted in [member, pending]) {
      await expectLater(
        restricted.registerCustomer(
          input,
          idempotencyKey: createOrderIdempotencyKey(),
        ),
        throwsA(
          isA<OrderManagementFailure>().having(
            (e) => e.code,
            'code',
            'AUTH_FORBIDDEN',
          ),
        ),
      );
    }
    await expectLater(
      anon.load(filter: OrderListFilter.active),
      throwsA(isA<OrderManagementFailure>()),
    );
    expect(
      (await pending.load(filter: OrderListFilter.active)).orders,
      isEmpty,
    );
    expect(
      (await member.load(filter: OrderListFilter.active)).canManage,
      isFalse,
    );
    final destinations = <ShippingDestination>[];
    for (var i = 0; i < 2; i++) {
      destinations.add(
        await admin.registerDestination(
          DestinationInput(
            customerId: customer.id,
            name: '配送先$i',
            recipientName: '架空受取人',
            postalCode: '000-0000',
            address: '検証住所$i',
          ),
          idempotencyKey: createOrderIdempotencyKey(),
        ),
      );
    }
    expect((await admin.loadCustomer(customer.id)).destinations.length, 2);
    final dest = await admin.updateDestination(
      destinations.first,
      DestinationInput(
        customerId: customer.id,
        name: '配送先0',
        recipientName: '架空受取人',
        postalCode: '000-0000',
        address: '更新住所',
      ),
      reason: '住所変更',
      idempotencyKey: createOrderIdempotencyKey(),
    );
    expect(dest.version, 2);
    OrderInput orderInput(double weight) => OrderInput(
      customerId: customer.id,
      destinationId: dest.id,
      orderedOn: DateTime(2026, 9, 12),
      scheduledShipOn: DateTime(2026, 9, 20),
      varietyId: config['variety'] as String,
      gradeId: config['grade'] as String,
      orderedWeight: weight,
      notes: 'LIVE-$suffix',
    );
    final key = createOrderIdempotencyKey();
    network.dropNext = true;
    final order = await admin.registerOrder(
      orderInput(1.10),
      idempotencyKey: key,
    );
    expect(network.drops, 1);
    expect(
      (await admin.registerOrder(orderInput(1.10), idempotencyKey: key)).id,
      order.id,
    );
    final data = await admin.load(
      filter: OrderListFilter.active,
      customerSearch: 'NO-MATCH-$suffix',
    );
    expect(data.customers, isEmpty);
    expect(data.customerOptions.any((c) => c.id == customer.id), isTrue);
    expect(data.orders.where((o) => o.id == order.id).length, 1);
    expect(data.canManage, isTrue);
    final detail = await admin.loadOrder(order.id);
    expect(detail.address, '更新住所');
    final changed = await admin.updateOrder(
      detail,
      orderInput(2.01),
      reason: '数量変更',
      idempotencyKey: createOrderIdempotencyKey(),
    );
    expect(changed.orderedWeight, 2.01);
    await expectLater(
      admin.updateOrder(
        detail,
        orderInput(2.01),
        reason: '古い版',
        idempotencyKey: createOrderIdempotencyKey(),
      ),
      throwsA(
        isA<OrderManagementFailure>().having(
          (e) => e.code,
          'code',
          'CONFLICT_STALE',
        ),
      ),
    );
    await expectLater(
      admin.registerOrder(
        orderInput(0),
        idempotencyKey: createOrderIdempotencyKey(),
      ),
      throwsA(
        isA<OrderManagementFailure>().having(
          (e) => e.code,
          'code',
          'VALIDATION_FAILED',
        ),
      ),
    );
    final confirmed = await admin.confirmOrder(
      await admin.loadOrder(order.id),
      reason: '確定検証',
      idempotencyKey: createOrderIdempotencyKey(),
    );
    expect(confirmed.status, OrderStatus.confirmed);
    final cancelled = await admin.cancelOrder(
      await admin.loadOrder(order.id),
      reason: '中止検証',
      idempotencyKey: createOrderIdempotencyKey(),
    );
    expect(cancelled.status, OrderStatus.cancelled);
    final simultaneousKey = createOrderIdempotencyKey();
    final pair = await Future.wait([
      for (var i = 0; i < 2; i++)
        admin.registerOrder(orderInput(4.10), idempotencyKey: simultaneousKey),
    ]);
    expect(pair[0].id, pair[1].id);
  });

  test('S2縦断: 複数受注・予備→部分予約→確定→ToDo・PC→中止', () async {
    final orders = repo('administrator');
    final adminClient = clients.last;
    repo('member');
    final memberClient = clients.last;
    final plans = SupabaseRipeningPlanRepository(memberClient);
    final tasks = SupabaseWorkTaskRepository(memberClient);
    final adminTasks = SupabaseWorkTaskRepository(adminClient);
    final dashboard = DefaultManagerDashboardRepository(
      workTaskRepository: adminTasks,
      orderManagementRepository: orders,
    );
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final customer = await orders.registerCustomer(
      CustomerInput(
        code: 'S2-$suffix',
        name: 'S2架空顧客',
        nickname: '',
        postalCode: '000',
        address: '検証',
      ),
      idempotencyKey: createOrderIdempotencyKey(),
    );
    final destination = await orders.registerDestination(
      DestinationInput(
        customerId: customer.id,
        name: '検証配送先',
        recipientName: '架空',
        postalCode: '000',
        address: '検証',
      ),
      idempotencyKey: createOrderIdempotencyKey(),
    );
    final options = await plans.loadOptions();
    final stock = options.inventories.singleWhere(
      (i) => i.id == '53500000-0000-0000-0000-000000000001',
    );
    expect(stock.availableWeightHundredths, 1000);
    final orderIds = <String>[];
    for (var i = 0; i < 2; i++) {
      final item = await orders.registerOrder(
        OrderInput(
          customerId: customer.id,
          destinationId: destination.id,
          orderedOn: DateTime(2027, 5, 1),
          scheduledShipOn: DateTime(2027, 6, 1),
          varietyId: stock.varietyId,
          gradeId: stock.gradeId,
          orderedWeight: 4,
          notes: '',
        ),
        idempotencyKey: createOrderIdempotencyKey(),
      );
      await orders.confirmOrder(
        await orders.loadOrder(item.id),
        reason: 'S2確認',
        idempotencyKey: createOrderIdempotencyKey(),
      );
      orderIds.add(item.id);
    }
    final input = RipeningPlanInput(
      inventory: stock,
      totalWeightHundredths: 600,
      locationId: options.locations.first.id,
      workerId: options.workers.first.id,
      plannedEthyleneAt: DateTime.utc(2027, 5, 10),
      plannedCompletionAt: DateTime.utc(2027, 5, 20),
      allocations: [
        for (final id in orderIds)
          RipeningAllocationInput(
            type: RipeningAllocationType.order,
            orderId: id,
            weightHundredths: 200,
          ),
        const RipeningAllocationInput(
          type: RipeningAllocationType.reserve,
          weightHundredths: 200,
        ),
      ],
    );
    final operationKey = createRipeningIdempotencyKey();
    final pair = await Future.wait([
      for (var i = 0; i < 2; i++)
        plans.register(input: input, idempotencyKey: operationKey),
    ]);
    expect(pair[0].id, pair[1].id);
    final plan = pair.first;
    expect(
      (await plans.loadOptions()).inventories
          .singleWhere((i) => i.id == stock.id)
          .availableWeightHundredths,
      400,
    );
    await expectLater(
      plans.register(
        input: input,
        idempotencyKey: createRipeningIdempotencyKey(),
      ),
      throwsA(
        isA<RipeningPlanFailure>().having(
          (e) => e.code,
          'code',
          'INVENTORY_UNAVAILABLE',
        ),
      ),
    );
    final confirmed = await plans.confirm(
      ripeningLotId: plan.id,
      expectedVersion: plan.version,
      reason: 'S2確定',
      idempotencyKey: createRipeningIdempotencyKey(),
    );
    expect(confirmed.status, 'confirmed');
    final todo = (await tasks.loadTasks())
        .where((t) => t.targetId == plan.id)
        .toList();
    expect(todo.length, 3);
    expect(
      todo.every(
        (t) => t.weightHundredths == 600 && t.targetDisplayId == plan.displayId,
      ),
      isTrue,
    );
    for (final task in todo) {
      expect((await tasks.loadTask(task.id))?.id, task.id);
    }
    final dbTasks = await adminClient
        .from('work_tasks')
        .select()
        .eq('ripening_lot_id', plan.id);
    final injection = dbTasks.singleWhere(
      (t) => t['task_type'] == 'ethylene_injection',
    );
    final removal = dbTasks.singleWhere(
      (t) => t['task_type'] == 'ethylene_removal_check',
    );
    expect(
      DateTime.parse(removal['scheduled_at'] as String)
          .difference(DateTime.parse(injection['scheduled_at'] as String))
          .inHours,
      168,
    );
    final screen = await dashboard.load();
    expect(screen.tasks.where((t) => t.targetId == plan.id).length, 3);
    expect(
      screen.shortageOrders
          .where((o) => orderIds.contains(o.id))
          .every((o) => o.shortageWeight == 2),
      isTrue,
    );
    final before = await adminClient.rpc(
      'ripening_plan_get',
      params: {'ripening_lot_id_value': plan.id},
    );
    expect(before['allocations'].length, 3);
    await orders.cancelOrder(
      await orders.loadOrder(orderIds.first),
      reason: 'S2中止',
      idempotencyKey: createOrderIdempotencyKey(),
    );
    expect(
      (await tasks.loadTasks()).where((t) => t.targetId == plan.id),
      isEmpty,
    );
    final after = await adminClient.rpc(
      'ripening_plan_get',
      params: {'ripening_lot_id_value': plan.id},
    );
    expect(after['status'], 'draft');
    expect(after['needs_review'], isTrue);
    final cancel = await memberClient.rpc(
      'ripening_plan_cancel',
      params: {
        'req': {
          'meta': {
            'idempotency_key': createRipeningIdempotencyKey(),
            'correlation_id': createRipeningIdempotencyKey(),
          },
          'input': {
            'ripening_lot_id': plan.id,
            'expected_version': after['version'],
            'reason': 'S2片付け',
          },
        },
      },
    );
    expect(cancel['ok'], isTrue);
    expect(
      (await plans.loadOptions()).inventories
          .singleWhere((i) => i.id == stock.id)
          .availableWeightHundredths,
      1000,
    );
    expect(
      (await adminClient
              .from('work_tasks')
              .select()
              .eq('ripening_lot_id', plan.id))
          .every((t) => t['status'] == 'cancelled'),
      isTrue,
    );
  });
}
