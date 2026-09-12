import 'package:flutter/material.dart';

import 'dart:math';

import '../work_tasks/work_task_repository.dart';
import 'ripening_work_repository.dart';

class RipeningWorkPage extends StatefulWidget {
  const RipeningWorkPage({
    required this.repository,
    required this.taskId,
    this.now = DateTime.now,
    super.key,
  });
  final RipeningWorkRepository repository;
  final String taskId;
  final DateTime Function() now;

  @override
  State<RipeningWorkPage> createState() => _RipeningWorkPageState();
}

class _RipeningWorkPageState extends State<RipeningWorkPage> {
  late Future<RipeningWorkDetail> _detail;
  @override
  void initState() {
    super.initState();
    _detail = widget.repository.load(widget.taskId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('追熟作業')),
    body: SafeArea(
      child: FutureBuilder<RipeningWorkDetail>(
        future: _detail,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  error is RipeningWorkFailure
                      ? error.message
                      : '作業を読み込めませんでした。',
                ),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _detail = widget.repository.load(widget.taskId);
                  }),
                  child: const Text('再読込'),
                ),
              ],
            );
          }
          final detail = snapshot.requireData;
          if (detail.task.id != widget.taskId ||
              !isRipeningWork(detail.task.type)) {
            return const Center(child: Text('対象の作業が見つかりません。'));
          }
          return _RipeningWorkForm(
            key: ObjectKey(detail),
            detail: detail,
            repository: widget.repository,
            now: widget.now,
          );
        },
      ),
    ),
  );
}

class _RipeningWorkForm extends StatefulWidget {
  const _RipeningWorkForm({
    required this.detail,
    required this.repository,
    required this.now,
    super.key,
  });
  final RipeningWorkDetail detail;
  final RipeningWorkRepository repository;
  final DateTime Function() now;
  @override
  State<_RipeningWorkForm> createState() => _RipeningWorkFormState();
}

class _RipeningWorkFormState extends State<_RipeningWorkForm> {
  final _form = GlobalKey<FormState>();
  final _temperature = TextEditingController();
  final _notes = TextEditingController();
  String? _worker;
  DateTime? _manualAt;
  bool _checked = false;
  bool _busy = false;
  bool _done = false;
  bool _blocked = false;
  String? _error;

  WorkTaskItem get task => widget.detail.task;
  String get action => task.type == WorkTaskType.ethyleneRemovalCheck
      ? '抜き確認・寝かせ開始'
      : task.type.label;
  String get checkLabel => switch (task.type) {
    WorkTaskType.ethyleneInjection => '対象とエチレン注入の実施を確認しました',
    WorkTaskType.ethyleneRemovalCheck => 'エチレン抜きと寝かせ開始を確認しました',
    _ => '追熟状態を確認し、出荷可能と判断しました',
  };

  @override
  void initState() {
    super.initState();
    _temperature.text = widget.detail.plannedTemperature?.toString() ?? '';
    if (widget.detail.workers.any((w) => w.id == task.assignedWorkerId)) {
      _worker = task.assignedWorkerId;
    }
  }

  @override
  void dispose() {
    _temperature.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(action, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          const Text('対象ID'),
          Text(
            task.targetDisplayId,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
              fontSize: 20,
            ),
          ),
          Text(
            task.weightHundredths == null
                ? '重量未設定'
                : formatWorkTaskWeight(task.weightHundredths!),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          Text(task.productLabel),
          Text('場所：${task.location ?? '未設定'}'),
          const Divider(height: 32),
          Text('予定日時：${_date(task.scheduledAt)}'),
          Text(
            '予定温度：${widget.detail.plannedTemperature?.toString() ?? '未設定'} ℃',
          ),
          const SizedBox(height: 20),
          if (_done)
            const Text('作業を完了しました')
          else if (!task.isPending)
            const Text('この作業は完了または中止されています')
          else if (!widget.detail.canComplete)
            const Text('この作業を完了する権限がありません')
          else if (task.weightHundredths == null || task.weightHundredths! <= 0)
            const Text('対象の重量を確認できないため、完了できません。')
          else
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '実績日時：${_manualAt == null ? '完了確認へ進む時の現在日時' : _date(_manualAt!)}',
                  ),
                  OutlinedButton(
                    onPressed: _busy || _blocked ? null : _pickDate,
                    child: const Text('実績日時を変更'),
                  ),
                  if (_manualAt != null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _manualAt = null),
                      child: const Text('現在日時を使用'),
                    ),
                  TextFormField(
                    key: const Key('work-temperature'),
                    controller: _temperature,
                    enabled: !_busy && !_blocked,
                    decoration: const InputDecoration(labelText: '実績温度（℃）'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    validator: (value) {
                      final number = double.tryParse(value?.trim() ?? '');
                      return number == null || !number.isFinite
                          ? '温度を数値で入力してください'
                          : null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const Key('work-worker'),
                    initialValue: _worker,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '担当者'),
                    items: widget.detail.workers
                        .map(
                          (w) => DropdownMenuItem(
                            value: w.id,
                            child: Text(w.name),
                          ),
                        )
                        .toList(),
                    onChanged: _busy || _blocked
                        ? null
                        : (value) => setState(() => _worker = value),
                    validator: (value) => value == null ? '担当者を選択してください' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notes,
                    enabled: !_busy && !_blocked,
                    decoration: const InputDecoration(labelText: '備考（任意）'),
                    maxLines: 3,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(checkLabel),
                    value: _checked,
                    onChanged: _busy || _blocked
                        ? null
                        : (value) => setState(() => _checked = value!),
                  ),
                  if (_error != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: _busy || _blocked ? null : _confirm,
                    child: const Text('完了内容を確認'),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _pickDate() async {
    final initial = _manualAt ?? widget.now();
    final day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(
      () => _manualAt = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _confirm() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    if (!_checked) {
      setState(() => _error = '作業の実施確認にチェックしてください。');
      return;
    }
    final input = RipeningWorkInput(
      actualAt: _manualAt ?? widget.now(),
      temperature: double.parse(_temperature.text.trim()),
      workerId: _worker!,
      notes: _notes.text.trim(),
      checked: _checked,
    );
    final operationKey = _operationKey();
    setState(() => _busy = true);
    var saving = false;
    var uncertain = false;
    String? error;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !saving && !uncertain,
          child: AlertDialog(
            title: Text('$actionを完了'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.targetDisplayId,
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    formatWorkTaskWeight(task.weightHundredths!),
                    style: const TextStyle(fontSize: 24),
                  ),
                  Text('実績日時：${_date(input.actualAt)}'),
                  Text('実績温度：${input.temperature} ℃'),
                  Text(
                    '担当者：${widget.detail.workers.firstWhere((w) => w.id == input.workerId).name}',
                  ),
                  if (input.notes.isNotEmpty) Text('備考：${input.notes}'),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving || uncertain
                    ? null
                    : () => Navigator.pop(context, false),
                child: const Text('入力へ戻る'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        update(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await widget.repository.complete(
                            widget.detail,
                            input,
                            idempotencyKey: operationKey,
                          );
                          if (context.mounted) Navigator.pop(context, true);
                        } catch (failure) {
                          if (!context.mounted) return;
                          if (failure is RipeningWorkFailure &&
                              !failure.retryable) {
                            _blocked = true;
                            _error =
                                '${failure.message} 作業一覧へ戻り、最新の状態で開き直してください。';
                            Navigator.pop(context, false);
                            return;
                          }
                          update(() {
                            saving = false;
                            uncertain = true;
                            error = '保存結果を確認できません。同じ内容で再試行してください。';
                          });
                        }
                      },
                child: Text(
                  saving
                      ? '保存中…'
                      : uncertain
                      ? '同じ内容で再試行'
                      : '完了する',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = result == true;
    });
    if (_done) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('完了しました'),
          content: Text(
            '${task.targetDisplayId}\n${formatWorkTaskWeight(task.weightHundredths!)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
    }
  }
}

String _date(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String _operationKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
