import 'dart:async';

import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

import '../core/utils/formatters.dart';
import '../models/cashier_summary.dart';
import 'printer_filter.dart';
import 'printer_preference_storage.dart';
import 'ticket_layout.dart';

class CashierSummaryPrinterException implements Exception {
  final String message;

  const CashierSummaryPrinterException(this.message);

  @override
  String toString() => message;
}

/// Thrown when no USB printer is connected at all — callers catch this
/// separately to fall back to [TicketPreviewDialog] instead of an error toast.
class CashierSummaryPrinterNotFoundException
    extends CashierSummaryPrinterException {
  const CashierSummaryPrinterNotFoundException()
    : super(
        "Printer USB tidak ditemukan. Pastikan printer terhubung dan menyala.",
      );
}

/// Prints tickets for the "Tutup Kas" (close register) flow — the summary
/// ticket and the cafe items-sold ticket — via the same USB ESC/POS flow as
/// [ReceiptPrinterService].
class CashierSummaryPrinterService {
  Future<void> printSummary(
    CashierClosingSummary summary, {
    required String cashierName,
  }) {
    return _print(() => _buildSummaryTicket(summary, cashierName));
  }

  Future<void> printCafeItems(
    CashierClosingSummary summary, {
    required String cashierName,
  }) {
    return _print(() => _buildCafeItemsTicket(summary, cashierName));
  }

  /// Shared USB scan/connect/print/disconnect flow — [buildTicket] builds
  /// whichever ticket layout the caller needs.
  Future<void> _print(Future<Ticket> Function() buildTicket) async {
    final manager = PrinterManager();

    try {
      await _run(manager, buildTicket).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw const CashierSummaryPrinterException(
          "Printer tidak merespon dalam 15 detik. Periksa kabel USB, "
          "pastikan printer menyala, lalu coba lagi.",
        ),
      );
    } on PrinterException catch (e) {
      throw CashierSummaryPrinterException(
        e.cause != null ? "${e.message} — ${e.cause}" : e.message,
      );
    } finally {
      // Fire-and-forget with its own timeout: if the hang that triggered
      // the timeout above is inside the plugin's native call, dispose()
      // would queue behind it and never return either — that must not
      // block this method from returning the error to the caller.
      unawaited(
        manager.dispose().timeout(const Duration(seconds: 3), onTimeout: () {}),
      );
    }
  }

  Future<void> _run(
    PrinterManager manager,
    Future<Ticket> Function() buildTicket,
  ) async {
    final selection = await PrinterPreferenceStorage().getSelection();

    // LAN printer: connect straight to the saved host:port — no scan needed.
    if (selection != null && selection.isNetwork) {
      await manager.connect(resolveSelection(const [], selection)!);
      await manager.printTicket(await buildTicket());
      await manager.disconnect();
      return;
    }

    final printers = await manager.scanPrinters(
      types: {PrinterConnectionType.usb},
    );

    if (printers.isEmpty) {
      throw const CashierSummaryPrinterNotFoundException();
    }

    await manager.connect(pickPrinter(printers, selection));
    await manager.printTicket(await buildTicket());
    await manager.disconnect();
  }

  Future<Ticket> _buildSummaryTicket(
    CashierClosingSummary summary,
    String cashierName,
  ) async {
    final ticket = await Ticket.create(PaperSize.mm80);

    ticket.text(
      "TUTUP KAS",
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.text(formatFullDate(summary.businessDate), align: PrintAlign.center);
    ticket.separator(char: '=', linesAfter: 1);

    TicketLayout.row(ticket, "Kasir", cashierName);

    TicketLayout.sectionTitle(ticket, "Billiard");
    TicketLayout.row(ticket, "Jumlah Nota", "${summary.billing.invoiceCount}");
    TicketLayout.row(
      ticket,
      "Total Transaksi",
      formatCurrency(summary.billing.totalTransaction * 2),
    );
    _byPayment(ticket, summary.billing.byPayment, multiplier: 2);
    _cashRecon(
      ticket,
      cash: summary.billing.cashTotal,
      expense: summary.expenseTotalBilling,
      net: summary.billingNetCash,
    );

    TicketLayout.sectionTitle(ticket, "Mahjong");
    TicketLayout.row(ticket, "Jumlah Nota", "${summary.mahjong.invoiceCount}");
    TicketLayout.row(
      ticket,
      "Total Transaksi",
      formatCurrency(summary.mahjong.totalTransaction * 2),
    );
    _byPayment(ticket, summary.mahjong.byPayment, multiplier: 2);
    _cashRecon(
      ticket,
      cash: summary.mahjong.cashTotal,
      expense: summary.expenseTotalMahjong,
      net: summary.mahjongNetCash,
    );

    TicketLayout.sectionTitle(ticket, "Cafe / POS");
    TicketLayout.row(ticket, "Jumlah Nota", "${summary.cafe.invoiceCount}");
    TicketLayout.row(
      ticket,
      "Total Transaksi",
      formatCurrency(summary.cafe.totalTransaction),
    );
    _byPayment(ticket, summary.cafe.byPayment);
    _cashRecon(
      ticket,
      cash: summary.cafe.cashTotal,
      expense: summary.expenseTotalCafe,
      net: summary.cafeNetCash,
    );

    TicketLayout.sectionTitle(ticket, "Pengisian Saldo");
    TicketLayout.row(ticket, "Jumlah Nota", "${summary.saldo.invoiceCount}");
    TicketLayout.row(
      ticket,
      "Total Transaksi",
      formatCurrency(summary.saldo.totalTransaction),
    );
    _byPayment(ticket, summary.saldo.byPayment);

    if (summary.expenses.isNotEmpty) {
      TicketLayout.sectionTitle(ticket, "Pengeluaran Kas");
      for (final e in summary.expenses) {
        final tag = switch (e.channel) {
          ExpenseChannel.cafe => "[Cafe] ",
          ExpenseChannel.mahjong => "[Mjg] ",
          ExpenseChannel.billing => "[Bil] ",
        };
        TicketLayout.row(
          ticket,
          "$tag${e.keterangan}",
          "-${formatCurrency(e.nominal)}",
        );
      }
      TicketLayout.row(
        ticket,
        "Total Pengeluaran",
        "-${formatCurrency(summary.expenseTotal)}",
      );
    }

    ticket.separator(char: '-', linesAfter: 1);
    TicketLayout.row(ticket, "Total Nota", "${summary.totalInvoiceCount}");

    TicketLayout.grandTotal(
      ticket,
      "GRAND TOTAL",
      summary.displayTotalTransaction,
    );

    ticket.feed(3);
    ticket.cut();

    return ticket;
  }

  Future<Ticket> _buildCafeItemsTicket(
    CashierClosingSummary summary,
    String cashierName,
  ) async {
    final ticket = await Ticket.create(PaperSize.mm80);

    ticket.text(
      "ITEM CAFE TERJUAL",
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.text(formatFullDate(summary.businessDate), align: PrintAlign.center);
    ticket.separator(char: '=', linesAfter: 1);

    TicketLayout.row(ticket, "Kasir", cashierName);
    ticket.separator(char: '-', linesAfter: 1);

    if (summary.cafeItems.isEmpty) {
      ticket.text(
        "Tidak ada penjualan cafe hari ini",
        align: PrintAlign.center,
      );
    } else {
      var totalQty = 0;
      for (final item in summary.cafeItems) {
        TicketLayout.row(ticket, item.productName, "${item.quantity}");
        totalQty += item.quantity;
      }
      ticket.separator(char: '-', linesAfter: 1);
      TicketLayout.row(ticket, "Total Item", "$totalQty");
    }

    ticket.feed(3);
    ticket.cut();

    return ticket;
  }

  /// Tunai bersih channel = tunai (CASH) − pengeluaran kas channel itu.
  /// Hanya dicetak kalau ada pengeluaran di channel tsb.
  void _cashRecon(
    Ticket ticket, {
    required int cash,
    required int expense,
    required int net,
  }) {
    if (expense <= 0) return;
    TicketLayout.row(ticket, "  Tunai (CASH)", formatCurrency(cash));
    TicketLayout.row(ticket, "  Pengeluaran", "-${formatCurrency(expense)}");
    TicketLayout.row(ticket, "  Tunai Bersih", formatCurrency(net));
  }

  void _byPayment(
    Ticket ticket,
    List<CashierPaymentBreakdown> byPayment, {
    int multiplier = 1,
  }) {
    for (final payment in byPayment) {
      TicketLayout.row(
        ticket,
        "  ${payment.paymentName}",
        "${formatCurrency(payment.totalTransaction * multiplier)} (${payment.invoiceCount})",
      );
    }
  }
}
