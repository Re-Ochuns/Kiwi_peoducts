import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/common_state_view.dart';
import 'shipping_repository.dart';

class ShippingPage extends StatefulWidget {
  const ShippingPage({
    required this.repository,
    this.initialOrderId,
    this.currentDate,
    this.embedded = false,
    super.key,
  });

  final ShippingRepository repository;
  final String? initialOrderId;
  final DateTime? currentDate;
  final bool embedded;

  @override
  State<ShippingPage> createState() => _ShippingPageState();
}

class _ShippingPageState extends State<ShippingPage> {
  List<ShippingOrderSummary>? _orders;
  ShippingOrderDetail? _detail;
  ShippingFailure? _failure;
  final Map<String, TextEditingController> _weightControllers = {};
  final _shippedAtController = TextEditingController();
  final _reasonController = TextEditingController(text: '出荷内容確認済み');
  final _notesController = TextEditingController();
  String? _selectedOrderId;
  String? _workerId;
  String? _confirmKey;
  _PendingCancel? _pendingCancel;
  bool _loadingOrders = true;
  bool _loadingDetail = false;
  bool _submitting = false;
  int _detailRequest = 0;

  @override
  void initState() {
    super.initState();
    _selectedOrderId = widget.initialOrderId;
    _shippedAtController.text = _formatInputDate(
      (widget.currentDate ?? DateTime.now()).toLocal(),
    );
    _loadOrders();
  }

  @override
  void dispose() {
    for (final controller in _weightControllers.values) {
      controller.dispose();
    }
    _shippedAtController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _loadingOrders = true;
      _failure = null;
    });
    try {
      final orders = await widget.repository.loadOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _loadingOrders = false;
      });
      final initialId = _selectedOrderId;
      if (initialId != null) await _loadDetail(initialId);
    } on ShippingFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _loadingOrders = false;
      });
    }
  }

  Future<bool> _loadDetail(String orderId) async {
    final request = ++_detailRequest;
    setState(() {
      _selectedOrderId = orderId;
      _loadingDetail = true;
      _detail = null;
      _failure = null;
    });
    try {
      final detail = await widget.repository.loadOrder(orderId);
      if (!mounted || request != _detailRequest) return false;
      for (final controller in _weightControllers.values) {
        controller.dispose();
      }
      _weightControllers.clear();
      for (final container in detail.containers) {
        _weightControllers[container.id] = TextEditingController();
      }
      setState(() {
        _detail = detail;
        _orders = [
          for (final order in _orders ?? <ShippingOrderSummary>[])
            order.id == detail.order.id ? detail.order : order,
        ];
        _workerId = detail.workers.any((worker) => worker.id == _workerId)
            ? _workerId
            : detail.workers.firstOrNull?.id;
        _loadingDetail = false;
        _confirmKey = null;
        _pendingCancel = null;
      });
      return true;
    } on ShippingFailure catch (failure) {
      if (!mounted || request != _detailRequest) return false;
      setState(() {
        _failure = failure;
        _loadingDetail = false;
      });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = LayoutBuilder(
      builder: (context, constraints) {
        if (_loadingOrders && _orders == null) {
          return CommonStateView.loading(title: '出荷予定を読み込んでいます');
        }
        if (_failure != null && _orders == null) {
          return CommonStateView.error(
            title: '出荷予定を表示できません',
            message: _failure!.message,
            actionLabel: _failure!.retryable ? '再試行' : null,
            onAction: _failure!.retryable ? _loadOrders : null,
          );
        }
        if (constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 360, child: _buildOrderList()),
              const VerticalDivider(width: 1),
              Expanded(
                child: _selectedOrderId == null
                    ? const CommonStateView.empty(
                        title: '出荷予定を選択してください',
                        message: '受注と使用コンテナを確認できます。',
                      )
                    : _buildDetail(),
              ),
            ],
          );
        }
        return _selectedOrderId == null ? _buildOrderList() : _buildDetail();
      },
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 8,
        title: TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('← ToDoへ戻る'),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _buildOrderList() {
    final orders = _orders ?? const <ShippingOrderSummary>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '出荷予定・実績',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '${orders.length}件',
            style: const TextStyle(color: AppColors.mutedText),
          ),
          const SizedBox(height: 18),
          if (orders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Text('出荷予定・実績はありません'),
            )
          else
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Column(
                children: [
                  for (final order in orders)
                    _OrderRow(
                      order: order,
                      selected: order.id == _selectedOrderId,
                      onTap: _submitting ? null : () => _loadDetail(order.id),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetail() {
    if (_loadingDetail || _detail == null) {
      if (_failure != null && !_loadingDetail) {
        return CommonStateView.error(
          title: '出荷詳細を表示できません',
          message: _failure!.message,
          actionLabel: _failure!.retryable ? '再試行' : null,
          onAction: _failure!.retryable
              ? () => _loadDetail(_selectedOrderId!)
              : null,
        );
      }
      return CommonStateView.loading(title: '出荷詳細を読み込んでいます');
    }
    final detail = _detail!;
    final input = _buildInput(detail);
    final validation = _validationMessage(detail);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (MediaQuery.sizeOf(context).width < 900 &&
                  widget.initialOrderId == null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                            _selectedOrderId = null;
                            _detail = null;
                            _failure = null;
                          }),
                    child: const Text('← 出荷予定へ戻る'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const Text(
                '出荷内容',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              _OrderSummary(detail: detail),
              const SizedBox(height: 28),
              const Text(
                '使用コンテナと出荷重量',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '出荷残量 ${formatShippingWeight(detail.order.remainingWeightHundredths)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (detail.containers.isEmpty)
                const _InlineNotice(message: 'この受注に使用できる追熟コンテナがありません')
              else
                DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.line)),
                  ),
                  child: Column(
                    children: [
                      for (final container in detail.containers)
                        _ContainerInputRow(
                          container: container,
                          controller: _weightControllers[container.id]!,
                          enabled: !_submitting,
                          onChanged: _inputChanged,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 22),
              TextField(
                key: const Key('shipping-shipped-at'),
                controller: _shippedAtController,
                enabled: !_submitting,
                onChanged: _inputChanged,
                decoration: const InputDecoration(
                  labelText: '出荷日時（YYYY/MM/DD HH:mm）',
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                key: const Key('shipping-worker'),
                initialValue: _workerId,
                isExpanded: true,
                icon: const ExcludeSemantics(
                  child: Text('▼', style: TextStyle(fontSize: 12)),
                ),
                decoration: const InputDecoration(labelText: '担当者'),
                items: [
                  for (final worker in detail.workers)
                    DropdownMenuItem(
                      value: worker.id,
                      child: Text(worker.label),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() {
                        _workerId = value;
                        _clearConfirmOperation();
                      }),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('shipping-reason'),
                controller: _reasonController,
                enabled: !_submitting,
                onChanged: _inputChanged,
                decoration: const InputDecoration(labelText: '確認理由'),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('shipping-notes'),
                controller: _notesController,
                enabled: !_submitting,
                maxLines: 3,
                onChanged: _inputChanged,
                decoration: const InputDecoration(labelText: '備考（任意）'),
              ),
              if (validation != null && _hasWeightInput) ...[
                const SizedBox(height: 12),
                Text(
                  validation,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (_failure != null) ...[
                const SizedBox(height: 16),
                _FailureNotice(
                  failure: _failure!,
                  onReload: _failure!.isConflict
                      ? () => _loadDetail(detail.order.id)
                      : null,
                  onRetryCancel: _failure!.retryable && _pendingCancel != null
                      ? _retryCancel
                      : null,
                ),
              ],
              const SizedBox(height: 24),
              Semantics(
                liveRegion: _submitting,
                child: FilledButton(
                  key: const Key('shipping-confirm-input'),
                  onPressed: !_submitting && input != null && validation == null
                      ? () => _showConfirmation(detail, input)
                      : null,
                  child: Text(
                    _submitting
                        ? '処理結果を確認しています'
                        : _confirmKey != null && _failure?.retryable == true
                        ? '同じ内容で結果を確認'
                        : '入力内容を確認',
                  ),
                ),
              ),
              const SizedBox(height: 36),
              const Text(
                '出荷実績',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (detail.shipments.isEmpty)
                const Text('出荷実績はありません')
              else
                DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.line)),
                  ),
                  child: Column(
                    children: [
                      for (final shipment in detail.shipments)
                        _ShipmentRow(
                          shipment: shipment,
                          enabled: !_submitting,
                          onCancel: shipment.canCancel
                              ? () => _showCancelConfirmation(shipment)
                              : null,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasWeightInput => _weightControllers.values.any(
    (controller) => controller.text.trim().isNotEmpty,
  );

  ShippingConfirmInput? _buildInput(ShippingOrderDetail detail) {
    final shippedAt = _parseInputDate(_shippedAtController.text);
    final workerId = _workerId;
    final reason = _reasonController.text.trim();
    if (shippedAt == null || workerId == null || reason.isEmpty) return null;
    final lines = <ShippingLineInput>[];
    for (final container in detail.containers) {
      final value = _parseWeight(_weightControllers[container.id]?.text ?? '');
      if (value == null || value == 0) continue;
      lines.add(
        ShippingLineInput(
          containerId: container.id,
          expectedVersion: container.version,
          weightHundredths: value,
        ),
      );
    }
    if (lines.isEmpty) return null;
    return ShippingConfirmInput(
      orderId: detail.order.id,
      expectedOrderVersion: detail.order.version,
      shippedAt: shippedAt,
      workerId: workerId,
      reason: reason,
      lines: lines,
      notes: _notesController.text,
    );
  }

  String? _validationMessage(ShippingOrderDetail detail) {
    final shippedAt = _parseInputDate(_shippedAtController.text);
    if (shippedAt == null) return '出荷日時を確認してください';
    final now = (widget.currentDate ?? DateTime.now()).toLocal();
    if (shippedAt.isAfter(now)) return '出荷日時は現在以前にしてください';
    if (_workerId == null) return '担当者を選択してください';
    if (_reasonController.text.trim().isEmpty) return '確認理由を入力してください';
    var total = 0;
    final lotTotals = <String, int>{};
    for (final container in detail.containers) {
      final raw = _weightControllers[container.id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final weight = _parseWeight(raw);
      if (weight == null || weight <= 0) {
        return '出荷重量は0.01kg単位の正の数で入力してください';
      }
      if (weight > container.availableWeightHundredths) {
        return '${container.displayId}の使用可能残量を超えています';
      }
      total += weight;
      lotTotals.update(
        container.ripeningLotId,
        (value) => value + weight,
        ifAbsent: () => weight,
      );
    }
    if (total == 0) return '使用するコンテナの出荷重量を入力してください';
    if (total > detail.order.remainingWeightHundredths) {
      return '受注の出荷残量を超えています';
    }
    for (final entry in lotTotals.entries) {
      if (entry.value >
          (detail.remainingAllocationHundredths[entry.key] ?? 0)) {
        return '同じ追熟計画の割当残量を超えています';
      }
    }
    return null;
  }

  void _inputChanged(String _) => setState(_clearConfirmOperation);

  void _clearConfirmOperation() {
    if (!_submitting) {
      _confirmKey = null;
      _failure = null;
      _pendingCancel = null;
    }
  }

  Future<void> _showConfirmation(
    ShippingOrderDetail detail,
    ShippingConfirmInput input,
  ) async {
    final containers = {for (final item in detail.containers) item.id: item};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('出荷内容の確認'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SummaryRow(label: '受注番号', value: detail.order.number),
              _SummaryRow(label: '取引先', value: detail.order.customer),
              _SummaryRow(
                label: '出荷重量',
                value: formatShippingWeight(
                  input.lines.fold(
                    0,
                    (sum, line) => sum + line.weightHundredths,
                  ),
                ),
              ),
              for (final line in input.lines)
                _SummaryRow(
                  label: containers[line.containerId]!.displayId,
                  value: formatShippingWeight(line.weightHundredths),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('戻って修正'),
          ),
          FilledButton(
            key: const Key('shipping-complete'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('出荷を確定'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _confirm(detail, input);
  }

  Future<void> _confirm(
    ShippingOrderDetail detail,
    ShippingConfirmInput input,
  ) async {
    setState(() {
      _submitting = true;
      _failure = null;
      _pendingCancel = null;
      _confirmKey ??= createShippingIdempotencyKey();
    });
    try {
      final completion = await widget.repository.confirm(
        input: input,
        idempotencyKey: _confirmKey!,
      );
      if (!mounted) return;
      _confirmKey = null;
      final refreshed = await _loadDetail(detail.order.id);
      final refreshedDetail = refreshed ? _detail : null;
      if (!mounted) return;
      setState(() => _submitting = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('出荷を記録しました'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SummaryRow(label: '出荷ID', value: completion.shipment.displayId),
              _SummaryRow(
                label: '出荷重量',
                value: formatShippingWeight(
                  completion.shipment.totalWeightHundredths,
                ),
              ),
              if (refreshedDetail != null)
                _SummaryRow(
                  label: '受注残量',
                  value: formatShippingWeight(
                    refreshedDetail.order.remainingWeightHundredths,
                  ),
                )
              else
                const Text('出荷は記録済みです。最新の残量を取得できなかったため、詳細を再読み込みしてください。'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                refreshedDetail?.order.status == 'shipped' && !widget.embedded
                    ? 'ToDoへ戻る'
                    : refreshedDetail == null
                    ? '詳細の再読み込みへ'
                    : '出荷内容へ戻る',
              ),
            ),
          ],
        ),
      );
      if (mounted &&
          refreshedDetail?.order.status == 'shipped' &&
          !widget.embedded) {
        Navigator.of(context).pop(true);
      }
    } on ShippingFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _failure = failure;
        if (!failure.retryable) _confirmKey = null;
      });
    }
  }

  Future<void> _showCancelConfirmation(ShipmentRecord shipment) async {
    final request = await showDialog<String>(
      context: context,
      builder: (context) => _CancelDialog(shipment: shipment),
    );
    if (request == null) return;
    final pending = _PendingCancel(
      shipment: shipment,
      reason: request,
      idempotencyKey: createShippingIdempotencyKey(),
    );
    setState(() => _pendingCancel = pending);
    await _cancel(pending);
  }

  Future<void> _retryCancel() async {
    final pending = _pendingCancel;
    if (pending != null) await _cancel(pending);
  }

  Future<void> _cancel(_PendingCancel pending) async {
    final orderId = _selectedOrderId!;
    setState(() {
      _submitting = true;
      _failure = null;
    });
    try {
      await widget.repository.cancel(
        shipmentId: pending.shipment.id,
        expectedVersion: pending.shipment.version,
        reason: pending.reason,
        idempotencyKey: pending.idempotencyKey,
      );
      if (!mounted) return;
      _pendingCancel = null;
      await _loadDetail(orderId);
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('出荷を取り消しました')));
    } on ShippingFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _failure = failure;
        if (!failure.retryable) _pendingCancel = null;
      });
    }
  }
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog({required this.shipment});

  final ShipmentRecord shipment;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reason = TextEditingController(text: '出荷取消確認済み');

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('出荷取消の確認'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SummaryRow(label: '出荷ID', value: widget.shipment.displayId),
          _SummaryRow(
            label: '出荷重量',
            value: formatShippingWeight(widget.shipment.totalWeightHundredths),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('shipping-cancel-reason'),
            controller: _reason,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: '取消理由'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('戻る'),
      ),
      FilledButton(
        key: const Key('shipping-cancel-complete'),
        onPressed: _reason.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(_reason.text.trim()),
        child: const Text('出荷を取り消す'),
      ),
    ],
  );
}

class _PendingCancel {
  const _PendingCancel({
    required this.shipment,
    required this.reason,
    required this.idempotencyKey,
  });

  final ShipmentRecord shipment;
  final String reason;
  final String idempotencyKey;
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.selected,
    required this.onTap,
  });

  final ShippingOrderSummary order;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${order.number}の出荷内容を見る',
    button: true,
    selected: selected,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF2F6F3) : null,
          border: const Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.number,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(order.customer),
                  Text(_shippingOrderStatusLabel(order.status)),
                  Text(
                    '出荷日 ${_formatDate(order.scheduledShipOn)}',
                    style: const TextStyle(color: AppColors.mutedText),
                  ),
                  Text(
                    '${order.variety}・${order.grade}　${formatShippingWeight(order.orderedWeightHundredths)}',
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

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.detail});

  final ShippingOrderDetail detail;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: Column(
      children: [
        _SummaryRow(label: '受注番号', value: detail.order.number, prominent: true),
        _SummaryRow(label: '取引先', value: detail.order.customer),
        _SummaryRow(
          label: '出荷日',
          value: _formatDate(detail.order.scheduledShipOn),
        ),
        _SummaryRow(
          label: '品種・等級',
          value: '${detail.order.variety}・${detail.order.grade}',
        ),
        _SummaryRow(
          label: '受注重量',
          value: formatShippingWeight(detail.order.orderedWeightHundredths),
          prominent: true,
        ),
        _SummaryRow(
          label: '受注状態',
          value: _shippingOrderStatusLabel(detail.order.status),
        ),
        _SummaryRow(label: '配送先', value: detail.destination),
      ],
    ),
  );
}

class _ContainerInputRow extends StatelessWidget {
  const _ContainerInputRow({
    required this.container,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final ShippingContainer container;
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          container.displayId,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '${container.useLabel}　現在 ${formatShippingWeight(container.currentWeightHundredths)}',
        ),
        Text(
          '使用可能 ${formatShippingWeight(container.availableWeightHundredths)}　期限 ${_formatDateTime(container.shippableUntil)}',
          style: const TextStyle(color: AppColors.mutedText),
        ),
        const SizedBox(height: 10),
        TextField(
          key: Key('shipping-weight-${container.id}'),
          controller: controller,
          enabled: enabled && container.availableWeightHundredths > 0,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: onChanged,
          decoration: const InputDecoration(labelText: 'このコンテナから出荷する重量（kg）'),
        ),
      ],
    ),
  );
}

class _ShipmentRow extends StatelessWidget {
  const _ShipmentRow({
    required this.shipment,
    required this.enabled,
    this.onCancel,
  });

  final ShipmentRecord shipment;
  final bool enabled;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          shipment.displayId,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '${formatShippingWeight(shipment.totalWeightHundredths)}　${_formatDateTime(shipment.shippedAt)}',
        ),
        Text(
          shipment.status == 'cancelled' ? '取消済み' : '出荷済み',
          style: TextStyle(
            color: shipment.status == 'cancelled'
                ? AppColors.error
                : AppColors.mutedText,
          ),
        ),
        if (shipment.cancellationReason?.trim().isNotEmpty == true)
          Text('取消理由 ${shipment.cancellationReason}'),
        if (onCancel != null) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: enabled ? onCancel : null,
            child: const Text('この出荷を取り消す'),
          ),
        ],
      ],
    ),
  );
}

class _FailureNotice extends StatelessWidget {
  const _FailureNotice({
    required this.failure,
    this.onReload,
    this.onRetryCancel,
  });

  final ShippingFailure failure;
  final VoidCallback? onReload;
  final VoidCallback? onRetryCancel;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.error),
      borderRadius: BorderRadius.circular(AppRadius.control),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          failure.message,
          style: const TextStyle(
            color: AppColors.error,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (failure.correlationId != null) ...[
          const SizedBox(height: 6),
          Text('問い合わせ番号 ${failure.correlationId}'),
        ],
        if (onReload != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onReload, child: const Text('最新状態を読み込む')),
        ],
        if (onRetryCancel != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetryCancel,
            child: const Text('同じ取消内容で結果を確認'),
          ),
        ],
      ],
    ),
  );
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: const BoxDecoration(
      border: Border(
        top: BorderSide(color: AppColors.line),
        bottom: BorderSide(color: AppColors.line),
      ),
    ),
    child: Text(message),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.prominent = false,
  });

  final String label;
  final String value;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: AppColors.mutedText),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: prominent ? 22 : 16,
            fontWeight: prominent ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

int? _parseWeight(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return 0;
  final value = double.tryParse(text);
  if (value == null || !value.isFinite || value < 0) return null;
  final scaled = value * 100;
  if ((scaled - scaled.round()).abs() > 0.000001) return null;
  return scaled.round();
}

DateTime? _parseInputDate(String raw) {
  final match = RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})\s+(\d{1,2}):(\d{2})$')
      .firstMatch(raw.trim());
  if (match == null) return null;
  final values = [for (var i = 1; i <= 5; i++) int.parse(match.group(i)!)];
  final value = DateTime(values[0], values[1], values[2], values[3], values[4]);
  if (value.year != values[0] ||
      value.month != values[1] ||
      value.day != values[2] ||
      value.hour != values[3] ||
      value.minute != values[4]) {
    return null;
  }
  return value;
}

String _formatInputDate(DateTime value) =>
    '${value.year}/${_two(value.month)}/${_two(value.day)} '
    '${_two(value.hour)}:${_two(value.minute)}';

String _formatDate(DateTime value) =>
    '${value.year}年${value.month}月${value.day}日';

String _formatDateTime(DateTime value) =>
    '${_formatDate(value)} ${_two(value.hour)}:${_two(value.minute)}';

String _shippingOrderStatusLabel(String status) => switch (status) {
  'confirmed' => '出荷待ち',
  'in_progress' => '準備中',
  'partially_shipped' => '一部出荷',
  'shipped' => '出荷完了',
  'cancelled' => '取消済み',
  _ => '要確認',
};

String _two(int value) => value.toString().padLeft(2, '0');
