import 'package:flutter/material.dart';

import 'csv_downloader.dart';
import 'csv_export_dialog.dart';
import 'csv_export_repository.dart';

class BusinessCsvButton extends StatelessWidget {
  const BusinessCsvButton({
    required this.repository,
    required this.request,
    this.enabled = true,
    this.downloader = downloadCsv,
    super.key,
  });
  final CsvExportRepository repository;
  final CsvExportRequest request;
  final bool enabled;
  final CsvDownloader downloader;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: !enabled
        ? null
        : () async {
            final result = await showCsvExportDialog(
              context: context,
              repository: repository,
              initialRequest: request,
              availableDatasets: {request.dataset},
              downloader: downloader,
            );
            if (result == null || !context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  result.rowCount == 0
                      ? '該当データはありません。ヘッダーのみのCSVの保存を開始しました。'
                      : '${result.rowCount}件のCSVの保存を開始しました。',
                ),
              ),
            );
          },
    child: const Text('CSV出力'),
  );
}
