import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../models/pagination_info.dart';
import '../../../models/point_exchange.dart';

class PointExchangeRepositoryException implements Exception {
  final String message;

  const PointExchangeRepositoryException(this.message);

  @override
  String toString() => message;
}

class PointRedemptionResult {
  final List<PointRedemption> items;
  final PaginationInfo pagination;

  const PointRedemptionResult({
    required this.items,
    required this.pagination,
  });
}

/// Reads member point-redemption history (gameon `reward_redemption`) via
/// Setting/point_exchange_history. Read-only: the reward catalogue is no
/// longer managed from the billing app.
class PointExchangeRepository {
  final Dio _dio = Dio();

  Future<PointRedemptionResult> getRedemptionHistory({
    required int page,
    required int perPage,
    String? search,
  }) async {
    final data = await _post(ApiEndpoints.pointExchangeHistory, {
      "page": page,
      "per_page": perPage,
      if (search != null && search.trim().isNotEmpty) "search": search.trim(),
    });

    final result = data['result'];
    final map = result is Map<String, dynamic> ? result : data;

    final list = map['data'];
    if (list is! List) {
      throw const PointExchangeRepositoryException(
        "Format respons riwayat tukar point tidak valid.",
      );
    }

    final items = list
        .whereType<Map<String, dynamic>>()
        .map(PointRedemption.fromJson)
        .toList();

    final paginationJson = map['pagination'];
    final pagination = paginationJson is Map<String, dynamic>
        ? PaginationInfo.fromJson(paginationJson)
        : PaginationInfo.empty;

    return PointRedemptionResult(items: items, pagination: pagination);
  }

  /// Marks a coupon as used at the counter (gameon: status Redeemed -> Claimed).
  /// Returns the server's success message.
  Future<String> claimRedemption({
    required int id,
    required String createdBy,
  }) async {
    final data = await _post(ApiEndpoints.pointExchangeClaim, {
      "id": id,
      "created_by": createdBy,
    });
    return data['result']?.toString() ?? "Kupon berhasil ditandai terpakai";
  }

  /// Reverses a claim (gameon: status Claimed -> Redeemed).
  Future<String> unclaimRedemption({required int id}) async {
    final data = await _post(ApiEndpoints.pointExchangeUnclaim, {"id": id});
    return data['result']?.toString() ?? "Klaim kupon berhasil dibatalkan";
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
          throw const PointExchangeRepositoryException(
            "Format respons tidak valid.",
          );
        }
      }
      if (data is! Map<String, dynamic>) {
        throw const PointExchangeRepositoryException(
          "Format respons tidak valid.",
        );
      }

      final code = data['code'];
      if (code != null && code.toString() != "200") {
        throw PointExchangeRepositoryException(
          data['message']?.toString() ??
              data['result']?.toString() ??
              "Permintaan gagal.",
        );
      }

      return data;
    } on PointExchangeRepositoryException {
      rethrow;
    } on DioException catch (e) {
      final responseData = e.response?.data;
      if (responseData is Map && responseData['message'] != null) {
        throw PointExchangeRepositoryException(
          responseData['message'].toString(),
        );
      }
      throw const PointExchangeRepositoryException(
        "Tidak dapat terhubung ke server. Periksa koneksi Anda.",
      );
    }
  }
}
