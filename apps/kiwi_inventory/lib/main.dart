import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth/auth_controller.dart';
import 'auth/auth_gate.dart';
import 'auth/auth_repository.dart';
import 'auth/supabase_auth_repository.dart';
import 'core/app_breakpoints.dart';
import 'core/app_config.dart';
import 'core/app_theme.dart';
import 'core/common_state_view.dart';
import 'csv_export/csv_export_repository.dart';
import 'csv_export/supabase_csv_export_repository.dart';
import 'inventory/inventory_page.dart';
import 'inventory/inventory_repository.dart';
import 'inventory/supabase_inventory_repository.dart';
import 'label/label_page.dart';
import 'label/label_repository.dart';
import 'label/supabase_label_repository.dart';
import 'master/master_page.dart';
import 'master/master_repository.dart';
import 'master/supabase_master_repository.dart';
import 'manager_dashboard/manager_dashboard_page.dart';
import 'manager_dashboard/manager_dashboard_repository.dart';
import 'orders/order_management_page.dart';
import 'orders/order_management_repository.dart';
import 'orders/supabase_order_management_repository.dart';
import 'receiving/receiving_page.dart';
import 'receiving/receiving_repository.dart';
import 'receiving/supabase_receiving_repository.dart';
import 'ripening/ripening_plan_page.dart';
import 'ripening/ripening_plan_repository.dart';
import 'ripening/supabase_ripening_plan_repository.dart';
import 'sorting/sorting_page.dart';
import 'sorting/sorting_repository.dart';
import 'sorting/supabase_sorting_repository.dart';
import 'work_tasks/supabase_work_task_repository.dart';
import 'work_tasks/work_task_repository.dart';
import 'work_tasks/worker_todo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final configurationError = config.validate();

  if (configurationError != null) {
    runApp(KiwiInventoryApp(startupError: configurationError));
    return;
  }

  try {
    final repository = await SupabaseAuthRepository.initialize(config);
    runApp(
      KiwiInventoryApp(
        authRepository: repository,
        csvExportRepository:
            SupabaseCsvExportRepository.fromInitializedClient(),
        masterRepository: SupabaseMasterRepository.fromInitializedClient(),
        orderManagementRepository:
            SupabaseOrderManagementRepository.fromInitializedClient(),
        inventoryRepository:
            SupabaseInventoryRepository.fromInitializedClient(),
        labelRepository: SupabaseLabelRepository.fromInitializedClient(config),
        sortingRepository: SupabaseSortingRepository.fromInitializedClient(),
        receivingRepository:
            SupabaseReceivingRepository.fromInitializedClient(),
        ripeningPlanRepository:
            SupabaseRipeningPlanRepository.fromInitializedClient(),
        workTaskRepository: SupabaseWorkTaskRepository.fromInitializedClient(),
      ),
    );
  } catch (_) {
    runApp(
      const KiwiInventoryApp(
        startupError: '認証サービスへ接続できませんでした。接続設定と通信状況を確認してください。',
      ),
    );
  }
}

class KiwiInventoryApp extends StatelessWidget {
  const KiwiInventoryApp({
    this.authRepository,
    this.startupError,
    this.currentDate,
    this.csvExportRepository,
    this.masterRepository,
    this.labelRepository,
    this.sortingRepository,
    this.receivingRepository,
    this.inventoryRepository,
    this.ripeningPlanRepository,
    this.workTaskRepository,
    this.orderManagementRepository,
    this.theme,
    super.key,
  });

  final AuthRepository? authRepository;
  final String? startupError;
  final DateTime? currentDate;
  final CsvExportRepository? csvExportRepository;
  final MasterRepository? masterRepository;
  final LabelRepository? labelRepository;
  final ReceivingRepository? receivingRepository;
  final InventoryRepository? inventoryRepository;
  final RipeningPlanRepository? ripeningPlanRepository;
  final WorkTaskRepository? workTaskRepository;
  final OrderManagementRepository? orderManagementRepository;
  final SortingRepository? sortingRepository;
  final ThemeData? theme;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'キウイ在庫管理',
      debugShowCheckedModeBanner: false,
      theme: theme ?? buildAppTheme(),
      home: _buildHome(),
      initialRoute: workTaskInitialRoute(Uri.base),
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final taskId = workTaskIdFromRoute(settings.name);
    final repository = workTaskRepository;
    if (taskId == null || repository == null) return null;
    return PageRouteBuilder<void>(
      settings: settings,
      pageBuilder: (context, _, _) => _authenticated(
        (_, _) => WorkTaskRoutePage(
          repository: repository,
          taskId: taskId,
          currentDate: currentDate,
          targetPageBuilder: (task) => _buildWorkTaskTargetPage(
            task,
            currentDate: currentDate,
            labelRepository: labelRepository,
            sortingRepository: sortingRepository,
          ),
        ),
      ),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  Widget _authenticated(Widget Function(BuildContext, VoidCallback) builder) {
    final repository = authRepository;
    if (repository == null) return _buildHome();
    return ChangeNotifierProvider(
      create: (_) => AuthController(repository),
      child: AuthGate(authenticatedBuilder: builder),
    );
  }

  Widget _buildHome() {
    final repository = authRepository;
    if (repository == null) {
      return Scaffold(
        body: CommonStateView.error(
          title: 'アプリを開始できません',
          message: startupError ?? '認証設定を確認してください。',
        ),
      );
    }

    return ChangeNotifierProvider(
      create: (_) => AuthController(repository),
      child: AuthGate(
        authenticatedBuilder: (_, signOut) => ResponsiveHomePage(
          onSignOut: signOut,
          currentDate: currentDate,
          csvExportRepository: csvExportRepository,
          masterRepository: masterRepository,
          labelRepository: labelRepository,
          sortingRepository: sortingRepository,
          receivingRepository: receivingRepository,
          inventoryRepository: inventoryRepository,
          ripeningPlanRepository: ripeningPlanRepository,
          workTaskRepository: workTaskRepository,
          orderManagementRepository: orderManagementRepository,
        ),
      ),
    );
  }
}

class ResponsiveHomePage extends StatelessWidget {
  const ResponsiveHomePage({
    this.onSignOut,
    this.currentDate,
    this.csvExportRepository,
    this.masterRepository,
    this.labelRepository,
    this.sortingRepository,
    this.receivingRepository,
    this.inventoryRepository,
    this.ripeningPlanRepository,
    this.workTaskRepository,
    this.orderManagementRepository,
    super.key,
  });
  final DateTime? currentDate;
  final CsvExportRepository? csvExportRepository;
  final MasterRepository? masterRepository;
  final LabelRepository? labelRepository;
  final ReceivingRepository? receivingRepository;
  final InventoryRepository? inventoryRepository;
  final RipeningPlanRepository? ripeningPlanRepository;
  final WorkTaskRepository? workTaskRepository;
  final OrderManagementRepository? orderManagementRepository;
  final SortingRepository? sortingRepository;

  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= AppBreakpoints.manager
          ? ManagerHomePage(
              onSignOut: onSignOut,
              currentDate: currentDate,
              csvExportRepository: csvExportRepository,
              masterRepository: masterRepository,
              inventoryRepository: inventoryRepository,
              ripeningPlanRepository: ripeningPlanRepository,
              workTaskRepository: workTaskRepository,
              orderManagementRepository: orderManagementRepository,
            )
          : WorkerHomePage(
              onSignOut: onSignOut,
              currentDate: currentDate,
              csvExportRepository: csvExportRepository,
              labelRepository: labelRepository,
              sortingRepository: sortingRepository,
              receivingRepository: receivingRepository,
              inventoryRepository: inventoryRepository,
              ripeningPlanRepository: ripeningPlanRepository,
              workTaskRepository: workTaskRepository,
            ),
    );
  }
}

enum TaskTone { error, warning, progress, neutral }

class WorkTask {
  const WorkTask({
    required this.title,
    required this.id,
    required this.details,
    required this.weight,
    required this.schedule,
    required this.location,
    required this.status,
    required this.tone,
  });

  final String title;
  final String id;
  final String details;
  final String weight;
  final String schedule;
  final String location;
  final String status;
  final TaskTone tone;
}

const overdueTask = WorkTask(
  title: '選果登録',
  id: 'LOT-2026-0142',
  details: 'ヘイワード・M',
  weight: '48.25 kg',
  schedule: '期限 9月6日',
  location: '第一冷蔵庫',
  status: '期限超過',
  tone: TaskTone.error,
);

const todayTasks = [
  WorkTask(
    title: 'エチレン注入',
    id: 'RIP-2026-0031',
    details: 'ヘイワード・L',
    weight: '20.50 kg',
    schedule: '10:00',
    location: '第1追熟庫',
    status: '予定',
    tone: TaskTone.progress,
  ),
  WorkTask(
    title: '選果登録',
    id: 'LOT-2026-0148',
    details: '香緑・M',
    weight: '36.80 kg',
    schedule: '14:00',
    location: '第二冷蔵庫',
    status: '予定',
    tone: TaskTone.progress,
  ),
];

class WorkerHomePage extends StatefulWidget {
  const WorkerHomePage({
    this.onSignOut,
    this.currentDate,
    this.csvExportRepository,
    this.labelRepository,
    this.sortingRepository,
    this.receivingRepository,
    this.inventoryRepository,
    this.ripeningPlanRepository,
    this.workTaskRepository,
    super.key,
  });
  final DateTime? currentDate;
  final CsvExportRepository? csvExportRepository;
  final LabelRepository? labelRepository;
  final ReceivingRepository? receivingRepository;
  final InventoryRepository? inventoryRepository;
  final RipeningPlanRepository? ripeningPlanRepository;
  final WorkTaskRepository? workTaskRepository;
  final SortingRepository? sortingRepository;

  final VoidCallback? onSignOut;

  @override
  State<WorkerHomePage> createState() => _WorkerHomePageState();
}

class _WorkerHomePageState extends State<WorkerHomePage> {
  final _todoKey = GlobalKey<WorkerTodoSectionsState>();
  Future<void> _refreshTasks() async {
    await _todoKey.currentState?.refresh();
  }

  DateTime? get currentDate => widget.currentDate;
  CsvExportRepository? get csvExportRepository => widget.csvExportRepository;
  LabelRepository? get labelRepository => widget.labelRepository;
  ReceivingRepository? get receivingRepository => widget.receivingRepository;
  InventoryRepository? get inventoryRepository => widget.inventoryRepository;
  RipeningPlanRepository? get ripeningPlanRepository =>
      widget.ripeningPlanRepository;
  WorkTaskRepository? get workTaskRepository => widget.workTaskRepository;
  SortingRepository? get sortingRepository => widget.sortingRepository;
  VoidCallback? get onSignOut => widget.onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _plainAppBar('おおくま農園', onSignOut: onSignOut),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: RefreshIndicator(
            onRefresh: _refreshTasks,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      formattedToday(currentDate),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF56605A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'ToDo',
                      style: TextStyle(
                        fontSize: 30,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SectionTitle('作業を始める'),
                    const SizedBox(height: 12),
                    ActionButton(
                      label: '収穫・仕入れ登録',
                      onPressed: () => _openReceiving(context),
                    ),
                    const SizedBox(height: 10),
                    ActionButton(
                      label: '選果登録',
                      onPressed: () => _openSorting(context),
                    ),
                    const SizedBox(height: 10),
                    ActionButton(
                      label: 'ラベル発行',
                      onPressed: () => _openLabels(context),
                    ),
                    const SizedBox(height: 10),
                    ActionButton(
                      label: '追熟計画作成',
                      onPressed: () => _openRipeningPlan(context),
                    ),
                    const SizedBox(height: 10),
                    ActionButton(
                      label: '在庫参照',
                      onPressed: () => _openInventory(context),
                    ),
                    const SizedBox(height: 32),
                    if (workTaskRepository == null) ...[
                      const SectionTitle('期限超過', count: '1件'),
                      const SizedBox(height: 8),
                      const TaskRow(task: overdueTask),
                      const SizedBox(height: 28),
                      const SectionTitle('本日の予定', count: '2件'),
                      const SizedBox(height: 8),
                      const TaskList(tasks: todayTasks),
                      const SizedBox(height: 28),
                      const SectionTitle('今後の作業'),
                      const SizedBox(height: 8),
                      const TaskRow(
                        task: WorkTask(
                          title: '追熟確認',
                          id: 'RIP-2026-0028',
                          details: 'ヘイワード・M',
                          weight: '18.40 kg',
                          schedule: '9月10日 9:00',
                          location: '第2追熟庫',
                          status: '今後',
                          tone: TaskTone.neutral,
                        ),
                      ),
                    ] else
                      WorkerTodoSections(
                        key: _todoKey,
                        repository: workTaskRepository!,
                        currentDate: currentDate,
                        onOpenTask: (task) => _openTask(context, task),
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

  void _openReceiving(BuildContext context) {
    final repository = receivingRepository;
    if (repository == null) {
      preparing(context);
      return;
    }
    Navigator.of(context)
        .push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) =>
                ReceivingPage(repository: repository, currentDate: currentDate),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        )
        .then((_) {
          if (mounted) _refreshTasks();
        });
  }

  void _openSorting(BuildContext context) {
    final repository = sortingRepository;
    if (repository == null) {
      preparing(context);
      return;
    }
    Navigator.of(context)
        .push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => SortingTargetPage(
              repository: repository,
              currentDate: currentDate,
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        )
        .then((_) {
          if (mounted) _refreshTasks();
        });
  }

  void _openLabels(BuildContext context) {
    final repository = labelRepository;
    if (repository == null) {
      preparing(context);
      return;
    }
    Navigator.of(context)
        .push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => LabelTargetPage(repository: repository),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        )
        .then((_) {
          if (mounted) _refreshTasks();
        });
  }

  void _openInventory(BuildContext context) {
    final repository = inventoryRepository;
    if (repository == null) {
      preparing(context);
      return;
    }
    Navigator.of(context)
        .push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => InventoryPage(
              repository: repository,
              csvExportRepository: csvExportRepository,
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        )
        .then((_) {
          if (mounted) _refreshTasks();
        });
  }

  void _openRipeningPlan(BuildContext context) {
    final repository = ripeningPlanRepository;
    if (repository == null) {
      preparing(context);
      return;
    }
    Navigator.of(context)
        .push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => RipeningPlanPage(
              repository: repository,
              currentDate: currentDate,
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        )
        .then((_) {
          if (mounted) _refreshTasks();
        });
  }

  void _openTask(BuildContext context, WorkTaskItem task) {
    final targetPage = _buildWorkTaskTargetPage(
      task,
      currentDate: currentDate,
      labelRepository: labelRepository,
      sortingRepository: sortingRepository,
    );
    Navigator.of(context)
        .push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => WorkTaskDetailPage(
              task: task,
              currentDate: currentDate,
              onOpenTarget: targetPage == null
                  ? null
                  : () => Navigator.of(context).push(
                      PageRouteBuilder<void>(
                        pageBuilder: (_, _, _) => targetPage,
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                      ),
                    ),
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        )
        .then((_) {
          if (mounted) _refreshTasks();
        });
  }
}

Widget? _buildWorkTaskTargetPage(
  WorkTaskItem task, {
  required DateTime? currentDate,
  required LabelRepository? labelRepository,
  required SortingRepository? sortingRepository,
}) => switch (task.type) {
  WorkTaskType.sorting when sortingRepository != null => SortingTargetPage(
    repository: sortingRepository,
    currentDate: currentDate,
  ),
  WorkTaskType.labelPrinting when labelRepository != null => LabelTargetPage(
    repository: labelRepository,
  ),
  _ => null,
};

class ManagerHomePage extends StatelessWidget {
  const ManagerHomePage({
    this.onSignOut,
    this.currentDate,
    this.csvExportRepository,
    this.masterRepository,
    this.inventoryRepository,
    this.ripeningPlanRepository,
    this.workTaskRepository,
    this.orderManagementRepository,
    super.key,
  });
  final DateTime? currentDate;
  final CsvExportRepository? csvExportRepository;
  final MasterRepository? masterRepository;
  final InventoryRepository? inventoryRepository;
  final RipeningPlanRepository? ripeningPlanRepository;
  final WorkTaskRepository? workTaskRepository;
  final OrderManagementRepository? orderManagementRepository;

  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          ManagerNavigation(
            onSignOut: onSignOut,
            onSelected: (item) => _openNavigation(context, item),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _buildDashboard(context)),
        ],
      ),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    final tasks = workTaskRepository;
    final orders = orderManagementRepository;
    return ManagerDashboardPage(
      repository: tasks != null && orders != null
          ? DefaultManagerDashboardRepository(
              workTaskRepository: tasks,
              orderManagementRepository: orders,
            )
          : const _EmptyManagerDashboardRepository(),
      currentDate: currentDate ?? DateTime.now(),
      onOpenTask: (task) => Navigator.of(context).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => WorkTaskDetailPage(
            task: task,
            currentDate: currentDate,
            backLabel: '← ホームへ戻る',
            showCalendarSyncStatus: true,
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      ),
      onOpenOrder: orders == null
          ? (_) {}
          : (order) => Navigator.of(context).push(
              PageRouteBuilder<void>(
                pageBuilder: (_, _, _) => ManagerOrderPage(
                  repository: orders,
                  initialOrderId: order.id,
                  currentDate: currentDate,
                  ripeningPlanRepository: ripeningPlanRepository,
                  inventoryRepository: inventoryRepository,
                  masterRepository: masterRepository,
                  csvExportRepository: csvExportRepository,
                  onSignOut: onSignOut,
                ),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            ),
    );
  }

  void _openNavigation(BuildContext context, String item) {
    final Widget? page = switch (item) {
      '受注' when orderManagementRepository != null => ManagerOrderPage(
        repository: orderManagementRepository!,
        currentDate: currentDate,
        ripeningPlanRepository: ripeningPlanRepository,
        inventoryRepository: inventoryRepository,
        masterRepository: masterRepository,
        csvExportRepository: csvExportRepository,
        onSignOut: onSignOut,
      ),
      '在庫管理' when inventoryRepository != null => ManagerInventoryPage(
        repository: inventoryRepository!,
        masterRepository: masterRepository,
        orderManagementRepository: orderManagementRepository,
        csvExportRepository: csvExportRepository,
        ripeningPlanRepository: ripeningPlanRepository,
        onSignOut: onSignOut,
      ),
      'マスター' when masterRepository != null => ManagerMasterPage(
        repository: masterRepository!,
        inventoryRepository: inventoryRepository,
        orderManagementRepository: orderManagementRepository,
        csvExportRepository: csvExportRepository,
        ripeningPlanRepository: ripeningPlanRepository,
        onSignOut: onSignOut,
      ),
      '追熟計画' when ripeningPlanRepository != null => ManagerRipeningPlanPage(
        repository: ripeningPlanRepository!,
        orderManagementRepository: orderManagementRepository,
        currentDate: currentDate,
        inventoryRepository: inventoryRepository,
        masterRepository: masterRepository,
        csvExportRepository: csvExportRepository,
        onSignOut: onSignOut,
      ),
      _ => null,
    };
    if (page == null) {
      preparing(context, '$item画面は準備中です');
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }
}

class _EmptyManagerDashboardRepository implements ManagerDashboardRepository {
  const _EmptyManagerDashboardRepository();

  @override
  Future<ManagerDashboardData> load() async => const ManagerDashboardData(
    tasks: [],
    orders: OrderManagementData(
      orders: [],
      customers: [],
      varieties: [],
      grades: [],
      canManage: false,
    ),
    syncWarnings: WorkTaskSyncWarnings.empty(),
  );
}

class ManagerMasterPage extends StatelessWidget {
  const ManagerMasterPage({
    required this.repository,
    this.inventoryRepository,
    this.csvExportRepository,
    this.ripeningPlanRepository,
    this.orderManagementRepository,
    this.onSignOut,
    super.key,
  });

  final MasterRepository repository;
  final InventoryRepository? inventoryRepository;
  final CsvExportRepository? csvExportRepository;
  final RipeningPlanRepository? ripeningPlanRepository;
  final OrderManagementRepository? orderManagementRepository;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        ManagerNavigation(
          selectedItem: 'マスター',
          onSignOut: onSignOut == null
              ? null
              : () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  onSignOut!.call();
                },
          onSelected: (item) {
            if (item == 'ホーム') {
              Navigator.of(context).pop();
            } else if (item == '受注' && orderManagementRepository != null) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => ManagerOrderPage(
                    repository: orderManagementRepository!,
                    ripeningPlanRepository: ripeningPlanRepository,
                    inventoryRepository: inventoryRepository,
                    masterRepository: repository,
                    csvExportRepository: csvExportRepository,
                    onSignOut: onSignOut,
                  ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            } else if (item == '在庫管理' && inventoryRepository != null) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => ManagerInventoryPage(
                    repository: inventoryRepository!,
                    masterRepository: repository,
                    csvExportRepository: csvExportRepository,
                    ripeningPlanRepository: ripeningPlanRepository,
                    orderManagementRepository: orderManagementRepository,
                    onSignOut: onSignOut,
                  ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            } else if (item == '追熟計画' && ripeningPlanRepository != null) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => ManagerRipeningPlanPage(
                    repository: ripeningPlanRepository!,
                    inventoryRepository: inventoryRepository,
                    masterRepository: repository,
                    csvExportRepository: csvExportRepository,
                    orderManagementRepository: orderManagementRepository,
                    onSignOut: onSignOut,
                  ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            } else {
              preparing(context, '$item画面は準備中です');
            }
          },
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: MasterPage(
            repository: repository,
            csvExportRepository: csvExportRepository,
            embedded: true,
          ),
        ),
      ],
    ),
  );
}

class ManagerInventoryPage extends StatelessWidget {
  const ManagerInventoryPage({
    required this.repository,
    this.masterRepository,
    this.csvExportRepository,
    this.ripeningPlanRepository,
    this.orderManagementRepository,
    this.onSignOut,
    super.key,
  });

  final InventoryRepository repository;
  final MasterRepository? masterRepository;
  final CsvExportRepository? csvExportRepository;
  final RipeningPlanRepository? ripeningPlanRepository;
  final OrderManagementRepository? orderManagementRepository;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        ManagerNavigation(
          selectedItem: '在庫管理',
          onSignOut: onSignOut == null
              ? null
              : () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  onSignOut!.call();
                },
          onSelected: (item) {
            if (item == 'ホーム') {
              Navigator.of(context).pop();
            } else if (item == '受注' && orderManagementRepository != null) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => ManagerOrderPage(
                    repository: orderManagementRepository!,
                    ripeningPlanRepository: ripeningPlanRepository,
                    inventoryRepository: repository,
                    masterRepository: masterRepository,
                    csvExportRepository: csvExportRepository,
                    onSignOut: onSignOut,
                  ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            } else if (item == 'マスター' && masterRepository != null) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => ManagerMasterPage(
                    repository: masterRepository!,
                    inventoryRepository: repository,
                    csvExportRepository: csvExportRepository,
                    ripeningPlanRepository: ripeningPlanRepository,
                    orderManagementRepository: orderManagementRepository,
                    onSignOut: onSignOut,
                  ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            } else if (item == '追熟計画' && ripeningPlanRepository != null) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => ManagerRipeningPlanPage(
                    repository: ripeningPlanRepository!,
                    inventoryRepository: repository,
                    masterRepository: masterRepository,
                    csvExportRepository: csvExportRepository,
                    orderManagementRepository: orderManagementRepository,
                    onSignOut: onSignOut,
                  ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            } else {
              preparing(context, '$item画面は準備中です');
            }
          },
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: InventoryPage(
            repository: repository,
            csvExportRepository: csvExportRepository,
            embedded: true,
          ),
        ),
      ],
    ),
  );
}

class ManagerRipeningPlanPage extends StatelessWidget {
  const ManagerRipeningPlanPage({
    required this.repository,
    this.currentDate,
    this.inventoryRepository,
    this.masterRepository,
    this.csvExportRepository,
    this.orderManagementRepository,
    this.onSignOut,
    super.key,
  });

  final RipeningPlanRepository repository;
  final DateTime? currentDate;
  final InventoryRepository? inventoryRepository;
  final MasterRepository? masterRepository;
  final CsvExportRepository? csvExportRepository;
  final OrderManagementRepository? orderManagementRepository;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        ManagerNavigation(
          selectedItem: '追熟計画',
          onSignOut: onSignOut == null
              ? null
              : () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  onSignOut!.call();
                },
          onSelected: (item) {
            if (item == 'ホーム') {
              Navigator.of(context).pop();
            } else if (item == '受注' && orderManagementRepository != null) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => ManagerOrderPage(
                    repository: orderManagementRepository!,
                    ripeningPlanRepository: repository,
                    inventoryRepository: inventoryRepository,
                    masterRepository: masterRepository,
                    csvExportRepository: csvExportRepository,
                    onSignOut: onSignOut,
                  ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            } else if (item == '在庫管理' && inventoryRepository != null) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => ManagerInventoryPage(
                    repository: inventoryRepository!,
                    masterRepository: masterRepository,
                    csvExportRepository: csvExportRepository,
                    ripeningPlanRepository: repository,
                    orderManagementRepository: orderManagementRepository,
                    onSignOut: onSignOut,
                  ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            } else if (item == 'マスター' && masterRepository != null) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => ManagerMasterPage(
                    repository: masterRepository!,
                    inventoryRepository: inventoryRepository,
                    csvExportRepository: csvExportRepository,
                    ripeningPlanRepository: repository,
                    orderManagementRepository: orderManagementRepository,
                    onSignOut: onSignOut,
                  ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            } else {
              preparing(context, '$item画面は準備中です');
            }
          },
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: RipeningPlanPage(
            repository: repository,
            currentDate: currentDate,
            embedded: true,
          ),
        ),
      ],
    ),
  );
}

class ManagerOrderPage extends StatelessWidget {
  const ManagerOrderPage({
    required this.repository,
    this.currentDate,
    this.initialOrderId,
    this.ripeningPlanRepository,
    this.inventoryRepository,
    this.masterRepository,
    this.csvExportRepository,
    this.onSignOut,
    super.key,
  });

  final OrderManagementRepository repository;
  final DateTime? currentDate;
  final String? initialOrderId;
  final RipeningPlanRepository? ripeningPlanRepository;
  final InventoryRepository? inventoryRepository;
  final MasterRepository? masterRepository;
  final CsvExportRepository? csvExportRepository;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        ManagerNavigation(
          selectedItem: '受注',
          onSignOut: onSignOut == null
              ? null
              : () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  onSignOut!.call();
                },
          onSelected: (item) {
            if (item == 'ホーム') {
              Navigator.of(context).pop();
            } else if (item == '追熟計画' && ripeningPlanRepository != null) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => ManagerRipeningPlanPage(
                    repository: ripeningPlanRepository!,
                    currentDate: currentDate,
                    inventoryRepository: inventoryRepository,
                    masterRepository: masterRepository,
                    csvExportRepository: csvExportRepository,
                    orderManagementRepository: repository,
                    onSignOut: onSignOut,
                  ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            } else if (item == '在庫管理' && inventoryRepository != null) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => ManagerInventoryPage(
                    repository: inventoryRepository!,
                    masterRepository: masterRepository,
                    csvExportRepository: csvExportRepository,
                    ripeningPlanRepository: ripeningPlanRepository,
                    orderManagementRepository: repository,
                    onSignOut: onSignOut,
                  ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            } else if (item == 'マスター' && masterRepository != null) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => ManagerMasterPage(
                    repository: masterRepository!,
                    inventoryRepository: inventoryRepository,
                    csvExportRepository: csvExportRepository,
                    ripeningPlanRepository: ripeningPlanRepository,
                    orderManagementRepository: repository,
                    onSignOut: onSignOut,
                  ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            } else {
              preparing(context, '$item画面は準備中です');
            }
          },
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: OrderManagementPage(
            repository: repository,
            initialOrderId: initialOrderId,
          ),
        ),
      ],
    ),
  );
}

class ManagerNavigation extends StatelessWidget {
  const ManagerNavigation({
    this.onSignOut,
    this.onSelected,
    this.selectedItem = 'ホーム',
    super.key,
  });

  final VoidCallback? onSignOut;
  final ValueChanged<String>? onSelected;
  final String selectedItem;
  static const items = ['ホーム', '受注', '追熟計画', '在庫管理', '出荷', 'マスター'];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: SizedBox(
        width: 224,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'おおくま農園',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 28),
                for (final item in items)
                  NavigationItem(
                    label: item,
                    selected: item == selectedItem,
                    onTap: () => onSelected?.call(item),
                  ),
                const Spacer(),
                if (onSignOut != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextButton(
                      onPressed: onSignOut,
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        minimumSize: const Size(0, 48),
                      ),
                      child: const Text('ログアウト'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NavigationItem extends StatelessWidget {
  const NavigationItem({
    required this.label,
    required this.selected,
    this.onTap,
    super.key,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: selected
            ? null
            : onTap ?? () => preparing(context, '$label画面は準備中です'),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF2ED) : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: selected ? const Color(0xFF205C3B) : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? const Color(0xFF15452C)
                  : const Color(0xFF303633),
            ),
          ),
        ),
      ),
    );
  }
}

class SummaryStrip extends StatelessWidget {
  const SummaryStrip({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('ToDo', '5件'),
      ('要確認', '2件'),
      ('7日以内の予定', '8件'),
      ('予約不足', '1件'),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFCBD1CD)),
          bottom: BorderSide(color: Color(0xFFCBD1CD)),
        ),
      ),
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      items[index].$1,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF56605A),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      items[index].$2,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (index != items.length - 1)
              const SizedBox(height: 52, child: VerticalDivider(width: 1)),
          ],
        ],
      ),
    );
  }
}

class ScheduleColumn extends StatelessWidget {
  const ScheduleColumn({required this.title, required this.rows, super.key});
  final String title;
  final List<(String, String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title),
        const SizedBox(height: 10),
        for (final row in rows)
          PlainScheduleRow(time: row.$1, title: row.$2, id: row.$3),
      ],
    );
  }
}

class PlainScheduleRow extends StatelessWidget {
  const PlainScheduleRow({
    required this.time,
    required this.title,
    required this.id,
    super.key,
  });
  final String time;
  final String title;
  final String id;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFCBD1CD))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(time, style: const TextStyle(fontSize: 14)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  id,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF56605A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ActionButton extends StatelessWidget {
  const ActionButton({required this.label, required this.onPressed, super.key});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$labelへ進む',
      button: true,
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Row(
          children: [
            Expanded(child: Text(label)),
            const ExcludeSemantics(
              child: Text('→', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.label, {this.count, super.key});
  final String label;
  final String? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
        ),
        if (count != null)
          Text(
            count!,
            style: const TextStyle(fontSize: 14, color: Color(0xFF56605A)),
          ),
      ],
    );
  }
}

class TaskList extends StatelessWidget {
  const TaskList({required this.tasks, super.key});
  final List<WorkTask> tasks;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFCBD1CD))),
      ),
      child: Column(children: [for (final task in tasks) TaskRow(task: task)]),
    );
  }
}

class TaskRow extends StatelessWidget {
  const TaskRow({required this.task, super.key});
  final WorkTask task;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${task.id}の詳細を見る',
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => TaskDetailPage(task: task),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFCBD1CD))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        StatusLabel(label: task.status, tone: task.tone),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      task.id,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          task.details,
                          style: const TextStyle(fontSize: 14),
                        ),
                        Text(
                          task.weight,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          task.schedule,
                          style: const TextStyle(fontSize: 14),
                        ),
                        Text(
                          task.location,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF56605A),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const ExcludeSemantics(
                child: Text(
                  '→',
                  style: TextStyle(fontSize: 20, color: Color(0xFF35413A)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StatusLabel extends StatelessWidget {
  const StatusLabel({required this.label, required this.tone, super.key});
  final String label;
  final TaskTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      TaskTone.error => (const Color(0xFFFFE9E7), const Color(0xFF8D1C16)),
      TaskTone.warning => (const Color(0xFFFFF1C7), const Color(0xFF654B00)),
      TaskTone.progress => (const Color(0xFFE7F0FA), const Color(0xFF174D7D)),
      TaskTone.neutral => (const Color(0xFFEDF0EE), const Color(0xFF3F4943)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: colors.$2,
        ),
      ),
    );
  }
}

class TaskDetailPage extends StatelessWidget {
  const TaskDetailPage({required this.task, super.key});
  final WorkTask task;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 8,
        title: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF205C3B),
            minimumSize: const Size(48, 48),
          ),
          child: const Text('← ToDoへ戻る', style: TextStyle(fontSize: 16)),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 48),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      StatusLabel(label: task.status, tone: task.tone),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    '対象ID',
                    style: TextStyle(fontSize: 14, color: Color(0xFF56605A)),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    task.id,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(height: 1),
                  DetailValue(label: '重量', value: task.weight, prominent: true),
                  DetailValue(label: '品種・等級', value: task.details),
                  DetailValue(label: '期限・予定', value: task.schedule),
                  DetailValue(label: '場所', value: task.location),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: () => preparing(context, '作業画面は準備中です'),
                    child: Text('${task.title}を開始'),
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

class DetailValue extends StatelessWidget {
  const DetailValue({
    required this.label,
    required this.value,
    this.prominent = false,
    super.key,
  });
  final String label;
  final String value;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 17),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFCBD1CD))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: Color(0xFF56605A)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: prominent ? 24 : 16,
                fontWeight: prominent ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

AppBar _plainAppBar(String title, {VoidCallback? onSignOut}) => AppBar(
  automaticallyImplyLeading: false,
  backgroundColor: Colors.white,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  titleSpacing: 16,
  title: Text(
    title,
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
  ),
  actions: [
    if (onSignOut != null)
      TextButton(
        onPressed: onSignOut,
        style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
        child: const Text('ログアウト'),
      ),
  ],
  bottom: const PreferredSize(
    preferredSize: Size.fromHeight(1),
    child: Divider(height: 1),
  ),
);

String formattedToday([DateTime? currentDate]) {
  final now = currentDate ?? DateTime.now();
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  return '${now.year}年${now.month}月${now.day}日（${weekdays[now.weekday - 1]}）';
}

void preparing(BuildContext context, [String message = 'この作業画面は準備中です']) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
