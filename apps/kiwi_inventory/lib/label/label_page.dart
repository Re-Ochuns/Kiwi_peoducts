import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../core/common_state_view.dart';
import 'label_pdf_opener.dart';
import 'label_repository.dart';
import 'supabase_label_repository.dart';

enum _LabelFilter { pending, completed }

class LabelTargetPage extends StatefulWidget {
  const LabelTargetPage({required this.repository, this.pdfOpener, super.key});

  final LabelRepository repository;
  final LabelPdfOpener? pdfOpener;

  @override
  State<LabelTargetPage> createState() => _LabelTargetPageState();
}

class _LabelTargetPageState extends State<LabelTargetPage> {
  LabelLoadData? _data;
  LabelFailure? _error;
  bool _loadingMore = false;
  String? _moreError;
  int _loadGeneration = 0;
  _LabelFilter _filter = _LabelFilter.pending;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _data = null;
      _error = null;
      _loadingMore = false;
      _moreError = null;
    });
    try {
      final data = await widget.repository.load(
        completed: _filter == _LabelFilter.completed,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _data = data);
    } on LabelFailure catch (failure) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = failure);
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(
        () => _error = const LabelFailure(
          message: 'ラベル対象を読み込めませんでした。通信状況を確認してください。',
          retryable: true,
        ),
      );
    }
  }

  Future<void> _loadMore() async {
    final data = _data;
    final cursor = data?.nextCursor;
    if (data == null || cursor == null || _loadingMore) return;
    final generation = _loadGeneration;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await widget.repository.load(
        completed: _filter == _LabelFilter.completed,
        after: cursor,
      );
      if (!mounted || generation != _loadGeneration) return;
      final ids = data.jobs.map((job) => job.id).toSet();
      setState(
        () => _data = LabelLoadData(
          jobs: [...data.jobs, ...page.jobs.where((job) => ids.add(job.id))],
          workers: page.workers,
          locations: page.locations,
          nextCursor: page.nextCursor,
        ),
      );
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _moreError = '続きを読み込めませんでした。再試行してください。');
      }
    } finally {
      if (mounted && generation == _loadGeneration)
        setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _labelAppBar(context),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null) {
      return CommonStateView.error(
        title: 'ラベル対象を読み込めませんでした',
        message: error.message,
        actionLabel: error.retryable ? '再試行' : null,
        onAction: error.retryable ? _load : null,
      );
    }
    final data = _data;
    if (data == null) {
      return const CommonStateView.loading(title: 'ラベル対象を読み込んでいます');
    }
    if (data.workers.isEmpty) {
      return CommonStateView.error(
        title: 'ラベル対応を開始できません',
        message: '有効な担当者がありません。管理者へ連絡してください。',
        actionLabel: '再読込',
        onAction: _load,
      );
    }
    final jobs = data.jobs
        .where(
          (job) =>
              _filter == _LabelFilter.pending ? job.isPending : !job.isPending,
        )
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
                    'ラベル発行',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  const Text('表示する対象', style: _fieldLabelStyle),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<_LabelFilter>(
                    key: const Key('label-filter'),
                    icon: const SizedBox.shrink(),
                    initialValue: _filter,
                    items: const [
                      DropdownMenuItem(
                        value: _LabelFilter.pending,
                        child: Text('未対応・一部印刷'),
                      ),
                      DropdownMenuItem(
                        value: _LabelFilter.completed,
                        child: Text('対応済み'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _filter = value);
                        _load();
                      }
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: jobs.isEmpty
                  ? CommonStateView.empty(
                      title: _filter == _LabelFilter.pending
                          ? '未対応のラベルはありません'
                          : '対応済みのラベルはありません',
                      message: _filter == _LabelFilter.pending
                          ? '選果でコンテナが作成されると、ここに表示されます。'
                          : '印刷または手書き対応が完了すると、ここに表示されます。',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        itemCount:
                            jobs.length + (data.nextCursor != null ? 1 : 0),
                        itemBuilder: (context, index) => index == jobs.length
                            ? Column(
                                children: [
                                  if (_moreError != null) Text(_moreError!),
                                  OutlinedButton(
                                    onPressed: _loadingMore ? null : _loadMore,
                                    child: Text(
                                      _loadingMore ? '読み込み中' : 'さらに読み込む',
                                    ),
                                  ),
                                ],
                              )
                            : _LabelJobRow(
                                job: jobs[index],
                                onTap: () => _openDetail(data, jobs[index]),
                              ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDetail(LabelLoadData data, LabelJob job) async {
    final reload = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        pageBuilder: (_, _, _) => LabelDetailPage(
          repository: widget.repository,
          job: job,
          workers: data.workers,
          locations: data.locations,
          pdfOpener: widget.pdfOpener,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
    if (reload == true && mounted) await _load();
  }
}

class _LabelJobRow extends StatelessWidget {
  const _LabelJobRow({required this.job, required this.onTap});

  final LabelJob job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${job.containerDisplayId}、${job.gradeCode}、'
          '${formatWeight(job.weightHundredths)}キログラム、${job.statusLabel}、'
          '${job.containerDisplayId}のラベル詳細を見る',
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
                      job.containerDisplayId,
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
                    '${formatWeight(job.weightHundredths)} kg',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text('${job.varietyName}　${job.gradeCode}　${job.originName}'),
              const SizedBox(height: 7),
              Row(
                children: [
                  _StatusLabel(text: job.statusLabel),
                  const Spacer(),
                  const Text(
                    '詳細を見る →',
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

class LabelDetailPage extends StatefulWidget {
  const LabelDetailPage({
    required this.repository,
    required this.job,
    required this.workers,
    required this.locations,
    this.pdfOpener,
    super.key,
  });

  final LabelRepository repository;
  final LabelJob job;
  final List<LabelOption> workers;
  final List<LabelOption> locations;
  final LabelPdfOpener? pdfOpener;

  @override
  State<LabelDetailPage> createState() => _LabelDetailPageState();
}

class _LabelDetailPageState extends State<LabelDetailPage> {
  late final TextEditingController _copiesController;
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  String? _workerId;
  String? _locationId;
  String? _error;
  bool _busy = false;
  bool _loadingPdf = false;
  LabelPdf? _pdf;
  String? _actionSignature;
  String? _idempotencyKey;
  Future<LabelActionResult> Function()? _pendingAction;
  bool _pendingReprint = false;

  LabelJob get job => widget.job;

  @override
  void initState() {
    super.initState();
    _copiesController = TextEditingController(
      text: job.canReprint ? '1' : '${job.remainingCopies}',
    );
    _copiesController.addListener(_formChanged);
    _reasonController.addListener(_formChanged);
    _notesController.addListener(_formChanged);
    if (job.isPending || job.canReprint) _preparePdf();
  }

  @override
  void dispose() {
    _copiesController
      ..removeListener(_formChanged)
      ..dispose();
    _reasonController
      ..removeListener(_formChanged)
      ..dispose();
    _notesController
      ..removeListener(_formChanged)
      ..dispose();
    super.dispose();
  }

  void _formChanged() {
    if (!mounted) return;
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_pendingAction != null) {
      return PopScope<void>(
        canPop: false,
        child: Scaffold(
          appBar: _labelAppBar(context, backLabel: '← ラベル一覧へ戻る'),
          body: SafeArea(
            child: CommonStateView.error(
              title: _busy ? '記録結果を確認しています' : '記録結果が未確認です',
              message: _error ?? '再印刷や入力変更はせず、同じ操作の結果を確認してください。',
              actionLabel: _busy ? null : '記録結果を再確認',
              onAction: _busy ? null : _executePending,
            ),
          ),
        ),
      );
    }
    return PopScope<void>(
      canPop: !_busy,
      child: Scaffold(
        appBar: _labelAppBar(context, backLabel: '← ラベル一覧へ戻る'),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'ラベル確認',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            job.containerDisplayId,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        _StatusLabel(text: job.statusLabel),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _LabelPreview(job: job),
                    const SizedBox(height: 24),
                    _ProgressSummary(job: job),
                    if (job.isPending || job.canReprint) ...[
                      const SizedBox(height: 24),
                      const Text('担当者', style: _fieldLabelStyle),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        key: const Key('label-worker'),
                        icon: const SizedBox.shrink(),
                        initialValue: _workerId,
                        hint: const Text('選択してください'),
                        isExpanded: true,
                        items: [
                          for (final worker in widget.workers)
                            DropdownMenuItem(
                              value: worker.id,
                              child: Text(worker.label),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                _workerId = value;
                                _error = null;
                              }),
                      ),
                      const SizedBox(height: 18),
                      const Text('今回の枚数', style: _fieldLabelStyle),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('label-copies'),
                        controller: _copiesController,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(hintText: '1'),
                      ),
                    ],
                    if (job.isPending) ...[
                      const SizedBox(height: 18),
                      const Text('保管場所（任意）', style: _fieldLabelStyle),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        key: const Key('label-location'),
                        icon: const SizedBox.shrink(),
                        initialValue: _locationId,
                        hint: const Text('指定しない'),
                        isExpanded: true,
                        items: [
                          for (final location in widget.locations)
                            DropdownMenuItem(
                              value: location.id,
                              child: Text(location.label),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                _locationId = value;
                                _error = null;
                              }),
                      ),
                    ],
                    if (job.canReprint) ...[
                      const SizedBox(height: 18),
                      const Text('再印刷理由', style: _fieldLabelStyle),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('reprint-reason'),
                        controller: _reasonController,
                        enabled: !_busy,
                        maxLines: 2,
                        maxLength: 200,
                        decoration: const InputDecoration(
                          hintText: '汚損・紛失などの理由を入力',
                        ),
                      ),
                    ],
                    if (job.isPending) ...[
                      const SizedBox(height: 18),
                      const Text('手書き対応の備考（任意）', style: _fieldLabelStyle),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('handwritten-notes'),
                        controller: _notesController,
                        enabled: !_busy,
                        maxLines: 2,
                        maxLength: 200,
                        decoration: const InputDecoration(
                          hintText: '印刷できなかった理由など',
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (job.isPending || job.canReprint) ...[
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('open-label-pdf'),
                        onPressed: _busy || _loadingPdf
                            ? null
                            : _pdf == null
                            ? _preparePdf
                            : _openPdfAndConfirm,
                        child: Text(
                          _busy
                              ? '処理しています'
                              : _loadingPdf
                              ? 'PDFを準備しています'
                              : _pdf == null
                              ? 'PDFを再取得'
                              : job.canReprint
                              ? '再印刷用PDFを表示'
                              : 'PDFを表示して印刷',
                        ),
                      ),
                    ],
                    if (job.isPending) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        key: const Key('handwritten-label'),
                        onPressed: _busy ? null : _confirmHandwritten,
                        child: const Text('手書き対応'),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '印刷環境が復旧する見込みならPDFを再試行してください。'
                        '作業を続ける必要がある場合だけ手書き対応を確定します。',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.mutedText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  int? _validatedCopies() {
    final copies = int.tryParse(_copiesController.text.trim());
    if (copies == null || copies < 1 || copies > 999) {
      setState(() => _error = '今回の枚数は1〜999の整数で入力してください。');
      return null;
    }
    return copies;
  }

  bool _validateWorker() {
    if (_workerId != null) return true;
    setState(() => _error = '担当者を選択してください。');
    return false;
  }

  Future<void> _preparePdf() async {
    if (_loadingPdf) return;
    setState(() {
      _loadingPdf = true;
      _error = null;
    });
    try {
      final pdf = await widget.repository.fetchPdf(
        containerId: job.containerId,
      );
      if (!mounted) return;
      setState(() => _pdf = pdf);
    } on LabelFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = _messageWithCorrelation(failure));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'ラベルPDFを取得できませんでした。再試行してください。');
    } finally {
      if (mounted) setState(() => _loadingPdf = false);
    }
  }

  Future<void> _openPdfAndConfirm() async {
    if (!_validateWorker()) return;
    final copies = _validatedCopies();
    if (copies == null) return;
    if (job.canReprint && _reasonController.text.trim().isEmpty) {
      setState(() => _error = '再印刷理由を入力してください。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pdf = _pdf;
      if (pdf == null) return;
      final opened = await (widget.pdfOpener ?? openLabelPdf)(
        pdf.bytes,
        '${job.containerDisplayId}.pdf',
      );
      if (!mounted) return;
      if (!opened) {
        setState(() => _error = 'PDFを開けませんでした。ポップアップの許可を確認して再試行してください。');
        return;
      }
      final printed = await _showPrintConfirmation(copies);
      if (printed == true && mounted) await _recordPrint(copies);
    } on LabelFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = _messageWithCorrelation(failure));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'ラベルPDFを表示できませんでした。再試行してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _showPrintConfirmation(int copies) => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(job.canReprint ? '再印刷結果を確認' : '印刷結果を確認'),
      content: Text(
        '${job.containerDisplayId}を$copies枚印刷できましたか。'
        '\n中断や失敗の場合は記録せず、PDFから印刷をやり直してください。',
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('印刷できなかった'),
        ),
        FilledButton(
          key: const Key('confirm-label-printed'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('印刷できた'),
        ),
      ],
    ),
  );

  Future<void> _recordPrint(int copies) async {
    final isReprint = job.canReprint;
    final signature = isReprint
        ? 'reprint:${job.id}:${_workerId!}:${_reasonController.text.trim()}:$copies'
        : 'print:${job.id}:${_workerId!}:$copies:${_locationId ?? ''}';
    final key = _keyFor(signature);
    final workerId = _workerId!;
    final reason = _reasonController.text;
    final locationId = _locationId;
    _pendingReprint = isReprint;
    _pendingAction = isReprint
        ? () => widget.repository.reprint(
            labelJobId: job.id,
            workerId: workerId,
            reason: reason,
            copies: copies,
            idempotencyKey: key,
          )
        : () => widget.repository.markPrinted(
            labelJobId: job.id,
            workerId: workerId,
            copies: copies,
            locationId: locationId,
            idempotencyKey: key,
          );
    await _executePending();
  }

  Future<void> _executePending() async {
    final action = _pendingAction;
    if (action == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await action();
      if (!mounted) return;
      _pendingAction = null;
      await _showSuccess(result, reprint: _pendingReprint);
    } on LabelFailure catch (failure) {
      if (!mounted) return;
      if (!failure.retryable) {
        _pendingAction = null;
        _actionSignature = null;
        _idempotencyKey = null;
      }
      if (failure.isConflict) {
        await _showConflict(failure);
      } else {
        setState(() => _error = _messageWithCorrelation(failure));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '記録結果を確認できませんでした。同じ操作の結果を再確認してください。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmHandwritten() async {
    if (!_validateWorker()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('手書き内容を確認'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('次の内容をA5用紙へ記入してから確定してください。'),
            const SizedBox(height: 14),
            _DialogValue(label: 'コンテナID', value: job.containerDisplayId),
            _DialogValue(label: '産地・区画', value: job.originName),
            _DialogValue(
              label: '品種・等級',
              value: '${job.varietyName}・${job.gradeCode}',
            ),
            _DialogValue(
              label: '正味重量',
              value: '${formatWeight(job.weightHundredths)} kg',
            ),
            _DialogValue(label: '選果日', value: _formatDate(job.sortedOn)),
            _DialogValue(label: '選果担当者', value: job.workerName),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('確認へ戻る'),
          ),
          FilledButton(
            key: const Key('confirm-handwritten-label'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('手書き対応を確定'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final signature =
        'handwritten:${job.id}:${_workerId!}:${_notesController.text.trim()}:${_locationId ?? ''}';
    final workerId = _workerId!;
    final notes = _notesController.text;
    final locationId = _locationId;
    final key = _keyFor(signature);
    _pendingReprint = false;
    _pendingAction = () => widget.repository.markHandwritten(
      labelJobId: job.id,
      workerId: workerId,
      notes: notes,
      locationId: locationId,
      idempotencyKey: key,
    );
    await _executePending();
  }

  String _keyFor(String signature) {
    if (_actionSignature != signature) {
      _actionSignature = signature;
      _idempotencyKey = createLabelIdempotencyKey();
    }
    return _idempotencyKey!;
  }

  Future<void> _showSuccess(
    LabelActionResult result, {
    bool reprint = false,
  }) async {
    final partial = result.status == LabelJobStatus.partiallyPrinted;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          reprint
              ? '再印刷を記録しました'
              : partial
              ? '一部印刷を記録しました'
              : result.status == LabelJobStatus.handwritten
              ? '手書き対応を記録しました'
              : '印刷済みを記録しました',
        ),
        content: Text(
          reprint
              ? '再印刷回数 ${result.reprintCount}回、累計 ${result.printedCopies}枚です。'
              : partial
              ? '${result.printedCopies}/${result.requiredCopies}枚です。残りを印刷してください。'
              : '${job.containerDisplayId}のラベル対応が完了しました。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('一覧へ戻る'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _showConflict(LabelFailure failure) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('最新の状態を確認してください'),
        content: Text(failure.message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('一覧を再読込'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  String _messageWithCorrelation(LabelFailure failure) {
    final id = failure.correlationId;
    return id == null || id.isEmpty
        ? failure.message
        : '${failure.message}\n問い合わせ番号: $id';
  }
}

class _LabelPreview extends StatelessWidget {
  const _LabelPreview({required this.job});

  final LabelJob job;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ink, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('ラベル記載内容', style: _fieldLabelStyle),
          const SizedBox(height: 14),
          Text(
            job.containerDisplayId,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${formatWeight(job.weightHundredths)} kg',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          _PreviewRow(label: '産地・区画', value: job.originName),
          _PreviewRow(label: '品種', value: job.varietyName),
          _PreviewRow(label: '等級', value: job.gradeCode),
          _PreviewRow(label: '選果日', value: _formatDate(job.sortedOn)),
          _PreviewRow(label: '担当者', value: job.workerName),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.mutedText),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({required this.job});

  final LabelJob job;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.line),
          bottom: BorderSide(color: AppColors.line),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('印刷 ${job.printedCopies}/${job.requiredCopies}枚'),
          ),
          Text('再印刷 ${job.reprintCount}回'),
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDEA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: _fieldLabelStyle),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

AppBar _labelAppBar(BuildContext context, {String backLabel = '← ホームへ戻る'}) =>
    AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      title: TextButton(
        onPressed: () => Navigator.maybePop(context),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
          foregroundColor: AppColors.ink,
        ),
        child: Text(backLabel),
      ),
    );

const _fieldLabelStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);

String formatWeight(int hundredths) => (hundredths / 100).toStringAsFixed(2);

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
