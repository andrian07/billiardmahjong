import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/navigation/app_navigation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../models/table_setting.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_layout.dart';
import '../../shared/widgets/app_toast.dart';
import 'data/table_setting_repository.dart';
import 'widgets/table_category_dialog.dart';
import 'widgets/table_setting_edit_dialog.dart';

class TableSettingPage extends StatefulWidget {
  const TableSettingPage({super.key});

  @override
  State<TableSettingPage> createState() => _TableSettingPageState();
}

class _TableSettingPageState extends State<TableSettingPage> {
  final _repository = TableSettingRepository();

  List<TableSetting> _tables = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tables = await _repository.getTableSettings();
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _loading = false;
      });
    } on TableSettingRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _openEditDialog(TableSetting table) async {
    final result = await showDialog<TableSettingEditResult>(
      context: context,
      builder: (_) => TableSettingEditDialog(table: table),
    );
    if (result == null) return;

    try {
      await _repository.updateTableSetting(
        tableId: table.id,
        relay: result.relay,
        number: result.number,
        point: result.point,
      );
      if (!mounted) return;
      AppToast.success(
        context,
        "Setting meja ${result.number} berhasil diperbarui",
      );
      // Reload (bukan patch lokal) supaya categoryName ikut ter-resolve dari server,
      // bukan cuma categoryId-nya.
      await _load();
    } on TableSettingRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: "Setting Meja",
      subtitle: "Kelola relay dan point tiap meja",
      showSearch: false,
      activeMenuKey: "setting_table",
      onMenuSelect: (key) => navigateToMenu(context, key),
      onRefresh: _load,
      child: _buildCard(),
    );
  }

  Widget _buildCard() {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: _buildToolbar(),
          ),
          const Divider(height: 1, color: AppColors.divider),
          if (!_loading && _error == null && _tables.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 14, 36, 6),
              child: _TableSettingRow.header(),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildErrorState(_error!);
    }
    if (_tables.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: _tables.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final table = _tables[index];
        return _RowCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _TableSettingRow.data(
              no: index + 1,
              table: table,
              onEdit: () => _openEditDialog(table),
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolbar() {
    return Row(
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
            Icons.settings_input_component_rounded,
            color: AppColors.primary,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Setting Meja",
              style: AppText.title.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              _loading || _error != null
                  ? "Memuat data..."
                  : "${_tables.length} meja terdaftar",
              style: AppText.caption,
            ),
          ],
        ),
        const Spacer(),
        SizedBox(
          height: 40,
          child: OutlinedButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const TableCategoryDialog(),
            ),
            icon: const Icon(Icons.category_outlined, size: 18),
            label: Text(
              "Kategori Meja",
              style: AppText.button.copyWith(fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.textHint.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.table_bar_rounded,
              size: 30,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 14),
          Text("Belum ada meja ditemukan", style: AppText.bodySecondary),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cloud_off_rounded,
              size: 30,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.bodySecondary,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _load,
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
}

/// Individual row rendered as its own card, with a hover "lift" effect.
class _RowCard extends StatefulWidget {
  final Widget child;

  const _RowCard({required this.child});

  @override
  State<_RowCard> createState() => _RowCardState();
}

class _RowCardState extends State<_RowCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _hovered
              ? AppColors.hover
              : AppColors.background.withValues(alpha: .4),
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          border: Border.all(
            color: _hovered
                ? AppColors.primary.withValues(alpha: .4)
                : AppColors.border,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .25),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: widget.child,
      ),
    );
  }
}

class _TableSettingRow extends StatelessWidget {
  final bool header;
  final int? no;
  final TableSetting? table;
  final VoidCallback? onEdit;

  const _TableSettingRow.header()
    : header = true,
      no = null,
      table = null,
      onEdit = null;

  const _TableSettingRow.data({
    required this.no,
    required this.table,
    required this.onEdit,
  }) : header = false;

  @override
  Widget build(BuildContext context) {
    if (header) {
      return _row(
        no: _headerText("NO"),
        number: _headerText("MEJA"),
        relay: _headerText("RELAY", alignEnd: true),
        point: _headerText("POINT", alignEnd: true),
        category: _headerText("CATEGORY", alignEnd: true),
        aksi: _headerText("AKSI", alignCenter: true),
      );
    }

    final t = table!;
    final cellStyle = AppText.caption.copyWith(fontSize: 13);

    return _row(
      no: Text("$no", style: cellStyle.copyWith(color: AppColors.textHint)),
      number: Text(
        t.number,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: cellStyle.copyWith(fontWeight: FontWeight.w600),
      ),
      relay: Text("${t.relay}", textAlign: TextAlign.end, style: cellStyle),
      point: Text("${t.point}", textAlign: TextAlign.end, style: cellStyle),
      category: Text(
        t.categoryName ?? "-",
        textAlign: TextAlign.end,
        style: cellStyle.copyWith(color: AppColors.textHint),
      ),
      aksi: Center(
        child: IconButton(
          tooltip: "Edit",
          icon: const Icon(
            Icons.edit_outlined,
            size: 17,
            color: AppColors.textSecondary,
          ),
          onPressed: onEdit,
        ),
      ),
    );
  }

  static Widget _headerText(
    String text, {
    bool alignEnd = false,
    bool alignCenter = false,
  }) {
    return Text(
      text,
      textAlign: alignCenter
          ? TextAlign.center
          : (alignEnd ? TextAlign.end : TextAlign.start),
      style: AppText.caption.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
        color: AppColors.textSecondary,
      ),
    );
  }

  static Widget _row({
    required Widget no,
    required Widget number,
    required Widget relay,
    required Widget point,
    required Widget category,
    required Widget aksi,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 28, child: no),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: number),
        const SizedBox(width: 10),
        Expanded(child: relay),
        const SizedBox(width: 10),
        Expanded(child: point),
        const SizedBox(width: 10),
        Expanded(child: category),
        const SizedBox(width: 10),
        SizedBox(width: 48, child: aksi),
      ],
    );
  }
}
