import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../models/pagination_info.dart';
import '../../../models/sync_pending_item.dart';

class SyncRepositoryException implements Exception {
  final String message;

  const SyncRepositoryException(this.message);

  @override
  String toString() => message;
}

/// Reads which local rows (billing/cafe/saldo transactions, pembelian) have
/// never successfully been pushed to the online report (gameon) — driven by
/// Sync/pending, which reads each source table's `*_upload_status` — and
/// retries the push for one row via Sync/retry.
class SyncRepository {
  final Dio _dio = Dio();

  /// Cheap 4x COUNT(*) — no rows, no sorting — for [SyncWatcher]'s frequent
  /// background poll, so an (almost always empty) tick stays lightweight.
  Future<SyncPendingCounts> getPendingCount() async {
    final data = await _post(ApiEndpoints.syncPendingCount, const {});
    final result = data['result'];
    return result is Map<String, dynamic>
        ? SyncPendingCounts.fromJson(result)
        : SyncPendingCounts.empty;
  }

  Future<SyncPendingResult> getPending({
    required int page,
    required int perPage,
  }) async {
    final data = await _post(ApiEndpoints.syncPending, {
      "page": page,
      "per_page": perPage,
    });

    final result = data['result'];
    if (result is! Map<String, dynamic>) {
      throw const SyncRepositoryException(
        "Format respons daftar sinkron tidak valid.",
      );
    }

    final rows = result['data'];
    final items = rows is List
        ? rows.whereType<Map<String, dynamic>>().map(SyncPendingItem.fromJson).toList()
        : const <SyncPendingItem>[];

    final paginationJson = result['pagination'];
    final pagination = paginationJson is Map<String, dynamic>
        ? PaginationInfo.fromJson(paginationJson)
        : PaginationInfo.empty;

    final countsJson = result['counts'];
    final counts = countsJson is Map<String, dynamic>
        ? SyncPendingCounts.fromJson(countsJson)
        : SyncPendingCounts.empty;

    return SyncPendingResult(items: items, pagination: pagination, counts: counts);
  }

  /// Re-pushes one row to gameon, rebuilding the payload server-side from
  /// what's already stored locally — throws [SyncRepositoryException] with
  /// gameon's own error message when the retry itself fails (e.g. still
  /// unreachable), so callers can show it inline per-row.
  Future<void> retry({required SyncSourceType type, required int id}) {
    return _post(ApiEndpoints.syncRetry, {
      "type": type.apiValue,
      "id": id,
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
          throw const SyncRepositoryException("Format respons tidak valid.");
        }
      }
      if (data is! Map<String, dynamic>) {
        throw const SyncRepositoryException("Format respons tidak valid.");
      }

      final code = data['code'];
      if (code != null && code.toString() != "200") {
        throw SyncRepositoryException(
          data['message']?.toString() ??
              data['result']?.toString() ??
              "Permintaan gagal.",
        );
      }

      return data;
    } on SyncRepositoryException {
      rethrow;
    } on DioException catch (e) {
      final responseData = e.response?.data;
      if (responseData is Map && responseData['message'] != null) {
        throw SyncRepositoryException(responseData['message'].toString());
      }
      throw const SyncRepositoryException(
        "Tidak dapat terhubung ke server. Periksa koneksi Anda.",
      );
    }
  }
}
