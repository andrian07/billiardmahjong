import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../models/access_menu.dart';
import '../../../models/role.dart';
import '../../../models/role_menu_access.dart';
import '../data/role_repository.dart';

// Codes (ms_menu.menu_code, from Access/menu_list_no_pagging) that correspond
// to an actual, currently role-gated sidebar item, in the same order as
// AppSidebar's own sections — with the label the sidebar actually shows,
// since the backend's raw menu_name doesn't always match (e.g. "Master
// Role" here vs "Role & Akses" in the sidebar, "Pos" vs "POS"). ms_menu also
// accumulates leftover/test rows over time (old features, QA fixtures) that
// no longer correspond to anything in the sidebar; anything not listed here
// is filtered out of the dialog entirely so it can't drift out of sync with
// what the sidebar actually shows. "opname" (owner-only by a separate,
// harder-coded mechanism) and "ganti_password" / "booking" (always visible
// to everyone) are deliberately excluded too, since none is actually
// role-gated.
const _sidebarMenuOrder = <String>[
  'meja', 'pos', 'transaksi',
  'master_member', 'master_pengguna', 'master_role', 'master_promo',
  'produk', 'pembelian', 'unit', 'kategori',
  'Laporan',
  'harga_meja', 'setting_table', 'tukar_point',
];

const _sidebarMenuLabels = <String, String>{
  'meja': 'Meja',
  'pos': 'POS',
  'transaksi': 'Transaksi',
  'master_member': 'Member',
  'master_pengguna': 'Pengguna',
  'master_role': 'Role & Akses',
  'master_promo': 'Promo',
  'produk': 'Produk',
  'pembelian': 'Pembelian',
  'unit': 'Unit',
  'kategori': 'Kategori',
  'Laporan': 'Laporan (Billing, Cafe, Saldo, Stok, Pembelian)',
  'harga_meja': 'Harga Meja',
  'setting_table': 'Table',
  'tukar_point': 'Tukar Point',
};

/// Lets a supervisor pick which menus a role can access in the sidebar —
/// loads the current state via Access/role_access and saves the whole
/// matrix back through Access/update_role_access. The backend still keeps
/// separate can_view/can_add/can_edit/can_delete flags per menu, but
/// nothing in the app actually checks add/edit/delete individually (only
/// can_view drives sidebar visibility - see AppSidebar), so this UI just
/// shows one "akses" checkbox per menu and mirrors it onto all four flags.
class RoleAccessDialog extends StatefulWidget {
  final Role role;

  const RoleAccessDialog({super.key, required this.role});

  @override
  State<RoleAccessDialog> createState() => _RoleAccessDialogState();
}

class _RoleAccessDialogState extends State<RoleAccessDialog> {
  final _repository = RoleRepository();

  bool _loading = true;
  String? _loadError;
  List<AccessMenu> _menus = [];
  Map<int, RoleMenuAccess> _accessByMenu = {};

  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final allMenus = await _repository.getMenus();
      final menusByCode = {for (final m in allMenus) m.code: m};
      final menus = [
        for (final code in _sidebarMenuOrder)
          if (menusByCode[code] != null) menusByCode[code]!,
      ];
      final existing = await _repository.getRoleAccess(widget.role.id);
      final existingByMenu = {for (final a in existing) a.menuId: a};

      if (!mounted) return;
      setState(() {
        _menus = menus;
        _accessByMenu = {
          for (final menu in menus)
            menu.id: existingByMenu[menu.id] ?? RoleMenuAccess(menuId: menu.id),
        };
        _loading = false;
      });
    } on RoleRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      await _repository.updateRoleAccess(
        widget.role.id,
        _accessByMenu.values.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on RoleRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e.message;
      });
    }
  }

  void _toggleAll(bool value) {
    setState(() {
      for (final access in _accessByMenu.values) {
        access.canView = value;
        access.canAdd = value;
        access.canEdit = value;
        access.canDelete = value;
      }
    });
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
          maxWidth: 480,
          maxHeight: screenSize.height * 0.85,
        ),
        child: Container(
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
              const SizedBox(height: 16),
              Expanded(child: _buildBody()),
              if (!_loading && _loadError == null && _menus.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildBulkActions(),
              ],
              const SizedBox(height: 16),
              if (_saveError != null) ...[
                _buildInlineError(_saveError!, onRetry: _save),
                const SizedBox(height: 12),
              ],
              _buildActions(),
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
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          ),
          child: const Icon(
            Icons.admin_panel_settings_outlined,
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
                "Hak Akses",
                style: AppText.title.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text("Role: ${widget.role.name}", style: AppText.caption),
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(child: _buildInlineError(_loadError!, onRetry: _load));
    }

    if (_menus.isEmpty) {
      return Center(
        child: Text("Belum ada menu terdaftar.", style: AppText.bodySecondary),
      );
    }

    return SingleChildScrollView(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        ),
        child: Column(
          children: [
            _buildMatrixHeader(),
            for (var i = 0; i < _menus.length; i++)
              _buildMatrixRow(_menus[i], striped: i.isEven),
          ],
        ),
      ),
    );
  }

  Widget _buildMatrixHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: .6),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSizes.radiusMedium),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "Menu",
              style: AppText.caption.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          _matrixHeaderCell("Akses"),
        ],
      ),
    );
  }

  Widget _matrixHeaderCell(String label) {
    return SizedBox(
      width: 90,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppText.caption.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildMatrixRow(AccessMenu menu, {required bool striped}) {
    final access = _accessByMenu[menu.id]!;

    return Container(
      color: striped
          ? AppColors.background.withValues(alpha: .3)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _sidebarMenuLabels[menu.code] ?? menu.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body,
            ),
          ),
          _matrixCheckbox(
            value: access.canView,
            onChanged: (v) => setState(() {
              access.canView = v;
              access.canAdd = v;
              access.canEdit = v;
              access.canDelete = v;
            }),
          ),
        ],
      ),
    );
  }

  Widget _matrixCheckbox({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SizedBox(
      width: 90,
      child: Checkbox(
        value: value,
        activeColor: AppColors.primary,
        onChanged: (v) => onChanged(v ?? false),
      ),
    );
  }

  Widget _buildInlineError(String message, {required VoidCallback onRetry}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: AppColors.danger.withValues(alpha: .3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: AppText.caption.copyWith(color: AppColors.danger),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.danger,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text("Coba Lagi"),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _toggleAll(true),
            icon: const Icon(Icons.done_all_rounded, size: 16),
            label: const Text("Pilih Semua"),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withValues(alpha: .4)),
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _toggleAll(false),
            icon: const Icon(Icons.remove_done_rounded, size: 16),
            label: const Text("Hapus Semua"),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    final canSave = !_loading && _loadError == null && !_saving;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
            ),
            child: const Text("BATAL"),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: canSave ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined, size: 20),
            label: Text(_saving ? "MENYIMPAN..." : "SIMPAN HAK AKSES"),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.textHint,
              minimumSize: const Size(0, 48),
              elevation: 0,
              textStyle: AppText.button,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
