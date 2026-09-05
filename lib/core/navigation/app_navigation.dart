import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/booking_watcher.dart';
import '../../services/session_storage.dart';
import '../../services/sync_watcher.dart';
import '../../services/timer_expiry_watcher.dart';
import '../../services/topup_watcher.dart';

const _routesByKey = {
  'meja': '/meja',
  'pos': '/pos',
  'transaksi': '/transaksi',
  'booking': '/booking',
  'pengguna': '/pengguna',
  'role': '/role',
  'pelanggan': '/pelanggan',
  'pengaturan': '/pengaturan',
  'promo': '/promo',
  'produk': '/produk',
  'pembelian': '/pembelian',
  'laporan_billing': '/laporan/billing',
  'laporan_cafe': '/laporan/cafe',
  'laporan_saldo': '/laporan/saldo',
  'laporan_stok': '/laporan/stok',
  'laporan_pembelian': '/laporan/pembelian',
  'sync_online': '/sync-online',
  'unit': '/unit',
  'kategori': '/kategori',
  'setting_table': '/setting/table',
  'setting_game': '/setting/game',
  'setting_broadcast': '/setting/broadcast',
  'setting_point_exchange': '/setting/point-exchange',
  'ganti_password': '/setting/ganti-password',
  'opname': '/opname',
};

Future<void> navigateToMenu(BuildContext context, String key) async {
  if (key == 'logout') {
    TimerExpiryWatcher.instance.stop();
    TopupWatcher.instance.stop();
    BookingWatcher.instance.stop();
    SyncWatcher.instance.stop();
    await SessionStorage().clearSession();
    if (context.mounted) context.go('/login');
    return;
  }

  final route = _routesByKey[key];
  if (route == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Fitur ini akan segera hadir")),
    );
    return;
  }

  context.go(route);
}
