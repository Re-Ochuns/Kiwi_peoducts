import 'package:kiwi_inventory/ripening/ripening_plan_repository.dart';

class FakeRipeningPlanRepository implements RipeningPlanRepository {
  FakeRipeningPlanRepository({
    RipeningPlanOptions? options,
    this.loadFailures = 0,
    this.confirmFailures = 0,
  }) : options = options ?? testRipeningOptions;

  final RipeningPlanOptions options;
  int loadFailures;
  int confirmFailures;
  int loadCalls = 0;
  int registerCalls = 0;
  int updateCalls = 0;
  int confirmCalls = 0;
  RipeningPlanInput? lastInput;
  final List<String> registerKeys = [];
  final List<String> confirmKeys = [];

  @override
  Future<RipeningPlanOptions> loadOptions() async {
    loadCalls++;
    if (loadFailures > 0) {
      loadFailures--;
      throw const RipeningPlanFailure(
        message: '選択肢を読み込めませんでした。',
        retryable: true,
      );
    }
    return options;
  }

  @override
  Future<RipeningPlanResult> register({
    required RipeningPlanInput input,
    required String idempotencyKey,
  }) async {
    registerCalls++;
    lastInput = input;
    registerKeys.add(idempotencyKey);
    return _result(version: 1, status: 'draft', input: input);
  }

  @override
  Future<RipeningPlanResult> update({
    required RipeningPlanInput input,
    required String ripeningLotId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  }) async {
    updateCalls++;
    lastInput = input;
    return _result(version: expectedVersion + 1, status: 'draft', input: input);
  }

  @override
  Future<RipeningPlanResult> confirm({
    required String ripeningLotId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  }) async {
    confirmCalls++;
    confirmKeys.add(idempotencyKey);
    if (confirmFailures > 0) {
      confirmFailures--;
      throw const RipeningPlanFailure(
        message: '通信状況を確認して再試行してください。',
        code: 'NETWORK_FAILED',
        correlationId: 'correlation-1',
        retryable: true,
      );
    }
    return _result(
      version: expectedVersion + 1,
      status: 'confirmed',
      input: lastInput!,
    );
  }
}

RipeningPlanResult _result({
  required int version,
  required String status,
  required RipeningPlanInput input,
}) => RipeningPlanResult(
  id: 'ripening-lot-1',
  displayId: '追熟-2026-001',
  status: status,
  version: version,
  plannedEthyleneAt: input.plannedEthyleneAt,
  plannedCompletionAt: input.plannedCompletionAt,
  idempotentReplay: false,
);

final testRipeningOptions = RipeningPlanOptions(
  inventories: const [
    RipeningInventoryOption(
      id: 'container-1',
      displayId: '在庫-2026-001',
      varietyId: 'variety-1',
      varietyLabel: 'hayward　ヘイワード',
      gradeId: 'grade-m',
      gradeLabel: 'M',
      availableWeightHundredths: 1000,
    ),
  ],
  orders: [
    RipeningOrderOption(
      id: 'order-1',
      orderNumber: 'ORD-2026-001',
      customerLabel: '青果店A',
      varietyId: 'variety-1',
      gradeId: 'grade-m',
      availableWeightHundredths: 800,
      scheduledShipDate: DateTime(2026, 9, 20),
    ),
  ],
  locations: const [
    RipeningReferenceOption(id: 'location-1', label: 'ripening-01　第1追熟庫'),
  ],
  workers: const [RipeningReferenceOption(id: 'worker-1', label: 'W01　岡本')],
  rules: const [
    RipeningRuleOption(
      harvestYear: 2026,
      harvestMonth: 9,
      varietyId: 'variety-1',
      ethyleneHours: 72,
      restDays: 7,
    ),
  ],
);
