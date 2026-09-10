class MasterOption {
  const MasterOption({
    required this.id,
    required this.label,
    this.businessName,
    this.parentId,
    this.varietyId,
  });

  final String id;
  final String label;
  final String? businessName;
  final String? parentId;
  final String? varietyId;

  String get name => businessName ?? label;
}

class ReceivingMasters {
  const ReceivingMasters({
    required this.orchards,
    required this.plots,
    required this.trees,
    required this.suppliers,
    required this.varieties,
    required this.workers,
  });

  final List<MasterOption> orchards;
  final List<MasterOption> plots;
  final List<MasterOption> trees;
  final List<MasterOption> suppliers;
  final List<MasterOption> varieties;
  final List<MasterOption> workers;
}

enum ReceivingSourceType { harvest, purchase }

class ReceivingInput {
  const ReceivingInput({
    required this.sourceType,
    required this.receivedDate,
    required this.originName,
    required this.varietyId,
    required this.totalWeightKg,
    required this.containerCount,
    required this.workerId,
    this.orchardId,
    this.plotId,
    this.treeId,
    this.supplierId,
    this.supplierReference,
  });

  final ReceivingSourceType sourceType;
  final String receivedDate;
  final String? orchardId;
  final String? plotId;
  final String? treeId;
  final String? supplierId;
  final String? supplierReference;
  final String originName;
  final String varietyId;
  final double totalWeightKg;
  final int containerCount;
  final String workerId;

  Map<String, Object> toRpcInput() {
    final input = <String, Object>{
      'source_type': sourceType == ReceivingSourceType.harvest
          ? 'harvest'
          : 'purchase',
      'received_date': receivedDate,
      'origin_name': originName.trim(),
      'variety_id': varietyId,
      'total_weight_kg': totalWeightKg,
      'container_count': containerCount,
      'worker_id': workerId,
    };
    if (sourceType == ReceivingSourceType.harvest) {
      input.addAll({
        'orchard_id': orchardId!,
        'plot_id': plotId!,
        'tree_id': treeId!,
      });
    } else {
      input.addAll({
        'supplier_id': supplierId!,
        'supplier_reference': supplierReference!.trim(),
      });
    }
    return input;
  }

  String get signature => toRpcInput().toString();
}

class ReceivingResult {
  const ReceivingResult({
    required this.receivingLotId,
    required this.displayId,
    required this.receivedDate,
    required this.sortingDueDate,
    required this.version,
    required this.idempotentReplay,
  });

  final String receivingLotId;
  final String displayId;
  final String receivedDate;
  final String sortingDueDate;
  final int version;
  final bool idempotentReplay;
}

class ReceivingFailure implements Exception {
  const ReceivingFailure({
    required this.message,
    this.field,
    this.reason,
    this.correlationId,
    this.retryable = false,
  });

  final String message;
  final String? field;
  final String? reason;
  final String? correlationId;
  final bool retryable;
}

abstract interface class ReceivingRepository {
  Future<ReceivingMasters> loadMasters();

  Future<ReceivingResult> register({
    required ReceivingInput input,
    required String idempotencyKey,
  });

  Future<ReceivingResult> correct({
    required ReceivingInput input,
    required String receivingLotId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  });
}
