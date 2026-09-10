/// One row of a member's saldo ledger (gameon `history_saldo`). The Detail
/// Member dialog only ever requests deductions (`history_saldo_type = 'OUT'`),
/// so [isOut] is effectively always true here, but it is parsed anyway.
class CustomerSaldoHistoryEntry {
  final int id;

  /// Rupiah amount that moved on this row.
  final int amount;

  /// true = OUT (saldo dipotong), false = IN.
  final bool isOut;

  final String description;
  final String refType;
  final int? saldoBefore;
  final int? saldoAfter;
  final String createdBy;
  final DateTime? at;

  const CustomerSaldoHistoryEntry({
    required this.id,
    required this.amount,
    required this.isOut,
    required this.description,
    required this.refType,
    required this.saldoBefore,
    required this.saldoAfter,
    required this.createdBy,
    required this.at,
  });

  factory CustomerSaldoHistoryEntry.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      return int.tryParse(v?.toString() ?? "") ?? 0;
    }

    int? asIntOrNull(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
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

    return CustomerSaldoHistoryEntry(
      id: asInt(json['id']),
      amount: asInt(json['amount']),
      isOut: (json['movement']?.toString().toUpperCase() ?? "OUT") == "OUT",
      description: json['description']?.toString() ?? "",
      refType: json['ref_type']?.toString() ?? "",
      saldoBefore: asIntOrNull(json['saldo_before']),
      saldoAfter: asIntOrNull(json['saldo_after']),
      createdBy: json['created_by']?.toString() ?? "",
      at: parseAt(),
    );
  }
}
