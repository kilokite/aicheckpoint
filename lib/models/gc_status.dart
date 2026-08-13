import 'dart:math';

/// Git 自动 GC 距离状态。
///
/// Git 在 `git gc --auto` 被触发时自动回收不可达对象，阈值由两个配置决定：
/// - `gc.auto`：松散对象数量，默认 6700，设为 0 表示禁用；
/// - `gc.autoPackLimit`：pack 文件数量，默认 50，设为 0 表示禁用该触发。
///
/// 整体进度取两项中更接近阈值的一项，即"离自动 GC 最近的那条路还有多远"。
class GcStatus {
  const GcStatus({
    required this.looseObjectCount,
    required this.packCount,
    required this.autoThreshold,
    required this.packLimit,
  });

  /// 当前松散对象数量（`git count-objects -v` 的 count）。
  final int looseObjectCount;

  /// 当前 pack 文件数量（`git count-objects -v` 的 packs）。
  final int packCount;

  /// `gc.auto` 配置值，未配置时为默认值 6700。
  final int autoThreshold;

  /// `gc.autoPackLimit` 配置值，未配置时为默认值 50。
  final int packLimit;

  bool get autoGcDisabled => autoThreshold <= 0 || packLimit <= 0;

  double get _looseProgress =>
      autoThreshold <= 0 ? 0 : looseObjectCount / autoThreshold;

  double get _packProgress => packLimit <= 0 ? 0 : packCount / packLimit;

  /// 距离自动 GC 的整体进度（0..1），取松散对象与 pack 中更接近阈值的一项。
  double get progress =>
      max(_looseProgress, _packProgress).clamp(0.0, 1.0).toDouble();

  bool get exceeds => _looseProgress >= 1.0 || _packProgress >= 1.0;

  /// 人类可读的剩余距离描述。
  String get remainingDescription {
    if (autoGcDisabled) return '自动 GC 已禁用';
    if (exceeds) return '已达到自动 GC 阈值';
    final remainingObjects = autoThreshold - looseObjectCount;
    final remainingPacks = packLimit - packCount;
    if (_looseProgress >= _packProgress) {
      return '还差 $remainingObjects 个松散对象触发自动 GC';
    }
    return '还差 $remainingPacks 个 pack 文件触发自动 GC';
  }

  /// 用于悬浮提示的详细说明。
  String get tooltip =>
      '松散对象 $looseObjectCount / $autoThreshold，'
      'pack $packCount / $packLimit。$remainingDescription';
}
