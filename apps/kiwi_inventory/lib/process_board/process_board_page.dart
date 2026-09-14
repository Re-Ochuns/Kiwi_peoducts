import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/common_state_view.dart';
import '../ripening/ripening_plan_page.dart';
import '../ripening/ripening_plan_repository.dart';
import '../ripening_work/ripening_work_page.dart';
import '../ripening_work/ripening_work_repository.dart';
import '../shipping/shipping_page.dart';
import '../shipping/shipping_repository.dart';
import 'process_board_repository.dart';

class ProcessBoardPage extends StatefulWidget {
  const ProcessBoardPage({
    required this.repository,
    this.inventoryOnly = false,
    this.ripeningPlanRepository,
    this.ripeningWorkRepository,
    this.shippingRepository,
    this.currentDate,
    this.onBusyChanged,
    super.key,
  });

  final ProcessBoardRepository repository;
  final bool inventoryOnly;
  final RipeningPlanRepository? ripeningPlanRepository;
  final RipeningWorkRepository? ripeningWorkRepository;
  final ShippingRepository? shippingRepository;
  final DateTime? currentDate;
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<ProcessBoardPage> createState() => _ProcessBoardPageState();
}

enum _PanelMode { details, ripeningPlan, ripeningWork, shipping }

class _ProcessBoardPageState extends State<ProcessBoardPage> {
  final _boardScrollController = ScrollController();
  ProcessBoardData? _data;
  ProcessBoardFailure? _failure;
  String? _selectedId;
  String? _shippingOrderId;
  String? _selectedPlanId;
  _PanelMode _panelMode = _PanelMode.details;
  bool _loading = true;
  bool _panelBusy = false;

  void _setPanelBusy(bool value) {
    if (!mounted) return;
    setState(() => _panelBusy = value);
    widget.onBusyChanged?.call(value);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _boardScrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_panelBusy) return;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final data = await widget.repository.load();
      if (!mounted) return;
      if (_panelBusy) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        final previous = _selected;
        _data = data;
        _loading = false;
        final selected = _selected;
        final previousOrderId = _shippingOrderId;
        if (selected == null) {
          _selectedId = null;
          _selectedPlanId = null;
          _shippingOrderId = null;
          _panelMode = _PanelMode.details;
        } else {
          _selectedPlanId = selected.ripeningLotId;
          if (!selected.orderIds.contains(_shippingOrderId)) {
            _shippingOrderId = selected.orderIds.firstOrNull;
          }
          final invalidPanel = switch (_panelMode) {
            _PanelMode.details => false,
            _PanelMode.ripeningPlan =>
              selected.stage != ProcessStage.sorted ||
                  selected.ripeningLotId != null,
            _PanelMode.ripeningWork =>
              selected.nextTask == null ||
                  selected.nextTask?.id != previous?.nextTask?.id ||
                  selected.nextTask?.targetId != previous?.nextTask?.targetId ||
                  selected.stage != previous?.stage,
            _PanelMode.shipping =>
              selected.stage != ProcessStage.shippable ||
                  !selected.orderIds.contains(previousOrderId),
          };
          if (selected.needsReview || invalidPanel) {
            _panelMode = _PanelMode.details;
          }
        }
      });
    } on ProcessBoardFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _loading = false;
      });
    }
  }

  ProcessBoardData? get _visibleData {
    final data = _data;
    if (data == null || !widget.inventoryOnly) return data;
    return ProcessBoardData(
      items:
          data.inventoryItems ??
          data.items
              .where(
                (item) =>
                    item.useType == ProcessUseType.reserve ||
                    item.useType == ProcessUseType.unassigned,
              )
              .toList(growable: false),
    );
  }

  @override
  void didUpdateWidget(covariant ProcessBoardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inventoryOnly != widget.inventoryOnly && _selected == null) {
      _selectedId = null;
      _selectedPlanId = null;
      _shippingOrderId = null;
      _panelMode = _PanelMode.details;
    }
  }

  ProcessBoardItem? get _selected {
    final data = _visibleData;
    if (data == null || _selectedId == null) return null;
    return data.items
        .where((item) => item.id == _selectedId)
        .firstOrNull
        ?.forPlan(_selectedPlanId);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_panelBusy,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        if (viewportWidth < 900 && _panelMode == _PanelMode.details) {
          return const CommonStateView.empty(
            title: '工程ボードはPCで使用してください',
            message: '画面幅900px以上で、4工程を横並びに表示します。',
          );
        }
        if (_loading && _data == null) {
          return CommonStateView.loading(title: '工程ボードを読み込んでいます');
        }
        if (_failure != null && _data == null) {
          return CommonStateView.error(
            title: '工程ボードを表示できません',
            message: _failure!.message,
            actionLabel: _failure!.retryable ? '再試行' : null,
            onAction: _failure!.retryable ? _load : null,
          );
        }
        final data = _visibleData!;
        return Material(
          color: AppColors.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BoardHeader(
                refreshing: _loading,
                onRefresh: _panelBusy ? null : _load,
              ),
              if (_failure != null)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _BoardNotice(
                          message:
                              '更新に失敗しました。表示中の情報は前回取得した内容です。\n${_failure!.message}',
                        ),
                        if (_failure!.retryable)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: _loading || _panelBusy ? null : _load,
                              child: const Text('再試行'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _buildBoard(data)),
                    if (_selected != null)
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        width: constraints.maxWidth < 1100 ? 420 : 460,
                        child: _DetailPanel(
                          item: _selected!,
                          busy: _panelBusy,
                          onBusyChanged: _setPanelBusy,
                          mode: _panelMode,
                          shippingOrderId: _shippingOrderId,
                          ripeningPlanRepository: widget.ripeningPlanRepository,
                          ripeningWorkRepository: widget.ripeningWorkRepository,
                          shippingRepository: widget.shippingRepository,
                          currentDate: widget.currentDate,
                          onClose: _closePanel,
                          onBack: () =>
                              setState(() => _panelMode = _PanelMode.details),
                          onOpen: (mode) => setState(() => _panelMode = mode),
                          onShippingOrderChanged: (value) =>
                              setState(() => _shippingOrderId = value),
                          onPlanChanged: (value) => setState(() {
                            _selectedPlanId = value;
                            _panelMode = _PanelMode.details;
                          }),
                          onCompleted: _completeAndReload,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _buildBoard(ProcessBoardData data) => Scrollbar(
    controller: _boardScrollController,
    thumbVisibility: true,
    child: SingleChildScrollView(
      controller: _boardScrollController,
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(16, 20, _selected == null ? 16 : 480, 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final stage in ProcessStage.values) ...[
            SizedBox(
              width: 264,
              child: _BoardColumn(
                stage: stage,
                items: data.itemsFor(stage),
                totalWeightHundredths: data.weightFor(stage),
                selectedId: _selectedId,
                onSelected: _select,
              ),
            ),
            if (stage != ProcessStage.values.last) const SizedBox(width: 12),
          ],
        ],
      ),
    ),
  );

  void _select(ProcessBoardItem item) {
    if (_panelBusy) return;
    setState(() {
      _selectedId = item.id;
      _selectedPlanId = item.plans.firstOrNull?.id;
      _shippingOrderId = item.orderIds.firstOrNull;
      _panelMode = _PanelMode.details;
    });
  }

  void _closePanel() => setState(() {
    _selectedId = null;
    _selectedPlanId = null;
    _shippingOrderId = null;
    _panelMode = _PanelMode.details;
  });

  Future<void> _completeAndReload() async {
    if (!mounted) return;
    setState(() => _panelMode = _PanelMode.details);
    await _load();
  }
}

class _BoardHeader extends StatelessWidget {
  const _BoardHeader({required this.refreshing, required this.onRefresh});

  final bool refreshing;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '工程ボード',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton(
                onPressed: refreshing ? null : onRefresh,
                child: Text(refreshing ? '更新中' : '最新状態を読み込む'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _LegendItem(useType: ProcessUseType.reserve),
              _LegendItem(useType: ProcessUseType.order),
              _LegendItem(useType: ProcessUseType.mixed),
            ],
          ),
        ],
      ),
    ),
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.useType});

  final ProcessUseType useType;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _UseMark(useType: useType, color: AppColors.mutedText),
      const SizedBox(width: 5),
      Text(
        useType.label,
        style: const TextStyle(fontSize: 13, color: AppColors.mutedText),
      ),
    ],
  );
}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    required this.stage,
    required this.items,
    required this.totalWeightHundredths,
    required this.selectedId,
    required this.onSelected,
  });

  final ProcessStage stage;
  final List<ProcessBoardItem> items;
  final int totalWeightHundredths;
  final String? selectedId;
  final ValueChanged<ProcessBoardItem> onSelected;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FA),
        border: Border(top: BorderSide(color: _stageColor(stage), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _stageColor(stage),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    stage.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAECEF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      items.any((item) => item.inventoryBalance?.isLot == true)
                          ? '${items.length}件（ロット・コンテナ）'
                          : '${items.length}コンテナ',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatProcessBoardWeight(totalWeightHundredths),
                    style: const TextStyle(
                      color: AppColors.mutedText,
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '該当するコンテナはありません',
                      style: TextStyle(
                        color: AppColors.mutedText,
                        fontSize: 13,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _BoardItem(
                        item: item,
                        selected: item.id == selectedId,
                        onTap: () => onSelected(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

class _BoardItem extends StatelessWidget {
  const _BoardItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ProcessBoardItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${item.stage.label}、${item.useType.label}、${item.displayId}の詳細を見る',
    button: true,
    selected: selected,
    container: true,
    explicitChildNodes: true,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? const Color(0xFF0969DA) : AppColors.line,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x260969DA),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _ProcessIcon(item: item),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.displayId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0969DA),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FA),
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item.grade,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(item.variety, style: const TextStyle(fontSize: 14)),
            if (item.inventoryBalance != null)
              Text(
                item.inventoryBalance!.isLot ? '在庫残量（ロット合計）' : '用途未確定の残量',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedText,
                ),
              ),
            const SizedBox(height: 7),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 6,
              runSpacing: 4,
              children: [
                Text(
                  formatProcessBoardWeight(item.weightHundredths),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      item.stage.dateLabel,
                      style: TextStyle(
                        color: item.needsReview
                            ? AppColors.error
                            : AppColors.mutedText,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      _formatBoardDate(item.date),
                      style: TextStyle(
                        color: item.needsReview
                            ? AppColors.error
                            : AppColors.mutedText,
                        fontSize: 12,
                        fontWeight: item.needsReview
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProcessIcon extends StatelessWidget {
  const _ProcessIcon({required this.item});

  final ProcessBoardItem item;

  @override
  Widget build(BuildContext context) => Semantics(
    key: Key('process-icon-${item.id}'),
    label: '${item.stage.label}・${item.useType.label}・${item.displayId}',
    image: true,
    child: ExcludeSemantics(
      child: _UseMark(useType: item.useType, color: _stageColor(item.stage)),
    ),
  );
}

class _UseMark extends StatelessWidget {
  const _UseMark({required this.useType, required this.color});

  final ProcessUseType useType;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (useType == ProcessUseType.unassigned ||
        useType == ProcessUseType.order) {
      return SizedBox(
        width: 14,
        height: 14,
        child: Center(
          child: Container(
            width: useType == ProcessUseType.order ? 7 : 11,
            height: useType == ProcessUseType.order ? 7 : 11,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ),
      );
    }

    return SizedBox(
      width: 14,
      height: 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.5),
            ),
          ),
          if (useType == ProcessUseType.mixed)
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
        ],
      ),
    );
  }
}

Color _stageColor(ProcessStage stage) => switch (stage) {
  ProcessStage.sorted => const Color(0xFF57606A),
  ProcessStage.ripening => const Color(0xFFBF8700),
  ProcessStage.resting => const Color(0xFF8250DF),
  ProcessStage.shippable => const Color(0xFF1A7F37),
};

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.item,
    required this.mode,
    required this.shippingOrderId,
    required this.ripeningPlanRepository,
    required this.ripeningWorkRepository,
    required this.shippingRepository,
    required this.currentDate,
    required this.onClose,
    required this.onBack,
    required this.onOpen,
    required this.onShippingOrderChanged,
    required this.onPlanChanged,
    required this.onCompleted,
    required this.busy,
    required this.onBusyChanged,
  });

  final bool busy;
  final ValueChanged<bool> onBusyChanged;
  final ProcessBoardItem item;
  final _PanelMode mode;
  final String? shippingOrderId;
  final RipeningPlanRepository? ripeningPlanRepository;
  final RipeningWorkRepository? ripeningWorkRepository;
  final ShippingRepository? shippingRepository;
  final DateTime? currentDate;
  final VoidCallback onClose;
  final VoidCallback onBack;
  final ValueChanged<_PanelMode> onOpen;
  final ValueChanged<String?> onShippingOrderChanged;
  final ValueChanged<String?> onPlanChanged;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (mode != _PanelMode.details)
                  TextButton(
                    onPressed: busy ? null : onBack,
                    child: const Text('← 詳細へ戻る'),
                  )
                else
                  Expanded(
                    child: Text(
                      item.inventoryBalance?.isLot == true
                          ? 'ロット在庫詳細'
                          : 'コンテナ詳細',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (mode != _PanelMode.details) const Spacer(),
                TextButton(
                  onPressed: busy ? null : onClose,
                  child: const Text('閉じる'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildContent()),
        ],
      ),
    ),
  );

  Widget _buildContent() => switch (mode) {
    _PanelMode.details => _Details(
      item: item,
      shippingOrderId: shippingOrderId,
      canCreatePlan: ripeningPlanRepository != null,
      canCompleteWork: ripeningWorkRepository != null,
      canShip: shippingRepository != null,
      onOpen: onOpen,
      onShippingOrderChanged: onShippingOrderChanged,
      onPlanChanged: onPlanChanged,
    ),
    _PanelMode.ripeningPlan => RipeningPlanPage(
      key: ValueKey('board-plan-${item.id}'),
      repository: ripeningPlanRepository!,
      currentDate: currentDate,
      embedded: true,
      initialInventoryId: item.id,
      onCompleted: onCompleted,
      onBusyChanged: onBusyChanged,
    ),
    _PanelMode.ripeningWork => RipeningWorkPage(
      key: ValueKey('board-work-${item.id}-${item.nextTask!.type.name}'),
      repository: ripeningWorkRepository!,
      task: item.nextTask!,
      currentDate: currentDate,
      embedded: true,
      onCompleted: onCompleted,
      onBusyChanged: onBusyChanged,
    ),
    _PanelMode.shipping => ShippingPage(
      key: ValueKey('board-shipping-$shippingOrderId'),
      repository: shippingRepository!,
      initialOrderId: shippingOrderId,
      currentDate: currentDate,
      embedded: true,
      onChanged: onCompleted,
      onBusyChanged: onBusyChanged,
    ),
  };
}

class _Details extends StatelessWidget {
  const _Details({
    required this.item,
    required this.shippingOrderId,
    required this.canCreatePlan,
    required this.canCompleteWork,
    required this.canShip,
    required this.onOpen,
    required this.onShippingOrderChanged,
    required this.onPlanChanged,
  });

  final ProcessBoardItem item;
  final String? shippingOrderId;
  final bool canCreatePlan;
  final bool canCompleteWork;
  final bool canShip;
  final ValueChanged<_PanelMode> onOpen;
  final ValueChanged<String?> onShippingOrderChanged;
  final ValueChanged<String?> onPlanChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailRow(
          label: item.inventoryBalance?.isLot == true ? 'ロットID' : 'コンテナID',
          value: item.displayId,
          prominent: true,
        ),
        if (item.plans.length > 1) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'process-board-plan-${item.id}-${item.ripeningLotId}',
            ),
            initialValue: item.ripeningLotId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '操作する追熟計画'),
            items: [
              for (final plan in item.plans)
                DropdownMenuItem(
                  value: plan.id,
                  child: Text('${plan.displayId}・${plan.useType.label}'),
                ),
            ],
            onChanged: onPlanChanged,
          ),
        ],
        const SizedBox(height: 18),
        _ProcessProgress(current: item.stage),
        const SizedBox(height: 8),
        _DetailRow(label: '用途', value: item.useType.label),
        _DetailRow(label: '品種・等級', value: item.productLabel),
        _DetailRow(
          label: item.inventoryBalance != null ? '在庫残量' : '現在重量',
          value: formatProcessBoardWeight(item.weightHundredths),
          prominent: true,
        ),
        if (item.inventoryBalance case final balance?) ...[
          _DetailRow(
            label: balance.isLot ? 'ロット総重量' : '未引当重量',
            value: formatProcessBoardWeight(balance.totalHundredths),
          ),
          _DetailRow(
            label: '受注向け残量',
            value: formatProcessBoardWeight(balance.orderHundredths),
          ),
          _DetailRow(
            label: '対象コンテナ',
            value: balance.containerDisplayIds.join('、'),
          ),
          if (balance.isLot)
            const Text('ロット総重量から未出荷の受注割当量を差し引いた残量です。コンテナ別の按分は行いません。'),
        ],
        _DetailRow(
          label: item.stage.dateLabel,
          value: _formatBoardDate(item.date),
        ),
        _DetailRow(label: '場所', value: item.location),
        if (item.ripeningDisplayId != null)
          _DetailRow(label: '追熟計画', value: item.ripeningDisplayId!),
        if (item.orderNumbers.isNotEmpty)
          _DetailRow(label: '割当受注', value: item.orderNumbers.join('、')),
        if (item.needsReview) ...[
          const SizedBox(height: 16),
          const _BoardNotice(message: '期限または計画の再確認が必要です。最新状態を確認してください。'),
        ],
        const SizedBox(height: 24),
        const Text(
          '次の工程',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ..._action(),
      ],
    ),
  );

  List<Widget> _action() {
    if (item.inventoryBalance != null) {
      return const [Text('工程操作は「一覧」タブから行ってください。')];
    }
    if (item.needsReview) {
      return const [Text('要確認を解消すると工程操作を開始できます。')];
    }
    if (item.stage == ProcessStage.sorted && item.ripeningLotId == null) {
      return [
        if (canCreatePlan)
          FilledButton(
            onPressed: () => onOpen(_PanelMode.ripeningPlan),
            child: const Text('追熟計画を入力'),
          )
        else
          const Text('追熟計画機能を利用できません。'),
      ];
    }
    if (item.nextTask != null) {
      return [
        if (canCompleteWork)
          FilledButton(
            onPressed: () => onOpen(_PanelMode.ripeningWork),
            child: Text('${item.nextTask!.type.label}を入力'),
          )
        else
          const Text('追熟作業機能を利用できません。'),
      ];
    }
    if (item.stage == ProcessStage.shippable) {
      if (item.orderIds.isEmpty) {
        return const [Text('出荷可能な割当受注はありません。')];
      }
      return [
        if (item.orderIds.length > 1) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('process-board-order-${item.id}-$shippingOrderId'),
            initialValue: shippingOrderId,
            isExpanded: true,
            icon: const ExcludeSemantics(child: Text('▼')),
            decoration: const InputDecoration(labelText: '出荷する受注'),
            items: [
              for (var index = 0; index < item.orderIds.length; index++)
                DropdownMenuItem(
                  value: item.orderIds[index],
                  child: Text(item.orderNumbers[index]),
                ),
            ],
            onChanged: onShippingOrderChanged,
          ),
          const SizedBox(height: 12),
        ],
        if (canShip)
          FilledButton(
            onPressed: shippingOrderId == null
                ? null
                : () => onOpen(_PanelMode.shipping),
            child: const Text('出荷内容を入力'),
          )
        else
          const Text('出荷機能を利用できません。'),
      ];
    }
    return const [Text('現在実行できる工程操作はありません。')];
  }
}

class _ProcessProgress extends StatelessWidget {
  const _ProcessProgress({required this.current});

  final ProcessStage current;

  @override
  Widget build(BuildContext context) {
    final currentIndex = ProcessStage.values.indexOf(current);
    return Semantics(
      label: '現在の工程 ${current.label}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '工程',
              style: TextStyle(fontSize: 13, color: AppColors.mutedText),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                for (var index = 0; index < ProcessStage.values.length; index++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: index == ProcessStage.values.length - 1 ? 0 : 4,
                      ),
                      child: _ProgressStep(
                        stage: ProcessStage.values[index],
                        completed: index < currentIndex,
                        current: index == currentIndex,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.stage,
    required this.completed,
    required this.current,
  });

  final ProcessStage stage;
  final bool completed;
  final bool current;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        height: 5,
        decoration: BoxDecoration(
          color: completed || current
              ? _stageColor(stage)
              : const Color(0xFFD8DEE4),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(height: 5),
      Text(
        stage.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: current ? _stageColor(stage) : AppColors.mutedText,
          fontWeight: current ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    ],
  );
}

class _BoardNotice extends StatelessWidget {
  const _BoardNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: const BoxDecoration(
      border: Border(
        top: BorderSide(color: AppColors.error),
        bottom: BorderSide(color: AppColors.error),
      ),
    ),
    child: Text(
      message,
      style: const TextStyle(
        color: AppColors.error,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.prominent = false,
  });

  final String label;
  final String value;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
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
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: prominent ? 20 : 16,
            fontWeight: prominent ? FontWeight.w700 : FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

String _formatBoardDate(DateTime? value) {
  if (value == null) return '未設定';
  final time = value.hour == 0 && value.minute == 0
      ? ''
      : ' ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  return '${value.month}/${value.day}$time';
}
