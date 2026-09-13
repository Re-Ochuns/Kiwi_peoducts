import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/common_state_view.dart';
import '../csv_export/business_csv_button.dart';
import '../csv_export/csv_export_repository.dart';
import 'order_management_repository.dart';

enum _ManagementView { orders, customers }

class OrderManagementPage extends StatefulWidget {
  const OrderManagementPage({
    required this.repository,
    this.csvExportRepository,
    this.initialOrderId,
    super.key,
  });

  final OrderManagementRepository repository;
  final CsvExportRepository? csvExportRepository;
  final String? initialOrderId;

  @override
  State<OrderManagementPage> createState() => _OrderManagementPageState();
}

class _OrderManagementPageState extends State<OrderManagementPage> {
  final _orderSearch = TextEditingController();
  final _customerSearch = TextEditingController();
  _ManagementView _view = _ManagementView.orders;
  OrderListFilter _filter = OrderListFilter.active;
  OrderManagementData? _data;
  OrderManagementFailure? _failure;
  bool _loading = true;
  String _appliedSearch = '';
  OrderListFilter _appliedFilter = OrderListFilter.active;
  String? _selectedOrderId;
  String? _selectedCustomerId;

  @override
  void initState() {
    super.initState();
    _selectedOrderId = widget.initialOrderId;
    _load();
  }

  @override
  void dispose() {
    _orderSearch.dispose();
    _customerSearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
      _data = null;
    });
    final search = _orderSearch.text;
    final filter = _filter;
    try {
      final data = await widget.repository.load(
        filter: filter,
        search: search,
        customerSearch: _customerSearch.text,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _appliedSearch = search;
        _appliedFilter = filter;
        _loading = false;
        if (data.orders.every((item) => item.id != _selectedOrderId)) {
          _selectedOrderId = null;
        }
        if (data.customers.every((item) => item.id != _selectedCustomerId)) {
          _selectedCustomerId = null;
        }
      });
    } on OrderManagementFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_view == _ManagementView.orders &&
                widget.csvExportRepository != null)
              Align(
                alignment: Alignment.centerRight,
                child: BusinessCsvButton(
                  repository: widget.csvExportRepository!,
                  enabled: !_loading && _failure == null && _data != null,
                  request: CsvExportRequest.business(
                    dataset: CsvDataset.orders,
                    search: _appliedSearch,
                    status: _appliedFilter.status?.value ?? 'active',
                  ),
                ),
              ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '受注管理',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                ),
                if (_data?.canManage == true)
                  FilledButton(
                    key: Key(
                      _view == _ManagementView.orders
                          ? 'order-register'
                          : 'customer-register',
                    ),
                    onPressed: _loading ? null : _openRegister,
                    child: Text(
                      _view == _ManagementView.orders ? '受注を登録' : '顧客を登録',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _ViewSwitch(
              value: _view,
              onChanged: (value) => setState(() {
                _view = value;
                _selectedOrderId = null;
                _selectedCustomerId = null;
              }),
            ),
            const SizedBox(height: 20),
            if (_view == _ManagementView.orders)
              _OrderFilters(
                controller: _orderSearch,
                filter: _filter,
                enabled: !_loading,
                onSearch: _load,
                onFilter: (value) {
                  _filter = value;
                  _selectedOrderId = null;
                  _load();
                },
              )
            else
              _CustomerFilters(
                controller: _customerSearch,
                enabled: !_loading,
                onSearch: _load,
              ),
            const SizedBox(height: 20),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const CommonStateView.loading(title: '受注と顧客を読み込んでいます');
    final failure = _failure;
    if (failure != null) {
      return CommonStateView.error(
        title: failure.isPermissionDenied ? '受注管理を表示できません' : '受注と顧客を読み込めませんでした',
        message: failure.message,
        actionLabel: failure.retryable ? '再試行' : null,
        onAction: failure.retryable ? _load : null,
      );
    }
    final data = _data!;
    final empty = _view == _ManagementView.orders
        ? data.orders.isEmpty
        : data.customers.isEmpty;
    if (empty) {
      return CommonStateView.empty(
        title: _view == _ManagementView.orders
            ? '条件に合う受注はありません'
            : '条件に合う顧客はありません',
        message: '検索条件を変更してください。',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 850;
        final table = _view == _ManagementView.orders
            ? _OrderTable(
                data: data,
                selectedId: _selectedOrderId,
                onSelect: compact
                    ? (item) => _openOrderDetail(item.id)
                    : (item) => setState(() => _selectedOrderId = item.id),
              )
            : _CustomerTable(
                customers: data.customers,
                selectedId: _selectedCustomerId,
                onSelect: compact
                    ? (item) => _openCustomerDetail(item.id)
                    : (item) => setState(() => _selectedCustomerId = item.id),
              );
        if (compact) return table;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 13, child: table),
            const SizedBox(width: 24),
            const VerticalDivider(width: 1),
            const SizedBox(width: 24),
            Expanded(
              flex: 7,
              child: _view == _ManagementView.orders
                  ? (_selectedOrderId == null
                        ? const _NoSelection(message: '受注行を選択すると詳細を表示します')
                        : _OrderDetailPanel(
                            key: ValueKey(_selectedOrderId),
                            repository: widget.repository,
                            orderId: _selectedOrderId!,
                            data: data,
                            onChanged: _load,
                          ))
                  : (_selectedCustomerId == null
                        ? const _NoSelection(message: '顧客行を選択すると詳細を表示します')
                        : _CustomerDetailPanel(
                            key: ValueKey(_selectedCustomerId),
                            repository: widget.repository,
                            customerId: _selectedCustomerId!,
                            canManage: data.canManage,
                            onChanged: _load,
                          )),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openOrderDetail(String id) async {
    setState(() => _selectedOrderId = id);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('受注詳細'),
        content: SizedBox(
          width: 600,
          height: 620,
          child: _OrderDetailPanel(
            repository: widget.repository,
            orderId: id,
            data: _data!,
            onChanged: _load,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCustomerDetail(String id) async {
    setState(() => _selectedCustomerId = id);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('顧客詳細'),
        content: SizedBox(
          width: 600,
          height: 620,
          child: _CustomerDetailPanel(
            repository: widget.repository,
            customerId: id,
            canManage: _data!.canManage,
            onChanged: _load,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future<void> _openRegister() async {
    final data = _data!;
    final changed = _view == _ManagementView.orders
        ? await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) =>
                OrderFormDialog(repository: widget.repository, data: data),
          )
        : await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => CustomerFormDialog(repository: widget.repository),
          );
    if (changed == true) await _load();
  }
}

class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.value, required this.onChanged});
  final _ManagementView value;
  final ValueChanged<_ManagementView> onChanged;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        _ViewButton(
          label: '受注',
          selected: value == _ManagementView.orders,
          onTap: () => onChanged(_ManagementView.orders),
        ),
        _ViewButton(
          label: '顧客・配送先',
          selected: value == _ManagementView.customers,
          onTap: () => onChanged(_ManagementView.customers),
        ),
      ],
    ),
  );
}

class _ViewButton extends StatelessWidget {
  const _ViewButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: selected ? null : onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 144),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.green : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    ),
  );
}

class _OrderFilters extends StatelessWidget {
  const _OrderFilters({
    required this.controller,
    required this.filter,
    required this.enabled,
    required this.onSearch,
    required this.onFilter,
  });
  final TextEditingController controller;
  final OrderListFilter filter;
  final bool enabled;
  final VoidCallback onSearch;
  final ValueChanged<OrderListFilter> onFilter;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: 320,
        child: TextField(
          key: const Key('order-search'),
          controller: controller,
          enabled: enabled,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(labelText: '受注番号・顧客名'),
          onSubmitted: (_) => onSearch(),
        ),
      ),
      SizedBox(
        width: 180,
        child: DropdownButtonFormField<OrderListFilter>(
          key: const Key('order-status-filter'),
          initialValue: filter,
          isExpanded: true,
          icon: const SizedBox.shrink(),
          decoration: const InputDecoration(labelText: '状態'),
          items: [
            for (final value in OrderListFilter.values)
              DropdownMenuItem(value: value, child: Text(value.label)),
          ],
          onChanged: enabled
              ? (value) {
                  if (value != null) onFilter(value);
                }
              : null,
        ),
      ),
      OutlinedButton(
        onPressed: enabled ? onSearch : null,
        child: const Text('検索'),
      ),
    ],
  );
}

class _CustomerFilters extends StatelessWidget {
  const _CustomerFilters({
    required this.controller,
    required this.enabled,
    required this.onSearch,
  });
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: 420,
        child: TextField(
          key: const Key('customer-search'),
          controller: controller,
          enabled: enabled,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(labelText: '顧客コード・名称・通称'),
          onSubmitted: (_) => onSearch(),
        ),
      ),
      OutlinedButton(
        onPressed: enabled ? onSearch : null,
        child: const Text('検索'),
      ),
    ],
  );
}

class _OrderTable extends StatelessWidget {
  const _OrderTable({
    required this.data,
    required this.selectedId,
    required this.onSelect,
  });
  final OrderManagementData data;
  final String? selectedId;
  final ValueChanged<OrderItem> onSelect;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(
        top: BorderSide(color: AppColors.line),
        bottom: BorderSide(color: AppColors.line),
      ),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: SingleChildScrollView(
            child: DataTable(
              columnSpacing: 16,
              dataRowMaxHeight: MediaQuery.textScalerOf(context).scale(16) > 16
                  ? 106
                  : null,
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF0F2F0)),
              columns: const [
                DataColumn(label: Text('受注番号')),
                DataColumn(label: Text('顧客・品種')),
                DataColumn(label: Text('出荷予定日')),
                DataColumn(label: Text('注文量・不足'), numeric: true),
                DataColumn(label: Text('状態')),
                DataColumn(label: Text('')),
              ],
              rows: [
                for (final item in data.orders)
                  DataRow(
                    selected: item.id == selectedId,
                    onSelectChanged: (_) => onSelect(item),
                    cells: [
                      DataCell(
                        Text(
                          item.number,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${item.customerDisplayName}\n${data.varietyLabel(item.varietyId)}・${data.gradeLabel(item.gradeId)}',
                        ),
                      ),
                      DataCell(Text(_displayDate(item.scheduledShipOn))),
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _Weight(item.orderedWeight),
                            Text(
                              item.shortageWeight > 0
                                  ? '不足 ${item.shortageWeight.toStringAsFixed(2)} kg'
                                  : '不足なし',
                              style: TextStyle(
                                color: item.shortageWeight > 0
                                    ? AppColors.error
                                    : AppColors.mutedText,
                                fontWeight: item.shortageWeight > 0
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(_StatusLabel(status: item.status)),
                      DataCell(
                        Semantics(
                          label: '${item.number}の詳細を見る',
                          excludeSemantics: true,
                          child: const Text(
                            '→',
                            style: TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CustomerTable extends StatelessWidget {
  const _CustomerTable({
    required this.customers,
    required this.selectedId,
    required this.onSelect,
  });
  final List<CustomerSummary> customers;
  final String? selectedId;
  final ValueChanged<CustomerSummary> onSelect;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(
        top: BorderSide(color: AppColors.line),
        bottom: BorderSide(color: AppColors.line),
      ),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: SingleChildScrollView(
            child: DataTable(
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF0F2F0)),
              columns: const [
                DataColumn(label: Text('顧客コード')),
                DataColumn(label: Text('顧客名')),
                DataColumn(label: Text('通称')),
                DataColumn(label: Text('配送先'), numeric: true),
                DataColumn(label: Text('')),
              ],
              rows: [
                for (final item in customers)
                  DataRow(
                    selected: item.id == selectedId,
                    onSelectChanged: (_) => onSelect(item),
                    cells: [
                      DataCell(
                        Text(
                          item.code,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      DataCell(Text(item.name)),
                      DataCell(
                        Text(item.nickname.isEmpty ? '—' : item.nickname),
                      ),
                      DataCell(Text('${item.destinationCount}件')),
                      DataCell(
                        Semantics(
                          label: '${item.code}の詳細を見る',
                          excludeSemantics: true,
                          child: const Text(
                            '→',
                            style: TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _OrderDetailPanel extends StatefulWidget {
  const _OrderDetailPanel({
    required this.repository,
    required this.orderId,
    required this.data,
    required this.onChanged,
    super.key,
  });
  final OrderManagementRepository repository;
  final String orderId;
  final OrderManagementData data;
  final VoidCallback onChanged;

  @override
  State<_OrderDetailPanel> createState() => _OrderDetailPanelState();
}

class _OrderDetailPanelState extends State<_OrderDetailPanel> {
  OrderDetail? _detail;
  OrderManagementFailure? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await widget.repository.loadOrder(widget.orderId);
      if (mounted) {
        setState(() {
          _detail = detail;
          _failure = null;
        });
      }
    } on OrderManagementFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failure != null) {
      return CommonStateView.error(
        title: '受注詳細を読み込めませんでした',
        message: _failure!.message,
        actionLabel: _failure!.retryable ? '再試行' : null,
        onAction: _failure!.retryable ? _load : null,
      );
    }
    final detail = _detail;
    if (detail == null) {
      return const CommonStateView.loading(title: '受注詳細を読み込んでいます');
    }
    final item = detail.item;
    return SingleChildScrollView(
      key: const Key('order-detail'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            item.number,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _StatusLabel(status: item.status),
          ),
          const SizedBox(height: 22),
          _DetailRow(label: '顧客', value: item.customerDisplayName),
          _DetailRow(label: '注文日', value: _displayDate(item.orderedOn)),
          _DetailRow(label: '出荷予定日', value: _displayDate(item.scheduledShipOn)),
          _DetailRow(
            label: '品種・等級',
            value:
                '${widget.data.varietyLabel(item.varietyId)}・${widget.data.gradeLabel(item.gradeId)}',
          ),
          _DetailRow(
            label: '注文量',
            value: '${item.orderedWeight.toStringAsFixed(2)} kg',
            strong: true,
          ),
          _DetailRow(
            label: '割当済み',
            value: '${item.allocatedWeight.toStringAsFixed(2)} kg',
          ),
          _DetailRow(
            label: '不足',
            value: item.shortageWeight > 0
                ? '${item.shortageWeight.toStringAsFixed(2)} kg'
                : 'なし',
            error: item.shortageWeight > 0,
          ),
          const SizedBox(height: 20),
          const Text(
            '配送先',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '${detail.destinationName}\n${detail.recipientName}\n〒${detail.postalCode}\n${detail.address}',
            style: const TextStyle(fontSize: 15, height: 1.6),
          ),
          if (detail.allocations.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              '追熟割当',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final allocation in detail.allocations)
              _DetailRow(
                label: allocation.lotId,
                value: '${allocation.weight.toStringAsFixed(2)} kg',
              ),
          ],
          if (detail.notes.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              '備考',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(detail.notes),
          ],
          if (widget.data.canManage &&
              (item.status == OrderStatus.draft ||
                  item.status == OrderStatus.confirmed)) ...[
            const SizedBox(height: 24),
            OutlinedButton(onPressed: _edit, child: const Text('受注を編集')),
            const SizedBox(height: 8),
            if (item.status == OrderStatus.draft) ...[
              FilledButton(onPressed: _confirm, child: const Text('受注を確定')),
              const SizedBox(height: 8),
            ],
            TextButton(
              onPressed: _cancel,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                minimumSize: const Size(0, 48),
              ),
              child: const Text('受注をキャンセル'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _edit() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OrderFormDialog(
        repository: widget.repository,
        data: widget.data,
        existing: _detail,
      ),
    );
    if (changed == true) {
      await _load();
      widget.onChanged();
    }
  }

  Future<void> _confirm() async => _transition(confirm: true);
  Future<void> _cancel() async => _transition(confirm: false);

  Future<void> _transition({required bool confirm}) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OrderTransitionDialog(
        repository: widget.repository,
        order: _detail!,
        confirm: confirm,
      ),
    );
    if (changed == true) {
      await _load();
      widget.onChanged();
    }
  }
}

class _CustomerDetailPanel extends StatefulWidget {
  const _CustomerDetailPanel({
    required this.repository,
    required this.customerId,
    required this.canManage,
    required this.onChanged,
    super.key,
  });
  final OrderManagementRepository repository;
  final String customerId;
  final bool canManage;
  final VoidCallback onChanged;

  @override
  State<_CustomerDetailPanel> createState() => _CustomerDetailPanelState();
}

class _CustomerDetailPanelState extends State<_CustomerDetailPanel> {
  CustomerDetail? _detail;
  OrderManagementFailure? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await widget.repository.loadCustomer(widget.customerId);
      if (mounted) {
        setState(() {
          _detail = detail;
          _failure = null;
        });
      }
    } on OrderManagementFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failure != null) {
      return CommonStateView.error(
        title: '顧客詳細を読み込めませんでした',
        message: _failure!.message,
        actionLabel: _failure!.retryable ? '再試行' : null,
        onAction: _failure!.retryable ? _load : null,
      );
    }
    final detail = _detail;
    if (detail == null) {
      return const CommonStateView.loading(title: '顧客詳細を読み込んでいます');
    }
    final customer = detail.customer;
    return SingleChildScrollView(
      key: const Key('customer-detail'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            customer.code,
            style: const TextStyle(
              fontSize: 20,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _DetailRow(label: '顧客名', value: customer.name),
          _DetailRow(
            label: '通称',
            value: customer.nickname.isEmpty ? '—' : customer.nickname,
          ),
          _DetailRow(label: '郵便番号', value: customer.postalCode),
          _DetailRow(label: '住所', value: customer.address),
          if (widget.canManage) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _editCustomer,
              child: const Text('顧客情報を編集'),
            ),
          ],
          const SizedBox(height: 26),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '配送先',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              if (widget.canManage)
                TextButton(
                  onPressed: _addDestination,
                  child: const Text('配送先を追加'),
                ),
            ],
          ),
          const Divider(height: 1),
          if (detail.destinations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('配送先はありません。'),
            )
          else
            for (final destination in detail.destinations)
              InkWell(
                onTap: widget.canManage
                    ? () => _editDestination(destination)
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.line)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '${destination.name}\n${destination.recipientName}\n〒${destination.postalCode} ${destination.address}',
                          style: const TextStyle(height: 1.5),
                        ),
                      ),
                      if (widget.canManage)
                        Semantics(
                          label: '${destination.name}を編集',
                          excludeSemantics: true,
                          child: const Text(
                            '→',
                            style: TextStyle(fontSize: 20),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _editCustomer() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerFormDialog(
        repository: widget.repository,
        existing: _detail!.customer,
      ),
    );
    if (changed == true) {
      await _load();
      widget.onChanged();
    }
  }

  Future<void> _addDestination() => _openDestination(null);
  Future<void> _editDestination(ShippingDestination value) =>
      _openDestination(value);
  Future<void> _openDestination(ShippingDestination? destination) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DestinationFormDialog(
        repository: widget.repository,
        customer: _detail!.customer,
        existing: destination,
      ),
    );
    if (changed == true) {
      await _load();
      widget.onChanged();
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.strong = false,
    this.error = false,
  });
  final String label;
  final String value;
  final bool strong;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.mutedText),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: strong ? 20 : 15,
              fontWeight: strong || error ? FontWeight.w700 : FontWeight.w400,
              color: error ? AppColors.error : null,
              fontFeatures: strong
                  ? const [FontFeature.tabularFigures()]
                  : null,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Weight extends StatelessWidget {
  const _Weight(this.value);
  final double value;
  @override
  Widget build(BuildContext context) => Text(
    '${value.toStringAsFixed(2)} kg',
    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
  );
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});
  final OrderStatus status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: switch (status) {
        OrderStatus.confirmed || OrderStatus.shipped => const Color(0xFFE3F2E8),
        OrderStatus.cancelled => const Color(0xFFF1F2F1),
        OrderStatus.draft => const Color(0xFFFFF2CC),
        _ => const Color(0xFFE8EEF6),
      },
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      status.label,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

class _NoSelection extends StatelessWidget {
  const _NoSelection({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Text(message, style: const TextStyle(color: AppColors.mutedText)),
  );
}

class CustomerFormDialog extends StatefulWidget {
  const CustomerFormDialog({
    required this.repository,
    this.existing,
    super.key,
  });
  final OrderManagementRepository repository;
  final CustomerSummary? existing;
  @override
  State<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _nickname;
  late final TextEditingController _postalCode;
  late final TextEditingController _address;
  final _reason = TextEditingController();
  bool _confirming = false;
  bool _saving = false;
  bool _completed = false;
  String? _error;
  String? _operationKey;

  @override
  void initState() {
    super.initState();
    final value = widget.existing;
    _code = TextEditingController(text: value?.code ?? '');
    _name = TextEditingController(text: value?.name ?? '');
    _nickname = TextEditingController(text: value?.nickname ?? '');
    _postalCode = TextEditingController(text: value?.postalCode ?? '');
    _address = TextEditingController(text: value?.address ?? '');
  }

  @override
  void dispose() {
    for (final controller in [
      _code,
      _name,
      _nickname,
      _postalCode,
      _address,
      _reason,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _completed
          ? '登録完了'
          : widget.existing == null
          ? '顧客を登録'
          : '顧客情報を編集',
    ),
    content: SizedBox(
      width: 520,
      child: _completed
          ? Text('${_code.text} を保存しました。')
          : _confirming
          ? _customerConfirmation()
          : _customerForm(),
    ),
    actions: _completed
        ? [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('閉じる'),
            ),
          ]
        : _confirming
        ? [
            OutlinedButton(
              onPressed: _saving
                  ? null
                  : () => setState(() => _confirming = false),
              child: const Text('入力へ戻る'),
            ),
            FilledButton(
              key: const Key('customer-save'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中' : 'この内容で保存'),
            ),
          ]
        : [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              key: const Key('customer-confirm'),
              onPressed: _toConfirm,
              child: const Text('入力内容を確認'),
            ),
          ],
  );

  Widget _customerForm() => Form(
    key: _formKey,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Field(label: '顧客コード', controller: _code, keyValue: 'customer-code'),
          _Field(label: '顧客名', controller: _name, keyValue: 'customer-name'),
          _Field(
            label: '通称（任意）',
            controller: _nickname,
            required: false,
            keyValue: 'customer-nickname',
          ),
          _Field(
            label: '郵便番号',
            controller: _postalCode,
            keyValue: 'customer-postal-code',
          ),
          _Field(
            label: '住所',
            controller: _address,
            keyValue: 'customer-address',
            lines: 2,
          ),
          if (widget.existing != null)
            _Field(
              label: '変更理由',
              controller: _reason,
              keyValue: 'customer-reason',
            ),
          if (_error != null) _ErrorText(_error!),
        ],
      ),
    ),
  );

  Widget _customerConfirmation() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _DetailRow(label: '顧客コード', value: _code.text),
      _DetailRow(label: '顧客名', value: _name.text),
      if (_nickname.text.isNotEmpty)
        _DetailRow(label: '通称', value: _nickname.text),
      _DetailRow(label: '郵便番号', value: _postalCode.text),
      _DetailRow(label: '住所', value: _address.text),
      if (_error != null) _ErrorText(_error!),
    ],
  );

  void _toConfirm() {
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _confirming = true;
      _error = null;
      _operationKey = createOrderIdempotencyKey();
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final input = CustomerInput(
      code: _code.text,
      name: _name.text,
      nickname: _nickname.text,
      postalCode: _postalCode.text,
      address: _address.text,
    );
    try {
      if (widget.existing == null) {
        await widget.repository.registerCustomer(
          input,
          idempotencyKey: _operationKey!,
        );
      } else {
        await widget.repository.updateCustomer(
          widget.existing!,
          input,
          reason: _reason.text,
          idempotencyKey: _operationKey!,
        );
      }
      if (mounted) {
        setState(() {
          _saving = false;
          _completed = true;
        });
      }
    } on OrderManagementFailure catch (failure) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failure.message;
        });
      }
    }
  }
}

class DestinationFormDialog extends StatefulWidget {
  const DestinationFormDialog({
    required this.repository,
    required this.customer,
    this.existing,
    super.key,
  });
  final OrderManagementRepository repository;
  final CustomerSummary customer;
  final ShippingDestination? existing;
  @override
  State<DestinationFormDialog> createState() => _DestinationFormDialogState();
}

class _DestinationFormDialogState extends State<DestinationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _recipient;
  late final TextEditingController _postal;
  late final TextEditingController _address;
  final _reason = TextEditingController();
  bool _confirming = false;
  bool _saving = false;
  bool _completed = false;
  String? _error;
  String? _operationKey;

  @override
  void initState() {
    super.initState();
    final value = widget.existing;
    _name = TextEditingController(text: value?.name ?? '');
    _recipient = TextEditingController(text: value?.recipientName ?? '');
    _postal = TextEditingController(text: value?.postalCode ?? '');
    _address = TextEditingController(text: value?.address ?? '');
  }

  @override
  void dispose() {
    for (final controller in [_name, _recipient, _postal, _address, _reason]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _completed
          ? '登録完了'
          : widget.existing == null
          ? '配送先を追加'
          : '配送先を編集',
    ),
    content: SizedBox(
      width: 520,
      child: _completed
          ? Text('${_name.text} を保存しました。')
          : _confirming
          ? _confirmation()
          : _form(),
    ),
    actions: _completed
        ? [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('閉じる'),
            ),
          ]
        : _confirming
        ? [
            OutlinedButton(
              onPressed: _saving
                  ? null
                  : () => setState(() => _confirming = false),
              child: const Text('入力へ戻る'),
            ),
            FilledButton(
              key: const Key('destination-save'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中' : 'この内容で保存'),
            ),
          ]
        : [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              key: const Key('destination-confirm'),
              onPressed: _toConfirm,
              child: const Text('入力内容を確認'),
            ),
          ],
  );

  Widget _form() => Form(
    key: _formKey,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '顧客　${widget.customer.displayName}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 16),
          _Field(
            label: '配送先名',
            controller: _name,
            keyValue: 'destination-name',
          ),
          _Field(
            label: '受取人名',
            controller: _recipient,
            keyValue: 'destination-recipient',
          ),
          _Field(
            label: '郵便番号',
            controller: _postal,
            keyValue: 'destination-postal-code',
          ),
          _Field(
            label: '住所',
            controller: _address,
            keyValue: 'destination-address',
            lines: 2,
          ),
          if (widget.existing != null)
            _Field(
              label: '変更理由',
              controller: _reason,
              keyValue: 'destination-reason',
            ),
          if (_error != null) _ErrorText(_error!),
        ],
      ),
    ),
  );
  Widget _confirmation() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _DetailRow(label: '顧客', value: widget.customer.displayName),
      _DetailRow(label: '配送先名', value: _name.text),
      _DetailRow(label: '受取人名', value: _recipient.text),
      _DetailRow(label: '郵便番号', value: _postal.text),
      _DetailRow(label: '住所', value: _address.text),
      if (_error != null) _ErrorText(_error!),
    ],
  );
  void _toConfirm() {
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _confirming = true;
      _error = null;
      _operationKey = createOrderIdempotencyKey();
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final input = DestinationInput(
      customerId: widget.customer.id,
      name: _name.text,
      recipientName: _recipient.text,
      postalCode: _postal.text,
      address: _address.text,
    );
    try {
      if (widget.existing == null) {
        await widget.repository.registerDestination(
          input,
          idempotencyKey: _operationKey!,
        );
      } else {
        await widget.repository.updateDestination(
          widget.existing!,
          input,
          reason: _reason.text,
          idempotencyKey: _operationKey!,
        );
      }
      if (mounted) {
        setState(() {
          _saving = false;
          _completed = true;
        });
      }
    } on OrderManagementFailure catch (failure) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failure.message;
        });
      }
    }
  }
}

class OrderFormDialog extends StatefulWidget {
  const OrderFormDialog({
    required this.repository,
    required this.data,
    this.existing,
    super.key,
  });
  final OrderManagementRepository repository;
  final OrderManagementData data;
  final OrderDetail? existing;
  @override
  State<OrderFormDialog> createState() => _OrderFormDialogState();
}

class _OrderFormDialogState extends State<OrderFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _weight = TextEditingController();
  final _notes = TextEditingController();
  final _reason = TextEditingController();
  String? _customerId;
  String? _destinationId;
  String? _varietyId;
  String? _gradeId;
  late DateTime _orderedOn;
  late DateTime _shipOn;
  List<ShippingDestination> _destinations = const [];
  bool _loadingDestinations = true;
  bool _confirming = false;
  bool _saving = false;
  bool _completed = false;
  String? _resultNumber;
  String? _error;
  String? _operationKey;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final now = DateTime.now();
    _customerId =
        existing?.item.customerId ??
        widget.data.customerOptions.firstOrNull?.id;
    _destinationId = existing?.shippingDestinationId;
    _varietyId =
        existing?.item.varietyId ?? widget.data.varieties.firstOrNull?.id;
    _gradeId = existing?.item.gradeId ?? widget.data.grades.firstOrNull?.id;
    _orderedOn =
        existing?.item.orderedOn ?? DateTime(now.year, now.month, now.day);
    _shipOn = existing?.item.scheduledShipOn ?? _orderedOn;
    _weight.text = existing?.item.orderedWeight.toStringAsFixed(2) ?? '';
    _notes.text = existing?.notes ?? '';
    _loadDestinations();
  }

  @override
  void dispose() {
    _weight.dispose();
    _notes.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadDestinations() async {
    final customerId = _customerId;
    if (customerId == null) {
      setState(() => _loadingDestinations = false);
      return;
    }
    setState(() {
      _loadingDestinations = true;
      _error = null;
    });
    try {
      final values = await widget.repository.loadDestinations(customerId);
      if (!mounted || customerId != _customerId) return;
      setState(() {
        _destinations = values;
        if (values.every((value) => value.id != _destinationId)) {
          _destinationId = values.firstOrNull?.id;
        }
        _loadingDestinations = false;
      });
    } on OrderManagementFailure catch (failure) {
      if (mounted) {
        setState(() {
          _loadingDestinations = false;
          _error = failure.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _completed
          ? '登録完了'
          : widget.existing == null
          ? '受注を登録'
          : '受注を編集',
    ),
    content: SizedBox(
      width: 620,
      child: _completed
          ? Text(
              '${_resultNumber ?? widget.existing?.item.number ?? ''} を保存しました。',
            )
          : _confirming
          ? _confirmation()
          : _form(),
    ),
    actions: _completed
        ? [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('閉じる'),
            ),
          ]
        : _confirming
        ? [
            OutlinedButton(
              onPressed: _saving
                  ? null
                  : () => setState(() => _confirming = false),
              child: const Text('入力へ戻る'),
            ),
            FilledButton(
              key: const Key('order-save'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中' : 'この内容で保存'),
            ),
          ]
        : [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              key: const Key('order-confirm-input'),
              onPressed: _loadingDestinations ? null : _toConfirm,
              child: const Text('入力内容を確認'),
            ),
          ],
  );

  Widget _form() => Form(
    key: _formKey,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '顧客',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: const Key('order-customer'),
            initialValue: _customerId,
            icon: const SizedBox.shrink(),
            items: [
              for (final customer in widget.data.customerOptions)
                DropdownMenuItem(
                  value: customer.id,
                  child: Text('${customer.code}　${customer.displayName}'),
                ),
            ],
            onChanged: (value) {
              setState(() {
                _customerId = value;
                _destinationId = null;
              });
              _loadDestinations();
            },
            validator: (value) => value == null ? '顧客を選択してください。' : null,
          ),
          const SizedBox(height: 14),
          const Text(
            '配送先',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: const Key('order-destination'),
            initialValue: _destinationId,
            icon: const SizedBox.shrink(),
            items: [
              for (final value in _destinations)
                DropdownMenuItem(
                  value: value.id,
                  child: Text('${value.name}　${value.recipientName}'),
                ),
            ],
            onChanged: _loadingDestinations
                ? null
                : (value) => setState(() => _destinationId = value),
            validator: (value) => value == null ? '配送先を選択してください。' : null,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: '注文日',
                  keyValue: 'order-date',
                  date: _orderedOn,
                  onChanged: (value) => _orderedOn = value,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateField(
                  label: '出荷予定日',
                  keyValue: 'order-ship-date',
                  date: _shipOn,
                  onChanged: (value) => _shipOn = value,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ReferenceSelect(
                  label: '品種',
                  keyValue: 'order-variety',
                  value: _varietyId,
                  values: widget.data.varieties,
                  onChanged: (value) => setState(() => _varietyId = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ReferenceSelect(
                  label: '等級',
                  keyValue: 'order-grade',
                  value: _gradeId,
                  values: widget.data.grades,
                  onChanged: (value) => setState(() => _gradeId = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Field(
            label: '注文量（kg）',
            controller: _weight,
            keyValue: 'order-weight',
            number: true,
          ),
          _Field(
            label: '備考（任意）',
            controller: _notes,
            keyValue: 'order-notes',
            required: false,
            lines: 2,
          ),
          if (widget.existing != null)
            _Field(
              label: '変更理由',
              controller: _reason,
              keyValue: 'order-reason',
            ),
          if (_error != null) _ErrorText(_error!),
        ],
      ),
    ),
  );

  Widget _confirmation() {
    final customer = widget.data.customerOptions
        .where((item) => item.id == _customerId)
        .firstOrNull;
    final destination = _destinations
        .where((item) => item.id == _destinationId)
        .firstOrNull;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailRow(label: '顧客', value: customer?.displayName ?? ''),
          _DetailRow(label: '配送先', value: destination?.name ?? ''),
          _DetailRow(label: '注文日', value: _displayDate(_orderedOn)),
          _DetailRow(label: '出荷予定日', value: _displayDate(_shipOn)),
          _DetailRow(
            label: '品種・等級',
            value:
                '${widget.data.varietyLabel(_varietyId ?? '')}・${widget.data.gradeLabel(_gradeId ?? '')}',
          ),
          _DetailRow(
            label: '注文量',
            value: '${double.tryParse(_weight.text)?.toStringAsFixed(2)} kg',
            strong: true,
          ),
          if (_error != null) _ErrorText(_error!),
        ],
      ),
    );
  }

  void _toConfirm() {
    setState(() => _error = null);
    if (_formKey.currentState?.validate() != true) return;
    if (_shipOn.isBefore(_orderedOn)) {
      setState(() => _error = '出荷予定日は注文日以降を指定してください。');
      return;
    }
    final weight = double.tryParse(_weight.text);
    if (weight == null ||
        !weight.isFinite ||
        weight <= 0 ||
        !RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(_weight.text.trim())) {
      setState(() => _error = '注文量は0より大きい0.01kg単位で入力してください。');
      return;
    }
    setState(() => _confirming = true);
    _operationKey = createOrderIdempotencyKey();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final input = OrderInput(
      customerId: _customerId!,
      destinationId: _destinationId!,
      orderedOn: _orderedOn,
      scheduledShipOn: _shipOn,
      varietyId: _varietyId!,
      gradeId: _gradeId!,
      orderedWeight: double.parse(_weight.text),
      notes: _notes.text,
    );
    try {
      final result = widget.existing == null
          ? await widget.repository.registerOrder(
              input,
              idempotencyKey: _operationKey!,
            )
          : await widget.repository.updateOrder(
              widget.existing!,
              input,
              reason: _reason.text,
              idempotencyKey: _operationKey!,
            );
      if (mounted) {
        setState(() {
          _resultNumber = result.number;
          _saving = false;
          _completed = true;
        });
      }
    } on OrderManagementFailure catch (failure) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failure.message;
        });
      }
    }
  }
}

class OrderTransitionDialog extends StatefulWidget {
  const OrderTransitionDialog({
    required this.repository,
    required this.order,
    required this.confirm,
    super.key,
  });
  final OrderManagementRepository repository;
  final OrderDetail order;
  final bool confirm;
  @override
  State<OrderTransitionDialog> createState() => _OrderTransitionDialogState();
}

class _OrderTransitionDialogState extends State<OrderTransitionDialog> {
  final _reason = TextEditingController();
  bool _saving = false;
  bool _completed = false;
  String? _error;
  String? _operationKey;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _completed
          ? '更新完了'
          : widget.confirm
          ? '受注を確定'
          : '受注をキャンセル',
    ),
    content: SizedBox(
      width: 480,
      child: _completed
          ? Text(
              '${widget.order.item.number} を${widget.confirm ? '確定' : 'キャンセル'}しました。',
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DetailRow(label: '受注番号', value: widget.order.item.number),
                _DetailRow(
                  label: '注文量',
                  value:
                      '${widget.order.item.orderedWeight.toStringAsFixed(2)} kg',
                  strong: true,
                ),
                const SizedBox(height: 16),
                _Field(
                  label: widget.confirm ? '確定理由' : 'キャンセル理由',
                  controller: _reason,
                  keyValue: 'order-transition-reason',
                  onChanged: (_) => _operationKey = null,
                ),
                if (!widget.confirm)
                  const Text(
                    '関連する作業前の割当と予約が解除されます。',
                    style: TextStyle(color: AppColors.error),
                  ),
                if (_error != null) _ErrorText(_error!),
              ],
            ),
    ),
    actions: _completed
        ? [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('閉じる'),
            ),
          ]
        : [
            OutlinedButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('戻る'),
            ),
            FilledButton(
              key: const Key('order-transition-save'),
              onPressed: _saving ? null : _save,
              style: !widget.confirm
                  ? FilledButton.styleFrom(backgroundColor: AppColors.error)
                  : null,
              child: Text(
                _saving
                    ? '処理中'
                    : widget.confirm
                    ? '受注を確定'
                    : '受注をキャンセル',
              ),
            ),
          ],
  );

  Future<void> _save() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = '理由を入力してください。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    _operationKey ??= createOrderIdempotencyKey();
    try {
      if (widget.confirm) {
        await widget.repository.confirmOrder(
          widget.order,
          reason: _reason.text,
          idempotencyKey: _operationKey!,
        );
      } else {
        await widget.repository.cancelOrder(
          widget.order,
          reason: _reason.text,
          idempotencyKey: _operationKey!,
        );
      }
      if (mounted) {
        setState(() {
          _saving = false;
          _completed = true;
        });
      }
    } on OrderManagementFailure catch (failure) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failure.message;
        });
      }
    }
  }
}

class _ReferenceSelect extends StatelessWidget {
  const _ReferenceSelect({
    required this.label,
    required this.keyValue,
    required this.value,
    required this.values,
    required this.onChanged,
  });
  final String label;
  final String keyValue;
  final String? value;
  final List<OrderReference> values;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        key: Key(keyValue),
        initialValue: value,
        icon: const SizedBox.shrink(),
        items: [
          for (final item in values)
            DropdownMenuItem(value: item.id, child: Text(item.label)),
        ],
        onChanged: onChanged,
        validator: (value) => value == null ? '$labelを選択してください。' : null,
      ),
    ],
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.keyValue,
    required this.date,
    required this.onChanged,
  });
  final String label;
  final String keyValue;
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      TextFormField(
        key: Key(keyValue),
        initialValue: _inputDate(date),
        keyboardType: TextInputType.datetime,
        onChanged: (value) {
          final parsed = _parseInputDate(value);
          if (parsed != null) onChanged(parsed);
        },
        validator: (value) => _parseInputDate(value ?? '') == null
            ? 'YYYY-MM-DD形式で入力してください。'
            : null,
      ),
    ],
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.keyValue,
    this.required = true,
    this.lines = 1,
    this.number = false,
    this.onChanged,
  });
  final String label;
  final TextEditingController controller;
  final String keyValue;
  final bool required;
  final int lines;
  final bool number;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextFormField(
          key: Key(keyValue),
          controller: controller,
          minLines: lines,
          maxLines: lines,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          onChanged: onChanged,
          validator: (value) =>
              required && (value == null || value.trim().isEmpty)
              ? '$labelを入力してください。'
              : null,
        ),
      ],
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      message,
      style: const TextStyle(
        color: AppColors.error,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

String _displayDate(DateTime value) =>
    '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

String _inputDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

DateTime? _parseInputDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  final parsed = DateTime.tryParse(value);
  return parsed != null && _inputDate(parsed) == value ? parsed : null;
}
