import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_page.dart';
import '../../features/billing/billing_page.dart';
import '../../features/booking/booking_page.dart';
import '../../features/category/category_page.dart';
import '../../features/customer/customer_page.dart';
import '../../features/opname/opname_add_page.dart';
import '../../features/opname/opname_page.dart';
import '../../features/pos/pos_page.dart';
import '../../features/product/product_page.dart';
import '../../features/promo/promo_page.dart';
import '../../features/purchase/purchase_add_page.dart';
import '../../features/purchase/purchase_page.dart';
import '../../features/report/billing_report_page.dart';
import '../../features/report/cafe_report_page.dart';
import '../../features/report/purchase_report_page.dart';
import '../../features/report/saldo_report_page.dart';
import '../../features/report/stock_report_page.dart';
import '../../features/sync/sync_page.dart';
import '../../features/role/role_page.dart';
import '../../features/settings/change_password_page.dart';
import '../../features/settings/point_exchange_page.dart';
import '../../features/settings/saldo_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/settings/table_setting_page.dart';
import '../../features/transaction/transaction_page.dart';
import '../../features/unit/unit_page.dart';
import '../../features/user/user_page.dart';
import '../../services/session_storage.dart';

final _sessionStorage = SessionStorage();

CustomTransitionPage<void> _fadeThroughPage(Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, .02),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: .98, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Route paths are the source of truth for "which page am I on" — the
/// browser keeps this in the URL (as a `#/...` fragment), so a page reload
/// re-enters the same route instead of always restarting at the login page.
final appRouter = GoRouter(
  initialLocation: "/meja",
  redirect: (context, state) async {
    final loggedIn = await _sessionStorage.hasSession();
    final loggingIn = state.matchedLocation == "/login";

    if (!loggedIn && !loggingIn) return "/login";
    if (loggedIn && loggingIn) return "/meja";
    return null;
  },
  routes: [
    GoRoute(path: "/", redirect: (context, state) => "/meja"),
    GoRoute(
      path: "/login",
      pageBuilder: (context, state) => _fadeThroughPage(const LoginPage()),
    ),
    GoRoute(
      path: "/meja",
      // key beda dari /mahjong di bawah WAJIB ada - tanpa ini Flutter menganggap kedua
      // BillingPage ini widget yang "sama" (tipe sama, tidak ada key) dan cuma meng-update
      // instance lama saat pindah route alih-alih membuat baru, jadi initState()/_loadTables()
      // tidak pernah jalan ulang dan daftar meja nyangkut di data halaman yang dibuka duluan.
      pageBuilder: (context, state) => _fadeThroughPage(
        const BillingPage(key: ValueKey("meja")),
      ),
    ),
    GoRoute(
      path: "/mahjong",
      pageBuilder: (context, state) => _fadeThroughPage(
        const BillingPage(
          key: ValueKey("mahjong"),
          categoryType: "mahjong",
          pageTitle: "Mahjong",
          menuKey: "mahjong",
        ),
      ),
    ),
    GoRoute(
      path: "/pos",
      pageBuilder: (context, state) => _fadeThroughPage(const PosPage()),
    ),
    GoRoute(
      path: "/transaksi",
      pageBuilder: (context, state) =>
          _fadeThroughPage(const TransactionPage()),
    ),
    GoRoute(
      path: "/booking",
      pageBuilder: (context, state) => _fadeThroughPage(const BookingPage()),
    ),
    GoRoute(
      path: "/pengguna",
      pageBuilder: (context, state) => _fadeThroughPage(const UserPage()),
    ),
    GoRoute(
      path: "/role",
      pageBuilder: (context, state) => _fadeThroughPage(const RolePage()),
    ),
    GoRoute(
      path: "/pelanggan",
      pageBuilder: (context, state) => _fadeThroughPage(const CustomerPage()),
    ),
    GoRoute(
      path: "/pengaturan",
      pageBuilder: (context, state) => _fadeThroughPage(const SettingsPage()),
    ),
    GoRoute(
      path: "/promo",
      pageBuilder: (context, state) => _fadeThroughPage(const PromoPage()),
    ),
    GoRoute(
      path: "/produk",
      pageBuilder: (context, state) => _fadeThroughPage(const ProductPage()),
    ),
    GoRoute(
      path: "/pembelian",
      pageBuilder: (context, state) => _fadeThroughPage(const PurchasePage()),
    ),
    GoRoute(
      path: "/pembelian/tambah",
      pageBuilder: (context, state) =>
          _fadeThroughPage(const PurchaseAddPage()),
    ),
    GoRoute(
      path: "/opname",
      pageBuilder: (context, state) => _fadeThroughPage(const OpnamePage()),
    ),
    GoRoute(
      path: "/opname/tambah",
      pageBuilder: (context, state) =>
          _fadeThroughPage(const OpnameAddPage()),
    ),
    GoRoute(
      path: "/laporan/billing",
      pageBuilder: (context, state) =>
          _fadeThroughPage(const BillingReportPage()),
    ),
    GoRoute(
      path: "/laporan/cafe",
      pageBuilder: (context, state) =>
          _fadeThroughPage(const CafeReportPage()),
    ),
    GoRoute(
      path: "/laporan/saldo",
      pageBuilder: (context, state) =>
          _fadeThroughPage(const SaldoReportPage()),
    ),
    GoRoute(
      path: "/laporan/stok",
      pageBuilder: (context, state) =>
          _fadeThroughPage(const StockReportPage()),
    ),
    GoRoute(
      path: "/laporan/pembelian",
      pageBuilder: (context, state) =>
          _fadeThroughPage(const PurchaseReportPage()),
    ),
    GoRoute(
      path: "/sync-online",
      pageBuilder: (context, state) => _fadeThroughPage(const SyncPage()),
    ),
    GoRoute(
      path: "/unit",
      pageBuilder: (context, state) => _fadeThroughPage(const UnitPage()),
    ),
    GoRoute(
      path: "/kategori",
      pageBuilder: (context, state) => _fadeThroughPage(const CategoryPage()),
    ),
    GoRoute(
      path: "/setting/table",
      pageBuilder: (context, state) =>
          _fadeThroughPage(const TableSettingPage()),
    ),
    GoRoute(
      path: "/setting/ganti-password",
      pageBuilder: (context, state) =>
          _fadeThroughPage(const ChangePasswordPage()),
    ),
    GoRoute(
      path: "/setting/point-exchange",
      pageBuilder: (context, state) =>
          _fadeThroughPage(const PointExchangePage()),
    ),
    GoRoute(
      path: "/setting/saldo",
      pageBuilder: (context, state) => _fadeThroughPage(const SaldoPage()),
    ),
  ],
);
