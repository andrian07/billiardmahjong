import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/navigation/app_navigation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_user.dart';
import '../../models/customer.dart';
import '../../models/report.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_layout.dart';
import '../../shared/widgets/app_toast.dart';
import '../customer/data/customer_repository.dart';
import '../user/data/user_repository.dart';
import 'data/report_repository.dart';

/// Rekap transaksi billing meja — Report/billing_report, dengan filter
/// tanggal (wajib), member, dan kasir, serta export ke Excel/PDF.
class BillingReportPage extends StatefulWidget {
  const BillingReportPage({
    super.key,
    this.categoryType = "billiard",
    this.pageTitle = "Laporan Billiard",
    this.pageSubtitle = "Rekap transaksi meja billiard",
    this.menuKey = "laporan_billing",
  });

  /// 'billiard' / 'mahjong' - transaksi meja jenis mana yang dilaporkan.
  final String categoryType;
  final String pageTitle;
  final String pageSubtitle;
  final String menuKey;

  @override
  State<BillingReportPage> createState() => _BillingReportPageState();
}

class _BillingReportPageState extends State<BillingReportPage> {
  final _repository = ReportRepository();
  final _customerRepository = CustomerRepository();
  final _userRepository = UserRepository();

  late DateTime _dateFrom;
  late DateTime _dateTo;
  Customer? _selectedCustomer;
  AppUser? _selectedKasir;

  List<Customer> _customers = [];
  List<AppUser> _kasirs = [];

  bool _loading = true;
  String? _error;
  BillingReportResult? _result;

  bool _exportingExcel = false;
  bool _exportingPdf = false;

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _dateTo = today;
    _dateFrom = DateTime(today.year, today.month, 1);
    _loadFiltersAndReport();
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  Future<void> _loadFiltersAndReport() async {
    try {
      final customers = await _customerRepository.getCustomers(
        page: 1,
        perPage: 500,
      );
      final users = await _userRepository.getUsers(page: 1, perPage: 500);
      if (!mounted) return;
      setState(() {
        _customers = customers.customers;
        _kasirs = users.users;
      });
    } catch (_) {
      // Filter dropdowns are a convenience — if they fail to load the
      // report itself can still run unfiltered, so this fails silently.
    }
    await _runReport();
  }

  Future<void> _runReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _repository.getBillingReport(
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        customerId: _selectedCustomer?.id,
        paidBy: _selectedKasir?.id,
        categoryType: widget.categoryType,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } on ReportRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _pickDateFrom() async {
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: _dateTo,
      initialDate: _dateFrom,
    );
    if (result == null) return;
    setState(() => _dateFrom = _dateOnly(result));
  }

  Future<void> _pickDateTo() async {
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      firstDate: _dateFrom,
      lastDate: now,
      initialDate: _dateTo,
    );
    if (result == null) return;
    setState(() => _dateTo = _dateOnly(result));
  }

  Future<void> _export(String type) async {
    setState(() {
      if (type == "excel") {
        _exportingExcel = true;
      } else {
        _exportingPdf = true;
      }
    });

    try {
      final file = await _repository.exportBillingReport(
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        customerId: _selectedCustomer?.id,
        paidBy: _selectedKasir?.id,
        categoryType: widget.categoryType,
        type: type,
      );
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: "Simpan ${widget.pageTitle}",
        fileName: file.filename,
        bytes: file.bytes,
      );
      if (!mounted) return;
      if (savePath != null) {
        AppToast.success(context, "Laporan berhasil disimpan");
      }
    } on ReportRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } finally {
      if (mounted) {
        setState(() {
          if (type == "excel") {
            _exportingExcel = false;
          } else {
            _exportingPdf = false;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: widget.pageTitle,
      subtitle: widget.pageSubtitle,
      showSearch: false,
      activeMenuKey: widget.menuKey,
      onMenuSelect: (key) => navigateToMenu(context, key),
      onRefresh: _loadFiltersAndReport,
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
            child: _buildFilterBar(),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        _dateField(
          label: "Dari Tanggal",
          value: _dateFrom,
          onTap: _pickDateFrom,
        ),
        _dateField(label: "Sampai Tanggal", value: _dateTo, onTap: _pickDateTo),
        SizedBox(width: 220, child: _customerDropdown()),
        SizedBox(width: 200, child: _kasirDropdown()),
        SizedBox(
          height: 42,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _runReport,
            icon: const Icon(Icons.search_rounded, size: 18),
            label: const Text("Tampilkan"),
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
        SizedBox(
          height: 42,
          child: OutlinedButton.icon(
            onPressed: (_result == null || _exportingExcel || _exportingPdf)
                ? null
                : () => _export("excel"),
            icon: _exportingExcel
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.grid_on_rounded, size: 18),
            label: const Text("Excel"),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.success,
              side: BorderSide(color: AppColors.success.withValues(alpha: .4)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: OutlinedButton.icon(
            onPressed: (_result == null || _exportingExcel || _exportingPdf)
                ? null
                : () => _export("pdf"),
            icon: _exportingPdf
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_rounded, size: 18),
            label: const Text("PDF"),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: BorderSide(color: AppColors.danger.withValues(alpha: .4)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dateField({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: AppText.caption.copyWith(fontSize: 9)),
                Text(
                  formatDate(value),
                  style: AppText.caption.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerDropdown() {
    return DropdownButtonFormField<Customer?>(
      initialValue: _selectedCustomer,
      dropdownColor: AppColors.card,
      style: AppText.caption,
      isExpanded: true,
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: AppColors.textSecondary,
      ),
      decoration: _filterDecoration(
        hint: "Semua Member",
        icon: Icons.person_outline_rounded,
      ),
      items: [
        const DropdownMenuItem<Customer?>(
          value: null,
          child: Text("Semua Member"),
        ),
        for (final customer in _customers)
          DropdownMenuItem<Customer?>(
            value: customer,
            child: Text(customer.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) => setState(() => _selectedCustomer = value),
    );
  }

  Widget _kasirDropdown() {
    return DropdownButtonFormField<AppUser?>(
      initialValue: _selectedKasir,
      dropdownColor: AppColors.card,
      style: AppText.caption,
      isExpanded: true,
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: AppColors.textSecondary,
      ),
      decoration: _filterDecoration(
        hint: "Semua Kasir",
        icon: Icons.badge_outlined,
      ),
      items: [
        const DropdownMenuItem<AppUser?>(
          value: null,
          child: Text("Semua Kasir"),
        ),
        for (final kasir in _kasirs)
          DropdownMenuItem<AppUser?>(
            value: kasir,
            child: Text(kasir.username, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) => setState(() => _selectedKasir = value),
    );
  }

  InputDecoration _filterDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.caption,
      prefixIcon: Icon(icon, size: 18, color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.background,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildMessageState(
        icon: Icons.cloud_off_rounded,
        iconColor: AppColors.danger,
        message: _error!,
        action: OutlinedButton.icon(
          onPressed: _runReport,
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
      );
    }

    final result = _result;
    if (result == null || result.rows.isEmpty) {
      return _buildMessageState(
        icon: Icons.receipt_long_outlined,
        iconColor: AppColors.textHint,
        message: "Tidak ada transaksi billing pada rentang tanggal ini",
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: _BillingReportRowWidget.header(),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            itemCount: result.rows.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.divider),
            itemBuilder: (context, index) => _BillingReportRowWidget.data(
              no: index + 1,
              row: result.rows[index],
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.divider),
        Container(
          color: AppColors.background.withValues(alpha: .4),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: _buildSummary(result),
        ),
      ],
    );
  }

  Widget _buildSummary(BillingReportResult result) {
    final summary = result.summary;
    // Diskon promo Fix tidak dihitung sebagai diskon (lihat effectiveDiscount),
    // jadi total diskon di layar direkap ulang dari nilai efektif tiap baris.
    final totalDiscount = result.rows.fold<int>(
      0,
      (sum, row) => sum + row.effectiveDiscount,
    );
    return Row(
      children: [
        _summaryStat("Jumlah Nota", "${summary.invoiceCount}"),
        const SizedBox(width: 28),
        _summaryStat("Subtotal", formatCurrency(summary.totalSubTotal)),
        const SizedBox(width: 28),
        _summaryStat("Diskon", formatCurrency(totalDiscount)),
        const SizedBox(width: 28),
        _summaryStat("Pajak", formatCurrency(summary.totalTax)),
        const Spacer(),
        _summaryStat(
          "Total Tagihan",
          formatCurrency(summary.totalBill),
          emphasize: true,
        ),
      ],
    );
  }

  Widget _summaryStat(String label, String value, {bool emphasize = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppText.caption),
        const SizedBox(height: 2),
        Text(
          value,
          style: emphasize
              ? AppText.title.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                )
              : AppText.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildMessageState({
    required IconData icon,
    required Color iconColor,
    required String message,
    Widget? action,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: iconColor),
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
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    );
  }
}

class _BillingReportRowWidget extends StatelessWidget {
  final bool header;
  final int? no;
  final BillingReportRow? row;

  const _BillingReportRowWidget.header() : header = true, no = null, row = null;

  const _BillingReportRowWidget.data({required this.no, required this.row})
    : header = false;

  @override
  Widget build(BuildContext context) {
    if (header) {
      return _row(
        no: _headerText("No"),
        invoice: _headerText("No. Invoice"),
        tanggal: _headerText("Tanggal"),
        jam: _headerText("Jam"),
        member: _headerText("Member"),
        kasir: _headerText("Kasir"),
        payment: _headerText("Pembayaran"),
        promo: _headerText("Promo"),
        subTotal: _headerText("Subtotal", alignEnd: true),
        diskon: _headerText("Diskon", alignEnd: true),
        total: _headerText("Total", alignEnd: true),
        status: _headerText("Status", alignCenter: true),
        keterangan: _headerText("Keterangan"),
      );
    }

    final r = row!;
    final cellStyle = AppText.caption.copyWith(fontSize: 12.5);
    final isDone = r.status.toLowerCase() == "done";
    final statusColor = isDone ? AppColors.success : AppColors.danger;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: _row(
        no: Text("$no", style: cellStyle.copyWith(color: AppColors.textHint)),
        invoice: Text(
          r.invoiceNumber,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: cellStyle.copyWith(fontWeight: FontWeight.w600),
        ),
        tanggal: Text(formatDate(r.date), style: cellStyle),
        jam: Text("${r.startTime} - ${r.endTime}", style: cellStyle),
        member: Text(
          r.memberName ?? "-",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: cellStyle,
        ),
        kasir: Text(
          r.kasirName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: cellStyle,
        ),
        payment: Text(r.paymentName, style: cellStyle),
        promo: Text(
          _promoLabel(r),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: cellStyle.copyWith(
            color: r.promoName == null ? AppColors.textHint : AppColors.text,
          ),
        ),
        subTotal: Text(
          formatCurrency(r.subTotal),
          textAlign: TextAlign.end,
          style: cellStyle,
        ),
        diskon: Text(
          r.effectiveDiscount > 0
              ? "-${formatCurrency(r.effectiveDiscount)}"
              : "-",
          textAlign: TextAlign.end,
          style: cellStyle.copyWith(
            color: r.effectiveDiscount > 0
                ? AppColors.success
                : AppColors.textHint,
          ),
        ),
        total: Text(
          formatCurrency(r.totalBill),
          textAlign: TextAlign.end,
          style: cellStyle.copyWith(fontWeight: FontWeight.w700),
        ),
        status: Align(
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              r.status,
              style: AppText.caption.copyWith(
                fontSize: 10,
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        keterangan: Text(
          _keteranganLabel(r),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: cellStyle.copyWith(
            color: r.usedSavedTime ? AppColors.text : AppColors.textHint,
          ),
        ),
      ),
    );
  }

  /// Nama promo yang dipakai. Untuk promo Fix (paket harga+durasi tetap)
  /// nominal paket ikut ditulis di belakang nama — sejalan dengan export.
  static String _promoLabel(BillingReportRow r) {
    if (r.promoName == null) return "-";
    if (r.isFixPromo && r.promoValue > 0) {
      return "${r.promoName} (${formatCurrency(r.promoValue)})";
    }
    return r.promoName!;
  }

  /// Keterangan nota. Untuk nota yang dibayar pakai sisa waktu tersimpan,
  /// sebutkan nilai tagihan yang seharusnya — sejalan dengan export.
  static String _keteranganLabel(BillingReportRow r) {
    if (!r.usedSavedTime) return "-";
    final value = r.savedTimeValue;
    if (value == null) return "Bayar pakai sisa waktu";
    return "Bayar pakai sisa waktu (senilai ${formatCurrency(value)})";
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
        letterSpacing: .4,
        color: AppColors.textSecondary,
      ),
    );
  }

  static Widget _row({
    required Widget no,
    required Widget invoice,
    required Widget tanggal,
    required Widget jam,
    required Widget member,
    required Widget kasir,
    required Widget payment,
    required Widget promo,
    required Widget subTotal,
    required Widget diskon,
    required Widget total,
    required Widget status,
    required Widget keterangan,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 28, child: no),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: invoice),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: tanggal),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: jam),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: member),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: kasir),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: payment),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: promo),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: subTotal),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: diskon),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: total),
        const SizedBox(width: 10),
        SizedBox(width: 80, child: status),
        const SizedBox(width: 10),
        Expanded(flex: 3, child: keterangan),
      ],
    );
  }
}
