import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../sorting/sorting_repository.dart';
import 'label_pdf_opener.dart';
import 'label_repository.dart';
import 'supabase_label_repository.dart';

class SortingLabelBatchPage extends StatefulWidget {
  const SortingLabelBatchPage({
    required this.repository,
    required this.result,
    required this.lot,
    required this.grades,
    required this.workerId,
    required this.workerName,
    required this.sortedOn,
    this.pdfOpener,
    super.key,
  });

  final LabelRepository repository;
  final SortingResult result;
  final SortingLot lot;
  final List<SortingGrade> grades;
  final String workerId;
  final String workerName;
  final DateTime sortedOn;
  final LabelPdfOpener? pdfOpener;

  @override
  State<SortingLabelBatchPage> createState() => _SortingLabelBatchPageState();
}

class _SortingLabelBatchPageState extends State<SortingLabelBatchPage> {
  LabelPdf? _pdf;
  String? _error;
  String? _idempotencyKey;
  bool _loadingPdf = false;
  bool _busy = false;
  bool _resultUnconfirmed = false;
  int _pageIndex = 0;

  late final List<SortingResultContainer> _containers;

  @override
  void initState() {
    super.initState();
    _containers = [...widget.result.containers]
      ..sort((a, b) {
        final grade = _gradeOrder(a.gradeId).compareTo(_gradeOrder(b.gradeId));
        return grade != 0 ? grade : a.displayId.compareTo(b.displayId);
      });
    _preparePdf();
  }

  int _gradeOrder(String gradeId) => widget.grades
      .firstWhere(
        (grade) => grade.id == gradeId,
        orElse: () =>
            SortingGrade(id: gradeId, code: '不明', displayOrder: 1 << 30),
      )
      .displayOrder;

  String _gradeCode(String gradeId) => widget.grades
      .firstWhere(
        (grade) => grade.id == gradeId,
        orElse: () =>
            SortingGrade(id: gradeId, code: '不明', displayOrder: 1 << 30),
      )
      .code;

  @override
  Widget build(BuildContext context) {
    final current = _containers[_pageIndex];
    return PopScope<void>(
      canPop: !_busy && !_resultUnconfirmed,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          title: TextButton(
            onPressed: _busy || _resultUnconfirmed
                ? null
                : () => Navigator.maybePop(context),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: EdgeInsets.zero,
              foregroundColor: AppColors.ink,
            ),
            child: const Text('← 選果結果へ戻る'),
          ),
        ),
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
                      'ラベル一括確認',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.result.displayId}で作成した${_containers.length}枚を確認します。',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('previous-label'),
                            onPressed: _pageIndex == 0 || _busy
                                ? null
                                : () => setState(() => _pageIndex--),
                            child: const Text('← 前のラベル'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_pageIndex + 1} / ${_containers.length}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('next-label'),
                            onPressed:
                                _pageIndex == _containers.length - 1 || _busy
                                ? null
                                : () => setState(() => _pageIndex++),
                            child: const Text('次のラベル →'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _MonochromeSortingLabel(
                      page: _pageIndex + 1,
                      pageCount: _containers.length,
                      gradeCode: _gradeCode(current.gradeId),
                      varietyName: widget.lot.varietyName,
                      weightHundredths: current.weightHundredths,
                      containerDisplayId: current.displayId,
                      originName: widget.lot.originName,
                      sortedOn: widget.sortedOn,
                      workerName: widget.workerName,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '白黒で印刷されます。選果サイズ・品種・重量・コンテナIDを確認してください。',
                      style: TextStyle(fontSize: 14),
                    ),
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
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('open-sorting-batch-pdf'),
                      onPressed: _busy || _loadingPdf || _resultUnconfirmed
                          ? null
                          : _pdf == null
                          ? _preparePdf
                          : _openPdfAndConfirm,
                      child: Text(
                        _busy
                            ? '処理しています'
                            : _loadingPdf
                            ? 'PDFを準備しています'
                            : _resultUnconfirmed
                            ? '記録結果を確認してください'
                            : _pdf == null
                            ? 'PDFを再取得'
                            : '${_containers.length}枚を表示して印刷',
                      ),
                    ),
                    if (_resultUnconfirmed) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        key: const Key('retry-sorting-batch-result'),
                        onPressed: _busy ? null : _recordPrinted,
                        child: const Text('記録結果を再確認'),
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

  Future<void> _preparePdf() async {
    if (_loadingPdf) return;
    setState(() {
      _loadingPdf = true;
      _error = null;
    });
    try {
      final pdf = await widget.repository.fetchSortingBatchPdf(
        sortingResultId: widget.result.sortingResultId,
        expectedPageCount: _containers.length,
      );
      if (mounted) setState(() => _pdf = pdf);
    } on LabelFailure catch (failure) {
      if (mounted) setState(() => _error = _message(failure));
    } catch (_) {
      if (mounted) {
        setState(() => _error = '一括ラベルPDFを取得できませんでした。再試行してください。');
      }
    } finally {
      if (mounted) setState(() => _loadingPdf = false);
    }
  }

  Future<void> _openPdfAndConfirm() async {
    final pdf = _pdf;
    if (pdf == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final opened = await (widget.pdfOpener ?? openLabelPdf)(
        pdf.bytes,
        '${widget.result.displayId}-labels.pdf',
      );
      if (!mounted) return;
      if (!opened) {
        setState(() => _error = 'PDFを開けませんでした。ポップアップの許可を確認してください。');
        return;
      }
      final printed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('印刷結果を確認'),
          content: Text(
            '${_containers.length}枚すべてを印刷できましたか。'
            '\n中断や失敗の場合は記録せず、PDFから印刷をやり直してください。',
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('印刷できなかった'),
            ),
            FilledButton(
              key: const Key('confirm-sorting-batch-printed'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('すべて印刷完了'),
            ),
          ],
        ),
      );
      if (printed == true && mounted) await _recordPrinted();
    } on LabelFailure catch (failure) {
      if (mounted) setState(() => _error = _message(failure));
    } catch (_) {
      if (mounted) {
        setState(() => _error = '一括ラベルPDFを表示できませんでした。再試行してください。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recordPrinted() async {
    _idempotencyKey ??= createLabelIdempotencyKey();
    setState(() {
      _busy = true;
      _error = null;
      _resultUnconfirmed = true;
    });
    try {
      final result = await widget.repository.markSortingBatchPrinted(
        sortingResultId: widget.result.sortingResultId,
        workerId: widget.workerId,
        idempotencyKey: _idempotencyKey!,
      );
      if (!mounted) return;
      if (result.completedCount != _containers.length) {
        setState(() => _error = '完了件数を確認できませんでした。管理者へ連絡してください。');
        return;
      }
      _resultUnconfirmed = false;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('一括印刷を記録しました'),
          content: Text('${result.completedCount}枚すべてを印刷済みにしました。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('選果対象へ戻る'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on LabelFailure catch (failure) {
      if (!mounted) return;
      if (!failure.retryable) {
        _resultUnconfirmed = false;
        _idempotencyKey = null;
      }
      setState(() => _error = _message(failure));
    } catch (_) {
      if (mounted) {
        setState(() => _error = '記録結果を確認できませんでした。同じ操作の結果を再確認してください。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(LabelFailure failure) {
    final id = failure.correlationId;
    return id == null || id.isEmpty
        ? failure.message
        : '${failure.message}\n問い合わせ番号: $id';
  }
}

class _MonochromeSortingLabel extends StatelessWidget {
  const _MonochromeSortingLabel({
    required this.page,
    required this.pageCount,
    required this.gradeCode,
    required this.varietyName,
    required this.weightHundredths,
    required this.containerDisplayId,
    required this.originName,
    required this.sortedOn,
    required this.workerName,
  });

  final int page;
  final int pageCount;
  final String gradeCode;
  final String varietyName;
  final int weightHundredths;
  final String containerDisplayId;
  final String originName;
  final DateTime sortedOn;
  final String workerName;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 148 / 210,
      child: Container(
        key: const Key('sorting-label-preview'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black, width: 2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.black, height: 1.2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('選果サイズ', style: TextStyle(fontSize: 13)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            gradeCode,
                            style: const TextStyle(
                              fontSize: 54,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$page / $pageCount',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            varietyName,
                            style: const TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.black, thickness: 2, height: 18),
              const Text('正味重量', style: TextStyle(fontSize: 13)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${formatLabelWeight(weightHundredths)} kg',
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Divider(color: Colors.black, thickness: 2, height: 18),
              const Text('コンテナID', style: TextStyle(fontSize: 13)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  containerDisplayId,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const Divider(color: Colors.black, height: 18),
              _PreviewField(label: '産地・区画', value: originName),
              const Divider(color: Colors.black, height: 12),
              _PreviewField(label: '選果日', value: _date(sortedOn)),
              const Divider(color: Colors.black, height: 12),
              _PreviewField(label: '担当者', value: workerName),
              const Spacer(),
              const Text('おおくま農園', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  static String _date(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';
}

class _PreviewField extends StatelessWidget {
  const _PreviewField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
