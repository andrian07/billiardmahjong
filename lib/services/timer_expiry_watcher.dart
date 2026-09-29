import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/billing/data/billing_repository.dart';
import '../features/billing/data/table_repository.dart';
import '../models/pool_table.dart';

/// Polls the table list in the background and signals a Timer-mode table's
/// relay off the moment its countdown reaches zero — regardless of which
/// page is currently open.
///
/// Previously this only happened via a per-second UI tick owned by
/// [BillingPage] (see billing_page.dart), so it stopped the instant the
/// cashier navigated to any other page (POS, Transaksi, ...) since that
/// page's widget — and its [Timer.periodic] — got disposed. This watcher is
/// a singleton started once from [AppLayout] (idempotent — every page
/// mounting it just no-ops after the first) and stopped on logout, so it
/// keeps running across every page for as long as the user is logged in.
class TimerExpiryWatcher {
  TimerExpiryWatcher._();

  static final instance = TimerExpiryWatcher._();

  static const _pollInterval = Duration(seconds: 5);

  final _tableRepository = TableRepository();
  final _billingRepository = BillingRepository();

  Timer? _timer;
  bool _checking = false;

  /// Tables currently sitting in an expired-Timer state, refreshed every
  /// tick — drives the alarm badge in AppHeader (see app_header.dart) so a
  /// cashier notices regardless of which page (Billing, Mahjong, POS, ...)
  /// they're currently on, since a billiard table's relay light is the only
  /// other cue and mahjong tables don't even have one (relay_number = 0).
  final expiredTables = ValueNotifier<List<PoolTable>>(const []);

  // Tables already signaled for their *current* expiry, so a slow/offline
  // tick doesn't re-signal the same expiry repeatedly. Cleared per table as
  // soon as it's no longer sitting in an expired-Timer state (paid,
  // canceled, extended, ...) so the next booking on that same table id gets
  // signaled fresh.
  final Set<String> _notifiedTableIds = {};

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_pollInterval, (_) => _check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _notifiedTableIds.clear();
    expiredTables.value = const [];
  }

  Future<void> _check() async {
    // A slow response (or a burst of ticks after the app was backgrounded)
    // must not pile up overlapping requests.
    if (_checking) return;
    _checking = true;

    try {
      final tables = await _tableRepository.getTables();
      final now = DateTime.now();
      final currentlyExpired = <String>{};
      final expiredList = <PoolTable>[];

      for (final table in tables) {
        final isExpiredTimer =
            table.status == TableStatus.playing &&
            table.sessionType == SessionType.timer &&
            table.endAt != null &&
            !table.endAt!.isAfter(now);
        if (!isExpiredTimer) continue;

        currentlyExpired.add(table.id);
        expiredList.add(table);
        if (_notifiedTableIds.contains(table.id)) continue;

        try {
          await _billingRepository.notifyTimerExpired(tableId: table.id);
          _notifiedTableIds.add(table.id);
        } catch (_) {
          // Best-effort — not marked notified, so the next tick retries.
        }
      }

      _notifiedTableIds.retainWhere(currentlyExpired.contains);
      expiredTables.value = expiredList;
    } catch (_) {
      // Table list fetch failed (offline, server hiccup, ...) — try again
      // on the next tick.
    } finally {
      _checking = false;
    }
  }
}
