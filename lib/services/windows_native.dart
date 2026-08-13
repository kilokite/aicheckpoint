import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Windows 原生 API 封装（user32.dll）。
///
/// 仅用于「贴边模式」等需要读取全局鼠标位置与屏幕工作区的场景。
/// 所有函数在非 Windows 平台上安全地返回空值，调用方需自行判断。
final class _Point extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;
}

final class _Rect extends Struct {
  @Int32()
  external int left;

  @Int32()
  external int top;

  @Int32()
  external int right;

  @Int32()
  external int bottom;
}

final class _MonitorInfo extends Struct {
  @Uint32()
  external int cbSize;

  external _Rect rcMonitor;

  external _Rect rcWork;

  @Uint32()
  external int dwFlags;
}

typedef _GetCursorPosC = Int32 Function(Pointer<_Point>);
typedef _GetCursorPosDart = int Function(Pointer<_Point>);

typedef _GetSystemMetricsC = Int32 Function(Int32);
typedef _GetSystemMetricsDart = int Function(int);

typedef _SystemParametersInfoC = Int32 Function(
  Uint32,
  Uint32,
  Pointer<_Rect>,
  Uint32,
);
typedef _SystemParametersInfoDart = int Function(
  int,
  int,
  Pointer<_Rect>,
  int,
);

typedef _MonitorFromPointC = IntPtr Function(_Point, Uint32);
typedef _MonitorFromPointDart = int Function(_Point, int);

typedef _GetMonitorInfoC = Int32 Function(IntPtr, Pointer<_MonitorInfo>);
typedef _GetMonitorInfoDart = int Function(int, Pointer<_MonitorInfo>);

DynamicLibrary? _user32;
_GetCursorPosDart? _getCursorPos;
_GetSystemMetricsDart? _getSystemMetrics;
_SystemParametersInfoDart? _systemParametersInfo;
_MonitorFromPointDart? _monitorFromPoint;
_GetMonitorInfoDart? _getMonitorInfo;

const int _smCxScreen = 0;
const int _smCyScreen = 1;
const int _spiGetWorkArea = 0x0030;

/// 找不到显示器时返回距离最近的显示器（用于窗口因分辨率变化等原因跑到屏幕外时兜底）。
const int _monitorDefaultToNearest = 2;

void _ensureLoaded() {
  if (!Platform.isWindows || _user32 != null) return;
  final lib = DynamicLibrary.open('user32.dll');
  _user32 = lib;
  _getCursorPos = lib
      .lookupFunction<_GetCursorPosC, _GetCursorPosDart>('GetCursorPos');
  _getSystemMetrics = lib
      .lookupFunction<_GetSystemMetricsC, _GetSystemMetricsDart>(
        'GetSystemMetrics',
      );
  _systemParametersInfo = lib.lookupFunction<_SystemParametersInfoC,
      _SystemParametersInfoDart>('SystemParametersInfoA');
  _monitorFromPoint = lib.lookupFunction<_MonitorFromPointC,
      _MonitorFromPointDart>('MonitorFromPoint');
  _getMonitorInfo = lib.lookupFunction<_GetMonitorInfoC, _GetMonitorInfoDart>(
    'GetMonitorInfo',
  );
}

/// 全局鼠标位置（物理像素）。非 Windows 返回 (0, 0)。
({int x, int y}) getGlobalCursorPosition() {
  if (!Platform.isWindows) return (x: 0, y: 0);
  _ensureLoaded();
  final point = calloc<_Point>();
  try {
    _getCursorPos!(point);
    return (x: point.ref.x, y: point.ref.y);
  } finally {
    calloc.free(point);
  }
}

/// 主显示器尺寸（物理像素）。非 Windows 返回 (0, 0)。
({int width, int height}) getPrimaryScreenSize() {
  if (!Platform.isWindows) return (width: 0, height: 0);
  _ensureLoaded();
  return (
    width: _getSystemMetrics!(_smCxScreen),
    height: _getSystemMetrics!(_smCyScreen),
  );
}

/// 主显示器工作区（物理像素，不含任务栏）。非 Windows 返回全 0。
({int left, int top, int right, int bottom}) getPrimaryWorkArea() {
  if (!Platform.isWindows) return (left: 0, top: 0, right: 0, bottom: 0);
  _ensureLoaded();
  final rect = calloc<_Rect>();
  try {
    _systemParametersInfo!(_spiGetWorkArea, 0, rect, 0);
    return (
      left: rect.ref.left,
      top: rect.ref.top,
      right: rect.ref.right,
      bottom: rect.ref.bottom,
    );
  } finally {
    calloc.free(rect);
  }
}

/// 包含指定物理坐标的显示器工作区（物理像素，不含任务栏）。
///
/// 若该点不在任何显示器内，则返回距离最近的显示器（避免窗口跑出屏幕后无法找回）。
/// 非 Windows 返回全 0。
({int left, int top, int right, int bottom}) getMonitorWorkAreaAt(
  int x,
  int y,
) {
  if (!Platform.isWindows) return (left: 0, top: 0, right: 0, bottom: 0);
  _ensureLoaded();
  final point = calloc<_Point>();
  final info = calloc<_MonitorInfo>();
  try {
    point.ref.x = x;
    point.ref.y = y;
    final monitor = _monitorFromPoint!(point.ref, _monitorDefaultToNearest);
    if (monitor == 0) return getPrimaryWorkArea();
    info.ref.cbSize = sizeOf<_MonitorInfo>();
    _getMonitorInfo!(monitor, info);
    return (
      left: info.ref.rcWork.left,
      top: info.ref.rcWork.top,
      right: info.ref.rcWork.right,
      bottom: info.ref.rcWork.bottom,
    );
  } finally {
    calloc.free(point);
    calloc.free(info);
  }
}
