import 'package:kiwi_inventory/shipping/shipping_repository.dart';

class FakeShippingRepository implements ShippingRepository {
  FakeShippingRepository({
    this.loadFailures = 0,
    this.confirmFailures = 0,
    this.cancelFailures = 0,
  });

  int detailFailures = 0;
  List<ShippingOrderSummary>? orderList;
  int loadFailures;
  int confirmFailures;
  int cancelFailures;
  int loadOrdersCalls = 0;
  int loadOrderCalls = 0;
  int confirmCalls = 0;
  int cancelCalls = 0;
  int shippedWeightHundredths = 250;
  List<ShippingContainer> containers = testShippingContainers;
  Map<String, int> allocations = {'lot-1': 600, 'lot-2': 500};
  final List<String> confirmKeys = [];
  final List<String> cancelKeys = [];
  ShippingConfirmInput? lastInput;
  final List<ShipmentRecord> shipments = [testShipment];

  ShippingOrderSummary get order => ShippingOrderSummary(
    id: 'order-1',
    number: '受注-2026-001',
    customer: '青果店A',
    scheduledShipOn: DateTime(2026, 9, 13),
    variety: 'ヘイワード',
    grade: 'M',
    orderedWeightHundredths: 1000,
    shippedWeightHundredths: shippedWeightHundredths,
    status: shippedWeightHundredths >= 1000
        ? 'shipped'
        : shippedWeightHundredths > 0
        ? 'partially_shipped'
        : 'confirmed',
    version: 3 + confirmCalls + cancelCalls,
  );

  @override
  Future<List<ShippingOrderSummary>> loadOrders() async {
    loadOrdersCalls++;
    if (loadFailures > 0) {
      loadFailures--;
      throw const ShippingFailure(message: '出荷予定を読み込めませんでした。', retryable: true);
    }
    return orderList ?? [order];
  }

  @override
  Future<ShippingOrderDetail> loadOrder(String orderId) async {
    loadOrderCalls++;
    if (detailFailures > 0) {
      detailFailures--;
      throw const ShippingFailure(message: '詳細を取得できませんでした。', retryable: true);
    }
    return ShippingOrderDetail(
      order: order,
      destination: '本店　青果店A 御中　〒790-0001　愛媛県松山市一番町1-1',
      containers: containers,
      remainingAllocationHundredths: allocations,
      shipments: List.of(shipments),
      workers: const [
        ShippingWorker(id: 'worker-1', label: 'W01　岡本'),
        ShippingWorker(id: 'worker-2', label: 'W02　佐藤'),
      ],
    );
  }

  @override
  Future<ShipmentCompletion> confirm({
    required ShippingConfirmInput input,
    required String idempotencyKey,
  }) async {
    confirmCalls++;
    confirmKeys.add(idempotencyKey);
    lastInput = input;
    if (confirmFailures > 0) {
      confirmFailures--;
      throw const ShippingFailure(
        message: '出荷結果を確認できませんでした。',
        code: 'TIMEOUT',
        correlationId: 'correlation-1',
        retryable: true,
      );
    }
    final weight = input.lines.fold<int>(
      0,
      (sum, line) => sum + line.weightHundredths,
    );
    final result = ShipmentRecord(
      id: 'shipment-${shipments.length + 1}',
      displayId: '出荷-2026-${(shipments.length + 1).toString().padLeft(3, '0')}',
      version: 1,
      status: 'confirmed',
      shippedAt: input.shippedAt,
      totalWeightHundredths: weight,
      lines: [
        for (final line in input.lines)
          ShipmentLine(
            containerId: line.containerId,
            weightHundredths: line.weightHundredths,
          ),
      ],
    );
    shipments.insert(0, result);
    shippedWeightHundredths += weight;
    return ShipmentCompletion(shipment: result, idempotentReplay: false);
  }

  @override
  Future<ShipmentCompletion> cancel({
    required String shipmentId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  }) async {
    cancelCalls++;
    cancelKeys.add(idempotencyKey);
    if (cancelFailures > 0) {
      cancelFailures--;
      throw const ShippingFailure(
        message: '取消結果を確認できませんでした。',
        code: 'TIMEOUT',
        correlationId: 'correlation-2',
        retryable: true,
      );
    }
    final index = shipments.indexWhere((shipment) => shipment.id == shipmentId);
    final source = shipments[index];
    final cancelled = ShipmentRecord(
      id: source.id,
      displayId: source.displayId,
      version: source.version + 1,
      status: 'cancelled',
      shippedAt: source.shippedAt,
      totalWeightHundredths: source.totalWeightHundredths,
      lines: source.lines,
      cancellationReason: reason,
    );
    shipments[index] = cancelled;
    shippedWeightHundredths -= source.totalWeightHundredths;
    return ShipmentCompletion(shipment: cancelled, idempotentReplay: false);
  }
}

final testShippingContainers = [
  ShippingContainer(
    id: 'container-1',
    displayId: '追熟-2026-001-1',
    ripeningLotId: 'lot-1',
    version: 2,
    currentWeightHundredths: 600,
    availableWeightHundredths: 600,
    remainingUseType: 'order',
    shippableUntil: DateTime(2026, 9, 14, 12),
    bestBeforeAt: DateTime(2026, 9, 15, 12),
  ),
  ShippingContainer(
    id: 'container-2',
    displayId: '追熟-2026-002-1',
    ripeningLotId: 'lot-2',
    version: 1,
    currentWeightHundredths: 500,
    availableWeightHundredths: 500,
    remainingUseType: 'mixed',
    shippableUntil: DateTime(2026, 9, 14, 15),
    bestBeforeAt: DateTime(2026, 9, 15, 15),
  ),
];

final testShipment = ShipmentRecord(
  id: 'shipment-1',
  displayId: '出荷-2026-001',
  version: 1,
  status: 'confirmed',
  shippedAt: DateTime(2026, 9, 13, 8),
  totalWeightHundredths: 250,
  lines: const [
    ShipmentLine(containerId: 'container-1', weightHundredths: 250),
  ],
);
