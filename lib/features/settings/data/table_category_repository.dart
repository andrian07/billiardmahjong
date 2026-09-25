import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../models/pagination_info.dart';
import '../../../models/table_category.dart';

class TableCategoryRepositoryException implements Exception {
  final String message;

  const TableCategoryRepositoryException(this.message);

  @override
  String toString() => message;
}

class TableCategoryListResult {
  final List<TableCategory> items;
  final PaginationInfo pagination;

  const TableCategoryListResult({
    required this.items,
    required this.pagination,
  });
}

/// Reads and manages table categories via the Setting/*_category_meja
/// endpoints. delete_category_meja soft-deletes (sets
/// category_meja_active = 'N') rather than removing the row.
class TableCategoryRepository {
  final Dio _dio = Dio();

  Future<TableCategoryListResult> getTableCategories({
    required int page,
    required int perPage,
  }) async {
    final data = await _post(ApiEndpoints.categoryMejaList, {
      "page": page,
      "per_page": perPage,
    });

    final list = data['data'];
    if (list is! List) {
      throw const TableCategoryRepositoryException(
        "Format respons daftar kategori meja tidak valid.",
      );
    }

    final items = list
        .whereType<Map<String, dynamic>>()
        .map(TableCategory.fromJson)
        .toList();

    final paginationJson = data['pagination'];
    final pagination = paginationJson is Map<String, dynamic>
        ? PaginationInfo.fromJson(paginationJson)
        : PaginationInfo.empty;

    return TableCategoryListResult(items: items, pagination: pagination);
  }

  Future<int> addTableCategory({
    required String name,
    required int priceOption,
    required String type,
  }) async {
    final data = await _post(ApiEndpoints.addCategoryMeja, {
      "category_meja_name": name.trim(),
      "category_meja_price": priceOption,
      "category_meja_type": type,
    });

    final rawId = data['category_meja_id'];
    return rawId is int ? rawId : int.tryParse(rawId?.toString() ?? "") ?? 0;
  }

  /// Only the fields passed in are updated — at least one of
  /// [name]/[active]/[priceOption]/[type] must be given.
  Future<void> editTableCategory({
    required int id,
    String? name,
    bool? active,
    int? priceOption,
    String? type,
  }) {
    final payload = <String, dynamic>{"category_meja_id": id};
    if (name != null) payload["category_meja_name"] = name.trim();
    if (active != null) payload["category_meja_active"] = active ? "Y" : "N";
    if (priceOption != null) payload["category_meja_price"] = priceOption;
    if (type != null) payload["category_meja_type"] = type;

    return _post(ApiEndpoints.editCategoryMeja, payload);
  }

  Future<void> deleteTableCategory(int id) {
    return _post(ApiEndpoints.deleteCategoryMeja, {"category_meja_id": id});
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
          throw const TableCategoryRepositoryException(
            "Format respons tidak valid.",
          );
        }
      }
      if (data is! Map<String, dynamic>) {
        throw const TableCategoryRepositoryException(
          "Format respons tidak valid.",
        );
      }

      final code = data['code'];
      if (code != null && code.toString() != "200") {
        throw TableCategoryRepositoryException(
          data['message']?.toString() ??
              data['result']?.toString() ??
              "Permintaan gagal.",
        );
      }

      return data;
    } on TableCategoryRepositoryException {
      rethrow;
    } on DioException catch (e) {
      final responseData = e.response?.data;
      if (responseData is Map && responseData['message'] != null) {
        throw TableCategoryRepositoryException(
          responseData['message'].toString(),
        );
      }
      throw const TableCategoryRepositoryException(
        "Tidak dapat terhubung ke server. Periksa koneksi Anda.",
      );
    }
  }
}
