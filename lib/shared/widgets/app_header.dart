import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../features/attendance/widgets/absensi_scan_dialog.dart';
import '../../features/billing/data/billing_repository.dart';
import '../../features/cashier/widgets/expense_dialog.dart';
import '../../features/cashier/widgets/tutup_kas_dialog.dart';
import '../../features/topup/widgets/topup_requests_dialog.dart';
import '../../models/pool_table.dart';
import '../../services/booking_watcher.dart';
import '../../services/session_storage.dart';
import '../../services/timer_expiry_watcher.dart';
import '../../services/topup_watcher.dart';
import 'app_toast.dart';

class AppHeader extends StatefulWidget {
  final String title;
  final String? subtitle;
  final bool showSearch;
  final VoidCallback? onRefresh;

  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showSearch = true,
    this.onRefresh,
  });

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  String _username = "";
  String _roleName = "";

  // Diffed against TimerExpiryWatcher.instance.expiredTables on every tick
  // so a toast only fires for a table that JUST expired, not for ones that
  // were already expired before this AppHeader instance mounted (e.g. after
  // navigating to a different page) - see _onExpiredTablesChanged below.
  Set<String> _seenExpiredIds = {};

  @override
  void initState() {
    super.initState();
    _loadSession();
    _seenExpiredIds = TimerExpiryWatcher.instance.expiredTables.value
        .map((t) => t.id)
        .toSet();
    TimerExpiryWatcher.instance.expiredTables.addListener(
      _onExpiredTablesChanged,
    );
  }

  @override
  void dispose() {
    TimerExpiryWatcher.instance.expiredTables.removeListener(
      _onExpiredTablesChanged,
    );
    super.dispose();
  }

  void _onExpiredTablesChanged() {
    final tables = TimerExpiryWatcher.instance.expiredTables.value;
    final newlyExpired = tables
        .where((t) => !_seenExpiredIds.contains(t.id))
        .toList();
    _seenExpiredIds = tables.map((t) => t.id).toSet();
    if (newlyExpired.isEmpty || !mounted) return;

    for (final table in newlyExpired) {
      final pageLabel = table.categoryType == "mahjong" ? "Mahjong" : "Billing";
      AppToast.error(
        context,
        "Waktu ${table.name} ($pageLabel) sudah habis!",
      );
    }
  }

  Future<void> _loadSession() async {
    final session = await SessionStorage().getSession();
    if (!mounted) return;
    setState(() {
      _username = session?['username']?.toString() ?? "";
      _roleName = session?['roleName']?.toString() ?? "";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizes.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.header,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: AppText.heading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.subtitle != null)
                  Text(
                    widget.subtitle!,
                    style: AppText.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          if (widget.showSearch) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: TextField(
                decoration: InputDecoration(
                  hintText: "Search...",
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 20),
          ],

          if (widget.onRefresh != null) ...[
            IconButton(
              tooltip: "Refresh",
              onPressed: widget.onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 8),
          ],

          OutlinedButton.icon(
            onPressed: () => _openExpense(context),
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text("Pengeluaran"),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
            ),
          ),

          const SizedBox(width: 8),

          OutlinedButton.icon(
            onPressed: () => _openAbsensiScan(context),
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
            label: const Text("Absensi"),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
            ),
          ),

          const SizedBox(width: 8),

          OutlinedButton.icon(
            onPressed: () => _openTutupKas(context),
            icon: const Icon(Icons.summarize_rounded, size: 18),
            label: const Text("Tutup Kas"),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
            ),
          ),

          const SizedBox(width: 8),

          ValueListenableBuilder<int>(
            valueListenable: TopupWatcher.instance.unreadCount,
            builder: (context, count, _) {
              return IconButton(
                tooltip: "Permintaan Top Up",
                onPressed: () => _openTopupRequests(context),
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text("$count"),
                  child: const Icon(Icons.notifications_outlined),
                ),
              );
            },
          ),

          const SizedBox(width: 8),

          ValueListenableBuilder<int>(
            valueListenable: BookingWatcher.instance.unreadCount,
            builder: (context, count, _) {
              return IconButton(
                tooltip: "Booking Room",
                onPressed: () => context.go('/booking'),
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text("$count"),
                  child: const Icon(Icons.event_seat_outlined),
                ),
              );
            },
          ),

          const SizedBox(width: 8),

          ValueListenableBuilder<List<PoolTable>>(
            valueListenable: TimerExpiryWatcher.instance.expiredTables,
            builder: (context, tables, _) {
              return IconButton(
                tooltip: tables.isEmpty
                    ? "Tidak ada meja timer habis"
                    : "${tables.length} meja timer habis",
                onPressed: tables.isEmpty
                    ? null
                    : () => _openExpiredTables(context, tables),
                icon: Badge(
                  isLabelVisible: tables.isNotEmpty,
                  label: Text("${tables.length}"),
                  backgroundColor: AppColors.danger,
                  child: Icon(
                    Icons.alarm_rounded,
                    color: tables.isNotEmpty
                        ? AppColors.danger
                        : AppColors.textSecondary,
                  ),
                ),
              );
            },
          ),

          const SizedBox(width: 8),

          IconButton(
            tooltip: "Reset Lampu",
            onPressed: () => _resetLampu(context),
            icon: const Icon(Icons.lightbulb_outline),
          ),

          const SizedBox(width: 8),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(child: Icon(Icons.person)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _username.isNotEmpty ? _username : "...",
                    style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (_roleName.isNotEmpty)
                    Text(_roleName, style: AppText.caption),
                ],
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openTopupRequests(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const TopupRequestsDialog(),
    );
  }

  void _openExpiredTables(BuildContext context, List<PoolTable> tables) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.alarm_rounded, color: AppColors.danger),
            const SizedBox(width: 10),
            Text("Timer Habis (${tables.length})", style: AppText.title),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: tables.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppColors.divider),
              itemBuilder: (context, index) {
                final table = tables[index];
                final isMahjong = table.categoryType == "mahjong";
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isMahjong
                        ? Icons.casino_outlined
                        : Icons.table_bar_rounded,
                    color: AppColors.danger,
                  ),
                  title: Text(
                    table.name,
                    style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    isMahjong ? "Mahjong" : "Billing",
                    style: AppText.caption,
                  ),
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    context.go(isMahjong ? '/mahjong' : '/meja');
                  },
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text("TUTUP"),
          ),
        ],
      ),
    );
  }

  void _openAbsensiScan(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const AbsensiScanDialog(),
    );
  }

  Future<void> _openExpense(BuildContext context) async {
    final session = await SessionStorage().getSession();
    final userId = int.tryParse(session?['id']?.toString() ?? "") ?? 0;
    final cashierName = session?['username']?.toString() ?? "Kasir";

    if (!context.mounted) return;
    if (userId == 0) {
      AppToast.error(context, "Sesi tidak valid, silakan login ulang.");
      return;
    }
    showDialog(
      context: context,
      builder: (_) => ExpenseDialog(userId: userId, cashierName: cashierName),
    );
  }

  Future<void> _openTutupKas(BuildContext context) async {
    final session = await SessionStorage().getSession();
    final userId = int.tryParse(session?['id']?.toString() ?? "") ?? 0;
    final cashierName = session?['username']?.toString() ?? "Kasir";

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => TutupKasDialog(userId: userId, cashierName: cashierName),
    );
  }

  Future<void> _resetLampu(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        ),
        title: Text("Reset Lampu Meja?", style: AppText.title),
        content: Text(
          "Lampu setiap meja akan disinkronkan ulang sesuai status saat ini, "
          "diproses satu per satu. Proses ini butuh beberapa detik dan tidak "
          "bisa dibatalkan di tengah jalan.",
          style: AppText.bodySecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("BATAL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text("YA, RESET"),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // Non-dismissible: the barrier itself blocks every button underneath
    // (tap and keyboard) for as long as the sequential relay reset is
    // running on the backend.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text("Mereset lampu meja...", style: AppText.body),
              ],
            ),
          ),
        ),
      ),
    );

    String? errorMessage;
    var resultMessage = "Reset lampu selesai";
    try {
      resultMessage = await BillingRepository().resetLampu();
    } on BillingRepositoryException catch (e) {
      errorMessage = e.message;
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (errorMessage != null) {
      AppToast.error(context, errorMessage);
      return;
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.success),
            const SizedBox(width: 10),
            Text("Berhasil", style: AppText.title),
          ],
        ),
        content: Text(resultMessage, style: AppText.bodySecondary),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }
}
