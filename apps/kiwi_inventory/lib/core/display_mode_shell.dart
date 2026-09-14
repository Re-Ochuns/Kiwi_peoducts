import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_breakpoints.dart';

enum DisplayMode { automatic, desktop, mobile }

/// Keeps the display controls outside the Navigator and the scrolling viewport.
class DisplayModeShell extends StatefulWidget {
  const DisplayModeShell({required this.appBuilder, super.key});

  final Widget Function(GlobalKey<NavigatorState>, TransitionBuilder)
  appBuilder;

  @override
  State<DisplayModeShell> createState() => _DisplayModeShellState();
}

class _DisplayModeShellState extends State<DisplayModeShell> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  DisplayMode _mode = DisplayMode.automatic;
  bool _switching = false;

  Future<void> _select(DisplayMode mode) async {
    if (_mode == mode || _switching) return;
    setState(() => _switching = true);
    try {
      // Use maybePop so forms can decline navigation with their existing guard.
      final navigator = _navigatorKey.currentState;
      while (navigator != null && navigator.canPop()) {
        Route<dynamic>? top;
        navigator.popUntil((route) {
          top = route;
          return true;
        });
        if (!await navigator.maybePop()) return;
        if (!mounted) return;
        // A PopScope can handle the request without removing the route.
        if (top?.isCurrent ?? false) return;
      }
      if (mounted) setState(() => _mode = mode);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.appBuilder(_navigatorKey, _buildFrame);

  Widget _buildFrame(BuildContext context, Widget? child) => Material(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: SafeArea(
      child: Column(
        children: [
          Container(
            key: const ValueKey('display-mode-header'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '表示切替',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                for (final option in const [
                  (DisplayMode.desktop, 'PC'),
                  (DisplayMode.mobile, 'スマホ'),
                  (DisplayMode.automatic, '自動'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Semantics(
                      selected: _mode == option.$1,
                      child: TextButton(
                        key: ValueKey('display-mode-${option.$1.name}'),
                        onPressed: _switching ? null : () => _select(option.$1),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          backgroundColor: _mode == option.$1
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                        ),
                        child: Text(option.$2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = switch (_mode) {
                  DisplayMode.automatic => constraints.maxWidth,
                  DisplayMode.desktop => math.max(
                    constraints.maxWidth,
                    AppBreakpoints.desktop,
                  ),
                  DisplayMode.mobile => math.min(
                    constraints.maxWidth,
                    AppBreakpoints.compact,
                  ),
                };
                return Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      height: constraints.maxHeight,
                      child: MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(size: Size(width, constraints.maxHeight)),
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
