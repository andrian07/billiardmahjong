import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/customer_time_history_entry.dart';
import '../../../models/pool_table.dart';
import '../../../models/saved_customer_time.dart';
import 'member_approval_repository.dart';

class BillingRepositoryException implements Exception {
  final String message;

  const BillingRepositoryException(this.message);

  @override
  String toString() => message;
}

/// Dilempar oleh [BillingRepository.bookTable] kalau backend mengembalikan
/// peringatan booking (bentrok dengan booking member / data booking basi).
/// Bukan error keras - kasir boleh lanjut dengan memanggil ulang bookTable
/// memakai `ignoreBookingWarning: true`.
class BookingWarningException implements Exception {
  final List<String> warnings;

  const BookingWarningException(this.warnings);

  @override
  String toString() => warnings.join("\n");
}

class PriceCalculation {
  final int totalBilling;
  final int totalPromo;
  final int totalTax;
  final int totalPembulatan;
  final int totalTransaksi;

  const PriceCalculation({
    required this.totalBilling,
    required this.totalPromo,
    required this.totalTax,
    required this.totalPembulatan,
    required this.totalTransaksi,
  });

  factory PriceCalculation.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) {
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? "") ?? 0;
    }

    return PriceCalculation(
      totalBilling: asInt(json['total_billing']),
      totalPromo: asInt(json['total_promo']),
      totalTax: asInt(json['total_tax']),
      totalPembulatan: asInt(json['total_pembulatan']),
      totalTransaksi: asInt(json['total_transaksi']),
    );
  }
}

/// Books/starts table sessions and computes their bill via the Billing/*
/// endpoints.
class BillingRepository {
  final Dio _dio = Dio();

  Future<void> bookTable({
    required String tableId,
    required SessionType mode,
    required DateTime startTime,
    int? customerId,
    int? promoId,
    DateTime? endTime,
    Duration? duration,
    bool? useSavedTime,
    bool? prepaidSaldo,
    String? createdBy,
    bool ignoreBookingWarning = false,
    String? memberApprovalRef,
  }) async {
    final payload = <String, dynamic>{
      "table_id": tableId,
      "table_mode": mode == SessionType.timer ? "Timer" : "Reguler",
      "table_start_time": formatApiDateTime(startTime),
      if (customerId != null) "table_customer_id": "$customerId",
      if (promoId != null) "table_promo_id": "$promoId",
      if (endTime != null) "table_end_time": formatApiDateTime(endTime),
      if (duration != null) "table_duration": formatDuration(duration),
      if (useSavedTime != null) "use_saved_time": useSavedTime ? "Y" : "N",
      if (prepaidSaldo != null) "prepaid_saldo": prepaidSaldo ? "Y" : "N",
      if (createdBy != null) "created_by": createdBy,
      if (ignoreBookingWarning) "ignore_booking_warning": "Y",
      if (memberApprovalRef != null) "member_approval_ref": memberApprovalRef,
    };

    final data = await _post(ApiEndpoints.bookTable, payload);

    // backend memakai result == "BOOKING_WARNING" (code tetap 200) untuk minta
    // konfirmasi kasir sebelum benar-benar membuka meja
    if (data['result'] == 'BOOKING_WARNING') {
      final raw = data['warnings'];
      final warnings = raw is List
          ? raw.map((e) => e.toString()).toList()
          : <String>["Data booking perlu diperiksa sebelum membuka meja."];
      throw BookingWarningException(warnings);
    }

    // buka meja dengan "pakai waktu tersimpan": saldo waktu dipotong di sini, jadi
    // backend menahan sampai member konfirmasi PIN di aplikasi GAMEON
    if (data['result'] == 'NEED_MEMBER_APPROVAL') {
      final approval = data['approval'];
      throw MemberApprovalRequiredException.fromApproval(
        memberApprovalRef ?? "",
        approval is Map<String, dynamic> ? approval : null,
      );
    }
  }

  /// Looks up a customer's banked play time for the given table's category
  /// via Master/get_save_customer_time — used by the start-session dialog to
  /// offer "pakai waktu tersisa?" when a member with a balance is selected.
  /// Returns null when the lookup itself fails (e.g. table/category not
  /// set up), since that just means no saved-time offer should be shown.
  Future<SavedCustomerTime?> getSavedCustomerTime({
    required int customerId,
    required String tableId,
  }) async {
    try {
      final data = await _post(ApiEndpoints.getSaveCustomerTime, {
        "customer_id": customerId,
        "table_id": int.tryParse(tableId) ?? tableId,
      });

      final result = data['result'];
      if (result is! Map<String, dynamic>) return null;
      return SavedCustomerTime.fromJson(result);
    } on BillingRepositoryException {
      return null;
    }
  }

  /// "Kartu stok" waktu tersimpan 1 member (mutasi IN/OUT), terbaru dulu.
  /// Proxy ke gameon lewat Billing/customer_time_history.
  Future<List<CustomerTimeHistoryEntry>> getCustomerTimeHistory({
    required int customerId,
    int page = 1,
    int perPage = 30,
  }) async {
    final data = await _post(ApiEndpoints.customerTimeHistory, {
      "customer_id": customerId,
      "page": page,
      "per_page": perPage,
    });

    final result = data['result'];
    final rows = result is Map<String, dynamic> ? result['data'] : null;
    if (rows is! List) return const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(CustomerTimeHistoryEntry.fromJson)
        .toList();
  }

  Future<PriceCalculation> calculatePrice({
    required String tableId,
    bool? saveTime,
  }) async {
    final data = await _post(ApiEndpoints.calculationPrice, {
      "table_id": tableId,
      if (saveTime != null) "save_time": saveTime ? "Y" : "N",
    });

    final result = data['result'];
    if (result is! Map<String, dynamic>) {
      throw const BillingRepositoryException(
        "Format hasil kalkulasi harga tidak valid.",
      );
    }

    return PriceCalculation.fromJson(result);
  }

  /// Checks whether the "simpan sisa waktu" (save remaining time) choice
  /// should be offered on the payment summary for timer-mode tables.
  Future<bool> checkTimeSave() async {
    final data = await _post(ApiEndpoints.checkTimeSave, const {});

    final result = data['result'];
    final flag = result is Map<String, dynamic>
        ? result['check_time_save']
        : data['check_time_save'];

    return flag?.toString().toUpperCase() == "Y";
  }

  Future<void> addDuration({
    required String tableId,
    required Duration additionalDuration,
  }) async {
    await _post(ApiEndpoints.addDuration, {
      "table_id": int.tryParse(tableId) ?? tableId,
      "additional_duration": formatDuration(additionalDuration),
    });
  }

  /// Converts a Reguler (open-ended, count-up) session into a Timer
  /// counting down to [targetDuration] total from its start time — e.g.
  /// already running 01:35:00, rounded up to a 02:00:00 target leaves
  /// 00:25:00 remaining. The backend rejects a target that isn't strictly
  /// greater than the elapsed time.
  Future<void> roundUpDuration({
    required String tableId,
    required Duration targetDuration,
  }) async {
    await _post(ApiEndpoints.roundUpDuration, {
      "table_id": int.tryParse(tableId) ?? tableId,
      "target_duration": formatDuration(targetDuration),
    });
  }

  Future<void> cancelTable({
    required String tableId,
    required String createdBy,
    required int paidBy,
  }) async {
    await _post(ApiEndpoints.cancelTable, {
      "table_id": int.tryParse(tableId) ?? tableId,
      "created_by": createdBy,
      "paid_by": paidBy,
    });
  }

  /// Re-signals every table's physical relay/lamp to match its current
  /// `table_active` state in the database — used after the relay
  /// reader/power restarts and the physical lamps fall out of sync with the
  /// system. The backend processes tables sequentially (table 1 onward)
  /// with a pause between each, so this can take several seconds and only
  /// resolves once every table has been signaled.
  Future<String> resetLampu() async {
    final data = await _post(ApiEndpoints.resetLampu, const {});
    return data['result']?.toString() ?? "Reset lampu selesai";
  }

  /// Signals the table's relay/lamp off when its Timer-mode countdown hits
  /// zero — the session itself is left untouched (still "unpaid", waiting
  /// for staff to process payment/cancel as usual), this only turns the
  /// physical light off. Best-effort: callers should not surface failures
  /// to the user, since a missed signal is recoverable via "Reset Lampu".
  Future<void> notifyTimerExpired({required String tableId}) async {
    await _post(ApiEndpoints.timerExpired, {
      "table_id": int.tryParse(tableId) ?? tableId,
    });
  }

  Future<void> moveTable({
    required String fromTableId,
    required String toTableId,
  }) async {
    await _post(ApiEndpoints.moveTable, {
      "from_table_id": int.tryParse(fromTableId) ?? fromTableId,
      "to_table_id": int.tryParse(toTableId) ?? toTableId,
    });
  }

  Future<void> submitPayment({
    required String tableId,
    required SessionType? mode,
    required DateTime startTime,
    required DateTime endTime,
    required Duration duration,
    required int subTotal,
    required int tax,
    required int totalBill,
    required String createdBy,
    required int paidBy,
    required int paymentId,
    int? customerId,
    int? promoId,
    bool? saveTime,
    Duration? remainingTime,
    bool? usedSavedTime,
    String? memberApprovalRef,
  }) async {
    final data = await _post(ApiEndpoints.payment, {
      if (mode != null)
        "transaction_mode": mode == SessionType.timer ? "Timer" : "Reguler",
      if (customerId != null) "transaction_customer_id": "$customerId",
      "transaction_payment_id": "$paymentId",
      if (promoId != null) "transaction_promo_id": "$promoId",
      "transaction_start_time": formatApiDateTime(startTime),
      "transaction_end_time": formatApiDateTime(endTime),
      "transaction_duration": formatDuration(duration),
      if (remainingTime != null)
        "transaction_remaining_time": formatDuration(remainingTime),
      "transaction_sub_total": "$subTotal",
      "transaction_tax": "$tax",
      "transaction_total_bill": "$totalBill",
      "transaction_table": tableId,
      "created_by": createdBy,
      "paid_by": "$paidBy",
      if (saveTime != null) "save_time": saveTime ? "Y" : "N",
      if (usedSavedTime != null)
        "used_save_time": usedSavedTime ? "Y" : "N",
      if (memberApprovalRef != null)
        "member_approval_ref": memberApprovalRef,
    });

    // Potong Saldo + member: backend menahan pembayaran sampai member konfirmasi PIN
    if (data['result'] == 'NEED_MEMBER_APPROVAL') {
      final approval = data['approval'];
      throw MemberApprovalRequiredException.fromApproval(
        memberApprovalRef ?? "",
        approval is Map<String, dynamic> ? approval : null,
      );
    }
  }

  Future<Map<String, dynamic>> _post(
    String url,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.post(url, data: payload);

      var data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          throw const BillingRepositoryException("Format respons tidak valid.");
        }
      }
      if (data is! Map<String, dynamic>) {
        throw const BillingRepositoryException("Format respons tidak valid.");
      }

      final code = data['code'];
      if (code != null && code.toString() != "200") {
        throw BillingRepositoryException(
          data['message']?.toString() ??
              data['result']?.toString() ??
              "Permintaan gagal.",
        );
      }

      return data;
    } on BillingRepositoryException {
      rethrow;
    } on DioException catch (e) {
      final responseData = e.response?.data;
      if (responseData is Map && responseData['message'] != null) {
        throw BillingRepositoryException(responseData['message'].toString());
      }
      throw const BillingRepositoryException(
        "Tidak dapat terhubung ke server. Periksa koneksi Anda.",
      );
    }
  }
}
