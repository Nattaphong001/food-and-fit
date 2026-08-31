// หน้า: Workout Days Selection
// ทำหน้าที่: หน้าเลือกจำนวนวันและวันออกกำลังกายต่อสัปดาห์ ใช้ในขั้นตอนการตั้งค่าแผนการฝึก

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../services/api_client.dart';
import '../../../services/workout_service.dart';
import 'weight_training_schedule_view.dart';

class WorkoutDaysSelectionView extends StatefulWidget {
  const WorkoutDaysSelectionView({super.key});

  @override
  State<WorkoutDaysSelectionView> createState() => _WorkoutDaysSelectionViewState();
}

class _WorkoutDaysSelectionViewState extends State<WorkoutDaysSelectionView> {
  bool _isLoading = true; // เริ่มต้นเป็น true เพื่อโหลดข้อมูลแผน
  List<dynamic> _planTemplates = []; // เก็บแผนที่ดึงมาจาก API

  @override
  void initState() {
    super.initState();
    _fetchPlanTemplates();
  }

  // ดึงข้อมูลแผนทั้งหมดจาก Database
  Future<void> _fetchPlanTemplates() async {
    setState(() => _isLoading = true);
    try {
      final List<dynamic> templates = await WorkoutService.to.getPlanTemplates();
      
      if (!mounted) return;

      setState(() {
        _planTemplates = templates;
        _isLoading = false;
      });

      if (templates.isEmpty) {
        debugPrint("⚠️ ข้อมูลจาก API ว่างเปล่า");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint("❌ Error fetching templates: $e");
    }
  }

  Future<void> _confirmAndSelectPlan(
    int wptId,
    int days,
    String title,
    String imageUrl,
    String description,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.hardEdge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: รูปปกแผนจริง แทน icon เดา ให้เห็นว่ากำลังจะเลือกแผนไหน
            Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: 150,
                  decoration: BoxDecoration(
                    image: DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover),
                  ),
                ),
                Container(
                  width: double.infinity,
                  height: 150,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                    ),
                  ),
                ),
                Positioned(
                  left: 20, right: 20, bottom: 14,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
                  ),
                ),
              ],
            ),
            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.primaryGreen),
                      const SizedBox(width: 8),
                      Text('$days วัน / สัปดาห์',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textDark)),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      description,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.textBody, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: const Text('ยกเลิก',
                          style: TextStyle(color: AppColors.textBody, fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('ใช้แผนนี้',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    await _selectPlan(wptId, days, title);
  }

  Future<void> _selectPlan(int wptId, int days, String title) async {
    if (_isLoading) return; // กันกดซ้ำ
    setState(() => _isLoading = true);
    final result = await WorkoutService.to.selectPlan(wptId);
    if (!mounted) return;

    if (result['success'] != true) {
      setState(() => _isLoading = false);
      final isNetworkError = result['network_error'] == true;
      showAppAlert(
        context,
        result['message'] ?? 'เลือกแผนไม่สำเร็จ',
        type: AppAlertType.error,
        actionLabel: isNetworkError ? 'ลองใหม่' : null,
        onAction: isNetworkError ? () => _selectPlan(wptId, days, title) : null,
      );
      return;
    }

    await WorkoutService.to.saveActivePlan(wptId, days, title, type: 'system', weekdayBased: false);
    if (!mounted) return;
    setState(() => _isLoading = false);

    showAppAlert(context, 'เริ่มใช้แผน "$title" แล้ว', type: AppAlertType.success);

    final dayNumber = WorkoutService.dayNumberForWeekday(DateTime.now(), days);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => WeightTrainingScheduleView(
          planId: wptId,
          dayNumber: dayNumber,
          daysPerWeek: days,
          planName: title,
          isCustomPlan: false,
          isWeekdayBased: false,
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldGrey,
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440),
                child: CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      floating: false,
                      backgroundColor: AppColors.scaffoldGrey,
                      elevation: 0,
                      leadingWidth: 70,
                      leading: Padding(
                        padding: const EdgeInsets.only(left: 20),
                        child: Center(child: AppBackButton()),
                      ),
                      title: Text(
                        'เลือกจำนวนวันที่ต้องการฝึก',
                        style: AppTextStyles.pageTitle,
                      ),
                      centerTitle: false,
                    ),

                    // กรณีโหลดข้อมูลเสร็จแล้วแต่ไม่มีข้อมูลแผน
                    if (!_isLoading && _planTemplates.isEmpty)
                      const SliverFillRemaining(
                        child: Center(
                          child: Text(
                            'ไม่พบแผนการฝึกในระบบ',
                            style: TextStyle(fontFamily: 'Inter', fontSize: 16, color: AppColors.textBody),
                          ),
                        ),
                      )
                    
                    // แสดงข้อมูลที่โหลดมาจาก Database
                    else if (_planTemplates.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.only(top: 20, bottom: 40),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final plan = _planTemplates[index];
                              final int days = plan['wpt_days_per_week'] ?? plan['plan_days_per_week'] ?? 3;
                              final int wptId = plan['wpt_id'] ?? plan['plan_id'];

                              return _buildWorkoutSection(
                                wptId: wptId,
                                days: days,
                                imagePath: plan['wpt_image'] ?? '',
                                title: plan['wpt_name'] ?? plan['plan_name'] ?? 'แผนการฝึก',
                                daysText: '$days วัน / สัปดาห์',
                                description: plan['wpt_description'] ?? plan['plan_description'] ?? 'บริหารร่างกายตามตารางที่จัดไว้ให้',
                                hasBorder: true,
                                showBottomLine: index < _planTemplates.length - 1,
                              );
                            },
                            childCount: _planTemplates.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Loading overlay (แสดงทั้งตอนโหลดหน้าแรกและตอนกดเลือกแผน)
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primaryGreen),
                    SizedBox(height: 16),
                    Text('กำลังโหลดข้อมูล...',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWorkoutSection({
    required int wptId,
    required int days,
    required String imagePath,
    required String title,
    required String daysText,
    required String description,
    required bool hasBorder,
    required bool showBottomLine,
  }) {
    final imageUrl = '${ApiClient.serverUrl}/$imagePath';

    return Column(
      children: [
        GestureDetector(
          onTap: _isLoading ? null : () => _confirmAndSelectPlan(wptId, days, title, imageUrl, description),
          child: Container(
            width: 389,
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      height: 191,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        border: hasBorder ? Border.all(color: Colors.black.withValues(alpha: 0.1)) : null,
                        boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.1), offset: Offset(0, 4), blurRadius: 10)],
                        image: DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      height: 191,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 15, bottom: 15,
                      child: Text(title,
                          style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white)),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFF00F28A)),
                    const SizedBox(width: 8),
                    Text(daysText,
                        style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 18, color: Colors.black)),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    description,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.textBody, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showBottomLine)
          Container(
            width: 300,
            height: 2,
            margin: const EdgeInsets.symmetric(vertical: 25),
            color: AppColors.accentGreen.withValues(alpha: 0.3),
          ),
      ],
    );
  }
}