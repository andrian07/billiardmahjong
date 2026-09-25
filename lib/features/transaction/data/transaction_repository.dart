import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../models/cafe_transaction.dart';
import '../../../models/pagination_info.dart';
import '../../../models/saldo_transaction.dart';
import '../../../models/transaction.dart';
import '../../customer/data/customer_repository.dart';
import '../../payment/data/payment_method_repository.dart';
import '../../promo/data/promo_repository.dart';

class TransactionRepositoryException implements Exception {
  final String message;

  const TransactionRepositoryException(this.message);

  @override
  String toString() => message;
}

class CafeTransactionListResult {
  final List<CafeTransaction> transactions;
  final PaginationInfo pagination;

  const CafeTransactionListResult({
    required this.transactions,
    required this.pagination,
  });
}

class SaldoTransactionListResult {
  final List<SaldoTransaction> transactions;
  final PaginationInfo pagination;

  const SaldoTransactionListResult({
    required this.transactions,
    required this.pagination,
  });
}

/// Reads completed/cancelled transaction history via Billing/transaction_list
/// and Billing/transaction_detail.
class TransactionRepository {
  final Dio _dio = Dio();
  final _customerRepository = CustomerRepository();
  final _promoRepository = PromoRepository();
  final _paymentMethodRepository = PaymentMethodRepository();

  Future<List<Transaction>> getCompletedTransactions() async {
    final data = await _post(
      ApiEndpoints.transactionList,
      {"page": 1, "per_page": 1000},
    );

    final result = data['result'];
    final rows = result is Map<String, dynamic> ? result['data'] : null;
    if (rows is! List) {
      throw const TransactionRepositoryException(
        "Format respons daftar transaksi tidak valid.",
      );
    }

    final transactions = rows.whereType<Map<String, dynamic>>().toList();

    bool hasId(String key) => transactions.any((json) {
      final id = int.tryParse(json[key]?.toString() ?? "");
      return id != null && id != 0;
    });

    final customerNames = hasId('customer_id')
        ? await _fetchCustomerNames()
        : const <int, String>{};
    final promoNames = hasId('promo_id')
        ? await _fetchPromoNames()
        : const <int, String>{};
    final paymentNames = await _fetchPaymentNames();

    return transactions.map((json) {
      final customerId = int.tryParse(json['customer_id']?.toString() ?? "");
      final promoId = int.tryParse(json['promo_id']?.toString() ?? "");
      final paymentId = int.tryParse(json['payment_id']?.toString() ?? "");
      return Transaction.fromJson(
        json,
        customerName: (customerId != null && customerId != 0)
            ? customerNames[customerId]
            : null,
        promoName: (promoId != null && promoId != 0)
            ? promoNames[promoId]
            : null,
        paymentMethodName: paymentNames[paymentId],
      );
    }).toList();
  }

  Future<TransactionDetail> getTransactionDetail(int transactionId) async {
    final data = await _post(ApiEndpoints.transactionDetail, {
      "transaction_id": transactionId,
    });

    final result = data['result'];
    if (result is! Map<String, dynamic>) {
      throw const TransactionRepositoryException(
        "Format detail transaksi tidak valid.",
      );
    }

    final paymentId = int.tryParse(result['payment_id']?.toString() ?? "");
    final paymentNames = await _fetchPaymentNames();

    return TransactionDetail.fromJson(
      result,
      paymentMethodName: paymentNames[paymentId],
    );
  }

  Future<CafeTransactionListResult> getCafeTransactions({
    int page = 1,
    int perPage = 20,
  }) async {
    final data = await _post(ApiEndpoints.transactionCafeList, {
      "page": page,
      "per_page": perPage,
    });

    final result = data['result'];
    final rows = result is Map<String, dynamic> ? result['data'] : null;
    if (rows is! List) {
      throw const TransactionRepositoryException(
        "Format respons transaksi cafe tidak valid.",
      );
    }

    final rowsJson = rows.whereType<Map<String, dynamic>>().toList();

    bool hasId(String key) => rowsJson.any((json) {
      final id = int.tryParse(json[key]?.toString() ?? "");
      return id != null && id != 0;
    });

    // Unlike billing transactions, the cafe endpoint returns customer_name
    // directly on each row (a free-text name captured at checkout, not
    // necessarily tied to a Customer master record) — no client-side join
    // needed here.
    final promoNames = hasId('promo_id')
        ? await _fetchPromoNames()
        : const <int, String>{};
    final paymentNames = await _fetchPaymentNames();

    final transactions = rowsJson.map((json) {
      final promoId = int.tryParse(json['promo_id']?.toString() ?? "");
      final paymentId = int.tryParse(json['payment_id']?.toString() ?? "");
      return CafeTransaction.fromJson(
        json,
        promoName: (promoId != null && promoId != 0)
            ? promoNames[promoId]
            : null,
        paymentName: paymentNames[paymentId],
      );
    }).toList();

    final paginationJson = result['pagination'];
    final pagination = paginationJson is Map<String, dynamic>
        ? PaginationInfo.fromJson(paginationJson)
        : PaginationInfo.empty;

    return CafeTransactionListResult(
      transactions: transactions,
      pagination: pagination,
    );
  }

  Future<CafeTransactionDetail> getCafeTransactionDetail(
    int transactionCafeId,
  ) async {
    final data = await _post(ApiEndpoints.transactionCafeDetail, {
      "transaction_cafe_id": transactionCafeId,
    });

    final result = data['result'];
    if (result is! Map<String, dynamic>) {
      throw const TransactionRepositoryException(
        "Format detail transaksi cafe tidak valid.",
      );
    }

    return CafeTransactionDetail.fromJson(result);
  }

  /// [createdBy] is who's performing the cancellation (not who made the
  /// original sale) — the backend records it against each restocked item
  /// in movement_stock as the audit trail for the stock return.
  Future<void> cancelCafeTransaction(
    int transactionCafeId, {
    required String createdBy,
  }) async {
    await _post(ApiEndpoints.cancelTransactionCafe, {
      "transaction_cafe_id": transactionCafeId,
      "created_by": createdBy,
    });
  }

  /// Rejected server-side (and kept out of reach client-side too — see
  /// TransactionPage's cancel button visibility) when the transaction was
  /// paid via "Potong Saldo" or "Gunakan Timer" (saved-time balance) - the
  /// customer's saldo/time was already deducted at gameon and there's no
  /// stored ref to refund it automatically. See
  /// Billing_model::cancel_transaction on the backend for the full reasoning.
  Future<void> cancelBillingTransaction({
    required int transactionId,
    required String createdBy,
  }) async {
    await _post(ApiEndpoints.cancelTransaction, {
      "transaction_id": transactionId,
      "created_by": createdBy,
    });
  }

  /// Rejected server-side (and kept out of reach client-side too) when the
  /// transaction's old or new payment method is "Potong Saldo" — no logic
  /// exists to correct the customer's saldo for a payment-method edit made
  /// after the sale, only for the original save.
  Future<void> editBillingPayment({
    required int transactionId,
    required int paymentId,
    required String createdBy,
  }) async {
    await _post(ApiEndpoints.editPaymentTransaction, {
      "transaction_id": transactionId,
      "payment_id": paymentId,
      "created_by": createdBy,
    });
  }

  Future<void> editCafePayment({
    required int transactionCafeId,
    required int paymentId,
    required String createdBy,
  }) async {
    await _post(ApiEndpoints.editPaymentTransactionCafe, {
      "transaction_cafe_id": transactionCafeId,
      "payment_id": paymentId,
      "created_by": createdBy,
    });
  }

  Future<SaldoTransactionListResult> getSaldoTransactions({
    int page = 1,
    int perPage = 20,
  }) async {
    final data = await _post(ApiEndpoints.transactionSaldoList, {
      "page": page,
      "per_page": perPage,
    });

    final result = data['result'];
    final rows = result is Map<String, dynamic> ? result['data'] : null;
    if (rows is! List) {
      throw const TransactionRepositoryException(
        "Format respons transaksi saldo tidak valid.",
      );
    }

    final transactions = rows
        .whereType<Map<String, dynamic>>()
        .map(SaldoTransaction.fromJson)
        .toList();

    final paginationJson = result['pagination'];
    final pagination = paginationJson is Map<String, dynamic>
        ? PaginationInfo.fromJson(paginationJson)
        : PaginationInfo.empty;

    return SaldoTransactionListResult(
      transactions: transactions,
      pagination: pagination,
    );
  }

  Future<Map<int, String>> _fetchCustomerNames() async {
    try {
      final result = await _customerRepository.getCustomers(
        page: 1,
        perPage: 1000,
      );
      return {for (final c in result.customers) c.id: c.name};
    } catch (_) {
      return const {};
    }
  }

  Future<Map<int, String>> _fetchPromoNames() async {
    try {
      final promos = await _promoRepository.getAllPromos();
      return {for (final p in promos) p.id: p.name};
    } catch (_) {
      return const {};
    }
  }

  Future<Map<int, String>> _fetchPaymentNames() async {
    try {
      final methods = await _paymentMethodRepository.getPaymentMethods();
      return {for (final m in methods) m.id: m.name};
    } catch (_) {
      return const {};
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
          throw const TransactionRepositoryException(
            "Format respons tidak valid.",
          );
        }
      }
      if (data is! Map<String, dynamic>) {
        throw const TransactionRepositoryException(
          "Format respons tidak valid.",
        );
      }

      final code = data['code'];
      if (code != null && code.toString() != "200") {
        throw TransactionRepositoryException(
          data['message']?.toString() ??
              data['result']?.toString() ??
              "Permintaan gagal.",
        );
      }

      return data;
    } on TransactionRepositoryException {
      rethrow;
    } on DioException catch (_) {
      throw const TransactionRepositoryException(
        "Tidak dapat terhubung ke server. Periksa koneksi Anda.",
      );
    }
  }
}
