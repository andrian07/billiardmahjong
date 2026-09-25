import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/navigation/app_navigation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/formatters.dart';
import '../../models/price_setting.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_layout.dart';
import '../../shared/widgets/app_toast.dart';
import 'data/price_repository.dart';
import 'widgets/price_edit_dialog.dart';
import 'widgets/printer_select_dialog.dart';

const _dayOrder = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
];

const _dayLabels = {
  "Sunday": "Minggu",
  "Monday": "Senin",
  "Tuesday": "Selasa",
  "Wednesday": "Rabu",
  "Thursday": "Kamis",
  "Friday": "Jumat",
  "Saturday": "Sabtu",
};

const _dayAccents = {
  "Sunday": AppColors.danger,
  "Monday": AppColors.primary,
  "Tuesday": AppColors.purple,
  "Wednesday": AppColors.info,
  "Thursday": AppColors.success,
  "Friday": AppColors.warning,
  "Saturday": AppColors.primaryLight,
};

String _formatHourRange(int hour) {
  String two(int n) => n.toString().padLeft(2, '0');
  final next = (hour + 1) % 24;
  return "${two(hour)}:00-${two(next)}:00";
}

/// "Harga Meja" — 2 tab independen (Harga Billiard / Harga Mahjong), masing-masing
/// baca/tulis tabel harga sendiri di backend (ms_master_price vs
/// ms_master_price_mahjong, lihat PriceRepository). Tab shell di sini cuma
/// urus AppLayout + toolbar bersama (judul, tombol Pilih Printer) + TabBar;
/// semua state harga (load/edit/tampil) ada di [_PriceTab].
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 2, vsync: this);
  final _billiardTabKey = GlobalKey<_PriceTabState>();
  final _mahjongTabKey = GlobalKey<_PriceTabState>();

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshAll() {
    _billiardTabKey.currentState?.load();
    _mahjongTabKey.currentState?.load();
  }

  void _openPrinterSelectDialog() {
    showDialog(context: context, builder: (_) => const PrinterSelectDialog());
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: "Pengaturan",
      subtitle: "Kelola harga sewa meja per jam",
      showSearch: false,
      activeMenuKey: "pengaturan",
      onMenuSelect: (key) => navigateToMenu(context, key),
      onRefresh: _refreshAll,
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
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: "Harga Billiard"),
              Tab(text: "Harga Mahjong"),
            ],
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _PriceTab(key: _billiardTabKey, mahjong: false),
                _PriceTab(key: _mahjongTabKey, mahjong: true),
              ],
            ),
          ),
        ],
      ),
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
            Icons.sell_outlined,
            color: AppColors.primary,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Pengaturan Harga",
                style: AppText.title.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                "Harga sewa meja per jam, per kategori (billiard/mahjong)",
                style: AppText.caption,
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _openPrinterSelectDialog,
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text("Pilih Printer"),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
            ),
          ),
        ),
      ],
    );
  }
}

/// One tab's worth of price-editing state — everything SettingsPage used to
/// own directly, now parametrized by [mahjong] so the Billiard and Mahjong
/// tabs each get their own independent PriceRepository/data/loading state.
class _PriceTab extends StatefulWidget {
  final bool mahjong;

  const _PriceTab({super.key, required this.mahjong});

  @override
  State<_PriceTab> createState() => _PriceTabState();
}

class _PriceTabState extends State<_PriceTab>
    with AutomaticKeepAliveClientMixin {
  late final _repository = PriceRepository(mahjong: widget.mahjong);

  List<PriceSetting> _prices = [];
  bool _loading = true;
  String? _error;
  final Set<String> _expandedDays = {_dayOrder.first};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prices = await _repository.getPrices();
      if (!mounted) return;
      setState(() {
        _prices = prices;
        _loading = false;
      });
    } on PriceRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Map<String, List<PriceSetting>> get _grouped {
    final map = <String, List<PriceSetting>>{};
    for (final item in _prices) {
      (map[item.day] ??= []).add(item);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.hour.compareTo(b.hour));
    }
    return map;
  }

  Future<void> _openEditDialog(PriceSetting item) async {
    final result = await showDialog<PriceEditResult>(
      context: context,
      builder: (_) => PriceEditDialog(
        dayLabel: _dayLabels[item.day] ?? item.day,
        hourLabel: _formatHourRange(item.hour),
        item: item,
      ),
    );
    if (result == null) return;

    try {
      await _repository.editPrice(
        id: item.id,
        price: result.price,
        price2: result.price2,
        price3: result.price3,
        price4: result.price4,
        price5: result.price5,
      );
      if (!mounted) return;
      AppToast.success(
        context,
        "Harga ${_formatHourRange(item.hour)} berhasil diperbarui",
      );
      setState(() {
        final index = _prices.indexWhere((p) => p.id == item.id);
        if (index != -1) {
          _prices[index] = item.copyWith(
            price: result.price,
            price2: result.price2,
            price3: result.price3,
            price4: result.price4,
            price5: result.price5,
          );
        }
      });
    } on PriceRepositoryException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildBody();
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildErrorState(_error!);
    }
    if (_prices.isEmpty) {
      return _buildEmptyState();
    }

    final grouped = _grouped;
    // 1 kolom: baris harga sekarang menampilkan 5 tingkat (Harga 1..5) + kolom
    // JAM + tombol edit, jadi butuh lebar penuh biar angka tidak terpotong.
    const columns = 1;
    const spacing = 14.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final day in _dayOrder)
                SizedBox(
                  width: itemWidth,
                  child: _DaySection(
                    label: _dayLabels[day] ?? day,
                    accent: _dayAccents[day] ?? AppColors.primary,
                    items: grouped[day] ?? const <PriceSetting>[],
                    expanded: _expandedDays.contains(day),
                    onToggle: () => setState(() {
                      if (!_expandedDays.remove(day)) {
                        _expandedDays.add(day);
                      }
                    }),
                    onEdit: _openEditDialog,
                  ),
                ),
            ],
          );
        },
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
              Icons.sell_outlined,
              size: 30,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 14),
          Text("Belum ada data harga", style: AppText.bodySecondary),
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
            onPressed: load,
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

class _DaySection extends StatelessWidget {
  final String label;
  final Color accent;
  final List<PriceSetting> items;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<PriceSetting> onEdit;

  const _DaySection({
    required this.label,
    required this.accent,
    required this.items,
    required this.expanded,
    required this.onToggle,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 30,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: AppText.body.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "${items.length} slot jam",
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? _buildTable()
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1, color: AppColors.divider),
        Container(
          color: AppColors.background.withValues(alpha: .4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: _headerRow(),
        ),
        const Divider(height: 1, color: AppColors.divider),
        for (var i = 0; i < items.length; i++) ...[
          _priceRow(items[i], striped: i.isEven),
          if (i != items.length - 1)
            const Divider(height: 1, color: AppColors.divider),
        ],
      ],
    );
  }

  Widget _headerRow() {
    final style = AppText.caption.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: .5,
    );
    return Row(
      children: [
        SizedBox(width: 96, child: Text("JAM", style: style)),
        for (var i = 1; i <= 5; i++)
          Expanded(
            child: Text("HARGA $i", textAlign: TextAlign.end, style: style),
          ),
        const SizedBox(width: 44),
      ],
    );
  }

  Widget _priceRow(PriceSetting item, {required bool striped}) {
    final cellStyle = AppText.caption.copyWith(
      fontSize: 13,
      color: AppColors.text,
    );
    return Container(
      color: striped
          ? AppColors.background.withValues(alpha: .25)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              _formatHourRange(item.hour),
              style: cellStyle.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          for (final value in [
            item.price,
            item.price2,
            item.price3,
            item.price4,
            item.price5,
          ])
            Expanded(
              child: Text(
                formatCurrency(value),
                textAlign: TextAlign.end,
                style: cellStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          SizedBox(
            width: 44,
            child: IconButton(
              tooltip: "Edit",
              icon: const Icon(
                Icons.edit_outlined,
                size: 17,
                color: AppColors.textSecondary,
              ),
              onPressed: () => onEdit(item),
            ),
          ),
        ],
      ),
    );
  }
}
