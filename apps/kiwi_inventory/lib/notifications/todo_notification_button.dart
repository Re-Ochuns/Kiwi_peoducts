import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'dart:math';

import 'todo_notification_repository.dart';

class TodoNotificationButton extends StatefulWidget {
  const TodoNotificationButton({super.key});
  @override
  State<TodoNotificationButton> createState() => _TodoNotificationButtonState();
}

class _TodoNotificationButtonState extends State<TodoNotificationButton> {
  TodoNotificationRepository? _repository;
  bool _allowed = false;
  bool _busy = false;
  String? _requestId;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = context.watch<TodoNotificationRepository?>();
    if (identical(repository, _repository)) return;
    _repository = repository;
    _allowed = false;
    if (repository != null) _loadPermission(repository);
  }

  Future<void> _loadPermission(TodoNotificationRepository repository) async {
    try {
      final allowed = await repository.canNotify();
      if (mounted && identical(repository, _repository)) {
        setState(() => _allowed = allowed);
      }
    } catch (_) {
      /* Do not expose the button without confirmed access. */
    }
  }

  Future<void> _send() async {
    if (_busy || !_allowed) return;
    setState(() => _busy = true);
    String result;
    try {
      result = await _repository!.notify(_requestId ??= _newId());
    } catch (_) {
      result = 'unknown';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if ([
      'sent',
      'failed',
      'not_configured',
      'forbidden',
      'rate_limited',
    ].contains(result)) {
      _requestId = null;
    }
    final text = switch (result) {
      'sent' => '本日のToDoをDiscordに通知しました。',
      'not_configured' => '通知先が未設定です。管理者がDiscord通知設定を完了してください。',
      'forbidden' => '通知には有効な管理者権限が必要です。',
      'rate_limited' => '通知が続いています。1分ほど待ってからお試しください。',
      'failed' => '通知できませんでした。通知先の設定と接続状況を確認してください。',
      _ => '送信結果を確認できません。Discordと通知ログを確認してください。',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => !_allowed
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: OutlinedButton(
            onPressed: _busy ? null : _send,
            child: Text(_busy ? '通知中…' : 'Discordに通知'),
          ),
        );
}

String _newId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
