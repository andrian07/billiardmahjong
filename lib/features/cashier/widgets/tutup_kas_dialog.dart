import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/cashier_summary.dart';
import '../../../services/cashier_summary_printer_service.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/ticket_preview.dart';
import '../data/cashier_repository.dart';

/// "Tutup Kas" popup — shows the logged-in cashier's transactions for today
/// (billing + cafe/POS combined) via Report/get_transaction_today_by_cashier,
/// with a print action for the physical closing ticket.
class TutupKasDialog extends StatefulWidget {
  final int userId;
  final String cashierName;

  const TutupKasDialog({
    super.key,
    required this.userId,
    required this.cashierName,
  });

  @override
  State<TutupKasDialog> createState() => _TutupKasDialogState();
}

class _TutupKasDialogState extends State<TutupKasDialog> {
  final _repository = CashierRepository();
  final _printerService = CashierSummaryPrinterService();

  bool _loading = true;
  String? _error;
  CashierClosingSummary? _summary;
  bool _printing = false;
  bool _printingCafeItems = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final summary = await _repository.getTodaySummary(userId: widget.userId);

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } on CashierRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _print() async {
    final summary = _summary;
    if (summary == null || _printing) return;

    setState(() => _printing = true);

    try {
      try {
        await _printerService.printSummary(
          summary,
          cashierName: widget.cashierName,
        );
      } on CashierSummaryPrinterNotFoundException {
        if (!mounted) return;
        setState(() => _printing = false);
        await TicketPreviewDialog.show(
          context,
          title: "PREVIEW TUTUP KAS - printer tidak ditemukan",
          children: TicketPreviewContent.cashierSummary(
            summary,
            widget.cashierName,
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _printing = false);
      AppToast.success(context, "Struk tutup kas berhasil dicetak");
    } catch (e) {
      if (!mounted) return;
      setState(() => _printing = false);
      AppToast.error(context, "$e");
    }
  }

  Future<void> _printCafeItems() async {
    final summary = _summary;
    if (summary == null || _printingCafeItems) return;

    setState(() => _printingCafeItems = true);

    try {
      try {
        await _printerService.printCafeItems(
          summary,
          cashierName: widget.cashierName,
        );
      } on CashierSummaryPrinterNotFoundException {
        if (!mounted) return;
        setState(() => _printingCafeItems = false);
        await TicketPreviewDialog.show(
          context,
          title: "PREVIEW ITEM CAFE - printer tidak ditemukan",
          children: TicketPreviewContent.cafeItemsSold(
            summary,
            widget.cashierName,
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _printingCafeItems = false);
      AppToast.success(context, "Struk item cafe berhasil dicetak");
    } catch (e) {
      if (!mounted) return;
      setState(() => _printingCafeItems = false);
      AppToast.error(context, "$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusXL),
      ),
      backgroundColor: AppColors.card,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 640,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.radiusXL),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            const Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: 20),
            _buildBody(),
            const SizedBox(height: 24),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          ),
          child: const Icon(
            Icons.summarize_rounded,
            color: AppColors.warning,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Tutup Kas",
                style: AppText.title.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text("Ringkasan transaksi hari ini", style: AppText.caption),
            ],
          ),
        ),
        InkWell(
          onTap: () => Navigator.of(context).pop(),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              border: Border.all(color: AppColors.danger.withValues(alpha: .3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: AppText.caption.copyWith(color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _load,
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
      );
    }

    final summary = _summary!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Tanggal", style: AppText.bodySecondary),
            Text(
              formatFullDate(summary.businessDate),
              style: AppText.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Kasir", style: AppText.bodySecondary),
            Text(
              widget.cashierName,
              style: AppText.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _sectionCard(
                icon: Icons.table_bar_rounded,
                title: "Billing",
                summary: summary.billing,
                multiplier: 2,
                expenseTotal: summary.expenseTotalBilling,
                netCash: summary.billingNetCash,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _sectionCard(
                icon: Icons.point_of_sale_rounded,
                title: "Cafe / POS",
                summary: summary.cafe,
                expenseTotal: summary.expenseTotalCafe,
                netCash: summary.cafeNetCash,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _sectionCard(
                icon: Icons.savings_outlined,
                title: "Pengisian Saldo",
                summary: summary.saldo,
              ),
            ),
          ],
        ),
        if (summary.expenses.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildExpenses(summary),
        ],
        const SizedBox(height: 14),
        const Divider(color: AppColors.divider, height: 1),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Total Nota",
              style: AppText.body.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              "${summary.totalInvoiceCount}",
              style: AppText.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Grand Total",
              style: AppText.body.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              formatCurrency(
                summary.billing.totalTransaction * 2 +
                    summary.cafe.totalTransaction,
              ),
              style: AppText.title.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExpenses(CashierClosingSummary summary) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: AppColors.danger.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.payments_outlined,
                size: 16,
                color: AppColors.danger,
              ),
              const SizedBox(width: 8),
              Text(
                "Pengeluaran Kas",
                style: AppText.bodySecondary.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final e in summary.expenses)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      e.channel == ExpenseChannel.cafe ? "Cafe" : "Billing",
                      style: AppText.caption.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.keterangan,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "-${formatCurrency(e.nominal)}",
                    style: AppText.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 6),
          _cardKv(
            "Total Pengeluaran",
            "-${formatCurrency(summary.expenseTotal)}",
            color: AppColors.danger,
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required CashierTransactionSummary summary,
    int? expenseTotal,
    int? netCash,
    int multiplier = 1,
  }) {
    final showRecon = (expenseTotal ?? 0) > 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySecondary.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _cardKv("Jumlah Nota", "${summary.invoiceCount}"),
          const SizedBox(height: 4),
          _cardKv(
            "Total Transaksi",
            formatCurrency(summary.totalTransaction * multiplier),
          ),
          if (summary.byPayment.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: 8),
            for (final payment in summary.byPayment) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _cardKv(
                  "${payment.paymentName} (${payment.invoiceCount})",
                  formatCurrency(payment.totalTransaction * multiplier),
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
          if (showRecon) ...[
            const SizedBox(height: 8),
            const Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: 8),
            _cardKv("Tunai (CASH)", formatCurrency(summary.cashTotal)),
            const SizedBox(height: 4),
            _cardKv(
              "Pengeluaran",
              "-${formatCurrency(expenseTotal!)}",
              color: AppColors.danger,
            ),
            const SizedBox(height: 4),
            _cardKv(
              "Tunai Bersih",
              formatCurrency(netCash ?? (summary.cashTotal - expenseTotal)),
              bold: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardKv(
    String label,
    String value, {
    Color? color,
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(
              color: color,
              fontWeight: bold ? FontWeight.w700 : null,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.caption.copyWith(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    final canPrint = !_loading && _error == null && _summary != null;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
            ),
            child: const Text("TUTUP"),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            onPressed: canPrint && !_printingCafeItems ? _printCafeItems : null,
            icon: _printingCafeItems
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.local_cafe_outlined, size: 20),
            label: Text(_printingCafeItems ? "MENCETAK..." : "CETAK CAFE"),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text,
              side: const BorderSide(color: AppColors.border),
              minimumSize: const Size(0, 48),
              textStyle: AppText.button,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: canPrint && !_printing ? _print : null,
            icon: _printing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.print_rounded, size: 20),
            label: Text(_printing ? "MENCETAK..." : "CETAK STRUK"),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.textHint,
              minimumSize: const Size(0, 48),
              elevation: 0,
              textStyle: AppText.button,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
