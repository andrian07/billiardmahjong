import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/cashier_summary.dart';

class CashierRepositoryException implements Exception {
  final String message;

  const CashierRepositoryException(this.message);

  @override
  String toString() => message;
}

/// Reads a cashier's today-so-far transaction summary via
/// Report/get_transaction_today_by_cashier, used by the "Tutup Kas" flow.
class CashierRepository {
  final Dio _dio = Dio();

  /// [date] null = hari ini; diisi = tutup kas untuk hari bisnis tanggal itu.
  Future<CashierClosingSummary> getTodaySummary({
    required int userId,
    DateTime? date,
  }) async {
    final data = await _post(ApiEndpoints.transactionTodayByCashier, {
      "user_id": userId,
      if (date != null) "date": formatApiDate(date),
    });

    final result = data['result'];
    if (result is! Map<String, dynamic>) {
      throw const CashierRepositoryException(
        "Format respons ringkasan kasir tidak valid.",
      );
    }

    return CashierClosingSummary.fromJson(result);
  }

  /// Records one cash expense for [userId]'s shift. [channel] picks which
  /// drawer it's deducted from at Tutup Kas (billing vs cafe).
  Future<void> addExpense({
    required int userId,
    required String keterangan,
    required int nominal,
    required ExpenseChannel channel,
  }) {
    return _post(ApiEndpoints.addCashExpense, {
      "user_id": userId,
      "keterangan": keterangan,
      "nominal": nominal,
      "channel": expenseChannelToString(channel),
    });
  }

  /// Today's cash expenses logged by [userId] (drives the list in the
  /// expense dialog; Tutup Kas gets the same data folded into its summary).
  Future<List<CashExpense>> getExpensesToday({required int userId}) async {
    final data = await _post(ApiEndpoints.cashExpensesToday, {
      "user_id": userId,
    });

    final result = data['result'];
    final list = result is Map<String, dynamic> ? result['data'] : null;
    if (list is! List) return const [];

    return list
        .whereType<Map<String, dynamic>>()
        .map(CashExpense.fromJson)
        .toList();
  }

  Future<void> deleteExpense({required int expenseId, required int userId}) {
    return _post(ApiEndpoints.deleteCashExpense, {
      "cash_expense_id": expenseId,
      "user_id": userId,
    });
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
          throw const CashierRepositoryException("Format respons tidak valid.");
        }
      }
      if (data is! Map<String, dynamic>) {
        throw const CashierRepositoryException("Format respons tidak valid.");
      }

      final code = data['code'];
      if (code != null && code.toString() != "200") {
        throw CashierRepositoryException(
          data['message']?.toString() ??
              data['result']?.toString() ??
              "Permintaan gagal.",
        );
      }

      return data;
    } on CashierRepositoryException {
      rethrow;
    } on DioException catch (e) {
      final responseData = e.response?.data;
      if (responseData is Map && responseData['message'] != null) {
        throw CashierRepositoryException(responseData['message'].toString());
      }
      throw const CashierRepositoryException(
        "Tidak dapat terhubung ke server. Periksa koneksi Anda.",
      );
    }
  }
}
