import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../models/table_category.dart';
import '../../../models/table_setting.dart';
import '../data/table_setting_repository.dart';

class TableCategoryFormResult {
  final String name;
  final bool active;
  final String type;
  final int priceOption;

  /// Table ids the user checked to use this category — see the "Meja yang
  /// Memakai Kategori Ini" section. Only additions are applied by the
  /// caller (see TableCategoryDialog); unchecking a table that already used
  /// this category does NOT clear it (category_meja_id has no "none" value
  /// on the backend - see Billing_model::update_setting_table()).
  final List<int> selectedTableIds;

  const TableCategoryFormResult({
    required this.name,
    required this.active,
    required this.type,
    required this.priceOption,
    this.selectedTableIds = const [],
  });
}

class TableCategoryFormDialog extends StatefulWidget {
  final TableCategory? category;

  const TableCategoryFormDialog({super.key, this.category});

  @override
  State<TableCategoryFormDialog> createState() =>
      _TableCategoryFormDialogState();
}

class _TableCategoryFormDialogState extends State<TableCategoryFormDialog> {
  final _tableRepository = TableSettingRepository();
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.category?.name ?? "",
  );
  late bool _active = widget.category?.active ?? true;
  late String _type = widget.category?.type ?? "billiard";
  late int _priceOption = widget.category?.priceOption ?? 1;

  bool get _isEdit => widget.category != null;

  bool _loadingTables = true;
  String? _tablesError;
  List<TableSetting> _tables = [];
  final Set<int> _selectedTableIds = {};

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  Future<void> _loadTables() async {
    setState(() {
      _loadingTables = true;
      _tablesError = null;
    });

    try {
      final tables = await _tableRepository.getTableSettings();
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _selectedTableIds
          ..clear()
          ..addAll(
            tables
                .where((t) => t.categoryId == widget.category?.id)
                .map((t) => t.id),
          );
        _loadingTables = false;
      });
    } on TableSettingRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _tablesError = e.message;
        _loadingTables = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      TableCategoryFormResult(
        name: _nameController.text.trim(),
        active: _active,
        type: _type,
        priceOption: _priceOption,
        selectedTableIds: _selectedTableIds.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusXL),
      ),
      backgroundColor: AppColors.card,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Container(
          width: 400,
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
                const SizedBox(height: 20),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 22),

                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label("Nama Kategori"),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _nameController,
                          autofocus: true,
                          style: AppText.body,
                          decoration: _inputDecoration(
                            hint: "Mis. VIP, Reguler",
                            prefixIcon: Icons.category_outlined,
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? "Nama kategori wajib diisi"
                              : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),

                        const SizedBox(height: 16),
                        _label("Jenis Meja"),
                        const SizedBox(height: 8),
                        _buildTypeSelector(),

                        const SizedBox(height: 16),
                        _label("Harga yang Digunakan"),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          initialValue: _priceOption,
                          dropdownColor: AppColors.card,
                          style: AppText.body,
                          isExpanded: true,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: AppColors.textSecondary,
                          ),
                          decoration: _inputDecoration(
                            prefixIcon: Icons.payments_outlined,
                          ),
                          items: [
                            for (var i = 1; i <= 5; i++)
                              DropdownMenuItem(
                                value: i,
                                child: Text("Harga $i"),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _priceOption = value);
                          },
                        ),

                        if (_isEdit) ...[
                          const SizedBox(height: 16),
                          _buildActiveToggle(),
                        ],

                        const SizedBox(height: 16),
                        _label("Meja yang Memakai Kategori Ini"),
                        const SizedBox(height: 8),
                        _buildTableSelector(),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),
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
                          _isEdit ? Icons.save_outlined : Icons.add_rounded,
                          size: 20,
                        ),
                        label: Text(_isEdit ? "SIMPAN" : "TAMBAH KATEGORI"),
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

  Widget _buildTypeSelector() {
    Widget option(String value, String label, IconData icon) {
      final selected = _type == value;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _type = value),
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: .15)
                  : AppColors.background,
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: AppText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option("billiard", "Billiard", Icons.table_bar_rounded),
        const SizedBox(width: 12),
        option("mahjong", "Mahjong", Icons.casino_outlined),
      ],
    );
  }

  Widget _buildTableSelector() {
    if (_loadingTables) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text("Memuat daftar meja...", style: AppText.caption),
          ],
        ),
      );
    }

    if (_tablesError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          border: Border.all(color: AppColors.danger.withValues(alpha: .3)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: AppColors.danger,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _tablesError!,
                style: AppText.caption.copyWith(color: AppColors.danger),
              ),
            ),
            TextButton(onPressed: _loadTables, child: const Text("Coba Lagi")),
          ],
        ),
      );
    }

    if (_tables.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          border: Border.all(color: AppColors.border),
        ),
        child: Text("Belum ada meja terdaftar", style: AppText.caption),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      child: Scrollbar(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          children: [
            for (final table in _tables)
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  table.number,
                  style: AppText.body.copyWith(fontSize: 13),
                ),
                subtitle: table.categoryName != null
                    ? Text(
                        "Saat ini: ${table.categoryName}",
                        style: AppText.caption.copyWith(fontSize: 11),
                      )
                    : null,
                value: _selectedTableIds.contains(table.id),
                activeColor: AppColors.primary,
                onChanged: (checked) => setState(() {
                  if (checked ?? false) {
                    _selectedTableIds.add(table.id);
                  } else {
                    _selectedTableIds.remove(table.id);
                  }
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveToggle() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Aktif",
                style: AppText.body.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                "Kategori nonaktif tidak tampil untuk dipilih",
                style: AppText.caption,
              ),
            ],
          ),
        ),
        Switch(
          value: _active,
          activeThumbColor: AppColors.primary,
          onChanged: (value) => setState(() => _active = value),
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
            Icons.category_outlined,
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
                _isEdit ? "Edit Kategori Meja" : "Tambah Kategori Meja",
                style: AppText.title.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                _isEdit ? "Perbarui data kategori" : "Buat kategori baru",
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

  InputDecoration _inputDecoration({String? hint, IconData? prefixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.caption,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 20, color: AppColors.textSecondary)
          : null,
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
