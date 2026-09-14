import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/app_theme.dart';
import '../receiving/receiving_repository.dart';
import 'label_pdf_opener.dart';
import 'label_repository.dart';

class ReceivingLabelPreviewPage extends StatefulWidget {
  const ReceivingLabelPreviewPage({
    required this.repository,
    required this.result,
    required this.input,
    required this.varietyName,
    required this.sortingUrl,
    this.pdfOpener,
    super.key,
  });

  final LabelRepository repository;
  final ReceivingResult result;
  final ReceivingInput input;
  final String varietyName;
  final String sortingUrl;
  final LabelPdfOpener? pdfOpener;

  @override
  State<ReceivingLabelPreviewPage> createState() =>
      _ReceivingLabelPreviewPageState();
}

class _ReceivingLabelPreviewPageState extends State<ReceivingLabelPreviewPage> {
  LabelPdf? _pdf;
  String? _error;
  bool _loading = false;
  bool _opening = false;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _preparePdf();
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = widget.input.containerCount;
    return PopScope<bool>(
      canPop: !_opening,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          title: TextButton(
            onPressed: _opening ? null : () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: EdgeInsets.zero,
              foregroundColor: AppColors.ink,
            ),
            child: const Text('← ToDoへ戻る'),
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
                      '仮ラベル確認',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.result.displayId}の仮ラベル$pageCount枚を確認します。',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('previous-receiving-label'),
                            onPressed: _pageIndex == 0 || _opening
                                ? null
                                : () => setState(() => _pageIndex--),
                            child: const Text('← 前のラベル'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_pageIndex + 1} / $pageCount',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('next-receiving-label'),
                            onPressed: _pageIndex == pageCount - 1 || _opening
                                ? null
                                : () => setState(() => _pageIndex++),
                            child: const Text('次のラベル →'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _MonochromeReceivingLabel(
                      page: _pageIndex + 1,
                      pageCount: pageCount,
                      displayId: widget.result.displayId,
                      receivedDate: widget.result.receivedDate,
                      originName: widget.input.originName,
                      varietyName: widget.varietyName,
                      totalWeightKg: widget.input.totalWeightKg,
                      sortingUrl: widget.sortingUrl,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '白黒で印刷されます。品種・産地・受入ロットID・コンテナ番号を確認してください。',
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
                      key: const Key('open-receiving-label-pdf'),
                      onPressed: _loading || _opening
                          ? null
                          : _pdf == null
                          ? _preparePdf
                          : _openPdf,
                      child: Text(
                        _opening
                            ? 'PDFを表示しています'
                            : _loading
                            ? 'PDFを準備しています'
                            : _pdf == null
                            ? 'PDFを再取得'
                            : '$pageCount枚を表示して印刷',
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      key: const Key('edit-receiving-after-preview'),
                      onPressed: _opening
                          ? null
                          : () => Navigator.pop(context, true),
                      child: const Text('登録内容を修正'),
                    ),
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
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pdf = await widget.repository.fetchReceivingBatchPdf(
        receivingLotId: widget.result.receivingLotId,
        expectedPageCount: widget.input.containerCount,
      );
      if (mounted) setState(() => _pdf = pdf);
    } on LabelFailure catch (failure) {
      if (mounted) setState(() => _error = _failureMessage(failure));
    } catch (_) {
      if (mounted) {
        setState(() => _error = '仮ラベルPDFを取得できませんでした。再試行してください。');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPdf() async {
    final pdf = _pdf;
    if (pdf == null) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final opened = await (widget.pdfOpener ?? openLabelPdf)(
        pdf.bytes,
        '${widget.result.displayId}-receiving-labels.pdf',
      );
      if (mounted && !opened) {
        setState(() => _error = 'PDFを開けませんでした。ポップアップの許可を確認してください。');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '仮ラベルPDFを表示できませんでした。再試行してください。');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  String _failureMessage(LabelFailure failure) => failure.correlationId == null
      ? failure.message
      : '${failure.message}\n問い合わせID: ${failure.correlationId}';
}

class _MonochromeReceivingLabel extends StatelessWidget {
  const _MonochromeReceivingLabel({
    required this.page,
    required this.pageCount,
    required this.displayId,
    required this.receivedDate,
    required this.originName,
    required this.varietyName,
    required this.totalWeightKg,
    required this.sortingUrl,
  });

  final int page;
  final int pageCount;
  final String displayId;
  final String receivedDate;
  final String originName;
  final String varietyName;
  final double totalWeightKg;
  final String sortingUrl;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 148 / 210,
      child: Container(
        key: const Key('receiving-label-preview'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.black, height: 1.15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('収穫・受入 仮ラベル'),
                  Text('$page / $pageCount'),
                ],
              ),
              const SizedBox(height: 12),
              const Text('品種', style: TextStyle(fontSize: 11)),
              Text(
                varietyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text('産地・圃場・区画', style: TextStyle(fontSize: 11)),
              Text(
                originName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Divider(color: Colors.black, thickness: 2),
              const Text('受入ロットID', style: TextStyle(fontSize: 11)),
              Text(
                displayId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text('収穫・受入日　$receivedDate'),
              Text('合計重量　　　${totalWeightKg.toStringAsFixed(2)} kg'),
              const Divider(color: Colors.black),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'コンテナ番号',
                                style: TextStyle(fontSize: 11),
                              ),
                              Text(
                                '$page / $pageCount',
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const Text(
                            '読めない場合は\n受入ロットIDで探す',
                            style: TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 112,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          QrImageView(
                            key: const Key('receiving-sorting-qr'),
                            data: sortingUrl,
                            semanticsLabel: '$displayIdの選果入力を開くQRコード',
                            version: QrVersions.auto,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Colors.black,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Colors.black,
                            ),
                          ),
                          const Text('選果時に読み取る'),
                        ],
                      ),
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
}
