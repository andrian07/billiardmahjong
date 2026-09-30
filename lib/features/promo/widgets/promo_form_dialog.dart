import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/thousands_input_formatter.dart';
import '../../../models/promo.dart';
import '../../../models/table_category.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../settings/data/table_category_repository.dart';

class PromoFormResult {
  final String name;
  final PromoType type;
  final String tableType;
  final int value;
  final int? hourGained;
  final int? freeHour;
  final List<int> categoryIds;
  final List<int>? validDays;
  final int? validTimeStart;
  final int? validTimeEnd;

  const PromoFormResult({
    required this.name,
    required this.type,
    this.tableType = 'billiard',
    required this.value,
    this.hourGained,
    this.freeHour,
    this.categoryIds = const [],
    this.validDays,
    this.validTimeStart,
    this.validTimeEnd,
  });
}

class PromoFormDialog extends StatefulWidget {
  final Promo? promo;

  const PromoFormDialog({super.key, this.promo});

  @override
  State<PromoFormDialog> createState() => _PromoFormDialogState();
}

class _PromoFormDialogState extends State<PromoFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.promo?.name ?? "",
  );
  late final _valueController = TextEditingController(
    text: widget.promo != null ? formatThousands(widget.promo!.value) : "",
  );
  late final _hourController = TextEditingController(
    text: widget.promo?.hourGained != null
        ? "${widget.promo!.hourGained}"
        : "",
  );
  late final _freeHourController = TextEditingController(
    text: widget.promo?.freeHour != null ? "${widget.promo!.freeHour}" : "",
  );
  late PromoType _type = widget.promo?.type ?? PromoType.percentage;
  late String _tableType = widget.promo?.tableType ?? 'billiard';

  late final Set<int> _selectedDays = {...?widget.promo?.validDays};
  late bool _useTimeWindow = widget.promo?.hasTimeWindow ?? false;
  late int? _timeStart = widget.promo?.validTimeStart;
  late int? _timeEnd = widget.promo?.validTimeEnd;

  final _categoryRepository = TableCategoryRepository();
  List<TableCategory> _categories = [];
  bool _loadingCategories = true;
  late final Set<int> _selectedCategories = {
    ...?widget.promo?.categoryIds,
  };

  bool get _isEdit => widget.promo != null;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final result = await _categoryRepository.getTableCategories(
        page: 1,
        perPage: 1000,
      );
      if (!mounted) return;
      setState(() {
        _categories = result.items.where((c) => c.active).toList();
        _loadingCategories = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCategories = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    _hourController.dispose();
    _freeHourController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (_useTimeWindow && (_timeStart == null || _timeEnd == null)) {
      AppToast.error(context, "Pilih jam mulai dan jam selesai berlaku promo");
      return;
    }
    // Jam mulai boleh lebih besar dari jam selesai - itu artinya jendela melewati tengah
    // malam (mis. 22 s/d 4 = berlaku jam 22:00 malam - 04:00 keesokan paginya). Hanya sama
    // persis (durasi nol) yang ditolak.
    if (_useTimeWindow && _timeStart == _timeEnd) {
      AppToast.error(context, "Jam mulai tidak boleh sama dengan jam selesai");
      return;
    }

    Navigator.of(context).pop(
      PromoFormResult(
        name: _nameController.text.trim(),
        type: _type,
        tableType: _tableType,
        value: parseThousands(_valueController.text) ?? 0,
        hourGained: _type == PromoType.fixed
            ? int.tryParse(_hourController.text.trim())
            : null,
        freeHour: _type == PromoType.fixed
            ? int.tryParse(_freeHourController.text.trim())
            : null,
        categoryIds: _selectedCategories.toList(),
        validDays: _selectedDays.isNotEmpty ? _selectedDays.toList() : null,
        validTimeStart: _useTimeWindow ? _timeStart : null,
        validTimeEnd: _useTimeWindow ? _timeEnd : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusXL),
      ),
      backgroundColor: AppColors.card,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 780,
          maxHeight: screenSize.height * 0.88,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.radiusXL),
            border: Border.all(color: AppColors.border),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 18),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 20),
                // 2 kolom bersebelahan supaya tidak scroll terlalu panjang
                Flexible(
                  child: SingleChildScrollView(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _leftColumn()),
                        const SizedBox(width: 28),
                        Expanded(child: _rightColumn()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
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
                        child: const Text("BATAL"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _submit,
                        icon: Icon(
                          _isEdit
                              ? Icons.save_outlined
                              : Icons.local_offer_outlined,
                          size: 20,
                        ),
                        label: Text(_isEdit ? "SIMPAN" : "TAMBAH PROMO"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
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
          ),
        ),
      ),
    );
  }

  Widget _leftColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label("Nama Promo"),
        const SizedBox(height: 8),
        TextFormField(
          controller: _nameController,
          style: AppText.body,
          decoration: _inputDecoration(
            hint: "Masukkan nama promo",
            prefixIcon: Icons.local_offer_outlined,
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? "Nama promo wajib diisi"
              : null,
        ),
        const SizedBox(height: 18),
        _label("Tipe Promo"),
        const SizedBox(height: 8),
        _buildTypeSelector(),
        const SizedBox(height: 18),
        _label(
          _type == PromoType.percentage
              ? "Nilai Diskon (%)"
              : "Nilai Diskon (Rp)",
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _valueController,
          keyboardType: TextInputType.number,
          inputFormatters: const [ThousandsInputFormatter()],
          style: AppText.body,
          decoration: _inputDecoration(
            hint: "0",
            prefixIcon: Icons.payments_outlined,
            suffixText: _type == PromoType.percentage ? "%" : null,
          ),
          validator: (value) {
            final parsed = parseThousands(value ?? "");
            if (parsed == null || parsed < 0) return "Masukkan angka yang valid";
            if (_type == PromoType.percentage && parsed > 100) {
              return "Diskon persen maksimal 100";
            }
            return null;
          },
        ),
        if (_type == PromoType.fixed) ...[
          const SizedBox(height: 18),
          _label("Jam yang Didapat"),
          const SizedBox(height: 8),
          TextFormField(
            controller: _hourController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: AppText.body,
            decoration: _inputDecoration(
              hint: "0",
              prefixIcon: Icons.timer_outlined,
              suffixText: "jam",
            ),
            validator: (value) {
              final parsed = int.tryParse((value ?? "").trim());
              if (parsed == null || parsed <= 0) {
                return "Masukkan jumlah jam yang valid";
              }
              return null;
            },
          ),
          const SizedBox(height: 4),
          Text(
            "Durasi timer otomatis terisi & terkunci sebesar ini saat promo "
            "ini dipilih di open billing.",
            style: AppText.caption,
          ),
          const SizedBox(height: 18),
          _label("Gratis Berapa Jam (opsional)"),
          const SizedBox(height: 8),
          TextFormField(
            controller: _freeHourController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: AppText.body,
            decoration: _inputDecoration(
              hint: "0",
              prefixIcon: Icons.card_giftcard_outlined,
              suffixText: "jam",
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Hanya keterangan (mis. tampil sebagai \"2 Jam Gratis 1 Jam\"). "
            "Baru berefek saat meja dibuka pakai waktu tersimpan customer: "
            "main lebih dari \"Jam yang Didapat\" hanya memotong sisa waktu "
            "sejumlah itu, kelebihannya (maks jam gratis ini) tidak ikut "
            "dipotong - tidak berkelipatan.",
            style: AppText.caption,
          ),
        ],
        const SizedBox(height: 18),
        _label("Jenis Promo"),
        const SizedBox(height: 8),
        _buildTableTypeSelector(),
        const SizedBox(height: 18),
        _label("Kategori Meja Berlaku (kosongkan = semua kategori)"),
        const SizedBox(height: 8),
        _buildCategorySelector(),
      ],
    );
  }

  Widget _rightColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label("Hari Berlaku (kosongkan = semua hari)"),
        const SizedBox(height: 8),
        _buildDaySelector(),
        const SizedBox(height: 18),
        _buildTimeWindowToggle(),
        if (_useTimeWindow) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildHourDropdown(
                  label: "Dari Jam",
                  value: _timeStart,
                  onChanged: (v) => setState(() => _timeStart = v),
                  maxHour: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildHourDropdown(
                  label: "Sampai Jam",
                  value: _timeEnd,
                  onChanged: (v) => setState(() => _timeEnd = v),
                  maxHour: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Promo ini hanya bisa dipakai untuk mode Timer, dan sesi harus "
            "selesai sebelum jam yang dipilih di atas.",
            style: AppText.caption,
          ),
        ],
      ],
    );
  }

  Widget _buildCategorySelector() {
    if (_loadingCategories) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final categories = _categories.where((c) => c.type == _tableType).toList();
    if (categories.isEmpty) {
      return Text(
        "Tidak ada kategori meja. Promo berlaku untuk semua.",
        style: AppText.caption,
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in categories)
          _selectableChip(
            label: c.name,
            active: _selectedCategories.contains(c.id),
            onTap: () => setState(() {
              if (!_selectedCategories.add(c.id)) {
                _selectedCategories.remove(c.id);
              }
            }),
          ),
      ],
    );
  }

  Widget _selectableChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: .15)
              : AppColors.background,
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppText.body.copyWith(
            fontWeight: FontWeight.w600,
            color: active ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTableTypeSelector() {
    Widget option(String value, String label) {
      final active = _tableType == value;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          onTap: () => setState(() {
            if (_tableType == value) return;
            _tableType = value;
            _selectedCategories.clear();
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary.withValues(alpha: .15)
                  : AppColors.background,
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              border: Border.all(
                color: active ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Text(
              label,
              style: AppText.body.copyWith(
                fontWeight: FontWeight.w600,
                color: active ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option('billiard', "Billiard"),
        const SizedBox(width: 10),
        option('mahjong', "Mahjong"),
      ],
    );
  }

  Widget _buildTypeSelector() {
    return Row(
      children: [
        Expanded(child: _typeOption(PromoType.percentage)),
        const SizedBox(width: 10),
        Expanded(child: _typeOption(PromoType.fixed)),
      ],
    );
  }

  Widget _typeOption(PromoType type) {
    final active = _type == type;

    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
      onTap: () => setState(() => _type = type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: .15)
              : AppColors.background,
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          type.label,
          style: AppText.body.copyWith(
            fontWeight: FontWeight.w600,
            color: active ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildDaySelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in weekdayLabels.entries)
          _dayChip(day: entry.key, label: entry.value),
      ],
    );
  }

  Widget _dayChip({required int day, required String label}) {
    final active = _selectedDays.contains(day);

    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
      onTap: () => setState(() {
        if (active) {
          _selectedDays.remove(day);
        } else {
          _selectedDays.add(day);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: .15)
              : AppColors.background,
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppText.body.copyWith(
            fontWeight: FontWeight.w600,
            color: active ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTimeWindowToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          "Batasi Jam Berlaku",
          style: AppText.body.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          "Promo hanya bisa dipakai di antara jam tertentu",
          style: AppText.caption,
        ),
        value: _useTimeWindow,
        activeThumbColor: AppColors.primary,
        onChanged: (v) => setState(() {
          _useTimeWindow = v;
          if (!v) {
            _timeStart = null;
            _timeEnd = null;
          }
        }),
      ),
    );
  }

  Widget _buildHourDropdown({
    required String label,
    required int? value,
    required ValueChanged<int?> onChanged,
    required int maxHour,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: value,
          dropdownColor: AppColors.card,
          style: AppText.body,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textSecondary,
          ),
          decoration: _inputDecoration(hint: "Pilih jam"),
          items: [
            for (var h = 0; h <= maxHour; h++)
              DropdownMenuItem(
                value: h,
                child: Text("${h.toString().padLeft(2, '0')}:00"),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
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
            color: AppColors.primary.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          ),
          child: const Icon(
            Icons.local_offer_outlined,
            color: AppColors.primary,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEdit ? "Edit Promo" : "Tambah Promo",
                style: AppText.title.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                _isEdit ? "Perbarui data promo" : "Buat promo baru",
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

  Widget _label(String text) {
    return Text(
      text,
      style: AppText.bodySecondary.copyWith(fontWeight: FontWeight.w600),
    );
  }

  InputDecoration _inputDecoration({
    String? hint,
    IconData? prefixIcon,
    String? suffixText,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.caption,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 20, color: AppColors.textSecondary)
          : null,
      suffixText: suffixText,
      suffixStyle: AppText.body.copyWith(color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.background,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    );
  }
}
