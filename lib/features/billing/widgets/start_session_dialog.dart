import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/session_catalog.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/customer.dart';
import '../../../models/pool_table.dart';
import '../../../models/promo.dart';
import '../../../models/saved_customer_time.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../customer/data/customer_repository.dart';
import '../../promo/data/promo_repository.dart';
import '../data/billing_repository.dart';
import 'member_time_history_dialog.dart';

class StartSessionResult {
  final SessionType sessionType;
  final int? customerId;
  final String? memberName;
  final int? promoId;
  final String? promo;
  final Duration? duration;
  final bool? useSavedTime;

  /// Timer + member: potong saldo customer di muka (harga durasi penuh) saat buka meja.
  final bool prepaidSaldo;

  const StartSessionResult({
    required this.sessionType,
    this.customerId,
    this.memberName,
    this.promoId,
    this.promo,
    this.duration,
    this.useSavedTime,
    this.prepaidSaldo = false,
  });
}

class StartSessionDialog extends StatefulWidget {
  final PoolTable table;

  const StartSessionDialog({super.key, required this.table});

  @override
  State<StartSessionDialog> createState() => _StartSessionDialogState();
}

class _StartSessionDialogState extends State<StartSessionDialog> {
  final _customerRepository = CustomerRepository();
  final _promoRepository = PromoRepository();
  final _billingRepository = BillingRepository();

  SessionType _sessionType = SessionType.reguler;
  Customer? _selectedCustomer;
  Promo? _selectedPromo;
  int _durationHours = 0;
  int _durationMinutes = 0;
  String? _durationError;

  bool _checkingSavedTime = false;
  SavedCustomerTime? _savedTime;
  bool? _useSavedTime;
  bool? _habiskanTimer;

  /// Timer + member + tidak pakai waktu tersimpan: pilihan "Potong saldo di awal?".
  bool _prepaidSaldo = false;
  bool get _canOfferPrepaidSaldo =>
      _sessionType == SessionType.timer &&
      _selectedCustomer != null &&
      _useSavedTime != true;

  late final _hourController = TextEditingController(text: "$_durationHours");
  late final _minuteController = TextEditingController(
    text: "$_durationMinutes",
  );

  bool _loading = true;
  String? _loadError;
  List<Customer> _customers = [];
  List<Promo> _promos = [];

  /// Hanya promo yang berlaku untuk kategori meja ini (promo tanpa batasan
  /// kategori berlaku untuk semua) - biar tidak salah pilih.
  List<Promo> get _promosForTable {
    final cat = widget.table.categoryMejaId;
    return _promos
        .where((p) => p.categoryIds.isEmpty || p.categoryIds.contains(cat))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final customerResult = await _customerRepository.getCustomers(
        page: 1,
        perPage: 1000,
      );
      final promoResult = await _promoRepository.getPromos(
        page: 1,
        perPage: 1000,
      );
      if (!mounted) return;
      setState(() {
        _customers = customerResult.customers;
        _promos = promoResult.promos;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = "Gagal memuat data member/promo.";
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  static const _minDuration = Duration(minutes: 3);

  /// True when the selected promo is a fixed-hour promo — picking one
  /// auto-fills and locks the duration fields to that many hours.
  bool get _promoLocksDuration =>
      _selectedPromo?.type == PromoType.fixed &&
      _selectedPromo?.hourGained != null;

  /// Duration fields are only free to edit when the customer isn't using
  /// saved time, or chose to use just part of it ("Sebagian") — picking
  /// "Habiskan" locks the fields to the full saved balance. A fixed-hour
  /// promo locks them too, regardless of the saved-time state.
  bool get _durationFieldsEnabled =>
      (_useSavedTime != true || _habiskanTimer == false) &&
      !_promoLocksDuration;

  /// True when the selected promo can only be used with mode Timer: either it
  /// has a valid-hour window (see Billing_model::validate_promo_schedule on
  /// the backend), or it's a fixed price+duration package (type Fix) - a
  /// Reguler session has no fixed/known end time up front, so it can't be
  /// matched against a promo window or billed at a flat package price.
  bool get _promoRequiresTimer =>
      (_selectedPromo?.hasTimeWindow ?? false) ||
      _selectedPromo?.type == PromoType.fixed;

  void _selectPromo(Promo? promo) {
    if (promo != null && promo.hasDayRestriction) {
      final today = DateTime.now().weekday; // 1=Senin..7=Minggu, matches validDays
      if (!promo.validDays!.contains(today)) {
        final days = promo.validDays!.map((d) => weekdayLabels[d]).join(", ");
        AppToast.error(
          context,
          "Promo \"${promo.name}\" hanya berlaku hari $days.",
        );
        return;
      }
    }

    final lockedHours = promo?.type == PromoType.fixed
        ? promo?.hourGained
        : null;

    setState(() {
      final wasLocked = _promoLocksDuration;
      _selectedPromo = promo;

      if (promo != null && promo.hasTimeWindow) {
        _sessionType = SessionType.timer;
      }

      if (lockedHours != null) {
        _sessionType = SessionType.timer;
        _durationHours = lockedHours;
        _durationMinutes = 0;
        _durationError = null;
        _hourController.text = "$_durationHours";
        _minuteController.text = "$_durationMinutes";
      } else if (wasLocked) {
        _durationHours = 0;
        _durationMinutes = 0;
        _hourController.text = "0";
        _minuteController.text = "0";
      }
    });
  }

  /// True when the manually-entered duration (only reachable via
  /// "Sebagian") is more than the customer's saved time balance.
  bool get _exceedsSavedTime {
    final savedTime = _savedTime;
    if (savedTime == null || _useSavedTime != true || _habiskanTimer != false) {
      return false;
    }
    final duration = Duration(hours: _durationHours, minutes: _durationMinutes);
    return duration > savedTime.timeRemaining;
  }

  String get _savedTimeErrorText =>
      "Durasi tidak boleh melebihi sisa waktu tersimpan "
      "(${formatDuration(_savedTime!.timeRemaining)})";

  Future<void> _selectCustomer(Customer? customer) async {
    setState(() {
      _selectedCustomer = customer;
      _savedTime = null;
      _useSavedTime = null;
      _habiskanTimer = null;
      _prepaidSaldo = false;
      _checkingSavedTime = customer != null;
    });

    if (customer == null) return;

    final savedTime = await _billingRepository.getSavedCustomerTime(
      customerId: customer.id,
      tableId: widget.table.id,
    );
    if (!mounted || _selectedCustomer?.id != customer.id) return;

    setState(() {
      _savedTime = savedTime != null && savedTime.hasBalance ? savedTime : null;
      _checkingSavedTime = false;
    });
  }

  void _setUseSavedTime(bool value) {
    setState(() {
      _useSavedTime = value;
      _habiskanTimer = null;
      _durationError = null;
      if (value) {
        _sessionType = SessionType.timer;
        _prepaidSaldo = false; // saling eksklusif dgn "pakai waktu tersimpan"
      }
      _durationHours = 0;
      _durationMinutes = 0;
      _hourController.text = "0";
      _minuteController.text = "0";
    });
  }

  void _setHabiskanTimer(bool value) {
    final savedTime = _savedTime;
    setState(() {
      _habiskanTimer = value;
      _durationError = null;
      if (savedTime != null) {
        _durationHours = savedTime.timeRemaining.inHours;
        _durationMinutes = savedTime.timeRemaining.inMinutes % 60;
        _hourController.text = "$_durationHours";
        _minuteController.text = "$_durationMinutes";
      }
    });
  }

  void _submit() {
    final isTimer = _sessionType == SessionType.timer;
    final usingSavedTime =
        isTimer && _useSavedTime == true && _savedTime != null;
    final duration = Duration(
      hours: _durationHours,
      minutes: _durationMinutes,
    );

    if (usingSavedTime && _habiskanTimer == null) {
      setState(
        () => _durationError = "Pilih habiskan sisa waktu atau sebagian",
      );
      return;
    }

    if (_exceedsSavedTime) {
      setState(() => _durationError = _savedTimeErrorText);
      return;
    }

    final skipMinDuration = usingSavedTime && _habiskanTimer == true;
    if (isTimer && !skipMinDuration && duration < _minDuration) {
      setState(
        () => _durationError =
            "Durasi sesi minimal ${_minDuration.inMinutes} menit",
      );
      return;
    }

    final promo = _selectedPromo;
    if (isTimer && promo != null && promo.hasTimeWindow) {
      final now = DateTime.now();
      final startHod = now.hour + now.minute / 60;
      final elapsedHours = duration.inMinutes / 60;
      // valid_time_start bisa lebih besar dari valid_time_end untuk jendela yang melewati
      // tengah malam (mis. 22 s/d 4) - digeser relatif ke validTimeStart lalu dibungkus modulo
      // 24 jam supaya jendela normal & lintas-tengah-malam bisa dicek dengan rumus yang sama.
      // Sama persis dengan Billing_model::validate_promo_schedule() di backend.
      final windowLength = (promo.validTimeEnd! - promo.validTimeStart! + 24) % 24;
      final shiftedStart = (startHod - promo.validTimeStart! + 24) % 24;
      final shiftedEnd = shiftedStart + elapsedHours;

      if (shiftedStart > windowLength) {
        setState(
          () => _durationError =
              "Promo ini hanya berlaku antara jam ${promo.validTimeStart}:00 - "
              "${promo.validTimeEnd}:00",
        );
        return;
      }
      if (shiftedEnd > windowLength) {
        setState(
          () => _durationError =
              "Durasi ini membuat sesi selesai lewat dari jam "
              "${promo.validTimeEnd}:00 - batas berlaku promo ini",
        );
        return;
      }
    }

    Navigator.of(context).pop(
      StartSessionResult(
        sessionType: _sessionType,
        customerId: _selectedCustomer?.id,
        memberName: _selectedCustomer?.name,
        promoId: _selectedPromo?.id,
        promo: _selectedPromo?.name,
        duration: isTimer ? duration : null,
        useSavedTime: _savedTime != null ? (_useSavedTime ?? false) : null,
        prepaidSaldo: _canOfferPrepaidSaldo && _prepaidSaldo,
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
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.radiusXL),
          border: Border.all(color: AppColors.border),
        ),
        child: _loading
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            : _loadError != null
            ? _buildLoadError()
            : _buildForm(),
      ),
    );
  }

  Widget _buildLoadError() {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 30,
              color: AppColors.danger,
            ),
            const SizedBox(height: 12),
            Text(
              _loadError!,
              style: AppText.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadOptions,
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
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 22),

          _label("Mode"),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _typeOption(
                  SessionType.reguler,
                  "Reguler",
                  "Bayar per jam",
                  Icons.schedule_rounded,
                  enabled: !_promoRequiresTimer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _typeOption(
                  SessionType.timer,
                  "Timer",
                  "Sesi dengan durasi",
                  Icons.timer_rounded,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          _label("Nama Member (Opsional)"),
          const SizedBox(height: 8),
          Autocomplete<Customer>(
            displayStringForOption: (customer) => customer.name,
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) return _customers;
              final query = textEditingValue.text.toLowerCase();
              return _customers.where(
                (customer) =>
                    customer.name.toLowerCase().contains(query) ||
                    customer.phone.toLowerCase().contains(query),
              );
            },
            onSelected: (customer) => _selectCustomer(customer),
            fieldViewBuilder: (context, controller, focusNode, onSubmit) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: AppText.body,
                decoration: _inputDecoration(
                  hint: "Cari nama / no. HP member",
                  prefixIcon: Icons.person_outline_rounded,
                ),
                onChanged: (_) => _selectCustomer(null),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return _buildOptionsCard<Customer>(
                context,
                options: options,
                onSelected: onSelected,
                labelOf: (customer) => customer.phone.trim().isEmpty
                    ? customer.name
                    : "${customer.name} (${customer.phone})",
              );
            },
          ),

          if (_checkingSavedTime) ...[
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ] else if (_savedTime != null) ...[
            const SizedBox(height: 14),
            _buildSavedTimeSection(_savedTime!),
          ],

          if (_canOfferPrepaidSaldo) ...[
            const SizedBox(height: 20),
            _label("Potong Saldo"),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _toggleOption(
                    label: "Ya",
                    selected: _prepaidSaldo,
                    onTap: () => setState(() => _prepaidSaldo = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _toggleOption(
                    label: "Tidak",
                    selected: !_prepaidSaldo,
                    onTap: () => setState(() => _prepaidSaldo = false),
                  ),
                ),
              ],
            ),
          ],

          if (_sessionType == SessionType.timer) ...[
            const SizedBox(height: 20),
            _label("Durasi Sesi"),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _durationField(
                    controller: _hourController,
                    options: hourOptions,
                    suffix: "jam",
                    enabled: _durationFieldsEnabled,
                    onChanged: (value) => setState(() {
                      _durationHours = value;
                      _durationError = _exceedsSavedTime
                          ? _savedTimeErrorText
                          : null;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _durationField(
                    controller: _minuteController,
                    options: minuteOptions,
                    suffix: "menit",
                    enabled: _durationFieldsEnabled,
                    onChanged: (value) => setState(() {
                      _durationMinutes = value;
                      _durationError = _exceedsSavedTime
                          ? _savedTimeErrorText
                          : null;
                    }),
                  ),
                ),
              ],
            ),
            if (_durationError != null) ...[
              const SizedBox(height: 6),
              Text(
                _durationError!,
                style: AppText.caption.copyWith(color: AppColors.danger),
              ),
            ],
          ],

          const SizedBox(height: 20),
          _label("Promo (Opsional)"),
          const SizedBox(height: 8),
          DropdownButtonFormField<Promo?>(
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
          if (_promoLocksDuration) ...[
            const SizedBox(height: 8),
            Text(
              "Durasi timer otomatis mengikuti promo ini "
              "(${_selectedPromo!.hourGained} jam) dan tidak bisa diubah.",
              style: AppText.caption,
            ),
          ],
          if (_promoRequiresTimer) ...[
            const SizedBox(height: 8),
            Text(
              "Promo ini hanya berlaku untuk mode Timer, dan sesi harus "
              "selesai antara jam ${_selectedPromo!.validTimeStart}:00 - "
              "${_selectedPromo!.validTimeEnd}:00.",
              style: AppText.caption,
            ),
          ],

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
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text("MULAI SESI"),
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
            Icons.sports_esports_rounded,
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
                "Mulai Sesi",
                style: AppText.title.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                "Lengkapi detail untuk memulai permainan",
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

  Widget _typeOption(
    SessionType type,
    String label,
    String subtitle,
    IconData icon, {
    bool enabled = true,
  }) {
    final active = _sessionType == type;
    final effectiveColor = !enabled
        ? AppColors.textHint
        : (active ? AppColors.primary : AppColors.textSecondary);

    return InkWell(
      onTap: enabled
          ? () => setState(() {
              _sessionType = type;
              if (type == SessionType.reguler) {
                _prepaidSaldo = false; // hanya untuk Timer
              }
              if (type == SessionType.reguler && _useSavedTime != null) {
                _useSavedTime = null;
                _habiskanTimer = null;
                _durationHours = 0;
                _durationMinutes = 0;
                _hourController.text = "0";
                _minuteController.text = "0";
              }
            })
          : null,
      borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active && enabled
              ? AppColors.primary.withValues(alpha: .15)
              : AppColors.background,
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          border: Border.all(
            color: active && enabled ? AppColors.primary : AppColors.border,
            width: active && enabled ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: effectiveColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppText.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: effectiveColor,
                    ),
                  ),
                  Text(subtitle, style: AppText.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _durationField({
    required TextEditingController controller,
    required List<int> options,
    required String suffix,
    required ValueChanged<int> onChanged,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: AppText.body,
      decoration: _inputDecoration().copyWith(
        suffixText: suffix,
        suffixStyle: AppText.caption,
        suffixIcon: PopupMenuButton<int>(
          enabled: enabled,
          tooltip: "",
          color: AppColors.card,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: enabled ? AppColors.textSecondary : AppColors.textHint,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          ),
          itemBuilder: (context) => [
            for (final option in options)
              PopupMenuItem(value: option, child: Text("$option $suffix")),
          ],
          onSelected: (selected) {
            controller.text = "$selected";
            onChanged(selected);
          },
        ),
      ),
      onChanged: (text) => onChanged(int.tryParse(text) ?? 0),
    );
  }

  Widget _buildSavedTimeSection(SavedCustomerTime savedTime) {
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
          Row(
            children: [
              Icon(
                Icons.hourglass_bottom_rounded,
                size: 16,
                color: AppColors.textHint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "${savedTime.customerName} punya sisa waktu "
                  "${formatDuration(savedTime.timeRemaining)} "
                  "di kategori ${savedTime.categoryMejaName}",
                  style: AppText.caption,
                ),
              ),
            ],
          ),
          if (_selectedCustomer != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showMemberTimeHistoryDialog(
                  context,
                  customerId: _selectedCustomer!.id,
                  customerName: _selectedCustomer!.name,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.history_rounded, size: 15),
                label: Text(
                  "Lihat riwayat waktu",
                  style: AppText.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text("Pakai waktu tersisa?", style: AppText.caption),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _toggleOption(
                  label: "Ya",
                  selected: _useSavedTime == true,
                  onTap: () => _setUseSavedTime(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _toggleOption(
                  label: "Tidak",
                  selected: _useSavedTime == false,
                  onTap: () => _setUseSavedTime(false),
                ),
              ),
            ],
          ),
          if (_useSavedTime == true) ...[
            const SizedBox(height: 12),
            Text("Habiskan seluruh sisa waktu?", style: AppText.caption),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _toggleOption(
                    label: "Habiskan",
                    selected: _habiskanTimer == true,
                    onTap: () => _setHabiskanTimer(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _toggleOption(
                    label: "Sebagian",
                    selected: _habiskanTimer == false,
                    onTap: () => _setHabiskanTimer(false),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _toggleOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
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

  Widget _buildOptionsCard<T extends Object>(
    BuildContext context, {
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

  Widget _label(String text) {
    return Text(
      text,
      style: AppText.bodySecondary.copyWith(fontWeight: FontWeight.w600),
    );
  }

  InputDecoration _inputDecoration({
    String? hint,
    String? errorText,
    IconData? prefixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.caption,
      errorText: errorText,
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
