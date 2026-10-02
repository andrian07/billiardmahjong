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
import '../data/table_repository.dart';
import 'member_time_history_dialog.dart';

class StartSessionResult {
  final SessionType sessionType;
  final int? customerId;
  final String? memberName;

  /// customer_id pemain (maks 4, dipisah koma) - khusus meja mahjong, harus
  /// member terdaftar (lihat [PoolTable.playerIds]). Beda dari [memberName]:
  /// backend menolak kalau ada duplikat atau member itu sedang aktif di
  /// meja lain (lihat Billing_model::resolve_players).
  final String? playerIds;
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
    this.playerIds,
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

  SessionType _sessionType = SessionType.reguler;
  Customer? _selectedCustomer;
  Promo? _selectedPromo;
  int _durationHours = 0;
  int _durationMinutes = 0;
  String? _durationError;

  final bool _checkingSavedTime = false;
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

  /// Pemain (maks 4, harus member terdaftar) - cuma dipakai/ditampilkan
  /// untuk meja mahjong, lihat [_isMahjong] dan StartSessionResult.playerIds.
  /// Tiap slot Autocomplete-nya punya controller sendiri supaya bisa
  /// di-clear programatis kalau pilihannya ditolak (duplikat / sedang aktif
  /// di meja lain - lihat _selectPlayer).
  bool get _isMahjong => widget.table.categoryType == "mahjong";
  final _selectedPlayers = List<Customer?>.filled(4, null);
  final _playerFieldControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  // Autocomplete's assertion requires textEditingController and focusNode to
  // be supplied together (both null or both set) - see the widget's own
  // fieldViewBuilder-provided focusNode can't be reused here since it's only
  // handed to us inside the builder, after the widget's already built.
  final _playerFocusNodes = List.generate(4, (_) => FocusNode());

  /// customer_id yang sedang aktif di meja LAIN (billiard maupun mahjong) -
  /// baik sebagai member utama maupun sebagai salah satu pemain mahjong di
  /// meja itu. Dimuat sekali di _loadOptions() khusus untuk meja mahjong,
  /// dipakai _selectPlayer() supaya "1 member 1 meja" sudah dicegah dari UI
  /// (backend tetap validasi ulang sebagai source of truth, lihat
  /// Billing_model::resolve_players).
  Set<int> _occupiedElsewhere = {};

  bool _loading = true;
  String? _loadError;
  List<Customer> _customers = [];
  List<Promo> _promos = [];

  /// Hanya promo yang berlaku untuk kategori meja ini (promo tanpa batasan
  /// kategori berlaku untuk semua) - biar tidak salah pilih.
  List<Promo> get _promosForTable {
    final cat = widget.table.categoryMejaId;
    return _promos
        .where(
          (p) =>
              p.tableType == widget.table.categoryType &&
              (p.categoryIds.isEmpty || p.categoryIds.contains(cat)),
        )
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
      // "1 member 1 meja": UI-side hint - cek meja mana saja yang lagi aktif
      // (semua kategori, bukan cuma mahjong) supaya member yang sudah main
      // di tempat lain tidak bisa dipilih lagi di sini. Backend tetap jadi
      // source of truth (lihat Billing_model::resolve_players), ini cuma
      // supaya kasir langsung tahu tanpa perlu submit dulu.
      var occupied = <int>{};
      if (_isMahjong) {
        try {
          final allTables = await TableRepository().getTables();
          for (final t in allTables) {
            if (t.id == widget.table.id || t.status != TableStatus.playing) {
              continue;
            }
            if (t.customerId != null) occupied.add(t.customerId!);
            occupied.addAll(t.playerIdList);
          }
        } catch (_) {
          // Best-effort - gagal ambil daftar meja lain tidak boleh
          // menggagalkan seluruh dialog, backend tetap validasi ulang.
        }
      }
      if (!mounted) return;
      setState(() {
        _customers = customerResult.customers;
        _promos = promoResult.promos;
        _occupiedElsewhere = occupied;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = "Gagal memuat data member/promo.\n$e";
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    for (final c in _playerFieldControllers) {
      c.dispose();
    }
    for (final f in _playerFocusNodes) {
      f.dispose();
    }
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
      final today =
          DateTime.now().weekday; // 1=Senin..7=Minggu, matches validDays
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

  /// Menolak (dan clear field-nya lagi) kalau member yang dipilih sudah ada
  /// di slot pemain lain di meja ini, atau sedang aktif di meja lain - lihat
  /// _occupiedElsewhere. Backend tetap validasi ulang saat submit.
  void _selectPlayer(int index, Customer? customer) {
    if (customer == null) {
      setState(() => _selectedPlayers[index] = null);
      return;
    }

    final duplicateInThisTable = _selectedPlayers.asMap().entries.any(
      (e) => e.key != index && e.value?.id == customer.id,
    );
    if (duplicateInThisTable) {
      AppToast.error(
        context,
        "${customer.name} sudah dipilih sebagai pemain lain di meja ini.",
      );
      _playerFieldControllers[index].clear();
      return;
    }

    if (_occupiedElsewhere.contains(customer.id)) {
      AppToast.error(
        context,
        "${customer.name} sedang aktif di meja lain - 1 member cuma bisa main di 1 meja.",
      );
      _playerFieldControllers[index].clear();
      return;
    }

    setState(() => _selectedPlayers[index] = customer);
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
    final duration = Duration(hours: _durationHours, minutes: _durationMinutes);

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
      final windowLength =
          (promo.validTimeEnd! - promo.validTimeStart! + 24) % 24;
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

    final playerIds = _isMahjong
        ? _selectedPlayers.whereType<Customer>().map((c) => "${c.id}").join(",")
        : "";

    Navigator.of(context).pop(
      StartSessionResult(
        sessionType: _sessionType,
        customerId: _selectedCustomer?.id,
        memberName: _selectedCustomer?.name,
        playerIds: playerIds.isNotEmpty ? playerIds : null,
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
        width: _isMahjong ? 860 : 420,
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
            Icon(Icons.cloud_off_rounded, size: 30, color: AppColors.danger),
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

          // Meja mahjong: popup sudah dilebarkan (lihat build()) khusus supaya
          // muat 2 kolom - kiri isi pemain, kanan isi mode/jam main/promo.
          // Saved-time & Potong Saldo TIDAK ikut di kolom manapun di sini -
          // keduanya cuma relevan kalau _selectedCustomer terisi, dan itu
          // cuma bisa lewat field "Nama Member" yang sengaja disembunyikan
          // untuk mahjong (lihat _buildMemberSection), jadi otomatis tidak
          // pernah aktif di jalur ini.
          if (_isMahjong)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildPlayersSection(),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ..._buildModeSection(),
                      ..._buildDurationSection(),
                      ..._buildPromoSection(),
                    ],
                  ),
                ),
              ],
            )
          else ...[
            ..._buildModeSection(),
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
            ..._buildDurationSection(),
            ..._buildPromoSection(),
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

  List<Widget> _buildModeSection() {
    return [
      _label(_isMahjong ? "Mode Sesi" : "Mode"),
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
    ];
  }

  List<Widget> _buildPlayersSection() {
    return [
      _label("Pemain (Opsional, maks 4)"),
      const SizedBox(height: 10),
      for (var i = 0; i < 4; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        _playerSlot(i),
      ],
    ];
  }

  Widget _playerSlot(int i) {
    final player = _selectedPlayers[i];
    final filled = player != null;
    return InkWell(
      onTap: () => _pickPlayer(i),
      borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: filled
              ? AppColors.primary.withValues(alpha: .10)
              : AppColors.background,
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          border: Border.all(
            color: filled ? AppColors.primary : AppColors.border,
            width: filled ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: filled
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: .15),
              child: filled
                  ? Text(
                      "${i + 1}",
                      style: AppText.body.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : const Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Pemain ${i + 1}",
                    style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    filled
                        ? (player.phone.trim().isEmpty
                              ? player.name
                              : "${player.name} (${player.phone})")
                        : "Cari nama / no. HP member",
                    style: AppText.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (filled)
              IconButton(
                tooltip: "Batalkan pemain ${i + 1}",
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppColors.textSecondary,
                onPressed: () => _selectPlayer(i, null),
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPlayer(int i) async {
    final takenIds = {
      ..._occupiedElsewhere,
      for (var j = 0; j < 4; j++)
        if (j != i && _selectedPlayers[j] != null) _selectedPlayers[j]!.id,
    };
    final picked = await showDialog<Customer>(
      context: context,
      builder: (context) {
        var query = "";
        return StatefulBuilder(
          builder: (context, setLocal) {
            final q = query.toLowerCase();
            final options = _customers
                .where(
                  (c) =>
                      !takenIds.contains(c.id) &&
                      (q.isEmpty ||
                          c.name.toLowerCase().contains(q) ||
                          c.phone.toLowerCase().contains(q)),
                )
                .toList();
            return Dialog(
              backgroundColor: AppColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
              ),
              child: Container(
                width: 400,
                constraints: const BoxConstraints(maxHeight: 460),
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Pilih Pemain ${i + 1}",
                      style: AppText.title.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      style: AppText.body,
                      decoration: _inputDecoration(
                        hint: "Cari nama / no. HP member",
                        prefixIcon: Icons.search_rounded,
                      ),
                      onChanged: (v) => setLocal(() => query = v),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: options.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(20),
                              child: Center(
                                child: Text(
                                  "Member tidak ditemukan",
                                  style: AppText.caption,
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final c = options[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(c.name, style: AppText.body),
                                  subtitle: c.phone.trim().isEmpty
                                      ? null
                                      : Text(c.phone, style: AppText.caption),
                                  onTap: () => Navigator.of(context).pop(c),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (picked != null && mounted) _selectPlayer(i, picked);
  }

  List<Widget> _buildDurationSection() {
    if (_sessionType != SessionType.timer) return const [];
    return [
      const SizedBox(height: 20),
      _label("Durasi Sesi"),
      const SizedBox(height: 8),
      if (_isMahjong)
        Row(
          children: [
            Expanded(
              child: _stepper(
                value: _durationHours,
                unit: "Jam",
                step: 1,
                max: hourOptions.last,
                onChanged: (v) => setState(() {
                  _durationHours = v;
                  _hourController.text = "$v";
                  _durationError = _exceedsSavedTime
                      ? _savedTimeErrorText
                      : null;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _stepper(
                value: _durationMinutes,
                unit: "Menit",
                step: 15,
                max: minuteOptions.last,
                onChanged: (v) => setState(() {
                  _durationMinutes = v;
                  _minuteController.text = "$v";
                  _durationError = _exceedsSavedTime
                      ? _savedTimeErrorText
                      : null;
                }),
              ),
            ),
          ],
        )
      else
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
    ];
  }

  List<Widget> _buildPromoSection() {
    return [
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
    ];
  }

  Widget _mahjongTile(String char, Color color, double angle) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: 38,
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F1E8),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFF2E7D5B), width: 2),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          char,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_isMahjong) return _buildMahjongHeader();
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

  Widget _buildMahjongHeader() {
    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F2A44), Color(0xFF1E4F8F), Color(0xFF2E7D5B)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
            ),
            child: const Icon(
              Icons.sports_esports_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Mulai Sesi",
                  style: AppText.title.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Lengkapi detail untuk memulai permainan",
                  style: AppText.caption.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          _mahjongTile("發", const Color(0xFF1B8A4B), -.15),
          const SizedBox(width: 6),
          _mahjongTile("中", const Color(0xFFD32F2F), .05),
          const SizedBox(width: 6),
          _mahjongTile("●●", const Color(0xFF1E4F8F), .18),
          const SizedBox(width: 16),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
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

  Widget _stepper({
    required int value,
    required String unit,
    required int step,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    final enabled = _durationFieldsEnabled;
    Widget btn(IconData icon, bool canTap, VoidCallback onTap) {
      return InkWell(
        onTap: enabled && canTap ? onTap : null,
        customBorder: const CircleBorder(),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: enabled && canTap ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled && canTap ? AppColors.primary : AppColors.textHint,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          btn(
            Icons.remove_rounded,
            value > 0,
            () => onChanged((value - step).clamp(0, max)),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  "$value",
                  style: AppText.title.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(unit, style: AppText.caption),
              ],
            ),
          ),
          btn(
            Icons.add_rounded,
            value < max,
            () => onChanged((value + step).clamp(0, max)),
          ),
        ],
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
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.caption,
      errorText: errorText,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 20, color: AppColors.textSecondary)
          : null,
      suffixIcon: suffixIcon,
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
