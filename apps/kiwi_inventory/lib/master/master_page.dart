import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/common_state_view.dart';
import '../csv_export/csv_export_dialog.dart';
import '../csv_export/csv_export_repository.dart';
import 'master_repository.dart';
import 'supabase_master_repository.dart';

enum _MasterStatusFilter { active, inactive, all }

class MasterPage extends StatefulWidget {
  const MasterPage({
    required this.repository,
    this.csvExportRepository,
    this.embedded = false,
    super.key,
  });

  final MasterRepository repository;
  final CsvExportRepository? csvExportRepository;
  final bool embedded;

  @override
  State<MasterPage> createState() => _MasterPageState();
}

class _MasterPageState extends State<MasterPage> {
  final _searchController = TextEditingController();
  MasterCatalog? _catalog;
  MasterFailure? _failure;
  MasterType _type = MasterType.variety;
  _MasterStatusFilter _status = _MasterStatusFilter.active;
  String? _selectedId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final catalog = await widget.repository.loadCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
        if (catalog.find(_type, _selectedId) == null) _selectedId = null;
      });
    } on MasterFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          widget.embedded ? 32 : 16,
          widget.embedded ? 28 : 20,
          widget.embedded ? 32 : 16,
          24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              canRegister:
                  _catalog?.canManage == true && _type.canRegister && !_loading,
              canExport:
                  widget.csvExportRepository != null &&
                  !_loading &&
                  _failure == null &&
                  _catalog != null,
              onExport: _openCsv,
              onRegister: _openRegister,
            ),
            const SizedBox(height: 22),
            _Filters(
              searchController: _searchController,
              type: _type,
              status: _status,
              enabled: !_loading,
              onSearchChanged: (_) => setState(() => _selectedId = null),
              onTypeChanged: (type) {
                if (type == null) return;
                setState(() {
                  _type = type;
                  _selectedId = null;
                  _searchController.clear();
                });
              },
              onStatusChanged: (status) {
                if (status == null) return;
                setState(() {
                  _status = status;
                  _selectedId = null;
                });
              },
            ),
            const SizedBox(height: 18),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 8,
        title: TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('← ホームへ戻る'),
        ),
      ),
      body: content,
    );
  }

  Widget _buildBody() {
    final catalog = _catalog;
    final failure = _failure;
    if (_loading) {
      return const CommonStateView.loading(title: 'マスターを読み込んでいます');
    }
    if (failure != null) {
      return CommonStateView.error(
        title: 'マスターを読み込めませんでした',
        message: failure.message,
        actionLabel: failure.retryable ? '再試行' : null,
        onAction: failure.retryable ? _load : null,
      );
    }

    final query = _searchController.text.trim().toLowerCase();
    final records = catalog!.of(_type).where((record) {
      final matchesStatus = switch (_status) {
        _MasterStatusFilter.active => record.isActive,
        _MasterStatusFilter.inactive => !record.isActive,
        _MasterStatusFilter.all => true,
      };
      return matchesStatus &&
          (query.isEmpty ||
              record.searchText.contains(query) ||
              _relatedText(record, catalog).toLowerCase().contains(query));
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final showDetail = constraints.maxWidth >= 880;
        final table = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ResultLine(
              count: records.length,
              canManage: catalog.canManage,
              onReload: _load,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: records.isEmpty
                  ? const CommonStateView.empty(
                      title: '条件に合うマスターはありません',
                      message: '検索語または状態を変更してください。',
                    )
                  : _MasterTable(
                      records: records,
                      catalog: catalog,
                      selectedId: showDetail ? _selectedId : null,
                      onOpen: (record) => showDetail
                          ? setState(() => _selectedId = record.id)
                          : _openCompactDetail(record),
                    ),
            ),
          ],
        );
        if (!showDetail) return table;
        final selected = catalog.find(_type, _selectedId);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 13, child: table),
            const SizedBox(width: 28),
            const VerticalDivider(width: 1),
            const SizedBox(width: 28),
            Expanded(
              flex: 7,
              child: selected == null
                  ? const Padding(
                      padding: EdgeInsets.only(top: 42),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Text('一覧からマスターを選択してください。'),
                      ),
                    )
                  : _MasterDetail(
                      record: selected,
                      catalog: catalog,
                      canManage: catalog.canManage,
                      onEdit: () => _openEdit(selected),
                      onToggleActive: () => _openTransition(selected),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openCsv() async {
    final repository = widget.csvExportRepository;
    final catalog = _catalog;
    if (repository == null || catalog == null) return;
    final result = await showCsvExportDialog(
      context: context,
      repository: repository,
      initialRequest: CsvExportRequest.masters(
        masterType: _type.rpcValue,
        search: _searchController.text,
        active: switch (_status) {
          _MasterStatusFilter.active => 'active',
          _MasterStatusFilter.inactive => 'inactive',
          _MasterStatusFilter.all => 'all',
        },
      ),
      availableDatasets: {
        CsvDataset.inventory,
        CsvDataset.masters,
        if (catalog.canManage) CsvDataset.history,
      },
    );
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${result.rowCount}件のCSV保存を開始しました。')),
    );
  }

  Future<void> _openRegister() async {
    final catalog = _catalog;
    if (catalog == null || !catalog.canManage || !_type.canRegister) return;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => MasterFormDialog(
        type: _type,
        catalog: catalog,
        onSubmit: (submission, idempotencyKey) => widget.repository.register(
          type: _type,
          values: submission.values,
          reason: submission.reason,
          idempotencyKey: idempotencyKey,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openEdit(MasterRecord record) async {
    final catalog = _catalog;
    if (catalog == null || !catalog.canManage) return;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => MasterFormDialog(
        type: record.type,
        record: record,
        catalog: catalog,
        onSubmit: (submission, idempotencyKey) => widget.repository.update(
          record: record,
          values: submission.values,
          reason: submission.reason,
          idempotencyKey: idempotencyKey,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openTransition(MasterRecord record) async {
    final catalog = _catalog;
    if (catalog == null || !catalog.canManage) return;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => MasterTransitionDialog(
        record: record,
        onSubmit: (reason, idempotencyKey) => widget.repository.setActive(
          record: record,
          active: !record.isActive,
          reason: reason,
          idempotencyKey: idempotencyKey,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openCompactDetail(MasterRecord record) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(record.primaryText),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: _MasterDetail(
            record: record,
            catalog: _catalog!,
            canManage: _catalog!.canManage,
            onEdit: () {
              Navigator.of(context).pop();
              _openEdit(record);
            },
            onToggleActive: () {
              Navigator.of(context).pop();
              _openTransition(record);
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.canRegister,
    required this.canExport,
    required this.onExport,
    required this.onRegister,
  });

  final bool canRegister;
  final bool canExport;
  final VoidCallback onExport;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Text(
          'マスター',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
      ),
      if (canExport) ...[
        OutlinedButton(
          key: const Key('master-csv-export'),
          onPressed: onExport,
          child: const Text('CSV出力'),
        ),
        const SizedBox(width: 10),
      ],
      if (canRegister)
        FilledButton(onPressed: onRegister, child: const Text('新規登録')),
    ],
  );
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.searchController,
    required this.type,
    required this.status,
    required this.enabled,
    required this.onSearchChanged,
    required this.onTypeChanged,
    required this.onStatusChanged,
  });

  final TextEditingController searchController;
  final MasterType type;
  final _MasterStatusFilter status;
  final bool enabled;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<MasterType?> onTypeChanged;
  final ValueChanged<_MasterStatusFilter?> onStatusChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final fields = <Widget>[
        DropdownButtonFormField<MasterType>(
          key: const Key('master-type'),
          initialValue: type,
          icon: const SizedBox.shrink(),
          decoration: const InputDecoration(labelText: '種類'),
          items: [
            for (final value in MasterType.values)
              DropdownMenuItem(value: value, child: Text(value.label)),
          ],
          onChanged: enabled ? onTypeChanged : null,
        ),
        TextField(
          key: const Key('master-search'),
          controller: searchController,
          enabled: enabled,
          decoration: const InputDecoration(labelText: '検索'),
          onChanged: onSearchChanged,
        ),
        DropdownButtonFormField<_MasterStatusFilter>(
          key: const Key('master-status'),
          initialValue: status,
          icon: const SizedBox.shrink(),
          decoration: const InputDecoration(labelText: '状態'),
          items: const [
            DropdownMenuItem(
              value: _MasterStatusFilter.active,
              child: Text('有効'),
            ),
            DropdownMenuItem(
              value: _MasterStatusFilter.inactive,
              child: Text('無効'),
            ),
            DropdownMenuItem(
              value: _MasterStatusFilter.all,
              child: Text('すべて'),
            ),
          ],
          onChanged: enabled ? onStatusChanged : null,
        ),
      ];
      if (constraints.maxWidth < 760) {
        return Column(
          children: [
            for (var index = 0; index < fields.length; index++) ...[
              fields[index],
              if (index != fields.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      }
      return Row(
        children: [
          Expanded(flex: 3, child: fields[0]),
          const SizedBox(width: 14),
          Expanded(flex: 4, child: fields[1]),
          const SizedBox(width: 14),
          Expanded(flex: 2, child: fields[2]),
        ],
      );
    },
  );
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({
    required this.count,
    required this.canManage,
    required this.onReload,
  });

  final int count;
  final bool canManage;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          canManage ? '$count件' : '$count件　閲覧のみ',
          style: const TextStyle(fontSize: 14, color: AppColors.mutedText),
        ),
      ),
      TextButton(onPressed: onReload, child: const Text('再読込')),
    ],
  );
}

class _MasterTable extends StatelessWidget {
  const _MasterTable({
    required this.records,
    required this.catalog,
    required this.selectedId,
    required this.onOpen,
  });

  final List<MasterRecord> records;
  final MasterCatalog catalog;
  final String? selectedId;
  final ValueChanged<MasterRecord> onOpen;

  @override
  Widget build(BuildContext context) => Scrollbar(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          showCheckboxColumn: false,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF2F4F2)),
          columns: const [
            DataColumn(label: Text('コード・条件')),
            DataColumn(label: Text('名称・値')),
            DataColumn(label: Text('関連')),
            DataColumn(label: Text('状態')),
            DataColumn(label: Text('詳細')),
          ],
          rows: [
            for (final record in records)
              DataRow(
                selected: record.id == selectedId,
                onSelectChanged: (_) => onOpen(record),
                cells: [
                  DataCell(Text(record.primaryText)),
                  DataCell(Text(record.secondaryText)),
                  DataCell(Text(_relatedText(record, catalog))),
                  DataCell(_MasterStatusLabel(active: record.isActive)),
                  DataCell(
                    Semantics(
                      label: '${record.primaryText}の詳細を見る',
                      button: true,
                      excludeSemantics: true,
                      child: const Text('詳細 →'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

class _MasterDetail extends StatelessWidget {
  const _MasterDetail({
    required this.record,
    required this.catalog,
    required this.canManage,
    required this.onEdit,
    required this.onToggleActive,
  });

  final MasterRecord record;
  final MasterCatalog catalog;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final rows = _detailRows(record, catalog);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  record.primaryText,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _MasterStatusLabel(active: record.isActive),
            ],
          ),
          const SizedBox(height: 18),
          _DetailRows(rows: rows),
          if (canManage) ...[
            const SizedBox(height: 24),
            OutlinedButton(onPressed: onEdit, child: const Text('編集')),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onToggleActive,
              child: Text(record.isActive ? '無効化' : '再有効化'),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRows extends StatelessWidget {
  const _DetailRows({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: Column(
      children: [
        for (final row in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 112,
                  child: Text(
                    row.$1,
                    style: const TextStyle(color: AppColors.mutedText),
                  ),
                ),
                Expanded(child: Text(row.$2)),
              ],
            ),
          ),
      ],
    ),
  );
}

class _MasterStatusLabel extends StatelessWidget {
  const _MasterStatusLabel({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: active ? const Color(0xFFEAF2ED) : const Color(0xFFF0F1F0),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: active ? const Color(0xFF45805F) : const Color(0xFF8B938E),
      ),
    ),
    child: Text(
      active ? '有効' : '無効',
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

class MasterFormSubmission {
  const MasterFormSubmission({required this.values, required this.reason});

  final Map<String, Object> values;
  final String reason;
}

class MasterFormDialog extends StatefulWidget {
  const MasterFormDialog({
    required this.type,
    required this.catalog,
    required this.onSubmit,
    this.record,
    super.key,
  });

  final MasterType type;
  final MasterCatalog catalog;
  final MasterRecord? record;
  final Future<MasterMutationResult> Function(
    MasterFormSubmission submission,
    String idempotencyKey,
  )
  onSubmit;

  @override
  State<MasterFormDialog> createState() => _MasterFormDialogState();
}

class _MasterFormDialogState extends State<MasterFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  String? _orchardId;
  String? _plotId;
  String? _varietyId;
  String? _locationType;
  MasterFailure? _failure;
  bool _busy = false;
  String? _signature;
  String? _idempotencyKey;

  bool get _editing => widget.record != null;

  @override
  void initState() {
    super.initState();
    final values = widget.record?.values ?? const <String, Object?>{};
    _controllers = {
      for (final key in [
        'code',
        'name',
        'management_code',
        'display_name',
        'display_order',
        'harvest_year',
        'harvest_month',
        'deadline_days',
        'reason',
      ])
        key: TextEditingController(text: values[key]?.toString() ?? ''),
    };
    _orchardId = values['orchard_id'] as String?;
    _plotId = values['plot_id'] as String?;
    _varietyId = values['variety_id'] as String?;
    _locationType = values['location_type'] as String?;
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      _editing ? '${widget.type.label}を編集' : '${widget.type.label}を登録',
    ),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._withSpacing(_buildBusinessFields()),
            const SizedBox(height: 18),
            _textField(
              'reason',
              _editing ? '変更理由' : '登録理由（任意）',
              required: _editing,
              maxLines: 2,
            ),
            if (_failure != null) ...[
              const SizedBox(height: 16),
              _FailureText(failure: _failure!),
            ],
          ],
        ),
      ),
    ),
    actions: [
      OutlinedButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        key: const Key('master-submit'),
        onPressed: _busy ? null : _submit,
        child: Text(
          _busy
              ? '処理しています'
              : _editing
              ? '更新'
              : '登録',
        ),
      ),
    ],
  );

  List<Widget> _buildBusinessFields() => switch (widget.type) {
    MasterType.variety || MasterType.orchard => [
      _textField('code', 'コード', required: true),
      _textField('name', '名称', required: true),
    ],
    MasterType.grade => [
      if (_editing) _fixedValue('等級', widget.record!.value('code')),
      _numberField('display_order', '表示順', min: 1),
    ],
    MasterType.orchardPlot => [
      if (_editing)
        _fixedValue(
          '農園',
          widget.catalog.relatedLabel(
            MasterType.orchard,
            widget.record!.value('orchard_id'),
          ),
        )
      else
        _optionField(
          label: '農園',
          value: _orchardId,
          type: MasterType.orchard,
          field: 'orchard_id',
          onChanged: (value) => setState(() => _orchardId = value),
        ),
      _textField('code', 'コード', required: true),
      _textField('name', '名称', required: true),
    ],
    MasterType.tree => [
      if (_editing) ...[
        _fixedValue(
          '区画',
          widget.catalog.relatedLabel(
            MasterType.orchardPlot,
            widget.record!.value('plot_id'),
          ),
        ),
        _fixedValue(
          '品種',
          widget.catalog.relatedLabel(
            MasterType.variety,
            widget.record!.value('variety_id'),
          ),
        ),
      ] else ...[
        _optionField(
          label: '区画',
          value: _plotId,
          type: MasterType.orchardPlot,
          field: 'plot_id',
          onChanged: (value) => setState(() => _plotId = value),
        ),
        _optionField(
          label: '品種',
          value: _varietyId,
          type: MasterType.variety,
          field: 'variety_id',
          onChanged: (value) => setState(() => _varietyId = value),
        ),
      ],
      _textField('code', 'コード', required: true),
      _textField('name', '名称', required: true),
    ],
    MasterType.supplier => [
      _textField('management_code', '管理コード', required: true),
      _textField('name', '名称', required: true),
    ],
    MasterType.worker => [
      _textField('code', 'コード', required: true),
      _textField('display_name', '表示名', required: true),
    ],
    MasterType.storageLocation => [
      _textField('code', 'コード', required: true),
      _textField('name', '名称', required: true),
      _choiceField(
        label: '種別',
        value: _locationType,
        field: 'location_type',
        options: const {'cold_storage': '冷蔵庫', 'other': 'その他'},
        onChanged: (value) => setState(() => _locationType = value),
      ),
    ],
    MasterType.sortingDeadlineRule => [
      if (_editing) ...[
        _fixedValue('収穫年', widget.record!.value('harvest_year')),
        _fixedValue('収穫月', widget.record!.value('harvest_month')),
        _fixedValue(
          '品種',
          widget.catalog.relatedLabel(
            MasterType.variety,
            widget.record!.value('variety_id'),
          ),
        ),
      ] else ...[
        _numberField('harvest_year', '収穫年', min: 2000, max: 9999),
        _numberField('harvest_month', '収穫月', min: 1, max: 12),
        _optionField(
          label: '品種',
          value: _varietyId,
          type: MasterType.variety,
          field: 'variety_id',
          onChanged: (value) => setState(() => _varietyId = value),
        ),
      ],
      _numberField('deadline_days', '選果期限日数', min: 1),
    ],
  };

  List<Widget> _withSpacing(List<Widget> fields) => [
    for (var index = 0; index < fields.length; index++) ...[
      fields[index],
      if (index != fields.length - 1) const SizedBox(height: 16),
    ],
  ];

  Widget _textField(
    String key,
    String label, {
    required bool required,
    int maxLines = 1,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: _fieldLabelStyle),
      const SizedBox(height: 8),
      TextFormField(
        key: Key('master-field-$key'),
        controller: _controllers[key],
        enabled: !_busy,
        maxLines: maxLines,
        decoration: InputDecoration(errorText: _serverError(key)),
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                  ? '$labelを入力してください。'
                  : null
            : null,
        onChanged: (_) => setState(() => _failure = null),
      ),
    ],
  );

  Widget _numberField(String key, String label, {required int min, int? max}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: _fieldLabelStyle),
          const SizedBox(height: 8),
          TextFormField(
            key: Key('master-field-$key'),
            controller: _controllers[key],
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(errorText: _serverError(key)),
            validator: (value) {
              final number = int.tryParse(value?.trim() ?? '');
              if (number == null) return '$labelを整数で入力してください。';
              if (number < min || (max != null && number > max)) {
                return max == null
                    ? '$labelは$min以上で入力してください。'
                    : '$labelは$min〜$maxで入力してください。';
              }
              return null;
            },
            onChanged: (_) => setState(() => _failure = null),
          ),
        ],
      );

  Widget _optionField({
    required String label,
    required String? value,
    required MasterType type,
    required String field,
    required ValueChanged<String?> onChanged,
  }) {
    final options = widget.catalog.of(type).where((record) => record.isActive);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: _fieldLabelStyle),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: Key('master-field-$field'),
          initialValue: value,
          icon: const SizedBox.shrink(),
          decoration: InputDecoration(errorText: _serverError(field)),
          hint: const Text('選択してください'),
          isExpanded: true,
          items: [
            for (final option in options)
              DropdownMenuItem(
                value: option.id,
                child: Text(widget.catalog.relatedLabel(type, option.id)),
              ),
          ],
          onChanged: _busy ? null : onChanged,
          validator: (selected) => selected == null ? '$labelを選択してください。' : null,
        ),
      ],
    );
  }

  Widget _choiceField({
    required String label,
    required String? value,
    required String field,
    required Map<String, String> options,
    required ValueChanged<String?> onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: _fieldLabelStyle),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: Key('master-field-$field'),
        initialValue: value,
        icon: const SizedBox.shrink(),
        decoration: InputDecoration(errorText: _serverError(field)),
        hint: const Text('選択してください'),
        items: [
          for (final option in options.entries)
            DropdownMenuItem(value: option.key, child: Text(option.value)),
        ],
        onChanged: _busy ? null : onChanged,
        validator: (selected) => selected == null ? '$labelを選択してください。' : null,
      ),
    ],
  );

  Widget _fixedValue(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: _fieldLabelStyle),
      const SizedBox(height: 5),
      Text(value, style: const TextStyle(fontSize: 16)),
    ],
  );

  String? _serverError(String field) =>
      _failure?.field == field ? _failure!.message : null;

  Map<String, Object> _values() => switch (widget.type) {
    MasterType.variety || MasterType.orchard => {
      'code': _controllers['code']!.text.trim(),
      'name': _controllers['name']!.text.trim(),
    },
    MasterType.grade => {
      'display_order': int.parse(_controllers['display_order']!.text.trim()),
    },
    MasterType.orchardPlot => {
      if (!_editing) 'orchard_id': _orchardId!,
      'code': _controllers['code']!.text.trim(),
      'name': _controllers['name']!.text.trim(),
    },
    MasterType.tree => {
      if (!_editing) ...{'plot_id': _plotId!, 'variety_id': _varietyId!},
      'code': _controllers['code']!.text.trim(),
      'name': _controllers['name']!.text.trim(),
    },
    MasterType.supplier => {
      'management_code': _controllers['management_code']!.text.trim(),
      'name': _controllers['name']!.text.trim(),
    },
    MasterType.worker => {
      'code': _controllers['code']!.text.trim(),
      'display_name': _controllers['display_name']!.text.trim(),
    },
    MasterType.storageLocation => {
      'code': _controllers['code']!.text.trim(),
      'name': _controllers['name']!.text.trim(),
      'location_type': _locationType!,
    },
    MasterType.sortingDeadlineRule => {
      if (!_editing) ...{
        'harvest_year': int.parse(_controllers['harvest_year']!.text.trim()),
        'harvest_month': int.parse(_controllers['harvest_month']!.text.trim()),
        'variety_id': _varietyId!,
      },
      'deadline_days': int.parse(_controllers['deadline_days']!.text.trim()),
    },
  };

  Future<void> _submit() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    final submission = MasterFormSubmission(
      values: _values(),
      reason: _controllers['reason']!.text.trim(),
    );
    final signature =
        '${widget.type.rpcValue}:${widget.record?.id}:${submission.values}:${submission.reason}';
    if (_signature != signature) {
      _signature = signature;
      _idempotencyKey = createMasterIdempotencyKey();
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit(submission, _idempotencyKey!);
      if (mounted) Navigator.of(context).pop(true);
    } on MasterFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _busy = false;
      });
    }
  }
}

class MasterTransitionDialog extends StatefulWidget {
  const MasterTransitionDialog({
    required this.record,
    required this.onSubmit,
    super.key,
  });

  final MasterRecord record;
  final Future<MasterMutationResult> Function(
    String reason,
    String idempotencyKey,
  )
  onSubmit;

  @override
  State<MasterTransitionDialog> createState() => _MasterTransitionDialogState();
}

class _MasterTransitionDialogState extends State<MasterTransitionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  MasterFailure? _failure;
  bool _busy = false;
  String? _signature;
  String? _idempotencyKey;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activating = !widget.record.isActive;
    return AlertDialog(
      scrollable: true,
      title: Text(activating ? '再有効化を確認' : '無効化を確認'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                activating
                    ? '${widget.record.primaryText}を再度、業務入力の選択肢に表示します。'
                    : '${widget.record.primaryText}を新規の業務入力から除外します。',
              ),
              const SizedBox(height: 18),
              const Text('理由', style: _fieldLabelStyle),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('master-transition-reason'),
                controller: _reasonController,
                enabled: !_busy,
                maxLines: 2,
                decoration: InputDecoration(
                  errorText: _failure?.field == 'reason'
                      ? _failure!.message
                      : null,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? '理由を入力してください。'
                    : null,
                onChanged: (_) => setState(() => _failure = null),
              ),
              if (_failure != null) ...[
                const SizedBox(height: 16),
                _FailureText(failure: _failure!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('master-transition-submit'),
          onPressed: _busy ? null : _submit,
          style: activating
              ? null
              : FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: Text(
            _busy
                ? '処理しています'
                : activating
                ? '再有効化'
                : '無効化',
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    final reason = _reasonController.text.trim();
    final signature = '${widget.record.id}:${!widget.record.isActive}:$reason';
    if (_signature != signature) {
      _signature = signature;
      _idempotencyKey = createMasterIdempotencyKey();
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit(reason, _idempotencyKey!);
      if (mounted) Navigator.of(context).pop(true);
    } on MasterFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _busy = false;
      });
    }
  }
}

class _FailureText extends StatelessWidget {
  const _FailureText({required this.failure});

  final MasterFailure failure;

  @override
  Widget build(BuildContext context) {
    final reference = failure.correlationId;
    return Semantics(
      liveRegion: true,
      child: Text(
        reference == null || reference.isEmpty
            ? failure.message
            : '${failure.message}\n問い合わせ番号: $reference',
        style: const TextStyle(
          color: AppColors.error,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _relatedText(
  MasterRecord record,
  MasterCatalog catalog,
) => switch (record.type) {
  MasterType.orchardPlot => catalog.relatedLabel(
    MasterType.orchard,
    record.value('orchard_id'),
  ),
  MasterType.tree =>
    '${catalog.relatedLabel(MasterType.orchardPlot, record.value('plot_id'))} / '
        '${catalog.relatedLabel(MasterType.variety, record.value('variety_id'))}',
  MasterType.storageLocation =>
    record.value('location_type') == 'cold_storage' ? '冷蔵庫' : 'その他',
  MasterType.sortingDeadlineRule => catalog.relatedLabel(
    MasterType.variety,
    record.value('variety_id'),
  ),
  _ => '—',
};

List<(String, String)> _detailRows(
  MasterRecord record,
  MasterCatalog catalog,
) => switch (record.type) {
  MasterType.variety || MasterType.orchard => [
    ('コード', record.value('code')),
    ('名称', record.value('name')),
    ('版', record.version.toString()),
  ],
  MasterType.grade => [
    ('等級', record.value('code')),
    ('表示順', record.value('display_order')),
    ('版', record.version.toString()),
  ],
  MasterType.orchardPlot => [
    (
      '農園',
      catalog.relatedLabel(MasterType.orchard, record.value('orchard_id')),
    ),
    ('コード', record.value('code')),
    ('名称', record.value('name')),
    ('版', record.version.toString()),
  ],
  MasterType.tree => [
    (
      '区画',
      catalog.relatedLabel(MasterType.orchardPlot, record.value('plot_id')),
    ),
    (
      '品種',
      catalog.relatedLabel(MasterType.variety, record.value('variety_id')),
    ),
    ('コード', record.value('code')),
    ('名称', record.value('name')),
    ('版', record.version.toString()),
  ],
  MasterType.supplier => [
    ('管理コード', record.value('management_code')),
    ('名称', record.value('name')),
    ('版', record.version.toString()),
  ],
  MasterType.worker => [
    ('コード', record.value('code')),
    ('表示名', record.value('display_name')),
    ('版', record.version.toString()),
  ],
  MasterType.storageLocation => [
    ('コード', record.value('code')),
    ('名称', record.value('name')),
    ('種別', record.value('location_type') == 'cold_storage' ? '冷蔵庫' : 'その他'),
    ('版', record.version.toString()),
  ],
  MasterType.sortingDeadlineRule => [
    ('収穫年', record.value('harvest_year')),
    ('収穫月', record.value('harvest_month')),
    (
      '品種',
      catalog.relatedLabel(MasterType.variety, record.value('variety_id')),
    ),
    ('選果期限', '${record.value('deadline_days')}日'),
    ('版', record.version.toString()),
  ],
};

const _fieldLabelStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
