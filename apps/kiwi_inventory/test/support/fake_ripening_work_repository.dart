import 'package:kiwi_inventory/ripening_work/ripening_work_repository.dart';

class FakeRipeningWorkRepository implements RipeningWorkRepository {
  FakeRipeningWorkRepository({
    RipeningWorkDetails? details,
    this.loadFailures = 0,
    this.completeFailures = 0,
  }) : details = details ?? testRipeningWorkDetails;

  final RipeningWorkDetails details;
  int loadFailures;
  int completeFailures;
  int loadCalls = 0;
  int completeCalls = 0;
  RipeningWorkType? lastType;
  RipeningWorkInput? lastInput;
  final List<String> completionKeys = [];

  @override
  Future<RipeningWorkDetails> load(String ripeningLotId) async {
    loadCalls++;
    if (loadFailures > 0) {
      loadFailures--;
      throw const RipeningWorkFailure(
        message: '追熟作業を読み込めませんでした。',
        code: 'NETWORK_FAILED',
        retryable: true,
      );
    }
    return details;
  }

  @override
  Future<RipeningWorkCompletion> complete({
    required RipeningWorkType type,
    required RipeningWorkInput input,
    required String idempotencyKey,
  }) async {
    completeCalls++;
    lastType = type;
    lastInput = input;
    completionKeys.add(idempotencyKey);
    if (completeFailures > 0) {
      completeFailures--;
      throw const RipeningWorkFailure(
        message: '完了結果を確認できませんでした。',
        code: 'TIMEOUT',
        correlationId: 'correlation-1',
        retryable: true,
      );
    }
    return RipeningWorkCompletion(
      displayId: details.displayId,
      version: details.version + 1,
      status: 'in_progress',
      actualAt: input.actualAt,
      idempotentReplay: false,
    );
  }
}

final testRipeningWorkDetails = RipeningWorkDetails(
  id: 'ripening-1',
  displayId: '追熟-2026-001',
  version: 2,
  status: 'confirmed',
  weightHundredths: 2050,
  locationId: 'location-1',
  workerId: 'worker-1',
  plannedEthyleneAt: DateTime(2026, 9, 12, 9),
  plannedCompletionAt: DateTime(2026, 9, 19, 9),
  results: [
    RipeningWorkRecord(
      type: 'ethylene_injection',
      actualAt: DateTime(2026, 9, 12, 9),
    ),
    RipeningWorkRecord(
      type: 'ethylene_removal_check',
      actualAt: DateTime(2026, 9, 13, 9),
      restStartedAt: DateTime(2026, 9, 13, 10),
    ),
  ],
  locations: const [
    RipeningWorkOption(id: 'location-1', label: 'ripening-01　第1追熟庫'),
    RipeningWorkOption(id: 'location-2', label: 'ripening-02　第2追熟庫'),
  ],
  workers: const [
    RipeningWorkOption(id: 'worker-1', label: 'W01　岡本'),
    RipeningWorkOption(id: 'worker-2', label: 'W02　佐藤'),
  ],
);
