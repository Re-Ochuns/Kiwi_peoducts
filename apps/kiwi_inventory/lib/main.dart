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
    runApp(KiwiInventoryApp(authRepository: repository));
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
    this.theme,
    super.key,
  });

  final AuthRepository? authRepository;
  final String? startupError;
  final DateTime? currentDate;
  final ThemeData? theme;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'キウイ在庫管理',
      debugShowCheckedModeBanner: false,
      theme: theme ?? buildAppTheme(),
      home: _buildHome(),
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
        authenticatedBuilder: (_, signOut) =>
            ResponsiveHomePage(onSignOut: signOut, currentDate: currentDate),
      ),
    );
  }
}

class ResponsiveHomePage extends StatelessWidget {
  const ResponsiveHomePage({this.onSignOut, this.currentDate, super.key});
  final DateTime? currentDate;

  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= AppBreakpoints.manager
          ? ManagerHomePage(onSignOut: onSignOut, currentDate: currentDate)
          : WorkerHomePage(onSignOut: onSignOut, currentDate: currentDate),
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

class WorkerHomePage extends StatelessWidget {
  const WorkerHomePage({this.onSignOut, this.currentDate, super.key});
  final DateTime? currentDate;

  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _plainAppBar('おおくま農園', onSignOut: onSignOut),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
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
                    onPressed: () => preparing(context),
                  ),
                  const SizedBox(height: 10),
                  ActionButton(
                    label: '選果登録',
                    onPressed: () => preparing(context),
                  ),
                  const SizedBox(height: 10),
                  ActionButton(
                    label: '追熟計画作成',
                    onPressed: () => preparing(context),
                  ),
                  const SizedBox(height: 32),
                  const SectionTitle('期限超過', count: '1件'),
                  const SizedBox(height: 8),
                  const TaskRow(task: overdueTask),
                  const SizedBox(height: 28),
                  const SectionTitle('本日の予定', count: '2件'),
                  const SizedBox(height: 8),
                  const TaskList(tasks: todayTasks),
                  const SizedBox(height: 28),
                  const SectionTitle('今後'),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ManagerHomePage extends StatelessWidget {
  const ManagerHomePage({this.onSignOut, this.currentDate, super.key});
  final DateTime? currentDate;

  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          ManagerNavigation(onSignOut: onSignOut),
          const VerticalDivider(width: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 30, 32, 48),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'ホーム',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formattedToday(currentDate),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF56605A),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const SummaryStrip(),
                      const SizedBox(height: 34),
                      const SectionTitle('優先して確認'),
                      const SizedBox(height: 10),
                      const TaskList(
                        tasks: [
                          WorkTask(
                            title: '選果期限を超過しています',
                            id: 'LOT-2026-0142',
                            details: 'ヘイワード・M',
                            weight: '48.25 kg',
                            schedule: '期限 9月6日',
                            location: '第一冷蔵庫',
                            status: '期限超過',
                            tone: TaskTone.error,
                          ),
                          WorkTask(
                            title: '予約量が在庫を上回っています',
                            id: 'INV-2026-0081',
                            details: '香緑・L',
                            weight: '不足 4.20 kg',
                            schedule: '出荷予定 9月11日',
                            location: '第二冷蔵庫',
                            status: '要確認',
                            tone: TaskTone.warning,
                          ),
                        ],
                      ),
                      const SizedBox(height: 34),
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ScheduleColumn(
                              title: 'ToDo',
                              rows: [
                                ('10:00', 'エチレン注入', 'RIP-2026-0031'),
                                ('14:00', '選果登録', 'LOT-2026-0148'),
                                ('16:30', '出荷確認', 'ORD-2026-0106'),
                              ],
                            ),
                          ),
                          SizedBox(width: 32),
                          Expanded(
                            child: ScheduleColumn(
                              title: '今後7日',
                              rows: [
                                ('9月9日', '追熟開始', 'RIP-2026-0034'),
                                ('9月10日', '追熟確認', 'RIP-2026-0028'),
                                ('9月11日', '出荷予定', 'ORD-2026-0109'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ManagerNavigation extends StatelessWidget {
  const ManagerNavigation({this.onSignOut, super.key});

  final VoidCallback? onSignOut;
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
                  NavigationItem(label: item, selected: item == 'ホーム'),
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
    super.key,
  });
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: selected ? null : () => preparing(context, '$label画面は準備中です'),
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
