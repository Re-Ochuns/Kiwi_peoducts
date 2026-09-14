enum MasterType {
  variety,
  grade,
  orchard,
  orchardPlot,
  tree,
  supplier,
  worker,
  storageLocation,
  sortingDeadlineRule,
  ripeningRule,
}

extension MasterTypeDefinition on MasterType {
  String get rpcValue => switch (this) {
    MasterType.variety => 'variety',
    MasterType.grade => 'grade',
    MasterType.orchard => 'orchard',
    MasterType.orchardPlot => 'orchard_plot',
    MasterType.tree => 'tree',
    MasterType.supplier => 'supplier',
    MasterType.worker => 'worker',
    MasterType.storageLocation => 'storage_location',
    MasterType.sortingDeadlineRule => 'sorting_deadline_rule',
    MasterType.ripeningRule => 'ripening_rule',
  };

  String get tableName => switch (this) {
    MasterType.variety => 'varieties',
    MasterType.grade => 'grades',
    MasterType.orchard => 'orchards',
    MasterType.orchardPlot => 'orchard_plots',
    MasterType.tree => 'trees',
    MasterType.supplier => 'suppliers',
    MasterType.worker => 'workers',
    MasterType.storageLocation => 'storage_locations',
    MasterType.sortingDeadlineRule => 'sorting_deadline_rules',
    MasterType.ripeningRule => 'ripening_rules',
  };

  String get label => switch (this) {
    MasterType.variety => '品種',
    MasterType.grade => '等級',
    MasterType.orchard => '農園',
    MasterType.orchardPlot => '区画',
    MasterType.tree => '樹体',
    MasterType.supplier => '仕入先',
    MasterType.worker => '作業者',
    MasterType.storageLocation => '保管場所',
    MasterType.sortingDeadlineRule => '選果期限ルール',
    MasterType.ripeningRule => '追熟マスター',
  };

  String get selectColumns => switch (this) {
    MasterType.variety => 'id,code,name,is_active,version,updated_at',
    MasterType.grade => 'id,code,display_order,is_active,version,updated_at',
    MasterType.orchard => 'id,code,name,is_active,version,updated_at',
    MasterType.orchardPlot =>
      'id,orchard_id,code,name,is_active,version,updated_at',
    MasterType.tree =>
      'id,plot_id,variety_id,code,name,is_active,version,updated_at',
    MasterType.supplier =>
      'id,management_code,name,is_active,version,updated_at',
    MasterType.worker => 'id,code,display_name,is_active,version,updated_at',
    MasterType.storageLocation =>
      'id,code,name,location_type,is_active,version,updated_at',
    MasterType.sortingDeadlineRule => 'id,harvest_year,harvest_month,variety_id,deadline_days,is_active,version,updated_at',
    MasterType.ripeningRule => 'id,harvest_month,variety_id,ethylene_temperature,ethylene_hours,rest_temperature,rest_days,shippable_days,best_before_days,is_active,version,updated_at',
  };

  bool get canRegister => this != MasterType.grade;
}

class MasterRecord {
  MasterRecord({
    required this.type,
    required this.id,
    required this.values,
    required this.isActive,
    required this.version,
    required this.updatedAt,
  });

  final MasterType type;
  final String id;
  final Map<String, Object?> values;
  final bool isActive;
  final int version;
  final DateTime? updatedAt;

  String value(String key) => values[key]?.toString() ?? '';

  String get primaryText => switch (type) {
    MasterType.supplier => value('management_code'),
    MasterType.sortingDeadlineRule =>
      '${value('harvest_year')}年${value('harvest_month')}月',
    MasterType.ripeningRule => '${value('harvest_month')}月',
    _ => value('code'),
  };

  String get secondaryText => switch (type) {
    MasterType.grade => '表示順 ${value('display_order')}',
    MasterType.worker => value('display_name'),
    MasterType.storageLocation => value('name'),
    MasterType.sortingDeadlineRule => '${value('deadline_days')}日',
    MasterType.ripeningRule =>
      'エチレン ${_displayNumber(values['ethylene_hours'])}時間・寝かせ ${_displayNumber(values['rest_days'])}日',
    _ => value('name'),
  };

  static String _displayNumber(Object? raw) {
    if (raw is num && raw == raw.roundToDouble()) return raw.toInt().toString();
    return raw?.toString() ?? '';
  }

  String get searchText => values.values.join(' ').toLowerCase();
}

class MasterCatalog {
  const MasterCatalog({required this.records, required this.canManage});

  final Map<MasterType, List<MasterRecord>> records;
  final bool canManage;

  List<MasterRecord> of(MasterType type) => records[type] ?? const [];

  MasterRecord? find(MasterType type, String? id) {
    if (id == null) return null;
    for (final record in of(type)) {
      if (record.id == id) return record;
    }
    return null;
  }

  String relatedLabel(MasterType type, String id) {
    final record = find(type, id);
    if (record == null) return '不明';
    final secondary = record.secondaryText;
    return secondary.isEmpty
        ? record.primaryText
        : '${record.primaryText}　$secondary';
  }
}

class MasterMutationResult {
  const MasterMutationResult({
    required this.record,
    required this.idempotentReplay,
  });

  final MasterRecord record;
  final bool idempotentReplay;
}

class MasterFailure implements Exception {
  const MasterFailure({
    required this.message,
    this.code,
    this.field,
    this.reason,
    this.correlationId,
    this.retryable = false,
  });

  final String message;
  final String? code;
  final String? field;
  final String? reason;
  final String? correlationId;
  final bool retryable;

  bool get isConflict => code == 'CONFLICT_STALE';
}

abstract interface class MasterRepository {
  Future<MasterCatalog> loadCatalog();

  Future<MasterMutationResult> register({
    required MasterType type,
    required Map<String, Object> values,
    required String reason,
    required String idempotencyKey,
  });

  Future<MasterMutationResult> update({
    required MasterRecord record,
    required Map<String, Object> values,
    required String reason,
    required String idempotencyKey,
  });

  Future<MasterMutationResult> setActive({
    required MasterRecord record,
    required bool active,
    required String reason,
    required String idempotencyKey,
  });
}
