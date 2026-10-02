import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

import '../core/utils/formatters.dart';

/// Shared layout pieces for every printed receipt (table billing, cafe/POS,
/// tutup kas) so they read as one consistent design instead of three
/// independently hand-rolled layouts.
///
/// Bold is only ever applied via full-line [Ticket.text] calls here, never
/// inside a [Ticket.row] column: the plugin reinforces mid-line bold with a
/// bare-CR overstrike meant to overlap the same printed line on printers
/// that ignore inline ESC E, but this printer's firmware treats that CR as
/// a newline instead — turning the "reinforcement" into a literal
/// duplicate line. [grandTotal] gets its emphasis from size instead, which
/// is safe.
class TicketLayout {
  TicketLayout._();

  static void header(
    Ticket ticket, {
    required String businessName,
    required String businessAddress,
    required String invoiceNumber,
    required DateTime issuedAt,
    bool isReprint = false,
  }) {
    ticket.text(
      businessName,
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.text(businessAddress, align: PrintAlign.center);
    separator(ticket, char: '=', linesAfter: 1);
    ticket.text(
      invoiceNumber,
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.text(
      "${formatFullDate(issuedAt)}  ${formatClock(issuedAt)}",
      align: PrintAlign.center,
    );
    if (isReprint) {
      ticket.text(
        "*** PRINT ULANG ***",
        align: PrintAlign.center,
        style: const PrintTextStyle(bold: true),
      );
    }
    separator(ticket, char: '=', linesAfter: 1);
  }

  /// Lebar kertas 58mm = 32 karakter (font normal). Semua baris dibuat dari teks biasa yang
  /// di-pad spasi - TIDAK memakai ticket.row (posisi absolut ESC $), karena printer ini tidak
  /// mendukungnya sehingga kolom menempel & muncul karakter sampah.
  static const int width = 32;

  static void separator(
    Ticket ticket, {
    String char = '-',
    int linesAfter = 0,
  }) {
    ticket.separator(char: char, length: width, linesAfter: linesAfter);
  }

  /// Baris label kiri / nilai kanan dalam 1 baris teks biasa (label dibungkus kalau kepanjangan).
  static void row(Ticket ticket, String label, String value) {
    final v = value.length >= width ? value.substring(0, width) : value;
    final room = width - v.length - 1;
    if (room < 1) {
      ticket.text(label);
      ticket.text(v, align: PrintAlign.right);
      return;
    }
    final first = label.length <= room ? label : label.substring(0, room);
    ticket.text('${first.padRight(room)} $v');
    var rest = label.length <= room ? '' : label.substring(room);
    while (rest.isNotEmpty) {
      final n = rest.length <= width ? rest.length : width;
      ticket.text(rest.substring(0, n));
      rest = rest.substring(n);
    }
  }

  static void sectionTitle(Ticket ticket, String title) {
    ticket.feed(1);
    ticket.text(title, style: const PrintTextStyle(bold: true));
  }

  /// The final amount, set apart and enlarged so it's unmistakable —
  /// entirely via full-line text, never a row (see class doc).
  static void grandTotal(Ticket ticket, String label, int amount) {
    separator(ticket, char: '=', linesAfter: 1);
    ticket.text(label, style: const PrintTextStyle(bold: true));
    ticket.text(
      formatCurrency(amount),
      align: PrintAlign.right,
      style: const PrintTextStyle(
        bold: true,
        height: TextSize.size2,
        width: TextSize.size2,
      ),
    );
    separator(ticket, char: '=', linesAfter: 1);
  }

  static void footer(Ticket ticket, String cashierName) {
    row(ticket, "Kasir", cashierName);
    ticket.feed(1);
    ticket.text("Terima kasih atas kunjungan Anda", align: PrintAlign.center);
    ticket.feed(3);
    ticket.cut();
  }
}
