import 'dart:convert';
import 'dart:typed_data';

enum CsvDataset {
  inventory('inventory', '在庫'),
  masters('masters', 'マスター'),
  history('history', '変更履歴'),
  orders('orders', '受注'),
  ripening('ripening', '追熟計画・実績'),
  shipments('shipments', '出荷明細');

  const CsvDataset(this.value, this.label);

  final String value;
  final String label;
}

class CsvExportRequest {
  const CsvExportRequest._({required this.dataset, required this.filters});

  factory CsvExportRequest.inventory({
    required String search,
    String? status,
    required String sort,
  }) => CsvExportRequest._(
    dataset: CsvDataset.inventory,
    filters: {
      if (search.trim().isNotEmpty) 'search': search.trim(),
      'status': ?status,
      'sort': sort,
    },
  );

  factory CsvExportRequest.masters({
    required String masterType,
    required String search,
    required String active,
  }) => CsvExportRequest._(
    dataset: CsvDataset.masters,
    filters: {
      'master_type': masterType,
      if (search.trim().isNotEmpty) 'search': search.trim(),
      'active': active,
    },
  );

  factory CsvExportRequest.history({
    String? entityType,
    String? entityId,
    DateTime? fromDate,
    DateTime? toDate,
  }) => CsvExportRequest._(
    dataset: CsvDataset.history,
    filters: {
      'entity_type': ?entityType,
      'entity_id': ?entityId,
      if (fromDate != null) 'from_date': _date(fromDate),
      if (toDate != null) 'to_date': _date(toDate),
    },
  );

  factory CsvExportRequest.business({
    required CsvDataset dataset,
    String search = '',
    String status = 'all',
    String? orderId,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    if (!{
      CsvDataset.orders,
      CsvDataset.ripening,
      CsvDataset.shipments,
    }.contains(dataset)) {
      throw ArgumentError.value(dataset, 'dataset');
    }
    return CsvExportRequest._(
      dataset: dataset,
      filters: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'status': status,
        if (dataset == CsvDataset.shipments && orderId != null)
          'order_id': orderId,
        if (fromDate != null) 'from_date': _date(fromDate),
        if (toDate != null) 'to_date': _date(toDate),
      },
    );
  }

  final CsvDataset dataset;
  final Map<String, Object> filters;

  Map<String, Object> get input => {
    'dataset': dataset.value,
    'filters': filters,
  };

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class CsvExportResult {
  CsvExportResult({
    required this.exportId,
    required this.filename,
    required this.rowCount,
    required this.csv,
    required this.generatedAt,
  }) {
    if (!csv.startsWith('\uFEFF')) {
      throw const FormatException('CSV response must start with one BOM.');
    }
    if (csv.length > 1 && csv.codeUnitAt(1) == 0xFEFF) {
      throw const FormatException(
        'CSV response must not contain a double BOM.',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9._-]+\.csv$').hasMatch(filename)) {
      throw const FormatException('CSV filename is invalid.');
    }
  }

  final String exportId;
  final String filename;
  final int rowCount;
  final String csv;
  final DateTime generatedAt;

  Uint8List get bytes => Uint8List.fromList(utf8.encode(csv));

  factory CsvExportResult.fromMap(Map<String, dynamic> value) =>
      CsvExportResult(
        exportId: value['export_id'] as String,
        filename: value['filename'] as String,
        rowCount: value['row_count'] as int,
        csv: value['csv'] as String,
        generatedAt: DateTime.parse(value['generated_at'] as String),
      );
}

class CsvExportFailure implements Exception {
  const CsvExportFailure({
    required this.message,
    this.code,
    this.correlationId,
    this.retryable = false,
  });

  final String message;
  final String? code;
  final String? correlationId;
  final bool retryable;

  bool get isPermissionDenied =>
      code == 'AUTH_REQUIRED' || code == 'AUTH_FORBIDDEN';
}

abstract interface class CsvExportRepository {
  Future<CsvExportResult> export(CsvExportRequest request);
}
