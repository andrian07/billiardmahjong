import 'dart:async';

import '../features/product/data/product_repository.dart';
import 'session_storage.dart';

/// Pushes a full snapshot of this branch's product catalog (stock &
/// HPP/COGS) to gameon every 30 minutes, so the central "laporan online"
/// always has a recent-enough view of stock/COGS even on branches that go
/// long stretches without a cafe sale or stock purchase to trigger a push.
///
/// Same lifecycle as [SyncWatcher] / [BookingWatcher]: a singleton started
/// once from [AppLayout] (idempotent) and stopped on logout. The push itself
/// is self-healing (see Master::sync_product_stock() in billing_api) — it
/// always sends the current full catalog, so a failed tick just gets
/// overwritten by the next one 30 minutes later, no separate retry needed.
class ProductStockSyncWatcher {
  ProductStockSyncWatcher._();

  static final instance = ProductStockSyncWatcher._();

  static const _pollInterval = Duration(minutes: 30);

  final _repository = ProductRepository();

  Timer? _timer;
  bool _syncing = false;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_pollInterval, (_) => _sync());
    _sync(); // also push right away, don't wait 30 minutes for the first one
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _sync() async {
    if (_syncing) return;
    _syncing = true;

    try {
      final branch = await SessionStorage().getBranch();
      await _repository.syncStockToGameon(branch: branch);
    } catch (_) {
      // gameon/billing_api hiccup - dibiarkan, snapshot penuh dicoba lagi
      // tick berikutnya (30 menit lagi).
    } finally {
      _syncing = false;
    }
  }
}
