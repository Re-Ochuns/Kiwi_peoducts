import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../core/common_state_view.dart';
import 'sorting_repository.dart';
import 'supabase_sorting_repository.dart';

class SortingTargetPage extends StatefulWidget {
  const SortingTargetPage({
    required this.repository,
    this.currentDate,
    super.key,
  });

  final SortingRepository repository;
  final DateTime? currentDate;

  @override
  State<SortingTargetPage> createState() => _SortingTargetPageState();
}

class _SortingTargetPageState extends State<SortingTargetPage> {
  final _searchController = TextEditingController();
  SortingLoadData? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_searchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_searchChanged)
      ..dispose();
    super.dispose();
  }

  void _searchChanged() => setState(() {});

  Future<void> _load() async {
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final data = await widget.repository.load();
      if (!mounted) return;
      setState(() => _data = data);
    } on SortingFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '選果対象を読み込めませんでした。通信状況を確認してください。');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _sortingAppBar(context),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return CommonStateView.error(
        title: '選果対象を読み込めませんでした',
        message: _error!,
        actionLabel: '再試行',
        onAction: _load,
      );
    }
    final data = _data;
    if (data == null) {
      return const CommonStateView.loading(title: '選果対象を読み込んでいます');
    }
    if (data.grades.isEmpty || data.workers.isEmpty) {
      return CommonStateView.error(
        title: '選果を開始できません',
        message: data.grades.isEmpty
            ? '有効な等級がありません。管理者へ連絡してください。'
            : '有効な担当者がありません。管理者へ連絡してください。',
        actionLabel: '再読込',
        onAction: _load,
      );
    }

    final lots = data.lots
        .where((lot) => lot.matches(_searchController.text))
        .toList();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '選果対象',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  const Text('検索', style: _fieldLabelStyle),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(hintText: 'ロットID・品種・産地'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: lots.isEmpty
                  ? CommonStateView.empty(
                      title: data.lots.isEmpty ? '選果対象はありません' : '一致するロットはありません',
                      message: data.lots.isEmpty
                          ? '選果待ちのロットが登録されると、ここに表示されます。'
                          : '検索条件を変更してください。',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        itemCount: lots.length,
                        itemBuilder: (context, index) => _SortingLotRow(
                          lot: lots[index],
                          today: widget.currentDate ?? DateTime.now(),
                          onTap: () => _openInput(data, lots[index]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInput(SortingLoadData data, SortingLot lot) async {
    final reload = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        pageBuilder: (_, _, _) => SortingInputPage(
          repository: widget.repository,
          lot: lot,
          grades: data.grades,
          workers: data.workers,
          currentDate: widget.currentDate,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
    if (reload == true && mounted) await _load();
  }
}

class _SortingLotRow extends StatelessWidget {
  const _SortingLotRow({
    required this.lot,
    required this.today,
    required this.onTap,
  });

  final SortingLot lot;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dueDate = DateTime(
      lot.sortingDueOn.year,
      lot.sortingDueOn.month,
      lot.sortingDueOn.day,
    );
    final current = DateTime(today.year, today.month, today.day);
    final overdue = dueDate.isBefore(current);
    return Semantics(
      label: '${lot.displayId}の選果入力へ進む',
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 106),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      lot.displayId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${formatWeight(lot.totalWeightHundredths)} kg',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                '${lot.varietyName}　${lot.originName}',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${overdue ? '期限超過・' : ''}期限 ${_formatDate(lot.sortingDueOn)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: overdue ? FontWeight.w700 : FontWeight.w400,
                        color: overdue ? AppColors.error : AppColors.mutedText,
                      ),
                    ),
                  ),
                  const Text(
                    '選果入力へ →',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SortingInputPage extends StatefulWidget {
  const SortingInputPage({
    required this.repository,
    required this.lot,
    required this.grades,
    required this.workers,
    this.currentDate,
    super.key,
  });

  final SortingRepository repository;
  final SortingLot lot;
  final List<SortingGrade> grades;
  final List<SortingWorker> workers;
  final DateTime? currentDate;

  @override
  State<SortingInputPage> createState() => _SortingInputPageState();
}

class _SortingInputPageState extends State<SortingInputPage> {
  late final TextEditingController _dateController;
  late final Map<String, List<_ContainerEntry>> _entries;
  late String _selectedGradeId;
  String? _workerId;
  String? _screenError;
  bool _submitting = false;
  int _nextEntryId = 1;
  String? _submissionSignature;
  String? _idempotencyKey;

  @override
  void initState() {
    super.initState();
    final current = widget.currentDate ?? DateTime.now();
    _dateController = TextEditingController(text: _dateValue(current))
      ..addListener(_formChanged);
    _entries = {for (final grade in widget.grades) grade.id: []};
    _selectedGradeId = widget.grades.first.id;
  }

  @override
  void dispose() {
    _dateController
      ..removeListener(_formChanged)
      ..dispose();
    for (final entry in _entries.values.expand((items) => items)) {
      entry.controller
        ..removeListener(_formChanged)
        ..dispose();
    }
    super.dispose();
  }

  List<_ContainerEntry> get _orderedEntries => [
    for (final grade in widget.grades) ..._entries[grade.id]!,
  ];

  int get _outputHundredths => _orderedEntries.fold(
    0,
    (sum, entry) => sum + (parseWeightHundredths(entry.controller.text) ?? 0),
  );

  int get _lossHundredths =>
      widget.lot.totalWeightHundredths - _outputHundredths;

  bool get _hasValidDate => _parseDate(_dateController.text) != null;

  bool get _hasValidWeights =>
      _orderedEntries.isNotEmpty &&
      _orderedEntries.every((entry) {
        final weight = parseWeightHundredths(entry.controller.text);
        return weight != null && weight > 0;
      });

  bool get _canConfirm =>
      !_submitting &&
      _workerId != null &&
      _hasValidDate &&
      _hasValidWeights &&
      _lossHundredths >= 0;

  String? get _readinessMessage {
    if (!_hasValidDate) return '選果日をYYYY-MM-DD形式で入力してください。';
    if (_workerId == null) return '担当者を選択してください。';
    if (_orderedEntries.isEmpty) return 'コンテナを1件以上追加してください。';
    if (!_hasValidWeights) return 'すべてのコンテナ重量を0.01kg単位で入力してください。';
    if (_lossHundredths < 0) {
      return '選果後重量が元重量を${formatWeight(-_lossHundredths)} kg超えています。';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selectedGrade = widget.grades.firstWhere(
      (grade) => grade.id == _selectedGradeId,
    );
    final selectedEntries = _entries[selectedGrade.id]!;
    return Scaffold(
      appBar: _sortingAppBar(context, backLabel: '← 選果対象へ戻る'),
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '選果入力',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  _LotSummary(lot: widget.lot),
                  const SizedBox(height: 24),
                  const Text('選果日', style: _fieldLabelStyle),
                  const SizedBox(height: 8),
                  Semantics(
                    textField: true,
                    label: '選果日、YYYY-MM-DD形式',
                    child: TextField(
                      key: const Key('sorting-date'),
                      controller: _dateController,
                      keyboardType: TextInputType.datetime,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                        LengthLimitingTextInputFormatter(10),
                      ],
                      decoration: InputDecoration(
                        hintText: 'YYYY-MM-DD',
                        errorText: _hasValidDate
                            ? null
                            : 'YYYY-MM-DD形式で入力してください',
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('担当者', style: _fieldLabelStyle),
                  const SizedBox(height: 8),
                  Semantics(
                    label: '担当者を選択',
                    child: DropdownButtonFormField<String>(
                      key: const Key('sorting-worker'),
                      initialValue: _workerId,
                      isExpanded: true,
                      hint: const Text('選択してください'),
                      items: [
                        for (final worker in widget.workers)
                          DropdownMenuItem(
                            value: worker.id,
                            child: Text(worker.label),
                          ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) {
                              setState(() {
                                _workerId = value;
                                _screenError = null;
                              });
                            },
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    '等級とコンテナ',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  _GradeSelector(
                    grades: widget.grades,
                    entries: _entries,
                    selectedGradeId: _selectedGradeId,
                    onSelected: _submitting
                        ? null
                        : (gradeId) => setState(() {
                            _selectedGradeId = gradeId;
                            _screenError = null;
                          }),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '${selectedGrade.code}のコンテナ',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (selectedEntries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'コンテナはまだありません。',
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.mutedText,
                        ),
                      ),
                    )
                  else
                    for (var index = 0; index < selectedEntries.length; index++)
                      _buildContainerRow(
                        selectedGrade,
                        selectedEntries[index],
                        index,
                      ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    key: const Key('add-container'),
                    onPressed: _submitting
                        ? null
                        : () => _addContainer(selectedGrade.id),
                    child: Text('${selectedGrade.code}のコンテナを追加'),
                  ),
                  const SizedBox(height: 28),
                  if (_screenError != null)
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
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _SortingSummaryBar(
        outputHundredths: _outputHundredths,
        lossHundredths: _lossHundredths,
        readinessMessage: _readinessMessage,
        submitting: _submitting,
        onConfirm: _canConfirm ? _showConfirmation : null,
      ),
    );
  }

  Widget _buildContainerRow(
    SortingGrade grade,
    _ContainerEntry entry,
    int gradeIndex,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  'コンテナ${gradeIndex + 1}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Semantics(
                  textField: true,
                  label: '${grade.code} コンテナ${gradeIndex + 1}の正味重量',
                  child: TextField(
                    key: Key('weight-${entry.id}'),
                    controller: entry.controller,
                    enabled: !_submitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      hintText: '0.00',
                      errorText: entry.error,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text('kg', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => _removeContainer(grade, entry, gradeIndex),
                style: TextButton.styleFrom(minimumSize: const Size(60, 48)),
                child: const Text('削除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _addContainer(String gradeId) {
    final entry = _ContainerEntry(
      id: _nextEntryId++,
      gradeId: gradeId,
      controller: TextEditingController(),
    );
    entry.controller.addListener(_formChanged);
    setState(() {
      _entries[gradeId]!.add(entry);
      _screenError = null;
    });
  }

  Future<void> _removeContainer(
    SortingGrade grade,
    _ContainerEntry entry,
    int gradeIndex,
  ) async {
    if (entry.controller.text.trim().isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${grade.code}のコンテナ${gradeIndex + 1}を削除'),
          content: const Text('入力した重量は削除されます。'),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('入力へ戻る'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除する'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _entries[grade.id]!.remove(entry);
      _screenError = null;
    });
    entry.controller
      ..removeListener(_formChanged)
      ..dispose();
  }

  void _formChanged() {
    if (!mounted) return;
    setState(() {
      _screenError = null;
      for (final entry in _orderedEntries) {
        entry.error = null;
      }
    });
  }

  SortingInput _buildInput() => SortingInput(
    receivingLotId: widget.lot.id,
    sortingDate: _dateController.text,
    workerId: _workerId!,
    expectedLotVersion: widget.lot.version,
    containers: [
      for (final entry in _orderedEntries)
        SortingContainerInput(
          gradeId: entry.gradeId,
          weightHundredths: parseWeightHundredths(entry.controller.text)!,
        ),
    ],
  );

  Future<void> _showConfirmation() async {
    final input = _buildInput();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('選果内容を確認'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DialogValue(label: '対象ロット', value: widget.lot.displayId),
              _DialogValue(
                label: '元重量',
                value: '${formatWeight(widget.lot.totalWeightHundredths)} kg',
              ),
              _DialogValue(
                label: '選果後合計',
                value: '${formatWeight(_outputHundredths)} kg',
              ),
              _DialogValue(
                label: 'ロス',
                value: '${formatWeight(_lossHundredths)} kg',
              ),
              _DialogValue(
                label: 'コンテナ数',
                value: '${input.containers.length}件',
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('入力へ戻る'),
          ),
          FilledButton(
            key: const Key('submit-sorting'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('選果を確定'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _submit(input);
  }

  Future<void> _submit(SortingInput input) async {
    final signature = input.signature;
    if (_submissionSignature != signature) {
      _submissionSignature = signature;
      _idempotencyKey = createSortingIdempotencyKey();
    }
    setState(() {
      _submitting = true;
      _screenError = null;
    });
    try {
      final result = await widget.repository.confirm(
        input: input,
        idempotencyKey: _idempotencyKey!,
      );
      if (!mounted) return;
      await _showSuccess(result);
    } on SortingFailure catch (failure) {
      if (!mounted) return;
      if (failure.isConflict) {
        await _showConflict(failure);
        return;
      }
      _applyFieldError(failure);
      setState(() {
        _screenError = _errorWithCorrelation(failure);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _screenError = '確定結果を確認できませんでした。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _applyFieldError(SortingFailure failure) {
    final match = RegExp(r'^containers\[(\d+)\]\.weight_kg$')
        .firstMatch(failure.field ?? '');
    if (match == null) return;
    final index = int.parse(match.group(1)!);
    if (index >= 0 && index < _orderedEntries.length) {
      _orderedEntries[index].error = failure.message;
    }
  }

  String _errorWithCorrelation(SortingFailure failure) {
    final correlationId = failure.correlationId;
    if (correlationId == null || correlationId.isEmpty) return failure.message;
    return '${failure.message}\n問い合わせ番号: $correlationId';
  }

  Future<void> _showConflict(SortingFailure failure) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('最新の状態を確認してください'),
        content: Text(failure.message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('選果対象を再読込'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _showSuccess(SortingResult result) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('選果を確定しました'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DialogValue(label: '選果ID', value: result.displayId),
                _DialogValue(
                  label: '選果後合計',
                  value: '${formatWeight(result.outputWeightHundredths)} kg',
                ),
                _DialogValue(
                  label: 'ロス',
                  value: '${formatWeight(result.lossWeightHundredths)} kg',
                ),
                const SizedBox(height: 12),
                const Text('生成したコンテナ', style: _fieldLabelStyle),
                for (final container in result.containers)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${container.displayId}　${_gradeCode(container.gradeId)}　'
                      '${formatWeight(container.weightHundredths)} kg',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('選果対象へ戻る'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  String _gradeCode(String gradeId) => widget.grades
      .firstWhere(
        (grade) => grade.id == gradeId,
        orElse: () => SortingGrade(id: gradeId, code: '等級不明', displayOrder: 0),
      )
      .code;
}

class _LotSummary extends StatelessWidget {
  const _LotSummary({required this.lot});

  final SortingLot lot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.line),
          bottom: BorderSide(color: AppColors.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            lot.displayId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '${formatWeight(lot.totalWeightHundredths)} kg',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${lot.varietyName}　${lot.originName}',
            style: const TextStyle(fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _GradeSelector extends StatelessWidget {
  const _GradeSelector({
    required this.grades,
    required this.entries,
    required this.selectedGradeId,
    required this.onSelected,
  });

  final List<SortingGrade> grades;
  final Map<String, List<_ContainerEntry>> entries;
  final String selectedGradeId;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final grade in grades)
              SizedBox(width: width, child: _gradeButton(grade)),
          ],
        );
      },
    );
  }

  Widget _gradeButton(SortingGrade grade) {
    final selected = grade.id == selectedGradeId;
    final gradeEntries = entries[grade.id]!;
    final total = gradeEntries.fold(
      0,
      (sum, entry) => sum + (parseWeightHundredths(entry.controller.text) ?? 0),
    );
    return Semantics(
      selected: selected,
      button: true,
      label: '${grade.code}、${gradeEntries.length}個、${formatWeight(total)} kg',
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onSelected == null ? null : () => onSelected!(grade.id),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size(0, 68),
          backgroundColor: selected ? const Color(0xFFEAF2ED) : Colors.white,
          side: BorderSide(color: selected ? AppColors.green : AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              grade.code,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              '${gradeEntries.length}個・${formatWeight(total)} kg',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortingSummaryBar extends StatelessWidget {
  const _SortingSummaryBar({
    required this.outputHundredths,
    required this.lossHundredths,
    required this.readinessMessage,
    required this.submitting,
    required this.onConfirm,
  });

  final int outputHundredths;
  final int lossHundredths;
  final String? readinessMessage;
  final bool submitting;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 528),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryValue(
                          label: '選果後合計',
                          value: '${formatWeight(outputHundredths)} kg',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _SummaryValue(
                          label: lossHundredths < 0 ? '元重量から超過' : 'ロス',
                          value: '${formatWeight(lossHundredths.abs())} kg',
                          error: lossHundredths < 0,
                        ),
                      ),
                    ],
                  ),
                  if (readinessMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      readinessMessage!,
                      style: TextStyle(
                        fontSize: 13,
                        color: lossHundredths < 0
                            ? AppColors.error
                            : AppColors.mutedText,
                        fontWeight: lossHundredths < 0
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  FilledButton(
                    key: const Key('confirm-sorting'),
                    onPressed: onConfirm,
                    child: Text(submitting ? '確定しています' : '入力内容を確認'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.value,
    this.error = false,
  });

  final String label;
  final String value;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.mutedText),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: error ? AppColors.error : AppColors.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _DialogValue extends StatelessWidget {
  const _DialogValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: AppColors.mutedText),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContainerEntry {
  _ContainerEntry({
    required this.id,
    required this.gradeId,
    required this.controller,
  });

  final int id;
  final String gradeId;
  final TextEditingController controller;
  String? error;
}

AppBar _sortingAppBar(BuildContext context, {String backLabel = '← ToDoへ戻る'}) =>
    AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 8,
      title: TextButton(
        onPressed: () => Navigator.maybePop(context),
        style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
        child: Text(backLabel),
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1),
      ),
    );

const _fieldLabelStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);

String _formatDate(DateTime date) => '${date.year}年${date.month}月${date.day}日';

String _dateValue(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime? _parseDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      parsed.year != year ||
      parsed.month != month ||
      parsed.day != day) {
    return null;
  }
  return parsed;
}
