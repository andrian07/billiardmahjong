import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/navigation/app_navigation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/formatters.dart';
import '../../models/cashier_summary.dart';
import '../../models/pool_table.dart';
import '../../services/receipt_printer_service.dart';
import '../../services/session_storage.dart';
import '../../shared/widgets/app_layout.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/pin_guard.dart';
import '../cashier/data/cashier_repository.dart';
import 'data/billing_repository.dart';
import 'data/invoice_repository.dart';
import 'data/member_approval_repository.dart';
import 'data/table_repository.dart';
import 'widgets/add_duration_dialog.dart';
import 'widgets/member_approval_wait_dialog.dart';
import 'widgets/move_table_dialog.dart';
import 'widgets/payment_dialog.dart';
import 'widgets/round_up_duration_dialog.dart';
import 'widgets/stat_card.dart';
import 'widgets/start_session_dialog.dart';
import 'widgets/table_card.dart';

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  List<PoolTable> _tables = [];
  String _selectedTableId = "";
  TableStatus? _filter;
  Timer? _ticker;
  bool _loadingTables = true;
  String? _tablesError;
  final _tableRepository = TableRepository();
  final _billingRepository = BillingRepository();
  final _invoiceRepository = InvoiceRepository();
  final _receiptPrinter = ReceiptPrinterService();
  final _sessionStorage = SessionStorage();
  final _cashierRepository = CashierRepository();

  CashierClosingSummary? _cashierSummary;
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    _loadTables();
    _loadCashierSummary();
    _loadRole();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  // "Rincian Transaksi Billing/Cafe" (ringkasan omzet hari ini) hanya untuk owner
  Future<void> _loadRole() async {
    final isOwner = await _sessionStorage.isSuperadmin();
    if (!mounted) return;
    setState(() => _isOwner = isOwner);
  }

  /// Powers the "Rincian Transaksi Billing/Cafe" stat cards — today's
  /// per-cashier totals from Report/get_transaction_today_by_cashier.
  Future<void> _loadCashierSummary() async {
    final session = await _sessionStorage.getSession();
    final userId = int.tryParse(session?['id']?.toString() ?? "") ?? 0;
    if (userId == 0) return;

    try {
      final summary = await _cashierRepository.getTodaySummary(userId: userId);

      if (!mounted) return;
      setState(() => _cashierSummary = summary);
    } on CashierRepositoryException {
      // Silent — stat cards just keep showing the last known totals.
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _refreshAll() {
    _loadTables();
    _loadCashierSummary();
  }

  Future<void> _loadTables() async {
    setState(() {
      _loadingTables = true;
      _tablesError = null;
    });

    try {
      final tables = await _tableRepository.getTables();
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _selectedTableId = tables.isNotEmpty ? tables.first.id : "";
        _loadingTables = false;
      });
    } on TableRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _tablesError = e.message;
        _loadingTables = false;
      });
    }
  }

  // Kalau _sortByTimer aktif (lewat tombol di header, lihat _buildStatusHeader),
  // meja Timer yang sedang berjalan diurutkan berdasarkan sisa waktu tersedikit
  // (paling dekat habis) - supaya kasir bisa langsung lihat meja mana yang perlu
  // segera ditindaklanjuti (tambah durasi/checkout). Meja lain (belum main, atau
  // mode Reguler yang tidak ada batas waktu) tetap di urutan aslinya, ditaruh
  // setelah semua meja Timer yang sedang berjalan. Kalau tidak aktif, urutan asli
  // (dari API) dipakai apa adanya.
  bool _sortByTimer = false;

  Duration? _timerRemaining(PoolTable table) {
    if (table.status != TableStatus.playing) return null;
    if (table.sessionType != SessionType.timer) return null;
    if (table.endAt == null) return null;
    return table.endAt!.difference(DateTime.now());
  }

  List<PoolTable> get _filteredTables {
    final base = _filter == null
        ? _tables
        : _tables.where((t) => t.status == _filter).toList();

    if (!_sortByTimer) return base;

    final sorted = [...base];
    sorted.sort((a, b) {
      final aRemaining = _timerRemaining(a);
      final bRemaining = _timerRemaining(b);
      if (aRemaining == null && bRemaining == null) return 0;
      if (aRemaining == null) return 1;
      if (bRemaining == null) return -1;
      return aRemaining.compareTo(bRemaining);
    });
    return sorted;
  }

  void _selectTable(String id) {
    setState(() => _selectedTableId = id);
  }

  void _finishSession(PoolTable table) {
    final updated = PoolTable(
      id: table.id,
      name: table.name,
      status: TableStatus.ready,
    );
    _replaceTable(updated);
  }

  void _tick() {
    final now = DateTime.now();
    var changed = false;

    final updatedTables = [
      for (final table in _tables)
        if (table.status == TableStatus.playing &&
            (table.endAt != null ||
                (table.sessionType != null && table.startAt != null)))
          _tickTable(table, now, onChanged: () => changed = true)
        else
          table,
    ];

    if (changed) {
      setState(() => _tables = updatedTables);
    }
  }

  /// Timer meja dihitung mundur dari `endAt` (mis. table_end_time dari API)
  /// dikurangi waktu sekarang. Meja tanpa waktu selesai (sesi reguler)
  /// menghitung naik dari `startAt` seperti biasa.
  PoolTable _tickTable(
    PoolTable table,
    DateTime now, {
    required VoidCallback onChanged,
  }) {
    onChanged();

    if (table.endAt != null) {
      final remaining = table.endAt!.difference(now);

      if (remaining <= Duration.zero) {
        // Turning the physical light off is handled by TimerExpiryWatcher,
        // a background poller that runs independently of which page is
        // open (this widget's ticker stops the moment the cashier
        // navigates away — see timer_expiry_watcher.dart for why that
        // used to mean the light stayed on until they came back). This
        // tick only needs to flip the local display to "unpaid".
        return table.copyWith(
          status: TableStatus.unpaid,
          timerText: formatDuration(Duration.zero),
        );
      }

      return table.copyWith(timerText: formatDuration(remaining));
    }

    final elapsed = now.difference(table.startAt!);
    return table.copyWith(timerText: formatDuration(elapsed));
  }

  void _openStartSessionDialog(PoolTable table) async {
    final result = await showDialog<StartSessionResult>(
      context: context,
      builder: (context) => StartSessionDialog(table: table),
    );

    if (result == null) return;

    final now = DateTime.now();
    final endAt = result.duration != null ? now.add(result.duration!) : null;

    try {
      final session = await _sessionStorage.getSession();
      final createdBy = session?['username']?.toString();

      // buka meja pakai waktu tersimpan -> backend menahan sampai member konfirmasi
      // PIN di aplikasi GAMEON. 1 ref dipakai untuk percobaan pertama & ulang.
      final approvalRef = generateApprovalRef();

      Future<void> book({bool ignoreBookingWarning = false}) {
        return _billingRepository.bookTable(
          tableId: table.id,
          mode: result.sessionType,
          startTime: now,
          customerId: result.customerId,
          promoId: result.promoId,
          endTime: endAt,
          duration: result.duration,
          useSavedTime: result.useSavedTime,
          prepaidSaldo: result.prepaidSaldo,
          createdBy: createdBy,
          ignoreBookingWarning: ignoreBookingWarning,
          memberApprovalRef: approvalRef,
        );
      }

      // jalankan book(); kalau backend minta PIN member, tampilkan dialog "menunggu
      // konfirmasi" lalu ulangi book() dengan ref sama setelah disetujui. return
      // false = dibatalkan / ditolak / kadaluarsa (pemanggil berhenti).
      Future<bool> bookWithApproval({bool ignoreBookingWarning = false}) async {
        try {
          await book(ignoreBookingWarning: ignoreBookingWarning);
          return true;
        } on MemberApprovalRequiredException catch (e) {
          if (!mounted) return false;
          final outcome = await showDialog<MemberApprovalOutcome>(
            context: context,
            barrierDismissible: false,
            builder: (_) => MemberApprovalWaitDialog(
              ref: e.ref,
              amount: e.amount,
              expiresAt: e.expiresAt,
            ),
          );
          if (outcome != MemberApprovalOutcome.approved) {
            if (mounted) {
              AppToast.error(context, _bookingApprovalMessage(outcome));
            }
            return false;
          }
          await book(ignoreBookingWarning: ignoreBookingWarning);
          return true;
        }
      }

      try {
        if (!await bookWithApproval()) return;
      } on BookingWarningException catch (w) {
        if (!mounted) return;
        final proceed = await _confirmBookingWarning(table, w.warnings);
        if (proceed != true) return;
        if (!await bookWithApproval(ignoreBookingWarning: true)) return;
      }

      if (!mounted) return;
      AppToast.success(context, "Berhasil membuka ${table.name}");
      setState(() => _selectedTableId = table.id);
      await _loadTables();
    } on BillingRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
  }

  String _bookingApprovalMessage(MemberApprovalOutcome? o) {
    switch (o) {
      case MemberApprovalOutcome.rejected:
        return "Member menolak konfirmasi PIN — meja tidak dibuka";
      case MemberApprovalOutcome.expired:
        return "Waktu konfirmasi PIN member habis — meja tidak dibuka";
      case MemberApprovalOutcome.cancelled:
        return "Konfirmasi PIN member dibatalkan — meja tidak dibuka";
      default:
        return "Konfirmasi PIN member gagal — meja tidak dibuka";
    }
  }

  Future<bool?> _confirmBookingWarning(PoolTable table, List<String> warnings) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
            const SizedBox(width: 10),
            Text("Perlu Diperhatikan", style: AppText.title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final w in warnings) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("•  "),
                  Expanded(child: Text(w, style: AppText.bodySecondary)),
                ],
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            Text(
              "Tetap buka ${table.name}?",
              style: AppText.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            child: const Text("Tetap Buka"),
          ),
        ],
      ),
    );
  }

  void _replaceTable(PoolTable updated) {
    final index = _tables.indexWhere((t) => t.id == updated.id);
    setState(() {
      _tables = [
        for (var i = 0; i < _tables.length; i++)
          if (i == index) updated else _tables[i],
      ];
    });
  }

  void _openPaymentDialog(PoolTable table) async {
    final result = await showDialog<PaymentResult>(
      context: context,
      builder: (context) => PaymentDialog(table: table),
    );

    if (result == null || !mounted) return;

    _finishSession(table);
    AppToast.success(
      context,
      "Pembayaran ${table.name} sebesar ${formatCurrency(result.total)} berhasil via ${result.paymentMethod}",
    );
    _loadCashierSummary();

    try {
      final session = await _sessionStorage.getSession();
      final cashierName = session?['username']?.toString() ?? "Kasir";
      final receipt = await _invoiceRepository.generateInvoice(
        table,
        result,
        cashierName: cashierName,
      );
      await _receiptPrinter.printReceipt(receipt);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Gagal mencetak struk: $e")));
    }
  }

  void _openMoveTableDialog(PoolTable table) async {
    // hanya meja dengan category yang sama yang boleh jadi tujuan (backend Billing::move_table()
    // menolak kalau category beda) - difilter di sini supaya tidak muncul sebagai pilihan sama sekali
    final emptyTables = _tables
        .where(
          (t) =>
              t.status == TableStatus.ready &&
              t.id != table.id &&
              t.categoryMejaId == table.categoryMejaId,
        )
        .toList();

    final targetId = await showDialog<String>(
      context: context,
      builder: (context) =>
          MoveTableDialog(table: table, availableTables: emptyTables),
    );

    if (targetId == null) return;
    await _moveTable(table, targetId);
  }

  Future<void> _moveTable(PoolTable source, String targetId) async {
    try {
      await _billingRepository.moveTable(
        fromTableId: source.id,
        toTableId: targetId,
      );
      if (!mounted) return;
      AppToast.success(context, "Berhasil memindahkan ${source.name}");
      setState(() => _selectedTableId = targetId);
      await _loadTables();
    } on BillingRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
  }

  void _openAddDurationDialog(PoolTable table) async {
    final addition = await showDialog<Duration>(
      context: context,
      builder: (context) => AddDurationDialog(table: table),
    );

    if (addition == null) return;

    try {
      await _billingRepository.addDuration(
        tableId: table.id,
        additionalDuration: addition,
      );
      if (!mounted) return;
      AppToast.success(context, "Berhasil menambah durasi ${table.name}");
      await _loadTables();
    } on BillingRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
  }

  void _openRoundUpDurationDialog(PoolTable table) async {
    final target = await showDialog<Duration>(
      context: context,
      builder: (context) => RoundUpDurationDialog(table: table),
    );

    if (target == null) return;

    try {
      await _billingRepository.roundUpDuration(
        tableId: table.id,
        targetDuration: target,
      );
      if (!mounted) return;
      AppToast.success(context, "Waktu ${table.name} berhasil digenapkan");
      await _loadTables();
    } on BillingRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
  }

  static const _cancelGracePeriod = Duration(minutes: 6);

  // batal meja hanya boleh dalam 6 menit pertama sejak sesi dimulai - sama dengan guard di
  // Billing.php::cancel_table(). Dicek juga di sini supaya tombolnya sudah abu-abu/nonaktif
  // duluan, bukan cuma menunggu backend menolak.
  bool _canCancel(PoolTable table) {
    if (table.startAt == null) return true;
    return DateTime.now().difference(table.startAt!) <= _cancelGracePeriod;
  }

  void _cancelTransaction(PoolTable table) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        ),
        title: Text("Batalkan Transaksi?", style: AppText.title),
        content: Text(
          "Sesi ${table.name} akan dibatalkan dan meja menjadi kosong kembali."
          "${table.usedSavedTime == true ? " Waktu tersimpan yang dipakai akan dikembalikan ke member." : ""}",
          style: AppText.bodySecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("TIDAK"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text("YA, BATALKAN"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    if (!await PinGuard.confirm(context)) return;

    try {
      final session = await _sessionStorage.getSession();
      final createdBy = session?['username']?.toString() ?? "";
      final paidBy = int.tryParse(session?['id']?.toString() ?? "") ?? 0;

      await _billingRepository.cancelTable(
        tableId: table.id,
        createdBy: createdBy,
        paidBy: paidBy,
      );
      if (!mounted) return;
      AppToast.success(context, "Transaksi ${table.name} dibatalkan");
      await _loadTables();
    } on BillingRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: "Billing",
      showSearch: false,
      activeMenuKey: "meja",
      onMenuSelect: (key) => navigateToMenu(context, key),
      onRefresh: _refreshAll,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingTables) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_tablesError != null) {
      return _buildTablesErrorState(_tablesError!);
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isOwner) ...[
            _buildStatsRow(),
            const SizedBox(height: 16),
          ],

          _buildStatusHeader(),

          const SizedBox(height: 16),

          _buildTableGrid(),
        ],
      ),
    );
  }

  Widget _buildTablesErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 30,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.bodySecondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadTables,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text("Coba Lagi"),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final billing = _cashierSummary?.billing ?? CashierTransactionSummary.empty;
    final cafe = _cashierSummary?.cafe ?? CashierTransactionSummary.empty;
    final saldo = _cashierSummary?.saldo ?? CashierTransactionSummary.empty;

    return Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.table_bar_rounded,
            color: AppColors.primary,
            label: "Rincian Transaksi Billing",
            value: formatCurrency(billing.totalTransaction),
            subtitle: "${billing.invoiceCount} nota hari ini",
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatCard(
            icon: Icons.local_cafe_rounded,
            color: AppColors.success,
            label: "Rincian Transaksi Cafe",
            value: formatCurrency(cafe.totalTransaction),
            subtitle: "${cafe.invoiceCount} nota hari ini",
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatCard(
            icon: Icons.savings_outlined,
            color: AppColors.info,
            label: "Total Transaksi Saldo",
            value: formatCurrency(saldo.totalTransaction),
            subtitle: "${saldo.invoiceCount} nota hari ini",
          ),
        ),
      ],
    );
  }

  Widget _buildStatusHeader() {
    return Row(
      children: [
        Text("Status Meja", style: AppText.title),
        const SizedBox(width: 16),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              children: [
                _filterChip("Semua", null),
                const SizedBox(width: 8),
                _filterChip("Playing", TableStatus.playing),
                const SizedBox(width: 8),
                _filterChip("Ready", TableStatus.ready),
                const SizedBox(width: 12),
                _sortByTimerButton(),
                const SizedBox(width: 12),
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(
                    Icons.grid_view_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sortByTimerButton() {
    final active = _sortByTimer;

    return Tooltip(
      message: active
          ? "Urutan: Timer paling dekat habis dulu (klik untuk kembali ke urutan asli)"
          : "Urutkan berdasarkan Timer paling dekat habis",
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _sortByTimer = !_sortByTimer),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 16,
                color: active ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                "Urutkan Timer",
                style: AppText.bodySecondary.copyWith(
                  color: active ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, TableStatus? status) {
    final active = _filter == status;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _filter = status),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppText.bodySecondary.copyWith(
            color: active ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildTableGrid() {
    final tables = _filteredTables;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tables.length,
      // maxCrossAxisExtent (bukan crossAxisCount tetap) supaya jumlah kolom mengikuti lebar layar -
      // di layar besar tambah kolom (card tetap proporsional), bukan 5 card yang meregang lebar sekali
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 230,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        mainAxisExtent: 196,
      ),
      itemBuilder: (context, index) {
        final table = tables[index];

        return TableCard(
          table: table,
          selected: table.id == _selectedTableId,
          onTap: () => table.status == TableStatus.ready
              ? _openStartSessionDialog(table)
              : _selectTable(table.id),
          onPayment: () => _openPaymentDialog(table),
          onMoveTable: () => _openMoveTableDialog(table),
          onAddDuration:
              (table.sessionType == SessionType.timer && !table.hasFixPromo)
              ? () => _openAddDurationDialog(table)
              : null,
          onRoundUpDuration: table.sessionType == SessionType.reguler
              ? () => _openRoundUpDurationDialog(table)
              : null,
          onCancel: _canCancel(table) ? () => _cancelTransaction(table) : null,
        );
      },
    );
  }
}
