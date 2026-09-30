import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../models/cafe_receipt.dart';
import '../../models/cashier_summary.dart';
import '../../models/receipt.dart';
import '../../models/saldo_receipt.dart';

/// Fallback saat tidak ada printer USB terhubung — menampilkan isi struk yang
/// sama dengan yang dikirim ke printer (lihat *_printer_service.dart) sebagai
/// widget bergaya kertas struk.
class TicketPreviewDialog extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const TicketPreviewDialog({
    super.key,
    required this.title,
    required this.children,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => TicketPreviewDialog(title: title, children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.print_disabled_rounded,
                  size: 15,
                  color: Colors.white70,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340, maxHeight: 560),
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: SingleChildScrollView(
                child: DefaultTextStyle(
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.4,
                    color: Colors.black,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: Colors.white,
            ),
            label: const Text(
              "TUTUP PREVIEW",
              style: TextStyle(color: Colors.white),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}

/// Padanan [TicketLayout] (lib/services/ticket_layout.dart) berupa widget.
class TicketPreviewLayout {
  TicketPreviewLayout._();

  static List<Widget> header({
    required String businessName,
    required String businessAddress,
    required String invoiceNumber,
    required DateTime issuedAt,
    bool isReprint = false,
  }) {
    return [
      center(businessName, bold: true),
      center(businessAddress),
      separator(char: '='),
      center(invoiceNumber, bold: true),
      center("${formatFullDate(issuedAt)}  ${formatClock(issuedAt)}"),
      if (isReprint) center("*** PRINT ULANG ***", bold: true),
      separator(char: '='),
    ];
  }

  static Widget row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(label)),
          const SizedBox(width: 6),
          Expanded(flex: 5, child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  static Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  static Widget grandTotal(String label, int amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          separator(char: '='),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
            formatCurrency(amount),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          separator(char: '='),
        ],
      ),
    );
  }

  static List<Widget> footer(String cashierName) {
    return [
      row("Kasir", cashierName),
      const SizedBox(height: 8),
      center("Terima kasih atas kunjungan Anda"),
    ];
  }

  static Widget center(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  static Widget separator({String char = '-'}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(height: char == '=' ? 2.5 : 1, color: Colors.black87),
    );
  }

  static Widget feed([double height = 6]) => SizedBox(height: height);
}

/// Isi preview per jenis struk — harus sejalan dengan `_build*Ticket()` di
/// receipt_printer_service.dart / cashier_summary_printer_service.dart
/// (termasuk pengali ×2 untuk nominal billing).
class TicketPreviewContent {
  TicketPreviewContent._();

  static List<Widget> billing(Receipt receipt) {
    return [
      ...TicketPreviewLayout.header(
        businessName: receipt.businessName,
        businessAddress: receipt.businessAddress,
        invoiceNumber: receipt.invoiceNumber,
        issuedAt: receipt.date,
        isReprint: receipt.isReprint,
      ),
      TicketPreviewLayout.row("Meja", receipt.tableLabel),
      TicketPreviewLayout.row("Mulai", formatClock(receipt.startAt)),
      TicketPreviewLayout.row("Selesai", formatClock(receipt.endAt)),
      TicketPreviewLayout.row(
        "Durasi",
        formatDurationWords(receipt.totalDuration),
      ),
      if (receipt.periods.isNotEmpty) ...[
        TicketPreviewLayout.sectionTitle("Rincian Waktu"),
        for (final period in receipt.periods) ...[
          TicketPreviewLayout.row(
            period.label,
            formatCurrency(period.cost * 2),
          ),
          TicketPreviewLayout.row("  Durasi", formatDuration(period.duration)),
        ],
      ],
      TicketPreviewLayout.separator(),
      TicketPreviewLayout.row("Subtotal", formatCurrency(receipt.subtotal * 2)),
      if (receipt.promoName != null)
        TicketPreviewLayout.row("Promo", receipt.promoName!),
      if (receipt.discountAmount > 0)
        TicketPreviewLayout.row(
          "Diskon",
          "-${formatCurrency(receipt.discountAmount * 2)}",
        ),
      TicketPreviewLayout.grandTotal("GRAND TOTAL", receipt.grandTotal * 2),
      TicketPreviewLayout.row("Bayar", receipt.paymentMethod),
      ...TicketPreviewLayout.footer(receipt.cashierName),
    ];
  }

  static List<Widget> cafe(CafeReceipt receipt) {
    return [
      ...TicketPreviewLayout.header(
        businessName: receipt.businessName,
        businessAddress: receipt.businessAddress,
        invoiceNumber: receipt.invoiceNumber,
        issuedAt: receipt.date,
        isReprint: receipt.isReprint,
      ),
      if (receipt.table != null)
        TicketPreviewLayout.row("Meja", receipt.table!)
      else
        TicketPreviewLayout.row(
          "Customer",
          (receipt.customerName?.trim().isNotEmpty ?? false)
              ? receipt.customerName!.trim()
              : "-",
        ),
      TicketPreviewLayout.feed(),
      for (final item in receipt.items) ...[
        Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        if (item.note != null) Text("  (${item.note})"),
        TicketPreviewLayout.row(
          "  ${item.quantity} x ${formatCurrency(item.price)}",
          formatCurrency(item.price * item.quantity),
        ),
        for (final addon in item.addons)
          TicketPreviewLayout.row(
            "  + ${addon.name} x${addon.quantity}",
            formatCurrency(addon.lineTotal),
          ),
      ],
      TicketPreviewLayout.separator(),
      TicketPreviewLayout.row("Subtotal", formatCurrency(receipt.subtotal)),
      if (receipt.discountAmount > 0)
        TicketPreviewLayout.row(
          "Diskon (${receipt.discountPercent}%)",
          "-${formatCurrency(receipt.discountAmount)}",
        ),
      if (receipt.tax > 0)
        TicketPreviewLayout.row("Pajak", formatCurrency(receipt.tax)),
      TicketPreviewLayout.grandTotal("TOTAL", receipt.total),
      TicketPreviewLayout.row("Bayar", receipt.paymentMethod),
      ...TicketPreviewLayout.footer(receipt.cashierName),
    ];
  }

  static List<Widget> saldo(SaldoReceipt receipt) {
    return [
      ...TicketPreviewLayout.header(
        businessName: receipt.businessName,
        businessAddress: receipt.businessAddress,
        invoiceNumber: receipt.invoiceNumber,
        issuedAt: receipt.date,
      ),
      TicketPreviewLayout.row("Member", receipt.customerName),
      TicketPreviewLayout.row("Nominal Saldo", formatCurrency(receipt.nominal)),
      if (receipt.discount > 0)
        TicketPreviewLayout.row("Diskon", formatCurrency(receipt.discount)),
      TicketPreviewLayout.grandTotal("TOTAL DIBAYAR", receipt.price),
      TicketPreviewLayout.row("Bayar", receipt.paymentMethod),
      ...TicketPreviewLayout.footer(receipt.cashierName),
    ];
  }

  static List<Widget> _byPayment(
    List<CashierPaymentBreakdown> byPayment, {
    int multiplier = 1,
  }) {
    return [
      for (final payment in byPayment)
        TicketPreviewLayout.row(
          "  ${payment.paymentName}",
          "${formatCurrency(payment.totalTransaction * multiplier)} (${payment.invoiceCount})",
        ),
    ];
  }

  static List<Widget> _cashRecon({
    required int cash,
    required int expense,
    required int net,
  }) {
    if (expense <= 0) return const [];
    return [
      TicketPreviewLayout.row("  Tunai (CASH)", formatCurrency(cash)),
      TicketPreviewLayout.row("  Pengeluaran", "-${formatCurrency(expense)}"),
      TicketPreviewLayout.row("  Tunai Bersih", formatCurrency(net)),
    ];
  }

  static List<Widget> cashierSummary(
    CashierClosingSummary summary,
    String cashierName,
  ) {
    return [
      TicketPreviewLayout.center("TUTUP KAS", bold: true),
      TicketPreviewLayout.center(formatFullDate(summary.businessDate)),
      TicketPreviewLayout.separator(char: '='),
      TicketPreviewLayout.row("Kasir", cashierName),
      TicketPreviewLayout.sectionTitle("Billing"),
      TicketPreviewLayout.row("Jumlah Nota", "${summary.billing.invoiceCount}"),
      TicketPreviewLayout.row(
        "Total Transaksi",
        formatCurrency(summary.billing.totalTransaction * 2),
      ),
      ..._byPayment(summary.billing.byPayment, multiplier: 2),
      ..._cashRecon(
        cash: summary.billing.cashTotal,
        expense: summary.expenseTotalBilling,
        net: summary.billingNetCash,
      ),
      TicketPreviewLayout.sectionTitle("Cafe / POS"),
      TicketPreviewLayout.row("Jumlah Nota", "${summary.cafe.invoiceCount}"),
      TicketPreviewLayout.row(
        "Total Transaksi",
        formatCurrency(summary.cafe.totalTransaction),
      ),
      ..._byPayment(summary.cafe.byPayment),
      ..._cashRecon(
        cash: summary.cafe.cashTotal,
        expense: summary.expenseTotalCafe,
        net: summary.cafeNetCash,
      ),
      TicketPreviewLayout.sectionTitle("Pengisian Saldo"),
      TicketPreviewLayout.row("Jumlah Nota", "${summary.saldo.invoiceCount}"),
      TicketPreviewLayout.row(
        "Total Transaksi",
        formatCurrency(summary.saldo.totalTransaction),
      ),
      ..._byPayment(summary.saldo.byPayment),
      if (summary.expenses.isNotEmpty) ...[
        TicketPreviewLayout.sectionTitle("Pengeluaran Kas"),
        for (final e in summary.expenses)
          TicketPreviewLayout.row(
            "${e.channel == ExpenseChannel.cafe ? "[Cafe] " : "[Bil] "}${e.keterangan}",
            "-${formatCurrency(e.nominal)}",
          ),
        TicketPreviewLayout.row(
          "Total Pengeluaran",
          "-${formatCurrency(summary.expenseTotal)}",
        ),
      ],
      TicketPreviewLayout.separator(),
      TicketPreviewLayout.row("Total Nota", "${summary.totalInvoiceCount}"),
      TicketPreviewLayout.grandTotal(
        "GRAND TOTAL",
        summary.billing.totalTransaction * 2 + summary.cafe.totalTransaction,
      ),
    ];
  }

  static List<Widget> cafeItemsSold(
    CashierClosingSummary summary,
    String cashierName,
  ) {
    final rows = <Widget>[
      TicketPreviewLayout.center("ITEM CAFE TERJUAL", bold: true),
      TicketPreviewLayout.center(formatFullDate(summary.businessDate)),
      TicketPreviewLayout.separator(char: '='),
      TicketPreviewLayout.row("Kasir", cashierName),
      TicketPreviewLayout.separator(),
    ];

    if (summary.cafeItems.isEmpty) {
      rows.add(TicketPreviewLayout.center("Tidak ada penjualan cafe hari ini"));
    } else {
      var totalQty = 0;
      for (final item in summary.cafeItems) {
        rows.add(TicketPreviewLayout.row(item.productName, "${item.quantity}"));
        totalQty += item.quantity;
      }
      rows.add(TicketPreviewLayout.separator());
      rows.add(TicketPreviewLayout.row("Total Item", "$totalQty"));
    }

    return rows;
  }
}
