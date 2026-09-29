import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../models/pool_table.dart';

const _timerLowDuration = Duration(minutes: 5);

bool isTimerRunningLow(PoolTable table) {
  if (table.status != TableStatus.playing ||
      table.sessionType != SessionType.timer ||
      table.plannedDuration == null ||
      table.startAt == null) {
    return false;
  }

  final remaining =
      table.plannedDuration! - DateTime.now().difference(table.startAt!);
  return remaining > Duration.zero && remaining <= _timerLowDuration;
}

Color tableStatusColor(PoolTable table) {
  if (isTimerRunningLow(table)) {
    return AppColors.warning;
  }

  switch (table.status) {
    case TableStatus.playing:
      return AppColors.success;
    case TableStatus.unpaid:
      // Timer sudah habis (00:00:00) - merah, bukan warning/kuning, supaya lebih
      // menonjol dan segera terlihat perlu ditindaklanjuti (checkout).
      return AppColors.danger;
    case TableStatus.ready:
      return AppColors.textHint;
  }
}

String tableStatusLabel(PoolTable table) {
  switch (table.status) {
    case TableStatus.playing:
      return "Playing";
    case TableStatus.unpaid:
      return "Siap Dibayar";
    case TableStatus.ready:
      return "Kosong";
  }
}

class TableCard extends StatelessWidget {
  final PoolTable table;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onPayment;
  final VoidCallback? onMoveTable;
  final VoidCallback? onAddDuration;
  final VoidCallback? onRoundUpDuration;
  final VoidCallback? onCancel;

  const TableCard({
    super.key,
    required this.table,
    required this.selected,
    required this.onTap,
    this.onPayment,
    this.onMoveTable,
    this.onAddDuration,
    this.onRoundUpDuration,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final color = tableStatusColor(table);
    final isReady = table.status == TableStatus.ready;
    final isUnpaid = table.status == TableStatus.unpaid;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(
          color: selected ? color : (isReady ? AppColors.border : color.withValues(alpha: .35)),
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          if (selected)
            BoxShadow(
              color: color.withValues(alpha: .25),
              blurRadius: 14,
              offset: const Offset(0, 6),
            )
          else
            BoxShadow(
              color: Colors.black.withValues(alpha: .06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  table.name,
                  style: AppText.bodySecondary.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (table.badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    table.badge!,
                    style: AppText.caption.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 9,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isReady ? .06 : .12),
              borderRadius: BorderRadius.circular(AppSizes.radiusSmall),
            ),
            child: Column(
              children: [
                Icon(
                  isReady ? Icons.lightbulb_outline : Icons.lightbulb_rounded,
                  color: color,
                  size: 18,
                ),
                const SizedBox(height: 4),
                Text(
                  table.timerText ?? tableStatusLabel(table),
                  style: AppText.body.copyWith(
                    color: isReady ? AppColors.textSecondary : color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          Row(
            children: [
              Text(
                table.startTime != null ? "Mulai ${table.startTime}" : "-",
                style: AppText.caption.copyWith(fontSize: 10),
              ),
              if (table.memberName != null) ...[
                const Spacer(),
                Flexible(
                  child: Text(
                    table.memberName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: AppText.caption.copyWith(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),

          if (table.players != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.groups_outlined,
                  size: 12,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    table.players!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (table.promoName != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.local_offer_outlined,
                  size: 11,
                  color: table.hasFixPromo
                      ? AppColors.info
                      : AppColors.purple,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    table.promoName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: table.hasFixPromo
                          ? AppColors.info
                          : AppColors.purple,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 8),

          if (isReady || isUnpaid)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: isReady ? onTap : onPayment,
                style: OutlinedButton.styleFrom(
                  backgroundColor: color,
                  side: BorderSide(color: color),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusSmall),
                  ),
                ),
                child: Text(
                  isReady ? "MULAI" : "BAYAR",
                  style: AppText.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _actionSlot(
                  icon: Icons.payments_outlined,
                  tooltip: "Bayar",
                  color: AppColors.warning,
                  onTap: onPayment,
                ),
                _actionSlot(
                  icon: Icons.swap_horiz_rounded,
                  tooltip: "Pindah Meja",
                  color: AppColors.info,
                  onTap: onMoveTable,
                ),
                if (table.sessionType == SessionType.reguler)
                  _actionSlot(
                    icon: Icons.schedule_rounded,
                    tooltip: "Genapkan Waktu",
                    color: AppColors.primary,
                    onTap: onRoundUpDuration,
                  )
                else
                  _actionSlot(
                    icon: Icons.more_time_rounded,
                    tooltip: table.hasFixPromo
                        ? "Tidak bisa tambah durasi (promo paket)"
                        : "Tambah Durasi",
                    color: AppColors.primary,
                    onTap: table.sessionType == SessionType.timer
                        ? onAddDuration
                        : null,
                  ),
                _actionSlot(
                  icon: Icons.cancel_outlined,
                  tooltip: onCancel != null
                      ? "Batalkan"
                      : "Tidak bisa dibatalkan (lebih dari 6 menit)",
                  color: AppColors.danger,
                  onTap: onCancel,
                ),
              ],
            ),
        ],
      ),
    );
  }

  // Ukuran tombol dikunci (bukan Expanded+AspectRatio yang meregang mengikuti lebar card) supaya di
  // layar besar - dengan card yang jadi lebih lebar - tombolnya tetap proporsional sebagai lingkaran
  // ikon yang rapi, bukan kotak raksasa dengan ikon kecil mengambang di tengahnya. Sisa ruang di baris
  // jadi jarak antar tombol (spaceBetween di caller), bukan tombolnya sendiri yang membesar.
  Widget _actionSlot({
    required IconData icon,
    required String tooltip,
    required Color color,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final effectiveColor = enabled ? color : AppColors.textHint;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: effectiveColor.withValues(alpha: enabled ? .14 : .06),
        shape: CircleBorder(
          side: BorderSide(
            color: effectiveColor.withValues(alpha: enabled ? .3 : .12),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 17, color: effectiveColor),
          ),
        ),
      ),
    );
  }
}
