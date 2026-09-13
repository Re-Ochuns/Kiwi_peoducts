import 'package:flutter/material.dart';

import 'csv_downloader.dart';
import 'csv_export_repository.dart';

Future<CsvExportResult?> showCsvExportDialog({
  required BuildContext context,
  required CsvExportRepository repository,
  required CsvExportRequest initialRequest,
  required Set<CsvDataset> availableDatasets,
  CsvDownloader downloader = downloadCsv,
}) => showDialog<CsvExportResult>(
  context: context,
  barrierDismissible: false,
  builder: (context) => CsvExportDialog(
    repository: repository,
    initialRequest: initialRequest,
    availableDatasets: availableDatasets,
    downloader: downloader,
  ),
);

class CsvExportDialog extends StatefulWidget {
  const CsvExportDialog({
    required this.repository,
    required this.initialRequest,
    required this.availableDatasets,
    required this.downloader,
    super.key,
  });

  final CsvExportRepository repository;
  final CsvExportRequest initialRequest;
  final Set<CsvDataset> availableDatasets;
  final CsvDownloader downloader;

  @override
  State<CsvExportDialog> createState() => _CsvExportDialogState();
}

class _CsvExportDialogState extends State<CsvExportDialog> {
  static const _inventoryStatuses = <String, String>{
    '': 'すべて',
    'awaiting_label': 'ラベル待ち',
    'cold_storage': '冷蔵保管',
    'ethylene_processing': 'エチレン処理中',
    'resting': '静置中',
    'awaiting_ripeness_check': '追熟確認待ち',
    'shippable': '出荷可能',
    'shipped': '出荷済み',
    'expired': '期限切れ',
  };
  static const _inventorySorts = <String, String>{
    'updated_desc': '更新が新しい順',
    'display_id_asc': '在庫ID順',
    'current_weight_desc': '現在量が多い順',
  };
  static const _masterTypes = <String, String>{
    'variety': '品種',
    'grade': '等級',
    'orchard': '農園',
    'orchard_plot': '区画',
    'tree': '樹体',
    'supplier': '仕入先',
    'worker': '作業者',
    'storage_location': '保管場所',
    'sorting_deadline_rule': '選果期限ルール',
  };
  static const _activeFilters = <String, String>{
    'active': '有効のみ',
    'inactive': '無効のみ',
    'all': 'すべて',
  };
  static const _historyTypes = <String, String>{
    '': 'すべて',
    'master': 'マスター',
    'receiving_lot': '受入',
    'sorting_result': '選果',
    'container': '在庫',
    'label_job': 'ラベル',
  };

  late CsvDataset _dataset;
  late final TextEditingController _searchController;
  late final TextEditingController _entityIdController;
  late final TextEditingController _fromDateController;
  late final TextEditingController _toDateController;
  String _inventoryStatus = '';
  String _inventorySort = 'updated_desc';
  String _masterType = 'variety';
  String _active = 'active';
  String _historyType = '';
  String _businessStatus = 'all';
  bool _busy = false;
  String? _error;
  String? _correlationId;

  @override
  void initState() {
    super.initState();
    _dataset = widget.initialRequest.dataset;
    final filters = widget.initialRequest.filters;
    _searchController = TextEditingController(
      text: filters['search'] as String? ?? '',
    );
    _entityIdController = TextEditingController(
      text: filters['entity_id'] as String? ?? '',
    );
    _fromDateController = TextEditingController(
      text: filters['from_date'] as String? ?? '',
    );
    _toDateController = TextEditingController(
      text: filters['to_date'] as String? ?? '',
    );
    _inventoryStatus = filters['status'] as String? ?? '';
    _inventorySort = filters['sort'] as String? ?? 'updated_desc';
    _masterType = filters['master_type'] as String? ?? 'variety';
    _active = filters['active'] as String? ?? 'active';
    _historyType = filters['entity_type'] as String? ?? '';
    _businessStatus = filters['status'] as String? ?? 'all';
  }

  @override
  void dispose() {
    _searchController.dispose();
    _entityIdController.dispose();
    _fromDateController.dispose();
    _toDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'CSV出力',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text('現在の条件に一致する全件を出力します。ページ番号は含みません。'),
                const SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<CsvDataset>(
                          key: const Key('csv-dataset'),
                          initialValue: _dataset,
                          icon: const SizedBox.shrink(),
                          decoration: const InputDecoration(labelText: '出力対象'),
                          items: [
                            for (final dataset in CsvDataset.values)
                              if (widget.availableDatasets.contains(dataset))
                                DropdownMenuItem(
                                  value: dataset,
                                  child: Text(dataset.label),
                                ),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _dataset = value;
                                    _searchController.clear();
                                    _businessStatus = 'all';
                                    _fromDateController.clear();
                                    _toDateController.clear();
                                    _error = null;
                                    _correlationId = null;
                                  });
                                },
                        ),
                        const SizedBox(height: 16),
                        ..._fields(),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            key: const Key('csv-error'),
                            style: const TextStyle(color: Color(0xFF9E2A2B)),
                          ),
                          if (_correlationId != null)
                            Text(
                              '問い合わせ番号: $_correlationId',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF56605A),
                              ),
                            ),
                        ],
                        if (_busy) ...[
                          const SizedBox(height: 16),
                          const LinearProgressIndicator(),
                          const SizedBox(height: 8),
                          const Text('CSVを作成しています'),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('キャンセル'),
                    ),
                    FilledButton(
                      key: const Key('csv-submit'),
                      onPressed: _busy ? null : _submit,
                      child: const Text('CSVをダウンロード'),
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

  List<Widget> _fields() => switch (_dataset) {
    CsvDataset.orders || CsvDataset.ripening || CsvDataset.shipments => [
      if (_dataset == CsvDataset.shipments)
        Text(
          widget.initialRequest.filters['order_id'] == null
              ? '出荷予定・実績一覧の受注に属する明細を出力します。取消明細も含みます。'
              : '選択した受注の出荷明細を出力します。取消明細も含みます。',
        ),
      TextField(
        key: const Key('csv-business-search'),
        controller: _searchController,
        enabled: !_busy,
        maxLength: 100,
        decoration: InputDecoration(
          labelText: switch (_dataset) {
            CsvDataset.orders => '受注番号・顧客名・愛称',
            CsvDataset.ripening => '追熟ID・品種・等級',
            _ => '出荷ID・受注番号・顧客・コンテナID',
          },
        ),
      ),
      _stringDropdown(
        key: ValueKey('csv-business-status-${_dataset.value}'),
        label: '状態',
        value: _businessStatus,
        values: {
          'all': 'すべて',
          if (_dataset == CsvDataset.orders) 'active': '未出荷',
          if (_dataset != CsvDataset.shipments) 'draft': '下書き',
          'confirmed': '確定',
          if (_dataset != CsvDataset.shipments) 'in_progress': '進行中',
          if (_dataset == CsvDataset.orders) ...{
            'partially_shipped': '一部出荷',
            'shipped': '出荷済み',
          },
          if (_dataset == CsvDataset.ripening) 'completed': '完了',
          'cancelled': 'キャンセル',
        },
        onChanged: (value) => setState(() => _businessStatus = value),
      ),
      const SizedBox(height: 12),
      Text(switch (_dataset) {
        CsvDataset.orders => '期間：出荷予定日',
        CsvDataset.ripening => '期間：注入予定日（日本時間）',
        _ => '期間：出荷実績日（日本時間）',
      }),
      TextField(
        key: const Key('csv-business-from'),
        controller: _fromDateController,
        enabled: !_busy,
        decoration: const InputDecoration(labelText: '開始日（YYYY-MM-DD、任意）'),
      ),
      TextField(
        key: const Key('csv-business-to'),
        controller: _toDateController,
        enabled: !_busy,
        decoration: const InputDecoration(labelText: '終了日（YYYY-MM-DD、任意）'),
      ),
    ],
    CsvDataset.inventory => [
      TextField(
        key: const Key('csv-inventory-search'),
        controller: _searchController,
        enabled: !_busy,
        maxLength: 100,
        decoration: const InputDecoration(labelText: '在庫ID'),
      ),
      const SizedBox(height: 12),
      _stringDropdown(
        key: const Key('csv-inventory-status'),
        label: '状態',
        value: _inventoryStatus,
        values: _inventoryStatuses,
        onChanged: (value) => setState(() => _inventoryStatus = value),
      ),
      const SizedBox(height: 12),
      _stringDropdown(
        key: const Key('csv-inventory-sort'),
        label: '並び順',
        value: _inventorySort,
        values: _inventorySorts,
        onChanged: (value) => setState(() => _inventorySort = value),
      ),
    ],
    CsvDataset.masters => [
      _stringDropdown(
        key: const Key('csv-master-type'),
        label: '種類',
        value: _masterType,
        values: _masterTypes,
        onChanged: (value) => setState(() => _masterType = value),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('csv-master-search'),
        controller: _searchController,
        enabled: !_busy,
        maxLength: 100,
        decoration: const InputDecoration(labelText: '検索'),
      ),
      const SizedBox(height: 12),
      _stringDropdown(
        key: const Key('csv-master-active'),
        label: '有効状態',
        value: _active,
        values: _activeFilters,
        onChanged: (value) => setState(() => _active = value),
      ),
    ],
    CsvDataset.history => [
      _stringDropdown(
        key: const Key('csv-history-type'),
        label: '対象種別',
        value: _historyType,
        values: _historyTypes,
        onChanged: (value) => setState(() => _historyType = value),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('csv-history-id'),
        controller: _entityIdController,
        enabled: !_busy,
        decoration: const InputDecoration(labelText: '対象内部ID（任意）'),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('csv-history-from'),
        controller: _fromDateController,
        enabled: !_busy,
        keyboardType: TextInputType.datetime,
        decoration: const InputDecoration(labelText: '開始日（YYYY-MM-DD）'),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('csv-history-to'),
        controller: _toDateController,
        enabled: !_busy,
        keyboardType: TextInputType.datetime,
        decoration: const InputDecoration(labelText: '終了日（YYYY-MM-DD）'),
      ),
    ],
  };

  Widget _stringDropdown({
    required Key key,
    required String label,
    required String value,
    required Map<String, String> values,
    required ValueChanged<String> onChanged,
  }) => DropdownButtonFormField<String>(
    key: key,
    initialValue: value,
    icon: const SizedBox.shrink(),
    decoration: InputDecoration(labelText: label),
    items: [
      for (final entry in values.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
    ],
    onChanged: _busy
        ? null
        : (next) {
            if (next != null) onChanged(next);
          },
  );

  Future<void> _submit() async {
    final request = _request();
    if (request == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _correlationId = null;
    });
    try {
      final result = await widget.repository.export(request);
      if (!mounted) return;
      final started = await widget.downloader(result.bytes, result.filename);
      if (!mounted) return;
      if (!started) {
        setState(() {
          _busy = false;
          _error = 'この端末ではCSVの保存を開始できませんでした。';
        });
        return;
      }
      Navigator.pop(context, result);
    } on CsvExportFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
        _correlationId = failure.correlationId;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'CSVを保存できませんでした。再試行してください。';
      });
    }
  }

  CsvExportRequest? _request() {
    if (_dataset == CsvDataset.inventory) {
      return CsvExportRequest.inventory(
        search: _searchController.text,
        status: _inventoryStatus.isEmpty ? null : _inventoryStatus,
        sort: _inventorySort,
      );
    }
    if (_dataset == CsvDataset.masters) {
      return CsvExportRequest.masters(
        masterType: _masterType,
        search: _searchController.text,
        active: _active,
      );
    }
    final fromDate = _parseDate(_fromDateController.text, '開始日');
    if (_fromDateController.text.trim().isNotEmpty && fromDate == null) {
      return null;
    }
    final toDate = _parseDate(_toDateController.text, '終了日');
    if (_toDateController.text.trim().isNotEmpty && toDate == null) {
      return null;
    }
    if (fromDate != null && toDate != null && fromDate.isAfter(toDate)) {
      setState(() => _error = '開始日は終了日以前を指定してください。');
      return null;
    }
    if ({
      CsvDataset.orders,
      CsvDataset.ripening,
      CsvDataset.shipments,
    }.contains(_dataset)) {
      return CsvExportRequest.business(
        dataset: _dataset,
        search: _searchController.text,
        status: _businessStatus,
        fromDate: fromDate,
        toDate: toDate,
        orderId: _dataset == widget.initialRequest.dataset
            ? widget.initialRequest.filters['order_id'] as String?
            : null,
      );
    }
    return CsvExportRequest.history(
      entityType: _historyType.isEmpty ? null : _historyType,
      entityId: _entityIdController.text.trim().isEmpty
          ? null
          : _entityIdController.text.trim(),
      fromDate: fromDate,
      toDate: toDate,
    );
  }

  DateTime? _parseDate(String raw, String label) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) {
      setState(() => _error = '$labelはYYYY-MM-DD形式で入力してください。');
      return null;
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      setState(() => _error = '$labelに存在する日付を入力してください。');
      return null;
    }
    return parsed;
  }
}
