import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../models/product.dart';
import '../../../models/product_category.dart';
import '../../../models/unit.dart';
import '../../category/data/category_repository.dart';
import '../../unit/data/unit_repository.dart';

class ProductRepositoryException implements Exception {
  final String message;

  const ProductRepositoryException(this.message);

  @override
  String toString() => message;
}

/// An image picked in the UI, ready to be attached to a multipart request.
/// Carried as raw bytes (rather than a file path) so it works the same way
/// whether the app is running on web or a native platform.
class ProductImageInput {
  final String filename;
  final List<int> bytes;

  const ProductImageInput({required this.filename, required this.bytes});
}

/// Reads and manages products via the Master/*_product endpoints.
///
/// add_product/edit_product take multipart/form-data (they accept an image
/// upload), while product_list/delete_product take plain JSON.
class ProductRepository {
  final Dio _dio = Dio();
  final _categoryRepository = CategoryRepository();
  final _unitRepository = UnitRepository();

  Future<List<Product>> getProducts() async {
    final data = await _post(ApiEndpoints.productList, {
      "page": 1,
      "per_page": 1000,
    });

    final list = data['data'];
    if (list is! List) {
      throw const ProductRepositoryException(
        "Format respons daftar produk tidak valid.",
      );
    }

    return list
        .whereType<Map<String, dynamic>>()
        .map(Product.fromJson)
        .toList();
  }

  Future<List<ProductCategory>> getCategoryOptions() =>
      _categoryRepository.getCategories();

  Future<List<Unit>> getUnitOptions() => _unitRepository.getUnits();

  Future<void> addProduct({
    required String name,
    required int categoryId,
    required int unitId,
    required int price,
    required int cogs,
    required int stock,
    required bool reduceStock,
    ProductImageInput? image,
  }) async {
    final formData = FormData.fromMap({
      "category_id": "$categoryId",
      "unit_id": "$unitId",
      "product_name": name.trim(),
      "product_price": "$price",
      "product_cogs": "$cogs",
      "product_stock": "$stock",
      "reduce_stock": reduceStock ? "Y" : "N",
      if (image != null)
        "product_image": MultipartFile.fromBytes(
          image.bytes,
          filename: image.filename,
        ),
    });

    await _postForm(ApiEndpoints.addProduct, formData);
  }

  Future<void> editProduct({
    required int id,
    required String name,
    required int categoryId,
    required int unitId,
    required int price,
    required int cogs,
    required bool reduceStock,
    ProductImageInput? image,
  }) async {
    // product_stock is deliberately omitted — it's read-only in the edit
    // dialog (changes only via Purchase/Cafe transactions), and the value
    // held there is a snapshot from when the dialog opened. Sending it back
    // here would silently overwrite any stock change made elsewhere while
    // the dialog was open with that stale number.
    final formData = FormData.fromMap({
      "product_id": "$id",
      "category_id": "$categoryId",
      "unit_id": "$unitId",
      "product_name": name.trim(),
      "product_price": "$price",
      "product_cogs": "$cogs",
      "reduce_stock": reduceStock ? "Y" : "N",
      if (image != null)
        "product_image": MultipartFile.fromBytes(
          image.bytes,
          filename: image.filename,
        ),
    });

    await _postForm(ApiEndpoints.editProduct, formData);
  }

  Future<void> deleteProduct(int id) {
    return _post(ApiEndpoints.deleteProduct, {"product_id": id});
  }

  /// Pushes a full snapshot of this branch's product catalog (stock +
  /// HPP/COGS) to gameon — see [ProductStockSyncWatcher], which calls this
  /// every 30 minutes so gameon's copy never drifts far from the branch's
  /// real stock/COGS.
  Future<void> syncStockToGameon({required int branch}) {
    return _post(ApiEndpoints.syncProductStock, {"branch": branch});
  }

  Future<Map<String, dynamic>> _postForm(String url, FormData formData) async {
    try {
      final response = await _dio.post(url, data: formData);
      return _parseResponse(response.data);
    } on ProductRepositoryException {
      rethrow;
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  Future<Map<String, dynamic>> _post(
    String url,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.post(url, data: payload);
      return _parseResponse(response.data);
    } on ProductRepositoryException {
      rethrow;
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  Map<String, dynamic> _parseResponse(dynamic data) {
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        throw const ProductRepositoryException("Format respons tidak valid.");
      }
    }
    if (data is! Map<String, dynamic>) {
      throw const ProductRepositoryException("Format respons tidak valid.");
    }

    final code = data['code'];
    if (code != null && code.toString() != "200") {
      throw ProductRepositoryException(
        data['message']?.toString() ??
            data['result']?.toString() ??
            "Permintaan gagal.",
      );
    }

    return data;
  }

  ProductRepositoryException _mapDioError(DioException e) {
    final responseData = e.response?.data;
    if (responseData is Map && responseData['message'] != null) {
      return ProductRepositoryException(responseData['message'].toString());
    }
    return const ProductRepositoryException(
      "Tidak dapat terhubung ke server. Periksa koneksi Anda.",
    );
  }
}
