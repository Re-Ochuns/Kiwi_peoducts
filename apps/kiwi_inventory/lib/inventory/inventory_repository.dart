enum InventoryStatus {
  awaitingLabel('awaiting_label', 'ラベル待ち'),
  coldStorage('cold_storage', '冷蔵保管'),
  ethyleneProcessing('ethylene_processing', 'エチレン処理中'),
  resting('resting', '静置中'),
  awaitingRipenessCheck('awaiting_ripeness_check', '追熟確認待ち'),
  shippable('shippable', '出荷可能'),
  shipped('shipped', '出荷済み'),
  expired('expired', '期限切れ');

  const InventoryStatus(this.value, this.label);

  final String value;
  final String label;

  static InventoryStatus fromValue(String value) => values.firstWhere(
    (status) => status.value == value,
    orElse: () => InventoryStatus.awaitingLabel,
  );
}

enum InventorySort {
  updatedDescending('更新が新しい順'),
  displayIdAscending('在庫ID順'),
  currentWeightDescending('現在量が多い順');

  const InventorySort(this.label);

  final String label;
}

class InventoryQuery {
  const InventoryQuery({
    this.search = '',
    this.status,
    this.sort = InventorySort.updatedDescending,
    this.page = 0,
    this.pageSize = 20,
  });

  final String search;
  final InventoryStatus? status;
  final InventorySort sort;
  final int page;
  final int pageSize;

  InventoryQuery copyWith({
    String? search,
    InventoryStatus? status,
    bool clearStatus = false,
    InventorySort? sort,
    int? page,
    int? pageSize,
  }) => InventoryQuery(
    search: search ?? this.search,
    status: clearStatus ? null : status ?? this.status,
    sort: sort ?? this.sort,
    page: page ?? this.page,
    pageSize: pageSize ?? this.pageSize,
  );
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.displayId,
    required this.varietyName,
    required this.gradeCode,
    required this.originalWeightHundredths,
    required this.currentWeightHundredths,
    required this.reservedWeightHundredths,
    required this.status,
    required this.locationCode,
    required this.locationName,
    required this.updatedAt,
  });

  final String id;
  final String displayId;
  final String varietyName;
  final String gradeCode;
  final int originalWeightHundredths;
  final int currentWeightHundredths;
  final int reservedWeightHundredths;
  final InventoryStatus status;
  final String? locationCode;
  final String? locationName;
  final DateTime updatedAt;

  int get availableWeightHundredths =>
      currentWeightHundredths - reservedWeightHundredths;

  String get locationLabel {
    if (locationName == null) return '未設定';
    if (locationCode == null || locationCode!.isEmpty) return locationName!;
    return '$locationCode　$locationName';
  }
}

class InventoryPageData {
  const InventoryPageData({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  final List<InventoryItem> items;
  final int totalCount;
  final int page;
  final int pageSize;

  bool get hasPrevious => page > 0;
  bool get hasNext => (page + 1) * pageSize < totalCount;
  int get firstItemNumber => items.isEmpty ? 0 : page * pageSize + 1;
  int get lastItemNumber => page * pageSize + items.length;
}

class InventorySource {
  const InventorySource({
    required this.sortingDisplayId,
    required this.sortedOn,
    required this.sortingWorkerName,
    required this.receivingDisplayId,
    required this.receivedOn,
    required this.sourceType,
    required this.originName,
  });

  final String sortingDisplayId;
  final DateTime sortedOn;
  final String sortingWorkerName;
  final String receivingDisplayId;
  final DateTime receivedOn;
  final String sourceType;
  final String originName;

  String get sourceTypeLabel => sourceType == 'harvest' ? '収穫' : '仕入れ';
}

class InventoryHistoryEntry {
  const InventoryHistoryEntry({
    required this.operation,
    required this.reason,
    required this.changedAt,
    required this.changedBy,
  });

  final String operation;
  final String reason;
  final DateTime changedAt;
  final String changedBy;

  String get operationLabel => switch (operation) {
    'create' => '作成',
    'update' => '更新',
    'transition' => '状態変更',
    'correct' => '訂正',
    _ => operation,
  };
}

class InventoryDetailData {
  const InventoryDetailData({
    required this.item,
    required this.source,
    required this.history,
    required this.canViewHistory,
  });

  final InventoryItem item;
  final InventorySource source;
  final List<InventoryHistoryEntry> history;
  final bool canViewHistory;
}

class InventoryFailure implements Exception {
  const InventoryFailure({
    required this.message,
    this.code,
    this.retryable = false,
  });

  final String message;
  final String? code;
  final bool retryable;

  bool get isPermissionDenied =>
      code == 'AUTH_REQUIRED' || code == 'AUTH_FORBIDDEN';
}

abstract interface class InventoryRepository {
  Future<InventoryPageData> loadPage(InventoryQuery query);

  Future<InventoryDetailData> loadDetail(String containerId);
}

String formatInventoryWeight(int hundredths) =>
    (hundredths / 100).toStringAsFixed(2);
