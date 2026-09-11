import 'package:kiwi_inventory/csv_export/csv_export_repository.dart';

class FakeCsvExportRepository implements CsvExportRepository {
  int calls = 0;
  CsvExportRequest? lastRequest;
  CsvExportFailure? nextFailure;

  @override
  Future<CsvExportResult> export(CsvExportRequest request) async {
    calls++;
    lastRequest = request;
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) throw failure;
    return CsvExportResult(
      exportId: '49000000-0000-0000-0000-000000000001',
      filename: '${request.dataset.value}_20260912T010203_49000000.csv',
      rowCount: 1,
      csv: '\uFEFF"見出し"\r\n"値"\r\n',
      generatedAt: DateTime.utc(2026, 9, 12, 1, 2, 3),
    );
  }
}
