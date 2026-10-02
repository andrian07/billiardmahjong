import '../../../core/constants/business_info.dart';
import '../../../models/pool_table.dart';
import '../../../models/receipt.dart';
import '../widgets/payment_dialog.dart';

/// Builds invoice data for the receipt printer, from the table and the
/// payment result — [PaymentResult] already carries the real subtotal,
/// promo discount, and total computed by [PaymentDialog]'s pricing logic.
class InvoiceRepository {
  int _localSequence = 0;

  Future<Receipt> generateInvoice(
    PoolTable table,
    PaymentResult payment, {
    required String cashierName,
  }) {
    final now = DateTime.now();
    final start = table.startAt ?? now;
    // Timer: nota memakai akhir durasi (bukan jam bayar) kalau bayar setelah timer habis.
    final timerEnd = table.sessionType == SessionType.timer
        ? table.endAt
        : null;
    final end = (timerEnd != null && timerEnd.isBefore(now)) ? timerEnd : now;
    final duration = end.difference(start);

    _localSequence++;

    return Future.value(
      Receipt(
        businessName: BusinessInfo.name,
        businessAddress: BusinessInfo.address,
        invoiceNumber: _buildInvoiceNumber(now),
        tableLabel: "${_tableNumber(table)} - ${_sessionLabel(table)}",
        periods: const [],
        date: now,
        startAt: start,
        endAt: end,
        totalDuration: duration.isNegative ? Duration.zero : duration,
        subtotal: payment.subtotal,
        discountAmount: payment.discountAmount,
        promoName: payment.promo,
        grandTotal: payment.total,
        paymentMethod: payment.paymentMethod,
        cashierName: cashierName,
      ),
    );
  }

  String _buildInvoiceNumber(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    final date = "${now.year}-${two(now.month)}-${two(now.day)}";
    return "INV/${BusinessInfo.outletCode}/$date/${_localSequence.toString().padLeft(10, '0')}";
  }

  String _tableNumber(PoolTable table) =>
      table.name.replaceAll(RegExp(r'[^0-9]'), '');

  String _sessionLabel(PoolTable table) {
    switch (table.sessionType) {
      case SessionType.timer:
        return "Timer";
      case SessionType.reguler:
        return "Reguler";
      case null:
        return "-";
    }
  }
}
