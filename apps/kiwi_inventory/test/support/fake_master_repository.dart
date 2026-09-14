import 'package:kiwi_inventory/master/master_repository.dart';

class FakeMasterRepository implements MasterRepository {
  FakeMasterRepository({bool canManage = true, this.nextFailure})
    : catalog = sampleMasterCatalog(canManage: canManage);

  final MasterCatalog catalog;
  MasterFailure? nextFailure;
  MasterFailure? nextLoadFailure;
  int loadCalls = 0;
  int registerCalls = 0;
  int updateCalls = 0;
  int setActiveCalls = 0;
  MasterType? lastType;
  MasterRecord? lastRecord;
  Map<String, Object>? lastValues;
  String? lastReason;
  String? lastIdempotencyKey;
  bool? lastActive;

  @override
  Future<MasterCatalog> loadCatalog() async {
    loadCalls++;
    final failure = nextLoadFailure;
    nextLoadFailure = null;
    if (failure != null) throw failure;
    return catalog;
  }

  @override
  Future<MasterMutationResult> register({
    required MasterType type,
    required Map<String, Object> values,
    required String reason,
    required String idempotencyKey,
  }) async {
    registerCalls++;
    lastType = type;
    lastValues = values;
    lastReason = reason;
    lastIdempotencyKey = idempotencyKey;
    _throwNextFailure();
    return MasterMutationResult(
      record: MasterRecord(
        type: type,
        id: 'new-master',
        values: values,
        isActive: true,
        version: 1,
        updatedAt: DateTime(2026, 9, 11),
      ),
      idempotentReplay: false,
    );
  }

  @override
  Future<MasterMutationResult> update({
    required MasterRecord record,
    required Map<String, Object> values,
    required String reason,
    required String idempotencyKey,
  }) async {
    updateCalls++;
    lastRecord = record;
    lastValues = values;
    lastReason = reason;
    lastIdempotencyKey = idempotencyKey;
    _throwNextFailure();
    return MasterMutationResult(
      record: MasterRecord(
        type: record.type,
        id: record.id,
        values: {...record.values, ...values},
        isActive: record.isActive,
        version: record.version + 1,
        updatedAt: DateTime(2026, 9, 11),
      ),
      idempotentReplay: false,
    );
  }

  @override
  Future<MasterMutationResult> setActive({
    required MasterRecord record,
    required bool active,
    required String reason,
    required String idempotencyKey,
  }) async {
    setActiveCalls++;
    lastRecord = record;
    lastActive = active;
    lastReason = reason;
    lastIdempotencyKey = idempotencyKey;
    _throwNextFailure();
    return MasterMutationResult(
      record: MasterRecord(
        type: record.type,
        id: record.id,
        values: record.values,
        isActive: active,
        version: record.version + 1,
        updatedAt: DateTime(2026, 9, 11),
      ),
      idempotentReplay: false,
    );
  }

  void _throwNextFailure() {
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) throw failure;
  }
}

MasterCatalog sampleMasterCatalog({required bool canManage}) {
  MasterRecord record(
    MasterType type,
    String id,
    Map<String, Object?> values, {
    bool active = true,
    int version = 1,
  }) => MasterRecord(
    type: type,
    id: id,
    values: values,
    isActive: active,
    version: version,
    updatedAt: DateTime(2026, 9, 11, 9),
  );

  return MasterCatalog(
    canManage: canManage,
    records: {
      MasterType.variety: [
        record(MasterType.variety, 'variety-1', {
          'code': 'hayward',
          'name': 'ヘイワード',
        }),
        record(
          MasterType.variety,
          'variety-2',
          {'code': 'koryoku', 'name': '香緑'},
          active: false,
          version: 2,
        ),
      ],
      MasterType.grade: [
        record(MasterType.grade, 'grade-1', {'code': 'L', 'display_order': 5}),
        record(MasterType.grade, 'grade-2', {'code': 'M', 'display_order': 6}),
      ],
      MasterType.orchard: [
        record(MasterType.orchard, 'orchard-1', {
          'code': 'farm-01',
          'name': '第一農園',
        }),
      ],
      MasterType.orchardPlot: [
        record(MasterType.orchardPlot, 'plot-1', {
          'orchard_id': 'orchard-1',
          'code': 'plot-a',
          'name': 'A区画',
        }),
      ],
      MasterType.tree: [
        record(MasterType.tree, 'tree-1', {
          'plot_id': 'plot-1',
          'variety_id': 'variety-1',
          'code': 'tree-01',
          'name': '樹体1号',
        }),
      ],
      MasterType.supplier: [
        record(MasterType.supplier, 'supplier-1', {
          'management_code': 'supplier-01',
          'name': '仕入先A',
        }),
      ],
      MasterType.worker: [
        record(MasterType.worker, 'worker-1', {
          'code': 'worker-01',
          'display_name': '作業者A',
        }),
      ],
      MasterType.storageLocation: [
        record(MasterType.storageLocation, 'location-1', {
          'code': 'cold-01',
          'name': '第一冷蔵庫',
          'location_type': 'cold_storage',
        }),
      ],
      MasterType.sortingDeadlineRule: [
        record(MasterType.sortingDeadlineRule, 'rule-1', {
          'harvest_year': 2026,
          'harvest_month': 9,
          'variety_id': 'variety-1',
          'deadline_days': 30,
        }),
      ],
      MasterType.ripeningRule: [
        record(MasterType.ripeningRule, 'ripening-rule-1', {
          'harvest_year': 2026,
          'harvest_month': 9,
          'variety_id': 'variety-1',
          'ethylene_temperature': 20.0,
          'ethylene_hours': 72.0,
          'rest_temperature': 15.0,
          'rest_days': 7.0,
          'shippable_days': 5.0,
          'best_before_days': 7.0,
        }),
      ],
    },
  );
}
