import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../models/pagination_info.dart';
import '../../../models/table_category.dart';
import '../../../shared/widgets/app_toast.dart';
import '../data/table_category_repository.dart';
import '../data/table_setting_repository.dart';
import 'table_category_form_dialog.dart';

/// "Kategori Meja" popup — lists/manages table categories (VIP, Reguler,
/// etc.) via the Setting/*_category_meja endpoints. Opened from the Setting
/// > Table page; changes made here don't need to flow back to the caller.
class TableCategoryDialog extends StatefulWidget {
  const TableCategoryDialog({super.key});

  @override
  State<TableCategoryDialog> createState() => _TableCategoryDialogState();
}

class _TableCategoryDialogState extends State<TableCategoryDialog> {
  static const _perPage = 10;

  final _repository = TableCategoryRepository();
  final _tableRepository = TableSettingRepository();

  List<TableCategory> _categories = [];
  PaginationInfo _pagination = PaginationInfo.empty;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _repository.getTableCategories(
        page: page,
        perPage: _perPage,
      );
      if (!mounted) return;
      setState(() {
        _categories = result.items;
        _pagination = result.pagination;
        _loading = false;
      });
    } on TableCategoryRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _goToPage(int page) {
    if (page == _pagination.currentPage || _loading) return;
    _load(page);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        ),
        title: Text(title, style: AppText.title),
        content: Text(message, style: AppText.bodySecondary),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("TIDAK"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _openAddDialog() async {
    final result = await showDialog<TableCategoryFormResult>(
      context: context,
      builder: (_) => const TableCategoryFormDialog(),
    );
    if (result == null) return;

    try {
      final categoryId = await _repository.addTableCategory(
        name: result.name,
        priceOption: result.priceOption,
        type: result.type,
      );
      await _assignTablesToCategory(categoryId, result.selectedTableIds);
      if (!mounted) return;
      AppToast.success(context, "Kategori ${result.name} berhasil ditambahkan");
      await _load(_pagination.currentPage);
    } on TableCategoryRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
  }

  Future<void> _openEditDialog(TableCategory category) async {
    final result = await showDialog<TableCategoryFormResult>(
      context: context,
      builder: (_) => TableCategoryFormDialog(category: category),
    );
    if (result == null) return;

    try {
      await _repository.editTableCategory(
        id: category.id,
        name: result.name,
        active: result.active,
        priceOption: result.priceOption,
        type: result.type,
      );
      await _assignTablesToCategory(category.id, result.selectedTableIds);
      if (!mounted) return;
      AppToast.success(context, "Kategori ${result.name} berhasil diperbarui");
      await _load(_pagination.currentPage);
    } on TableCategoryRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
  }

  /// Assigns this category to every checked table — see the caveat on
  /// TableCategoryFormResult.selectedTableIds: unchecking a table that
  /// already used this category leaves it untouched, it isn't cleared.
  Future<void> _assignTablesToCategory(
    int categoryId,
    List<int> tableIds,
  ) async {
    for (final tableId in tableIds) {
      try {
        await _tableRepository.updateTableSetting(
          tableId: tableId,
          categoryId: categoryId,
        );
      } on TableSettingRepositoryException {
        // Satu meja gagal tidak boleh membatalkan penyimpanan kategori itu
        // sendiri (yang sudah berhasil) - meja itu bisa diatur manual lagi
        // lewat Setting > Table.
      }
    }
  }

  Future<void> _confirmDelete(TableCategory category) async {
    final confirmed = await _confirm(
      title: "Hapus Kategori?",
      message:
          "Apakah Anda yakin akan menghapus kategori \"${category.name}\"?",
      confirmLabel: "YA, HAPUS",
    );
    if (!confirmed) return;

    try {
      await _repository.deleteTableCategory(category.id);
      if (!mounted) return;
      AppToast.success(context, "Kategori ${category.name} berhasil dihapus");
      await _load(_pagination.currentPage);
    } on TableCategoryRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
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
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.radiusXL),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 16),
              Expanded(child: _buildBody()),
              if (!_loading && _error == null && _categories.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 12),
                _buildPagination(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          ),
          child: const Icon(
            Icons.category_outlined,
            color: AppColors.primary,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Kategori Meja",
                style: AppText.title.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                "Kelola kategori meja (VIP, Reguler, dll)",
                style: AppText.caption,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 36,
          child: ElevatedButton.icon(
            onPressed: _openAddDialog,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text("Tambah", style: AppText.button.copyWith(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 36,
              color: AppColors.danger,
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppText.bodySecondary,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => _load(_pagination.currentPage),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text("Coba Lagi"),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.category_outlined,
              size: 36,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 10),
            Text("Belum ada kategori meja", style: AppText.bodySecondary),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _categories.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildCategoryCard(_categories[index]),
    );
  }

  Widget _buildCategoryCard(TableCategory category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text("Harga ${category.priceOption}", style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (category.active ? AppColors.success : AppColors.textHint)
                  .withValues(alpha: .15),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              category.active ? "Aktif" : "Nonaktif",
              style: AppText.caption.copyWith(
                fontSize: 11,
                color: category.active ? AppColors.success : AppColors.textHint,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            tooltip: "Aksi",
            color: AppColors.card,
            icon: const Icon(
              Icons.more_vert_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              side: const BorderSide(color: AppColors.border),
            ),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _openEditDialog(category);
                  break;
                case 'delete':
                  _confirmDelete(category);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'edit',
                child: _menuItem(Icons.edit_outlined, "Edit"),
              ),
              PopupMenuItem(
                value: 'delete',
                child: _menuItem(
                  Icons.delete_outline_rounded,
                  "Hapus",
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color ?? AppColors.textSecondary),
        const SizedBox(width: 10),
        Text(
          label,
          style: AppText.body.copyWith(color: color ?? AppColors.text),
        ),
      ],
    );
  }

  Widget _buildPagination() {
    final p = _pagination;

    return Row(
      children: [
        Text("${p.totalItems} kategori", style: AppText.caption),
        const Spacer(),
        _pageArrow(
          icon: Icons.chevron_left_rounded,
          onTap: p.hasPrevPage ? () => _goToPage(p.currentPage - 1) : null,
        ),
        const SizedBox(width: 6),
        Text(
          "${p.currentPage} / ${p.totalPages}",
          style: AppText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 6),
        _pageArrow(
          icon: Icons.chevron_right_rounded,
          onTap: p.hasNextPage ? () => _goToPage(p.currentPage + 1) : null,
        ),
      ],
    );
  }

  Widget _pageArrow({required IconData icon, required VoidCallback? onTap}) {
    final enabled = onTap != null;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.textSecondary : AppColors.textHint,
        ),
      ),
    );
  }
}
