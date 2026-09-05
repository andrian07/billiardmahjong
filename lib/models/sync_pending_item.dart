import 'pagination_info.dart';

/// Which local table a pending sync row comes from — mirrors Sync.php's
/// `$valid_types`. The string value is exactly what's sent back to
/// Sync/retry as `type`.
enum SyncSourceType {
  transaction("transaction", "Billing"),
  transactionCafe("transaction_cafe", "Cafe / POS"),
  transaksiSaldo("transaksi_saldo", "Pengisian Saldo"),
  purchase("purchase", "Pembelian"),
  tableStatusEvent("table_status_event", "Status Meja");

  final String apiValue;
  final String label;

  const SyncSourceType(this.apiValue, this.label);

  static SyncSourceType fromApiValue(String? value) {
    return SyncSourceType.values.firstWhere(
      (t) => t.apiValue == value,
      orElse: () => SyncSourceType.transaction,
    );
  }
}

/// One local row (transaksi billing/cafe/saldo atau pembelian) whose
/// `*_upload_status` is still 'N' — belum pernah berhasil ke-push ke laporan
/// online (gameon). See Sync::pending() in billing_api.
class SyncPendingItem {
  final SyncSourceType type;
  final int id;
  final String inv;
  final String date;
  final int total;
  final int branch;
  final String createdBy;
  final DateTime? createdAt;
  final String status;

  const SyncPendingItem({
    required this.type,
    required this.id,
    required this.inv,
    required this.date,
    required this.total,
    required this.branch,
    required this.createdBy,
    this.createdAt,
    required this.status,
  });

  factory SyncPendingItem.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) {
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? "") ?? 0;
    }

    return SyncPendingItem(
      type: SyncSourceType.fromApiValue(json['type']?.toString()),
      id: asInt(json['id']),
      inv: json['inv']?.toString() ?? "",
      date: json['date']?.toString() ?? "",
      total: asInt(json['total']),
      branch: asInt(json['branch']),
      createdBy: json['created_by']?.toString() ?? "",
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ""),
      status: json['status']?.toString() ?? "",
    );
  }
}

/// Per-source pending counts from Sync::pending()'s `counts` — drives the
/// summary chips at the top of the Sinkron Online page.
class SyncPendingCounts {
  final int transaction;
  final int transactionCafe;
  final int transaksiSaldo;
  final int purchase;
  final int tableStatusEvent;

  const SyncPendingCounts({
    this.transaction = 0,
    this.transactionCafe = 0,
    this.transaksiSaldo = 0,
    this.purchase = 0,
    this.tableStatusEvent = 0,
  });

  static const empty = SyncPendingCounts();

  int get total =>
      transaction + transactionCafe + transaksiSaldo + purchase + tableStatusEvent;

  factory SyncPendingCounts.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) {
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? "") ?? 0;
    }

    return SyncPendingCounts(
      transaction: asInt(json['transaction']),
      transactionCafe: asInt(json['transaction_cafe']),
      transaksiSaldo: asInt(json['transaksi_saldo']),
      purchase: asInt(json['purchase']),
      tableStatusEvent: asInt(json['table_status_event']),
    );
  }
}

class SyncPendingResult {
  final List<SyncPendingItem> items;
  final PaginationInfo pagination;
  final SyncPendingCounts counts;

  const SyncPendingResult({
    required this.items,
    required this.pagination,
    required this.counts,
  });
}
