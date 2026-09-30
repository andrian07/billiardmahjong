import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/navigation/app_navigation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/formatters.dart';
import '../../models/pagination_info.dart';
import '../../models/promo.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_layout.dart';
import '../../shared/widgets/app_toast.dart';
import '../settings/data/table_category_repository.dart';
import 'data/promo_repository.dart';
import 'widgets/cafe_promo_section.dart';
import 'widgets/promo_form_dialog.dart';

enum _PromoTab { billing, cafe }

class PromoPage extends StatefulWidget {
  const PromoPage({super.key});

  @override
  State<PromoPage> createState() => _PromoPageState();
}

class _PromoPageState extends State<PromoPage> {
  static const _perPage = 10;

  final _repository = PromoRepository();
  final _categoryRepository = TableCategoryRepository();

  _PromoTab _tab = _PromoTab.billing;

  List<Promo> _promos = [];
  PaginationInfo _pagination = PaginationInfo.empty;
  bool _loading = true;
  String? _error;

  /// category_meja_id -> nama, dipakai untuk kolom "Kategori" di daftar promo.
  Map<int, String> _categoryNames = {};

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _load(1);
  }

  Future<void> _loadCategories() async {
    try {
      final result = await _categoryRepository.getTableCategories(
        page: 1,
        perPage: 200,
      );
      if (!mounted) return;
      setState(() {
        _categoryNames = {for (final c in result.items) c.id: c.name};
      });
    } on TableCategoryRepositoryException {
      // biarkan kosong - kolom kategori akan fallback ke "#id"
    }
  }

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _repository.getPromos(page: page, perPage: _perPage);
      if (!mounted) return;
      setState(() {
        _promos = result.promos;
        _pagination = result.pagination;
        _loading = false;
      });
    } on PromoRepositoryException catch (e) {
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

  void _notifyError(String message) {
    AppToast.error(context, message);
  }

  void _notifySuccess(String message) {
    AppToast.success(context, message);
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
    final result = await showDialog<PromoFormResult>(
      context: context,
      builder: (_) => const PromoFormDialog(),
    );
    if (result == null) return;

    try {
      await _repository.addPromo(
        name: result.name,
        type: result.type,
        tableType: result.tableType,
        value: result.value,
        hourGained: result.hourGained,
        freeHour: result.freeHour,
        categoryIds: result.categoryIds,
        validDays: result.validDays,
        validTimeStart: result.validTimeStart,
        validTimeEnd: result.validTimeEnd,
      );
      if (!mounted) return;
      _notifySuccess("Promo ${result.name} berhasil ditambahkan");
      await _load(_pagination.currentPage);
    } on PromoRepositoryException catch (e) {
      if (!mounted) return;
      _notifyError(e.message);
    }
  }

  Future<void> _openEditDialog(Promo promo) async {
    final result = await showDialog<PromoFormResult>(
      context: context,
      builder: (_) => PromoFormDialog(promo: promo),
    );
    if (result == null) return;

    try {
      await _repository.editPromo(
        id: promo.id,
        name: result.name,
        type: result.type,
        tableType: result.tableType,
        value: result.value,
        hourGained: result.hourGained,
        freeHour: result.freeHour,
        categoryIds: result.categoryIds,
        validDays: result.validDays,
        validTimeStart: result.validTimeStart,
        validTimeEnd: result.validTimeEnd,
      );
      if (!mounted) return;
      _notifySuccess("Promo ${result.name} berhasil diperbarui");
      await _load(_pagination.currentPage);
    } on PromoRepositoryException catch (e) {
      if (!mounted) return;
      _notifyError(e.message);
    }
  }

  Future<void> _confirmDelete(Promo promo) async {
    final confirmed = await _confirm(
      title: "Hapus Promo?",
      message: "Apakah Anda yakin akan menghapus promo \"${promo.name}\"?",
      confirmLabel: "YA, HAPUS",
    );
    if (!confirmed) return;

    try {
      await _repository.deletePromo(promo.id);
      if (!mounted) return;
      _notifySuccess("Promo ${promo.name} berhasil dihapus");
      await _load(_pagination.currentPage);
    } on PromoRepositoryException catch (e) {
      if (!mounted) return;
      _notifyError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: "Promo",
      subtitle: "Kelola promo diskon",
      showSearch: false,
      activeMenuKey: "promo",
      onMenuSelect: (key) => navigateToMenu(context, key),
      onRefresh: () => _load(_pagination.currentPage),
      child: _buildCard(),
    );
  }

  Widget _buildCard() {
    final isCafe = _tab == _PromoTab.cafe;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: _buildToolbar(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _buildTabSwitch(),
          ),
          const Divider(height: 1, color: AppColors.divider),
          if (isCafe)
            const Expanded(child: CafePromoSection())
          else ...[
            if (!_loading && _error == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 14, 36, 6),
                child: _PromoRow.header(),
              ),
            Expanded(child: _buildBody()),
            if (!_loading && _error == null && _promos.isNotEmpty) ...[
              const Divider(height: 1, color: AppColors.divider),
              Container(
                color: AppColors.background.withValues(alpha: .3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: _buildPagination(),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildTabSwitch() {
    Widget tab(String label, _PromoTab value, IconData icon) {
      final active = _tab == value;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          onTap: () => setState(() => _tab = value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              border: Border.all(
                color: active ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppText.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : AppColors.textSecondary,
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
        tab("Promo Billing", _PromoTab.billing, Icons.table_bar_rounded),
        const SizedBox(width: 8),
        tab("Promo Cafe", _PromoTab.cafe, Icons.local_cafe_outlined),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildErrorState(_error!);
    }
    if (_promos.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: _promos.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final promo = _promos[index];
        return _RowCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _PromoRow.data(
              no:
                  (_pagination.currentPage - 1) * _pagination.perPage +
                  index +
                  1,
              promo: promo,
              categoryNames: _categoryNames,
              onEdit: () => _openEditDialog(promo),
              onDelete: () => _confirmDelete(promo),
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
            Icons.local_offer_outlined,
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
              "Daftar Promo",
              style: AppText.title.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              _loading || _error != null
                  ? "Memuat data..."
                  : "${_pagination.totalItems} promo terdaftar",
              style: AppText.caption,
            ),
          ],
        ),
        const Spacer(),
        if (_tab == _PromoTab.billing)
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _openAddDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                "Tambah Promo",
                style: AppText.button.copyWith(fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
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
              Icons.local_offer_outlined,
              size: 30,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 14),
          Text("Belum ada promo ditemukan", style: AppText.bodySecondary),
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

  Widget _buildPagination() {
    final p = _pagination;
    final startItem = p.totalItems == 0
        ? 0
        : (p.currentPage - 1) * p.perPage + 1;
    final endItem = (p.currentPage * p.perPage).clamp(0, p.totalItems);

    return Row(
      children: [
        Text(
          "Menampilkan $startItem-$endItem dari ${p.totalItems} promo",
          style: AppText.caption,
        ),
        const Spacer(),
        _pageArrow(
          icon: Icons.chevron_left_rounded,
          onTap: p.hasPrevPage ? () => _goToPage(p.currentPage - 1) : null,
        ),
        const SizedBox(width: 6),
        ..._buildPageButtons(),
        const SizedBox(width: 6),
        _pageArrow(
          icon: Icons.chevron_right_rounded,
          onTap: p.hasNextPage ? () => _goToPage(p.currentPage + 1) : null,
        ),
      ],
    );
  }

  List<Widget> _buildPageButtons() {
    final window = _pageWindow(_pagination.totalPages, _pagination.currentPage);
    final widgets = <Widget>[];

    for (var i = 0; i < window.length; i++) {
      if (i > 0 && window[i] - window[i - 1] > 1) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text("...", style: AppText.caption),
          ),
        );
      }
      widgets.add(
        _pageNumberButton(
          window[i],
          active: window[i] == _pagination.currentPage,
        ),
      );
      widgets.add(const SizedBox(width: 6));
    }

    return widgets;
  }

  List<int> _pageWindow(int totalPages, int current) {
    if (totalPages <= 7) return List.generate(totalPages, (i) => i + 1);

    final set = <int>{1, totalPages, current};
    if (current - 1 >= 1) set.add(current - 1);
    if (current + 1 <= totalPages) set.add(current + 1);

    return set.toList()..sort();
  }

  Widget _pageNumberButton(int page, {required bool active}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: active ? null : () => _goToPage(page),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          "$page",
          style: AppText.caption.copyWith(
            color: active ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _pageArrow({required IconData icon, required VoidCallback? onTap}) {
    final enabled = onTap != null;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? AppColors.textSecondary : AppColors.textHint,
        ),
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

class _PromoRow extends StatelessWidget {
  final bool header;
  final int? no;
  final Promo? promo;
  final Map<int, String> categoryNames;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _PromoRow.header()
    : header = true,
      no = null,
      promo = null,
      categoryNames = const {},
      onEdit = null,
      onDelete = null;

  const _PromoRow.data({
    required this.no,
    required this.promo,
    required this.categoryNames,
    required this.onEdit,
    required this.onDelete,
  }) : header = false;

  /// Nama kategori tempat promo ini berlaku, atau "Semua kategori" kalau
  /// tidak dibatasi. Fallback ke "#id" kalau nama kategori belum termuat.
  String _categoryLabel(Promo p) {
    if (p.categoryIds.isEmpty) {
      return p.tableType == 'mahjong' ? "Semua meja Mahjong" : "Semua meja Billiard";
    }
    return p.categoryIds.map((id) => categoryNames[id] ?? "#$id").join(", ");
  }

  /// "Jam yang didapat" untuk promo Fix: jam utama + bonus jam gratis.
  /// Promo Diskon % tidak memberi jam, jadi "-".
  String _hoursLabel(Promo p) {
    if (p.type != PromoType.fixed) return "-";
    final base = p.hourGained ?? 0;
    final free = p.freeHour ?? 0;
    if (base == 0 && free == 0) return "-";
    final buffer = StringBuffer("$base jam");
    if (free > 0) buffer.write(" + $free gratis");
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (header) {
      return _row(
        no: _headerText("NO"),
        name: _headerText("NAMA PROMO"),
        category: _headerText("KATEGORI BERLAKU"),
        hours: _headerText("JAM DIDAPAT", alignCenter: true),
        type: _headerText("TIPE", alignCenter: true),
        value: _headerText("NILAI", alignEnd: true),
        aksi: _headerText("AKSI", alignCenter: true),
      );
    }

    final p = promo!;
    final cellStyle = AppText.caption.copyWith(fontSize: 13);
    final isPercentage = p.type == PromoType.percentage;
    final typeColor = isPercentage ? AppColors.purple : AppColors.info;

    return _row(
      no: Text("$no", style: cellStyle.copyWith(color: AppColors.textHint)),
      name: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: cellStyle.copyWith(fontWeight: FontWeight.w600),
          ),
          if ((p.freeHour != null && p.freeHour! > 0) ||
              p.hasDayRestriction ||
              p.hasTimeWindow) ...[
            const SizedBox(height: 2),
            Text(
              [
                if (p.freeHour != null && p.freeHour! > 0)
                  "Gratis ${p.freeHour} jam (pakai waktu tersimpan)",
                if (p.hasDayRestriction)
                  p.validDays!.map((d) => weekdayLabels[d]).join(", "),
                if (p.hasTimeWindow)
                  "${p.validTimeStart.toString().padLeft(2, '0')}:00-"
                      "${p.validTimeEnd.toString().padLeft(2, '0')}:00",
              ].join(" • "),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                fontSize: 10,
                color: AppColors.textHint,
              ),
            ),
          ],
        ],
      ),
      category: Text(
        _categoryLabel(p),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: cellStyle.copyWith(
          color: p.categoryIds.isEmpty
              ? AppColors.textHint
              : AppColors.textSecondary,
        ),
      ),
      hours: Text(
        _hoursLabel(p),
        textAlign: TextAlign.center,
        style: cellStyle.copyWith(fontWeight: FontWeight.w600),
      ),
      type: Align(
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: typeColor.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(
            p.type.label,
            style: AppText.caption.copyWith(
              fontSize: 11,
              color: typeColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      value: Text(
        isPercentage ? "${p.value}%" : formatCurrency(p.value),
        textAlign: TextAlign.end,
        style: cellStyle.copyWith(fontWeight: FontWeight.w600),
      ),
      aksi: Center(
        child: PopupMenuButton<String>(
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
                onEdit?.call();
                break;
              case 'delete':
                onDelete?.call();
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
      ),
    );
  }

  static Widget _menuItem(IconData icon, String label, {Color? color}) {
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
    required Widget name,
    required Widget category,
    required Widget hours,
    required Widget type,
    required Widget value,
    required Widget aksi,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 28, child: no),
        const SizedBox(width: 10),
        Expanded(flex: 3, child: name),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: category),
        const SizedBox(width: 10),
        SizedBox(width: 110, child: hours),
        const SizedBox(width: 10),
        SizedBox(width: 90, child: type),
        const SizedBox(width: 10),
        SizedBox(width: 100, child: value),
        const SizedBox(width: 10),
        SizedBox(width: 48, child: aksi),
      ],
    );
  }
}
