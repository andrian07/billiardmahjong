import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';

/// Thrown by payment calls when a Potong Saldo payment for a member needs the
/// member to confirm with their PIN in the member app. The cashier UI should
/// show a "waiting for PIN" dialog (polling [MemberApprovalRepository.status]),
/// then retry the same payment call with the same [ref] once approved.
class MemberApprovalRequiredException implements Exception {
  /// The approval ref that was used (and must be reused on retry).
  final String ref;
  final int amount;

  /// Server-provided expiry, if any (ISO string). Used for the countdown.
  final DateTime? expiresAt;

  const MemberApprovalRequiredException({
    required this.ref,
    required this.amount,
    this.expiresAt,
  });

  factory MemberApprovalRequiredException.fromApproval(
    String ref,
    Map<String, dynamic>? approval,
  ) {
    int asInt(dynamic v) =>
        v is int ? v : int.tryParse(v?.toString() ?? "") ?? 0;
    return MemberApprovalRequiredException(
      ref: ref,
      amount: asInt(approval?['amount']),
      expiresAt: DateTime.tryParse(approval?['expires_at']?.toString() ?? ""),
    );
  }

  @override
  String toString() => "Menunggu konfirmasi PIN member (ref $ref)";
}

/// A fresh idempotency ref for one checkout attempt.
String generateApprovalRef() {
  final r = Random();
  final rand = List.generate(6, (_) => r.nextInt(36).toRadixString(36)).join();
  return "appr-${DateTime.now().microsecondsSinceEpoch}-$rand";
}

class MemberApprovalException implements Exception {
  final String message;
  const MemberApprovalException(this.message);
  @override
  String toString() => message;
}

class MemberApprovalRepository {
  final Dio _dio = Dio();

  /// Current status: pending | approved | rejected | expired | cancelled.
  Future<String> status(String ref) async {
    final data = await _post(ApiEndpoints.memberApprovalStatus, {"ref": ref});
    final result = data['result'];
    if (result is Map && result['status'] != null) {
      return result['status'].toString();
    }
    throw const MemberApprovalException("Format status tidak valid.");
  }

  Future<void> cancel(String ref) async {
    try {
      await _post(ApiEndpoints.memberApprovalCancel, {"ref": ref});
    } catch (_) {
      // best-effort — an expired/gone approval doesn't need cancelling
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
          throw const MemberApprovalException("Format respons tidak valid.");
        }
      }
      if (data is! Map<String, dynamic>) {
        throw const MemberApprovalException("Format respons tidak valid.");
      }
      final code = data['code'];
      if (code != null && code.toString() != "200") {
        throw MemberApprovalException(
          data['result']?.toString() ?? "Permintaan gagal.",
        );
      }
      return data;
    } on MemberApprovalException {
      rethrow;
    } on DioException catch (_) {
      throw const MemberApprovalException("Tidak dapat terhubung ke server.");
    }
  }
}
