import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../models/pagination_info.dart';
import '../../../models/promo.dart';

class PromoRepositoryException implements Exception {
  final String message;

  const PromoRepositoryException(this.message);

  @override
  String toString() => message;
}

class PromoListResult {
  final List<Promo> promos;
  final PaginationInfo pagination;

  const PromoListResult({required this.promos, required this.pagination});
}

/// Reads and manages promo entries via the Master/*_promo endpoints.
class PromoRepository {
  final Dio _dio = Dio();

  Future<PromoListResult> getPromos({
    required int page,
    required int perPage,
  }) async {
    final data = await _post(ApiEndpoints.promoList, {
      "page": "$page",
      "per_page": "$perPage",
    });

    final list = data['data'];
    if (list is! List) {
      throw const PromoRepositoryException(
        "Format respons daftar promo tidak valid.",
      );
    }

    final promos = list.whereType<Map<String, dynamic>>().map(Promo.fromJson).toList();

    final paginationJson = data['pagination'];
    final pagination = paginationJson is Map<String, dynamic>
        ? PaginationInfo.fromJson(paginationJson)
        : PaginationInfo.empty;

    return PromoListResult(promos: promos, pagination: pagination);
  }

  /// Reads the full, unpaginated promo list — used where every promo needs
  /// to be available at once (e.g. the payment dialog's promo dropdown).
  Future<List<Promo>> getAllPromos() async {
    final data = await _get(ApiEndpoints.promoListNoPaging);

    if (data is! List) {
      throw const PromoRepositoryException(
        "Format respons daftar promo tidak valid.",
      );
    }

    return data.whereType<Map<String, dynamic>>().map(Promo.fromJson).toList();
  }

  Future<void> addPromo({
    required String name,
    required PromoType type,
    String tableType = 'billiard',
    required int value,
    int? hourGained,
    int? freeHour,
    List<int> categoryIds = const [],
    List<int>? validDays,
    int? validTimeStart,
    int? validTimeEnd,
  }) {
    return _post(ApiEndpoints.addPromo, {
      "ms_promo_name": name,
      "ms_promo_tipe": type.apiValue,
      "ms_promo_table_type": tableType,
      "ms_promo_value": "$value",
      if (hourGained != null) "hour": "$hourGained",
      if (freeHour != null) "free_hour": "$freeHour",
      "category_ids": categoryIds,
      if (validDays != null && validDays.isNotEmpty)
        "valid_days": validDays.join(","),
      if (validTimeStart != null) "valid_time_start": "$validTimeStart",
      if (validTimeEnd != null) "valid_time_end": "$validTimeEnd",
    });
  }

  Future<void> editPromo({
    required int id,
    required String name,
    required PromoType type,
    String tableType = 'billiard',
    required int value,
    int? hourGained,
    int? freeHour,
    List<int> categoryIds = const [],
    List<int>? validDays,
    int? validTimeStart,
    int? validTimeEnd,
  }) {
    return _post(ApiEndpoints.editPromo, {
      "ms_promo_id": "$id",
      "ms_promo_name": name,
      "ms_promo_tipe": type.apiValue,
      "ms_promo_table_type": tableType,
      "ms_promo_value": "$value",
      "hour": hourGained != null ? "$hourGained" : "",
      "free_hour": freeHour != null ? "$freeHour" : "",
      "category_ids": categoryIds,
      "valid_days": (validDays != null && validDays.isNotEmpty)
          ? validDays.join(",")
          : "",
      "valid_time_start": validTimeStart != null ? "$validTimeStart" : "",
      "valid_time_end": validTimeEnd != null ? "$validTimeEnd" : "",
    });
  }

  Future<void> deletePromo(int id) {
    return _post(ApiEndpoints.deletePromo, {"ms_promo_id": "$id"});
  }

  Future<dynamic> _get(String url) async {
    try {
      final response = await _dio.get(url);

      var data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          throw const PromoRepositoryException("Format respons tidak valid.");
        }
      }

      return data;
    } on PromoRepositoryException {
      rethrow;
    } on DioException catch (e) {
      final responseData = e.response?.data;
      if (responseData is Map && responseData['message'] != null) {
        throw PromoRepositoryException(responseData['message'].toString());
      }
      throw const PromoRepositoryException(
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
          throw const PromoRepositoryException("Format respons tidak valid.");
        }
      }
      if (data is! Map<String, dynamic>) {
        throw const PromoRepositoryException("Format respons tidak valid.");
      }

      final code = data['code'];
      if (code != null && code.toString() != "200") {
        throw PromoRepositoryException(
          data['message']?.toString() ??
              data['result']?.toString() ??
              "Permintaan gagal.",
        );
      }

      return data;
    } on PromoRepositoryException {
      rethrow;
    } on DioException catch (e) {
      final responseData = e.response?.data;
      if (responseData is Map && responseData['message'] != null) {
        throw PromoRepositoryException(responseData['message'].toString());
      }
      throw const PromoRepositoryException(
        "Tidak dapat terhubung ke server. Periksa koneksi Anda.",
      );
    }
  }
}
