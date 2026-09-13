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
    this.ripeningPlanRepository,
    this.ripeningWorkRepository,
    this.shippingRepository,
    this.currentDate,
    this.onBusyChanged,
    super.key,
  });

  final ProcessBoardRepository repository;
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

  ProcessBoardItem? get _selected {
    final data = _data;
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
        final data = _data!;
        return Material(
          color: AppColors.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BoardHeader(
                refreshing: _loading,
                onRefresh: _panelBusy ? null : _load,
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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '工程ボード',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _LegendItem(useType: ProcessUseType.reserve),
              _LegendItem(useType: ProcessUseType.order),
              _LegendItem(useType: ProcessUseType.mixed),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: refreshing ? null : onRefresh,
              child: Text(refreshing ? '更新中' : '最新状態を読み込む'),
            ),
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
  Widget build(BuildContext context) => Text(
    '${useType.symbol} ${useType.label}',
    style: const TextStyle(fontSize: 14, color: AppColors.mutedText),
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stage.label,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${items.length}件　${formatProcessBoardWeight(totalWeightHundredths)}',
              style: const TextStyle(color: AppColors.mutedText),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: items.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '該当するコンテナはありません',
                  style: TextStyle(color: AppColors.mutedText),
                ),
              )
            : ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2ED) : Colors.white,
          border: Border.all(
            color: selected ? AppColors.green : AppColors.line,
          ),
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
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(item.grade, style: const TextStyle(fontSize: 16)),
              ],
            ),
            const SizedBox(height: 9),
            Text(item.variety, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 3),
            Text(
              formatProcessBoardWeight(item.weightHundredths),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '${item.stage.dateLabel} ${_formatBoardDate(item.date)}',
              style: TextStyle(
                color: item.needsReview ? AppColors.error : AppColors.mutedText,
                fontSize: 14,
                fontWeight: item.needsReview
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 3),
            Text(item.useType.label, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerRight,
              child: Text('詳細を見る →'),
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

  Color get _color => switch (item.stage) {
    ProcessStage.sorted => const Color(0xFF616965),
    ProcessStage.ripening => const Color(0xFF9A5B00),
    ProcessStage.resting => const Color(0xFF6B4C8A),
    ProcessStage.shippable => AppColors.green,
  };

  @override
  Widget build(BuildContext context) => Semantics(
    key: Key('process-icon-${item.id}'),
    label: '${item.stage.label}・${item.useType.label}・${item.displayId}',
    image: true,
    child: ExcludeSemantics(
      child: SizedBox(
        width: 18,
        height: 18,
        child: item.useType == ProcessUseType.unassigned
            ? Center(
                child: ColoredBox(
                  color: _color,
                  child: const SizedBox(width: 12, height: 12),
                ),
              )
            : Text(
                item.useType.symbol,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _color,
                  fontSize: 18,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    ),
  );
}

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
                  const Expanded(
                    child: Text(
                      'コンテナ詳細',
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
        _DetailRow(label: 'コンテナID', value: item.displayId, prominent: true),
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
        _DetailRow(label: '工程', value: item.stage.label),
        _DetailRow(label: '用途', value: item.useType.label),
        _DetailRow(label: '品種・等級', value: item.productLabel),
        _DetailRow(
          label: '現在重量',
          value: formatProcessBoardWeight(item.weightHundredths),
          prominent: true,
        ),
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
  return '${value.year}年${value.month}月${value.day}日$time';
}
