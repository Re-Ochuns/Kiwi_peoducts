import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../orders/order_management_repository.dart';
import '../process_board/process_board_page.dart';
import '../process_board/process_board_repository.dart';
import '../ripening/ripening_plan_repository.dart';
import '../ripening_work/ripening_work_repository.dart';
import '../shipping/shipping_repository.dart';
import 'board_order_repository.dart';

class BoardOrderWorkspace extends StatefulWidget {
  const BoardOrderWorkspace({
    required this.repository,
    required this.boardRepository,
    required this.inventoryOnly,
    required this.onBusyChanged,
    this.ripeningPlanRepository,
    this.ripeningWorkRepository,
    this.shippingRepository,
    this.currentDate,
    super.key,
  });
  final BoardOrderRepository repository;
  final ProcessBoardRepository boardRepository;
  final bool inventoryOnly;
  final ValueChanged<bool> onBusyChanged;
  final RipeningPlanRepository? ripeningPlanRepository;
  final RipeningWorkRepository? ripeningWorkRepository;
  final ShippingRepository? shippingRepository;
  final DateTime? currentDate;
  @override
  State<BoardOrderWorkspace> createState() => _BoardOrderWorkspaceState();
}

class _BoardOrderWorkspaceState extends State<BoardOrderWorkspace> {
  final _form = GlobalKey<FormState>();
  final _date = TextEditingController();
  final _weight = TextEditingController();
  final _draft = BoardOrderDraft();
  BoardOrderOptions? _options;
  BoardOrderCriteria? _criteria;
  List<BoardOrderCandidate>? _candidates;
  String? _variety, _grade, _error;
  bool _loading = false;
  int _generation = 0, _boardRevision = 0;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _date.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.repository.loadOptions();
      if (mounted) setState(() => _options = data);
    } on BoardOrderFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _invalidate() => setState(() {
    _generation++;
    _criteria = null;
    _candidates = null;
    _error = null;
  });

  Future<void> _pickShipDate() async {
    final today = DateUtils.dateOnly(widget.currentDate ?? DateTime.now());
    final selected = DateTime.tryParse(_date.text);
    final lastDate = DateTime(today.year + 10, 12, 31);
    final initialDate = selected == null || selected.isBefore(today)
        ? today
        : selected.isAfter(lastDate)
        ? lastDate
        : selected;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: lastDate,
      currentDate: today,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: '出荷予定日を選択',
      cancelText: 'キャンセル',
      confirmText: '選択',
      builder: (context, child) => Localizations.override(
        context: context,
        locale: const Locale('ja'),
        delegates: GlobalMaterialLocalizations.delegates,
        child: child!,
      ),
    );
    if (!mounted || date == null) return;
    final value = date.toIso8601String().substring(0, 10);
    if (value == _date.text) return;
    _date.text = value;
    _invalidate();
  }

  Future<void> _search() async {
    if (!_form.currentState!.validate()) return;
    final generation = ++_generation;
    final criteria = BoardOrderCriteria(
      shipDate: _date.text.trim(),
      varietyId: _variety!,
      gradeId: _grade!,
      weightHundredths: (double.parse(_weight.text.trim()) * 100).round(),
    );
    setState(() {
      _loading = true;
      _error = null;
      _candidates = [];
      _criteria = criteria;
    });
    try {
      final data = await widget.repository.candidates(criteria);
      if (mounted && generation == _generation) {
        setState(() => _candidates = data);
      }
    } on BoardOrderFailure catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(ProcessBoardItem item) async {
    if (_loading || _criteria == null) return;
    final candidate = _candidates!.firstWhere(
      (candidate) => candidate.key == item.id,
    );
    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BoardOrderDialog(
        repository: widget.repository,
        criteria: _criteria!,
        candidate: candidate,
        options: _options!,
        draft: _draft,
        onBusyChanged: widget.onBusyChanged,
      ),
    );
    if (!mounted) return;
    if (completed == true) setState(() => _boardRevision++);
    await _search();
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    final criteria = _criteria;
    return Column(
      children: [
        if (widget.inventoryOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: options == null
                ? Row(
                    children: [
                      Expanded(child: Text(_error ?? '受注条件を読み込み中…')),
                      if (!_loading)
                        TextButton(
                          onPressed: _loadOptions,
                          child: const Text('再試行'),
                        ),
                    ],
                  )
                : Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '在庫から受注登録',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 165,
                              child: TextFormField(
                                controller: _date,
                                key: const Key('board-order-date'),
                                enabled: !_loading,
                                readOnly: true,
                                onTap: _loading ? null : _pickShipDate,
                                decoration: const InputDecoration(
                                  labelText: '出荷予定日',
                                  hintText: '日付を選択',
                                  suffixIcon: Icon(
                                    Icons.calendar_month_outlined,
                                  ),
                                ),
                                validator: (value) {
                                  final date = DateTime.tryParse(
                                    value?.trim() ?? '',
                                  );
                                  if (date == null ||
                                      date.toIso8601String().substring(0, 10) !=
                                          value?.trim()) {
                                    return '日付を入力';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            SizedBox(
                              width: 150,
                              child: _selectField(
                                '品種',
                                _variety,
                                options.varieties,
                                _loading
                                    ? null
                                    : (value) {
                                        _variety = value;
                                        _invalidate();
                                      },
                                key: const Key('board-order-variety'),
                              ),
                            ),
                            SizedBox(
                              width: 110,
                              child: _selectField(
                                '等級',
                                _grade,
                                options.grades,
                                _loading
                                    ? null
                                    : (value) {
                                        _grade = value;
                                        _invalidate();
                                      },
                                key: const Key('board-order-grade'),
                              ),
                            ),
                            SizedBox(
                              width: 145,
                              child: TextFormField(
                                controller: _weight,
                                key: const Key('board-order-weight'),
                                enabled: !_loading,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: '注文量（kg）',
                                ),
                                onChanged: (_) => _invalidate(),
                                validator: (value) =>
                                    RegExp(r'^\d+(\.\d{1,2})?$')
                                            .hasMatch(value?.trim() ?? '') &&
                                        (double.tryParse(value!.trim()) ?? 0) >
                                            0 &&
                                        (double.tryParse(value.trim()) ??
                                                double.infinity) <=
                                            9999999999.99
                                    ? null
                                    : '正の重量を入力',
                              ),
                            ),
                            FilledButton(
                              onPressed: _loading ? null : _search,
                              child: Text(_loading ? '検索中…' : '候補を表示'),
                            ),
                            TextButton(
                              onPressed: _loading ? null : _invalidate,
                              child: const Text('検索解除'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _error ??
                              (_candidates == null
                                  ? '出荷日9時に間に合う在庫を検索します。候補を選んで顧客・配送先を入力してください。'
                                  : _candidates!.isEmpty
                                  ? '条件に合う在庫はありません。数量・出荷日を見直してください。追熟マスター未設定や期限外の在庫は候補に含まれません。'
                                  : '${_candidates!.length}件の候補があります。ロットは予備残量で表示しています。'),
                          style: TextStyle(
                            color: _error == null ? null : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        Expanded(
          child: ProcessBoardPage(
            key: ValueKey('board-$_boardRevision'),
            repository: widget.boardRepository,
            inventoryOnly: widget.inventoryOnly,
            inventoryItemsOverride: criteria == null
                ? null
                : [
                    for (final candidate
                        in _candidates ?? <BoardOrderCandidate>[])
                      candidate.item(
                        options!.varieties
                            .firstWhere((o) => o.id == criteria.varietyId)
                            .label,
                        options.grades
                            .firstWhere((o) => o.id == criteria.gradeId)
                            .label,
                      ),
                  ],
            onCandidateSelected: widget.inventoryOnly && criteria != null
                ? _select
                : null,
            onBusyChanged: widget.onBusyChanged,
            ripeningPlanRepository: widget.ripeningPlanRepository,
            ripeningWorkRepository: widget.ripeningWorkRepository,
            shippingRepository: widget.shippingRepository,
            currentDate: widget.currentDate,
          ),
        ),
      ],
    );
  }
}

Widget _selectField(
  String label,
  String? value,
  List<BoardOrderOption> options,
  ValueChanged<String?>? onChanged, {
  Key? key,
}) => DropdownButtonFormField<String>(
  key: key ?? ValueKey('$label-$value'),
  initialValue: options.any((o) => o.id == value) ? value : null,
  isExpanded: true,
  decoration: InputDecoration(labelText: label),
  items: [
    for (final option in options)
      DropdownMenuItem(value: option.id, child: Text(option.label)),
  ],
  onChanged: onChanged,
  validator: (value) => value == null ? '選択してください' : null,
);

class BoardOrderDialog extends StatefulWidget {
  const BoardOrderDialog({
    required this.repository,
    required this.criteria,
    required this.candidate,
    required this.options,
    required this.draft,
    required this.onBusyChanged,
    super.key,
  });
  final BoardOrderRepository repository;
  final BoardOrderCriteria criteria;
  final BoardOrderCandidate candidate;
  final BoardOrderOptions options;
  final BoardOrderDraft draft;
  final ValueChanged<bool> onBusyChanged;
  @override
  State<BoardOrderDialog> createState() => _BoardOrderDialogState();
}

class _BoardOrderDialogState extends State<BoardOrderDialog> {
  final _form = GlobalKey<FormState>();
  List<BoardOrderOption> _destinations = [];
  BoardOrderFailure? _failure;
  BoardOrderResult? _result;
  String? _destinationError;
  bool _loadingDestinations = false, _busy = false, _review = false;
  String _key = createOrderIdempotencyKey();
  Map<String, Object?>? _input;
  int _generation = 0;
  BoardOrderDraft get draft => widget.draft;

  @override
  void initState() {
    super.initState();
    draft.locationId ??= widget.candidate.locationId;
    if (draft.customerId != null) _loadDestinations(draft.customerId!);
  }

  Future<void> _loadDestinations(String id) async {
    final generation = ++_generation;
    setState(() {
      _loadingDestinations = true;
      _destinationError = null;
      _destinations = [];
    });
    try {
      final data = await widget.repository.destinations(id);
      if (mounted && generation == _generation) {
        setState(() {
          _destinations = data;
          if (!data.any((d) => d.id == draft.destinationId)) {
            draft.destinationId = null;
          }
        });
      }
    } on BoardOrderFailure catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _destinationError = e.message);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingDestinations = false);
      }
    }
  }

  void _prepare() {
    if (_loadingDestinations || !_form.currentState!.validate()) return;
    _input = {
      ...widget.criteria.toJson(),
      'candidate_kind': widget.candidate.kind,
      'candidate_id': widget.candidate.id,
      'candidate_version': widget.candidate.version,
      'customer_id': draft.customerId,
      'shipping_destination_id': draft.destinationId,
      if (widget.candidate.kind == 'container') ...{
        'storage_location_id': draft.locationId,
        'assigned_worker_id': draft.workerId,
      },
    };
    _key = createOrderIdempotencyKey();
    setState(() {
      _review = true;
      _failure = null;
    });
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    widget.onBusyChanged(true);
    try {
      final result = await widget.repository.confirm(_input!, _key);
      if (mounted) {
        setState(() {
          _result = result;
          _failure = null;
        });
      }
    } on BoardOrderFailure catch (e) {
      if (mounted) setState(() => _failure = e);
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onBusyChanged(false);
    }
  }

  String _label(List<BoardOrderOption> options, String? id) =>
      options.where((o) => o.id == id).firstOrNull?.label ?? '';
  String _date(DateTime date) =>
      '${date.year}/${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final options = widget.options;
    final result = _result;
    final conflict = _failure?.code == 'INVENTORY_UNAVAILABLE';
    final uncertain = _failure?.uncertain == true;
    return PopScope(
      canPop: !_busy && !uncertain,
      child: AlertDialog(
        title: Text(
          result != null
              ? '登録が完了しました'
              : _review
              ? '受注・計画の確認'
              : '顧客・配送先と計画',
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: result != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('受注番号：${result.orderNumber}'),
                      Text('追熟計画：${result.planNumber}'),
                      Text(
                        result.existingPlan
                            ? '既存計画の予備分を受注に割り当てました。'
                            : '受注と追熟計画を同時に確定しました。',
                      ),
                    ],
                  )
                : Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${candidate.displayId}（${candidate.kind == 'lot' ? 'ロット' : 'コンテナ'}）',
                        ),
                        Text(
                          '${_label(options.varieties, widget.criteria.varietyId)}・${_label(options.grades, widget.criteria.gradeId)}',
                        ),
                        Text('出荷予定：${widget.criteria.shipDate} 09:00'),
                        Text(
                          '注文・使用量：${formatProcessBoardWeight(widget.criteria.weightHundredths)}',
                        ),
                        Text(
                          '利用可能：${formatProcessBoardWeight(candidate.availableHundredths)} → 登録後：${formatProcessBoardWeight(candidate.availableHundredths - widget.criteria.weightHundredths)}',
                        ),
                        Text('追熟開始：${_date(candidate.start)}'),
                        Text('追熟完了：${_date(candidate.completion)}'),
                        if (candidate.kind == 'lot')
                          Text('既存の追熟計画に紐付けます。対象：${candidate.containerIds}'),
                        const SizedBox(height: 16),
                        if (!_review) ...[
                          _selectField(
                            '顧客',
                            draft.customerId,
                            options.customers,
                            (value) {
                              setState(() {
                                draft.customerId = value;
                                draft.destinationId = null;
                              });
                              if (value != null) _loadDestinations(value);
                            },
                          ),
                          const SizedBox(height: 12),
                          _selectField(
                            '配送先',
                            draft.destinationId,
                            _destinations,
                            _loadingDestinations
                                ? null
                                : (value) => setState(
                                    () => draft.destinationId = value,
                                  ),
                          ),
                          if (_loadingDestinations)
                            const LinearProgressIndicator(),
                          if (_destinationError != null)
                            TextButton(
                              onPressed: () =>
                                  _loadDestinations(draft.customerId!),
                              child: Text('$_destinationError 再試行'),
                            ),
                          if (candidate.kind == 'container') ...[
                            const SizedBox(height: 12),
                            _selectField(
                              '保管場所',
                              draft.locationId,
                              options.locations,
                              (value) =>
                                  setState(() => draft.locationId = value),
                            ),
                            const SizedBox(height: 12),
                            _selectField(
                              '担当作業者',
                              draft.workerId,
                              options.workers,
                              (value) => setState(() => draft.workerId = value),
                            ),
                          ],
                        ] else ...[
                          Text(
                            '顧客：${_label(options.customers, draft.customerId)}',
                          ),
                          Text(
                            '配送先：${_label(_destinations, draft.destinationId)}',
                          ),
                          if (candidate.kind == 'container') ...[
                            Text(
                              '保管場所：${_label(options.locations, draft.locationId)}',
                            ),
                            Text(
                              '担当作業者：${_label(options.workers, draft.workerId)}',
                            ),
                          ],
                        ],
                        if (_failure != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _failure!.message,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
        actions: result != null
            ? [
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('工程ボードへ戻る'),
                ),
              ]
            : [
                if (!uncertain)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(context, false),
                    child: Text(conflict ? '候補を再検索' : '閉じる'),
                  ),
                if (_review && !uncertain && !conflict)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _review = false),
                    child: const Text('入力に戻る'),
                  ),
                if (!conflict)
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : _review
                        ? _submit
                        : _prepare,
                    child: Text(
                      _busy
                          ? '登録中…'
                          : _review
                          ? uncertain
                                ? '同じ内容で再試行'
                                : '受注・計画を確定'
                          : '確認へ',
                    ),
                  ),
              ],
      ),
    );
  }
}
