import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'windows_native.dart';

/// 「贴边模式」控制器：把窗口贴到屏幕最右侧隐藏，
/// 鼠标移动到屏幕最右边缘对应位置时再滑出来（模仿 QQ 的贴边逻辑）。
///
/// 仅支持 Windows，其余平台切换开关不生效。
class EdgeDockService extends ChangeNotifier with WindowListener {
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

  /// 显示器几何信息（工作区/分辨率）属于低频变化，
  /// 不必跟随鼠标检测的高频轮询一起重算。
  static const Duration _geometryRefreshInterval = Duration(milliseconds: 500);

  bool _enabled = false;
  bool _visible = false;
  bool _animating = false;
  int _animationGeneration = 0;
  Timer? _timer;
  DateTime _lastGeometryRefresh = DateTime.fromMillisecondsSinceEpoch(0);

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

    final current = await windowManager.getBounds();
    _restoreBounds = current;

    // 依据窗口当前所在的显示器计算工作区，而不是固定用主显示器，
    // 这样多显示器下也能贴到正确的屏幕边缘。
    final workArea = _workAreaFor(current);
    final top = _clampTop(current.top, current.height, workArea);
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

    // 开启时已经算好几何信息，避免第一次轮询重复计算。
    _lastGeometryRefresh = DateTime.now();

    // 贴边模式下不再占用任务栏，避免隐藏时仍留下一个图标；
    // 同时保持置顶，确保滑出时不会被其他窗口遮住。
    await windowManager.setSkipTaskbar(true);
    await windowManager.setAlwaysOnTop(true);

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
    await windowManager.setSkipTaskbar(false);
    await windowManager.setAlwaysOnTop(false);
    // 恢复位置可能因显示器变化而落到屏幕外，这里做一次钳制兜底。
    await _animateTo(_clampToWorkArea(_restoreBounds, _workAreaFor(_restoreBounds)));
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
    windowManager.setSkipTaskbar(false);
    windowManager.setAlwaysOnTop(false);
  }

  @override
  void onWindowMinimize() {
    if (!_enabled || !Platform.isWindows) return;
    // 贴边模式下窗口不可最小化（任务栏已隐藏，最小化后无从找回），
    // 拦截一切最小化行为（标题栏按钮、Win+D、Win+M、Alt+Space 等）。
    // 注意：这里的 restore 是异步 PostMessage，可能被「显示桌面」的后续操作
    // 覆盖，因此真正可靠的恢复由 _poll 里的 isMinimized 检测兜底。
    unawaited(_recoverFromMinimize());
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
    if (!_enabled) return;

    // 贴边模式下窗口不可最小化：「显示桌面」/Win+D 等会把窗口最小化，
    // 这里主动检测并恢复（不依赖事件时序，比 onWindowMinimize 更可靠）。
    if (await windowManager.isMinimized()) {
      await _recoverFromMinimize();
      return;
    }

    if (_animating) return;

    // 显示器几何信息低频刷新；鼠标检测仍保持高频，保证贴边响应灵敏。
    final now = DateTime.now();
    if (now.difference(_lastGeometryRefresh) >= _geometryRefreshInterval) {
      _lastGeometryRefresh = now;
      await _refreshGeometry();
    }

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

  /// 从最小化状态恢复，并重新贴回屏幕边缘（隐藏）。
  ///
  /// 「显示桌面」会把窗口最小化，而贴边模式下任务栏图标已被隐藏，
  /// 若不恢复窗口将彻底丢失。恢复后统一贴回边缘，避免窗口弹出挡住桌面。
  Future<void> _recoverFromMinimize() async {
    await windowManager.restore();
    // restore 内部是异步 PostMessage，稍等片刻确保恢复完成。
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!_enabled) return;

    // 恢复后先刷新几何信息，确保贴边位置基于最新工作区。
    await _refreshGeometry();
    if (!_enabled) return;

    if (_visible) {
      _visible = false;
      notifyListeners();
    }
    await _animateTo(_dockedBounds);
  }

  /// 根据窗口当前所在显示器重新计算几何信息，
  /// 以应对分辨率变化、任务栏位置变化、显示器插拔等情况。
  Future<void> _refreshGeometry() async {
    final bounds = await windowManager.getBounds();
    final workArea = _workAreaFor(bounds);
    final top = _clampTop(bounds.top, bounds.height, workArea);
    _dockedBounds = Rect.fromLTWH(
      workArea.right - _sliverWidth,
      top,
      bounds.width,
      bounds.height,
    );
    _visibleBounds = Rect.fromLTWH(
      workArea.right - bounds.width,
      top,
      bounds.width,
      bounds.height,
    );
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

  /// 返回包含 [bounds] 中心点的显示器工作区（逻辑像素）。
  Rect _workAreaFor(Rect bounds) {
    final dpr = windowManager.getDevicePixelRatio();
    final centerX = (bounds.left + bounds.width / 2) * dpr;
    final centerY = (bounds.top + bounds.height / 2) * dpr;
    final wa = getMonitorWorkAreaAt(centerX.round(), centerY.round());
    return Rect.fromLTRB(
      wa.left / dpr,
      wa.top / dpr,
      wa.right / dpr,
      wa.bottom / dpr,
    );
  }

  /// 把窗口顶部限制在 [workArea] 内，避免超出可点击/可见范围。
  double _clampTop(double top, double height, Rect workArea) {
    final maxTop = (workArea.bottom - height).clamp(
      workArea.top,
      workArea.bottom,
    );
    return top.clamp(workArea.top, maxTop);
  }

  /// 把窗口整体钳制到 [workArea] 内（窗口大于工作区时退化为尽量靠左上）。
  Rect _clampToWorkArea(Rect bounds, Rect workArea) {
    final maxLeft = (workArea.right - bounds.width).clamp(
      workArea.left,
      workArea.right,
    );
    final maxTop = (workArea.bottom - bounds.height).clamp(
      workArea.top,
      workArea.bottom,
    );
    return Rect.fromLTWH(
      bounds.left.clamp(workArea.left, maxLeft),
      bounds.top.clamp(workArea.top, maxTop),
      bounds.width,
      bounds.height,
    );
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
