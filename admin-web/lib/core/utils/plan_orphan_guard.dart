// ignore_for_file: use_build_context_synchronously

// เช็คก่อนบันทึกตอนแอดมินลดจำนวนวัน/สัปดาห์ของแผนที่มีท่าฝึกผูกอยู่แล้ว — กันข้อมูลกำพร้า
// (ptd_day_number เกิน wpt_days_per_week ใหม่) เพราะ SelectWorkoutPlan ฝั่ง Go
// (workout_controller.go) copy ทุกแถวใน plan_template_detail ของแผนแบบไม่กรองช่วงวันเลย
// ถ้าปล่อยผ่าน ท่าที่ตกค้างจะหลุดไปให้สมาชิกที่เลือกแผนนี้ "ในอนาคต" ด้วยวันที่ผิดเพี้ยน
// (toWeekday คืนค่า ptd_day_number ดิบเมื่อเกินช่วง daysPerWeek ที่แมปไว้ — วันที่ผิดจากแผนจริง)
// สมาชิกที่เคยเลือกแผนนี้ไปแล้วก่อนหน้านี้ไม่กระทบ เพราะ copy เป็นสำเนาของตัวเองแล้ว (workout_schedules)
//
// ใช้ร่วมกันทั้งฟอร์มแก้ไขแผนที่หน้ารายการ (manage_system_workout_plans_view.dart) และหน้า
// รายละเอียดแผน (manage_system_plan_details_view.dart) — เพื่อไม่ให้ตรรกะป้องกันข้อมูลกำพร้านี้
// หลุด sync กันระหว่าง 2 จุดที่แก้ wpt_days_per_week ได้เหมือนกัน

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../constants/app_colors.dart';
import '../widgets/app_confirm_dialog.dart';
import '../widgets/top_flash.dart';
import '../../services/api_client.dart';
import 'plan_day_labels.dart';

// คืนค่า true = บันทึกต่อได้เลย / false = ยกเลิก ไม่บันทึก (แอดมินกดยกเลิกตอนเห็น dialog เตือน)
Future<bool> resolveOrphanPlanDaysBeforeSave(
  BuildContext context, {
  required int planId,
  required int newDays,
  required int oldDays,
  required Map<String, String> authHeaders,
}) async {
  List<dynamic> details;
  try {
    final res = await http.get(Uri.parse('${ApiClient.serverUrl}/api/workouts/details?plan_id=$planId'), headers: authHeaders);
    if (res.statusCode != 200) return true;
    final decoded = json.decode(utf8.decode(res.bodyBytes));
    details = decoded is Map ? (decoded['data'] ?? decoded['items'] ?? decoded['result'] ?? []) as List : decoded as List;
  } catch (_) {
    return true; // เช็คไม่ได้ (เน็ตหลุด ฯลฯ) ปล่อยให้ backend เป็นคนตัดสินตอนบันทึกจริง ไม่บล็อกแอดมินเฉยๆ
  }

  final orphans = details.cast<Map<String, dynamic>>().where((d) => ((d['ptd_day_number'] as num?)?.toInt() ?? 0) > newDays).toList();
  if (orphans.isEmpty) return true;

  final byDay = <int, List<String>>{};
  for (final o in orphans) {
    final day = (o['ptd_day_number'] as num).toInt();
    final ex = o['weight_exercise'];
    final name = (ex is Map ? ex['wet_name'] : null)?.toString() ?? 'ท่า #${o['wet_id']}';
    byDay.putIfAbsent(day, () => []).add(name);
  }
  final sortedDays = byDay.keys.toList()..sort();
  final detailText = sortedDays.map((d) => '${planDayLabel(d, oldDays)}: ${byDay[d]!.join(", ")}').join('\n');

  final confirmed = await showAppConfirmDialog(
    context,
    icon: Icons.warning_amber_rounded,
    title: 'มีท่าฝึกค้างในวันที่จะถูกลด',
    content: 'ลดเหลือ $newDays วัน/สัปดาห์ไม่ได้ทันที เพราะยังมีท่าฝึก ${orphans.length} รายการผูกอยู่กับวันที่เกินจำนวนใหม่:\n\n$detailText\n\n'
        'กดยืนยันเพื่อลบท่าเหล่านี้แล้วบันทึกต่อ\n(สมาชิกที่เลือกแผนนี้ไปแล้วก่อนหน้านี้จะไม่ได้รับผลกระทบ เพราะระบบคัดลอกไปเป็นของสมาชิกเองแล้ว)',
    confirmLabel: 'ลบและบันทึก',
  );
  if (!confirmed) return false;

  showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)));
  try {
    await Future.wait(orphans.map((o) => http.delete(Uri.parse('${ApiClient.serverUrl}/api/workouts/details/${o['ptd_id']}'), headers: authHeaders)));
  } catch (e) {
    Navigator.pop(context);
    showAppAlert(context, 'ลบท่าที่เกินไม่สำเร็จ: $e');
    return false;
  }
  Navigator.pop(context);
  return true;
}
