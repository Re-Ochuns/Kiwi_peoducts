import 'package:flutter/material.dart';
import 'package:kiwi_inventory/csv_export/business_csv_button.dart';
import 'package:kiwi_inventory/csv_export/csv_export_repository.dart';
import 'package:kiwi_inventory/csv_export/supabase_csv_export_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Synthetic local browser acceptance only; never used by the production entry.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final client = SupabaseClient(
    'http://127.0.0.1:56980',
    'synthetic-local-key',
    accessToken: () async => const String.fromEnvironment('LOCAL_TEST_JWT'),
  );
  final repository = SupabaseCsvExportRepository(client);
  runApp(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final dataset in [
                CsvDataset.orders,
                CsvDataset.ripening,
                CsvDataset.shipments,
              ])
                Column(
                  children: [
                    Text(dataset.label),
                    BusinessCsvButton(
                      repository: repository,
                      request: CsvExportRequest.business(dataset: dataset),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
