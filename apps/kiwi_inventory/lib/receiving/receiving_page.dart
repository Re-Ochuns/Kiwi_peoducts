import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/common_state_view.dart';
import 'receiving_repository.dart';
import 'supabase_receiving_repository.dart';

class ReceivingPage extends StatefulWidget {
  const ReceivingPage({required this.repository, this.currentDate, super.key});

  final ReceivingRepository repository;
  final DateTime? currentDate;

  @override
  State<ReceivingPage> createState() => _ReceivingPageState();
}

class _ReceivingPageState extends State<ReceivingPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _receivedDate;
  final _supplierReference = TextEditingController();
  final _originName = TextEditingController();
  final _weight = TextEditingController();
  final _containerCount = TextEditingController();
  final _correctionReason = TextEditingController();

  ReceivingSourceType _sourceType = ReceivingSourceType.harvest;
  ReceivingMasters? _masters;
  ReceivingFailure? _loadFailure;
  String? _orchardId;
  String? _plotId;
  String? _treeId;
  String? _supplierId;
  String? _varietyId;
  String? _workerId;
  bool _submitting = false;
  String? _screenError;
  String? _serverField;
  String? _serverFieldMessage;
  String? _pendingSignature;
  String? _pendingKey;
  ReceivingResult? _correctionTarget;

  @override
  void initState() {
    super.initState();
    final date = widget.currentDate ?? DateTime.now();
    _receivedDate = TextEditingController(text: _formatDate(date));
    _loadMasters();
  }

  @override
  void dispose() {
    _receivedDate.dispose();
    _supplierReference.dispose();
    _originName.dispose();
    _weight.dispose();
    _containerCount.dispose();
    _correctionReason.dispose();
    super.dispose();
  }

  Future<void> _loadMasters() async {
    setState(() {
      _masters = null;
      _loadFailure = null;
    });
    try {
      final masters = await widget.repository.loadMasters();
      if (!mounted) return;
      setState(() => _masters = masters);
    } on ReceivingFailure catch (failure) {
      if (!mounted) return;
      setState(() => _loadFailure = failure);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _loadFailure = const ReceivingFailure(
          message: '選択肢を読み込めませんでした。通信状況を確認してください。',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final masters = _masters;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 8,
        title: TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: const Text('← ToDoへ戻る', style: TextStyle(fontSize: 16)),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: SafeArea(
        child: switch ((masters, _loadFailure)) {
          (null, null) => const CommonStateView.loading(title: '入力項目を読み込んでいます'),
          (null, final failure?) => CommonStateView.error(
            title: '入力項目を読み込めません',
            message: failure.message,
            actionLabel: '再試行',
            onAction: _loadMasters,
          ),
          (final loaded?, _) => _buildForm(loaded),
        },
      ),
    );
  }

  Widget _buildForm(ReceivingMasters masters) {
    final plots = masters.plots
        .where((item) => item.parentId == _orchardId)
        .toList();
    final trees = masters.trees
        .where((item) => item.parentId == _plotId)
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Form(
            key: _formKey,
            onChanged: _clearServerErrorAfterEdit,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '収穫・仕入れ登録',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
                if (_correctionTarget != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${_correctionTarget!.displayId}を修正',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                const _FieldLabel('受入区分'),
                Row(
                  children: [
                    Expanded(
                      child: _SourceButton(
                        label: '収穫',
                        selected: _sourceType == ReceivingSourceType.harvest,
                        onPressed: () =>
                            _changeSource(ReceivingSourceType.harvest),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SourceButton(
                        label: '仕入れ',
                        selected: _sourceType == ReceivingSourceType.purchase,
                        onPressed: () =>
                            _changeSource(ReceivingSourceType.purchase),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _TextField(
                  fieldKey: 'received_date',
                  label: '受入日',
                  controller: _receivedDate,
                  keyboardType: TextInputType.datetime,
                  validator: (value) => _validateDate(value, 'received_date'),
                ),
                if (_sourceType == ReceivingSourceType.harvest) ...[
                  _MasterField(
                    fieldKey: 'orchard_id',
                    label: '農園',
                    value: _orchardId,
                    options: masters.orchards,
                    errorText: _fieldError('orchard_id'),
                    onChanged: (value) => setState(() {
                      _resetErrors();
                      _orchardId = value;
                      _plotId = null;
                      _treeId = null;
                      _varietyId = null;
                    }),
                  ),
                  _MasterField(
                    fieldKey: 'plot_id',
                    label: '区画',
                    value: _plotId,
                    options: plots,
                    enabled: _orchardId != null,
                    errorText: _fieldError('plot_id'),
                    onChanged: (value) => setState(() {
                      _resetErrors();
                      _plotId = value;
                      _treeId = null;
                      _varietyId = null;
                    }),
                  ),
                  _MasterField(
                    fieldKey: 'tree_id',
                    label: '樹体',
                    value: _treeId,
                    options: trees,
                    enabled: _plotId != null,
                    errorText: _fieldError('tree_id'),
                    onChanged: (value) {
                      final tree = trees.firstWhere((item) => item.id == value);
                      setState(() {
                        _resetErrors();
                        _treeId = value;
                        _varietyId = tree.varietyId;
                      });
                    },
                  ),
                ] else ...[
                  _MasterField(
                    fieldKey: 'supplier_id',
                    label: '仕入先',
                    value: _supplierId,
                    options: masters.suppliers,
                    errorText: _fieldError('supplier_id'),
                    onChanged: (value) => setState(() {
                      _resetErrors();
                      _supplierId = value;
                    }),
                  ),
                  _TextField(
                    fieldKey: 'supplier_reference',
                    label: '仕入先管理ID',
                    controller: _supplierReference,
                    validator: (value) =>
                        _required(value, 'supplier_reference'),
                  ),
                  _TextField(
                    fieldKey: 'origin_name',
                    label: '産地・区画',
                    controller: _originName,
                    validator: (value) => _required(value, 'origin_name'),
                  ),
                ],
                _MasterField(
                  fieldKey: 'variety_id',
                  label: '品種',
                  value: _varietyId,
                  options: masters.varieties,
                  enabled: _sourceType == ReceivingSourceType.purchase,
                  supportingText: _sourceType == ReceivingSourceType.harvest
                      ? '樹体から自動設定されます'
                      : null,
                  errorText: _fieldError('variety_id'),
                  onChanged: (value) => setState(() {
                    _resetErrors();
                    _varietyId = value;
                  }),
                ),
                if (_correctionTarget != null)
                  _TextField(
                    fieldKey: 'reason',
                    label: '修正理由',
                    controller: _correctionReason,
                    validator: (value) => _required(value, 'reason'),
                  ),
                _TextField(
                  fieldKey: 'total_weight_kg',
                  label: '総重量（kg）',
                  controller: _weight,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _validateWeight,
                ),
                _TextField(
                  fieldKey: 'container_count',
                  label: 'コンテナ数',
                  controller: _containerCount,
                  keyboardType: TextInputType.number,
                  validator: _validateContainerCount,
                ),
                _MasterField(
                  fieldKey: 'worker_id',
                  label: '担当者',
                  value: _workerId,
                  options: masters.workers,
                  errorText: _fieldError('worker_id'),
                  onChanged: (value) => setState(() {
                    _resetErrors();
                    _workerId = value;
                  }),
                ),
                if (_screenError != null) ...[
                  const SizedBox(height: 4),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _screenError!,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : () => _confirm(masters),
                  child: Text(
                    _submitting
                        ? (_correctionTarget == null ? '登録しています' : '修正しています')
                        : (_correctionTarget == null ? '入力内容を確認' : '修正内容を確認'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _changeSource(ReceivingSourceType next) {
    if (_sourceType == next) return;
    setState(() {
      _sourceType = next;
      _orchardId = null;
      _plotId = null;
      _treeId = null;
      _supplierId = null;
      _varietyId = null;
      _screenError = null;
      _serverField = null;
      _serverFieldMessage = null;
    });
  }

  Future<void> _confirm(ReceivingMasters masters) async {
    setState(() {
      _screenError = null;
      _serverField = null;
      _serverFieldMessage = null;
    });
    final valid = _formKey.currentState?.validate() ?? false;
    if (!_validateSelections()) return;
    if (!valid) return;
    final input = _buildInput(masters);
    final correction = _correctionTarget;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(correction == null ? '登録内容を確認' : '修正内容を確認'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ConfirmRow(
              label: '区分',
              value: input.sourceType == ReceivingSourceType.harvest
                  ? '収穫'
                  : '仕入れ',
            ),
            _ConfirmRow(label: '受入日', value: input.receivedDate),
            _ConfirmRow(label: '産地・区画', value: input.originName),
            _ConfirmRow(
              label: '品種',
              value: _labelOf(masters.varieties, input.varietyId),
            ),
            _ConfirmRow(
              label: '総重量',
              value: '${input.totalWeightKg.toStringAsFixed(2)} kg',
            ),
            _ConfirmRow(label: 'コンテナ数', value: '${input.containerCount}'),
            if (correction != null)
              _ConfirmRow(label: '修正理由', value: _correctionReason.text.trim()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('入力へ戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(correction == null ? '登録を確定' : '修正を確定'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _register(input);
  }

  bool _validateSelections() {
    String? field;
    if (_sourceType == ReceivingSourceType.harvest) {
      if (_orchardId == null) {
        field = 'orchard_id';
      } else if (_plotId == null) {
        field = 'plot_id';
      } else if (_treeId == null) {
        field = 'tree_id';
      }
    } else if (_supplierId == null) {
      field = 'supplier_id';
    }
    field ??= _varietyId == null ? 'variety_id' : null;
    field ??= _workerId == null ? 'worker_id' : null;
    if (field == null) return true;
    setState(() {
      _serverField = field;
      _serverFieldMessage = '選択してください。';
    });
    return false;
  }

  ReceivingInput _buildInput(ReceivingMasters masters) {
    final origin = _sourceType == ReceivingSourceType.harvest
        ? '${_nameOf(masters.orchards, _orchardId!)} ${_nameOf(masters.plots, _plotId!)}'
        : _originName.text.trim();
    return ReceivingInput(
      sourceType: _sourceType,
      receivedDate: _receivedDate.text.trim(),
      orchardId: _orchardId,
      plotId: _plotId,
      treeId: _treeId,
      supplierId: _supplierId,
      supplierReference: _supplierReference.text,
      originName: origin,
      varietyId: _varietyId!,
      totalWeightKg: double.parse(_weight.text.trim()),
      containerCount: int.parse(_containerCount.text.trim()),
      workerId: _workerId!,
    );
  }

  Future<void> _register(ReceivingInput input) async {
    final correction = _correctionTarget;
    final signature = correction == null
        ? 'register:${input.signature}'
        : 'correct:${correction.receivingLotId}:${correction.version}:'
              '${_correctionReason.text.trim()}:${input.signature}';
    if (_pendingSignature != signature || _pendingKey == null) {
      _pendingSignature = signature;
      _pendingKey = createIdempotencyKey();
    }
    setState(() {
      _submitting = true;
      _screenError = null;
    });
    try {
      final result = correction == null
          ? await widget.repository.register(
              input: input,
              idempotencyKey: _pendingKey!,
            )
          : await widget.repository.correct(
              input: input,
              receivingLotId: correction.receivingLotId,
              expectedVersion: correction.version,
              reason: _correctionReason.text,
              idempotencyKey: _pendingKey!,
            );
      if (!mounted) return;
      _pendingKey = null;
      _pendingSignature = null;
      final edit = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(correction == null ? '登録が完了しました' : '修正が完了しました'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ConfirmRow(label: '受入ロットID', value: result.displayId),
              _ConfirmRow(label: '受入日', value: result.receivedDate),
              _ConfirmRow(label: '選果期限', value: result.sortingDueDate),
            ],
          ),
          actions: [
            if (correction == null)
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('登録内容を修正'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (edit == true) {
        setState(() {
          _correctionTarget = result;
          _correctionReason.clear();
        });
      } else {
        Navigator.of(context).pop();
      }
    } on ReceivingFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _serverField = failure.field;
        _serverFieldMessage = failure.field == null ? null : failure.message;
        _screenError = failure.field == null
            ? _failureMessage(failure)
            : '入力内容を確認してください。';
      });
      _formKey.currentState?.validate();
    } catch (_) {
      if (!mounted) return;
      setState(() => _screenError = '登録結果を確認できませんでした。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _failureMessage(ReceivingFailure failure) {
    if (failure.correlationId == null) return failure.message;
    return '${failure.message}\n問い合わせID: ${failure.correlationId}';
  }

  void _clearServerErrorAfterEdit() {
    if (_serverField == null && _screenError == null) return;
    setState(_resetErrors);
  }

  void _resetErrors() {
    _serverField = null;
    _serverFieldMessage = null;
    _screenError = null;
  }

  String? _required(String? value, String field) {
    if (value == null || value.trim().isEmpty) return '入力してください。';
    return _fieldError(field);
  }

  String? _validateDate(String? value, String field) {
    if (value == null || value.trim().isEmpty) return '入力してください。';
    final match = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value.trim());
    final parsed = DateTime.tryParse(value.trim());
    if (!match || parsed == null || _formatDate(parsed) != value.trim()) {
      return 'YYYY-MM-DD形式の正しい日付を入力してください。';
    }
    return _fieldError(field);
  }

  String? _validateWeight(String? value) {
    if (value == null || value.trim().isEmpty) return '入力してください。';
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value.trim())) {
      return '0.01kg単位までの数値を入力してください。';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return '0より大きい重量を入力してください。';
    return _fieldError('total_weight_kg');
  }

  String? _validateContainerCount(String? value) {
    if (value == null || value.trim().isEmpty) return '入力してください。';
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 1) return '1以上の整数を入力してください。';
    return _fieldError('container_count');
  }

  String? _fieldError(String field) =>
      _serverField == field ? _serverFieldMessage : null;
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.validator,
    this.keyboardType,
  });

  final String fieldKey;
  final String label;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldLabel(label),
          TextFormField(
            key: ValueKey('field-$fieldKey'),
            controller: controller,
            keyboardType: keyboardType,
            validator: validator,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      label,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      backgroundColor: selected ? const Color(0xFFEAF2ED) : Colors.white,
      foregroundColor: selected ? const Color(0xFF15452C) : AppColors.ink,
      side: BorderSide(
        color: selected ? AppColors.green : const Color(0xFF8D9690),
        width: selected ? 2 : 1,
      ),
    ),
    child: Text(selected ? '$label（選択中）' : label),
  );
}

class _MasterField extends StatelessWidget {
  const _MasterField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
    this.supportingText,
    this.errorText,
  });

  final String fieldKey;
  final String label;
  final String? value;
  final List<MasterOption> options;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? supportingText;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final current = value == null
        ? null
        : options.where((item) => item.id == value).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldLabel(label),
          OutlinedButton(
            key: ValueKey('master-$fieldKey'),
            onPressed: enabled && options.isNotEmpty
                ? () => _choose(context)
                : null,
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              minimumSize: const Size(0, 52),
            ),
            child: Text(
              current?.label ??
                  (enabled ? '選択してください' : supportingText ?? '先に上の項目を選択'),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          if (supportingText != null) ...[
            const SizedBox(height: 6),
            Text(
              supportingText!,
              style: const TextStyle(fontSize: 13, color: AppColors.mutedText),
            ),
          ],
          if (errorText != null) ...[
            const SizedBox(height: 6),
            Text(
              errorText!,
              style: const TextStyle(fontSize: 13, color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _choose(BuildContext context) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$labelを選択'),
        content: SizedBox(
          width: 440,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final option = options[index];
              return TextButton(
                onPressed: () => Navigator.of(context).pop(option.id),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size(0, 52),
                ),
                child: Text(
                  option.id == value ? '${option.label}（選択中）' : option.label,
                ),
              );
            },
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
    if (selected != null) onChanged(selected);
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.mutedText),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _labelOf(List<MasterOption> options, String id) =>
    options.firstWhere((item) => item.id == id).label;

String _nameOf(List<MasterOption> options, String id) =>
    options.firstWhere((item) => item.id == id).name;
