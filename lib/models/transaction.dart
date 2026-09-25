import 'pool_table.dart';

enum TransactionStatus { completed, canceled }

class Transaction {
  final int id;
  final String invoiceNumber;
  final DateTime date;
  final DateTime startAt;
  final DateTime endAt;
  final String tableName;
  final String? customerName;
  final String? promoName;
  final String cashierName;
  final int paymentId;
  final String paymentMethod;
  final int total;
  final TransactionStatus status;

  /// 'billiard' or 'mahjong' — snapshot taken at payment time (see
  /// Billing_model::add_transaction on the backend), used to filter the
  /// Billing tab on the Transaksi page.
  final String categoryType;

  /// Who cancelled this transaction, if [status] is canceled.
  final String? cancelledBy;

  /// 'Normal' or 'Gunakan Timer' (paid using the customer's saved-time
  /// balance) — used alongside [paymentMethod] to decide whether the Cancel
  /// button can be shown (see Billing_model::cancel_transaction on the
  /// backend: both "Potong Saldo" and "Gunakan Timer" are rejected there
  /// because the deducted saldo/time has no stored ref to refund).
  final String paymentType;

  const Transaction({
    required this.id,
    required this.invoiceNumber,
    required this.date,
    required this.startAt,
    required this.endAt,
    required this.tableName,
    this.customerName,
    this.promoName,
    required this.cashierName,
    required this.paymentId,
    required this.paymentMethod,
    required this.total,
    this.status = TransactionStatus.completed,
    this.categoryType = "billiard",
    this.cancelledBy,
    this.paymentType = "Normal",
  });

  factory Transaction.fromJson(
    Map<String, dynamic> json, {
    String? customerName,
    String? promoName,
    String? paymentMethodName,
  }) {
    final date = _parseDate(json['date']);

    return Transaction(
      id: _asInt(json['id']),
      invoiceNumber: json['inv']?.toString() ?? "",
      date: date,
      startAt: _combineDateTime(date, json['start_time']?.toString()),
      endAt: _combineDateTime(date, json['end_time']?.toString()),
      tableName: _tableLabel(json),
      customerName: customerName,
      promoName: promoName,
      cashierName: json['created_by']?.toString() ?? "",
      paymentId: _asInt(json['payment_id']),
      paymentMethod: paymentMethodName ?? "-",
      total: _asInt(json['total_bill']),
      status: _parseStatus(json['status']),
      categoryType: json['category_type']?.toString() == "mahjong"
          ? "mahjong"
          : "billiard",
      cancelledBy: json['cancelled_by']?.toString(),
      paymentType: json['payment_type']?.toString() ?? "Normal",
    );
  }
}

/// Detail of a single transaction — Billing/transaction_detail already
/// resolves the member name and full promo object server-side, so unlike the
/// list endpoint no separate customer/promo lookup is needed here.
class TransactionDetail {
  final int id;
  final String invoiceNumber;
  final DateTime date;
  final SessionType? mode;
  final DateTime startAt;
  final DateTime endAt;
  final int subTotal;
  final int discount;
  final int tax;
  final int totalBill;
  final String tableName;
  final TransactionStatus status;
  final String createdBy;
  final int paidBy;
  final String paymentMethod;
  final String? memberName;
  final String? promoName;

  const TransactionDetail({
    required this.id,
    required this.invoiceNumber,
    required this.date,
    this.mode,
    required this.startAt,
    required this.endAt,
    required this.subTotal,
    required this.discount,
    required this.tax,
    required this.totalBill,
    required this.tableName,
    required this.status,
    required this.createdBy,
    required this.paidBy,
    required this.paymentMethod,
    this.memberName,
    this.promoName,
  });

  factory TransactionDetail.fromJson(
    Map<String, dynamic> json, {
    String? paymentMethodName,
  }) {
    final date = _parseDate(json['date']);
    final promoJson = json['promo'];

    return TransactionDetail(
      id: _asInt(json['id']),
      invoiceNumber: json['inv']?.toString() ?? "",
      date: date,
      mode: _parseSessionType(json['mode']?.toString()),
      startAt: _combineDateTime(date, json['start_time']?.toString()),
      endAt: _combineDateTime(date, json['end_time']?.toString()),
      subTotal: _asInt(json['sub_total']),
      discount: _asInt(json['discount']),
      tax: _asInt(json['tax']),
      totalBill: _asInt(json['total_bill']),
      tableName: _tableLabel(json),
      status: _parseStatus(json['status']),
      createdBy: json['created_by']?.toString() ?? "",
      paidBy: _asInt(json['paid_by']),
      paymentMethod: paymentMethodName ?? "-",
      memberName: json['member_name']?.toString(),
      promoName: promoJson is Map<String, dynamic>
          ? promoJson['name']?.toString()
          : null,
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? "") ?? 0;
}

/// "Meja Private 1" / "Meja VVIP" / "Meja 01" — same "Meja `table_number`"
/// convention as the live table grid (see table_repository.dart), using the
/// real table_active.table_number the backend now joins in (`table_number`)
/// instead of the raw `table` id (transaction_table FK), which used to be
/// zero-padded and shown as-is (e.g. "Meja 13" for a table actually named
/// "VVIP"). Falls back to the old id-based label only against a server that
/// hasn't been updated yet (no `table_number` key at all).
String _tableLabel(Map<String, dynamic> json) {
  final tableNumber = json['table_number']?.toString().trim();
  if (tableNumber != null && tableNumber.isNotEmpty) return "Meja $tableNumber";

  if (!json.containsKey('table_number')) {
    return "Meja ${_asInt(json['table']).toString().padLeft(2, '0')}";
  }
  return "Meja -";
}

DateTime _parseDate(dynamic value) {
  return DateTime.tryParse(value?.toString() ?? "") ?? DateTime.now();
}

TransactionStatus _parseStatus(dynamic value) {
  return value?.toString().toLowerCase() == "done"
      ? TransactionStatus.completed
      : TransactionStatus.canceled;
}

SessionType? _parseSessionType(String? mode) {
  switch (mode?.trim().toLowerCase()) {
    case "timer":
      return SessionType.timer;
    case "reguler":
    case "regular":
      return SessionType.reguler;
    default:
      return null;
  }
}

/// `start_time`/`end_time` come back either as a bare "HH:mm:ss" or a full
/// "yyyy-MM-dd HH:mm:ss" depending on the record, so both are handled here.
DateTime _combineDateTime(DateTime date, String? time) {
  if (time == null || time.trim().isEmpty) {
    return DateTime(date.year, date.month, date.day);
  }

  if (time.contains('-')) {
    final full = DateTime.tryParse(time);
    if (full != null) return full;
  }

  final parts = time.split(':');
  final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final second = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;

  return DateTime(date.year, date.month, date.day, hour, minute, second);
}
