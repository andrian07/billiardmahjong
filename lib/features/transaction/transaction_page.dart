import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/business_info.dart';
import '../../core/navigation/app_navigation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/formatters.dart';
import '../../models/payment_method.dart';
import '../../models/pool_table.dart';
import '../../models/receipt.dart';
import '../../models/transaction.dart';
import '../../services/receipt_printer_service.dart';
import '../../services/session_storage.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_layout.dart';
import '../../shared/widgets/app_toast.dart';
import 'data/transaction_repository.dart';
import 'widgets/cafe_transaction_list.dart';
import 'widgets/edit_payment_dialog.dart';
import 'widgets/saldo_transaction_list.dart';
import 'widgets/transaction_detail_dialog.dart';

class TransactionPage extends StatefulWidget {
  const TransactionPage({super.key});

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

enum _SortField { date, total }

enum _TransactionTab { billing, cafe, saldo }

class _TransactionPageState extends State<TransactionPage> {
  static const _pageSize = 10;

  final _repository = TransactionRepository();
  final _receiptPrinter = ReceiptPrinterService();
  final _searchController = TextEditingController();
  final _cafeListKey = GlobalKey<CafeTransactionListState>();

  _TransactionTab _tab = _TransactionTab.billing;

  List<Transaction> _transactions = [];
  bool _loading = true;
  String? _loadError;
  String _search = "";
  DateTime? _startDate;
  DateTime? _endDate;
  int _page = 0;
  _SortField _sortField = _SortField.date;
  bool _sortAscending = false;
  int? _reprintingId;
  int? _editingPaymentId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Reloads whichever tab's data — the billing list always, and the cafe
  /// list too if it has already mounted (it manages its own state).
  void _refreshAll() {
    _load();
    _cafeListKey.currentState?.refresh();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final transactions = await _repository.getCompletedTransactions();
      if (!mounted) return;
      setState(() {
        _transactions = transactions;
        _loading = false;
      });
    } on TransactionRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _reprintReceipt(Transaction transaction) async {
    if (_reprintingId != null) return;

    setState(() => _reprintingId = transaction.id);
    try {
      final detail = await _repository.getTransactionDetail(transaction.id);

      // detail.tableName datang sebagai "Meja <table_number>" (mis. "Meja Private
      // 1", "Meja VVIP") - "Meja" dilepas di sini karena strukLayout sudah
      // menaruh label "Meja" sendiri di kolom sebelahnya (lihat TicketLayout.row).
      final tableNumber = detail.tableName.replaceFirst(
        RegExp(r'^Meja\s*', caseSensitive: false),
        '',
      );
      final modeLabel = switch (detail.mode) {
        SessionType.timer => "Timer",
        SessionType.reguler => "Reguler",
        null => "-",
      };

      await _receiptPrinter.printReceipt(
        Receipt(
          businessName: BusinessInfo.name,
          businessAddress: BusinessInfo.address,
          invoiceNumber: detail.invoiceNumber,
          tableLabel: "$tableNumber - $modeLabel",
          periods: const [],
          date: detail.date,
          startAt: detail.startAt,
          endAt: detail.endAt,
          totalDuration: detail.endAt.difference(detail.startAt),
          subtotal: detail.subTotal,
          discountAmount: detail.discount,
          promoName: detail.promoName,
          grandTotal: detail.totalBill,
          paymentMethod: detail.paymentMethod,
          cashierName: detail.createdBy,
          isReprint: true,
        ),
      );

      if (!mounted) return;
      AppToast.success(context, "Struk ${transaction.invoiceNumber} berhasil dicetak ulang");
    } on TransactionRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, "Gagal mencetak ulang: $e");
    } finally {
      if (mounted) setState(() => _reprintingId = null);
    }
  }

  Future<void> _editPayment(Transaction transaction) async {
    if (_editingPaymentId != null) return;

    final result = await showDialog<PaymentMethod>(
      context: context,
      builder: (_) => EditPaymentDialog(
        invoiceNumber: transaction.invoiceNumber,
        currentPaymentId: transaction.paymentId,
        currentPaymentName: transaction.paymentMethod,
      ),
    );
    if (result == null) return;

    setState(() => _editingPaymentId = transaction.id);
    try {
      final session = await SessionStorage().getSession();
      final createdBy = session?['username']?.toString() ?? "";
      await _repository.editBillingPayment(
        transactionId: transaction.id,
        paymentId: result.id,
        createdBy: createdBy,
      );
      if (!mounted) return;
      AppToast.success(
        context,
        "Metode pembayaran ${transaction.invoiceNumber} diubah ke ${result.name}",
      );
      await _load();
    } on TransactionRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } finally {
      if (mounted) setState(() => _editingPaymentId = null);
    }
  }

  void _openDetail(Transaction transaction) {
    showDialog<void>(
      context: context,
      builder: (context) =>
          TransactionDetailDialog(transactionId: transaction.id),
    );
  }

  void _toggleSort(_SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = false;
      }
      _page = 0;
    });
  }

  List<Transaction> get _filtered {
    final query = _search.trim().toLowerCase();

    final filtered = _transactions.where((t) {
      if (!_matchesDateRange(t.date)) return false;
      if (query.isEmpty) return true;

      return t.invoiceNumber.toLowerCase().contains(query) ||
          t.tableName.toLowerCase().contains(query) ||
          (t.customerName?.toLowerCase().contains(query) ?? false) ||
          (t.promoName?.toLowerCase().contains(query) ?? false) ||
          t.cashierName.toLowerCase().contains(query) ||
          formatDate(t.date).contains(query);
    }).toList();

    filtered.sort((a, b) {
      final comparison = switch (_sortField) {
        _SortField.date => a.date.compareTo(b.date),
        _SortField.total => a.total.compareTo(b.total),
      };
      return _sortAscending ? comparison : -comparison;
    });

    return filtered;
  }

  bool _matchesDateRange(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    if (_startDate != null && day.isBefore(_startDate!)) return false;
    if (_endDate != null && day.isAfter(_endDate!)) return false;
    return true;
  }

  void _onSearchChanged(String value) {
    setState(() {
      _search = value;
      _page = 0;
    });
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: _endDate ?? now,
      initialDate: _startDate ?? _endDate ?? now,
    );

    if (result == null) return;
    setState(() {
      _startDate = DateTime(result.year, result.month, result.day);
      _page = 0;
    });
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      firstDate: _startDate ?? DateTime(now.year - 2),
      lastDate: now,
      initialDate: _endDate ?? _startDate ?? now,
    );

    if (result == null) return;
    setState(() {
      _endDate = DateTime(result.year, result.month, result.day);
      _page = 0;
    });
  }

  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _page = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final pageCount = (filtered.length / _pageSize).ceil().clamp(
      1,
      1 << 30,
    );
    final page = _page.clamp(0, pageCount - 1);
    final pageItems = filtered
        .skip(page * _pageSize)
        .take(_pageSize)
        .toList();

    return AppLayout(
      title: "Transaksi",
      subtitle: "Riwayat transaksi yang sudah selesai",
      showSearch: false,
      activeMenuKey: "transaksi",
      onMenuSelect: (key) => navigateToMenu(context, key),
      onRefresh: _refreshAll,
      child: Column(
        children: [
          _buildTabBar(),
          const SizedBox(height: 16),
          Expanded(child: _buildTabContent(filtered, pageItems, page, pageCount)),
        ],
      ),
    );
  }

  Widget _buildTabContent(
    List<Transaction> filtered,
    List<Transaction> pageItems,
    int page,
    int pageCount,
  ) {
    switch (_tab) {
      case _TransactionTab.billing:
        if (_loading) return const Center(child: CircularProgressIndicator());
        if (_loadError != null) return _buildErrorState(_loadError!);
        return _buildCard(filtered, pageItems, page, pageCount);
      case _TransactionTab.cafe:
        return AppCard(
          padding: EdgeInsets.zero,
          child: CafeTransactionList(key: _cafeListKey),
        );
      case _TransactionTab.saldo:
        return AppCard(
          padding: EdgeInsets.zero,
          child: const SaldoTransactionList(),
        );
    }
  }

  Widget _buildTabBar() {
    return Row(
      children: [
        _tabChip(_TransactionTab.billing, "Billing", Icons.receipt_long_outlined),
        const SizedBox(width: 10),
        _tabChip(_TransactionTab.cafe, "Cafe", Icons.local_cafe_outlined),
        const SizedBox(width: 10),
        _tabChip(
          _TransactionTab.saldo,
          "Pengisian Saldo",
          Icons.savings_outlined,
        ),
      ],
    );
  }

  Widget _tabChip(_TransactionTab tab, String label, IconData icon) {
    final active = _tab == tab;

    return InkWell(
      onTap: () => setState(() => _tab = tab),
      borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withValues(alpha: .15) : null,
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppText.body.copyWith(
                fontWeight: FontWeight.w600,
                color: active ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: AppColors.danger,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: AppText.bodySecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text("Coba Lagi")),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: AppText.bodySecondary,
              decoration: const InputDecoration(
                isDense: true,
                hintText: "Cari no. invoice, meja, member, kasir...",
                prefixIcon: Icon(Icons.search, size: 18),
                prefixIconConstraints: BoxConstraints(
                  minWidth: 34,
                  minHeight: 34,
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _dateBox(
          label: "Dari Tanggal",
          value: _startDate,
          onTap: _pickStartDate,
        ),
        const SizedBox(width: 6),
        Text("s/d", style: AppText.caption),
        const SizedBox(width: 6),
        _dateBox(
          label: "Sampai Tanggal",
          value: _endDate,
          onTap: _pickEndDate,
        ),
        if (_startDate != null || _endDate != null) ...[
          const SizedBox(width: 8),
          InkWell(
            onTap: _clearDateFilter,
            child: const Icon(
              Icons.close_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _dateBox({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              value == null ? label : formatDate(value),
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    List<Transaction> filtered,
    List<Transaction> pageItems,
    int page,
    int pageCount,
  ) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: _buildFilterRow(),
          ),
          const Divider(height: 1),
          Container(
            color: AppColors.background.withValues(alpha: .5),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: _TransactionRow.header(
              sortField: _sortField,
              sortAscending: _sortAscending,
              onSortDate: () => _toggleSort(_SortField.date),
              onSortTotal: () => _toggleSort(_SortField.total),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: pageItems.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: pageItems.length,
                    itemBuilder: (context, index) => _TransactionRow.data(
                      no: page * _pageSize + index + 1,
                      transaction: pageItems[index],
                      striped: index.isEven,
                      onTap: () => _openDetail(pageItems[index]),
                      onReprint: () => _reprintReceipt(pageItems[index]),
                      reprinting: _reprintingId == pageItems[index].id,
                      onEditPayment: () => _editPayment(pageItems[index]),
                      editingPayment:
                          _editingPaymentId == pageItems[index].id,
                    ),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildPagination(filtered.length, page, pageCount),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 40,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 12),
          Text("Tidak ada transaksi ditemukan", style: AppText.bodySecondary),
        ],
      ),
    );
  }

  Widget _buildPagination(int totalItems, int page, int pageCount) {
    final startItem = totalItems == 0 ? 0 : page * _pageSize + 1;
    final endItem = totalItems == 0
        ? 0
        : ((page + 1) * _pageSize).clamp(0, totalItems);

    return Row(
      children: [
        Text(
          "Menampilkan $startItem-$endItem dari $totalItems transaksi",
          style: AppText.caption,
        ),
        const Spacer(),
        _pageArrow(
          icon: Icons.chevron_left_rounded,
          onTap: page > 0 ? () => setState(() => _page = page - 1) : null,
        ),
        const SizedBox(width: 6),
        ..._buildPageButtons(page, pageCount),
        const SizedBox(width: 6),
        _pageArrow(
          icon: Icons.chevron_right_rounded,
          onTap: page < pageCount - 1
              ? () => setState(() => _page = page + 1)
              : null,
        ),
      ],
    );
  }

  List<Widget> _buildPageButtons(int page, int pageCount) {
    final window = _pageWindow(pageCount, page);
    final widgets = <Widget>[];

    for (var i = 0; i < window.length; i++) {
      if (i > 0 && window[i] - window[i - 1] > 1) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text("...", style: AppText.caption),
          ),
        );
      }
      widgets.add(_pageNumberButton(window[i], active: window[i] == page));
      widgets.add(const SizedBox(width: 6));
    }

    return widgets;
  }

  List<int> _pageWindow(int pageCount, int current) {
    if (pageCount <= 7) return List.generate(pageCount, (i) => i);

    final set = <int>{0, pageCount - 1, current};
    if (current - 1 >= 0) set.add(current - 1);
    if (current + 1 <= pageCount - 1) set.add(current + 1);

    return set.toList()..sort();
  }

  Widget _pageNumberButton(int index, {required bool active}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: active ? null : () => setState(() => _page = index),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          "${index + 1}",
          style: AppText.caption.copyWith(
            color: active ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _pageArrow({required IconData icon, required VoidCallback? onTap}) {
    final enabled = onTap != null;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? AppColors.textSecondary : AppColors.textHint,
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final bool header;
  final int? no;
  final Transaction? transaction;
  final bool striped;
  final _SortField? sortField;
  final bool sortAscending;
  final VoidCallback? onSortDate;
  final VoidCallback? onSortTotal;
  final VoidCallback? onTap;
  final VoidCallback? onReprint;
  final bool reprinting;
  final VoidCallback? onEditPayment;
  final bool editingPayment;

  const _TransactionRow.header({
    required this.sortField,
    required this.sortAscending,
    required this.onSortDate,
    required this.onSortTotal,
  }) : header = true,
       no = null,
       transaction = null,
       striped = false,
       onTap = null,
       onReprint = null,
       reprinting = false,
       onEditPayment = null,
       editingPayment = false;

  const _TransactionRow.data({
    required this.no,
    required this.transaction,
    required this.striped,
    this.onTap,
    this.onReprint,
    this.reprinting = false,
    this.onEditPayment,
    this.editingPayment = false,
  }) : header = false,
       sortField = null,
       sortAscending = false,
       onSortDate = null,
       onSortTotal = null;

  @override
  Widget build(BuildContext context) {
    if (header) {
      return _row(
        no: _headerText("No"),
        invoice: _headerText("No. Invoice"),
        tanggal: _sortableHeaderText(
          "Tanggal",
          active: sortField == _SortField.date,
          ascending: sortAscending,
          onTap: onSortDate,
        ),
        jamMulai: _headerText("Jam Mulai"),
        jamSelesai: _headerText("Jam Selesai"),
        meja: _headerText("Meja"),
        pelanggan: _headerText("Member"),
        promo: _headerText("Promo"),
        kasir: _headerText("Kasir"),
        total: _sortableHeaderText(
          "Total",
          alignEnd: true,
          active: sortField == _SortField.total,
          ascending: sortAscending,
          onTap: onSortTotal,
        ),
        status: _headerText("Status", alignCenter: true),
        aksi: _headerText("Aksi", alignCenter: true),
      );
    }

    final t = transaction!;
    final cellStyle = AppText.caption.copyWith(fontSize: 13);
    final isCompleted = t.status == TransactionStatus.completed;
    final statusColor = isCompleted ? AppColors.success : AppColors.danger;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: striped
            ? AppColors.background.withValues(alpha: .3)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _row(
          no: Text("$no", style: cellStyle),
          invoice: Text(
            t.invoiceNumber,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: cellStyle.copyWith(fontWeight: FontWeight.w600),
          ),
          tanggal: Text(formatDate(t.date), style: cellStyle),
          jamMulai: Text(formatTime(t.startAt), style: cellStyle),
          jamSelesai: Text(formatTime(t.endAt), style: cellStyle),
          meja: Text(t.tableName, style: cellStyle),
          pelanggan: Text(
            t.customerName ?? "-",
            style: cellStyle,
          ),
          promo: Text(
            t.promoName ?? "-",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: cellStyle,
          ),
          kasir: Text(t.cashierName, style: cellStyle),
          total: Text(
            formatCurrency(t.total),
            textAlign: TextAlign.end,
            style: cellStyle.copyWith(fontWeight: FontWeight.w600),
          ),
          status: Align(
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                isCompleted ? "Selesai" : "Dibatalkan",
                style: AppText.caption.copyWith(
                  fontSize: 10,
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          aksi: isCompleted
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ReprintButton(
                      reprinting: reprinting,
                      onTap: onReprint,
                    ),
                    if (t.paymentMethod != "Potong Saldo") ...[
                      const SizedBox(width: 6),
                      _EditPaymentButton(
                        editing: editingPayment,
                        onTap: onEditPayment,
                      ),
                    ],
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  static Widget _sortableHeaderText(
    String text, {
    bool alignEnd = false,
    required bool active,
    required bool ascending,
    required VoidCallback? onTap,
  }) {
    final color = active ? AppColors.primary : AppColors.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: alignEnd
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (alignEnd && active) ...[
            Icon(
              ascending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          if (!alignEnd && active) ...[
            const SizedBox(width: 3),
            Icon(
              ascending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 12,
              color: color,
            ),
          ],
        ],
      ),
    );
  }

  static Widget _headerText(
    String text, {
    bool alignEnd = false,
    bool alignCenter = false,
  }) {
    return Text(
      text,
      textAlign: alignCenter
          ? TextAlign.center
          : (alignEnd ? TextAlign.end : TextAlign.start),
      style: AppText.caption.copyWith(fontWeight: FontWeight.w700),
    );
  }

  static Widget _row({
    required Widget no,
    required Widget invoice,
    required Widget tanggal,
    required Widget jamMulai,
    required Widget jamSelesai,
    required Widget meja,
    required Widget pelanggan,
    required Widget promo,
    required Widget kasir,
    required Widget total,
    required Widget status,
    required Widget aksi,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 32, child: no),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: invoice),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: tanggal),
        const SizedBox(width: 12),
        Expanded(flex: 1, child: jamMulai),
        const SizedBox(width: 12),
        Expanded(flex: 1, child: jamSelesai),
        const SizedBox(width: 12),
        Expanded(flex: 1, child: meja),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: pelanggan),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: promo),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: kasir),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: total),
        const SizedBox(width: 12),
        SizedBox(width: 90, child: status),
        const SizedBox(width: 12),
        SizedBox(width: 96, child: aksi),
      ],
    );
  }
}

class _ReprintButton extends StatelessWidget {
  final bool reprinting;
  final VoidCallback? onTap;

  const _ReprintButton({required this.reprinting, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (reprinting) {
      return const SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Tooltip(
      message: "Cetak ulang struk",
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(
            Icons.print_outlined,
            size: 16,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _EditPaymentButton extends StatelessWidget {
  final bool editing;
  final VoidCallback? onTap;

  const _EditPaymentButton({required this.editing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (editing) {
      return const SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Tooltip(
      message: "Ubah metode pembayaran",
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(
            Icons.sync_alt_rounded,
            size: 16,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
