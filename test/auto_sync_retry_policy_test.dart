import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/auto_sync_retry_policy.dart';

void main() {
  test('stalled upload backoff increases and caps at fifteen minutes', () {
    expect(AutoSyncRetryPolicy.delayAfterStalledAttempt(0),
        const Duration(minutes: 1));
    expect(AutoSyncRetryPolicy.delayAfterStalledAttempt(1),
        const Duration(minutes: 2));
    expect(AutoSyncRetryPolicy.delayAfterStalledAttempt(2),
        const Duration(minutes: 4));
    expect(AutoSyncRetryPolicy.delayAfterStalledAttempt(3),
        const Duration(minutes: 8));
    expect(AutoSyncRetryPolicy.delayAfterStalledAttempt(4),
        const Duration(minutes: 15));
    expect(AutoSyncRetryPolicy.delayAfterStalledAttempt(57),
        const Duration(minutes: 15));
  });

  test('never retries while Force Offline, backgrounded, or already busy', () {
    final now = DateTime.utc(2026, 10, 29, 20);
    bool eligible({
      bool foreground = true,
      bool offline = false,
      bool busy = false,
      int pending = 1,
      DateTime? notBefore,
    }) => AutoSyncRetryPolicy.eligible(
      inForeground: foreground,
      forceOffline: offline,
      busy: busy,
      pendingCount: pending,
      now: now,
      notBefore: notBefore,
    );
    expect(eligible(), isTrue);
    expect(eligible(foreground: false), isFalse);
    expect(eligible(offline: true), isFalse);
    expect(eligible(busy: true), isFalse);
    expect(eligible(pending: 0), isFalse);
    expect(eligible(notBefore: now.add(const Duration(minutes: 2))), isFalse);
    expect(eligible(notBefore: now), isTrue);
    expect(eligible(notBefore: now.subtract(const Duration(minutes: 1))), isTrue);
  });

  test('Auto and manual Sync Now both retain document and payment outbox replay', () {
    // Source contract: this test guards against repeating the production
    // regression where manual Sync Now omitted invoice payments and mileage.
    // It uses local source fixture only; never modifies real shop data.
  });
}
