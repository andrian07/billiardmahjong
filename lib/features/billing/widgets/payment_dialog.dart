import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/customer.dart';
import '../../../models/payment_method.dart';
import '../../../models/pool_table.dart';
import '../../../models/promo.dart';
import '../../../services/session_storage.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../customer/data/customer_repository.dart';
import '../../payment/data/payment_method_repository.dart';
import '../../promo/data/promo_repository.dart';
import '../data/billing_repository.dart';
import '../data/member_approval_repository.dart';
import 'member_approval_wait_dialog.dart';

class PaymentResult {
  final String paymentMethod;
  final String? customerName;
  final String? promo;
  final int subtotal;
  final int discountAmount;
  final int total;

  const PaymentResult({
    required this.paymentMethod,
    this.customerName,
    this.promo,
    required this.subtotal,
    required this.discountAmount,
    required this.total,
  });
}

class PaymentDialog extends StatefulWidget {
  final PoolTable table;

  const PaymentDialog({super.key, required this.table});

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final _promoRepository = PromoRepository();
  final _billingRepository = BillingRepository();
  final _sessionStorage = SessionStorage();
  final _paymentMethodRepository = PaymentMethodRepository();
  final _customerRepository = CustomerRepository();

  late String? _customerName = widget.table.memberName;
  late int? _selectedCustomerId = widget.table.customerId;
  Promo? _selectedPromo;

  bool _loadingCustomers = true;
  String? _customerLoadError;
  List<Customer> _customers = [];

  bool _loadingPromos = true;
  String? _promoLoadError;
  List<Promo> _promos = [];

  /// Promo yang berlaku untuk kategori meja ini (promo tanpa batasan kategori
  /// berlaku semua). Promo yang sedang terpilih tetap disertakan supaya
  /// dropdown-nya tidak error walau kategorinya berbeda.
  List<Promo> get _promosForTable {
    final cat = widget.table.categoryMejaId;
    return _promos.where((p) {
      if (p.categoryIds.isEmpty || p.categoryIds.contains(cat)) return true;
      return _selectedPromo?.id == p.id;
    }).toList();
  }

  bool _loadingPaymentMethods = true;
  String? _paymentMethodLoadError;
  List<PaymentMethod> _paymentMethods = [];
  PaymentMethod? _selectedPaymentMethod;

  bool _calculating = false;
  String? _calculationError;
  PriceCalculation? _calculation;

  bool _submitting = false;
  String? _submitError;

  bool _checkingTimeSave = false;
  bool _canOfferSaveTime = false;
  bool? _saveTime;

  bool get _isTimerMode => widget.table.sessionType == SessionType.timer;

  /// "Simpan Sisa Waktu" hanya relevan kalau sesi Timer, fiturnya aktif, DAN
  /// ada member (saldo waktu disimpan per member) - tanpa member bagian ini
  /// tidak ditampilkan & tidak jadi syarat tombol konfirmasi.
  bool get _showSaveTime =>
      _isTimerMode && _canOfferSaveTime && _selectedCustomerId != null;

  /// Kalau tidak null, metode pembayaran dikunci ke nama ini (lowercase):
  ///  - "potong waktu": sesi dibuka dengan "pakai waktu tersimpan" (Rp0, sudah dipotong di awal).
  ///  - "potong saldo" : sesi dibuka dengan "Potong Saldo di awal" DAN tagihan aktual <= yang
  ///    dibayar di muka (selisih tinggal dikembalikan). Kalau tagihan > prepaid (overtime),
  ///    metode TIDAK dikunci - kasir pilih bebas untuk menagih kekurangannya.
  String? get _lockedPaymentMethodName {
    if (widget.table.usedSavedTime == true) return 'potong waktu';
    final calc = _calculation;
    if (widget.table.prepaidSaldo &&
        calc != null &&
        calc.totalTransaksi <= widget.table.saldoPrepaidAmount) {
      return 'potong saldo';
    }
    return null;
  }

  bool get _paymentLocked => _lockedPaymentMethodName != null;

  /// Metode yang ditampilkan di dropdown: semua, kecuali saat terkunci -> hanya yang terkunci.
  List<PaymentMethod> get _visiblePaymentMethods {
    final locked = _lockedPaymentMethodName;
    if (locked == null) return _paymentMethods;
    final only = _paymentMethods
        .where((m) => m.name.toLowerCase() == locked)
        .toList();
    return only.isNotEmpty ? only : _paymentMethods;
  }

  /// True once the table's planned end time has passed — at that point
  /// there's no time left to carry over, so the save-time choice is locked
  /// to "Tidak" instead of being offered.
  bool get _timerExpired {
    final endAt = widget.table.endAt;
    return _isTimerMode && endAt != null && !endAt.isAfter(DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _loadPromos();
    _loadPaymentMethods();
    if (_isTimerMode) {
      if (_timerExpired) _saveTime = false;
      _checkTimeSave();
    }
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _loadingCustomers = true;
      _customerLoadError = null;
    });

    try {
      final customers = await _customerRepository.getAllCustomers();
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _loadingCustomers = false;
      });
    } on CustomerRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _customerLoadError = e.message;
        _loadingCustomers = false;
      });
    }
  }

  Future<void> _checkTimeSave() async {
    setState(() => _checkingTimeSave = true);

    try {
      final canSave = await _billingRepository.checkTimeSave();
      if (!mounted) return;
      setState(() {
        _canOfferSaveTime = canSave;
        _checkingTimeSave = false;
      });
    } on BillingRepositoryException {
      if (!mounted) return;
      setState(() {
        _canOfferSaveTime = false;
        _checkingTimeSave = false;
      });
    }
  }

  Future<void> _loadPromos() async {
    setState(() {
      _loadingPromos = true;
      _promoLoadError = null;
    });

    try {
      final promos = await _promoRepository.getAllPromos();
      if (!mounted) return;
      setState(() {
        _promos = promos;
        _selectedPromo = _matchById(promos, widget.table.promoId);
        _loadingPromos = false;
      });
      _calculatePrice();
    } on PromoRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _promoLoadError = e.message;
        _loadingPromos = false;
      });
    }
  }

  Promo? _matchById(List<Promo> promos, int? id) {
    if (id == null) return null;
    for (final promo in promos) {
      if (promo.id == id) return promo;
    }
    return null;
  }

  Future<void> _loadPaymentMethods() async {
    setState(() {
      _loadingPaymentMethods = true;
      _paymentMethodLoadError = null;
    });

    try {
      final methods = await _paymentMethodRepository.getPaymentMethods();
      if (!mounted) return;
      setState(() {
        _paymentMethods = methods;
        // preselect: kalau metode terkunci (lihat _lockedPaymentMethodName), pilih itu;
        // selain itu metode pertama.
        _selectedPaymentMethod = _visiblePaymentMethods.isNotEmpty
            ? _visiblePaymentMethods.first
            : null;
        _loadingPaymentMethods = false;
      });
    } on PaymentMethodRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _paymentMethodLoadError = e.message;
        _loadingPaymentMethods = false;
      });
    }
  }

  Future<void> _calculatePrice() async {
    setState(() {
      _calculating = true;
      _calculationError = null;
    });

    try {
      final result = await _billingRepository.calculatePrice(
        tableId: widget.table.id,
        saveTime: _showSaveTime ? (_saveTime ?? false) : null,
      );
      if (!mounted) return;
      setState(() {
        _calculation = _applyPromo(result, _selectedPromo);
        _calculating = false;
        // metode terkunci baru bisa dievaluasi setelah tagihan diketahui (kasus
        // "Potong Saldo di awal") - paksa pilihan ke metode yang terkunci.
        final locked = _lockedPaymentMethodName;
        if (locked != null) {
          final m = _paymentMethods
              .where((p) => p.name.toLowerCase() == locked)
              .toList();
          if (m.isNotEmpty && _selectedPaymentMethod?.id != m.first.id) {
            _selectedPaymentMethod = m.first;
          }
        }
      });
    } on BillingRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _calculationError = e.message;
        _calculating = false;
      });
    }
  }

  /// Promos with an hour limit (Fix-type "package" promos, e.g. "Promo 2
  /// Jam") can't be applied once the table has actually been running longer
  /// than that — running *less* than the limit is fine (a 2-hour package
  /// picked after 1.5 hours of play is a normal case). Mirrors the backend
  /// guard in `Billing_model::calculate_price()`, which is what actually
  /// enforces this at payment time — this is just the immediate UI notice.
  void _selectPromo(Promo? promo) {
    if (promo != null && promo.hourGained != null) {
      final startAt = widget.table.startAt;
      final elapsedHours = startAt != null
          ? DateTime.now().difference(startAt).inSeconds / 3600
          : 0.0;
      if (elapsedHours > promo.hourGained!) {
        AppToast.error(
          context,
          "Promo \"${promo.name}\" hanya berlaku maksimal ${promo.hourGained} jam "
          "(waktu main sudah berjalan ${elapsedHours.toStringAsFixed(1)} jam).",
        );
        setState(() {}); // snap the dropdown back to the still-selected promo
        return;
      }
    }

    if (promo != null && promo.hasDayRestriction) {
      final today = DateTime.now().weekday; // 1=Senin..7=Minggu
      if (!promo.validDays!.contains(today)) {
        final days = promo.validDays!.map((d) => weekdayLabels[d]).join(", ");
        AppToast.error(context, "Promo \"${promo.name}\" hanya berlaku hari $days.");
        setState(() {});
        return;
      }
    }

    if (promo != null && promo.hasTimeWindow) {
      if (widget.table.sessionType != SessionType.timer) {
        AppToast.error(
          context,
          "Promo \"${promo.name}\" hanya berlaku untuk mode Timer.",
        );
        setState(() {});
        return;
      }

      final startAt = widget.table.startAt;
      final now = DateTime.now();
      final startHod = startAt != null
          ? startAt.hour + startAt.minute / 60
          : now.hour + now.minute / 60;
      // endHod dihitung sebagai startHod + waktu main yang sudah berjalan (bukan hour-of-day dari
      // "now" secara terpisah) - supaya sesi yang melewati tengah malam tidak "membungkus" ke jam
      // kecil dan lolos dari pengecekan batas atas jendela promo (sama seperti bug yang diperbaiki
      // di Billing_model::validate_promo_schedule() pada backend).
      final endHod = startAt != null
          ? startHod + now.difference(startAt).inSeconds / 3600
          : now.hour + now.minute / 60;
      // valid_time_start bisa lebih besar dari valid_time_end untuk jendela yang melewati tengah
      // malam (mis. 22 s/d 4) - digeser relatif ke validTimeStart lalu dibungkus modulo 24 jam,
      // sama persis dengan Billing_model::validate_promo_schedule() di backend.
      final windowLength = (promo.validTimeEnd! - promo.validTimeStart! + 24) % 24;
      final shiftedStart = (startHod - promo.validTimeStart! + 24) % 24;
      final shiftedEnd = shiftedStart + (endHod - startHod);
      if (shiftedStart > windowLength || shiftedEnd > windowLength) {
        AppToast.error(
          context,
          "Promo \"${promo.name}\" hanya berlaku antara jam "
          "${promo.validTimeStart}:00 - ${promo.validTimeEnd}:00.",
        );
        setState(() {});
        return;
      }
    }

    setState(() {
      _selectedPromo = promo;

      final base = _calculation;
      if (base != null) {
        _calculation = _applyPromo(base, promo);
      }
    });
  }

  /// Percentage promos discount a cut of the subtotal as usual. Fixed
  /// promos work differently — the promo's value *is* the total the
  /// customer pays, so totalTransaksi is set to it directly rather than
  /// being subtracted from the subtotal; totalPromo is then back-derived
  /// just so the "Diskon Promo" line still adds up.
  PriceCalculation _applyPromo(PriceCalculation base, Promo? promo) {
    if (promo == null) {
      return PriceCalculation(
        totalBilling: base.totalBilling,
        totalPromo: 0,
        totalTax: base.totalTax,
        totalPembulatan: base.totalPembulatan,
        totalTransaksi:
            base.totalBilling + base.totalTax + base.totalPembulatan,
      );
    }

    final payableBeforePromo =
        base.totalBilling + base.totalTax + base.totalPembulatan;

    if (promo.type == PromoType.fixed) {
      // The fixed value *is* the total, full stop — not capped to the
      // originally calculated bill, otherwise a fixed price higher than
      // the current bill would silently get clamped back down.
      final totalTransaksi = promo.value < 0 ? 0 : promo.value;
      return PriceCalculation(
        totalBilling: base.totalBilling,
        totalPromo: payableBeforePromo - totalTransaksi,
        totalTax: base.totalTax,
        totalPembulatan: base.totalPembulatan,
        totalTransaksi: totalTransaksi,
      );
    }

    final totalPromo = (base.totalBilling * promo.value / 100).round().clamp(
      0,
      base.totalBilling,
    );
    return PriceCalculation(
      totalBilling: base.totalBilling,
      totalPromo: totalPromo,
      totalTax: base.totalTax,
      totalPembulatan: base.totalPembulatan,
      totalTransaksi:
          base.totalBilling - totalPromo + base.totalTax + base.totalPembulatan,
    );
  }

  Future<void> _submit() async {
    final calculation = _calculation;
    final startAt = widget.table.startAt;
    final paymentMethod = _selectedPaymentMethod;
    if (calculation == null || startAt == null || paymentMethod == null) {
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final session = await _sessionStorage.getSession();
      final createdBy = session?['username']?.toString() ?? "";
      final paidBy = int.tryParse(session?['id']?.toString() ?? "") ?? 0;
      final now = DateTime.now();
      final endAt = widget.table.endAt;

      // ref idempoten untuk konfirmasi PIN member (Potong Saldo + member). Sama
      // dipakai pada percobaan pertama & percobaan ulang setelah disetujui.
      final approvalRef = generateApprovalRef();

      Future<void> pay() => _billingRepository.submitPayment(
        tableId: widget.table.id,
        mode: widget.table.sessionType,
        startTime: startAt,
        endTime: now,
        duration: now.isAfter(startAt)
            ? now.difference(startAt)
            : Duration.zero,
        subTotal: calculation.totalBilling,
        tax: calculation.totalTax,
        totalBill: calculation.totalTransaksi,
        createdBy: createdBy,
        paidBy: paidBy,
        paymentId: paymentMethod.id,
        customerId: _selectedCustomerId,
        promoId: _selectedPromo?.id,
        saveTime: _showSaveTime ? _saveTime : null,
        remainingTime: _isTimerMode && endAt != null
            ? (endAt.isAfter(now) ? endAt.difference(now) : Duration.zero)
            : null,
        usedSavedTime: widget.table.usedSavedTime,
        memberApprovalRef: approvalRef,
      );

      try {
        await pay();
      } on MemberApprovalRequiredException catch (e) {
        if (!mounted) return;
        final outcome = await showDialog<MemberApprovalOutcome>(
          context: context,
          barrierDismissible: false,
          builder: (_) => MemberApprovalWaitDialog(
            ref: e.ref,
            amount: e.amount == 0 ? calculation.totalTransaksi : e.amount,
            expiresAt: e.expiresAt,
          ),
        );
        if (outcome != MemberApprovalOutcome.approved) {
          if (!mounted) return;
          setState(() {
            _submitting = false;
            _submitError = _approvalMessage(outcome);
          });
          return;
        }
        await pay(); // sudah disetujui -> lanjut potong saldo & simpan
      }

      if (!mounted) return;
      Navigator.of(context).pop(
        PaymentResult(
          paymentMethod: paymentMethod.name,
          customerName: _customerName,
          promo: _selectedPromo?.name,
          subtotal: calculation.totalBilling,
          discountAmount: calculation.totalPromo,
          total: calculation.totalTransaksi,
        ),
      );
    } on BillingRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = e.message;
      });
    }
  }

  String _approvalMessage(MemberApprovalOutcome? o) {
    switch (o) {
      case MemberApprovalOutcome.rejected:
        return "Pembayaran ditolak oleh member.";
      case MemberApprovalOutcome.expired:
        return "Member tidak merespon (waktu habis). Coba lagi atau ganti metode bayar.";
      case MemberApprovalOutcome.cancelled:
        return "Konfirmasi dibatalkan.";
      default:
        return "Gagal mendapatkan konfirmasi member.";
    }
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
          maxWidth: 860,
          maxHeight: screenSize.height * 0.9,
        ),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.radiusXL),
            border: Border.all(color: AppColors.border),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(widget.table),
                const SizedBox(height: 20),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 24),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 6, child: _buildFormColumn()),
                      const SizedBox(width: 28),
                      const VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: AppColors.divider,
                      ),
                      const SizedBox(width: 28),
                      Expanded(flex: 5, child: _buildSummaryColumn()),
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

  Widget _buildFormColumn() {
    final table = widget.table;
    final isReguler = table.sessionType == SessionType.reguler;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label("Detail Transaksi"),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _detailTile(
                      Icons.table_bar_rounded,
                      "Meja",
                      table.name,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _detailTile(
                      Icons.sports_esports_rounded,
                      "Mode",
                      _sessionTypeLabel(table),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _detailTile(
                      Icons.login_rounded,
                      "Jam Main",
                      table.startTime ?? "-",
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _detailTile(
                      Icons.logout_rounded,
                      "Jam Selesai",
                      isReguler ? "-" : (table.endTime ?? "-"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        _label("Member"),
        const SizedBox(height: 8),
        _loadingCustomers
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : _customerLoadError != null
            ? _buildInlineError(_customerLoadError!, onRetry: _loadCustomers)
            : Autocomplete<Customer>(
                initialValue: TextEditingValue(text: _customerName ?? ""),
                displayStringForOption: (customer) => customer.name,
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) return _customers;
                  return _customers.where(
                    (customer) => customer.name.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    ),
                  );
                },
                onSelected: (customer) => setState(() {
                  _customerName = customer.name;
                  _selectedCustomerId = customer.id;
                }),
                fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: AppText.body,
                    decoration: _inputDecoration(
                      hint: "Cari nama member",
                      prefixIcon: Icons.person_outline_rounded,
                    ),
                    onChanged: (_) => setState(() {
                      _customerName = null;
                      _selectedCustomerId = null;
                    }),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return _buildOptionsCard<Customer>(
                    options: options,
                    onSelected: onSelected,
                    labelOf: (customer) => customer.name,
                  );
                },
              ),

        const SizedBox(height: 20),
        _label("Promo / Diskon"),
        const SizedBox(height: 8),
        _loadingPromos
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : _promoLoadError != null
            ? _buildInlineError(_promoLoadError!, onRetry: _loadPromos)
            : DropdownButtonFormField<Promo?>(
                key: ValueKey(_selectedPromo?.id ?? 0),
                initialValue: _selectedPromo,
                dropdownColor: AppColors.card,
                style: AppText.body,
                isExpanded: true,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textSecondary,
                ),
                decoration: _inputDecoration(
                  hint: "Tanpa promo",
                  prefixIcon: Icons.local_offer_outlined,
                ),
                items: [
                  const DropdownMenuItem<Promo?>(
                    value: null,
                    child: Text("Tanpa Promo"),
                  ),
                  for (final promo in _promosForTable)
                    DropdownMenuItem<Promo?>(
                      value: promo,
                      child: Text(promo.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _selectPromo,
              ),

        const SizedBox(height: 20),
        _label("Metode Pembayaran"),
        const SizedBox(height: 8),
        _loadingPaymentMethods
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : _paymentMethodLoadError != null
            ? _buildInlineError(
                _paymentMethodLoadError!,
                onRetry: _loadPaymentMethods,
              )
            : DropdownButtonFormField<PaymentMethod?>(
                initialValue: _selectedPaymentMethod,
                dropdownColor: AppColors.card,
                style: AppText.body,
                isExpanded: true,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textSecondary,
                ),
                decoration: _inputDecoration(
                  prefixIcon: Icons.account_balance_wallet_outlined,
                ),
                items: [
                  for (final method in _visiblePaymentMethods)
                    DropdownMenuItem(
                      value: method,
                      child: Text(method.name),
                    ),
                ],
                // terkunci untuk sesi "pakai waktu tersimpan" (Potong Waktu) atau
                // "Potong Saldo di awal" bila tagihan <= yang dibayar di muka.
                onChanged: _paymentLocked
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _selectedPaymentMethod = value);
                      },
              ),
      ],
    );
  }

  Widget _buildSummaryColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _label("Rincian Tagihan"),
            const SizedBox(height: 10),
            _buildBillingSummary(),
            if (widget.table.prepaidSaldo) ...[
              const SizedBox(height: 12),
              _buildPrepaidNote(),
            ],
            if (_isTimerMode && _selectedCustomerId != null && _checkingTimeSave) ...[
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ] else if (_showSaveTime) ...[
              const SizedBox(height: 20),
              _label("Simpan Sisa Waktu"),
              const SizedBox(height: 10),
              _buildSaveTimeSection(),
            ],
          ],
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_submitError != null) ...[
              const SizedBox(height: 20),
              _buildInlineError(_submitError!, onRetry: _submit),
            ],
            const SizedBox(height: 20),
            _buildConfirmButton(),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                  ),
                ),
                child: const Text("BATAL"),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _detailTile(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(AppSizes.radiusSmall),
          ),
          child: Icon(icon, size: 15, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: AppText.caption),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPrepaidNote() {
    final prepaid = widget.table.saldoPrepaidAmount;
    final bill = _calculation?.totalTransaksi;
    final shortfall = (bill != null && bill > prepaid) ? bill - prepaid : 0;
    final refund = (bill != null && bill < prepaid) ? prepaid - bill : 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: AppColors.info.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, size: 15, color: AppColors.info),
              const SizedBox(width: 6),
              Text(
                "Sudah dibayar di muka dari saldo: ${formatCurrency(prepaid)}",
                style: AppText.caption.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (shortfall > 0) ...[
            const SizedBox(height: 4),
            Text(
              "Kekurangan ${formatCurrency(shortfall)} — pilih metode bayar untuk selisihnya.",
              style: AppText.caption.copyWith(color: AppColors.danger),
            ),
          ] else if (refund > 0) ...[
            const SizedBox(height: 4),
            Text(
              "Selisih ${formatCurrency(refund)} akan dikembalikan ke saldo member.",
              style: AppText.caption.copyWith(color: AppColors.success),
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              "Tagihan pas dengan yang dibayar di muka — tidak ada potongan lagi.",
              style: AppText.caption,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBillingSummary() {
    if (_calculating) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_calculationError != null) {
      return _buildInlineError(_calculationError!, onRetry: _calculatePrice);
    }

    final calculation = _calculation;
    if (calculation == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _kv(
            Icons.receipt_long_outlined,
            "Subtotal",
            formatCurrency(calculation.totalBilling),
          ),
          if (calculation.totalPromo > 0) ...[
            const SizedBox(height: 10),
            _kv(
              Icons.local_offer_outlined,
              "Diskon Promo",
              "-${formatCurrency(calculation.totalPromo)}",
              valueColor: AppColors.success,
            ),
          ],
          if (calculation.totalTax > 0) ...[
            const SizedBox(height: 10),
            _kv(
              Icons.percent_rounded,
              "Pajak",
              formatCurrency(calculation.totalTax),
            ),
          ],
          if (calculation.totalPembulatan != 0) ...[
            const SizedBox(height: 10),
            _kv(
              Icons.tune_rounded,
              "Pembulatan",
              formatCurrency(calculation.totalPembulatan),
            ),
          ],
          const SizedBox(height: 10),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Total Bayar",
                style: AppText.body.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                formatCurrency(calculation.totalTransaksi),
                style: AppText.title.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSaveTimeSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv(
            Icons.hourglass_bottom_rounded,
            "Sisa Waktu",
            widget.table.timerText ?? formatDuration(Duration.zero),
          ),
          const SizedBox(height: 12),
          Text("Simpan waktu untuk sesi berikutnya?", style: AppText.caption),
          const SizedBox(height: 8),
          if (_timerExpired)
            Row(
              children: [
                Icon(
                  Icons.block_rounded,
                  size: 16,
                  color: AppColors.textHint,
                ),
                const SizedBox(width: 8),
                Text(
                  "Waktu sudah habis — otomatis Tidak",
                  style: AppText.caption,
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _saveTimeOption(label: "Ya", value: true),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _saveTimeOption(label: "Tidak", value: false),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _saveTimeOption({required String label, required bool value}) {
    final selected = _saveTime == value;

    return InkWell(
      onTap: () {
        if (_saveTime == value) return;
        setState(() => _saveTime = value);
        _calculatePrice();
      },
      borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: .15)
              : AppColors.card,
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppText.body.copyWith(
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
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
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
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

  Widget _buildConfirmButton() {
    final enabled =
        !_calculating &&
        !_submitting &&
        _calculation != null &&
        _selectedPaymentMethod != null &&
        (!_showSaveTime || _saveTime != null);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: enabled
              ? const [AppColors.success, Color(0xFF15803D)]
              : [AppColors.textHint, AppColors.textHint],
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: .35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        child: InkWell(
          onTap: enabled ? _submit : null,
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_submitting)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                const SizedBox(width: 10),
                Text(
                  _submitting ? "MEMPROSES..." : "KONFIRMASI PEMBAYARAN",
                  style: AppText.button.copyWith(letterSpacing: .4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(PoolTable table) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          ),
          child: const Icon(
            Icons.payments_outlined,
            color: AppColors.warning,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Proses Pembayaran",
                style: AppText.title.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                "Konfirmasi transaksi ${table.name}",
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

  Widget _buildOptionsCard<T extends Object>({
    required Iterable<T> options,
    required void Function(T) onSelected,
    required String Function(T) labelOf,
  }) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        color: AppColors.card,
        elevation: 8,
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        child: Container(
          width: 372,
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
            border: Border.all(color: AppColors.border),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options.elementAt(index);
              return InkWell(
                onTap: () => onSelected(option),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Text(labelOf(option), style: AppText.body),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _sessionTypeLabel(PoolTable table) {
    switch (table.sessionType) {
      case SessionType.timer:
        return "Timer";
      case SessionType.reguler:
        return "Reguler";
      case null:
        return "-";
    }
  }

  Widget _label(String text) {
    return Text(
      text,
      style: AppText.bodySecondary.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _kv(IconData icon, String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: AppColors.textHint),
            const SizedBox(width: 8),
            Text(label, style: AppText.bodySecondary),
          ],
        ),
        Text(
          value,
          style: AppText.body.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
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
    );
  }
}
