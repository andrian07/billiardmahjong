import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/pool_table.dart';
import '../../../models/promo.dart';
import '../../promo/data/promo_repository.dart';

class TableRepositoryException implements Exception {
  final String message;

  const TableRepositoryException(this.message);

  @override
  String toString() => message;
}

/// Reads the physical table roster via Billing/get_table_list.
///
/// `table_id` is kept as the table's identifier (used as the foreign key by
/// other endpoints), `table_number` is the human-facing table number,
/// `table_active` tells whether a session is currently running on it, and
/// `is_active` tells whether the table should be shown at all. A table can
/// also carry a booking (`table_mode`, customer, promo, start/end time,
/// duration, running bill) before it's actually marked active.
class TableRepository {
  final Dio _dio = Dio();
  final _promoRepository = PromoRepository();

  Future<List<PoolTable>> getTables() async {
    try {
      final response = await _dio.post(ApiEndpoints.tableList, data: const {});

      var data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          throw const TableRepositoryException("Format respons tidak valid.");
        }
      }
      if (data is! List) {
        throw const TableRepositoryException(
          "Format respons daftar meja tidak valid.",
        );
      }

      final rows = data
          .whereType<Map<String, dynamic>>()
          .where((json) => json['is_active']?.toString() == "1")
          .toList();

      final needsPromos = rows.any((json) {
        final promoId = int.tryParse(json['table_promo_id']?.toString() ?? "");
        return promoId != null && promoId != 0;
      });

      final promos = needsPromos ? await _fetchPromos() : const <int, Promo>{};

      return rows.map((json) => _tableFromJson(json, promos)).toList();
    } on TableRepositoryException {
      rethrow;
    } on DioException catch (_) {
      throw const TableRepositoryException(
        "Tidak dapat terhubung ke server. Periksa koneksi Anda.",
      );
    }
  }

  Future<Map<int, Promo>> _fetchPromos() async {
    try {
      final result = await _promoRepository.getPromos(page: 1, perPage: 1000);
      return {for (final p in result.promos) p.id: p};
    } catch (_) {
      return const {};
    }
  }

  PoolTable _tableFromJson(
    Map<String, dynamic> json,
    Map<int, Promo> promos,
  ) {
    final isRunning = json['table_active']?.toString() == "1";
    final number = json['table_number']?.toString() ?? "";
    final mode = json['table_mode']?.toString();
    final customerId = int.tryParse(
      json['table_customer_id']?.toString() ?? "",
    );
    // nama member diambil dari snapshot yang disimpan billing_api saat buka meja
    // (billing_api sendiri mengambilnya dari gameon/online) - lihat Billing::book_table
    final memberName = json['table_customer_name']?.toString();
    final promoId = int.tryParse(json['table_promo_id']?.toString() ?? "");
    final promo = (promoId != null && promoId != 0) ? promos[promoId] : null;
    final startAt = _parseDateTime(json['table_start_time']?.toString());
    final endAt = _parseDateTime(json['table_end_time']?.toString());

    return PoolTable(
      id: json['table_id']?.toString() ?? "",
      name: "Meja $number",
      status: isRunning ? TableStatus.playing : TableStatus.ready,
      categoryMejaId: int.tryParse(json['table_category']?.toString() ?? ""),
      badge: mode,
      sessionType: _parseSessionType(mode),
      startTime: startAt != null ? formatTime(startAt) : null,
      endTime: endAt != null ? formatTime(endAt) : null,
      startAt: startAt,
      endAt: endAt,
      plannedDuration: _parseDuration(json['table_duration']?.toString()),
      usedSavedTime: _parseYesNo(json['use_saved_time']?.toString()),
      prepaidSaldo: json['prepaid_saldo']?.toString().toUpperCase() == "Y",
      saldoPrepaidAmount:
          int.tryParse(json['saldo_prepaid_amount']?.toString() ?? "") ?? 0,
      customerId: (customerId != null && customerId != 0) ? customerId : null,
      memberName: (memberName != null && memberName.trim().isNotEmpty)
          ? memberName
          : null,
      promoId: (promoId != null && promoId != 0) ? promoId : null,
      promoName: promo?.name,
      promoType: promo?.type,
      currentBill: int.tryParse(json['table_bill']?.toString() ?? ""),
    );
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

  bool? _parseYesNo(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value.trim().toUpperCase() == "Y";
  }

  DateTime? _parseDateTime(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim());
  }

  Duration? _parseDuration(String? value) {
    if (value == null || value.trim().isEmpty) return null;

    final parts = value.trim().split(':');
    if (parts.length != 3) return null;

    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    final seconds = int.tryParse(parts[2]);
    if (hours == null || minutes == null || seconds == null) return null;

    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }
}
