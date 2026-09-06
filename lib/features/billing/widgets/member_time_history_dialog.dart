import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../models/customer_time_history_entry.dart';
import '../data/billing_repository.dart';

/// Dialog "Riwayat Waktu Tersimpan" untuk 1 member: daftar mutasi IN (disimpan /
/// refund) & OUT (dipakai buka meja), terbaru dulu. Data dari gameon lewat
/// Billing/customer_time_history.
Future<void> showMemberTimeHistoryDialog(
  BuildContext context, {
  required int customerId,
  String? customerName,
}) {
  return showDialog(
    context: context,
    builder: (_) => _MemberTimeHistoryDialog(
      customerId: customerId,
      customerName: customerName,
    ),
  );
}

class _MemberTimeHistoryDialog extends StatefulWidget {
  final int customerId;
  final String? customerName;

  const _MemberTimeHistoryDialog({
    required this.customerId,
    this.customerName,
  });

  @override
  State<_MemberTimeHistoryDialog> createState() =>
      _MemberTimeHistoryDialogState();
}

class _MemberTimeHistoryDialogState extends State<_MemberTimeHistoryDialog> {
  final _repository = BillingRepository();
  late Future<List<CustomerTimeHistoryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.getCustomerTimeHistory(customerId: widget.customerId);
  }

  static const _months = [
    "Jan", "Feb", "Mar", "Apr", "Mei", "Jun",
    "Jul", "Agu", "Sep", "Okt", "Nov", "Des",
  ];

  String _fmtWhen(DateTime? at) {
    if (at == null) return "";
    String two(int n) => n.toString().padLeft(2, '0');
    return "${at.day} ${_months[at.month - 1]} ${at.year} • "
        "${two(at.hour)}:${two(at.minute)}";
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
      ),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.history_rounded, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Riwayat Waktu Tersimpan", style: AppText.title),
                        if (widget.customerName != null)
                          Text(widget.customerName!, style: AppText.caption),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: FutureBuilder<List<CustomerTimeHistoryEntry>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return _msg("Gagal memuat riwayat. Coba lagi nanti.");
                    }
                    final items = snapshot.data ?? const [];
                    if (items.isEmpty) {
                      return _msg("Belum ada riwayat waktu tersimpan.");
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 16, color: AppColors.divider),
                      itemBuilder: (_, i) => _row(items[i]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _msg(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(text, style: AppText.bodySecondary),
        ),
      );

  Widget _row(CustomerTimeHistoryEntry h) {
    final color = h.isIn ? AppColors.success : AppColors.danger;
    final when = _fmtWhen(h.at);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            h.isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
            size: 16,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                h.categoryMejaName,
                style: AppText.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (h.ref != null) h.ref!,
                  if (when.isNotEmpty) when,
                  if (h.createdBy.isNotEmpty) h.createdBy,
                ].join("  •  "),
                style: AppText.caption,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          h.amountLabel,
          style: AppText.body.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
