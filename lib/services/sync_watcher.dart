import 'dart:async';

import '../features/sync/data/sync_repository.dart';

/// Polls in the background for local rows that never made it to the online
/// report (gameon) — billing/cafe/saldo transactions and pembelian whose
/// `*_upload_status` is still 'N' (see Sync/pending, Sync/retry in
/// billing_api) — and retries them automatically, regardless of which page
/// is open.
///
/// Same lifecycle as [BookingWatcher] / [TimerExpiryWatcher]: a singleton
/// started once from [AppLayout] (idempotent) and stopped on logout, so a
/// gameon outage keeps getting retried no matter which page the cashier is
/// on, not just while the Sinkron Online page happens to be open.
///
/// Every tick starts with a cheap 4x COUNT(*) (Sync/pending_count) so the
/// (near-always) case of nothing pending stays lightweight; retries only
/// run when that count is actually > 0.
class SyncWatcher {
  SyncWatcher._();

  static final instance = SyncWatcher._();

  static const _pollInterval = Duration(seconds: 3);

  /// One page's worth of pending rows retried per tick — a genuinely long
  /// gameon outage drains across several ticks instead of one tick trying
  /// to push everything at once.
  static const _batchSize = 10;

  final _repository = SyncRepository();

  Timer? _timer;
  bool _checking = false;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_pollInterval, (_) => _check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;

    try {
      final counts = await _repository.getPendingCount();
      if (counts.total <= 0) return;

      final pending = await _repository.getPending(page: 1, perPage: _batchSize);
      for (final item in pending.items) {
        try {
          await _repository.retry(type: item.type, id: item.id);
        } on SyncRepositoryException {
          // Masih gagal (gameon belum kembali, dsb) - dibiarkan, dicoba lagi
          // tick berikutnya. Baris lain di batch ini tetap dilanjutkan.
        }
      }
    } catch (_) {
      // billing_api sendiri tidak terjangkau, dsb - coba lagi tick berikutnya.
    } finally {
      _checking = false;
    }
  }
}
