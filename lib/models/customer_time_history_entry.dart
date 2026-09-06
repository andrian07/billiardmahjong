import '../core/utils/formatters.dart';

/// Satu baris "kartu stok" waktu tersimpan member: mutasi IN (disimpan / refund)
/// atau OUT (dipakai buka meja). Sumber: Billing/customer_time_history (proxy ke
/// gameon).
class CustomerTimeHistoryEntry {
  final int id;
  final int categoryMejaId;
  final String categoryMejaName;

  /// Jumlah waktu yang bergerak pada baris ini (bukan saldo).
  final Duration amount;

  /// true = IN (nambah), false = OUT (kepakai).
  final bool isIn;

  final String? ref;
  final String createdBy;
  final DateTime? at;

  const CustomerTimeHistoryEntry({
    required this.id,
    required this.categoryMejaId,
    required this.categoryMejaName,
    required this.amount,
    required this.isIn,
    required this.ref,
    required this.createdBy,
    required this.at,
  });

  factory CustomerTimeHistoryEntry.fromJson(Map<String, dynamic> json) {
    Duration parseHms(dynamic v) {
      final p = (v?.toString() ?? "").split(":");
      if (p.length != 3) return Duration.zero;
      return Duration(
        hours: int.tryParse(p[0]) ?? 0,
        minutes: int.tryParse(p[1]) ?? 0,
        seconds: int.tryParse(p[2]) ?? 0,
      );
    }

    DateTime? parseAt() {
      final raw = json['created_at']?.toString();
      if (raw != null && raw.isNotEmpty) {
        final d = DateTime.tryParse(raw.replaceFirst(" ", "T"));
        if (d != null) return d;
      }
      return DateTime.tryParse(
        "${json['date'] ?? ''}T${json['time'] ?? '00:00:00'}",
      );
    }

    return CustomerTimeHistoryEntry(
      id: int.tryParse(json['id'].toString()) ?? 0,
      categoryMejaId: int.tryParse(json['category_meja_id'].toString()) ?? 0,
      categoryMejaName: json['category_meja_name']?.toString() ?? "-",
      amount: parseHms(json['amount']),
      isIn: (json['movement']?.toString().toUpperCase() ?? "OUT") == "IN",
      ref: (json['ref']?.toString().isNotEmpty ?? false)
          ? json['ref'].toString()
          : null,
      createdBy: json['created_by']?.toString() ?? "",
      at: parseAt(),
    );
  }

  String get amountLabel => "${isIn ? '+' : '−'}${formatDuration(amount)}";
}
