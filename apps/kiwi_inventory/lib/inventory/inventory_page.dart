import 'package:flutter/material.dart';

import '../core/common_state_view.dart';
import '../csv_export/csv_export_dialog.dart';
import '../csv_export/csv_export_repository.dart';
import 'inventory_repository.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({
    required this.repository,
    this.csvExportRepository,
    this.embedded = false,
    super.key,
  });

  final InventoryRepository repository;
  final CsvExportRepository? csvExportRepository;
  final bool embedded;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _searchController = TextEditingController();
  InventoryQuery _query = const InventoryQuery();
  InventoryPageData? _data;
  InventoryFailure? _failure;
  bool _loading = true;
  String? _selectedId;

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
      _data = null;
    });
    try {
      final data = await widget.repository.loadPage(_query);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        if (data.items.every((item) => item.id != _selectedId)) {
          _selectedId = null;
        }
      });
    } on InventoryFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _loading = false;
      });
    }
  }

  void _search() {
    final search = _searchController.text.trim();
    if (search == _query.search && _query.page == 0) return;
    _query = _query.copyWith(search: search, page: 0);
    _selectedId = null;
    _load();
  }

  void _changeStatus(InventoryStatus? status) {
    _query = _query.copyWith(
      status: status,
      clearStatus: status == null,
      page: 0,
    );
    _selectedId = null;
    _load();
  }

  void _changeSort(InventorySort sort) {
    _query = _query.copyWith(sort: sort, page: 0);
    _selectedId = null;
    _load();
  }

  void _changePage(int page) {
    _query = _query.copyWith(page: page);
    _selectedId = null;
    _load();
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
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '在庫参照',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                ),
                if (widget.csvExportRepository != null)
                  OutlinedButton(
                    key: const Key('inventory-csv-export'),
                    onPressed: _loading || _data == null ? null : _openCsv,
                    child: const Text('CSV出力'),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            _Filters(
              searchController: _searchController,
              status: _query.status,
              sort: _query.sort,
              enabled: !_loading,
              onSearch: _search,
              onStatusChanged: _changeStatus,
              onSortChanged: _changeSort,
            ),
            const SizedBox(height: 20),
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('← ホームへ戻る'),
        ),
      ),
      body: content,
    );
  }

  Widget _buildBody() {
    if (_loading && _data == null) {
      return const CommonStateView.loading(title: '在庫一覧を読み込んでいます');
    }
    final failure = _failure;
    if (failure != null && _data == null) {
      return CommonStateView.error(
        title: failure.isPermissionDenied ? '在庫を表示できません' : '在庫一覧を読み込めませんでした',
        message: failure.message,
        actionLabel: failure.retryable ? '再試行' : null,
        onAction: failure.retryable ? _load : null,
      );
    }
    final data = _data!;
    if (data.items.isEmpty) {
      return CommonStateView.empty(
        title: '条件に合う在庫はありません',
        message: '検索する在庫IDまたは状態を変更してください。',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = widget.embedded && constraints.maxWidth >= 880;
        final list = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ResultSummary(data: data, onReload: _load),
            const SizedBox(height: 8),
            Expanded(
              child: desktop
                  ? _InventoryTable(
                      items: data.items,
                      selectedId: _selectedId,
                      onOpen: (item) => setState(() => _selectedId = item.id),
                    )
                  : _InventoryList(
                      items: data.items,
                      onOpen: _openMobileDetail,
                    ),
            ),
            const SizedBox(height: 12),
            _Pagination(
              data: data,
              enabled: !_loading,
              onPrevious: () => _changePage(data.page - 1),
              onNext: () => _changePage(data.page + 1),
            ),
          ],
        );
        if (!desktop) return list;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 13, child: list),
            const SizedBox(width: 28),
            const VerticalDivider(width: 1),
            const SizedBox(width: 28),
            Expanded(
              flex: 7,
              child: _selectedId == null
                  ? const _NoSelection()
                  : InventoryDetail(
                      key: ValueKey(_selectedId),
                      repository: widget.repository,
                      csvExportRepository: widget.csvExportRepository,
                      containerId: _selectedId!,
                      compact: true,
                    ),
            ),
          ],
        );
      },
    );
  }

  void _openMobileDetail(InventoryItem item) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => InventoryDetailPage(
          repository: widget.repository,
          csvExportRepository: widget.csvExportRepository,
          containerId: item.id,
          displayId: item.displayId,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  Future<void> _openCsv() async {
    final repository = widget.csvExportRepository;
    if (repository == null) return;
    final result = await showCsvExportDialog(
      context: context,
      repository: repository,
      initialRequest: CsvExportRequest.inventory(
        search: _query.search,
        status: _query.status?.value,
        sort: _query.sort.rpcValue,
      ),
      availableDatasets: const {CsvDataset.inventory, CsvDataset.masters},
    );
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${result.rowCount}件のCSV保存を開始しました。')),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.searchController,
    required this.status,
    required this.sort,
    required this.enabled,
    required this.onSearch,
    required this.onStatusChanged,
    required this.onSortChanged,
  });

  final TextEditingController searchController;
  final InventoryStatus? status;
  final InventorySort sort;
  final bool enabled;
  final VoidCallback onSearch;
  final ValueChanged<InventoryStatus?> onStatusChanged;
  final ValueChanged<InventorySort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final search = TextField(
      key: const Key('inventory-search'),
      controller: searchController,
      enabled: enabled,
      textInputAction: TextInputAction.search,
      decoration: const InputDecoration(
        labelText: '在庫ID',
        hintText: '例：在庫-2026-001',
      ),
      onSubmitted: (_) => onSearch(),
    );
    final searchButton = OutlinedButton(
      key: const Key('inventory-search-button'),
      onPressed: enabled ? onSearch : null,
      child: const Text('検索'),
    );
    final statusField = DropdownButtonFormField<InventoryStatus?>(
      key: const Key('inventory-status-filter'),
      initialValue: status,
      icon: const SizedBox.shrink(),
      decoration: const InputDecoration(labelText: '状態'),
      items: [
        const DropdownMenuItem(value: null, child: Text('すべて')),
        for (final value in InventoryStatus.values)
          DropdownMenuItem(value: value, child: Text(value.label)),
      ],
      onChanged: enabled ? onStatusChanged : null,
    );
    final sortField = DropdownButtonFormField<InventorySort>(
      key: const Key('inventory-sort'),
      initialValue: sort,
      icon: const SizedBox.shrink(),
      decoration: const InputDecoration(labelText: '並び順'),
      items: [
        for (final value in InventorySort.values)
          DropdownMenuItem(value: value, child: Text(value.label)),
      ],
      onChanged: enabled
          ? (value) {
              if (value != null) onSortChanged(value);
            }
          : null,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 8),
                  SizedBox(width: 76, height: 56, child: searchButton),
                ],
              ),
              const SizedBox(height: 10),
              statusField,
              const SizedBox(height: 10),
              sortField,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(flex: 4, child: search),
            const SizedBox(width: 8),
            searchButton,
            const SizedBox(width: 14),
            Expanded(flex: 3, child: statusField),
            const SizedBox(width: 14),
            Expanded(flex: 3, child: sortField),
          ],
        );
      },
    );
  }
}

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({required this.data, required this.onReload});

  final InventoryPageData data;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Semantics(
          liveRegion: true,
          child: Text(
            '${data.totalCount}件中 ${data.firstItemNumber}〜${data.lastItemNumber}件',
            style: const TextStyle(fontSize: 14, color: Color(0xFF56605A)),
          ),
        ),
      ),
      TextButton(onPressed: onReload, child: const Text('再読込')),
    ],
  );
}

class _InventoryList extends StatelessWidget {
  const _InventoryList({required this.items, required this.onOpen});

  final List<InventoryItem> items;
  final ValueChanged<InventoryItem> onOpen;

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: items.length,
    itemBuilder: (context, index) {
      final item = items[index];
      return _InventoryRow(item: item, onTap: () => onOpen(item));
    },
  );
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({required this.item, required this.onTap});

  final InventoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${item.displayId}、${item.varietyName}、${item.gradeCode}、'
        '在庫詳細を見る',
    button: true,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFCBD1CD))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.displayId,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      InventoryStatusLabel(status: item.status),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text('${item.varietyName}・${item.gradeCode}'),
                  const SizedBox(height: 4),
                  Text(
                    '現在 ${formatInventoryWeight(item.currentWeightHundredths)} kg　'
                    '予約 ${formatInventoryWeight(item.reservedWeightHundredths)} kg',
                    style: const TextStyle(color: Color(0xFF303633)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '保管場所 ${item.locationLabel}',
                    style: const TextStyle(color: Color(0xFF56605A)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const ExcludeSemantics(
              child: Text('→', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InventoryTable extends StatelessWidget {
  const _InventoryTable({
    required this.items,
    required this.selectedId,
    required this.onOpen,
  });

  final List<InventoryItem> items;
  final String? selectedId;
  final ValueChanged<InventoryItem> onOpen;

  @override
  Widget build(BuildContext context) => Scrollbar(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          showCheckboxColumn: false,
          columnSpacing: 16,
          horizontalMargin: 12,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF2F4F2)),
          columns: const [
            DataColumn(label: Text('在庫ID')),
            DataColumn(label: Text('品種・等級')),
            DataColumn(numeric: true, label: Text('現在量')),
            DataColumn(numeric: true, label: Text('予約量')),
            DataColumn(numeric: true, label: Text('利用可能')),
            DataColumn(label: Text('状態')),
            DataColumn(label: Text('詳細')),
          ],
          rows: [
            for (final item in items)
              DataRow(
                selected: item.id == selectedId,
                onSelectChanged: (_) => onOpen(item),
                cells: [
                  DataCell(Text(item.displayId)),
                  DataCell(Text('${item.varietyName}・${item.gradeCode}')),
                  DataCell(
                    Text(
                      '${formatInventoryWeight(item.currentWeightHundredths)} kg',
                    ),
                  ),
                  DataCell(
                    Text(
                      '${formatInventoryWeight(item.reservedWeightHundredths)} kg',
                    ),
                  ),
                  DataCell(
                    Text(
                      '${formatInventoryWeight(item.availableWeightHundredths)} kg',
                    ),
                  ),
                  DataCell(InventoryStatusLabel(status: item.status)),
                  DataCell(
                    Semantics(
                      label: '${item.displayId}の詳細を見る',
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

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.data,
    required this.enabled,
    required this.onPrevious,
    required this.onNext,
  });

  final InventoryPageData data;
  final bool enabled;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      OutlinedButton(
        key: const Key('inventory-previous-page'),
        onPressed: enabled && data.hasPrevious ? onPrevious : null,
        child: const Text('← 前へ'),
      ),
      const SizedBox(width: 10),
      Text('${data.page + 1}ページ'),
      const SizedBox(width: 10),
      OutlinedButton(
        key: const Key('inventory-next-page'),
        onPressed: enabled && data.hasNext ? onNext : null,
        child: const Text('次へ →'),
      ),
    ],
  );
}

class InventoryStatusLabel extends StatelessWidget {
  const InventoryStatusLabel({required this.status, super.key});

  final InventoryStatus status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: _statusBackground(status),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: _statusBorder(status)),
    ),
    child: Text(
      status.label,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

Color _statusBackground(InventoryStatus status) => switch (status) {
  InventoryStatus.expired => const Color(0xFFFFEEEE),
  InventoryStatus.shippable => const Color(0xFFEAF2ED),
  InventoryStatus.shipped => const Color(0xFFF0F1F0),
  _ => const Color(0xFFFFF7E5),
};

Color _statusBorder(InventoryStatus status) => switch (status) {
  InventoryStatus.expired => const Color(0xFFB42318),
  InventoryStatus.shippable => const Color(0xFF45805F),
  InventoryStatus.shipped => const Color(0xFF8B938E),
  _ => const Color(0xFFB77A14),
};

class _NoSelection extends StatelessWidget {
  const _NoSelection();

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: EdgeInsets.only(top: 34),
      child: Text(
        '一覧から在庫を選択すると詳細を確認できます。',
        style: TextStyle(color: Color(0xFF56605A)),
      ),
    ),
  );
}

class InventoryDetailPage extends StatelessWidget {
  const InventoryDetailPage({
    required this.repository,
    required this.containerId,
    required this.displayId,
    this.csvExportRepository,
    super.key,
  });

  final InventoryRepository repository;
  final CsvExportRepository? csvExportRepository;
  final String containerId;
  final String displayId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 8,
      title: TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('← 在庫一覧へ戻る'),
      ),
    ),
    body: SafeArea(
      child: InventoryDetail(
        repository: repository,
        csvExportRepository: csvExportRepository,
        containerId: containerId,
        displayId: displayId,
      ),
    ),
  );
}

class InventoryDetail extends StatefulWidget {
  const InventoryDetail({
    required this.repository,
    required this.containerId,
    this.csvExportRepository,
    this.displayId,
    this.compact = false,
    super.key,
  });

  final InventoryRepository repository;
  final CsvExportRepository? csvExportRepository;
  final String containerId;
  final String? displayId;
  final bool compact;

  @override
  State<InventoryDetail> createState() => _InventoryDetailState();
}

class _InventoryDetailState extends State<InventoryDetail> {
  InventoryDetailData? _data;
  InventoryFailure? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failure = null);
    try {
      final data = await widget.repository.loadDetail(widget.containerId);
      if (!mounted) return;
      setState(() => _data = data);
    } on InventoryFailure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    if (failure != null) {
      return CommonStateView.error(
        title: '在庫詳細を読み込めませんでした',
        message: failure.message,
        actionLabel: failure.retryable ? '再試行' : null,
        onAction: failure.retryable ? _load : null,
      );
    }
    final data = _data;
    if (data == null) {
      return CommonStateView.loading(
        title: widget.displayId == null
            ? '在庫詳細を読み込んでいます'
            : '${widget.displayId}を読み込んでいます',
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                data.item.displayId,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            InventoryStatusLabel(status: data.item.status),
          ],
        ),
        const SizedBox(height: 24),
        _DetailSection(
          title: '在庫情報',
          rows: [
            ('品種', data.item.varietyName),
            ('等級', data.item.gradeCode),
            (
              '元重量',
              '${formatInventoryWeight(data.item.originalWeightHundredths)} kg',
            ),
            (
              '現在量',
              '${formatInventoryWeight(data.item.currentWeightHundredths)} kg',
            ),
            (
              '予約量',
              '${formatInventoryWeight(data.item.reservedWeightHundredths)} kg',
            ),
            (
              '利用可能',
              '${formatInventoryWeight(data.item.availableWeightHundredths)} kg',
            ),
            ('保管場所', data.item.locationLabel),
          ],
        ),
        const SizedBox(height: 28),
        _SourceSection(source: data.source),
        const SizedBox(height: 28),
        _HistorySection(
          data: data,
          csvExportRepository: widget.csvExportRepository,
        ),
      ],
    );
    return SingleChildScrollView(
      padding: EdgeInsets.all(widget.compact ? 0 : 20),
      child: widget.compact
          ? content
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: content,
              ),
            ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFCBD1CD))),
        ),
        child: Column(
          children: [
            for (final row in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFCBD1CD))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 104,
                      child: Text(
                        row.$1,
                        style: const TextStyle(color: Color(0xFF56605A)),
                      ),
                    ),
                    Expanded(child: Text(row.$2)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _SourceSection extends StatelessWidget {
  const _SourceSection({required this.source});

  final InventorySource source;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '発生元',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => _showSource(context, receiving: true),
        style: TextButton.styleFrom(alignment: Alignment.centerLeft),
        child: Text('${source.receivingDisplayId}の受入情報を見る →'),
      ),
      TextButton(
        onPressed: () => _showSource(context, receiving: false),
        style: TextButton.styleFrom(alignment: Alignment.centerLeft),
        child: Text('${source.sortingDisplayId}の選果情報を見る →'),
      ),
    ],
  );

  Future<void> _showSource(BuildContext context, {required bool receiving}) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: Text(receiving ? '受入情報' : '選果情報'),
          content: _DetailSection(
            title: receiving
                ? source.receivingDisplayId
                : source.sortingDisplayId,
            rows: receiving
                ? [
                    ('区分', source.sourceTypeLabel),
                    ('受入日', _formatDate(source.receivedOn)),
                    ('産地', source.originName),
                  ]
                : [
                    ('選果日', _formatDate(source.sortedOn)),
                    ('担当者', source.sortingWorkerName),
                    ('受入ID', source.receivingDisplayId),
                  ],
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

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.data, this.csvExportRepository});

  final InventoryDetailData data;
  final CsvExportRepository? csvExportRepository;

  @override
  Widget build(BuildContext context) {
    if (!data.canViewHistory) {
      return const _DetailSection(
        title: '変更履歴',
        rows: [('閲覧権限', '変更履歴は管理者のみ確認できます。')],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '変更履歴',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            if (csvExportRepository != null)
              OutlinedButton(
                key: const Key('history-csv-export'),
                onPressed: () => _exportHistory(context),
                child: const Text('履歴CSV出力'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (data.history.isEmpty)
          const Text('記録はありません。')
        else
          for (final entry in data.history)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFCBD1CD))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.operationLabel}　${_formatDateTime(entry.changedAt)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(entry.reason),
                  const SizedBox(height: 3),
                  Text(
                    '担当 ${entry.changedBy}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF56605A),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Future<void> _exportHistory(BuildContext context) async {
    final repository = csvExportRepository;
    if (repository == null) return;
    final result = await showCsvExportDialog(
      context: context,
      repository: repository,
      initialRequest: CsvExportRequest.history(
        entityType: 'container',
        entityId: data.item.id,
      ),
      availableDatasets: const {
        CsvDataset.inventory,
        CsvDataset.masters,
        CsvDataset.history,
      },
    );
    if (!context.mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${result.rowCount}件のCSV保存を開始しました。')),
    );
  }
}

String _formatDate(DateTime value) =>
    '${value.year}年${value.month}月${value.day}日';

String _formatDateTime(DateTime value) {
  final jst = value.toUtc().add(const Duration(hours: 9));
  return '${_formatDate(jst)} '
      '${jst.hour.toString().padLeft(2, '0')}:'
      '${jst.minute.toString().padLeft(2, '0')}';
}
