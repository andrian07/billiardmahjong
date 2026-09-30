import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/business_info.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/cafe_receipt.dart';
import '../../../models/cafe_transaction.dart';
import '../../../models/payment_method.dart';
import '../../../models/transaction.dart';
import '../../../services/receipt_printer_service.dart';
import '../../../services/session_storage.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/ticket_preview.dart';
import '../../../shared/widgets/pin_guard.dart';
import '../data/transaction_repository.dart';
import 'edit_payment_dialog.dart';

class CafeTransactionList extends StatefulWidget {
  const CafeTransactionList({super.key});

  @override
  State<CafeTransactionList> createState() => CafeTransactionListState();
}

class CafeTransactionListState extends State<CafeTransactionList> {
  // Ukuran halaman TAMPILAN (paginasi lokal di client) - bukan lagi ukuran per_page yang diminta
  // ke server. Semua transaksi dimuat sekali (lihat _load()), lalu difilter+dipaginasi di sini,
  // persis pola yang dipakai TransactionPage (Billing) supaya search-nya konsisten.
  static const _pageSize = 20;

  final _repository = TransactionRepository();
  final _receiptPrinter = ReceiptPrinterService();
  final _searchController = TextEditingController();

  List<CafeTransaction> _transactions = [];
  String _search = "";
  DateTime? _startDate;
  DateTime? _endDate;
  int _page = 0;
  bool _loading = true;
  String? _error;
  int? _reprintingId;
  int? _cancelingId;
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

  /// Reloads the full list — exposed for [TransactionPage]'s header refresh
  /// button via a [GlobalKey].
  Future<void> refresh() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // per_page besar supaya seluruh data termuat sekali (search & paginasi selanjutnya dilakukan
      // di client) - sama seperti TransactionRepository.getCompletedTransactions() untuk Billing.
      final result = await _repository.getCafeTransactions(
        page: 1,
        perPage: 1000,
      );
      if (!mounted) return;
      setState(() {
        _transactions = result.transactions;
        _loading = false;
      });
    } on TransactionRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  List<CafeTransaction> get _filtered {
    final query = _search.trim().toLowerCase();

    return _transactions.where((t) {
      if (!_matchesDateRange(t.date)) return false;
      if (query.isEmpty) return true;

      return t.invoiceNumber.toLowerCase().contains(query) ||
          (t.table?.toLowerCase().contains(query) ?? false) ||
          (t.promoName?.toLowerCase().contains(query) ?? false) ||
          t.createdBy.toLowerCase().contains(query) ||
          formatDate(t.date).contains(query);
    }).toList();
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

  Future<void> _reprintReceipt(CafeTransaction transaction) async {
    if (_reprintingId != null) return;

    setState(() => _reprintingId = transaction.id);
    try {
      final detail = await _repository.getCafeTransactionDetail(transaction.id);

      final receipt = CafeReceipt(
        businessName: BusinessInfo.name,
        businessAddress: BusinessInfo.address,
        invoiceNumber: detail.invoiceNumber,
        date: detail.date,
        table: detail.table != null ? "Meja ${detail.table}" : null,
        customerName: detail.customerName,
        items: [
          for (final item in detail.items)
            CafeReceiptItem(
              name: item.name,
              quantity: item.quantity,
              price: item.price,
              note: item.note,
              addons: [
                for (final addon in item.addons)
                  CafeReceiptAddon(
                    name: addon.name,
                    quantity: addon.quantity,
                    price: addon.price,
                  ),
              ],
            ),
        ],
        subtotal: detail.subTotal,
        discountPercent: detail.discount,
        discountAmount: (detail.subTotal * detail.discount / 100).round(),
        tax: detail.tax,
        total: detail.totalBill,
        paymentMethod: detail.paymentMethod,
        cashierName: detail.createdBy,
        isReprint: true,
      );

      try {
        await _receiptPrinter.printCafeReceipt(receipt);
      } on ReceiptPrinterNotFoundException {
        if (!mounted) return;
        await TicketPreviewDialog.show(
          context,
          title: "PREVIEW STRUK - printer tidak ditemukan",
          children: TicketPreviewContent.cafe(receipt),
        );
        return;
      }

      if (!mounted) return;
      AppToast.success(
        context,
        "Struk ${transaction.invoiceNumber} berhasil dicetak ulang",
      );
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

  Future<void> _cancelTransaction(CafeTransaction transaction) async {
    if (_cancelingId != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        ),
        title: Text("Batalkan Transaksi?", style: AppText.title),
        content: Text(
          "Transaksi ${transaction.invoiceNumber} akan ditandai dibatalkan, "
          "tidak lagi dihitung ke total transaksi, dan stok item yang "
          "terjual akan dikembalikan.",
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

    setState(() => _cancelingId = transaction.id);
    try {
      final session = await SessionStorage().getSession();
      final createdBy = session?['username']?.toString() ?? "";
      await _repository.cancelCafeTransaction(
        transaction.id,
        createdBy: createdBy,
      );
      if (!mounted) return;
      AppToast.success(
        context,
        "Transaksi ${transaction.invoiceNumber} dibatalkan",
      );
      await _load();
    } on TransactionRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } finally {
      if (mounted) setState(() => _cancelingId = null);
    }
  }

  Future<void> _editPayment(CafeTransaction transaction) async {
    if (_editingPaymentId != null) return;

    final result = await showDialog<PaymentMethod>(
      context: context,
      builder: (_) => EditPaymentDialog(
        invoiceNumber: transaction.invoiceNumber,
        currentPaymentId: transaction.paymentId,
        currentPaymentName: transaction.paymentName ?? "-",
      ),
    );
    if (result == null) return;

    setState(() => _editingPaymentId = transaction.id);
    try {
      final session = await SessionStorage().getSession();
      final createdBy = session?['username']?.toString() ?? "";
      await _repository.editCafePayment(
        transactionCafeId: transaction.id,
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildErrorState(_error!);
    }

    final filtered = _filtered;
    final pageCount = (filtered.length / _pageSize).ceil().clamp(1, 1 << 30);
    final page = _page.clamp(0, pageCount - 1);
    final pageItems = filtered.skip(page * _pageSize).take(_pageSize).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: _buildFilterRow(),
        ),
        const Divider(height: 1),
        Container(
          color: AppColors.background.withValues(alpha: .5),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: _header(),
        ),
        const Divider(height: 1),
        Expanded(
          child: pageItems.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: pageItems.length,
                  itemBuilder: (context, index) => _row(
                    no: page * _pageSize + index + 1,
                    transaction: pageItems[index],
                    striped: index.isEven,
                  ),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: _buildPagination(filtered.length, page, pageCount),
        ),
      ],
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
                hintText: "Cari no. invoice, meja, kasir...",
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
        _dateBox(label: "Sampai Tanggal", value: _endDate, onTap: _pickEndDate),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_cafe_outlined,
            size: 40,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 12),
          Text(
            "Tidak ada transaksi cafe ditemukan",
            style: AppText.bodySecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildPagination(int totalItems, int page, int pageCount) {
    final startItem = totalItems == 0 ? 0 : page * _pageSize + 1;
    final endItem = ((page + 1) * _pageSize).clamp(0, totalItems);

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

  Widget _header() {
    return _rowLayout(
      no: _headerText("No"),
      invoice: _headerText("No. Invoice"),
      tanggal: _headerText("Tanggal"),
      meja: _headerText("Meja"),
      customer: _headerText("Customer"),
      total: _headerText("Total", alignEnd: true),
      kasir: _headerText("Kasir"),
      status: _headerText("Status", alignCenter: true),
      aksi: _headerText("Aksi", alignCenter: true),
    );
  }

  Widget _row({
    required int no,
    required CafeTransaction transaction,
    required bool striped,
  }) {
    final cellStyle = AppText.caption.copyWith(fontSize: 13);
    final isCompleted = transaction.status == TransactionStatus.completed;
    final statusColor = isCompleted ? AppColors.success : AppColors.danger;

    return Container(
      color: striped
          ? AppColors.background.withValues(alpha: .3)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _rowLayout(
        no: Text("$no", style: cellStyle),
        invoice: Text(
          transaction.invoiceNumber,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: cellStyle.copyWith(fontWeight: FontWeight.w600),
        ),
        tanggal: Text(formatDate(transaction.date), style: cellStyle),
        meja: Text(transaction.table ?? "-", style: cellStyle),
        customer: Text(
          transaction.customerName ?? "-",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: cellStyle,
        ),
        total: Text(
          formatCurrency(transaction.totalBill),
          textAlign: TextAlign.end,
          style: cellStyle.copyWith(fontWeight: FontWeight.w600),
        ),
        kasir: Text(transaction.createdBy, style: cellStyle),
        status: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
            if (!isCompleted && transaction.cancelledBy != null) ...[
              const SizedBox(height: 2),
              Tooltip(
                message: "Dibatalkan oleh ${transaction.cancelledBy}",
                child: Text(
                  "oleh ${transaction.cancelledBy}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(
                    fontSize: 9,
                    color: AppColors.textHint,
                  ),
                ),
              ),
            ],
          ],
        ),
        aksi: isCompleted
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ActionButton(
                    icon: Icons.print_outlined,
                    tooltip: "Cetak ulang struk",
                    loading: _reprintingId == transaction.id,
                    onTap: () => _reprintReceipt(transaction),
                  ),
                  const SizedBox(width: 6),
                  if (transaction.paymentName != "Potong Saldo") ...[
                    _ActionButton(
                      icon: Icons.sync_alt_rounded,
                      tooltip: "Ubah metode pembayaran",
                      loading: _editingPaymentId == transaction.id,
                      onTap: () => _editPayment(transaction),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _ActionButton(
                    icon: Icons.cancel_outlined,
                    tooltip: "Batalkan transaksi",
                    loading: _cancelingId == transaction.id,
                    color: AppColors.danger,
                    onTap: () => _cancelTransaction(transaction),
                  ),
                ],
              )
            : const SizedBox.shrink(),
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

  static Widget _rowLayout({
    required Widget no,
    required Widget invoice,
    required Widget tanggal,
    required Widget meja,
    required Widget customer,
    required Widget total,
    required Widget kasir,
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
        Expanded(flex: 1, child: meja),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: customer),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: total),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: kasir),
        const SizedBox(width: 12),
        SizedBox(width: 90, child: status),
        const SizedBox(width: 12),
        SizedBox(width: 112, child: aksi),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool loading;
  final Color? color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.loading,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Tooltip(
      message: tooltip,
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
          child: Icon(icon, size: 15, color: color ?? AppColors.textSecondary),
        ),
      ),
    );
  }
}
