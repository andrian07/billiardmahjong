import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../data/member_approval_repository.dart';

/// Result of the wait dialog.
enum MemberApprovalOutcome { approved, rejected, expired, cancelled, error }

/// Shown after a Potong Saldo payment returns NEED_MEMBER_APPROVAL. Polls the
/// approval status every 2s while showing a countdown; pops a
/// [MemberApprovalOutcome]. If the cashier closes it, the approval is cancelled
/// server-side so it can't be approved later out of band.
class MemberApprovalWaitDialog extends StatefulWidget {
  final String ref;
  final int amount;
  final DateTime? expiresAt;

  const MemberApprovalWaitDialog({
    super.key,
    required this.ref,
    required this.amount,
    this.expiresAt,
  });

  @override
  State<MemberApprovalWaitDialog> createState() =>
      _MemberApprovalWaitDialogState();
}

class _MemberApprovalWaitDialogState extends State<MemberApprovalWaitDialog> {
  final _repository = MemberApprovalRepository();

  Timer? _poll;
  Timer? _tick;
  bool _closing = false;
  late DateTime _deadline;
  Duration _left = Duration.zero;

  @override
  void initState() {
    super.initState();
    _deadline =
        widget.expiresAt ?? DateTime.now().add(const Duration(seconds: 120));
    _updateLeft();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _updateLeft());
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    _check();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _updateLeft() {
    final left = _deadline.difference(DateTime.now());
    setState(() => _left = left.isNegative ? Duration.zero : left);
    if (left.isNegative && !_closing) _finish(MemberApprovalOutcome.expired);
  }

  Future<void> _check() async {
    if (_closing) return;
    try {
      final status = await _repository.status(widget.ref);
      switch (status) {
        case 'approved':
          _finish(MemberApprovalOutcome.approved);
          break;
        case 'rejected':
          _finish(MemberApprovalOutcome.rejected);
          break;
        case 'expired':
          _finish(MemberApprovalOutcome.expired);
          break;
        case 'cancelled':
          _finish(MemberApprovalOutcome.cancelled);
          break;
        // 'pending' -> keep waiting
      }
    } catch (_) {
      // transient network error while polling — keep trying
    }
  }

  void _finish(MemberApprovalOutcome outcome) {
    if (_closing || !mounted) return;
    _closing = true;
    _poll?.cancel();
    _tick?.cancel();
    Navigator.of(context).pop(outcome);
  }

  Future<void> _cancel() async {
    if (_closing) return;
    _closing = true;
    _poll?.cancel();
    _tick?.cancel();
    await _repository.cancel(widget.ref);
    if (mounted) Navigator.of(context).pop(MemberApprovalOutcome.cancelled);
  }

  @override
  Widget build(BuildContext context) {
    final s = _left.inSeconds;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 18),
            Text(
              "Menunggu Konfirmasi Member",
              style: AppText.title.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.amount > 0
                  ? "Member sedang memasukkan PIN di aplikasinya untuk menyetujui "
                        "pembayaran ${formatCurrency(widget.amount)} lewat saldo."
                  : "Member sedang memasukkan PIN di aplikasinya untuk menyetujui "
                        "pemakaian saldo waktu tersimpan.",
              style: AppText.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              s > 0 ? "Sisa waktu: ${s}s" : "Waktu habis",
              style: AppText.body.copyWith(
                fontWeight: FontWeight.w700,
                color: s <= 20 ? AppColors.danger : AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _closing ? null : _cancel,
            child: const Text("BATALKAN"),
          ),
        ],
      ),
    );
  }
}
