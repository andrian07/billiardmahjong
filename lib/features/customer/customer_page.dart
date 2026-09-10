import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/business_info.dart';
import '../../core/navigation/app_navigation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/formatters.dart';
import '../../models/customer.dart';
import '../../models/pagination_info.dart';
import '../../models/saldo_receipt.dart';
import '../../services/receipt_printer_service.dart';
import '../../services/session_storage.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_layout.dart';
import '../../shared/widgets/app_toast.dart';
import 'data/customer_repository.dart';
import 'widgets/add_saldo_dialog.dart';
import 'widgets/customer_detail_dialog.dart';
import 'widgets/customer_saved_time_dialog.dart';

class CustomerPage extends StatefulWidget {
  const CustomerPage({super.key});

  @override
  State<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage> {
  static const _perPage = 10;

  final _repository = CustomerRepository();
  final _sessionStorage = SessionStorage();
  final _receiptPrinter = ReceiptPrinterService();

  List<Customer> _customers = [];
  PaginationInfo _pagination = PaginationInfo.empty;
  bool _loading = true;
  String? _error;
  bool _isSuperadmin = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load(1);
    _loadIsSuperadmin();
  }

  Future<void> _loadIsSuperadmin() async {
    final isSuperadmin = await _sessionStorage.isSuperadmin();
    if (mounted) setState(() => _isSuperadmin = isSuperadmin);
  }

  void _openSaldoManagement() {
    context.push('/setting/saldo');
  }

  Future<void> _syncCustomers() async {
    setState(() => _syncing = true);
    try {
      final syncedCount = await _repository.syncCustomers();
      if (!mounted) return;
      _notifySuccess(
        syncedCount > 0
            ? "$syncedCount member baru berhasil disinkronkan"
            : "Tidak ada member baru untuk disinkronkan",
      );
      await _load(_pagination.currentPage);
    } on CustomerRepositoryException catch (e) {
      if (!mounted) return;
      _notifyError(e.message);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _repository.getCustomers(
        page: page,
        perPage: _perPage,
      );
      if (!mounted) return;
      setState(() {
        _customers = result.customers;
        _pagination = result.pagination;
        _loading = false;
      });
    } on CustomerRepositoryException catch (e) {
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

  Future<void> _openAddSaldoDialog() async {
    final result = await showDialog<AddSaldoResult>(
      context: context,
      builder: (_) => const AddSaldoDialog(),
    );
    if (result == null) return;

    try {
      final session = await _sessionStorage.getSession();
      final createdBy = session?['username']?.toString() ?? "";
      final paidBy = int.tryParse(session?['id']?.toString() ?? "") ?? 0;

      final transaksiSaldoId = await _repository.addSaldo(
        customerId: result.customerId,
        saldoId: result.saldoId,
        paymentId: result.paymentId,
        createdBy: createdBy,
        paidBy: paidBy,
      );
      if (!mounted) return;
      _notifySuccess(
        "Saldo ${result.customerName} berhasil ditambahkan "
        "(${formatCurrency(result.nominal)})",
      );

      try {
        await _receiptPrinter.printSaldoReceipt(
          SaldoReceipt(
            businessName: BusinessInfo.name,
            businessAddress: BusinessInfo.address,
            invoiceNumber: _buildSaldoInvoiceNumber(transaksiSaldoId),
            customerName: result.customerName,
            nominal: result.nominal,
            discount: result.discount,
            price: result.price,
            paymentMethod: result.paymentMethodName,
            date: DateTime.now(),
            cashierName: createdBy,
          ),
        );
      } on ReceiptPrinterException catch (e) {
        if (!mounted) return;
        AppToast.error(context, "Gagal mencetak nota: $e");
      }
    } on CustomerRepositoryException catch (e) {
      if (!mounted) return;
      _notifyError(e.message);
    }
  }

  String _buildSaldoInvoiceNumber(int transaksiSaldoId) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = "${now.year}-${two(now.month)}-${two(now.day)}";
    return "SALDO/${BusinessInfo.outletCode}/$date/"
        "${transaksiSaldoId.toString().padLeft(4, '0')}";
  }

  Future<void> _confirmDelete(Customer customer) async {
    final confirmed = await _confirm(
      title: "Hapus Member?",
      message:
          "Apakah Anda yakin akan menghapus member \"${customer.name}\"?",
      confirmLabel: "YA, HAPUS",
    );
    if (!confirmed) return;

    try {
      await _repository.deleteCustomer(customer.id);
      if (!mounted) return;
      _notifySuccess("Member ${customer.name} berhasil dihapus");
      await _load(_pagination.currentPage);
    } on CustomerRepositoryException catch (e) {
      if (!mounted) return;
      _notifyError(e.message);
    }
  }

  Future<void> _openSavedTimeDialog(Customer customer) {
    return showDialog(
      context: context,
      builder: (_) => CustomerSavedTimeDialog(customer: customer),
    );
  }

  Future<void> _openDetailDialog(Customer customer) {
    return showCustomerDetailDialog(context, customer: customer);
  }

  Future<void> _confirmResetPassword(Customer customer) async {
    final confirmed = await _confirm(
      title: "Reset Password?",
      message:
          "Apakah Anda yakin akan mereset password member \"${customer.name}\"?",
      confirmLabel: "YA, RESET",
    );
    if (!confirmed) return;

    try {
      await _repository.resetPassword(customer.id);
      if (!mounted) return;
      _notifySuccess("Password ${customer.name} berhasil direset");
    } on CustomerRepositoryException catch (e) {
      if (!mounted) return;
      _notifyError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: "Member",
      subtitle: "Kelola data member",
      showSearch: false,
      activeMenuKey: "pelanggan",
      onMenuSelect: (key) => navigateToMenu(context, key),
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
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 14, 36, 6),
              child: _CustomerRow.header(),
            ),
          Expanded(child: _buildBody()),
          if (!_loading && _error == null && _customers.isNotEmpty) ...[
            const Divider(height: 1, color: AppColors.divider),
            Container(
              color: AppColors.background.withValues(alpha: .3),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: _buildPagination(),
            ),
          ],
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
    if (_customers.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: _customers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final customer = _customers[index];
        return _RowCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _CustomerRow.data(
              no:
                  (_pagination.currentPage - 1) * _pagination.perPage +
                  index +
                  1,
              customer: customer,
              onViewDetail: () => _openDetailDialog(customer),
              onViewSavedTime: () => _openSavedTimeDialog(customer),
              onResetPassword: () => _confirmResetPassword(customer),
              onDelete: () => _confirmDelete(customer),
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
            Icons.people_alt_outlined,
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
              "Daftar Member",
              style: AppText.title.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              _loading || _error != null
                  ? "Memuat data..."
                  : "${_pagination.totalItems} member terdaftar",
              style: AppText.caption,
            ),
          ],
        ),
        const Spacer(),
        if (_isSuperadmin) ...[
          SizedBox(
            height: 40,
            child: OutlinedButton.icon(
              onPressed: _openSaldoManagement,
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: Text(
                "Kelola Saldo",
                style: AppText.button.copyWith(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 40,
            child: OutlinedButton.icon(
              onPressed: _syncing ? null : _syncCustomers,
              icon: _syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 16),
              label: Text(
                "Sync Customer",
                style: AppText.button.copyWith(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        SizedBox(
          height: 40,
          child: OutlinedButton.icon(
            onPressed: _openAddSaldoDialog,
            icon: const Icon(Icons.savings_outlined, size: 16),
            label: Text(
              "Tambah Saldo",
              style: AppText.button.copyWith(fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text,
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
              Icons.people_outline_rounded,
              size: 30,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 14),
          Text("Tidak ada member ditemukan", style: AppText.bodySecondary),
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
          "Menampilkan $startItem-$endItem dari ${p.totalItems} member",
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

class _CustomerRow extends StatelessWidget {
  final bool header;
  final int? no;
  final Customer? customer;
  final VoidCallback? onViewDetail;
  final VoidCallback? onViewSavedTime;
  final VoidCallback? onResetPassword;
  final VoidCallback? onDelete;

  const _CustomerRow.header()
    : header = true,
      no = null,
      customer = null,
      onViewDetail = null,
      onViewSavedTime = null,
      onResetPassword = null,
      onDelete = null;

  const _CustomerRow.data({
    required this.no,
    required this.customer,
    required this.onViewDetail,
    required this.onViewSavedTime,
    required this.onResetPassword,
    required this.onDelete,
  }) : header = false;

  @override
  Widget build(BuildContext context) {
    if (header) {
      return _row(
        no: _headerText("NO"),
        id: _headerText("KODE"),
        name: _headerText("NAMA"),
        phone: _headerText("TELEPON"),
        address: _headerText("ALAMAT"),
        email: _headerText("EMAIL"),
        saldo: _headerText("SALDO", alignEnd: true),
        point: _headerText("POIN", alignEnd: true),
        aksi: _headerText("AKSI", alignCenter: true),
      );
    }

    final c = customer!;
    final cellStyle = AppText.caption.copyWith(fontSize: 13);

    return _row(
      no: Text("$no", style: cellStyle.copyWith(color: AppColors.textHint)),
        id: Text(
          c.idNumber.isNotEmpty ? c.idNumber : "-",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: cellStyle.copyWith(color: AppColors.textSecondary),
        ),
        name: Text(
          c.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: cellStyle.copyWith(fontWeight: FontWeight.w600),
        ),
        phone: Text(
          c.phone,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: cellStyle,
        ),
        address: Text(
          c.address?.isNotEmpty == true ? c.address! : "-",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: cellStyle,
        ),
        email: Text(
          c.email?.isNotEmpty == true ? c.email! : "-",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: cellStyle,
        ),
        saldo: Text(
          formatCurrency(c.saldo),
          textAlign: TextAlign.end,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: cellStyle.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        point: Text(
          formatThousands(c.point),
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
                case 'detail':
                  onViewDetail?.call();
                  break;
                case 'saved_time':
                  onViewSavedTime?.call();
                  break;
                case 'reset':
                  onResetPassword?.call();
                  break;
                case 'delete':
                  onDelete?.call();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'detail',
                child: _menuItem(
                  Icons.receipt_long_rounded,
                  "Detail Member",
                ),
              ),
              PopupMenuItem(
                value: 'saved_time',
                child: _menuItem(
                  Icons.hourglass_bottom_rounded,
                  "Lihat Waktu Tersimpan",
                ),
              ),
              PopupMenuItem(
                value: 'reset',
                child: _menuItem(Icons.lock_reset_rounded, "Reset Password"),
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
    required Widget id,
    required Widget name,
    required Widget phone,
    required Widget address,
    required Widget email,
    required Widget saldo,
    required Widget point,
    required Widget aksi,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 28, child: no),
        const SizedBox(width: 10),
        SizedBox(width: 120, child: id),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: name),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: phone),
        const SizedBox(width: 10),
        Expanded(flex: 3, child: address),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: email),
        const SizedBox(width: 10),
        SizedBox(width: 110, child: saldo),
        const SizedBox(width: 10),
        SizedBox(width: 56, child: point),
        const SizedBox(width: 10),
        SizedBox(width: 48, child: aksi),
      ],
    );
  }
}
