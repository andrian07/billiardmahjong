import 'dart:async';

import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

import '../core/utils/formatters.dart';
import '../models/cafe_receipt.dart';
import '../models/cart_item.dart';
import '../models/receipt.dart';
import '../models/saldo_receipt.dart';
import 'printer_filter.dart';
import 'printer_preference_storage.dart';
import 'ticket_layout.dart';

class ReceiptPrinterException implements Exception {
  final String message;

  const ReceiptPrinterException(this.message);

  @override
  String toString() => message;
}

/// Thrown when no USB printer is connected at all — callers catch this
/// separately to fall back to [TicketPreviewDialog] instead of an error toast.
class ReceiptPrinterNotFoundException extends ReceiptPrinterException {
  const ReceiptPrinterNotFoundException()
    : super(
        "Printer USB tidak ditemukan. Pastikan printer terhubung dan menyala.",
      );
}

class ReceiptPrinterService {
  Future<void> printReceipt(Receipt receipt) {
    return _print(buildTicket: () => _buildTicket(receipt));
  }

  Future<void> printCafeReceipt(CafeReceipt receipt) {
    return _print(buildTicket: () => _buildCafeTicket(receipt));
  }

  Future<void> printSaldoReceipt(SaldoReceipt receipt) {
    return _print(buildTicket: () => _buildSaldoTicket(receipt));
  }

  /// Kitchen order slip for a POS "keep" (parked order) save — [items] is
  /// just what's new in *this* save, not the whole held cart, so re-saving
  /// onto an existing hold only sends the kitchen the items it hasn't seen
  /// yet.
  Future<void> printKitchenOrder({
    required String keepCode,
    String? customerName,
    required List<CartItem> items,
  }) {
    return _print(
      buildTicket: () => _buildKitchenTicket(keepCode, customerName, items),
    );
  }

  /// Slip cetak untuk booking room yang baru masuk dari aplikasi member —
  /// dicetak otomatis oleh [BookingWatcher] begitu booking terdeteksi, biar
  /// kasir langsung tahu ruangan mana yang harus disiapkan. Formatnya sengaja
  /// ringkas: Nama / Hari / Jam / Jumlah Jam / Ruangan.
  Future<void> printBookingSlip({
    required String customerName,
    required DateTime start,
    required int durationHours,
    required String roomLabel,
  }) {
    return _print(
      buildTicket: () => _buildBookingSlipTicket(
        customerName: customerName,
        start: start,
        durationHours: durationHours,
        roomLabel: roomLabel,
      ),
    );
  }

  Future<Ticket> _buildBookingSlipTicket({
    required String customerName,
    required DateTime start,
    required int durationHours,
    required String roomLabel,
  }) async {
    final ticket = await Ticket.create(PaperSize.mm80);

    ticket.text(
      "BOOKING ROOM",
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.text(
      "Masuk ${formatFullDate(DateTime.now())} ${formatClock(DateTime.now())}",
      align: PrintAlign.center,
    );
    ticket.separator(char: '=', linesAfter: 1);

    TicketLayout.row(ticket, "Nama", customerName);
    TicketLayout.row(ticket, "Hari", formatWeekdayFullDate(start));
    TicketLayout.row(ticket, "Jam", formatTime(start));
    TicketLayout.row(ticket, "Jumlah Jam", "$durationHours jam");
    TicketLayout.row(ticket, "Ruangan", roomLabel);

    ticket.separator(char: '=', linesAfter: 1);
    ticket.feed(3);
    ticket.cut();

    return ticket;
  }

  /// Prints a short dummy receipt to [device] so the operator can confirm,
  /// straight from the printer picker, that the printer they just selected
  /// actually prints — without saving the choice or running a real
  /// transaction. [device] is the in-memory pick from the dialog, which may
  /// not be the saved selection yet, so this bypasses [PrinterPreferenceStorage].
  Future<void> printTestReceipt(PrinterDevice device) async {
    final manager = PrinterManager();
    try {
      await _runTest(manager, device).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw const ReceiptPrinterException(
          "Printer tidak merespon dalam 15 detik. Periksa koneksi printer, "
          "pastikan printer menyala, lalu coba lagi.",
        ),
      );
    } on PrinterException catch (e) {
      throw ReceiptPrinterException(
        e.cause != null ? "${e.message} — ${e.cause}" : e.message,
      );
    } finally {
      unawaited(
        manager.dispose().timeout(const Duration(seconds: 3), onTimeout: () {}),
      );
    }
  }

  Future<void> _runTest(PrinterManager manager, PrinterDevice device) async {
    // LAN: connect straight to host:port, same as a real receipt print.
    if (device is NetworkPrinterDevice) {
      await manager.connect(device);
      await manager.printTicket(await _buildTestTicket());
      await manager.disconnect();
      return;
    }

    // USB: re-scan and match by identifier so we connect through a fresh
    // device handle from *this* manager (mirrors [_run]).
    final printers = await manager.scanPrinters(
      types: {PrinterConnectionType.usb},
    );
    if (printers.isEmpty) {
      throw const ReceiptPrinterException(
        "Printer USB tidak ditemukan. Pastikan printer terhubung dan menyala.",
      );
    }
    final wantedId = device is UsbPrinterDevice ? device.identifier : null;
    final match = printers.firstWhere(
      (p) => p is UsbPrinterDevice && p.identifier == wantedId,
      orElse: () => excludeVirtualPrinters(printers).first,
    );
    await manager.connect(match);
    await manager.printTicket(await _buildTestTicket());
    await manager.disconnect();
  }

  Future<Ticket> _buildTestTicket() async {
    final ticket = await Ticket.create(PaperSize.mm80);
    final now = DateTime.now();

    ticket.text(
      "TEST PRINT",
      align: PrintAlign.center,
      style: const PrintTextStyle(
        bold: true,
        height: TextSize.size2,
        width: TextSize.size2,
      ),
    );
    ticket.separator(char: '=', linesAfter: 1);
    ticket.text("Nota dummy - bukan transaksi", align: PrintAlign.center);
    ticket.text(
      "${formatFullDate(now)}  ${formatClock(now)}",
      align: PrintAlign.center,
    );
    ticket.separator(char: '=', linesAfter: 1);

    TicketLayout.row(ticket, "Meja", "Meja 01");
    TicketLayout.row(ticket, "Durasi", "1 jam");
    ticket.feed(1);
    ticket.text("Kopi Hitam", style: const PrintTextStyle(bold: true));
    TicketLayout.row(
      ticket,
      "  1 x ${formatCurrency(15000)}",
      formatCurrency(15000),
    );
    ticket.separator(char: '-', linesAfter: 1);
    TicketLayout.row(ticket, "Subtotal", formatCurrency(15000));
    TicketLayout.grandTotal(ticket, "GRAND TOTAL", 15000);
    TicketLayout.row(ticket, "Bayar", "Tunai");

    ticket.feed(1);
    ticket.text(
      "Jika struk ini tercetak rapi,\nprinter siap digunakan.",
      align: PrintAlign.center,
    );
    ticket.feed(3);
    ticket.cut();

    return ticket;
  }

  /// Shared USB scan/connect/print/disconnect flow — [buildTicket] builds
  /// whichever ticket layout the caller needs.
  Future<void> _print({required Future<Ticket> Function() buildTicket}) async {
    final manager = PrinterManager();

    try {
      await _run(manager, buildTicket).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw const ReceiptPrinterException(
          "Printer tidak merespon dalam 15 detik. Periksa kabel USB, "
          "pastikan printer menyala, lalu coba lagi.",
        ),
      );
    } on PrinterException catch (e) {
      throw ReceiptPrinterException(
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

    // LAN printer: connect straight to the saved host:port — no scan needed
    // (subnet discovery is slow and often finds nothing on wired networks).
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
      throw const ReceiptPrinterNotFoundException();
    }

    await manager.connect(pickPrinter(printers, selection));
    await manager.printTicket(await buildTicket());
    await manager.disconnect();
  }

  Future<Ticket> _buildTicket(Receipt receipt) async {
    final ticket = await Ticket.create(PaperSize.mm80);

    TicketLayout.header(
      ticket,
      businessName: receipt.businessName,
      businessAddress: receipt.businessAddress,
      invoiceNumber: receipt.invoiceNumber,
      issuedAt: receipt.date,
      isReprint: receipt.isReprint,
    );

    TicketLayout.row(ticket, "Meja", receipt.tableLabel);
    TicketLayout.row(ticket, "Mulai", formatClock(receipt.startAt));
    TicketLayout.row(ticket, "Selesai", formatClock(receipt.endAt));
    TicketLayout.row(
      ticket,
      "Durasi",
      formatDurationWords(receipt.totalDuration),
    );

    if (receipt.periods.isNotEmpty) {
      TicketLayout.sectionTitle(ticket, "Rincian Waktu");
      for (final period in receipt.periods) {
        TicketLayout.row(ticket, period.label, formatCurrency(period.cost * 2));
        TicketLayout.row(ticket, "  Durasi", formatDuration(period.duration));
      }
    }

    ticket.separator(char: '-', linesAfter: 1);
    TicketLayout.row(ticket, "Subtotal", formatCurrency(receipt.subtotal * 2));
    if (receipt.promoName != null) {
      TicketLayout.row(ticket, "Promo", receipt.promoName!);
    }
    if (receipt.discountAmount > 0) {
      TicketLayout.row(
        ticket,
        "Diskon",
        "-${formatCurrency(receipt.discountAmount * 2)}",
      );
    }

    TicketLayout.grandTotal(ticket, "GRAND TOTAL", receipt.grandTotal * 2);

    TicketLayout.row(ticket, "Bayar", receipt.paymentMethod);
    TicketLayout.footer(ticket, receipt.cashierName);

    return ticket;
  }

  Future<Ticket> _buildCafeTicket(CafeReceipt receipt) async {
    final ticket = await Ticket.create(PaperSize.mm80);

    TicketLayout.header(
      ticket,
      businessName: receipt.businessName,
      businessAddress: receipt.businessAddress,
      invoiceNumber: receipt.invoiceNumber,
      issuedAt: receipt.date,
      isReprint: receipt.isReprint,
    );

    if (receipt.table != null) {
      TicketLayout.row(ticket, "Meja", receipt.table!);
    } else {
      final name = receipt.customerName?.trim();
      TicketLayout.row(
        ticket,
        "Customer",
        (name != null && name.isNotEmpty) ? name : "-",
      );
    }

    ticket.feed(1);
    for (final item in receipt.items) {
      ticket.text(item.name, style: const PrintTextStyle(bold: true));
      if (item.note != null) {
        ticket.text("  (${item.note})");
      }
      TicketLayout.row(
        ticket,
        "  ${item.quantity} x ${formatCurrency(item.price)}",
        formatCurrency(item.price * item.quantity),
      );
      for (final addon in item.addons) {
        TicketLayout.row(
          ticket,
          "  + ${addon.name} x${addon.quantity}",
          formatCurrency(addon.lineTotal),
        );
      }
    }

    ticket.separator(char: '-', linesAfter: 1);
    TicketLayout.row(ticket, "Subtotal", formatCurrency(receipt.subtotal));
    if (receipt.discountAmount > 0) {
      TicketLayout.row(
        ticket,
        "Diskon (${receipt.discountPercent}%)",
        "-${formatCurrency(receipt.discountAmount)}",
      );
    }
    if (receipt.tax > 0) {
      TicketLayout.row(ticket, "Pajak", formatCurrency(receipt.tax));
    }

    TicketLayout.grandTotal(ticket, "TOTAL", receipt.total);

    TicketLayout.row(ticket, "Bayar", receipt.paymentMethod);
    TicketLayout.footer(ticket, receipt.cashierName);

    return ticket;
  }

  Future<Ticket> _buildSaldoTicket(SaldoReceipt receipt) async {
    final ticket = await Ticket.create(PaperSize.mm80);

    TicketLayout.header(
      ticket,
      businessName: receipt.businessName,
      businessAddress: receipt.businessAddress,
      invoiceNumber: receipt.invoiceNumber,
      issuedAt: receipt.date,
    );

    TicketLayout.row(ticket, "Member", receipt.customerName);
    TicketLayout.row(ticket, "Nominal Saldo", formatCurrency(receipt.nominal));
    if (receipt.discount > 0) {
      TicketLayout.row(ticket, "Diskon", formatCurrency(receipt.discount));
    }

    TicketLayout.grandTotal(ticket, "TOTAL DIBAYAR", receipt.price);

    TicketLayout.row(ticket, "Bayar", receipt.paymentMethod);
    TicketLayout.footer(ticket, receipt.cashierName);

    return ticket;
  }

  Future<Ticket> _buildKitchenTicket(
    String keepCode,
    String? customerName,
    List<CartItem> items,
  ) async {
    final ticket = await Ticket.create(PaperSize.mm80);
    final now = DateTime.now();

    ticket.text(
      "PESANAN DAPUR",
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.separator(char: '=', linesAfter: 1);

    final name = customerName?.trim();
    TicketLayout.row(
      ticket,
      "Customer",
      (name != null && name.isNotEmpty) ? name : "-",
    );
    TicketLayout.row(ticket, "Kode", keepCode);
    ticket.text("${formatFullDate(now)}  ${formatClock(now)}");
    ticket.separator(char: '=', linesAfter: 1);

    for (final item in items) {
      ticket.text(
        "${item.quantity} x ${item.product.name}",
        style: const PrintTextStyle(bold: true),
      );
      final note = item.note?.trim();
      if (note != null && note.isNotEmpty) {
        ticket.text("  ($note)");
      }
      for (final addon in item.addons) {
        ticket.text("  + ${addon.quantity} x ${addon.product.name}");
      }
      ticket.feed(1);
    }

    ticket.separator(char: '=', linesAfter: 1);
    ticket.feed(3);
    ticket.cut();

    return ticket;
  }
}
