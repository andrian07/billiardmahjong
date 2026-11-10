import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/report.dart';

class ReportRepositoryException implements Exception {
  final String message;

  const ReportRepositoryException(this.message);

  @override
  String toString() => message;
}

/// A downloaded Excel/PDF report ready to be written to disk.
class ReportExportFile {
  final String filename;
  final Uint8List bytes;

  const ReportExportFile({required this.filename, required this.bytes});
}

/// Reads billing/cafe/stock reports via the Report/* endpoints — `view`
/// returns JSON, `excel`/`pdf` return a downloadable file instead.
class ReportRepository {
  final Dio _dio = Dio();

  Future<BillingReportResult> getBillingReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    int? customerId,
    int? paidBy,
    String? categoryType,
  }) async {
    final data = await _post(ApiEndpoints.billingReport, {
      "date_from": formatApiDate(dateFrom),
      "date_to": formatApiDate(dateTo),
      if (categoryType != null) "category_type": categoryType,
      if (customerId != null && customerId != 0) "customer_id": customerId,
      if (paidBy != null && paidBy != 0) "paid_by": paidBy,
      "type": "view",
    });

    final result = data['result'];
    if (result is! Map<String, dynamic>) {
      throw const ReportRepositoryException(
        "Format respons laporan billing tidak valid.",
      );
    }

    return BillingReportResult.fromJson(result);
  }

  Future<CafeReportResult> getCafeReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    int? customerId,
    int? paidBy,
  }) async {
    final data = await _post(ApiEndpoints.cafeReport, {
      "date_from": formatApiDate(dateFrom),
      "date_to": formatApiDate(dateTo),
      if (customerId != null && customerId != 0) "customer_id": customerId,
      if (paidBy != null && paidBy != 0) "paid_by": paidBy,
      "type": "view",
    });

    final result = data['result'];
    if (result is! Map<String, dynamic>) {
      throw const ReportRepositoryException(
        "Format respons laporan cafe tidak valid.",
      );
    }

    return CafeReportResult.fromJson(result);
  }

  Future<SaldoReportResult> getSaldoReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    int? customerId,
    int? paidBy,
  }) async {
    final data = await _post(ApiEndpoints.saldoReport, {
      "date_from": formatApiDate(dateFrom),
      "date_to": formatApiDate(dateTo),
      if (customerId != null && customerId != 0) "customer_id": customerId,
      if (paidBy != null && paidBy != 0) "paid_by": paidBy,
      "type": "view",
    });

    final result = data['result'];
    if (result is! Map<String, dynamic>) {
      throw const ReportRepositoryException(
        "Format respons laporan saldo tidak valid.",
      );
    }

    return SaldoReportResult.fromJson(result);
  }

  Future<List<StockReportRow>> getStockReport() async {
    final data = await _post(ApiEndpoints.stockReport, {"type": "view"});

    final result = data['result'];
    if (result is! List) {
      throw const ReportRepositoryException(
        "Format respons laporan stok tidak valid.",
      );
    }

    return result
        .whereType<Map<String, dynamic>>()
        .map(StockReportRow.fromJson)
        .toList();
  }

  Future<ReportExportFile> exportBillingReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    int? customerId,
    int? paidBy,
    String? categoryType,
    required String type,
  }) {
    return _download(
      ApiEndpoints.billingReport,
      {
        "date_from": formatApiDate(dateFrom),
        "date_to": formatApiDate(dateTo),
        if (categoryType != null) "category_type": categoryType,
        if (customerId != null && customerId != 0) "customer_id": customerId,
        if (paidBy != null && paidBy != 0) "paid_by": paidBy,
        "type": type,
      },
      defaultBasename: categoryType == "mahjong"
          ? "laporan_mahjong"
          : "laporan_billing",
      type: type,
    );
  }

  Future<ReportExportFile> exportCafeReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    int? customerId,
    int? paidBy,
    required String type,
  }) {
    return _download(
      ApiEndpoints.cafeReport,
      {
        "date_from": formatApiDate(dateFrom),
        "date_to": formatApiDate(dateTo),
        if (customerId != null && customerId != 0) "customer_id": customerId,
        if (paidBy != null && paidBy != 0) "paid_by": paidBy,
        "type": type,
      },
      defaultBasename: "laporan_cafe",
      type: type,
    );
  }

  Future<ReportExportFile> exportSaldoReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    int? customerId,
    int? paidBy,
    required String type,
  }) {
    return _download(
      ApiEndpoints.saldoReport,
      {
        "date_from": formatApiDate(dateFrom),
        "date_to": formatApiDate(dateTo),
        if (customerId != null && customerId != 0) "customer_id": customerId,
        if (paidBy != null && paidBy != 0) "paid_by": paidBy,
        "type": type,
      },
      defaultBasename: "laporan_saldo",
      type: type,
    );
  }

  Future<ReportExportFile> exportStockReport({required String type}) {
    return _download(
      ApiEndpoints.stockReport,
      {"type": type},
      defaultBasename: "laporan_stok",
      type: type,
    );
  }

  Future<PurchaseReportResult> getPurchaseReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    String? supplier,
  }) async {
    final data = await _post(ApiEndpoints.purchaseReport, {
      "date_from": formatApiDate(dateFrom),
      "date_to": formatApiDate(dateTo),
      if (supplier != null && supplier.isNotEmpty) "supplier": supplier,
      "type": "view",
    });

    final result = data['result'];
    if (result is! Map<String, dynamic>) {
      throw const ReportRepositoryException(
        "Format respons laporan pembelian tidak valid.",
      );
    }

    return PurchaseReportResult.fromJson(result);
  }

  Future<ReportExportFile> exportPurchaseReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    String? supplier,
    required String type,
  }) {
    return _download(
      ApiEndpoints.purchaseReport,
      {
        "date_from": formatApiDate(dateFrom),
        "date_to": formatApiDate(dateTo),
        if (supplier != null && supplier.isNotEmpty) "supplier": supplier,
        "type": type,
      },
      defaultBasename: "laporan_pembelian",
      type: type,
    );
  }

  /// Distinct supplier names ever used on a purchase — for the report's
  /// supplier filter dropdown.
  Future<List<String>> getPurchaseSuppliers() async {
    final data = await _post(ApiEndpoints.purchaseSuppliers, const {});

    final result = data['result'];
    if (result is! List) {
      throw const ReportRepositoryException(
        "Format respons daftar supplier tidak valid.",
      );
    }

    return result.map((e) => e.toString()).toList();
  }

  Future<ReportExportFile> _download(
    String url,
    Map<String, dynamic> payload, {
    required String defaultBasename,
    required String type,
  }) async {
    try {
      final response = await _dio.post(
        url,
        data: payload,
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = Uint8List.fromList(response.data as List<int>);
      final contentType = response.headers.value('content-type') ?? "";

      if (contentType.contains('json')) {
        Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(bytes));
        } catch (_) {
          throw const ReportRepositoryException("Format respons tidak valid.");
        }
        final message = decoded is Map
            ? (decoded['message']?.toString() ??
                  decoded['result']?.toString() ??
                  "Permintaan gagal.")
            : "Permintaan gagal.";
        throw ReportRepositoryException(message);
      }

      final extension = type == "pdf" ? "pdf" : "xlsx";
      final filename =
          _filenameFromContentDisposition(
            response.headers.value('content-disposition'),
          ) ??
          "$defaultBasename.$extension";

      return ReportExportFile(filename: filename, bytes: bytes);
    } on ReportRepositoryException {
      rethrow;
    } on DioException catch (_) {
      throw const ReportRepositoryException(
        "Tidak dapat terhubung ke server. Periksa koneksi Anda.",
      );
    }
  }

  String? _filenameFromContentDisposition(String? header) {
    if (header == null) return null;
    final match = RegExp(
      r'''filename\*?=(?:UTF-8'')?"?([^";]+)"?''',
    ).firstMatch(header);
    return match?.group(1)?.trim();
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
          throw const ReportRepositoryException("Format respons tidak valid.");
        }
      }
      if (data is! Map<String, dynamic>) {
        throw const ReportRepositoryException("Format respons tidak valid.");
      }

      final code = data['code'];
      if (code != null && code.toString() != "200") {
        throw ReportRepositoryException(
          data['message']?.toString() ??
              data['result']?.toString() ??
              "Permintaan gagal.",
        );
      }

      return data;
    } on ReportRepositoryException {
      rethrow;
    } on DioException catch (e) {
      final responseData = e.response?.data;
      if (responseData is Map && responseData['message'] != null) {
        throw ReportRepositoryException(responseData['message'].toString());
      }
      throw const ReportRepositoryException(
        "Tidak dapat terhubung ke server. Periksa koneksi Anda.",
      );
    }
  }
}
