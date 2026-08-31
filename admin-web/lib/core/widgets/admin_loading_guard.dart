// modal spinner ระหว่างรอ API (save/delete) — กฎเดียวกับ AdminListStateView:
// ไม่โชว์ถ้า API ตอบเร็วกว่า kAdminLoadingDelay, โชว์แล้วต้องอยู่ครบ kAdminLoadingMinDisplay ก่อนปิด
// กัน "จอมืดแว้บ" ตอน API ตอบไว (3-12ms) — เคยเป็นปัญหาเดียวกับ skeleton ก่อนแก้

import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'admin_list_state.dart';

Future<void> runWithGuardedLoading({
  required BuildContext context,
  required Future<void> Function() task,
  Duration delay = kAdminLoadingDelay,
  Duration minDisplay = kAdminLoadingMinDisplay,
}) async {
  var shown = false;
  DateTime? shownAt;
  final timer = Timer(delay, () {
    if (!context.mounted) return;
    shown = true;
    shownAt = DateTime.now();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
    );
  });

  await task();

  timer.cancel();
  if (shown) {
    final remaining = minDisplay - DateTime.now().difference(shownAt!);
    if (remaining > Duration.zero) await Future.delayed(remaining);
    if (context.mounted) Navigator.pop(context);
  }
}
