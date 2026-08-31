import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/cached_image.dart';
import '../../../core/widgets/app_date_picker_sheet.dart';
import '../../../core/widgets/weekly_calendar_component.dart';
import '../../../core/widgets/sticky_filter_chip_bar.dart';
import '../../../core/widgets/swipe_delete_item.dart';
import '../../../core/widgets/undo_snackbar.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../models/exercise_model.dart';
import '../../../models/workout_model.dart';
import '../../../services/exercise_service.dart';
import '../../../services/workout_service.dart';
import '../../../services/api_client.dart';
import 'weight_training_schedule_view.dart';
import 'cardio_activity_view.dart';
import 'my_workout_plans_view.dart';
import 'workout_days_selection_view.dart';

class WorkoutView extends StatefulWidget {
  final ValueNotifier<int>? dashboardRefreshNotifier;
  const WorkoutView({super.key, this.dashboardRefreshNotifier});

  @override
  State<WorkoutView> createState() => _WorkoutViewState();
}

class _WorkoutViewState extends State<WorkoutView> with RouteAware {
  DateTime _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  List<WorkoutResult> _weightResults = [];
  List<CardioResult> _cardioResults = [];
  Map<int, Exercise> _exerciseMap = {};
  Map<int, CardioType> _cardioTypeMap = {};
  bool _isLoading = false;
  String _activityFilter = 'ทั้งหมด';
  final Set<String> _pendingDeleteKeys = {}; // รายการที่กำลังรอ undo หลังปัดลบ

  // plan info อ่านจาก storage ผ่าน WorkoutService
  int? _activePlanId;
  int _activePlanDays = 3;
  String _activePlanName = '';
  String _activePlanType = 'system'; // 'system' | 'copied' | 'custom'
  bool _activePlanIsWeekdayBased = false;
  Set<int> _workoutWeekdays = {}; // 0=จันทร์ … 6=อาทิตย์

  @override
  void initState() {
    super.initState();
    _loadActivePlan();
    _loadTodayActivities();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) undoRouteObserver.subscribe(this, route);
  }

  // มีหน้าอื่นถูกดันมาบังหน้านี้ (เช่นแตะเข้าไปดูตารางฝึกหลังปัดลบกิจกรรมทิ้ง) — commit การลบ
  // ที่ค้าง undo อยู่ทันที กัน toast ลอยตามไปโผล่ทับหน้าถัดไป (Overlay entry ไม่ผูกกับ route เลย
  // ปล่อยไว้จะค้างจนกว่าจะหมดเวลาเองหรือถูกปัดทิ้งเอง)
  @override
  void didPushNext() => commitPendingUndo();

  @override
  void dispose() {
    undoRouteObserver.unsubscribe(this);
    commitPendingUndo(); // ออกจากหน้านี้ไปเลย (กดย้อนกลับ) ก็ commit ทันทีเหมือนกัน
    super.dispose();
  }

  Future<void> _loadActivePlan() async {
    final svc = WorkoutService.to;
    // ดึงจาก server ทุกครั้ง (ไม่ใช่แค่ตอน storage ว่าง) — กันชื่อ/จำนวนวันฝึกที่โชว์ค้างจากแคช
    // เก่าเมื่อแอดมินแก้ไขแผนระบบภายหลัง (เปลี่ยนชื่อ/จำนวนวัน)
    await svc.refreshActivePlanFromServer();
    if (!mounted) return;
    setState(() {
      _activePlanId = svc.activePlanId;
      _activePlanDays = svc.activePlanDays;
      _activePlanName = svc.activePlanName;
      _activePlanType = svc.activePlanType;
      _activePlanIsWeekdayBased = svc.activePlanIsWeekdayBased;
    });
    _loadWeekdayStatus();
  }

  Future<void> _loadWeekdayStatus() async {
    if (!_hasPlan || _activePlanId == null) {
      if (mounted) setState(() => _workoutWeekdays = {});
      return;
    }
    // ดึงจาก workout_schedules (แหล่งข้อมูลจริง) ทุก plan type
    final result = await WorkoutService.to.getAllSchedulesForPlan(_activePlanId!, isCustom: _activePlanType == 'custom');
    if (!mounted) return;
    if (result['success'] == true) {
      final schedules = (result['data'] as List).cast<UserWorkoutSchedule>();
      // dayNumber 1=จันทร์..7=อาทิตย์ → weekday index 0..6
      setState(() {
        _workoutWeekdays = schedules
            .where((s) => s.dayNumber > 0)
            .map((s) => s.dayNumber - 1)
            .toSet();
      });
    } else {
      setState(() => _workoutWeekdays = {});
    }
  }

  bool get _hasPlan => _activePlanId != null;

  // ห้ามเลือกวันในอนาคต — เหมือนกฎในหน้าอาหาร
  bool _isDateDisabled(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final today = DateTime.now();
    return d.isAfter(DateTime(today.year, today.month, today.day));
  }

  int get _planDayNumber {
    if (_activePlanIsWeekdayBased) return _selectedDate.weekday;
    return WorkoutService.dayNumberForWeekday(_selectedDate, _activePlanDays);
  }

  Future<void> _loadTodayActivities() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      WorkoutService.to.getWorkoutResults(date: _selectedDate),
      WorkoutService.to.getCardioResults(date: _selectedDate),
      ExerciseService.to.getWeightExercises(),
      ExerciseService.to.getCardioActivities(),
    ]);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (results[0]['success'] == true) {
        _weightResults = results[0]['data'] as List<WorkoutResult>;
      }
      if (results[1]['success'] == true) {
        _cardioResults = results[1]['data'] as List<CardioResult>;
      }
      if (results[2]['success'] == true) {
        final exercises = results[2]['data'] as List<Exercise>;
        _exerciseMap = {for (final e in exercises) e.exerciseId: e};
      }
      if (results[3]['success'] == true) {
        final cardioTypes = results[3]['data'] as List<CardioType>;
        _cardioTypeMap = {for (final c in cardioTypes) c.typeId: c};
      }
    });
    widget.dashboardRefreshNotifier?.value++;
  }

  double get _weightKcal => _weightResults.fold(0.0, (sum, r) => sum + r.calories);
  double get _cardioKcal => _cardioResults.fold(0.0, (sum, r) => sum + r.caloriesBurned);

  int get _totalKcal => (_weightKcal + _cardioKcal).round();

  // เปิดหน้า "แผนของฉัน" — รวมทุกแผน (ระบบที่เคยเลือก + ส่วนตัว) เลือก/แก้/ลบแผนได้จากหน้านั้น
  // ใช้ตอน "เปลี่ยนแผน" (มีแผนอยู่แล้ว อยากสลับ/จัดการ) — ต่างจาก _selectNewPlan ที่ข้ามหน้านี้ไปเลย
  Future<void> _openMyPlans() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyWorkoutPlansView()),
    );
    if (!mounted) return;
    _loadActivePlan();
    _loadTodayActivities();
  }

  // ยังไม่มีแผน active เลย → ข้าม MyWorkoutPlansView ไปเลย แต่ยังต้องให้เลือกได้ว่า
  // จะเอาแผนระบบหรือสร้างแผนเอง (บั๊กเดิม: ข้ามตรงไป WorkoutDaysSelectionView ซึ่งมีแต่ลิสต์
  // แผนระบบ ไม่มีตัวเลือก "สร้างแผนส่วนตัว" เลย ทำให้ครั้งแรกกดแล้วไม่เห็นทางเลือกนี้)
  Future<void> _selectNewPlan() async {
    await _showAddPlanSheet();
  }

  // ชีทเลือกประเภทแผน — เนื้อหา/โครงเดียวกับ _showAddPlanSheet ใน my_workout_plans_view.dart
  // (คัดลอกมาเพราะฝั่งนั้นเป็น private method ของอีก State ดึงมาเรียกตรงไม่ได้)
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
            child: Text('เลือกแผนการฝึก', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
              if (!mounted) return;
              _loadActivePlan();
              _loadTodayActivities();
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

  // สร้างแผนส่วนตัว + ตั้งเป็นแผน active ทันที — ก็อปโฟลว์จาก my_workout_plans_view.dart
  // (_createPersonalPlanFlow) ตัดส่วน setState(_isLoading) ออกเพราะ _isLoading ของหน้านี้
  // ผูกกับสปินเนอร์ในลิสต์กิจกรรมวันนี้ ไม่ใช่ full-screen overlay แบบหน้านั้น
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

    final createResult = await WorkoutService.to.createPersonalPlan(name);
    if (!mounted) return;
    if (createResult['success'] != true) {
      showAppAlert(context, createResult['message'] ?? 'สร้างแผนไม่สำเร็จ', type: AppAlertType.error);
      return;
    }

    final mwpId = createResult['mwp_id'] as int;
    final activateResult = await WorkoutService.to.activatePlan(mwpId: mwpId);
    if (!mounted) return;
    if (activateResult['success'] != true) {
      // สร้างแผนสำเร็จแต่ตั้ง active ไม่สำเร็จ (เช่น network error) — ห้ามพาเข้าหน้าแก้ตารางต่อ
      // เหมือนแผนนั้น active อยู่แล้ว เพราะ member_profile.mb_active_mwp_id ยังไม่ได้ชี้มาที่แผนนี้จริง
      showAppAlert(context, activateResult['message'] ?? 'ตั้งแผนที่ใช้งานไม่สำเร็จ', type: AppAlertType.error);
      _loadActivePlan();
      _loadTodayActivities();
      return;
    }
    await WorkoutService.to.saveActivePlan(mwpId, 7, name, type: 'custom', weekdayBased: true);
    if (!mounted) return;
    _loadActivePlan();
    _loadTodayActivities();

    await Navigator.push(
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

  void _startWeightTraining() {
    if (!_hasPlan) {
      _selectNewPlan();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WeightTrainingScheduleView(
          planId: _activePlanId!,
          dayNumber: _planDayNumber,
          daysPerWeek: _activePlanDays,
          planName: _activePlanName,
          isCustomPlan: _activePlanType == 'custom' || _activePlanType == 'copied',
          isWeekdayBased: _activePlanIsWeekdayBased,
        ),
      ),
    ).then((_) {
      _loadWeekdayStatus();
      _loadTodayActivities();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // โปร่งใส — ให้พื้นหลังร่วมของ MainShell โชว์ผ่านตลอด กัน navbar เห็นแต่สีทึบเรียบๆ
      backgroundColor: Colors.transparent,
      // bottom: false — extendBody อัด MediaQuery.padding.bottom เท่าความสูง navbar มาให้ SafeArea
      // กิน ถ้าไม่ปิด content จะหดขึ้นไปหยุดเหนือ navbar เสมอ (extendBody เลยไม่มีผลอะไรเลย)
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ApiClient.clearCache();
            await _loadTodayActivities();
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(
                child: WeeklyCalendarComponent(
                  selectedDate: _selectedDate,
                  isDisabled: _isDateDisabled,
                  // จุดเขียว-ขาวบนปฏิทินแถบบนสุด — เดิมไม่เคยส่ง activeDays เลยตั้งแต่แรก
                  // (คนละจุดกับวงกลม 7 วันในการ์ดแผนด้านล่าง ที่ผูกกับ _workoutWeekdays อยู่แล้ว)
                  // เลยไม่เคยขึ้นจุดเลยไม่ว่าจะเพิ่ม/ลบท่าไปกี่ครั้ง — แปลง 0-based (จันทร์=0)
                  // เป็น 1-based (จันทร์=1..อาทิตย์=7) ตาม DateTime.weekday ที่ widget ใช้เทียบ
                  activeDays: _workoutWeekdays.map((d) => d + 1).toSet(),
                  onDaySelected: (date) {
                    setState(() {
                      _selectedDate = date;
                      _activityFilter = 'ทั้งหมด'; // ล้างตัวกรองเดิม กันเลือกประเภทที่วันใหม่ไม่มีรายการ
                    });
                    _loadTodayActivities();
                  },
                ),
              ),
              SliverToBoxAdapter(child: _buildPlanCard()),
              SliverToBoxAdapter(child: _buildWorkoutTypesSection()),
              SliverToBoxAdapter(child: _buildActivityLogHeader()),
              if (_weightResults.isNotEmpty || _cardioResults.isNotEmpty)
                stickyFilterChipSliver<String>(
                  items: [
                    const FilterChipItem(id: 'ทั้งหมด', label: 'ทั้งหมด'),
                    if (_weightResults.isNotEmpty)
                      const FilterChipItem(id: 'เวทเทรนนิ่ง', label: 'เวทเทรนนิ่ง'),
                    if (_cardioResults.isNotEmpty)
                      const FilterChipItem(id: 'คาร์ดิโอ', label: 'คาร์ดิโอ'),
                  ],
                  selectedId: _activityFilter,
                  onSelected: (f) => setState(() => _activityFilter = f),
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                ),
              SliverToBoxAdapter(child: _buildActivityList()),
              const SliverToBoxAdapter(child: SizedBox(height: 104)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text('ตารางฝึกของฉัน',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          ),
          GestureDetector(
            onTap: () async {
              final picked = await showAppCalendarPicker(
                context,
                initialDate: _selectedDate,
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() {
                  _selectedDate = picked;
                  _activityFilter = 'ทั้งหมด';
                });
                _loadTodayActivities();
              }
            },
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
              ),
              child: const Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.primaryGreen),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard() {
    if (!_hasPlan) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 25, 22, 0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ยังไม่มีแผนการฝึก',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Colors.black)),
              const SizedBox(height: 8),
              const Text('เลือกแผนการฝึกที่เหมาะกับคุณเพื่อเริ่มต้นออกกำลังกาย',
                  style: TextStyle(fontSize: 14, color: AppColors.textBody, height: 1.4)),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _selectNewPlan,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('เลือกแผนการฝึก',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.black)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isRestDay = _workoutWeekdays.isNotEmpty &&
        !_workoutWeekdays.contains(_selectedDate.weekday - 1);
    final (typeIcon, typeColor, typeBg, typeLabel) = _activePlanTypeMeta;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ส่วนบน: กดแล้วเข้าตาราง
            GestureDetector(
              onTap: _startWeightTraining,
              child: Container(
                color: Colors.transparent,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(color: typeBg, borderRadius: BorderRadius.circular(12)),
                          child: Icon(typeIcon, color: typeColor, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _activePlanName.isNotEmpty ? _activePlanName : '$_activePlanDays วัน / สัปดาห์',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textDark),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              // badge ประเภทแผน + จำนวนวันฝึก — ภาษาเดียวกับหน้า "แผนของฉัน"
                              // ให้จำได้ว่าสีนี้ = แผนแบบนี้ ไม่ว่าจะเจอที่หน้าไหน
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _planChip(typeLabel, typeColor, typeBg),
                                  _planChip(
                                    _activePlanIsWeekdayBased ? 'จ-อา' : '$_activePlanDays วัน / สัปดาห์',
                                    AppColors.textMuted,
                                    AppColors.surfaceLight,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
                      ],
                    ),
                    if (_workoutWeekdays.isNotEmpty || _activePlanIsWeekdayBased) ...[
                      const SizedBox(height: 16),
                      _buildWeekdayRow(),
                    ],
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isRestDay ? Colors.blue.shade50 : AppColors.primaryGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isRestDay ? Icons.self_improvement_rounded : Icons.bolt_rounded,
                            size: 16,
                            color: isRestDay ? Colors.blue.shade400 : AppColors.primaryGreen,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isRestDay
                                  ? 'วันนี้เป็นวันพัก ให้ร่างกายฟื้นฟู'
                                  : 'กดเพื่อดูตารางฝึกวันนี้',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isRestDay ? Colors.blue.shade600 : AppColors.primaryGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ส่วนล่าง: ปุ่มเดียว "เปลี่ยนแผน" — เข้าหน้า "แผนของฉัน" ไปสลับ/จัดการ/รีเซ็ตแผนต่อได้ที่นั่น
            // (ตัดปุ่มรีเซ็ทออกจากการ์ดหน้าแรกนี้แล้ว เพราะเป็น action ทำลายข้อมูลที่ไม่ควรโผล่ถาวร
            // ให้เห็นทุกครั้งที่เปิดแท็บ — ย้ายไปอยู่ต่อรายการแผนแต่ละแผนในหน้า "แผนของฉัน" แทน)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openMyPlans,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('เปลี่ยนแผน', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textDark,
                    backgroundColor: AppColors.surfaceLight,
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // เขียว='แผนของระบบ, ฟ้า='แผนส่วนตัว — คู่สีเดียวกับ _typeMeta ในหน้า "แผนของฉัน"
  // (ไม่แยกสถานะ "ปรับแต่งแล้ว" ที่นี่ เพราะการ์ดนี้ไม่ได้โหลด is_modified มาเก็บ ไปดูรายละเอียด
  // ระดับนั้นที่หน้า "แผนของฉัน" แทน)
  (IconData, Color, Color, String) get _activePlanTypeMeta {
    if (_activePlanType == 'custom') {
      return (Icons.edit_note_rounded, AppColors.cardioIcon, AppColors.cardioBg, 'แผนส่วนตัว');
    }
    return (Icons.view_list_rounded, AppColors.primaryGreen, AppColors.primaryGreen.withValues(alpha: 0.12), 'แผนของระบบ');
  }

  Widget _planChip(String label, Color fg, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
  );

  Widget _buildWeekdayRow() {
    const labels = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];
    final todayIdx = DateTime.now().weekday - 1; // 0=จันทร์..6=อาทิตย์
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(7, (i) {
        final isWorkout = _workoutWeekdays.contains(i);
        final isToday = i == todayIdx;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: isWorkout ? AppColors.primaryGreen : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isToday && !isWorkout
                      ? AppColors.primaryGreen
                      : isWorkout
                          ? Colors.transparent
                          : AppColors.divider,
                  width: isToday && !isWorkout ? 2 : 1,
                ),
              ),
              child: Center(
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isWorkout || isToday ? FontWeight.w700 : FontWeight.w500,
                    color: isWorkout
                        ? Colors.black87
                        : isToday
                            ? AppColors.primaryGreen
                            : AppColors.textMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 4, height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isWorkout
                    ? AppColors.primaryGreen
                    : Colors.transparent,
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildWorkoutTypesSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('แคลอรี่ที่เผาผลาญ',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20, color: AppColors.textDark)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.weightBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('🔥 $_totalKcal Kcal',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.weightIcon)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildWorkoutTypeCard(
            title: 'เวทเทรนนิ่ง',
            iconAsset: 'assets/images/icon_weight_dumbbell.png',
            bgColor: AppColors.weightBg,
            iconColor: AppColors.weightIcon,
            onTap: _startWeightTraining,
          ),
          const SizedBox(height: 16),
          _buildWorkoutTypeCard(
            title: 'คาร์ดิโอ',
            iconAsset: 'assets/images/icon_cardio_running_shoe.png',
            bgColor: AppColors.cardioBg,
            iconColor: AppColors.cardioIcon,
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const CardioActivityView()));
              _loadTodayActivities();
            },
          ),
        ],
      ),
    );
  }

  // วางภาพไอคอนซ้อน 2 ชั้น: ชั้นล่างเบลอ+จาง (เงา) เยื้องลงนิดนึง, ชั้นบนคือภาพจริงคมชัด —
  // หลอกตาว่าไอคอนลอยเหนือบล็อกสี (แทน Icon.shadows เดิมที่ใช้กับ Material Icon ไม่ได้กับภาพ asset)
  // tint สีด้วย BlendMode.srcIn ทั้งคู่ ใช้ alpha ของภาพต้นฉบับเป็น mask ล้วนๆ ไม่สนสีเดิมของไฟล์
  Widget _liftedIconArtwork(String asset, Color color, double size) {
    return Transform.rotate(
      angle: -0.18,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0, top: 10,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Opacity(
                opacity: 0.35,
                child: Image.asset(asset, width: size, height: size, color: color, colorBlendMode: BlendMode.srcIn),
              ),
            ),
          ),
          Image.asset(asset, width: size, height: size, color: color, colorBlendMode: BlendMode.srcIn),
        ],
      ),
    );
  }

  // การ์ดประเภทออกกำลังกาย — เล่นมิติความลึกด้วยภาพ line icon โปร่งใส (assets/images/icon_weight_dumbbell.png,
  // icon_cardio_running_shoe.png — ดาวน์โหลดจาก IconScout ฟรีไลเซนส์ ไม่ต้อง attribution เช็คแล้วจริง):
  // บล็อกสีขอบขวาโค้งมนไล่เข้าพื้นขาว (ไม่ตัดตรงแบ่งครึ่งแบบเดิม) + ไอคอนขนาดใหญ่เอียงเล็กน้อย
  // ใส่เงานุ่มๆ ให้ตัวไอคอนเอง (ดู _liftedIconArtwork) หลอกตาว่าลอยเหนือบล็อกสี + ล้นขอบบล็อกออกมานิดนึง
  // ให้ความรู้สึก "ทะลุกรอบ" ตาม concept ที่ขอมา — สลับไทเทิลเดิม เปลี่ยนเป็นสถิติวันนี้จริงแทน
  // (จำนวนท่า/ครั้ง + kcal) ให้มีข้อมูลจริงมากกว่าป้ายชื่อเฉยๆ
  Widget _buildWorkoutTypeCard({
    required String title,
    required String iconAsset,
    required Color bgColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    const double cardHeight = 112;
    const double colorBlockWidth = 128;
    const double iconSize = 84;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: cardHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                // บล็อกสีฝั่งซ้าย — ขอบขวาโค้งมนลึก ไล่เข้าพื้นขาวแทนการตัดตรงแบ่งครึ่งจอ
                Positioned(
                  left: 0, top: 0, bottom: 0,
                  width: colorBlockWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(56)),
                    ),
                  ),
                ),
                // ไอคอนใหญ่เอียงเล็กน้อย + เงาลอยตัว ล้นขอบบล็อกสีออกมาทางขวานิดนึง
                // ภาพเส้น (line icon, PNG โปร่งใส) โหลดจาก IconScout ฟรีไลเซนส์ — เช็คแล้วจาก
                // JSON metadata ของหน้าโปรดักต์จริง attribution_required=false ไม่ต้องเครดิต
                Positioned(
                  left: colorBlockWidth - 70,
                  top: (cardHeight - iconSize) / 2,
                  child: _liftedIconArtwork(iconAsset, iconColor, iconSize),
                ),
                // ข้อความ: หัวข้อ + สถิติวันนี้จริง
                Positioned(
                  left: colorBlockWidth + 20, right: 56, top: 0, bottom: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textDark)),
                  ),
                ),
                // ปุ่มวงกลม CTA ขอบขวา กึ่งกลางแนวตั้งของการ์ด
                Positioned(
                  right: 14, top: 0, bottom: 0,
                  child: Center(child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: iconColor,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: iconColor.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 17),
                  )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // จำนวน exercise groups (ไม่ใช่จำนวน sets)
  int get _weightGroupCount {
    final seen = <int>{};
    for (final r in _weightResults) { seen.add(r.exerciseId); }
    return seen.length;
  }

  Widget _buildActivityLogHeader() {
    final total = _activityFilter == 'เวทเทรนนิ่ง'
        ? _weightGroupCount
        : _activityFilter == 'คาร์ดิโอ'
            ? _cardioResults.length
            : _weightGroupCount + _cardioResults.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 20, 30, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('รายการบันทึกกิจกรรมวันนี้',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          Text('$total รายการ',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.primaryGreen)),
        ],
      ),
    );
  }

  Widget _buildActivityList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
      );
    }

    final allEmpty = _weightResults.isEmpty && _cardioResults.isEmpty;
    if (allEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Text('ยังไม่มีกิจกรรมในวันนี้\nกด "เริ่ม" เพื่อออกกำลังกาย!',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 15, height: 1.5)),
        ),
      );
    }

    // Group weight results by exerciseId
    final Map<int, List<WorkoutResult>> grouped = {};
    for (final r in _weightResults) {
      grouped.putIfAbsent(r.exerciseId, () => []).add(r);
    }

    final widgets = <Widget>[];
    if (_activityFilter != 'คาร์ดิโอ') {
      for (final entry in grouped.entries.toList().reversed) {
        final exerciseId = entry.key;
        final sets = entry.value;
        final key = 'weight_$exerciseId';
        if (_pendingDeleteKeys.contains(key)) continue;
        widgets.add(SwipeDeleteItem(
          itemKey: Key('${key}_${sets.first.date}'),
          background: _dismissBg(),
          onDismissed: () => _handleWeightSwipeDelete(exerciseId, sets),
          child: _buildWeightGroupItem(exerciseId, sets),
        ));
      }
    }
    if (_activityFilter != 'เวทเทรนนิ่ง') {
      for (final r in _cardioResults.reversed) {
        final key = 'cardio_${r.resultId}';
        if (_pendingDeleteKeys.contains(key)) continue;
        widgets.add(SwipeDeleteItem(
          itemKey: Key(key),
          background: _dismissBg(),
          onDismissed: () => _handleCardioSwipeDelete(r),
          child: _buildCardioActivityItem(r),
        ));
      }
    }

    return Column(children: widgets);
  }

  // User > ลบรายการผลออกกำลังกายประจำวัน: บัคเก็ตเดียวกับลบรายการอาหารประจำวัน — ลบได้เลย
  // ไม่ต้องยืนยันก่อน ซ่อนออกจากลิสต์ทันทีแล้วรอหน้าต่าง undo ปิดก่อนค่อยยิงลบจริง
  void _handleWeightSwipeDelete(int exerciseId, List<WorkoutResult> sets) {
    final key = 'weight_$exerciseId';
    setState(() => _pendingDeleteKeys.add(key));
    showUndoSnackbar(
      context,
      message: 'ลบรายการเวทเทรนนิ่งแล้ว',
      onUndo: () {
        if (!mounted) return;
        setState(() => _pendingDeleteKeys.remove(key));
      },
      onExpire: () async {
        await _deleteWeightGroup(exerciseId, sets);
        if (!mounted) return;
        setState(() => _pendingDeleteKeys.remove(key));
      },
    );
  }

  void _handleCardioSwipeDelete(CardioResult r) {
    final key = 'cardio_${r.resultId}';
    setState(() => _pendingDeleteKeys.add(key));
    showUndoSnackbar(
      context,
      message: 'ลบรายการคาร์ดิโอแล้ว',
      onUndo: () {
        if (!mounted) return;
        setState(() => _pendingDeleteKeys.remove(key));
      },
      onExpire: () async {
        await _deleteCardioItem(r);
        if (!mounted) return;
        setState(() => _pendingDeleteKeys.remove(key));
      },
    );
  }

  Widget _buildWeightGroupItem(int exerciseId, List<WorkoutResult> sets) {
    final ex = _exerciseMap[exerciseId];
    final name = sets.first.exerciseName ?? ex?.exerciseName ?? 'เวทเทรนนิ่ง';
    final imageUrl = sets.first.imageUrl ?? ex?.imageUrl;
    final totalCalories = sets.fold(0.0, (sum, r) => sum + r.calories);
    final totalReps = sets.fold(0, (sum, r) => sum + r.reps);

    return GestureDetector(
      onTap: () => _showWeightSetsSheet(sets, name, imageUrl),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            Container(
              width: 55, height: 55,
              decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.antiAlias,
              child: (imageUrl != null && imageUrl.isNotEmpty)
                  ? cachedImage(imageUrl, fit: BoxFit.cover)
                  : const Icon(Icons.fitness_center, color: Colors.black54),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.weightBg, borderRadius: BorderRadius.circular(6)),
                        child: const Text('เวท', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.weightIcon)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _chip('${sets.length} เซ็ต'),
                      _chip('$totalReps ครั้งรวม'),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${totalCalories.round()} kcal',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('รายละเอียด', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    Icon(Icons.chevron_right_rounded, size: 14, color: AppColors.textMuted),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardioActivityItem(CardioResult r) {
    final ct = _cardioTypeMap[r.cardioTypeId];
    final name = r.cardioTypeName ?? ct?.typeName ?? 'คาร์ดิโอ';
    final imageUrl = r.imageUrl ?? ct?.imageUrl;

    return GestureDetector(
      onTap: () => _showCardioDetailSheet(r, name, imageUrl),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            Container(
              width: 55, height: 55,
              decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.antiAlias,
              child: (imageUrl != null && imageUrl.isNotEmpty)
                  ? cachedImage(imageUrl, fit: BoxFit.cover)
                  : const Icon(Icons.directions_run, color: Colors.black54),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.cardioBg, borderRadius: BorderRadius.circular(6)),
                        child: const Text('คาร์ดิโอ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.cardioIcon)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _chip('${r.duration.round()} นาที'),
                      if (r.distance > 0) _chip('${r.distance.toStringAsFixed(1)} กม.'),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${r.caloriesBurned.round()} kcal',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('รายละเอียด', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    Icon(Icons.chevron_right_rounded, size: 14, color: AppColors.textMuted),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text) => Container(
    margin: const EdgeInsets.only(right: 5),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10)),
  );

  void _showWeightSetsSheet(List<WorkoutResult> sets, String name, String? imageUrl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final totalCalories = sets.fold(0.0, (sum, r) => sum + r.calories);
        final totalVolume = sets.fold(0.0, (sum, r) => sum + r.weight * r.reps);
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
                    clipBehavior: Clip.antiAlias,
                    child: (imageUrl != null && imageUrl.isNotEmpty)
                        ? cachedImage(imageUrl, fit: BoxFit.cover)
                        : const Icon(Icons.fitness_center, color: Colors.black54),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                        Text(
                          '${sets.length} เซ็ต • ${totalCalories.round()} kcal • Volume ${totalVolume.round()} กก.',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              // Header — 3 คอลัมน์ Expanded เท่ากันหมด (1:1:1) ให้แต่ละคอลัมน์กึ่งกลางในพื้นที่
              // ของตัวเองจริง แทนที่ "เซ็ต" จะเป็นกล่องขนาดคงที่ปักซ้ายเหมือนเดิม (ทำให้ทั้งแถวเอียงซ้าย)
              const Row(
                children: [
                  Expanded(child: Text('เซ็ต', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textMuted))),
                  Expanded(child: Text('ครั้ง', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textMuted))),
                  Expanded(child: Text('น้ำหนัก (กก.)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textMuted))),
                ],
              ),
              const SizedBox(height: 4),
              ...sets.map((s) => _buildSetRow(s)),
            ],
          ),
        );
      },
    );
  }

  void _showCardioDetailSheet(CardioResult r, String name, String? imageUrl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
                  clipBehavior: Clip.antiAlias,
                  child: (imageUrl != null && imageUrl.isNotEmpty)
                      ? cachedImage(imageUrl, fit: BoxFit.cover)
                      : const Icon(Icons.directions_run, color: Colors.black54),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                      Text('${r.caloriesBurned.round()} kcal เผาผลาญ',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _cardioDetailRow(Icons.timer_outlined, 'ระยะเวลา', '${r.duration.round()} นาที', AppColors.cardioIcon),
            if (r.distance > 0) ...[
              const SizedBox(height: 12),
              _cardioDetailRow(Icons.straighten_rounded, 'ระยะทาง', '${r.distance.toStringAsFixed(2)} กม.', AppColors.cardioIcon),
            ],
            const SizedBox(height: 12),
            _cardioDetailRow(Icons.local_fire_department_rounded, 'แคลอรี่', '${r.caloriesBurned.round()} kcal', Colors.orange),
          ],
        ),
      ),
    );
  }

  Widget _cardioDetailRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ],
    );
  }

  Widget _buildSetRow(WorkoutResult r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text('${r.setNo}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primaryGreen)),
                ),
              ),
            ),
          ),
          Expanded(child: Text('${r.reps}', textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          Expanded(child: Text('${r.weight % 1 == 0 ? r.weight.toInt() : r.weight}', textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
        ],
      ),
    );
  }

  // ── Swipe-to-delete ───────────────────────────────────────────────────────────

  Widget _dismissBg() => Container(
    margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
    decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(16)),
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 20),
    child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
  );

  Future<void> _deleteWeightGroup(int exerciseId, List<WorkoutResult> sets) async {
    final futures = sets.map((s) => WorkoutService.to.deleteWorkoutResult(s.resultId));
    final results = await Future.wait(futures);
    if (!mounted) return;
    if (results.every((r) => r['success'] == true)) {
      setState(() => _weightResults.removeWhere((r) => r.exerciseId == exerciseId));
      widget.dashboardRefreshNotifier?.value++;
    } else {
      showAppAlert(context, 'ลบไม่สำเร็จ', type: AppAlertType.error);
      _loadTodayActivities();
    }
  }

  Future<void> _deleteCardioItem(CardioResult r) async {
    final result = await WorkoutService.to.deleteCardioResult(r.resultId);
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() => _cardioResults.removeWhere((c) => c.resultId == r.resultId));
      widget.dashboardRefreshNotifier?.value++;
    } else {
      showAppAlert(context, 'ลบไม่สำเร็จ', type: AppAlertType.error);
    }
  }
}
