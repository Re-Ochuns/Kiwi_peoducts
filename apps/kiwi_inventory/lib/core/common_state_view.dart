import 'package:flutter/material.dart';

enum CommonStateKind { loading, empty, error }

class CommonStateView extends StatelessWidget {
  const CommonStateView.loading({this.title = '読み込み中', this.message, super.key})
    : kind = CommonStateKind.loading,
      actionLabel = null,
      onAction = null;

  const CommonStateView.empty({
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : kind = CommonStateKind.empty;

  const CommonStateView.error({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : kind = CommonStateKind.error;

  final CommonStateKind kind;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Semantics(
            liveRegion: kind != CommonStateKind.empty,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (kind == CommonStateKind.loading) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Text(message!, style: const TextStyle(fontSize: 16)),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 28),
                  FilledButton(onPressed: onAction, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
