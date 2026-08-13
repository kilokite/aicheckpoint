import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../services/edge_dock_service.dart';

class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: 38,
    color: const Color(0xFF20231F),
    child: Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) {
              // 用户手动拖动标题栏时，退出贴边模式以免互相争抢。
              EdgeDockService.instance.cancel();
              windowManager.startDragging();
            },
            onDoubleTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
            child: const SizedBox(
              height: double.infinity,
              child: Padding(
                padding: EdgeInsets.only(left: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.bookmark_rounded,
                      color: Color(0xFF58C994),
                      size: 17,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Checkpoint',
                      style: TextStyle(
                        color: Color(0xFFD7DAD5),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const _EdgeDockButton(),
        _MinimizeButton(),
        _WindowButton(
          tooltip: '最大化',
          icon: Icons.crop_square,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _WindowButton(
          tooltip: '关闭',
          icon: Icons.close,
          closeButton: true,
          onPressed: windowManager.close,
        ),
      ],
    ),
  );
}

class _EdgeDockButton extends StatefulWidget {
  const _EdgeDockButton();

  @override
  State<_EdgeDockButton> createState() => _EdgeDockButtonState();
}

class _EdgeDockButtonState extends State<_EdgeDockButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: EdgeDockService.instance,
    builder: (context, _) {
      final active = EdgeDockService.instance.enabled;
      return Tooltip(
        message: active ? '退出贴边模式' : '贴边模式（贴到右侧隐藏）',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: InkWell(
            onTap: EdgeDockService.instance.toggle,
            child: SizedBox(
              width: 48,
              height: 38,
              child: ColoredBox(
                color: _hovered
                    ? const Color(0xFF363A35)
                    : active
                    ? const Color(0xFF1B2A22)
                    : Colors.transparent,
                child: Icon(
                  Icons.last_page,
                  size: 16,
                  color: active
                      ? const Color(0xFF58C994)
                      : const Color(0xFFD7DAD5),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _MinimizeButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: EdgeDockService.instance,
    builder: (context, _) {
      // 贴边模式下窗口不可最小化（任务栏已隐藏，最小化后无从找回）。
      final docked = EdgeDockService.instance.enabled;
      return Tooltip(
        message: docked ? '贴边模式下不可最小化' : '最小化',
        child: _WindowButton(
          tooltip: docked ? '贴边模式下不可最小化' : '最小化',
          icon: Icons.remove,
          enabled: !docked,
          onPressed: docked ? () async {} : windowManager.minimize,
        ),
      );
    },
  );
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.closeButton = false,
    this.enabled = true,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;
  final bool closeButton;
  final bool enabled;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.enabled ? widget.onPressed : null,
        child: SizedBox(
          width: 48,
          height: 38,
          child: ColoredBox(
            color: _hovered && widget.enabled
                ? widget.closeButton
                      ? const Color(0xFFC42B1C)
                      : const Color(0xFF363A35)
                : Colors.transparent,
            child: Icon(
              widget.icon,
              size: 16,
              color: widget.enabled
                  ? const Color(0xFFD7DAD5)
                  : const Color(0xFF6A6E68),
            ),
          ),
        ),
      ),
    ),
  );
}
