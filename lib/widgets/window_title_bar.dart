import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

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
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
            child: const DragToMoveArea(
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
        _WindowButton(
          tooltip: '最小化',
          icon: Icons.remove,
          onPressed: windowManager.minimize,
        ),
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

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.closeButton = false,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;
  final bool closeButton;

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
        onTap: widget.onPressed,
        child: SizedBox(
          width: 48,
          height: 38,
          child: ColoredBox(
            color: _hovered
                ? widget.closeButton
                      ? const Color(0xFFC42B1C)
                      : const Color(0xFF363A35)
                : Colors.transparent,
            child: Icon(widget.icon, size: 16, color: const Color(0xFFD7DAD5)),
          ),
        ),
      ),
    ),
  );
}
