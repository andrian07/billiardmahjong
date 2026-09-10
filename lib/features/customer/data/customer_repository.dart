import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../models/customer.dart';
import '../../../models/customer_point_history_entry.dart';
import '../../../models/customer_saldo_history_entry.dart';
import '../../../models/customer_time_balance.dart';
import '../../../models/pagination_info.dart';

class CustomerRepositoryException implements Exception {
  final String message;

  const CustomerRepositoryException(this.message);

  @override
  String toString() => message;
}

class CustomerListResult {
  final List<Customer> customers;
  final PaginationInfo pagination;

  const CustomerListResult({required this.customers, required this.pagination});
}

/// Reads and manages customer accounts via the Master/*_customer endpoints.
class CustomerRepository {
  final Dio _dio = Dio();

  Future<CustomerListResult> getCustomers({
    required int page,
    required int perPage,
  }) async {
    final data = await _post(ApiEndpoints.customerList, {
      "page": "$page",
      "per_page": "$perPage",
    });

    final list = data['data'];
    if (list is! List) {
      throw const CustomerRepositoryException(
        "Format respons daftar member tidak valid.",
      );
    }

    final customers = list
        .whereType<Map<String, dynamic>>()
        .map(Customer.fromJson)
        .toList();

    final paginationJson = data['pagination'];
    final pagination = paginationJson is Map<String, dynamic>
        ? PaginationInfo.fromJson(paginationJson)
        : PaginationInfo.empty;

    return CustomerListResult(customers: customers, pagination: pagination);
  }

  /// Reads the full, unpaginated customer list — used where every member
  /// needs to be available at once (e.g. the payment dialog's member
  /// autocomplete).
  Future<List<Customer>> getAllCustomers() async {
    final data = await _get(ApiEndpoints.customerListNoPaging);

    final list = data is Map<String, dynamic> ? data['result'] ?? data['data'] : data;
    if (list is! List) {
      throw const CustomerRepositoryException(
        "Format respons daftar member tidak valid.",
      );
    }

    return list.whereType<Map<String, dynamic>>().map(Customer.fromJson).toList();
  }

  /// Reads a member's banked play time across all table categories via
  /// Master/get_time_per_customer — shown from the "Lihat Waktu Tersimpan"
  /// action on the member page.
  Future<List<CustomerTimeBalance>> getTimeBalances(int customerId) async {
    final data = await _post(ApiEndpoints.getTimePerCustomer, {
      "customer_id": customerId,
    });

    final result = data['result'];
    if (result is! List) {
      throw const CustomerRepositoryException(
        "Format respons waktu tersimpan tidak valid.",
      );
    }

    return result
        .whereType<Map<String, dynamic>>()
        .map(CustomerTimeBalance.fromJson)
        .toList();
  }

  /// Reads a member's saldo deductions (gameon `history_saldo`, OUT only),
  /// newest first — shown in the "Potongan Saldo" tab of the Detail Member
  /// dialog. Proxy via Billing/customer_saldo_history.
  Future<List<CustomerSaldoHistoryEntry>> getSaldoDeductions(
    int customerId, {
    int page = 1,
    int perPage = 50,
  }) async {
    final data = await _post(ApiEndpoints.customerSaldoHistory, {
      "customer_id": customerId,
      "page": page,
      "per_page": perPage,
    });

    final result = data['result'];
    final rows = result is Map<String, dynamic> ? result['data'] : null;
    if (rows is! List) return const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(CustomerSaldoHistoryEntry.fromJson)
        .toList();
  }

  /// Reads a member's point deductions (gameon `customer_point_history`, OUT
  /// only), newest first — shown in the "Potongan Point" tab of the Detail
  /// Member dialog. Proxy via Billing/customer_point_history.
  Future<List<CustomerPointHistoryEntry>> getPointDeductions(
    int customerId, {
    int page = 1,
    int perPage = 50,
  }) async {
    final data = await _post(ApiEndpoints.customerPointHistory, {
      "customer_id": customerId,
      "page": page,
      "per_page": perPage,
    });

    final result = data['result'];
    final rows = result is Map<String, dynamic> ? result['data'] : null;
    if (rows is! List) return const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(CustomerPointHistoryEntry.fromJson)
        .toList();
  }

  /// Tops up a member's saldo via Master/add_customer_saldo, recorded as a
  /// saldo transaction — used by the "Tambah Saldo" action on the member
  /// page. saldoId references the Setting/saldo_list_no_pagging package the
  /// cashier picked; the backend derives the credited nominal (and the
  /// price/discount) from that package server-side, so they aren't sent
  /// here. Returns the new transaksi_saldo_id.
  Future<int> addSaldo({
    required int customerId,
    required int saldoId,
    required int paymentId,
    required String createdBy,
    required int paidBy,
  }) async {
    final data = await _post(ApiEndpoints.addCustomerSaldo, {
      "customer_id": customerId,
      "ms_saldo_id": saldoId,
      "payment_id": paymentId,
      "created_by": createdBy,
      "paid_by": paidBy,
    });

    final rawId = data['transaksi_saldo_id'];
    return rawId is int ? rawId : int.tryParse(rawId?.toString() ?? "") ?? 0;
  }

  /// Pulls new customers from the gameon central server into billing_api's
  /// local database via Master/sync_customer — used by the "Sync Customer"
  /// action on the member page. Returns how many new customers were synced.
  Future<int> syncCustomers() async {
    final data = await _post(ApiEndpoints.syncCustomer, {});

    final rawCount = data['synced_count'];
    return rawCount is int ? rawCount : int.tryParse(rawCount?.toString() ?? "") ?? 0;
  }

  Future<void> deleteCustomer(int customerId) {
    return _post(ApiEndpoints.deleteCustomer, {
      "customer_id": "$customerId",
    });
  }

  Future<void> resetPassword(int customerId) {
    return _post(ApiEndpoints.resetPasswordCustomer, {
      "customer_id": "$customerId",
    });
  }

  Future<dynamic> _get(String url) async {
    try {
      final response = await _dio.get(url);

      var data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          throw const CustomerRepositoryException("Format respons tidak valid.");
        }
      }

      return data;
    } on CustomerRepositoryException {
      rethrow;
    } on DioException catch (e) {
      final responseData = e.response?.data;
      if (responseData is Map && responseData['message'] != null) {
        throw CustomerRepositoryException(responseData['message'].toString());
      }
      throw const CustomerRepositoryException(
        "Tidak dapat terhubung ke server. Periksa koneksi Anda.",
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
          throw const CustomerRepositoryException(
            "Format respons tidak valid.",
          );
        }
      }
      if (data is! Map<String, dynamic>) {
        throw const CustomerRepositoryException(
          "Format respons tidak valid.",
        );
      }

      final code = data['code'];
      if (code != null && code.toString() != "200") {
        throw CustomerRepositoryException(
          data['message']?.toString() ??
              data['result']?.toString() ??
              "Permintaan gagal.",
        );
      }

      return data;
    } on CustomerRepositoryException {
      rethrow;
    } on DioException catch (e) {
      final responseData = e.response?.data;
      if (responseData is Map && responseData['message'] != null) {
        throw CustomerRepositoryException(responseData['message'].toString());
      }
      throw const CustomerRepositoryException(
        "Tidak dapat terhubung ke server. Periksa koneksi Anda.",
      );
    }
  }
}
