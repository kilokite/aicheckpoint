import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'windows_native.dart';

/// 「贴边模式」控制器：把窗口贴到屏幕最右侧隐藏，
/// 鼠标移动到屏幕最右边缘对应位置时再滑出来（模仿 QQ 的贴边逻辑）。
///
/// 仅支持 Windows，其余平台切换开关不生效。
class EdgeDockService extends ChangeNotifier {
  EdgeDockService._();

  static final EdgeDockService instance = EdgeDockService._();

  /// 隐藏时保留在屏幕右边缘的可见宽度（逻辑像素），方便看到窗口仍贴在这里。
  static const double _sliverWidth = 2;

  /// 鼠标触发显示的距离阈值：距屏幕右边缘多少像素内算「贴边」。
  static const double _triggerZone = 4;

  /// 显示状态下，鼠标离开窗口多少像素后再次隐藏。
  static const double _leaveMargin = 8;

  static const Duration _pollInterval = Duration(milliseconds: 80);
  static const Duration _slideDuration = Duration(milliseconds: 160);

  bool _enabled = false;
  bool _visible = false;
  bool _animating = false;
  int _animationGeneration = 0;
  Timer? _timer;

  Rect _restoreBounds = Rect.zero;
  Rect _dockedBounds = Rect.zero;
  Rect _visibleBounds = Rect.zero;

  /// 是否已开启贴边模式。
  bool get enabled => _enabled;

  /// 贴边模式下窗口当前是否滑出（可见）。
  bool get isVisible => _visible;

  Future<void> toggle() => _enabled ? disable() : enable();

  Future<void> enable() async {
    if (_enabled || !Platform.isWindows) return;

    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    }

    final dpr = windowManager.getDevicePixelRatio();
    final workAreaRaw = getPrimaryWorkArea();
    final workArea = Rect.fromLTRB(
      workAreaRaw.left / dpr,
      workAreaRaw.top / dpr,
      workAreaRaw.right / dpr,
      workAreaRaw.bottom / dpr,
    );

    final current = await windowManager.getBounds();
    _restoreBounds = current;

    final maxTop = (workArea.bottom - current.height).clamp(
      workArea.top,
      workArea.bottom,
    );
    final top = current.top.clamp(workArea.top, maxTop);
    _dockedBounds = Rect.fromLTWH(
      workArea.right - _sliverWidth,
      top,
      current.width,
      current.height,
    );
    _visibleBounds = Rect.fromLTWH(
      workArea.right - current.width,
      top,
      current.width,
      current.height,
    );

    _enabled = true;
    _visible = false;
    notifyListeners();

    await _animateTo(_dockedBounds);
    if (_enabled) {
      _startPolling();
    }
  }

  Future<void> disable() async {
    if (!_enabled) return;
    _enabled = false;
    _stopPolling();
    notifyListeners();
    await _animateTo(_restoreBounds);
    _visible = false;
  }

  /// 停止贴边模式，但保持窗口当前位置不动。
  ///
  /// 用于用户手动拖动标题栏时接管窗口，避免自动隐藏逻辑与拖拽互相争抢。
  void cancel() {
    if (!_enabled) return;
    _enabled = false;
    _stopPolling();
    _visible = false;
    notifyListeners();
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (!_enabled || _animating) return;

    final cursorRaw = getGlobalCursorPosition();
    final dpr = windowManager.getDevicePixelRatio();
    final cursor = Offset(cursorRaw.x / dpr, cursorRaw.y / dpr);

    if (_visible) {
      final area = _visibleBounds.inflate(_leaveMargin);
      if (!area.contains(cursor)) {
        await _hide();
      }
    } else if (cursor.dx >= _visibleBounds.right - _triggerZone &&
        cursor.dy >= _dockedBounds.top &&
        cursor.dy <= _dockedBounds.bottom) {
      await _show();
    }
  }

  Future<void> _show() async {
    _visible = true;
    notifyListeners();
    await _animateTo(_visibleBounds);
  }

  Future<void> _hide() async {
    _visible = false;
    notifyListeners();
    await _animateTo(_dockedBounds);
  }

  /// 以 ease-out 曲线把窗口滑动到目标位置。
  ///
  /// 使用代数（generation）避免多次触发时动画互相争抢：新动画会取代旧动画。
  Future<void> _animateTo(Rect target) async {
    final generation = ++_animationGeneration;
    _animating = true;
    try {
      final start = await windowManager.getBounds();
      final stopwatch = Stopwatch()..start();
      final totalMicros = _slideDuration.inMicroseconds;

      while (stopwatch.elapsedMicroseconds < totalMicros) {
        if (generation != _animationGeneration) return;
        final t = (stopwatch.elapsedMicroseconds / totalMicros).clamp(0.0, 1.0);
        final eased = Curves.easeOut.transform(t);
        await windowManager.setPosition(
          Offset(
            start.left + (target.left - start.left) * eased,
            start.top + (target.top - start.top) * eased,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (generation == _animationGeneration) {
        await windowManager.setPosition(target.topLeft);
      }
    } finally {
      if (generation == _animationGeneration) {
        _animating = false;
      }
    }
  }
}
