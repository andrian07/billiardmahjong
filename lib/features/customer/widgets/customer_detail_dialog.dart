import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/customer.dart';
import '../../../models/customer_point_history_entry.dart';
import '../../../models/customer_saldo_history_entry.dart';
import '../../../models/customer_time_history_entry.dart';
import '../../billing/data/billing_repository.dart';
import '../data/customer_repository.dart';

/// Dialog "Detail Member": tiga tab riwayat POTONGAN milik 1 member —
/// potongan saldo (history_saldo OUT), potongan point (customer_point_history
/// OUT), potongan waktu (customer_time_history OUT). Semua read-only, terbaru
/// dulu. Sumber data gameon lewat proxy billing_api.
Future<void> showCustomerDetailDialog(
  BuildContext context, {
  required Customer customer,
}) {
  return showDialog(
    context: context,
    builder: (_) => _CustomerDetailDialog(customer: customer),
  );
}

class _CustomerDetailDialog extends StatefulWidget {
  final Customer customer;

  const _CustomerDetailDialog({required this.customer});

  @override
  State<_CustomerDetailDialog> createState() => _CustomerDetailDialogState();
}

class _CustomerDetailDialogState extends State<_CustomerDetailDialog> {
  final _customerRepo = CustomerRepository();
  final _billingRepo = BillingRepository();

  late final Future<List<CustomerSaldoHistoryEntry>> _saldoFuture;
  late final Future<List<CustomerPointHistoryEntry>> _pointFuture;
  late final Future<List<CustomerTimeHistoryEntry>> _timeFuture;

  @override
  void initState() {
    super.initState();
    final id = widget.customer.id;
    _saldoFuture = _customerRepo.getSaldoDeductions(id);
    _pointFuture = _customerRepo.getPointDeductions(id);
    _timeFuture = _billingRepo
        .getCustomerTimeHistory(customerId: id, perPage: 50)
        .then((rows) => rows.where((e) => !e.isIn).toList());
  }

  static const _months = [
    "Jan", "Feb", "Mar", "Apr", "Mei", "Jun",
    "Jul", "Agu", "Sep", "Okt", "Nov", "Des",
  ];

  static String _fmtWhen(DateTime? at) {
    if (at == null) return "";
    String two(int n) => n.toString().padLeft(2, '0');
    return "${at.day} ${_months[at.month - 1]} ${at.year} • "
        "${two(at.hour)}:${two(at.minute)}";
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;

    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
      ),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: DefaultTabController(
          length: 3,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.receipt_long_rounded,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Detail Member", style: AppText.title),
                          Text(
                            [
                              c.name,
                              if (c.idNumber.isNotEmpty) c.idNumber,
                            ].join("  •  "),
                            style: AppText.caption,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _SummaryPill(
                      label: "Saldo",
                      value: formatCurrency(c.saldo),
                    ),
                    const SizedBox(width: 8),
                    _SummaryPill(
                      label: "Poin",
                      value: formatThousands(c.point),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const TabBar(
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  tabs: [
                    Tab(text: "Potongan Saldo"),
                    Tab(text: "Potongan Point"),
                    Tab(text: "Potongan Waktu"),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    children: [
                      _saldoTab(),
                      _pointTab(),
                      _timeTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _saldoTab() {
    return _HistoryList<CustomerSaldoHistoryEntry>(
      future: _saldoFuture,
      emptyText: "Belum ada potongan saldo.",
      rowBuilder: (h) => _row(
        title: h.description.isNotEmpty ? h.description : "Potongan Saldo",
        subtitleParts: [
          if (h.refType.isNotEmpty) h.refType,
          _fmtWhen(h.at),
          if (h.createdBy.isNotEmpty) h.createdBy,
        ],
        amount: "−${formatCurrency(h.amount)}",
      ),
    );
  }

  Widget _pointTab() {
    return _HistoryList<CustomerPointHistoryEntry>(
      future: _pointFuture,
      emptyText: "Belum ada potongan point.",
      rowBuilder: (h) => _row(
        title: h.description.isNotEmpty ? h.description : "Potongan Point",
        subtitleParts: [
          if (h.refType.isNotEmpty) h.refType,
          _fmtWhen(h.at),
          if (h.createdBy.isNotEmpty) h.createdBy,
        ],
        amount: "−${formatThousands(h.point)} poin",
      ),
    );
  }

  Widget _timeTab() {
    return _HistoryList<CustomerTimeHistoryEntry>(
      future: _timeFuture,
      emptyText: "Belum ada potongan waktu.",
      rowBuilder: (h) => _row(
        title: h.categoryMejaName,
        subtitleParts: [
          if (h.ref != null) h.ref!,
          _fmtWhen(h.at),
          if (h.createdBy.isNotEmpty) h.createdBy,
        ],
        amount: "−${formatDuration(h.amount)}",
      ),
    );
  }

  Widget _row({
    required String title,
    required List<String> subtitleParts,
    required String amount,
  }) {
    const color = AppColors.danger;
    final subtitle = subtitleParts.where((p) => p.isNotEmpty).join("  •  ");
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
          child: const Icon(
            Icons.north_east_rounded,
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
                title,
                style: AppText.body.copyWith(fontWeight: FontWeight.w600),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle, style: AppText.caption),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          amount,
          style: AppText.body.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _HistoryList<T> extends StatelessWidget {
  final Future<List<T>> future;
  final String emptyText;
  final Widget Function(T) rowBuilder;

  const _HistoryList({
    required this.future,
    required this.emptyText,
    required this.rowBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _msg("Gagal memuat riwayat. Coba lagi nanti.");
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) return _msg(emptyText);
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 16, color: AppColors.divider),
          itemBuilder: (_, i) => rowBuilder(items[i]),
        );
      },
    );
  }

  Widget _msg(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, style: AppText.bodySecondary),
        ),
      );
}

class _SummaryPill extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("$label: ", style: AppText.caption),
          Text(
            value,
            style: AppText.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}
