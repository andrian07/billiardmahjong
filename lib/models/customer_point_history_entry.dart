/// One row of a member's point ledger (gameon `customer_point_history`). The
/// Detail Member dialog only ever requests deductions (`movement_type = 'OUT'`),
/// so [isOut] is effectively always true here, but it is parsed anyway.
class CustomerPointHistoryEntry {
  final int id;

  /// Number of points that moved on this row.
  final int point;

  /// true = OUT (point dipotong), false = IN.
  final bool isOut;

  final String description;
  final String refType;
  final int? pointBefore;
  final int? pointAfter;
  final String createdBy;
  final DateTime? at;

  const CustomerPointHistoryEntry({
    required this.id,
    required this.point,
    required this.isOut,
    required this.description,
    required this.refType,
    required this.pointBefore,
    required this.pointAfter,
    required this.createdBy,
    required this.at,
  });

  factory CustomerPointHistoryEntry.fromJson(Map<String, dynamic> json) {
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

    return CustomerPointHistoryEntry(
      id: asInt(json['id']),
      point: asInt(json['point']),
      isOut: (json['movement']?.toString().toUpperCase() ?? "OUT") == "OUT",
      description: json['description']?.toString() ?? "",
      refType: json['ref_type']?.toString() ?? "",
      pointBefore: asIntOrNull(json['point_before']),
      pointAfter: asIntOrNull(json['point_after']),
      createdBy: json['created_by']?.toString() ?? "",
      at: parseAt(),
    );
  }
}
