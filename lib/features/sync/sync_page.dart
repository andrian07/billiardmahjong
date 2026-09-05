import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/navigation/app_navigation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/formatters.dart';
import '../../models/pagination_info.dart';
import '../../models/sync_pending_item.dart';
import '../../shared/widgets/app_layout.dart';
import '../../shared/widgets/app_toast.dart';
import '../billing/widgets/stat_card.dart';
import 'data/sync_repository.dart';

/// "Sinkron Online" — transaksi billing/cafe/saldo dan pembelian di-curl ke
/// laporan online (gameon) begitu dibuat, fire-and-forget; kalau gameon
/// tidak terjangkau saat itu, data lokal tetap sah tapi tidak pernah
/// otomatis diulang. Halaman ini menampilkan baris yang belum berhasil
/// ("*_upload_status" masih 'N') dan tombol upload ulang, per baris atau
/// sekaligus semua yang tampil di halaman ini.
class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  static const _perPage = 20;

  final _repository = SyncRepository();

  List<SyncPendingItem> _items = [];
  PaginationInfo _pagination = PaginationInfo.empty;
  SyncPendingCounts _counts = SyncPendingCounts.empty;
  bool _loading = true;
  String? _error;
  bool _retryingAll = false;

  /// id unik per baris ("type:id") yang sedang di-retry sendiri-sendiri, jadi
  /// tombol baris lain tetap aktif selagi satu baris diproses.
  final Set<String> _retryingRows = {};

  /// Alasan gagal upload terakhir per baris ("type:id" -> pesan dari gameon),
  /// ditampilkan menempel di barisnya sampai baris itu di-retry lagi / berhasil.
  final Map<String, String> _rowErrors = {};

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  String _rowKey(SyncPendingItem item) => "${item.type.apiValue}:${item.id}";

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _repository.getPending(page: page, perPage: _perPage);
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _pagination = result.pagination;
        _counts = result.counts;
        _loading = false;
        // buang catatan error untuk baris yang sudah tidak ada di halaman ini
        // (mis. sudah berhasil tersinkron) supaya map tidak menumpuk.
        final visible = result.items.map(_rowKey).toSet();
        _rowErrors.removeWhere((key, _) => !visible.contains(key));
      });
    } on SyncRepositoryException catch (e) {
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

  Future<void> _retryOne(SyncPendingItem item) async {
    final key = _rowKey(item);
    setState(() {
      _retryingRows.add(key);
      _rowErrors.remove(key);
    });

    try {
      await _repository.retry(type: item.type, id: item.id);
      if (!mounted) return;
      AppToast.success(context, "${item.inv} berhasil diupload ulang");
      await _load(_pagination.currentPage);
    } on SyncRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _retryingRows.remove(key);
        _rowErrors[key] = e.message;
      });
      AppToast.error(context, "${item.inv}: ${_cleanError(e.message)}");
    }
  }

  /// Buang awalan "Gagal upload ulang: " dari pesan backend — di UI ini
  /// konteksnya sudah jelas gagal, jadi yang berguna cuma sebab aslinya.
  String _cleanError(String message) {
    const prefix = "Gagal upload ulang: ";
    return message.startsWith(prefix)
        ? message.substring(prefix.length)
        : message;
  }

  /// Upload ulang berurutan untuk semua baris yang SEDANG tampil di halaman
  /// ini (bukan seluruh data pending lintas halaman) — satu per satu supaya
  /// tidak membanjiri gameon dengan request paralel. Baris yang gagal
  /// dilewati (tetap 'N', tersisa di daftar) tanpa menghentikan sisanya.
  Future<void> _retryAllOnPage() async {
    if (_retryingAll || _items.isEmpty) return;
    setState(() {
      _retryingAll = true;
      _rowErrors.clear();
    });

    var succeeded = 0;
    var failed = 0;
    for (final item in List<SyncPendingItem>.from(_items)) {
      try {
        await _repository.retry(type: item.type, id: item.id);
        succeeded++;
      } on SyncRepositoryException catch (e) {
        failed++;
        _rowErrors[_rowKey(item)] = e.message;
      }
    }

    if (!mounted) return;
    setState(() => _retryingAll = false);
    if (failed == 0) {
      AppToast.success(context, "$succeeded data berhasil diupload ulang");
    } else {
      AppToast.error(
        context,
        "$succeeded berhasil, $failed masih gagal — lihat alasannya di tiap baris",
      );
    }
    await _load(_pagination.currentPage);
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: "Sinkron Online",
      subtitle: "Data yang belum berhasil terkirim ke laporan online",
      showSearch: false,
      activeMenuKey: "sync_online",
      onMenuSelect: (key) => navigateToMenu(context, key),
      onRefresh: () => _load(_pagination.currentPage),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatsRow(),
          const SizedBox(height: 16),
          _buildListCard(),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.table_bar_rounded,
            color: AppColors.primary,
            label: "Billing",
            value: "${_counts.transaction}",
            subtitle: "belum tersinkron",
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatCard(
            icon: Icons.local_cafe_rounded,
            color: AppColors.success,
            label: "Cafe / POS",
            value: "${_counts.transactionCafe}",
            subtitle: "belum tersinkron",
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatCard(
            icon: Icons.savings_outlined,
            color: AppColors.info,
            label: "Pengisian Saldo",
            value: "${_counts.transaksiSaldo}",
            subtitle: "belum tersinkron",
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatCard(
            icon: Icons.shopping_cart_checkout_rounded,
            color: AppColors.warning,
            label: "Pembelian",
            value: "${_counts.purchase}",
            subtitle: "belum tersinkron",
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatCard(
            icon: Icons.event_seat_outlined,
            color: AppColors.primaryLight,
            label: "Status Meja",
            value: "${_counts.tableStatusEvent}",
            subtitle: "belum tersinkron",
          ),
        ),
      ],
    );
  }

  Widget _buildListCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("Belum Tersinkron", style: AppText.title),
              const Spacer(),
              if (_items.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _retryingAll ? null : _retryAllOnPage,
                  icon: _retryingAll
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: Text(
                    _retryingAll
                        ? "Mengupload..."
                        : "Upload Ulang Semua (halaman ini)",
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildContent(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: _buildInlineError(_error!),
      );
    }

    if (_items.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        for (final item in _items) ...[
          _buildRow(item),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        _buildPagination(),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_done_rounded,
                size: 30,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              "Semua data sudah tersinkron ke laporan online",
              style: AppText.bodySecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(SyncPendingItem item) {
    final key = _rowKey(item);
    final retrying = _retryingRows.contains(key);
    final error = _rowErrors[key];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              item.type.label,
              style: AppText.caption.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.inv,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  "${item.date} • Cabang ${item.branch} • ${item.createdBy}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption,
                ),
                if (error != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 14,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          "Gagal: ${_cleanError(error)}",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatCurrency(item.total),
            style: AppText.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: OutlinedButton.icon(
              onPressed: retrying ? null : () => _retryOne(item),
              icon: retrying
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 16),
              label: Text(
                retrying ? "..." : "Upload Ulang",
                style: AppText.caption,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    final p = _pagination;
    final startItem = p.totalItems == 0 ? 0 : (p.currentPage - 1) * p.perPage + 1;
    final endItem = (p.currentPage * p.perPage).clamp(0, p.totalItems);

    return Row(
      children: [
        Text(
          "Menampilkan $startItem-$endItem dari ${p.totalItems} data",
          style: AppText.caption,
        ),
        const Spacer(),
        OutlinedButton(
          onPressed: p.hasPrevPage ? () => _goToPage(p.currentPage - 1) : null,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size(0, 36),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
            ),
          ),
          child: const Icon(Icons.chevron_left_rounded, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          "Halaman ${p.currentPage} dari ${p.totalPages == 0 ? 1 : p.totalPages}",
          style: AppText.caption,
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: p.hasNextPage ? () => _goToPage(p.currentPage + 1) : null,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size(0, 36),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
            ),
          ),
          child: const Icon(Icons.chevron_right_rounded, size: 18),
        ),
      ],
    );
  }

  Widget _buildInlineError(String message) {
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
            onPressed: () => _load(_pagination.currentPage),
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
}
