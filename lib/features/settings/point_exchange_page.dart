import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/navigation/app_navigation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/formatters.dart';
import '../../models/pagination_info.dart';
import '../../models/point_exchange.dart';
import '../../services/session_storage.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_layout.dart';
import '../../shared/widgets/app_toast.dart';
import 'data/point_exchange_repository.dart';

/// "Tukar Point" — riwayat penukaran point member (dari tabel reward_redemption
/// di gameon). Katalog hadiah tidak dikelola di sini; satu-satunya aksi tulis
/// adalah menandai kupon terpakai (Redeemed -> Claimed) dan membatalkannya.
class PointExchangePage extends StatefulWidget {
  const PointExchangePage({super.key});

  @override
  State<PointExchangePage> createState() => _PointExchangePageState();
}

class _PointExchangePageState extends State<PointExchangePage> {
  static const _perPage = 10;

  final _repository = PointExchangeRepository();
  final _sessionStorage = SessionStorage();
  final _searchCtrl = TextEditingController();

  List<PointRedemption> _items = [];
  PaginationInfo _pagination = PaginationInfo.empty;
  bool _loading = true;
  String? _error;
  int? _busyId;
  String _query = "";
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // Live search — refetch (page 1) a short beat after the user stops typing,
  // same feel as the Transaksi page but server-side since this list is paged.
  void _onSearchChanged(String value) {
    setState(() {}); // refresh the clear (×) button
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      final next = value.trim();
      if (next == _query) return;
      _query = next;
      _load(1);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    if (_query.isEmpty && _searchCtrl.text.isEmpty) return;
    _searchCtrl.clear();
    _query = "";
    _load(1);
  }

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _repository.getRedemptionHistory(
        page: page,
        perPage: _perPage,
        search: _query.isEmpty ? null : _query,
      );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _pagination = result.pagination;
        _loading = false;
      });
    } on PointExchangeRepositoryException catch (e) {
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

  static const _months = [
    "Jan", "Feb", "Mar", "Apr", "Mei", "Jun",
    "Jul", "Agu", "Sep", "Okt", "Nov", "Des",
  ];

  String _fmtWhen(DateTime? at) {
    if (at == null) return "-";
    String two(int n) => n.toString().padLeft(2, '0');
    return "${at.day} ${_months[at.month - 1]} ${at.year} • "
        "${two(at.hour)}:${two(at.minute)}";
  }

  String _fmtDay(DateTime? at) {
    if (at == null) return "-";
    return "${at.day} ${_months[at.month - 1]} ${at.year}";
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = false,
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
            child: const Text("BATAL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? AppColors.danger : AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _claim(PointRedemption item) async {
    final ok = await _confirm(
      title: "Tandai Kupon Terpakai?",
      message:
          "Hadiah \"${item.rewardName}\" milik ${item.customerName} "
          "(kode ${item.redeemCode}) akan ditandai sudah diserahkan / terpakai.",
      confirmLabel: "YA, TANDAI",
    );
    if (!ok) return;

    final session = await _sessionStorage.getSession();
    final createdBy = session?['username']?.toString() ?? "";

    setState(() => _busyId = item.id);
    try {
      final msg = await _repository.claimRedemption(
        id: item.id,
        createdBy: createdBy,
      );
      if (!mounted) return;
      AppToast.success(context, msg);
      await _load(_pagination.currentPage);
    } on PointExchangeRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _unclaim(PointRedemption item) async {
    final ok = await _confirm(
      title: "Batalkan Klaim Kupon?",
      message:
          "Kupon \"${item.rewardName}\" milik ${item.customerName} "
          "(kode ${item.redeemCode}) akan dikembalikan ke status belum terpakai.",
      confirmLabel: "YA, BATALKAN",
      danger: true,
    );
    if (!ok) return;

    setState(() => _busyId = item.id);
    try {
      final msg = await _repository.unclaimRedemption(id: item.id);
      if (!mounted) return;
      AppToast.success(context, msg);
      await _load(_pagination.currentPage);
    } on PointExchangeRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: "Tukar Point",
      subtitle: "Riwayat penukaran point member",
      showSearch: false,
      activeMenuKey: "setting_point_exchange",
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
          if (!_loading && _error == null && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 14, 36, 6),
              child: _RedemptionRow.header(),
            ),
          Expanded(child: _buildBody()),
          if (!_loading && _error == null && _items.isNotEmpty) ...[
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
    if (_items.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = _items[index];
        return _RowCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _RedemptionRow.data(
              no:
                  (_pagination.currentPage - 1) * _pagination.perPage +
                  index +
                  1,
              item: item,
              when: _fmtWhen(item.createdAt),
              claimLine: item.isClaimed
                  ? "Terpakai ${_fmtDay(item.claimedAt)}"
                        "${item.claimedBy.isEmpty ? "" : " • ${item.claimedBy}"}"
                  : null,
              busy: _busyId == item.id,
              anyBusy: _busyId != null,
              onClaim: () => _claim(item),
              onUnclaim: () => _unclaim(item),
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
            Icons.card_giftcard_rounded,
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
              "Riwayat Penukaran Point",
              style: AppText.title.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              _loading || _error != null
                  ? "Memuat data..."
                  : _query.isEmpty
                  ? "${_pagination.totalItems} penukaran tercatat"
                  : "${_pagination.totalItems} hasil untuk \"$_query\"",
              style: AppText.caption,
            ),
          ],
        ),
        const Spacer(),
        _buildSearchField(),
        const SizedBox(width: 8),
        SizedBox(
          height: 40,
          child: OutlinedButton.icon(
            onPressed: _loading ? null : () => _load(_pagination.currentPage),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(
              "Muat Ulang",
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

  Widget _buildSearchField() {
    return SizedBox(
      width: 280,
      height: 40,
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        style: AppText.body.copyWith(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: "Cari kode kupon / nama member",
          hintStyle: AppText.caption.copyWith(fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          prefixIconConstraints: const BoxConstraints(minWidth: 38),
          suffixIcon: _searchCtrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  splashRadius: 16,
                  tooltip: "Hapus pencarian",
                  onPressed: _clearSearch,
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          filled: true,
          fillColor: AppColors.background.withValues(alpha: .4),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
            borderSide: const BorderSide(color: AppColors.primary),
          ),
        ),
      ),
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
              Icons.card_giftcard_rounded,
              size: 30,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _query.isEmpty
                ? "Belum ada penukaran point"
                : "Tidak ada penukaran yang cocok dengan \"$_query\"",
            style: AppText.bodySecondary,
          ),
          if (_query.isNotEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _clearSearch,
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text("Hapus pencarian"),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                ),
              ),
            ),
          ],
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
          "Menampilkan $startItem-$endItem dari ${p.totalItems} penukaran",
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

class _RedemptionRow extends StatelessWidget {
  final bool header;
  final int? no;
  final PointRedemption? item;
  final String? when;
  final String? claimLine;
  final bool busy;
  final bool anyBusy;
  final VoidCallback? onClaim;
  final VoidCallback? onUnclaim;

  const _RedemptionRow.header()
    : header = true,
      no = null,
      item = null,
      when = null,
      claimLine = null,
      busy = false,
      anyBusy = false,
      onClaim = null,
      onUnclaim = null;

  const _RedemptionRow.data({
    required this.no,
    required this.item,
    required this.when,
    required this.claimLine,
    required this.busy,
    required this.anyBusy,
    required this.onClaim,
    required this.onUnclaim,
  }) : header = false;

  @override
  Widget build(BuildContext context) {
    if (header) {
      return _row(
        no: _headerText("NO"),
        when: _headerText("TANGGAL"),
        member: _headerText("MEMBER"),
        reward: _headerText("HADIAH"),
        point: _headerText("POINT", alignEnd: true),
        code: _headerText("KODE"),
        status: _headerText("STATUS", alignCenter: true),
        action: _headerText("AKSI", alignCenter: true),
      );
    }

    final r = item!;
    final cellStyle = AppText.caption.copyWith(fontSize: 13);

    return _row(
      no: Text("$no", style: cellStyle.copyWith(color: AppColors.textHint)),
      when: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            when ?? "-",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: cellStyle.copyWith(color: AppColors.textSecondary),
          ),
          if (claimLine != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                claimLine!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cellStyle.copyWith(
                  fontSize: 11,
                  color: AppColors.success,
                ),
              ),
            ),
        ],
      ),
      member: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            r.customerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: cellStyle.copyWith(fontWeight: FontWeight.w600),
          ),
          if (r.customerPhone.isNotEmpty)
            Text(
              r.customerPhone,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: cellStyle.copyWith(color: AppColors.textHint),
            ),
        ],
      ),
      reward: Text(
        r.rewardName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: cellStyle.copyWith(color: AppColors.textSecondary),
      ),
      point: Text(
        formatThousands(r.pointSpent),
        textAlign: TextAlign.end,
        style: cellStyle.copyWith(fontWeight: FontWeight.w600),
      ),
      code: Text(
        r.redeemCode.isEmpty ? "-" : r.redeemCode,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: cellStyle.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: .3,
        ),
      ),
      status: Center(child: _StatusChip(status: r.status)),
      action: Center(child: _actionButton(r)),
    );
  }

  Widget _actionButton(PointRedemption r) {
    if (busy) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (r.isRedeemed) {
      return SizedBox(
        height: 32,
        child: ElevatedButton.icon(
          onPressed: anyBusy ? null : onClaim,
          icon: const Icon(Icons.check_circle_outline_rounded, size: 15),
          label: const Text("Terpakai"),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            textStyle: AppText.button.copyWith(fontSize: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusSmall),
            ),
          ),
        ),
      );
    }

    if (r.isClaimed) {
      return SizedBox(
        height: 32,
        child: TextButton.icon(
          onPressed: anyBusy ? null : onUnclaim,
          icon: const Icon(Icons.undo_rounded, size: 15),
          label: const Text("Batalkan"),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.danger,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: AppText.button.copyWith(fontSize: 12),
          ),
        ),
      );
    }

    return Text(
      "-",
      style: AppText.caption.copyWith(fontSize: 13, color: AppColors.textHint),
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
    required Widget when,
    required Widget member,
    required Widget reward,
    required Widget point,
    required Widget code,
    required Widget status,
    required Widget action,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 28, child: no),
        const SizedBox(width: 10),
        Expanded(flex: 3, child: when),
        const SizedBox(width: 10),
        Expanded(flex: 3, child: member),
        const SizedBox(width: 10),
        Expanded(flex: 3, child: reward),
        const SizedBox(width: 10),
        SizedBox(width: 64, child: point),
        const SizedBox(width: 10),
        SizedBox(width: 104, child: code),
        const SizedBox(width: 10),
        SizedBox(width: 88, child: status),
        const SizedBox(width: 10),
        SizedBox(width: 116, child: action),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status.isEmpty) {
      return Text("-", style: AppText.caption.copyWith(fontSize: 13));
    }

    final s = status.toLowerCase();
    final Color color;
    if (s.contains('claim') || s.contains('done') || s.contains('selesai')) {
      color = AppColors.success;
    } else if (s.contains('cancel') ||
        s.contains('batal') ||
        s.contains('expired')) {
      color = AppColors.danger;
    } else {
      color = AppColors.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.caption.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
