// หน้า: My Workout Plans (แผนของฉัน)
// ทำหน้าที่: รวมทุกแผนของผู้ใช้ (ระบบที่เคยเลือก + ส่วนตัวที่สร้างเอง) เลือกแผนที่ใช้งานอยู่ได้ทีละแผน
// (กันข้อมูลชนกันระหว่างแผน) แก้ชื่อ/ลบแผนส่วนตัวได้อิสระ

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_page_header.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../services/workout_service.dart';
import 'workout_days_selection_view.dart';
import 'weight_training_schedule_view.dart';

class MyWorkoutPlansView extends StatefulWidget {
  const MyWorkoutPlansView({super.key});

  @override
  State<MyWorkoutPlansView> createState() => _MyWorkoutPlansViewState();
}

class _MyWorkoutPlansViewState extends State<MyWorkoutPlansView> {
  List<Map<String, dynamic>> _plans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() => _isLoading = true);
    final result = await WorkoutService.to.getMyPlans();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _plans = (result['data'] as List).cast<Map<String, dynamic>>();
      }
    });
  }

  Future<void> _activate(Map<String, dynamic> plan) async {
    if (_isLoading) return; // กันกดซ้ำ
    final isCustom = plan['plan_type'] == 'custom';
    setState(() => _isLoading = true);
    final result = await WorkoutService.to.activatePlan(
      wptId: isCustom ? null : plan['wpt_id'] as int,
      mwpId: isCustom ? plan['mwp_id'] as int : null,
    );
    if (!mounted) return;

    if (result['success'] != true) {
      setState(() => _isLoading = false);
      final isNetworkError = result['network_error'] == true;
      showAppAlert(
        context,
        result['message'] ?? 'ตั้งแผนที่ใช้งานไม่สำเร็จ',
        type: AppAlertType.error,
        actionLabel: isNetworkError ? 'ลองใหม่' : null,
        onAction: isNetworkError ? () => _activate(plan) : null,
      );
      return;
    }

    final planId = (isCustom ? plan['mwp_id'] : plan['wpt_id']) as int;
    final days = plan['days_per_week'] as int;
    final name = plan['name'] as String;
    await WorkoutService.to.saveActivePlan(
      planId, days, name,
      type: isCustom ? 'custom' : 'system',
      weekdayBased: isCustom,
    );
    await _loadPlans();
    if (!mounted) return;

    showAppAlert(
      context,
      'เปลี่ยนแผนเป็น $name แล้ว',
      type: AppAlertType.success,
      actionLabel: 'ไปที่แผน',
      position: AppAlertPosition.bottom,
      onAction: () {
        final dayNumber = isCustom
            ? DateTime.now().weekday
            : WorkoutService.dayNumberForWeekday(DateTime.now(), days);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WeightTrainingScheduleView(
              planId: planId,
              dayNumber: dayNumber,
              daysPerWeek: days,
              planName: name,
              isCustomPlan: isCustom,
              isWeekdayBased: isCustom,
            ),
          ),
        ).then((_) => _loadPlans());
      },
    );
  }

  Future<void> _rename(Map<String, dynamic> plan) async {
    final controller = TextEditingController(text: plan['name'] as String);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('แก้ชื่อแผน'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == plan['name']) return;
    if (!mounted) return;
    await _submitRename(plan, newName);
  }

  // แยกจาก _rename() เพื่อให้ปุ่ม "ลองใหม่" เรียกซ้ำได้โดยไม่ต้องเปิด dialog กรอกชื่อใหม่อีกรอบ
  Future<void> _submitRename(Map<String, dynamic> plan, String newName) async {
    final result = await WorkoutService.to.renamePersonalPlan(plan['mwp_id'] as int, newName);
    if (!mounted) return;
    if (result['success'] == true) {
      await _loadPlans();
      if (!mounted) return;
      showAppAlert(context, 'เปลี่ยนชื่อแล้ว', type: AppAlertType.success);
    } else {
      final isNetworkError = result['network_error'] == true;
      showAppAlert(
        context,
        result['message'] ?? 'แก้ชื่อไม่สำเร็จ',
        type: AppAlertType.error,
        actionLabel: isNetworkError ? 'ลองใหม่' : null,
        onAction: isNetworkError ? () => _submitRename(plan, newName) : null,
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> plan) async {
    final confirm = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'ลบแผนนี้?',
      content: 'ลบแผน "${plan['name']}" และตารางฝึกทั้งหมดในแผนนี้\n'
          'ประวัติผลการฝึกที่บันทึกไว้แล้วจะยังคงอยู่',
      confirmLabel: 'ลบแผน',
    );
    if (!confirm) return;
    if (!mounted) return;
    await _submitDeletePersonal(plan);
  }

  Future<void> _submitDeletePersonal(Map<String, dynamic> plan) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final wasActive = plan['is_active'] == true;
    final result = await WorkoutService.to.deletePersonalPlan(plan['mwp_id'] as int);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (result['success'] == true) {
      if (wasActive) WorkoutService.to.clearActivePlan();
      await _loadPlans();
      if (!mounted) return;
      if (wasActive) {
        showAppAlert(
          context,
          'ลบแผน "${plan['name']}" แล้ว (เป็นแผนที่ใช้งานอยู่ ตอนนี้ยังไม่มีแผนที่ใช้งาน)',
          type: AppAlertType.success,
        );
      }
    } else {
      final isNetworkError = result['network_error'] == true;
      showAppAlert(
        context,
        result['message'] ?? 'ลบไม่สำเร็จ',
        type: AppAlertType.error,
        actionLabel: isNetworkError ? 'ลองใหม่' : null,
        onAction: isNetworkError ? () => _submitDeletePersonal(plan) : null,
      );
    }
  }

  // เกณฑ์เดียวกับ _showReset ในหน้าตารางฝึก (weight_training_schedule_view.dart) — ระบบ:
  // ต้องแก้ไขไปจากแม่แบบแล้ว (is_modified), ส่วนตัว: ต้องมีท่าฝึกอยู่แล้วอย่างน้อย 1 ท่า
  // ไม่โชว์ปุ่มรีเซ็ทถ้ายังไม่มีอะไรให้รีเซ็ทจริง กันปุ่มรกจอโดยไม่มีประโยชน์
  bool _canReset(Map<String, dynamic> plan) {
    final isCustom = plan['plan_type'] == 'custom';
    return isCustom
        ? ((plan['days_per_week'] as num?)?.toInt() ?? 0) > 0
        : (plan['is_modified'] as bool? ?? false);
  }

  // รีเซ็ตแผนนี้กลับเป็นค่าเริ่มต้น — ทำได้ไม่ว่าแผนจะ active อยู่หรือไม่ (ต่างจากเดิมที่ผูกกับ
  // แผน active เท่านั้น) กดจากรายการตรงนี้เลย ไม่ต้องเปิดแผนเข้าไปในตารางฝึกก่อน
  Future<void> _resetPlan(Map<String, dynamic> plan) async {
    final isCustom = plan['plan_type'] == 'custom';
    final name = plan['name'] as String;
    final content = isCustom
        ? 'ท่าออกกำลังกายทั้งหมดในแผน "$name" จะถูกลบออก คุณจะต้องเพิ่มท่าใหม่ทั้งหมด'
        : 'แผน "$name" จะกลับสู่ท่าฝึกมาตรฐานของระบบ\nท่าที่คุณแก้ไขทั้งหมดจะหายไป';
    final confirm = await showAppConfirmDialog(
      context,
      icon: Icons.restore_rounded,
      title: 'รีเซ็ตแผนการฝึก',
      content: content,
      confirmLabel: 'รีเซ็ต',
    );
    if (!confirm) return;
    if (!mounted) return;
    await _submitReset(plan);
  }

  Future<void> _submitReset(Map<String, dynamic> plan) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final isCustom = plan['plan_type'] == 'custom';
    final result = await WorkoutService.to.resetPlan(
      wptId: isCustom ? null : plan['wpt_id'] as int,
      mwpId: isCustom ? plan['mwp_id'] as int : null,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      await _loadPlans();
      if (!mounted) return;
      showAppAlert(context, 'รีเซ็ตแผน "${plan['name']}" แล้ว', type: AppAlertType.success);
    } else {
      setState(() => _isLoading = false);
      final isNetworkError = result['network_error'] == true;
      showAppAlert(
        context,
        result['message'] ?? 'รีเซ็ตไม่สำเร็จ',
        type: AppAlertType.error,
        actionLabel: isNetworkError ? 'ลองใหม่' : null,
        onAction: isNetworkError ? () => _submitReset(plan) : null,
      );
    }
  }

  // ลบสำเนาแผนระบบที่ copy ไว้ในเครื่อง — แผนต้นฉบับที่แอดมินดูแลไม่หายไปไหน เลือกใหม่ได้เสมอ
  Future<void> _deleteSystemPlan(Map<String, dynamic> plan) async {
    final confirm = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'ลบแผนนี้ออกจากรายการ?',
      content: 'ท่าฝึกที่คุณคัดลอกมาจากแผน "${plan['name']}" จะถูกลบออกจากรายการของฉัน\n'
          '(แผนต้นฉบับในระบบยังอยู่ เลือกใหม่ได้เสมอ)',
      confirmLabel: 'ลบ',
    );
    if (!confirm) return;
    if (!mounted) return;
    await _submitDeleteSystemCopy(plan);
  }

  Future<void> _submitDeleteSystemCopy(Map<String, dynamic> plan) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final wasActive = plan['is_active'] == true;
    final result = await WorkoutService.to.deleteSystemPlanCopy(plan['wpt_id'] as int);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (result['success'] == true) {
      if (wasActive) WorkoutService.to.clearActivePlan();
      await _loadPlans();
      if (!mounted) return;
      if (wasActive) {
        showAppAlert(
          context,
          'ลบแผน "${plan['name']}" แล้ว (เป็นแผนที่ใช้งานอยู่ ตอนนี้ยังไม่มีแผนที่ใช้งาน)',
          type: AppAlertType.success,
        );
      }
    } else {
      final isNetworkError = result['network_error'] == true;
      showAppAlert(
        context,
        result['message'] ?? 'ลบไม่สำเร็จ',
        type: AppAlertType.error,
        actionLabel: isNetworkError ? 'ลองใหม่' : null,
        onAction: isNetworkError ? () => _submitDeleteSystemCopy(plan) : null,
      );
    }
  }

  Future<void> _showAddPlanSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text('เพิ่มแผนใหม่', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            onTap: () async {
              Navigator.pop(ctx);
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WorkoutDaysSelectionView()),
              );
              _loadPlans();
            },
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.view_list_rounded, color: AppColors.primaryGreen, size: 22),
            ),
            title: const Text('แผนของระบบ', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            subtitle: const Text('เลือกจากแผนสำเร็จรูปที่ระบบมีให้',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ),
          Divider(indent: 20, endIndent: 20, height: 1, color: Colors.grey.shade100),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            onTap: () {
              Navigator.pop(ctx);
              _createPersonalPlanFlow();
            },
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.cardioBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.edit_note_rounded, color: AppColors.cardioIcon, size: 22),
            ),
            title: const Text('สร้างแผนส่วนตัว', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            subtitle: const Text('ตั้งชื่อเอง กำหนดท่าฝึกได้อิสระ',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Future<void> _createPersonalPlanFlow() async {
    final controller = TextEditingController(text: 'แผนส่วนตัวของฉัน');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ตั้งชื่อแผน'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('สร้าง'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (!mounted) return;

    setState(() => _isLoading = true);
    final createResult = await WorkoutService.to.createPersonalPlan(name);
    if (!mounted) return;
    if (createResult['success'] != true) {
      setState(() => _isLoading = false);
      showAppAlert(context, createResult['message'] ?? 'สร้างแผนไม่สำเร็จ', type: AppAlertType.error);
      return;
    }

    final mwpId = createResult['mwp_id'] as int;
    final activateResult = await WorkoutService.to.activatePlan(mwpId: mwpId);
    if (!mounted) return;
    if (activateResult['success'] != true) {
      // สร้างแผนสำเร็จแต่ตั้ง active ไม่สำเร็จ (เช่น network error) — ห้ามพาเข้าหน้าแก้ตารางต่อ
      // เหมือนแผนนั้น active อยู่แล้ว เพราะ member_profile.mb_active_mwp_id ยังไม่ได้ชี้มาที่แผนนี้จริง
      setState(() => _isLoading = false);
      showAppAlert(context, activateResult['message'] ?? 'ตั้งแผนที่ใช้งานไม่สำเร็จ', type: AppAlertType.error);
      await _loadPlans();
      return;
    }
    await WorkoutService.to.saveActivePlan(mwpId, 7, name, type: 'custom', weekdayBased: true);
    setState(() => _isLoading = false);
    await _loadPlans();
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WeightTrainingScheduleView(
          planId: mwpId,
          dayNumber: DateTime.now().weekday,
          daysPerWeek: 7,
          planName: name,
          isCustomPlan: true,
          isWeekdayBased: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldGrey,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            AppPageHeader(
              title: 'แผนของฉัน',
              trailing: GestureDetector(
                onTap: _showAddPlanSheet,
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.add_rounded, color: Colors.black),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
    }
    if (_plans.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fitness_center_rounded, size: 56, color: AppColors.textMuted),
              const SizedBox(height: 14),
              const Text('ยังไม่มีแผนการฝึก',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textDark)),
              const SizedBox(height: 6),
              const Text('กดปุ่ม + เพื่อเลือกแผนระบบ หรือสร้างแผนส่วนตัว',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4)),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      itemCount: _plans.length,
      itemBuilder: (_, i) => _planCard(_plans[i]),
    );
  }

  // สี/ไอคอน/ป้ายกำกับ ต่างกัน 3 แบบ ให้ดูออกทันทีว่าแผนไหนเป็นแบบไหน:
  // แผนระบบเดิม (เขียว) / แผนระบบที่ปรับแต่งแล้ว (ส้ม) / แผนส่วนตัวที่สร้างเอง (ฟ้า)
  (IconData, Color, Color, String) _typeMeta(Map<String, dynamic> plan) {
    final isCustom = plan['plan_type'] == 'custom';
    if (isCustom) {
      return (Icons.edit_note_rounded, AppColors.cardioIcon, AppColors.cardioBg, 'แผนส่วนตัว');
    }
    if (plan['is_modified'] == true) {
      return (Icons.tune_rounded, AppColors.weightIcon, AppColors.weightBg, 'ปรับแต่งแล้ว');
    }
    return (Icons.view_list_rounded, AppColors.primaryGreen, AppColors.primaryGreen.withValues(alpha: 0.12), 'แผนของระบบ');
  }

  Widget _planCard(Map<String, dynamic> plan) {
    final isCustom = plan['plan_type'] == 'custom';
    final isActive = plan['is_active'] == true;
    final name = plan['name'] as String;
    final days = plan['days_per_week'] as int;
    final (icon, color, bg, typeLabel) = _typeMeta(plan);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isActive ? Border.all(color: color, width: 1.5) : null,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textDark),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.check_circle_rounded, color: color, size: 18),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _chip(typeLabel, color, bg),
                        _chip('$days วัน / สัปดาห์', AppColors.textMuted, AppColors.surfaceLight),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (!isActive)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _activate(plan),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    child: const Text('ใช้แผนนี้',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                )
              else
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('กำลังใช้งานอยู่',
                        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
              const SizedBox(width: 8),
              if (isCustom)
                _squareIconButton(Icons.edit_outlined, AppColors.textMuted, () => _rename(plan)),
              if (isCustom) const SizedBox(width: 6),
              // ปุ่มรีเซ็ทโผล่เฉพาะแผนที่มีอะไรให้รีเซ็ทจริง (ดู _canReset) — สีส้มแยกจากปุ่มลบสีแดง
              // ให้เห็นชัดว่าคนละระดับความรุนแรง (รีเซ็ท = คืนท่ากลับมาตรฐาน, ลบ = หายทั้งแผน)
              if (_canReset(plan)) ...[
                _squareIconButton(Icons.restore_rounded, AppColors.weightIcon, () => _resetPlan(plan)),
                const SizedBox(width: 6),
              ],
              _squareIconButton(Icons.delete_outline_rounded, Colors.red,
                  () => isCustom ? _delete(plan) : _deleteSystemPlan(plan)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color fg, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
  );

  Widget _squareIconButton(IconData icon, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 42, height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 19, color: color),
    ),
  );
}
