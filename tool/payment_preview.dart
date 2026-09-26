import 'package:flutter/material.dart';

import 'package:mahjong_billiard_billing/core/theme/app_theme.dart';
import 'package:mahjong_billiard_billing/features/billing/widgets/payment_dialog.dart';
import 'package:mahjong_billiard_billing/models/pool_table.dart';

void main() {
  runApp(const PreviewApp());
}

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        backgroundColor: Colors.black87,
        body: Center(
          child: PaymentDialog(
            table: PoolTable(
              id: '1',
              name: 'Meja 01',
              status: TableStatus.playing,
              sessionType: SessionType.timer,
              startTime: '21:50',
              startAt: DateTime.now().subtract(const Duration(minutes: 45)),
            ),
          ),
        ),
      ),
    );
  }
}
