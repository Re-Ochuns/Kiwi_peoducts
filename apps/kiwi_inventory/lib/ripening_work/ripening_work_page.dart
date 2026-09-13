import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/common_state_view.dart';
import '../work_tasks/work_task_repository.dart';
import 'ripening_work_repository.dart';

class RipeningWorkPage extends StatefulWidget {
  const RipeningWorkPage({
    required this.repository,
    required this.task,
    this.currentDate,
    super.key,
  });

  final RipeningWorkRepository repository;
  final WorkTaskItem task;
  final DateTime? currentDate;

  @override
  State<RipeningWorkPage> createState() => _RipeningWorkPageState();
}

class _RipeningWorkPageState extends State<RipeningWorkPage> {
  final _actualAtController = TextEditingController();
  final _temperatureController = TextEditingController();
  final _restStartedAtController = TextEditingController();
  final _restTemperatureController = TextEditingController();
  final _notesController = TextEditingController();

  RipeningWorkDetails? _details;
  RipeningWorkFailure? _loadFailure;
  RipeningWorkFailure? _submitFailure;
  String? _locationId;
  String? _workerId;
  String? _operationKey;
  bool _loading = true;
  bool _submitting = false;

  RipeningWorkType get _type => switch (widget.task.type) {
    WorkTaskType.ethyleneInjection => RipeningWorkType.ethyleneInjection,
    WorkTaskType.ethyleneRemovalCheck => RipeningWorkType.ethyleneRemoval,
    _ => RipeningWorkType.ripenessCheck,
  };

  @override
  void initState() {
    super.initState();
    final now = (widget.currentDate ?? DateTime.now()).toLocal();
    _actualAtController.text = _formatInputDate(now);
    _restStartedAtController.text = _formatInputDate(now);
    _load();
  }

  @override
  void dispose() {
    _actualAtController.dispose();
    _temperatureController.dispose();
    _restStartedAtController.dispose();
    _restTemperatureController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailure = null;
    });
    try {
      final details = await widget.repository.load(widget.task.targetId);
      if (!mounted) return;
      setState(() {
        _details = details;
        _locationId =
            details.locations.any((option) => option.id == _locationId)
            ? _locationId
            : details.locations.any((option) => option.id == details.locationId)
            ? details.locationId
            : null;
        _workerId = details.workers.any((option) => option.id == _workerId)
            ? _workerId
            : details.workers.any((option) => option.id == details.workerId)
            ? details.workerId
            : null;
        _loading = false;
      });
    } on RipeningWorkFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loadFailure = failure;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 8,
        title: TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.green,
            minimumSize: const Size(48, 48),
          ),
          child: const Text('← 作業確認へ戻る'),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: SafeArea(
        child: _loading && details == null
            ? CommonStateView.loading(title: '${_type.label}を読み込んでいます')
            : _loadFailure != null && details == null
            ? CommonStateView.error(
                title: '${_type.label}を表示できません',
                message: _loadFailure!.message,
                actionLabel: _loadFailure!.retryable ? '再試行' : null,
                onAction: _loadFailure!.retryable ? _load : null,
              )
            : _buildForm(details!),
      ),
    );
  }

  Widget _buildForm(RipeningWorkDetails details) {
    final previousAt = _previousActualAt(details);
    final actualAt = _parseInputDate(_actualAtController.text);
    final restStartedAt = _parseInputDate(_restStartedAtController.text);
    final chronologyError =
        actualAt != null && previousAt != null && actualAt.isBefore(previousAt)
        ? '実績日時は前工程の実績以降にしてください'
        : _type == RipeningWorkType.ethyleneRemoval &&
              actualAt != null &&
              restStartedAt != null &&
              restStartedAt.isBefore(actualAt)
        ? '寝かせ開始は抜き確認以降にしてください'
        : null;
    final canSubmit =
        !_submitting &&
        actualAt != null &&
        _finiteNumber(_temperatureController.text) != null &&
        _locationId != null &&
        _workerId != null &&
        chronologyError == null &&
        (_type != RipeningWorkType.ethyleneRemoval ||
            restStartedAt != null &&
                _finiteNumber(_restTemperatureController.text) != null);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 48),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _type.label,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 22),
              _TargetSummary(task: widget.task, details: details),
              const SizedBox(height: 28),
              const Text(
                '実績を入力',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              _InputField(
                key: const Key('ripening-work-actual-at'),
                controller: _actualAtController,
                label: '実績日時（YYYY/MM/DD HH:mm）',
                enabled: !_submitting,
                onChanged: _inputChanged,
                errorText: actualAt == null ? '日時を確認してください' : null,
              ),
              const SizedBox(height: 14),
              _InputField(
                key: const Key('ripening-work-temperature'),
                controller: _temperatureController,
                label: '実績温度（℃）',
                enabled: !_submitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                onChanged: _inputChanged,
                errorText:
                    _temperatureController.text.isNotEmpty &&
                        _finiteNumber(_temperatureController.text) == null
                    ? '有限の数値を入力してください'
                    : null,
              ),
              if (_type == RipeningWorkType.ethyleneRemoval) ...[
                const SizedBox(height: 14),
                _InputField(
                  key: const Key('ripening-work-rest-started-at'),
                  controller: _restStartedAtController,
                  label: '寝かせ開始日時（YYYY/MM/DD HH:mm）',
                  enabled: !_submitting,
                  onChanged: _inputChanged,
                  errorText: restStartedAt == null ? '日時を確認してください' : null,
                ),
                const SizedBox(height: 14),
                _InputField(
                  key: const Key('ripening-work-rest-temperature'),
                  controller: _restTemperatureController,
                  label: '寝かせ温度（℃）',
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  onChanged: _inputChanged,
                  errorText:
                      _restTemperatureController.text.isNotEmpty &&
                          _finiteNumber(_restTemperatureController.text) == null
                      ? '有限の数値を入力してください'
                      : null,
                ),
              ],
              const SizedBox(height: 14),
              _OptionField(
                key: const Key('ripening-work-location'),
                label: '場所',
                value: _locationId,
                options: details.locations,
                enabled: !_submitting,
                onChanged: (value) => setState(() {
                  _locationId = value;
                  _clearOperation();
                }),
              ),
              const SizedBox(height: 14),
              _OptionField(
                key: const Key('ripening-work-worker'),
                label: '担当者',
                value: _workerId,
                options: details.workers,
                enabled: !_submitting,
                onChanged: (value) => setState(() {
                  _workerId = value;
                  _clearOperation();
                }),
              ),
              const SizedBox(height: 14),
              _InputField(
                key: const Key('ripening-work-notes'),
                controller: _notesController,
                label: '備考（任意）',
                enabled: !_submitting,
                maxLines: 3,
                onChanged: _inputChanged,
              ),
              if (chronologyError != null) ...[
                const SizedBox(height: 12),
                Text(
                  chronologyError,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (_submitFailure != null) ...[
                const SizedBox(height: 16),
                _FailureNotice(
                  failure: _submitFailure!,
                  onReload: _submitFailure!.isConflict ? _load : null,
                ),
              ],
              const SizedBox(height: 24),
              Semantics(
                liveRegion: _submitting,
                child: FilledButton(
                  key: const Key('ripening-work-confirm-input'),
                  onPressed: canSubmit
                      ? () => _showConfirmation(details)
                      : null,
                  child: Text(
                    _submitting
                        ? '完了結果を確認しています'
                        : _operationKey != null &&
                              _submitFailure?.retryable == true
                        ? '同じ内容で結果を確認'
                        : '入力内容を確認',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DateTime? _previousActualAt(RipeningWorkDetails details) {
    final previousType = switch (_type) {
      RipeningWorkType.ethyleneInjection => null,
      RipeningWorkType.ethyleneRemoval => 'ethylene_injection',
      RipeningWorkType.ripenessCheck => 'ethylene_removal_check',
    };
    if (previousType == null) return null;
    final records = details.results.where(
      (record) => record.type == previousType,
    );
    if (records.isEmpty) return null;
    final record = records.single;
    return record.restStartedAt ?? record.actualAt;
  }

  void _inputChanged(String _) => setState(_clearOperation);

  void _clearOperation() {
    if (!_submitting) {
      _operationKey = null;
      _submitFailure = null;
    }
  }

  RipeningWorkInput? _input(RipeningWorkDetails details) {
    final actualAt = _parseInputDate(_actualAtController.text);
    final temperature = _finiteNumber(_temperatureController.text);
    final locationId = _locationId;
    final workerId = _workerId;
    if (actualAt == null ||
        temperature == null ||
        locationId == null ||
        workerId == null) {
      return null;
    }
    return RipeningWorkInput(
      ripeningLotId: details.id,
      expectedVersion: details.version,
      actualAt: actualAt,
      actualTemperature: temperature,
      locationId: locationId,
      workerId: workerId,
      restStartedAt: _type == RipeningWorkType.ethyleneRemoval
          ? _parseInputDate(_restStartedAtController.text)
          : null,
      restTemperature: _type == RipeningWorkType.ethyleneRemoval
          ? _finiteNumber(_restTemperatureController.text)
          : null,
      notes: _notesController.text,
    );
  }

  Future<void> _showConfirmation(RipeningWorkDetails details) async {
    final input = _input(details);
    if (input == null) return;
    final location = details.locations
        .firstWhere((option) => option.id == input.locationId)
        .label;
    final worker = details.workers
        .firstWhere((option) => option.id == input.workerId)
        .label;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_type.label}の確認'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SummaryRow(label: '対象ID', value: details.displayId),
              _SummaryRow(
                label: '重量',
                value: formatRipeningWorkWeight(details.weightHundredths),
              ),
              _SummaryRow(
                label: '実績日時',
                value: _formatDisplayDate(input.actualAt),
              ),
              _SummaryRow(
                label: '実績温度',
                value: '${_formatNumber(input.actualTemperature)} ℃',
              ),
              if (_type == RipeningWorkType.ethyleneRemoval) ...[
                _SummaryRow(
                  label: '寝かせ開始',
                  value: _formatDisplayDate(input.restStartedAt!),
                ),
                _SummaryRow(
                  label: '寝かせ温度',
                  value: '${_formatNumber(input.restTemperature!)} ℃',
                ),
              ],
              _SummaryRow(label: '場所', value: location),
              _SummaryRow(label: '担当者', value: worker),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('戻って修正'),
          ),
          FilledButton(
            key: const Key('ripening-work-complete'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_type.completeLabel),
          ),
        ],
      ),
    );
    if (confirmed == true) await _complete(input);
  }

  Future<void> _complete(RipeningWorkInput input) async {
    setState(() {
      _submitting = true;
      _submitFailure = null;
      _operationKey ??= createRipeningWorkIdempotencyKey();
    });
    try {
      final result = await widget.repository.complete(
        type: _type,
        input: input,
        idempotencyKey: _operationKey!,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('完了を記録しました'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SummaryRow(label: '対象ID', value: result.displayId),
              _SummaryRow(label: '作業', value: _type.label),
              _SummaryRow(
                label: '実績日時',
                value: _formatDisplayDate(result.actualAt),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ToDoへ戻る'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on RipeningWorkFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitFailure = failure;
        if (!failure.retryable) _operationKey = null;
      });
    }
  }
}

class _TargetSummary extends StatelessWidget {
  const _TargetSummary({required this.task, required this.details});

  final WorkTaskItem task;
  final RipeningWorkDetails details;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(
        top: BorderSide(color: AppColors.line),
        bottom: BorderSide(color: AppColors.line),
      ),
    ),
    child: Column(
      children: [
        _SummaryRow(label: '対象ID', value: details.displayId, prominent: true),
        _SummaryRow(
          label: '重量',
          value: formatRipeningWorkWeight(details.weightHundredths),
          prominent: true,
        ),
        _SummaryRow(label: '品種・等級', value: task.productLabel),
        _SummaryRow(label: '予定', value: _formatDisplayDate(task.scheduledAt)),
        _SummaryRow(label: '期限', value: _formatDisplayDate(task.dueAt)),
      ],
    ),
  );
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.label,
    required this.enabled,
    required this.onChanged,
    this.keyboardType,
    this.errorText,
    this.maxLines = 1,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final String? errorText;
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    keyboardType: keyboardType,
    maxLines: maxLines,
    onChanged: onChanged,
    decoration: InputDecoration(labelText: label, errorText: errorText),
  );
}

class _OptionField extends StatelessWidget {
  const _OptionField({
    required this.label,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String? value;
  final List<RipeningWorkOption> options;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    icon: const ExcludeSemantics(
      child: Text('▼', style: TextStyle(fontSize: 12)),
    ),
    decoration: InputDecoration(labelText: label),
    items: [
      for (final option in options)
        DropdownMenuItem(value: option.id, child: Text(option.label)),
    ],
    onChanged: enabled ? onChanged : null,
  );
}

class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.failure, this.onReload});

  final RipeningWorkFailure failure;
  final VoidCallback? onReload;

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
      ],
    ),
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
            fontSize: prominent ? 24 : 16,
            fontWeight: prominent ? FontWeight.w700 : FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

double? _finiteNumber(String raw) {
  final value = double.tryParse(raw.trim());
  return value?.isFinite == true ? value : null;
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

String _formatDisplayDate(DateTime value) =>
    '${value.year}年${value.month}月${value.day}日 '
    '${_two(value.hour)}:${_two(value.minute)}';

String _formatNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

String _two(int value) => value.toString().padLeft(2, '0');
