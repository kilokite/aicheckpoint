import 'package:checkpoint/models/gc_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('progress uses the closer of loose objects and packs', () {
    const status = GcStatus(
      looseObjectCount: 3350,
      packCount: 1,
      autoThreshold: 6700,
      packLimit: 50,
    );
    expect(status.progress, closeTo(0.5, 0.0001));
    expect(status.exceeds, isFalse);
    expect(status.remainingDescription, contains('3350'));
    expect(status.remainingDescription, contains('松散对象'));
  });

  test('exceeds when either threshold is met', () {
    const status = GcStatus(
      looseObjectCount: 7000,
      packCount: 2,
      autoThreshold: 6700,
      packLimit: 50,
    );
    expect(status.exceeds, isTrue);
    expect(status.progress, 1.0);
    expect(status.remainingDescription, contains('已达到'));
  });

  test('pack distance shown when packs are closer to their limit', () {
    const status = GcStatus(
      looseObjectCount: 100,
      packCount: 40,
      autoThreshold: 6700,
      packLimit: 50,
    );
    expect(status.progress, closeTo(0.8, 0.0001));
    expect(status.remainingDescription, contains('pack'));
  });

  test('disabled when a threshold is zero', () {
    const status = GcStatus(
      looseObjectCount: 3,
      packCount: 0,
      autoThreshold: 0,
      packLimit: 50,
    );
    expect(status.autoGcDisabled, isTrue);
    expect(status.progress, 0.0);
    expect(status.remainingDescription, contains('禁用'));
  });
}
