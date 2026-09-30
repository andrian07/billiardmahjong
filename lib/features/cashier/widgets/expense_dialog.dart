import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/thousands_input_formatter.dart';
import '../../../models/cashier_summary.dart';
import '../../../shared/widgets/app_toast.dart';
import '../data/cashier_repository.dart';

/// "Pengeluaran" popup — the cashier logs a cash outlay during the shift
/// (keterangan + nominal) and picks which drawer it comes out of: Billiard,
/// Mahjong, or Cafe. At Tutup Kas the total is subtracted from that channel's CASH
/// figure (revenue / Grand Total stays put).
///
/// Entries and their deletes are scoped to this cashier ([userId]) and
/// today only — same window Tutup Kas reads.
class ExpenseDialog extends StatefulWidget {
  final int userId;
  final String cashierName;

  const ExpenseDialog({
    super.key,
    required this.userId,
    required this.cashierName,
  });

  @override
  State<ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<ExpenseDialog> {
  final _repository = CashierRepository();
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  final _nominalController = TextEditingController();

  ExpenseChannel _channel = ExpenseChannel.billing;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<CashExpense> _expenses = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _nominalController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repository.getExpensesToday(userId: widget.userId);
      if (!mounted) return;
      setState(() {
        _expenses = list;
        _loading = false;
      });
    } on CashierRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final nominal = parseThousands(_nominalController.text) ?? 0;
    setState(() => _saving = true);
    try {
      await _repository.addExpense(
        userId: widget.userId,
        keterangan: _noteController.text.trim(),
        nominal: nominal,
        channel: _channel,
      );
      if (!mounted) return;
      _noteController.clear();
      _nominalController.clear();
      setState(() => _saving = false);
      await _load();
      if (mounted) AppToast.success(context, "Pengeluaran dicatat");
    } on CashierRepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(context, e.message);
    }
  }

  Future<void> _delete(CashExpense expense) async {
    try {
      await _repository.deleteExpense(
        expenseId: expense.id,
        userId: widget.userId,
      );
      await _load();
    } on CashierRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
  }

  int get _totalBilling => _expenses
      .where((e) => e.channel == ExpenseChannel.billing)
      .fold(0, (s, e) => s + e.nominal);

  int get _totalMahjong => _expenses
      .where((e) => e.channel == ExpenseChannel.mahjong)
      .fold(0, (s, e) => s + e.nominal);

  int get _totalCafe => _expenses
      .where((e) => e.channel == ExpenseChannel.cafe)
      .fold(0, (s, e) => s + e.nominal);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusXL),
      ),
      backgroundColor: AppColors.card,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.radiusXL),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            const Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: 20),
            _buildForm(),
            const SizedBox(height: 20),
            const Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: 16),
            _buildList(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSizes.radiusMedium,
                        ),
                      ),
                    ),
                    child: const Text("SELESAI"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          ),
          child: const Icon(
            Icons.payments_outlined,
            color: AppColors.danger,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Pengeluaran Kas",
                style: AppText.title.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                "${widget.cashierName} • dikurangi dari kas saat Tutup Kas",
                style: AppText.caption,
              ),
            ],
          ),
        ),
        InkWell(
          onTap: () => Navigator.of(context).pop(),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Kurangi dari kas",
            style: AppText.bodySecondary.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _channelChip("Billiard", ExpenseChannel.billing),
              const SizedBox(width: 8),
              _channelChip("Mahjong", ExpenseChannel.mahjong),
              const SizedBox(width: 8),
              _channelChip("Cafe", ExpenseChannel.cafe),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "Keterangan",
            style: AppText.bodySecondary.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _noteController,
            style: AppText.body,
            textCapitalization: TextCapitalization.sentences,
            decoration: _fieldDecoration("mis. Beli galon, parkir, bensin"),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? "Isi keterangan"
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            "Nominal",
            style: AppText.bodySecondary.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _nominalController,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ThousandsInputFormatter()],
                  style: AppText.body,
                  decoration: _fieldDecoration("0"),
                  validator: (value) {
                    final parsed = parseThousands(value ?? "");
                    if (parsed == null || parsed <= 0) {
                      return "Masukkan nominal yang valid";
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _add,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_rounded, size: 18),
                  label: const Text("TAMBAH"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    textStyle: AppText.button,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppSizes.radiusMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _channelChip(String label, ExpenseChannel channel) {
    final active = _channel == channel;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _channel = channel),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppText.bodySecondary.copyWith(
            color: active ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          _error!,
          style: AppText.caption.copyWith(color: AppColors.danger),
        ),
      );
    }
    if (_expenses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          "Belum ada pengeluaran hari ini.",
          style: AppText.bodySecondary,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Pengeluaran hari ini",
          style: AppText.bodySecondary.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            child: Column(
              children: [for (final e in _expenses) _expenseRow(e)],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _totalRow("Total Pengeluaran Billiard", _totalBilling),
        const SizedBox(height: 4),
        _totalRow("Total Pengeluaran Mahjong", _totalMahjong),
        const SizedBox(height: 4),
        _totalRow("Total Pengeluaran Cafe", _totalCafe),
      ],
    );
  }

  Widget _expenseRow(CashExpense e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              expenseChannelLabel(e.channel),
              style: AppText.caption.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              e.keterangan,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatCurrency(e.nominal),
            style: AppText.body.copyWith(fontWeight: FontWeight.w600),
          ),
          IconButton(
            tooltip: "Hapus",
            visualDensity: VisualDensity.compact,
            onPressed: () => _delete(e),
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, int value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppText.caption),
        Text(
          formatCurrency(value),
          style: AppText.caption.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.caption,
      isDense: true,
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}
