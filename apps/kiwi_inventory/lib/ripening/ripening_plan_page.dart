import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/common_state_view.dart';
import '../csv_export/business_csv_button.dart';
import '../csv_export/csv_export_repository.dart';
import 'ripening_plan_repository.dart';
import 'supabase_ripening_plan_repository.dart';

class RipeningPlanPage extends StatefulWidget {
  const RipeningPlanPage({
    required this.repository,
    this.csvExportRepository,
    this.currentDate,
    this.embedded = false,
    this.onBusyChanged,
    this.initialInventoryId,
    this.onCompleted,
    super.key,
  });

  final RipeningPlanRepository repository;
  final CsvExportRepository? csvExportRepository;
  final DateTime? currentDate;
  final bool embedded;
  final ValueChanged<bool>? onBusyChanged;
  final String? initialInventoryId;
  final VoidCallback? onCompleted;

  @override
  State<RipeningPlanPage> createState() => _RipeningPlanPageState();
}

class _RipeningPlanPageState extends State<RipeningPlanPage> {
  final _weightController = TextEditingController();
  late final TextEditingController _ethyleneController;
  final _allocations = <_AllocationEditor>[];

  RipeningPlanOptions? _options;
  RipeningPlanFailure? _loadFailure;
  RipeningPlanFailure? _submitFailure;
  RipeningInventoryOption? _inventory;
  String? _locationId;
  String? _workerId;
  bool _loading = true;
  bool _busy = false;
  void _setBusy(bool value) {
    _busy = value;
    widget.onBusyChanged?.call(value);
  }

  RipeningPlanResult? _draft;
  String? _draftSignature;
  String? _registerKey;
  String? _updateKey;
  String? _updateSignature;
  String? _confirmKey;
  int? _confirmVersion;

  static const _processingHours = 168;

  @override
  void initState() {
    super.initState();
    final initial = (widget.currentDate ?? DateTime.now()).toLocal();
    final nextHour = DateTime(
      initial.year,
      initial.month,
      initial.day,
      initial.hour + 1,
    );
    _ethyleneController = TextEditingController(
      text: _formatInputDate(nextHour),
    );
    _weightController.addListener(_onInputChanged);
    _ethyleneController.addListener(_onInputChanged);
    _addAllocation(notify: false);
    _load();
  }

  @override
  void dispose() {
    _weightController.dispose();
    _ethyleneController.dispose();
    for (final allocation in _allocations) {
      allocation.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailure = null;
    });
    try {
      final options = await widget.repository.loadOptions();
      if (!mounted) return;
      setState(() {
        _options = options;
        final initialInventoryId = widget.initialInventoryId;
        if (initialInventoryId != null) {
          _inventory = options.inventories
              .where((inventory) => inventory.id == initialInventoryId)
              .firstOrNull;
        }
        _loading = false;
      });
    } on RipeningPlanFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loadFailure = failure;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: _loading
          ? const CommonStateView.loading(title: '追熟計画の選択肢を読み込んでいます')
          : _loadFailure != null
          ? CommonStateView.error(
              title: '追熟計画を開始できません',
              message: _loadFailure!.message,
              actionLabel: _loadFailure!.retryable ? '再試行' : null,
              onAction: _loadFailure!.retryable ? _load : null,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.csvExportRepository != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: BusinessCsvButton(
                        repository: widget.csvExportRepository!,
                        enabled: !_busy,
                        request: CsvExportRequest.business(
                          dataset: CsvDataset.ripening,
                        ),
                      ),
                    ),
                  ),
                Expanded(child: _buildForm()),
              ],
            ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 8,
        title: TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
          child: const Text('← ToDoへ戻る'),
        ),
      ),
      body: body,
    );
  }

  Widget _buildForm() {
    final options = _options!;
    if (options.inventories.isEmpty) {
      return const CommonStateView.empty(
        title: '使用できる冷蔵在庫がありません',
        message: '冷蔵在庫の状態と予約量を確認してください。',
      );
    }
    if (options.locations.isEmpty || options.workers.isEmpty) {
      return const CommonStateView.empty(
        title: '追熟計画に必要なマスターがありません',
        message: '有効な追熟場所と担当者を確認してください。',
      );
    }
    return PopScope(
      canPop: !_busy,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          widget.embedded ? 32 : 16,
          24,
          widget.embedded ? 32 : 16,
          48,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '追熟計画作成',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
                if (_submitFailure != null) ...[
                  const SizedBox(height: 20),
                  _ErrorMessage(failure: _submitFailure!, draft: _draft),
                ],
                const SizedBox(height: 28),
                const _FormHeading('使用する在庫'),
                const SizedBox(height: 12),
                _LabeledField(
                  label: '冷蔵在庫',
                  child: DropdownButtonFormField<RipeningInventoryOption>(
                    key: const Key('ripening-inventory'),
                    initialValue: _inventory,
                    isExpanded: true,
                    icon: const SizedBox.shrink(),
                    decoration: const InputDecoration(),
                    hint: const Text('選択してください'),
                    items: [
                      for (final inventory in options.inventories)
                        DropdownMenuItem(
                          value: inventory,
                          child: Text(
                            '${inventory.displayId}　使用可能 ${formatRipeningWeight(inventory.availableWeightHundredths)} kg',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy ? null : _selectInventory,
                  ),
                ),
                if (_inventory != null) ...[
                  const SizedBox(height: 12),
                  _InventorySummary(inventory: _inventory!),
                ],
                const SizedBox(height: 16),
                _LabeledField(
                  label: '追熟重量（kg）',
                  child: TextField(
                    key: const Key('ripening-weight'),
                    controller: _weightController,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(hintText: '0.00'),
                  ),
                ),
                const SizedBox(height: 28),
                const _FormHeading('追熟内訳'),
                const SizedBox(height: 6),
                const Text('受注と予備を合わせて、追熟重量と同じ数量にします。'),
                const SizedBox(height: 12),
                for (var index = 0; index < _allocations.length; index++) ...[
                  if (index > 0) const Divider(height: 28),
                  _AllocationFields(
                    index: index,
                    editor: _allocations[index],
                    orders: _eligibleOrders,
                    showNoOrdersMessage: _inventory != null,
                    enabled: !_busy,
                    canRemove: _allocations.length > 1,
                    onTypeChanged: (type) {
                      setState(() {
                        _allocations[index].type = type;
                        _allocations[index].orderId = null;
                        _inputChanged();
                      });
                    },
                    onOrderChanged: (orderId) {
                      setState(() {
                        _allocations[index].orderId = orderId;
                        _inputChanged();
                      });
                    },
                    onRemove: () => _removeAllocation(index),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton(
                  key: const Key('ripening-add-allocation'),
                  onPressed: _busy ? null : _addAllocation,
                  child: const Text('内訳を追加'),
                ),
                const SizedBox(height: 16),
                _WeightSummary(
                  totalHundredths: _totalWeightHundredths,
                  allocatedHundredths: _allocatedWeightHundredths,
                ),
                const SizedBox(height: 30),
                const _FormHeading('場所と予定'),
                const SizedBox(height: 12),
                _LabeledField(
                  label: '追熟場所',
                  child: DropdownButtonFormField<String>(
                    key: const Key('ripening-location'),
                    initialValue: _locationId,
                    isExpanded: true,
                    icon: const SizedBox.shrink(),
                    decoration: const InputDecoration(),
                    hint: const Text('選択してください'),
                    items: [
                      for (final location in options.locations)
                        DropdownMenuItem(
                          value: location.id,
                          child: Text(location.label),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _locationId = value;
                            _inputChanged();
                          }),
                  ),
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  label: 'エチレン注入予定（YYYY-MM-DD HH:mm）',
                  child: TextField(
                    key: const Key('ripening-ethylene-at'),
                    controller: _ethyleneController,
                    enabled: !_busy,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(),
                  ),
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  label: '担当者',
                  child: DropdownButtonFormField<String>(
                    key: const Key('ripening-worker'),
                    initialValue: _workerId,
                    isExpanded: true,
                    icon: const SizedBox.shrink(),
                    decoration: const InputDecoration(),
                    hint: const Text('選択してください'),
                    items: [
                      for (final worker in options.workers)
                        DropdownMenuItem(
                          value: worker.id,
                          child: Text(worker.label),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _workerId = value;
                            _inputChanged();
                          }),
                  ),
                ),
                const SizedBox(height: 24),
                _ScheduleSummary(
                  ethyleneAt: _plannedEthyleneAt,
                  completionAt: _plannedCompletionAt,
                ),
                if (_validationMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _validationMessage!,
                    key: const Key('ripening-validation'),
                    style: const TextStyle(color: Color(0xFF9E2A2B)),
                  ),
                ],
                const SizedBox(height: 28),
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text('追熟計画を登録しています'),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  key: const Key('ripening-review'),
                  onPressed: _canReview && !_busy ? _review : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('入力内容を確認'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<RipeningOrderOption> get _eligibleOrders {
    final inventory = _inventory;
    if (inventory == null) return const [];
    return _options!.orders
        .where(
          (order) =>
              order.varietyId == inventory.varietyId &&
              order.gradeId == inventory.gradeId,
        )
        .toList();
  }

  int? get _totalWeightHundredths => _parseWeight(_weightController.text);

  int get _allocatedWeightHundredths => _allocations.fold(
    0,
    (sum, allocation) =>
        sum + (_parseWeight(allocation.weightController.text) ?? 0),
  );

  DateTime? get _plannedEthyleneAt => _parseInputDate(_ethyleneController.text);

  DateTime? get _plannedCompletionAt =>
      _plannedEthyleneAt?.add(const Duration(hours: _processingHours));

  String? get _validationMessage {
    final inventory = _inventory;
    if (inventory == null) return '冷蔵在庫を選択してください。';
    final total = _totalWeightHundredths;
    if (total == null || total <= 0) return '追熟重量を0.01kg単位で入力してください。';
    if (total > inventory.availableWeightHundredths) {
      return '追熟重量が使用可能量を超えています。';
    }
    if (_allocations.isEmpty) return '追熟内訳を1行以上入力してください。';
    final seenOrders = <String>{};
    var reserveCount = 0;
    for (final allocation in _allocations) {
      final weight = _parseWeight(allocation.weightController.text);
      if (weight == null || weight <= 0) return '各内訳の重量を0.01kg単位で入力してください。';
      if (allocation.type == RipeningAllocationType.order) {
        final orderId = allocation.orderId;
        if (orderId == null) return '受注内訳の受注番号を選択してください。';
        if (!seenOrders.add(orderId)) return '同じ受注番号は1行だけ指定してください。';
        final order = _eligibleOrders
            .where((value) => value.id == orderId)
            .firstOrNull;
        if (order == null || weight > order.availableWeightHundredths) {
          return '受注内訳が受注の未割当量を超えています。';
        }
      } else {
        reserveCount++;
        if (reserveCount > 1) return '予備内訳は1行だけ指定してください。';
      }
    }
    if (_allocatedWeightHundredths != total) return '内訳合計を追熟重量と一致させてください。';
    if (_locationId == null) return '追熟場所を選択してください。';
    if (_plannedEthyleneAt == null) return 'エチレン注入予定を正しい形式で入力してください。';
    if (_workerId == null) return '担当者を選択してください。';
    return null;
  }

  bool get _canReview => _validationMessage == null;

  void _selectInventory(RipeningInventoryOption? inventory) {
    setState(() {
      _inventory = inventory;
      for (final allocation in _allocations) {
        allocation.orderId = null;
      }
      _inputChanged();
    });
  }

  void _addAllocation({bool notify = true}) {
    final editor = _AllocationEditor(onChanged: _onInputChanged);
    _allocations.add(editor);
    if (notify) {
      setState(_inputChanged);
    }
  }

  void _removeAllocation(int index) {
    final editor = _allocations.removeAt(index);
    editor.dispose();
    setState(_inputChanged);
  }

  void _onInputChanged() {
    if (mounted) setState(_inputChanged);
  }

  void _inputChanged() {
    _submitFailure = null;
  }

  Future<void> _review() async {
    final input = _buildInput();
    if (input == null) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ConfirmationDialog(
        input: input,
        location: _optionLabel(_options!.locations, _locationId!),
        worker: _optionLabel(_options!.workers, _workerId!),
      ),
    );
    if (accepted == true && mounted) await _submit(input);
  }

  RipeningPlanInput? _buildInput() {
    if (!_canReview) return null;
    return RipeningPlanInput(
      inventory: _inventory!,
      totalWeightHundredths: _totalWeightHundredths!,
      locationId: _locationId!,
      plannedEthyleneAt: _plannedEthyleneAt!,
      plannedCompletionAt: _plannedCompletionAt!,
      workerId: _workerId!,
      allocations: [
        for (final editor in _allocations)
          RipeningAllocationInput(
            type: editor.type,
            orderId: editor.orderId,
            weightHundredths: _parseWeight(editor.weightController.text)!,
          ),
      ],
    );
  }

  Future<void> _submit(RipeningPlanInput input) async {
    setState(() {
      _setBusy(true);
      _submitFailure = null;
    });
    try {
      var draft = _draft;
      if (draft == null) {
        _registerKey ??= createRipeningIdempotencyKey();
        draft = await widget.repository.register(
          input: input,
          idempotencyKey: _registerKey!,
        );
        if (!mounted) return;
        setState(() {
          _draft = draft;
          _draftSignature = input.signature;
        });
      } else if (_draftSignature != input.signature) {
        if (_updateSignature != input.signature) {
          _updateKey = createRipeningIdempotencyKey();
          _updateSignature = input.signature;
        }
        draft = await widget.repository.update(
          input: input,
          ripeningLotId: draft.id,
          expectedVersion: draft.version,
          reason: '追熟計画入力の修正',
          idempotencyKey: _updateKey!,
        );
        if (!mounted) return;
        setState(() {
          _draft = draft;
          _draftSignature = input.signature;
          _confirmKey = null;
          _confirmVersion = null;
        });
      }

      if (_confirmVersion != draft.version) {
        _confirmKey = createRipeningIdempotencyKey();
        _confirmVersion = draft.version;
      }
      final result = await widget.repository.confirm(
        ripeningLotId: draft.id,
        expectedVersion: draft.version,
        reason: '追熟計画の確定',
        idempotencyKey: _confirmKey!,
      );
      if (!mounted) return;
      setState(() => _setBusy(false));
      await _showCompletion(result);
      if (!mounted) return;
      if (widget.onCompleted != null) {
        widget.onCompleted!.call();
      } else {
        await Navigator.of(context).maybePop();
      }
    } on RipeningPlanFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _setBusy(false);
        _submitFailure = failure;
      });
    }
  }

  Future<void> _showCompletion(RipeningPlanResult result) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '登録完了',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                _SummaryRow(label: '追熟計画ID', value: result.displayId),
                _SummaryRow(
                  label: '注入予定',
                  value: _formatDisplayDate(result.plannedEthyleneAt),
                ),
                _SummaryRow(
                  label: '追熟完了予定',
                  value: _formatDisplayDate(result.plannedCompletionAt),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('ripening-complete-close'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AllocationEditor {
  _AllocationEditor({required VoidCallback onChanged})
    : weightController = TextEditingController() {
    weightController.addListener(onChanged);
    _listener = onChanged;
  }

  RipeningAllocationType type = RipeningAllocationType.order;
  String? orderId;
  final TextEditingController weightController;
  late final VoidCallback _listener;

  void dispose() {
    weightController.removeListener(_listener);
    weightController.dispose();
  }
}

class _AllocationFields extends StatelessWidget {
  const _AllocationFields({
    required this.index,
    required this.editor,
    required this.orders,
    required this.showNoOrdersMessage,
    required this.enabled,
    required this.canRemove,
    required this.onTypeChanged,
    required this.onOrderChanged,
    required this.onRemove,
  });

  final int index;
  final _AllocationEditor editor;
  final List<RipeningOrderOption> orders;
  final bool showNoOrdersMessage;
  final bool enabled;
  final bool canRemove;
  final ValueChanged<RipeningAllocationType> onTypeChanged;
  final ValueChanged<String?> onOrderChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              '内訳 ${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (canRemove)
            TextButton(
              onPressed: enabled ? onRemove : null,
              child: const Text('この内訳を削除'),
            ),
        ],
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          final fields = [
            _LabeledField(
              label: '割当種別',
              child: DropdownButtonFormField<RipeningAllocationType>(
                key: Key('ripening-allocation-type-$index'),
                initialValue: editor.type,
                isExpanded: true,
                icon: const SizedBox.shrink(),
                decoration: const InputDecoration(),
                items: const [
                  DropdownMenuItem(
                    value: RipeningAllocationType.order,
                    child: Text('受注'),
                  ),
                  DropdownMenuItem(
                    value: RipeningAllocationType.reserve,
                    child: Text('予備'),
                  ),
                ],
                onChanged: enabled
                    ? (value) {
                        if (value != null) onTypeChanged(value);
                      }
                    : null,
              ),
            ),
            if (editor.type == RipeningAllocationType.order)
              _LabeledField(
                label: '受注番号',
                child: DropdownButtonFormField<String>(
                  key: Key('ripening-allocation-order-$index'),
                  initialValue: editor.orderId,
                  isExpanded: true,
                  icon: const SizedBox.shrink(),
                  decoration: const InputDecoration(),
                  hint: const Text('選択してください'),
                  items: [
                    for (final order in orders)
                      DropdownMenuItem(
                        value: order.id,
                        child: Text(
                          '${order.orderNumber}　残 ${formatRipeningWeight(order.availableWeightHundredths)} kg',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: enabled ? onOrderChanged : null,
                ),
              ),
            _LabeledField(
              label: '割当重量（kg）',
              child: TextField(
                key: Key('ripening-allocation-weight-$index'),
                controller: editor.weightController,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(hintText: '0.00'),
              ),
            ),
          ];
          if (constraints.maxWidth < 720) {
            return Column(
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  fields[i],
                  if (i < fields.length - 1) const SizedBox(height: 12),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                Expanded(child: fields[i]),
                if (i < fields.length - 1) const SizedBox(width: 12),
              ],
            ],
          );
        },
      ),
      if (showNoOrdersMessage &&
          editor.type == RipeningAllocationType.order &&
          orders.isEmpty) ...[
        const SizedBox(height: 8),
        const Text('選択した品種・等級に割り当て可能な受注がありません。'),
      ],
    ],
  );
}

class _InventorySummary extends StatelessWidget {
  const _InventorySummary({required this.inventory});

  final RipeningInventoryOption inventory;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Divider(),
      Wrap(
        spacing: 24,
        runSpacing: 6,
        children: [
          Text('品種　${inventory.varietyLabel}'),
          Text('等級　${inventory.gradeLabel}'),
          Text(
            '使用可能量　${formatRipeningWeight(inventory.availableWeightHundredths)} kg',
          ),
        ],
      ),
      const Divider(),
    ],
  );
}

class _WeightSummary extends StatelessWidget {
  const _WeightSummary({
    required this.totalHundredths,
    required this.allocatedHundredths,
  });

  final int? totalHundredths;
  final int allocatedHundredths;

  @override
  Widget build(BuildContext context) {
    final total = totalHundredths ?? 0;
    final remaining = total - allocatedHundredths;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: Color(0xFFC7CECA)),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 24,
        runSpacing: 8,
        children: [
          Text('内訳合計　${formatRipeningWeight(allocatedHundredths)} kg'),
          Text(
            '未割当　${formatRipeningWeight(remaining)} kg',
            key: const Key('ripening-unallocated'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: remaining == 0
                  ? const Color(0xFF15452C)
                  : const Color(0xFF9E2A2B),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleSummary extends StatelessWidget {
  const _ScheduleSummary({
    required this.ethyleneAt,
    required this.completionAt,
  });

  final DateTime? ethyleneAt;
  final DateTime? completionAt;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: const BoxDecoration(
      border: Border.symmetric(
        horizontal: BorderSide(color: Color(0xFFC7CECA)),
      ),
    ),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        _ScheduleStep(
          label: 'エチレン処理',
          value: ethyleneAt == null ? '日時を確認' : '168時間',
        ),
        const Text('→', semanticsLabel: '次の工程'),
        const _ScheduleStep(label: '寝かせ', value: '追加条件なし'),
        const Text('→', semanticsLabel: '次の工程'),
        _ScheduleStep(
          label: '追熟完了予定',
          value: completionAt == null
              ? '日時を確認'
              : _formatDisplayDate(completionAt!),
        ),
      ],
    ),
  );
}

class _ScheduleStep extends StatelessWidget {
  const _ScheduleStep({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(value),
    ],
  );
}

class _ConfirmationDialog extends StatelessWidget {
  const _ConfirmationDialog({
    required this.input,
    required this.location,
    required this.worker,
  });

  final RipeningPlanInput input;
  final String location;
  final String worker;

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '入力内容の確認',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _SummaryRow(
                      label: '冷蔵在庫',
                      value: input.inventory.displayId,
                    ),
                    _SummaryRow(
                      label: '品種・等級',
                      value:
                          '${input.inventory.varietyLabel}・${input.inventory.gradeLabel}',
                    ),
                    _SummaryRow(
                      label: '追熟重量',
                      value:
                          '${formatRipeningWeight(input.totalWeightHundredths)} kg',
                    ),
                    _SummaryRow(
                      label: '内訳',
                      value: _allocationLabel(input.allocations),
                    ),
                    _SummaryRow(label: '追熟場所', value: location),
                    _SummaryRow(
                      label: '注入予定',
                      value: _formatDisplayDate(input.plannedEthyleneAt),
                    ),
                    _SummaryRow(
                      label: '追熟完了予定',
                      value: _formatDisplayDate(input.plannedCompletionAt),
                    ),
                    _SummaryRow(label: '担当者', value: worker),
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
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('修正する'),
                ),
                FilledButton(
                  key: const Key('ripening-submit'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('この内容で登録'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: const TextStyle(color: Color(0xFF56605A))),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _FormHeading extends StatelessWidget {
  const _FormHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
  );
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: const TextStyle(fontSize: 14)),
      const SizedBox(height: 6),
      child,
    ],
  );
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.failure, required this.draft});

  final RipeningPlanFailure failure;
  final RipeningPlanResult? draft;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFF9E2A2B)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(failure.message, style: const TextStyle(color: Color(0xFF9E2A2B))),
        if (draft != null) Text('下書きID: ${draft!.displayId}'),
        if (failure.correlationId != null)
          Text(
            '問い合わせ番号: ${failure.correlationId}',
            style: const TextStyle(fontSize: 12),
          ),
      ],
    ),
  );
}

String _optionLabel(List<RipeningReferenceOption> options, String id) =>
    options.firstWhere((option) => option.id == id).label;

String _allocationLabel(List<RipeningAllocationInput> allocations) {
  final orderCount = allocations
      .where((item) => item.type == RipeningAllocationType.order)
      .length;
  final reserveCount = allocations
      .where((item) => item.type == RipeningAllocationType.reserve)
      .length;
  return '受注 $orderCount件・予備 $reserveCount件';
}

int? _parseWeight(String raw) {
  final value = double.tryParse(raw.trim());
  if (value == null || !value.isFinite || value <= 0) return null;
  final hundredths = (value * 100).round();
  if ((hundredths / 100 - value).abs() > 0.000001) return null;
  return hundredths;
}

DateTime? _parseInputDate(String raw) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$')
      .firstMatch(raw.trim());
  if (match == null) return null;
  final parts = [
    for (var index = 1; index <= 5; index++) int.parse(match.group(index)!),
  ];
  final value = DateTime(parts[0], parts[1], parts[2], parts[3], parts[4]);
  return _formatInputDate(value) == raw.trim() ? value : null;
}

String _formatInputDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _formatDisplayDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year}年${local.month}月${local.day}日 '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
