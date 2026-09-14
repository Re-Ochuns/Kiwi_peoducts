import 'package:flutter/material.dart';

import 'order_management_repository.dart';

class OrderInventoryPicker extends StatefulWidget {
  const OrderInventoryPicker({
    super.key,
    required this.repository,
    required this.data,
    required this.initial,
    required this.onSelected,
    this.orderId,
    this.varietyId,
    this.gradeId,
  });
  final OrderInventoryRepository repository;
  final OrderManagementData data;
  final List<OrderStockReservation> initial;
  final String? orderId, varietyId, gradeId;
  final void Function(List<OrderStockReservation>, String, String) onSelected;
  @override
  State<OrderInventoryPicker> createState() => _OrderInventoryPickerState();
}

class _OrderInventoryPickerState extends State<OrderInventoryPicker> {
  final _search = TextEditingController();
  late Map<String, OrderStockReservation> _selected;
  String? _variety, _grade, _error;
  List<OrderStock> _rows = [];
  bool _loading = true, _more = false;
  int _offset = 0, _request = 0;
  @override
  void initState() {
    super.initState();
    _selected = {for (final r in widget.initial) r.containerId: r};
    _variety = widget.varietyId;
    _grade = widget.gradeId;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.repository.loadInventory(
        search: _search.text,
        varietyId: _variety,
        gradeId: _grade,
        offset: _offset,
        orderId: widget.orderId,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _rows = rows.take(50).toList();
        _more = rows.length > 50;
        _loading = false;
      });
    } on OrderManagementFailure catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  void _toggle(OrderStock stock, bool selected) {
    setState(() {
      if (!selected) {
        _selected.remove(stock.id);
        return;
      }
      _variety = stock.varietyId;
      _grade = stock.gradeId;
      _selected[stock.id] = OrderStockReservation(
        containerId: stock.id,
        displayId: stock.displayId,
        weightHundredths: stock.available + stock.ownReserved,
      );
    });
  }

  String _kg(int n) => (n / 100).toStringAsFixed(2);
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 530,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('利用可能な在庫を確認して選択してください。入力中は予約されません。'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(labelText: 'コンテナIDで検索'),
                onSubmitted: (_) {
                  _offset = 0;
                  _load();
                },
              ),
            ),
            IconButton(
              tooltip: '在庫を検索・更新',
              onPressed: _loading
                  ? null
                  : () {
                      _offset = 0;
                      _load();
                    },
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('variety-$_variety'),
                initialValue: _variety,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '品種'),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('すべて'),
                  ),
                  for (final v in widget.data.varieties)
                    DropdownMenuItem(value: v.id, child: Text(v.label)),
                ],
                onChanged: _selected.isNotEmpty
                    ? null
                    : (v) {
                        _variety = v;
                        _offset = 0;
                        _load();
                      },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('grade-$_grade'),
                initialValue: _grade,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '等級'),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('すべて'),
                  ),
                  for (final v in widget.data.grades)
                    DropdownMenuItem(value: v.id, child: Text(v.label)),
                ],
                onChanged: _selected.isNotEmpty
                    ? null
                    : (v) {
                        _grade = v;
                        _offset = 0;
                        _load();
                      },
              ),
            ),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(onPressed: _load, child: const Text('再試行')),
                    ],
                  ),
                )
              : _rows.isEmpty
              ? const Center(child: Text('利用可能な在庫はありません。'))
              : ListView(
                  children: [
                    for (final stock in _rows)
                      CheckboxListTile(
                        value: _selected.containsKey(stock.id),
                        onChanged:
                            _selected.isNotEmpty &&
                                (_variety != stock.varietyId ||
                                    _grade != stock.gradeId)
                            ? null
                            : (v) => _toggle(stock, v == true),
                        title: Text(
                          '${stock.displayId}　${stock.varietyLabel}・${stock.gradeLabel}',
                        ),
                        subtitle: Text(
                          '利用可能 ${_kg(stock.available)} kg　現在 ${_kg(stock.current)} kg　予約 ${_kg(stock.reserved)} kg\n'
                          '${stock.origin}　選果 ${stock.sortedOn}　${stock.location}',
                        ),
                      ),
                  ],
                ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _loading || _offset == 0
                  ? null
                  : () {
                      _offset -= 50;
                      _load();
                    },
              child: const Text('前へ'),
            ),
            Text('${_offset ~/ 50 + 1} ページ'),
            TextButton(
              onPressed: _loading || !_more
                  ? null
                  : () {
                      _offset += 50;
                      _load();
                    },
              child: const Text('次へ'),
            ),
          ],
        ),
        Row(
          children: [
            Text('${_selected.length} 件選択'),
            TextButton(
              onPressed: () => setState(() {
                _selected.clear();
              }),
              child: const Text('選択解除'),
            ),
            const Spacer(),
            Flexible(
              child: FilledButton(
                key: const Key('order-stock-next'),
                onPressed: _selected.isEmpty
                    ? null
                    : () => widget.onSelected(
                        _selected.values.toList(),
                        _variety!,
                        _grade!,
                      ),
                child: const Text('この在庫で受注登録'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
