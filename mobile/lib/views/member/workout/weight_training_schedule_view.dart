// หน้า: Weight Training Schedule (ตารางเวทเทรนนิ่ง)
// ทำหน้าที่: แสดงรายการท่าฝึกเวทตามวันที่เลือก กรองตามกลุ่มกล้ามเนื้อ เพิ่ม/ลบท่าฝึกในแผน custom ได้

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_fab.dart';
import '../../../core/widgets/app_page_header.dart';
import '../../../core/widgets/cached_image.dart';
import '../../../core/widgets/floating_selection_bar.dart';
import '../../../core/widgets/sticky_filter_chip_bar.dart';
import '../../../core/widgets/swipe_delete_item.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../core/widgets/undo_snackbar.dart';
import '../../../core/widgets/weekly_calendar_component.dart';
import '../../../models/exercise_model.dart';
import '../../../models/workout_model.dart';
// UserWorkoutSchedule ใช้ใน _loadPlanExercises
import '../../../services/api_client.dart';
import '../../../services/exercise_service.dart';
import '../../../services/workout_service.dart';
import 'weight_training_detail_view.dart';

class WeightTrainingScheduleView extends StatefulWidget {
  final int planId;
  final int dayNumber; // initial day (1-N = workout day, 0 = rest)
  final int daysPerWeek;
  final String planName;
  final bool isCustomPlan;
  final bool isWeekdayBased;

  const WeightTrainingScheduleView({
    super.key,
    required this.planId,
    required this.dayNumber,
    required this.daysPerWeek,
    required this.planName,
    this.isCustomPlan = false,
    this.isWeekdayBased = false,
  });

  @override
  State<WeightTrainingScheduleView> createState() =>
      _WeightTrainingScheduleViewState();
}

// ── internal model: join PlanDetail + Exercise ──────────────────────────────
class _PlanExercise {
  final int detailId;
  final Exercise exercise;
  final int suggestedSets;
  final String suggestedReps;

  _PlanExercise({
    required this.detailId,
    required this.exercise,
    required this.suggestedSets,
    required this.suggestedReps,
  });
}

enum _ExerciseStatus { notDone, incomplete, done }

// marker แยกส่วน "อื่นๆ" ออกจาก MuscleGroup จริงใน list ผสม (grouped exercise list)
class _OtherGroupMarker {
  const _OtherGroupMarker();
}

class _WeightTrainingScheduleViewState extends State<WeightTrainingScheduleView>
    with RouteAware {
  // ── calendar state ───────────────────────────────────────────────────────
  late DateTime _selectedDate;

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  // day number = weekday จริง (1=จันทร์...7=อาทิตย์) สำหรับทุกวัน ทั้ง workout และ rest
  int get _currentDayNumber => _selectedDate.weekday;

  // "วันพัก" = วันนี้ไม่มีท่าฝึกจริง แต่วันอื่นในแผนมี — อิงข้อมูลจริงจาก _daysWithExercises
  // (workout_schedules) เดียวกับที่การ์ดหน้าแรก (workout_view.dart) ใช้ ไม่ใช่ pattern ตายตัวจาก
  // แม่แบบตอนสร้างแผนครั้งแรก (ของเดิม: ใช้ WorkoutService.workoutDayMap[daysPerWeek] เทียบ ทำให้
  // แผนระบบที่ลบท่าออกจากวันเดิมจนหมดยังถูกนับเป็น "วันฝึก" อยู่ ทั้งที่ไม่มีท่าจริงแล้ว และแผน
  // ส่วนตัว (isWeekdayBased) ถูก hardcode ให้ไม่มีวันพักเลย ทั้งที่การ์ดหน้าแรกปฏิบัติเหมือนกันทั้ง
  // 2 ประเภทแผนไปแล้ว) เงื่อนไข "ทั้งแผนว่างเปล่า" แยกไว้ต่างหากที่ _isPlanEmpty ไม่ถือเป็นวันพัก
  bool get _isRestDay =>
      _daysWithExercises.isNotEmpty &&
      !_daysWithExercises.contains(_currentDayNumber);

  // ทั้งแผนยังไม่มีท่าฝึกเลยสักวัน (แผนระบบที่ถูกลบจนว่าง หรือแผนส่วนตัวที่เพิ่งสร้าง) — คนละสถานะ
  // กับ "วันพัก" (มีท่าฝึกวันอื่นอยู่) ต้องแยกเพื่อโชว์ข้อความให้ตรงกับการ์ดหน้าแรก
  bool get _isPlanEmpty => _daysWithExercises.isEmpty;

  // รูปแบบเดียวกับชิปที่การ์ดหน้าแรก (_activeWeekdaysLabel ใน workout_view.dart) — ทั้ง 2 ประเภทแผน
  String get _daysWithExercisesLabel {
    if (_daysWithExercises.isEmpty) return 'ยังไม่ตั้งวันฝึก';
    return '${_daysWithExercises.length} วัน / สัปดาห์';
  }

  // ── exercise state ───────────────────────────────────────────────────────
  int? _selectedGroupId; // null = ทั้งหมด
  List<_PlanExercise> _planExercises = [];
  List<Exercise> _allExercises = [];
  bool _isLoading = true;

  // muscle-group filter data (โหลดครั้งเดียว, cache ไว้)
  List<MuscleGroup> _muscleGroups = [];
  Map<int, int> _exercisePrimaryGroup =
      {}; // exerciseId → primary muscleGroupId
  List<MuscleGroup> _planMuscleGroups = []; // groups ที่มีในแผนวันนี้
  Map<int, List<WorkoutResult>> _resultsByExercise = {};
  final Set<int> _pendingDeleteIds = {}; // detailId ที่กำลังรอ undo หลังปัดลบ

  // วันที่มีท่าฝึกอยู่แล้วทั้งสัปดาห์ (ไม่ใช่แค่วันที่เลือกอยู่) — ป้อนให้ WeeklyCalendarComponent
  // วาดจุดเขียวสด real-time ทันทีที่เพิ่ม/ลบท่า ทั้งแผนระบบและแผนส่วนตัว (ก่อนหน้านี้ปฏิทินในหน้านี้
  // ไม่เคยส่ง activeDays เลย จุดสถานะเลยไม่เปลี่ยนแม้เพิ่งเพิ่มท่าไปหมาดๆ)
  Set<int> _daysWithExercises = {};

  // แสดงปุ่มรีเซ็ทเฉพาะตอนมีอะไรให้รีเซ็ทจริง — แผนระบบ: ต้องแก้ไขไปจากแม่แบบแล้ว (is_modified),
  // แผนส่วนตัว: ต้องมีท่าฝึกอยู่แล้วอย่างน้อย 1 ท่า (นับทั้งแผนทุกวัน ไม่ใช่แค่วันนี้)
  // ดึงจาก getActivePlanStatus() (GetMemberActivePlan) ที่ backend คำนวณไว้แล้ว ไม่คำนวณซ้ำฝั่ง
  // client กันตรรกะสองฝั่งเพี้ยนจากกัน
  bool _showReset = false;

  @override
  void initState() {
    super.initState();
    // Initialize with current date but adjust to the workout day
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    _selectedDate = today;
    _loadPlanExercises();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) undoRouteObserver.subscribe(this, route);
  }

  // มีหน้าอื่นถูกดันมาบังหน้านี้ — commit การลบท่าที่ค้าง undo อยู่ทันที กัน toast ลอยตามไปโผล่
  // ทับหน้าถัดไป (Overlay entry ไม่ผูกกับ route เลย ปล่อยไว้จะค้างจนกว่าจะหมดเวลาเองหรือถูกปัดทิ้งเอง)
  @override
  void didPushNext() => commitPendingUndo();

  @override
  void dispose() {
    undoRouteObserver.unsubscribe(this);
    commitPendingUndo(); // ออกจากหน้านี้ไปเลย (กดย้อนกลับ) ก็ commit ทันทีเหมือนกัน
    super.dispose();
  }

  Future<void> _loadPlanExercises() async {
    setState(() {
      _isLoading = true;
      _selectedGroupId = null;
    });

    final dayNum = _currentDayNumber;
    final fetchMuscleGroups = _muscleGroups.isEmpty;
    final futures = <Future>[
      WorkoutService.to.getSchedulesForDay(
        widget.planId,
        dayNum,
        isCustom: widget.isCustomPlan,
      ),
      ExerciseService.to.getWeightExercises(),
      if (fetchMuscleGroups) ExerciseService.to.getMuscleGroups(),
      WorkoutService.to.getWorkoutResults(date: _selectedDate),
      WorkoutService.to.getActivePlanStatus(), // ใช้เช็คว่าควรโชว์ปุ่มรีเซ็ทมั้ย
      // ดึง schedule ทั้งสัปดาห์ (ไม่กรองวัน) ไว้ท้ายสุดเสมอ — ใช้ป้อนจุดสถานะปฏิทิน (activeDays)
      WorkoutService.to.getAllSchedulesForPlan(
        widget.planId,
        isCustom: widget.isCustomPlan,
      ),
    ];
    final results = await Future.wait(futures);
    if (!mounted) return;

    final schedulesResult = results[0] as Map<String, dynamic>;

    // แผนหายไปจาก DB → แจ้งและกลับหน้าหลัก
    if (schedulesResult['plan_not_found'] == true) {
      setState(() => _isLoading = false);
      showAppAlert(
        context,
        'แผนหายไปจากระบบ กรุณาเลือกหรือสร้างแผนใหม่',
        type: AppAlertType.warning,
      );
      Navigator.pop(context);
      return;
    }

    final exercisesResult = results[1] as Map<String, dynamic>;
    final Map<int, Exercise> exerciseMap = {};
    if (exercisesResult['success'] == true) {
      final list = (exercisesResult['data'] as List).cast<Exercise>();
      _allExercises = list;
      for (final e in list) {
        exerciseMap[e.exerciseId] = e;
      }
    }

    if (fetchMuscleGroups && results.length > 2) {
      final r = results[2] as Map<String, dynamic>;
      if (r['success'] == true) {
        _muscleGroups = (r['data'] as List).cast<MuscleGroup>();
      }
    }

    _exercisePrimaryGroup = {
      for (final e in exerciseMap.values)
        if (e.muscleGroupId != null) e.exerciseId: e.muscleGroupId!,
    };

    // สร้าง _PlanExercise จาก workout_schedules
    List<_PlanExercise> planExercises = [];
    if (schedulesResult['success'] == true) {
      final schedules = (schedulesResult['data'] as List)
          .cast<UserWorkoutSchedule>();
      final seenIds = <int>{};
      for (final s in schedules) {
        if (!seenIds.add(s.exerciseId)) continue;
        final ex =
            exerciseMap[s.exerciseId] ??
            Exercise(
              exerciseId: s.exerciseId,
              exerciseName: s.exerciseName ?? 'ท่าที่ ${s.exerciseId}',
              description: '',
              difficulty: 'beginner',
              imageUrl: s.imageUrl,
            );
        planExercises.add(
          _PlanExercise(
            detailId: s.scheduleId,
            exercise: ex,
            suggestedSets: s.sets,
            suggestedReps: s.reps,
          ),
        );
      }
    }

    // ชิปที่โชว์ต้องครอบคลุมทุกกลุ่ม (หลัก+รอง) ที่กรองแล้วมีท่าจริง ไม่ใช่แค่กลุ่มหลักตัวเดียว
    // ให้ตรงกับ semantics ของ _filtered ด้านบน ไม่งั้นกดชิปกลุ่มที่มีท่า (เป็นกล้ามเนื้อรอง) แล้ว
    // จะเจอลิสต์ว่างเปล่า
    final groupIdsInPlan = planExercises
        .expand((p) => p.exercise.muscleGroupIds)
        .toSet();
    final planMuscleGroups = _muscleGroups
        .where((g) => groupIdsInPlan.contains(g.groupId))
        .toList();

    final wrIndex = fetchMuscleGroups ? 3 : 2;
    final Map<int, List<WorkoutResult>> resultsByExercise = {};
    if (results.length > wrIndex) {
      final wrData = results[wrIndex] as Map<String, dynamic>;
      if (wrData['success'] == true) {
        for (final r in (wrData['data'] as List).cast<WorkoutResult>()) {
          resultsByExercise.putIfAbsent(r.exerciseId, () => []).add(r);
        }
      }
    }

    // เช็คว่าควรโชว์ปุ่มรีเซ็ทมั้ย — ระบบ: ต้องแก้ไปจากแม่แบบแล้ว, ส่วนตัว: ต้องมีท่าฝึกอยู่แล้ว
    // (นับทั้งแผนทุกวัน) ผลลัพธ์นี้ backend คำนวณไว้ให้แล้วใน getActivePlanStatus() ไม่ต้องคำนวณซ้ำ
    final activePlanResult = results[results.length - 2] as Map<String, dynamic>;
    final showReset = _computeShowReset(
      activePlanResult['success'] == true && activePlanResult['has_plan'] == true
          ? activePlanResult['data'] as Map<String, dynamic>
          : null,
    );

    // dayNumber ที่เก็บจริงคือเลขวันในสัปดาห์ (1=จันทร์..7=อาทิตย์) ตัวเดียวกับ DateTime.weekday
    // ไม่ใช่ลำดับหมุนเวียน 1..N — ใช้ตรงๆ กับ WeeklyCalendarComponent.activeDays ได้เลย
    final allSchedulesResult = results.last as Map<String, dynamic>;
    Set<int> daysWithExercises = {};
    if (allSchedulesResult['success'] == true) {
      daysWithExercises = (allSchedulesResult['data'] as List)
          .cast<UserWorkoutSchedule>()
          .map((s) => s.dayNumber)
          .where((d) => d > 0)
          .toSet();
    }

    setState(() {
      _isLoading = false;
      _planExercises = planExercises;
      _planMuscleGroups = planMuscleGroups;
      _resultsByExercise = resultsByExercise;
      _daysWithExercises = daysWithExercises;
      _showReset = showReset;
    });
  }

  // แยกตรรกะเช็คปุ่มรีเซ็ทออกมาจาก _loadPlanExercises() — ใช้ซ้ำใน _refreshShowResetSilently()
  // (รีเฟรชเงียบๆ หลังลบท่า ไม่โหลดทั้งก้อน) กันตรรกะสองจุดเพี้ยนจากกัน
  // data มาจาก GetMemberActivePlan (แผน active เดียวของสมาชิก ไม่ใช่ list หลายแผนแบบเดิมอีกต่อไป)
  // เช็ค is_custom + planId ให้ตรงกับหน้าที่กำลังดูอยู่ก่อนเชื่อค่า is_modified/days_per_week
  bool _computeShowReset(Map<String, dynamic>? activePlan) {
    if (activePlan == null) return false;
    if ((activePlan['is_custom'] as bool? ?? false) != widget.isCustomPlan) return false;
    final idKey = widget.isCustomPlan ? 'mwp_id' : 'plan_id';
    if ((activePlan[idKey] as num?)?.toInt() != widget.planId) return false;
    return widget.isCustomPlan
        ? (activePlan['has_exercises'] as bool? ?? false)
        : (activePlan['is_modified'] as bool? ?? false);
  }

  // เช็คปุ่มรีเซ็ทใหม่แบบไม่แตะ _isLoading/_planExercises — กันจอกระพริบ/เลื่อนตำแหน่งหลังลบท่า
  // (เดิมเคยเรียก _loadPlanExercises() ทั้งก้อนหลังลบเพื่อกันปุ่มรีเซ็ทค้าง แต่มันเซ็ต
  // _isLoading = true ทำให้ทั้งลิสต์ถูกสลับไปโชว์ spinner กลางจอชั่ววูบ ดูไม่สมูท ทั้งที่ปัดลบ
  // ท่าเดียวไม่ควรรีโหลดทั้งจอ)
  Future<void> _refreshShowResetSilently() async {
    final result = await WorkoutService.to.getActivePlanStatus();
    if (!mounted || result['success'] != true) return;
    final showReset = _computeShowReset(
      result['has_plan'] == true ? result['data'] as Map<String, dynamic> : null,
    );
    if (showReset != _showReset) setState(() => _showReset = showReset);
  }

  // ── filtered list ────────────────────────────────────────────────────────
  List<_PlanExercise> get _filtered {
    final base = _planExercises.where(
      (p) => !_pendingDeleteIds.contains(p.detailId),
    );
    if (_selectedGroupId == null) return base.toList();
    // กรองด้วยกลุ่มกล้ามเนื้อ "ทั้งหมด" ของท่า (หลัก+รอง) ไม่ใช่แค่กลุ่มหลักตัวเดียว — ตรงกับ
    // semantics ตัวกรองที่ยืนยันไว้แล้วฝั่ง admin (ดูคอมเมนต์ admin_exercise_controller.go)
    return base
        .where((p) => p.exercise.muscleGroupIds.contains(_selectedGroupId))
        .toList();
  }

  // ── exercise status helpers ──────────────────────────────────────────────
  Future<void> _refreshResults() async {
    final result = await WorkoutService.to.getWorkoutResults(
      date: _selectedDate,
    );
    if (!mounted) return;
    final Map<int, List<WorkoutResult>> map = {};
    if (result['success'] == true) {
      for (final r in (result['data'] as List).cast<WorkoutResult>()) {
        map.putIfAbsent(r.exerciseId, () => []).add(r);
      }
    }
    setState(() => _resultsByExercise = map);
  }

  bool get _isFutureDate {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    return _selectedDate.isAfter(today);
  }

  _ExerciseStatus _getStatus(_PlanExercise item) {
    final sets = _resultsByExercise[item.exercise.exerciseId] ?? [];
    if (sets.isEmpty) return _ExerciseStatus.notDone;
    if (sets.length >= item.suggestedSets) return _ExerciseStatus.done;
    return _ExerciseStatus.incomplete;
  }

  Widget _statusBadge(_ExerciseStatus status) {
    switch (status) {
      case _ExerciseStatus.done:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.statusDoneBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.statusDoneText.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 11,
                color: AppColors.statusDoneText,
              ),
              const SizedBox(width: 4),
              Text(
                'ทำแล้ว',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.statusDoneText,
                ),
              ),
            ],
          ),
        );
      case _ExerciseStatus.incomplete:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.statusPartialBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.statusPartialText.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timelapse_rounded,
                size: 11,
                color: AppColors.statusPartialText,
              ),
              const SizedBox(width: 4),
              Text(
                'ทำไม่ครบ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.statusPartialText,
                ),
              ),
            ],
          ),
        );
      case _ExerciseStatus.notDone:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.statusPendingBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'ยังไม่ได้ทำ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.statusPendingText,
            ),
          ),
        );
    }
  }

  // ── plan actions (add/remove จาก workout_schedules) ────────────────────────

  // ปัดลบท่า + snackbar "เลิกทำ" (รูปแบบเดียวกับ workout_view.dart) — ซ่อนออกจากจอทันที ยังไม่ยิงลบจริง
  // จนกว่าจะหมดเวลา undo กันลบพลาดตอนไม่มีสำเนาสำรอง (fork ถูกตัดออกแล้ว มีแต่ resetPlan กู้ทั้งแผนได้)
  void _handleSwipeDeleteExercise(_PlanExercise item) {
    setState(() => _pendingDeleteIds.add(item.detailId));
    showUndoSnackbar(
      context,
      message: 'ลบ "${item.exercise.exerciseName}" แล้ว',
      onUndo: () {
        if (!mounted) return;
        setState(() => _pendingDeleteIds.remove(item.detailId));
      },
      onExpire: () async {
        final result = await WorkoutService.to.removeExerciseFromSchedule(
          item.detailId,
        );
        if (!mounted) return;
        if (result['success'] == true) {
          setState(() {
            _planExercises.removeWhere((p) => p.detailId == item.detailId);
            _pendingDeleteIds.remove(item.detailId);
            // _planExercises คือท่าของวันที่เลือกอยู่เท่านั้น (โหลดแบบกรองตามวันมาแล้ว) — ถ้าลบ
            // จนว่างหมด แปลว่าวันนี้ไม่มีท่าฝึกเหลือแล้วจริงๆ ต้องเอาออกจาก _daysWithExercises ด้วย
            // ไม่งั้นจุดเขียวบนปฏิทินจะค้าง
            if (_planExercises.isEmpty) {
              _daysWithExercises.remove(_currentDayNumber);
            }
            // ตัวกรองกลุ่มกล้ามเนื้อก็ค้างเหมือนกัน — คำนวณใหม่จาก _planExercises ที่เพิ่งอัปเดตสดๆ
            // ด้วยตรรกะเดียวกับใน _loadPlanExercises()
            final groupIdsInPlan = _planExercises
                .expand((p) => p.exercise.muscleGroupIds)
                .toSet();
            _planMuscleGroups = _muscleGroups
                .where((g) => groupIdsInPlan.contains(g.groupId))
                .toList();
            // กำลังกรองค้างอยู่ที่กลุ่มที่เพิ่งว่างไป → เด้งกลับ "ทั้งหมด" กันจอค้างว่างเปล่าไม่รู้สาเหตุ
            if (_selectedGroupId != null &&
                !groupIdsInPlan.contains(_selectedGroupId)) {
              _selectedGroupId = null;
            }
          });
          // ปุ่มรีเซ็ทต้องเช็คทั้งแผน (ทุกวัน) ไม่ใช่แค่วันนี้ — patch ในนี้ไม่พอ ต้องถามฝั่ง server
          // (getMyPlans) แต่ไม่ผ่าน _loadPlanExercises() ทั้งก้อน กันจอกระพริบ/เลื่อนตำแหน่ง (ของเดิม
          // เคยพลาดจุดนี้ไป ปุ่มรีเซ็ทค้างโชว์หลังลบท่าสุดท้ายของทั้งแผน)
          _refreshShowResetSilently();
        } else {
          // ลบจริงไม่สำเร็จ (เช่นเครือข่ายล้ม) — ดึงข้อมูลจริงจาก server กลับมาแสดงใหม่ กันรายการหายค้างบนจอ
          setState(() => _pendingDeleteIds.remove(item.detailId));
          showAppAlert(
            context,
            result['message'] ?? 'ลบท่าออกกำลังกายไม่สำเร็จ',
            type: AppAlertType.error,
          );
          await _loadPlanExercises();
        }
      },
    );
  }

  // แก้จำนวนเซ็ต/reps ของท่านี้ในแผนของตัวเอง — ค่าระบบตั้งมาเป็นแค่ค่าเริ่มต้น ผู้ใช้ปรับได้อิสระ
  Future<void> _editSetsReps(_PlanExercise item) async {
    final setsController = TextEditingController(text: '${item.suggestedSets}');
    final repsController = TextEditingController(text: item.suggestedReps);

    final result = await showDialog<(int, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'แก้ไข ${item.exercise.exerciseName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: setsController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'จำนวนเซ็ต'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: repsController,
              decoration: const InputDecoration(
                labelText: 'จำนวนครั้ง (เช่น 8-10)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () {
              final sets = int.tryParse(setsController.text.trim());
              final reps = repsController.text.trim();
              if (sets == null || sets < 1) {
                showAppAlert(
                  ctx,
                  'จำนวนเซ็ตต้องมากกว่า 0',
                  type: AppAlertType.error,
                );
                return;
              }
              Navigator.pop(ctx, (sets, reps));
            },
            child: const Text('บันทึกการเปลี่ยนแปลง'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final (sets, reps) = result;

    setState(() => _isLoading = true);
    final saveResult = await WorkoutService.to.updateSchedule(
      item.detailId,
      sets: sets,
      reps: reps.isEmpty ? null : reps,
    );
    if (!mounted) return;
    if (saveResult['success'] == true) {
      await _loadPlanExercises();
    } else {
      setState(() => _isLoading = false);
      showAppAlert(
        context,
        saveResult['message'] ?? 'แก้ไขไม่สำเร็จ',
        type: AppAlertType.error,
      );
    }
  }

  Future<void> _showAddExerciseSheet() async {
    if (_allExercises.isEmpty) {
      final result = await ExerciseService.to.getWeightExercises();
      if (!mounted) return;
      if (result['success'] == true) {
        _allExercises = (result['data'] as List).cast<Exercise>();
      }
    }
    if (!mounted) return;

    final existingIds = _planExercises
        .map((e) => e.exercise.exerciseId)
        .toSet();
    final available = _allExercises
        .where((e) => !existingIds.contains(e.exerciseId))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        // เดิม 0.95 ลากขึ้นสุดไม่ได้ ค้างช่องว่างล่างจอไว้เฉยๆ 5% เปลี่ยนเป็น 1.0 ลากเต็มจอได้จริง
        // (เนื้อหาด้านในกัน status bar เองด้วย SafeArea อยู่แล้ว)
        maxChildSize: 1.0,
        expand: false,
        builder: (_, scrollCtrl) => _ExercisePickerSheet(
          exercises: available,
          scrollController: scrollCtrl,
          onConfirm: (exercises) {
            Navigator.pop(ctx);
            _addExercisesToPlan(exercises);
          },
        ),
      ),
    );
  }

  // เพิ่มหลายท่าตะกร้า — ไม่มี batch endpoint ฝั่ง backend เลยยิงทีละท่า "เรียงลำดับ" (await ทีละตัว)
  // ไม่ใช้ Future.wait ยิงพร้อมกันเหมือนเดิม เพราะ backend (CreateWorkoutSchedule) ไม่มี
  // transaction/lock ครอบตอนเช็คซ้ำ + คำนวณ wsch_order — ยิงพร้อมกันหลายท่าชน table เดียวกัน
  // (mb_id + wsch_day_number เดียวกัน) ทำให้ MySQL InnoDB deadlock แล้วสุ่มทิ้ง 1 transaction เป็น
  // victim คือสาเหตุอาการ "เพิ่มสำเร็จ 2 ท่า ไม่สำเร็จ 1 ท่า" ที่เจอ — โหลดข้อมูลใหม่ครั้งเดียวตอนจบ
  // เหมือน pattern _saveAllSelected ของหน้าเพิ่มอาหาร (food_list_view.dart) ไม่ reload ทุกครั้งที่เพิ่ม
  Future<void> _addExercisesToPlan(List<Exercise> exercises) async {
    if (exercises.isEmpty) return;
    setState(() => _isLoading = true);
    final results = <Map<String, dynamic>>[];
    for (final ex in exercises) {
      results.add(
        await WorkoutService.to.addExerciseToSchedule(
          planId: widget.planId,
          dayNumber: _currentDayNumber,
          wetId: ex.exerciseId,
          isCustom: widget.isCustomPlan,
        ),
      );
    }
    if (!mounted) return;
    final failCount = results.where((r) => r['success'] != true).length;
    await _loadPlanExercises();
    if (!mounted) return;
    if (failCount == 0) {
      showAppAlert(
        context,
        'เพิ่ม ${exercises.length} ท่าแล้ว',
        type: AppAlertType.success,
      );
    } else if (failCount == exercises.length) {
      showAppAlert(
        context,
        'เพิ่มท่าออกกำลังกายไม่สำเร็จ',
        type: AppAlertType.error,
      );
    } else {
      showAppAlert(
        context,
        'เพิ่มสำเร็จ ${exercises.length - failCount} ท่า ไม่สำเร็จ $failCount ท่า',
        type: AppAlertType.warning,
      );
    }
  }

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final showFab = !_isLoading;

    return Scaffold(
      backgroundColor: AppColors.scaffoldGrey,
      floatingActionButton: showFab
          ? AppFab(onPressed: _showAddExerciseSheet)
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            _buildHeader(),
            const SizedBox(height: 16),
            WeeklyCalendarComponent(
              // เลือกวันอนาคตได้ — หน้านี้ใช้ "วางแผนล่วงหน้า" ได้ด้วย (ดูท่า/แก้เซ็ตของวันที่ยังไม่ถึง)
              // ต่างจากปฏิทินหน้า WorkoutView (หน้าแรกแท็บออกกำลังกาย) ที่ล็อกอนาคตไว้ตามเดิม
              selectedDate: _selectedDate,
              activeDays: _daysWithExercises,
              onDaySelected: (date) {
                setState(() {
                  _selectedDate = date;
                });
                _loadPlanExercises();
              },
            ),
            if (_planMuscleGroups.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildFilterChips(),
              const SizedBox(height: 14),
            ] else
              const SizedBox(height: 8),
            Expanded(child: _buildExerciseList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AppPageHeader(
      title: widget.planName.isNotEmpty
          ? widget.planName
          : 'ตารางฝึกเวทเทรนนิ่ง',
      // อ่านจาก _daysWithExercises สด ๆ (จำนวนวันที่มีท่าฝึกจริงตอนนี้) แทน widget.daysPerWeek /
      // widget.isWeekdayBased ที่เป็นค่านิ่งตอนเปิดหน้า — เดิมแผนระบบเพิ่ม/ลบท่าจนจำนวนวันจริง
      // เปลี่ยนแล้วตัวเลขบนหัวตารางไม่อัปเดตตาม และแผนส่วนตัวไม่เคยโชว์จำนวนวันเลย ใช้รูปแบบ/แหล่ง
      // ข้อมูลเดียวกับชิปที่การ์ดหน้าแรก (_activeWeekdaysLabel ใน workout_view.dart) ทั้ง 2 ประเภทแผน
      subtitle: _daysWithExercisesLabel,
      trailing: _showReset ? _resetButton() : null,
    );
  }

  // ปุ่มคืนค่าเดิม — ระบบ=คัดลอกท่าจากแม่แบบใหม่ทับของเดิม, ส่วนตัว=ล้างท่าออกให้ว่างเปล่า
  // สำคัญขึ้นมาหลังตัดปุ่มคัดลอกเป็นแผนของฉัน (fork) ออก เพราะไม่มีสำเนาสำรองให้กู้ถ้าลบท่าพลาด
  // กด disable ระหว่าง _isLoading กันกดซ้ำ (ตอนนี้ทั้งลิสต์ก็ถูกสลับเป็น spinner อยู่แล้วเช่นกัน)
  Widget _resetButton() => GestureDetector(
    onTap: _isLoading ? null : _confirmReset,
    child: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.restore_rounded, color: Colors.red.shade400, size: 18),
    ),
  );

  Future<void> _confirmReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('คืนค่าเดิม?'),
        content: Text(
          widget.isCustomPlan
              ? 'ท่าฝึกทั้งหมดในแผน "${widget.planName}" จะถูกลบออกจนว่างเปล่า'
              : 'คืนค่า "${widget.planName}" กลับเป็นแผนต้นฉบับ ท่าฝึกที่เพิ่มหรือลบไว้จะหายทั้งหมด',
        ),
        // ยกเลิก=เทาเรียบ (ทางปลอดภัย), ยืนยัน=ปุ่มกรอบแดง (ทางทำลายข้อมูล) — กรอบ/สไตล์เดียวกันทุกจุด
        // ที่เป็นการลบ/แทนที่ข้อมูลถาวรในฝั่งนี้ของแอป (ดู _confirmAndSelectPlan ใน
        // workout_days_selection_view.dart และ dialog ตั้งชื่อแผนใน workout_view.dart)
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'ยกเลิก',
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'คืนค่า',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    await _submitReset();
  }

  Future<void> _submitReset() async {
    setState(() => _isLoading = true);
    final result = await WorkoutService.to.resetPlan(
      wptId: widget.isCustomPlan ? null : widget.planId,
      mwpId: widget.isCustomPlan ? widget.planId : null,
    );
    if (!mounted) return;

    if (result['success'] != true) {
      setState(() => _isLoading = false);
      final isNetworkError = result['network_error'] == true;
      showAppAlert(
        context,
        result['message'] ?? 'คืนค่าเดิมไม่สำเร็จ',
        type: AppAlertType.error,
        actionLabel: isNetworkError ? 'ลองใหม่' : null,
        onAction: isNetworkError ? () => _submitReset() : null,
      );
      return;
    }

    showAppAlert(context, 'คืนค่าเดิมสำเร็จ', type: AppAlertType.success);
    await _loadPlanExercises();
  }

  Widget _buildRestDayState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.accentGreen.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.self_improvement_rounded,
                size: 40,
                color: AppColors.accentGreen,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'วันนี้เป็นวันพัก',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
            ),
            const SizedBox(height: 8),
            const Text(
              'ให้ร่างกายฟื้นฟู กล้ามเนื้อซ่อมแซมได้ดีที่สุดในวันพัก',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primaryGreen.withValues(alpha: 0.25),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    size: 16,
                    color: AppColors.primaryGreen,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'กด + เพื่อเพิ่มท่าฝึกในวันนี้',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ทั้งแผนยังไม่มีท่าฝึกเลยสักวัน — โทนเทากลาง ไม่ใช้สีเขียว/ฟ้าเหมือนวันฝึก/วันพัก กันสับสนว่า
  // "ยังไม่ได้ตั้งอะไรเลย" กับ "ตั้งแล้ว วันนี้แค่พัก" (ธีมสี+ข้อความเดียวกับ isPlanEmpty ในการ์ด
  // หน้าแรก workout_view.dart กันคนละความหมายคนละหน้า)
  Widget _buildEmptyPlanState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: AppColors.surfaceLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_circle_outline_rounded,
                size: 40,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'ยังไม่มีท่าฝึกในแผนนี้',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
            ),
            const SizedBox(height: 8),
            const Text(
              'เริ่มเพิ่มท่าออกกำลังกายเพื่อสร้างตารางฝึกของคุณ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.textMuted.withValues(alpha: 0.25),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'กด + เพื่อเพิ่มท่าฝึก',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }

    // ทั้งแผนยังไม่มีท่าฝึกเลยสักวัน — คนละสถานะกับวันพัก (ดูคอมเมนต์ _isPlanEmpty/_isRestDay)
    if (_isPlanEmpty) return _buildEmptyPlanState();
    // วันนี้ไม่มีท่าฝึก แต่วันอื่นในแผนมี → วันพักจริง (FAB ยังแสดงให้เพิ่มได้)
    if (_isRestDay) return _buildRestDayState();

    final exercises = _filtered;
    if (exercises.isEmpty) {
      // มาถึงจุดนี้ได้ทางเดียวคือตัวกรองกลุ่มกล้ามเนื้อทำให้ว่าง (เช็ค _isPlanEmpty/_isRestDay
      // ข้างบนแล้วว่าวันนี้มีท่าฝึกแน่ๆ)
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.fitness_center_outlined,
                size: 48,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 12),
              const Text(
                'ไม่พบท่าในกลุ่มกล้ามเนื้อที่เลือก',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // โหมด "ทั้งหมด" + มีมากกว่า 1 กลุ่มกล้ามเนื้อในวันนี้ → จัดเป็นส่วนๆ ตามกลุ่ม
    // (เรียงตามลำดับเดียวกับชิปตัวกรอง เช่น อก 1,2,3 ไหล่ 1,2,3) กรองกลุ่มเดียวแล้วไม่ต้องจัดซ้ำ
    if (_selectedGroupId == null && _planMuscleGroups.length > 1) {
      return _buildGroupedExerciseList(exercises);
    }

    // วันนี้ (กำลังฝึกจริง): ห้ามสลับตำแหน่งตามสถานะ — ลำดับต้องคงที่ตาม wsch_order (มีความหมาย
    // ทางสรีรวิทยาตาม ACSM บทที่ 2) ไม่งั้น list ขยับเองระหว่างกำลังฝึกจนกดผิดท่า ใช้ badge สถานะ
    // ในการ์ดบอกแทน (ดู _statusBadge) — วันอื่น (วางแผนล่วงหน้า/ดูย้อนหลัง) ไม่ใช่หน้ากดโต้ตอบสด
    // เรียงสถานะได้เต็มที่ ให้เห็น "เหลืออะไรต้องทำ" ก่อนเสมอเหมือนเดิม
    final display = _isToday
        ? exercises
        : (List<_PlanExercise>.from(exercises)..sort(
            (a, b) => _getStatus(a).index.compareTo(_getStatus(b).index),
          ));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(23, 4, 23, 100),
      itemCount: display.length,
      itemBuilder: (context, index) => _exerciseCard(display[index]),
    );
  }

  // ── grouped list (โหมด "ทั้งหมด") — ส่วนหัวตามกลุ่มกล้ามเนื้อ + เลขลำดับในกลุ่ม ──────
  Widget _buildGroupedExerciseList(List<_PlanExercise> exercises) {
    final Map<int, List<_PlanExercise>> grouped = {};
    final List<_PlanExercise> noGroup = [];
    for (final item in exercises) {
      final gid = _exercisePrimaryGroup[item.exercise.exerciseId];
      if (gid == null) {
        noGroup.add(item);
      } else {
        grouped.putIfAbsent(gid, () => []).add(item);
      }
    }

    // เรียงสถานะภายในแต่ละกลุ่ม — เฉพาะวันอื่น (ไม่ใช่วันนี้) เหมือนโหมด flat ด้านบน วันนี้ต้องคง
    // ลำดับ wsch_order เดิมไว้ ห้าม list ขยับเองระหว่างกำลังฝึก
    if (!_isToday) {
      int statusRank(_PlanExercise p) => _getStatus(p).index;
      for (final list in grouped.values) {
        list.sort((a, b) => statusRank(a).compareTo(statusRank(b)));
      }
      noGroup.sort((a, b) => statusRank(a).compareTo(statusRank(b)));
    }

    // items: MuscleGroup = ส่วนหัว, null = ส่วนหัว "อื่นๆ", _PlanExercise = การ์ดท่า
    final items = <Object?>[];
    for (final g in _planMuscleGroups) {
      final list = grouped[g.groupId];
      if (list == null || list.isEmpty) continue;
      items.add(g);
      items.addAll(list);
    }
    if (noGroup.isNotEmpty) {
      items.add(const _OtherGroupMarker());
      items.addAll(noGroup);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(23, 4, 23, 100),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is MuscleGroup)
          return _sectionHeader(item, grouped[item.groupId]!.length);
        if (item is _OtherGroupMarker)
          return _sectionHeader(null, noGroup.length);

        final planExercise = item as _PlanExercise;
        return _exerciseCard(planExercise);
      },
    );
  }

  // หัวข้อ section — รูปกลุ่มกล้ามเนื้อ (ถ้ามี) + ชื่อ + เส้นแบ่ง + จำนวนท่าในกลุ่มนั้น
  Widget _sectionHeader(MuscleGroup? group, int count) {
    final raw = group?.imageUrl;
    final fullUrl = (raw != null && raw.isNotEmpty)
        ? (raw.startsWith('http') ? raw : '${ApiClient.serverUrl}/$raw')
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Row(
        children: [
          if (fullUrl != null)
            ClipOval(
              child: SizedBox(
                width: 24,
                height: 24,
                child: cachedImage(fullUrl, fit: BoxFit.cover),
              ),
            )
          else
            Container(
              width: 8,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          const SizedBox(width: 10),
          Text(
            group?.groupName ?? 'อื่นๆ',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: const Color(0xFFECECEC))),
          const SizedBox(width: 8),
          Text(
            '$count ท่า',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  // การ์ดท่าฝึก 1 ท่า — ใช้ทั้งโหมด flat และ grouped
  Widget _exerciseCard(_PlanExercise item) {
    return SwipeDeleteItem(
      itemKey: Key('ex_${item.detailId}'),
      background: _exerciseDismissBg(),
      onDismissed: () => _handleSwipeDeleteExercise(item),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WeightTrainingDetailView(
              exerciseId: item.exercise.exerciseId,
              exerciseName: item.exercise.exerciseName,
              imageUrl: item.exercise.imageUrl ?? '',
              suggestedSets: item.suggestedSets,
              suggestedReps: item.suggestedReps,
              description: item.exercise.description,
              technique: item.exercise.technique,
              difficulty: item.exercise.difficulty,
              videoUrl: item.exercise.videoUrl ?? '',
              loopVideoUrl: item.exercise.loopVideoUrl ?? '',
              isToday: _isToday,
              exerciseType: item.exercise.exerciseType,
              muscleGroupName: item.exercise.muscleGroupName,
              equipment: item.exercise.equipment,
              // ท่านี้อยู่ในแผนอยู่แล้ว มี wsch_id จริงจาก workout_schedules —
              // ส่งตรงไปให้หน้าบันทึกผล ไม่ต้องให้มันไปสร้าง schedule ซ้ำเอง
              wschId: item.detailId,
            ),
          ),
        ).then((_) => _refreshResults()),
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child:
                      (item.exercise.imageUrl != null &&
                          item.exercise.imageUrl!.isNotEmpty)
                      ? cachedImage(item.exercise.imageUrl!, fit: BoxFit.cover)
                      : const Icon(
                          Icons.fitness_center,
                          color: AppColors.primaryGreen,
                          size: 30,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.exercise.exerciseName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _badge(
                          '${item.suggestedSets} เซ็ต',
                          AppColors.primaryGreen.withValues(alpha: 0.12),
                          AppColors.primaryGreen,
                        ),
                        _badge(
                          '${item.suggestedReps} ครั้ง',
                          const Color(0xFFF0F0F0),
                          Colors.black54,
                        ),
                        if (item.exercise.muscleGroupName.isNotEmpty)
                          _badge(
                            item.exercise.muscleGroupName,
                            const Color(0xFFEEF2FF),
                            const Color(0xFF5B6CF6),
                          ),
                      ],
                    ),
                    if (!_isFutureDate) ...[
                      const SizedBox(height: 6),
                      _statusBadge(_getStatus(item)),
                    ],
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _editSetsReps(item),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: AppColors.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // พื้นหลังตอนปัดลบท่าฝึก — ทรงเดียวกับการ์ดท่าฝึก (margin/borderRadius ตรงกัน) กันมุมโผล่ตอนปัด
  Widget _exerciseDismissBg() => Container(
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: AppColors.error,
      borderRadius: BorderRadius.circular(20),
    ),
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 20),
    child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
  );

  // ปุ่ม "ทั้งหมด" ปักหมุดซ้ายสุด กลุ่มกล้ามเนื้ออื่นเลื่อนลอดใต้ปุ่มนั้น — pattern เดียวกับตัวกรองหน้าเพิ่มอาหาร/บันทึกกิจกรรม
  Widget _buildFilterChips() {
    final items = <FilterChipItem<int?>>[
      const FilterChipItem<int?>(id: null, label: 'ทั้งหมด'),
      for (final group in _planMuscleGroups)
        FilterChipItem<int?>(
          id: group.groupId,
          label: group.groupName,
          imageUrl: (group.imageUrl != null && group.imageUrl!.isNotEmpty)
              ? (group.imageUrl!.startsWith('http')
                    ? group.imageUrl!
                    : '${ApiClient.serverUrl}/${group.imageUrl}')
              : null,
        ),
    ];
    return StickyFilterChipBar<int?>(
      items: items,
      selectedId: _selectedGroupId,
      onSelected: (id) => setState(() => _selectedGroupId = id),
      padding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }

  Widget _badge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

// ── Exercise picker bottom sheet ─────────────────────────────────────────────
class _ExercisePickerSheet extends StatefulWidget {
  final List<Exercise> exercises;
  final ScrollController scrollController;
  final void Function(List<Exercise>) onConfirm;

  const _ExercisePickerSheet({
    required this.exercises,
    required this.scrollController,
    required this.onConfirm,
  });

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  String _search = '';
  int? _selectedGroupId;

  // ตะกร้าเลือกหลายท่า — pattern เดียวกับหน้าเพิ่มอาหาร (food_list_view.dart _toggleCart):
  // แตะการ์ดเพื่อติ๊กเข้า/ออกตะกร้า ไม่ปิดชีททันทีเหมือนเดิม (เดิม onPick เดียวปิดชีทเลย
  // ทำให้เพิ่มทีละหลายท่าต้องกด FAB เปิดชีทใหม่ทุกครั้ง)
  final Set<int> _selectedIds = {};

  List<MuscleGroup> _muscleGroups = [];
  // exerciseId → กลุ่มกล้ามเนื้อ "หลัก" ตัวแรก — ใช้ทั้งจัด section ใน _groupedList และกรองด้วยชิป
  // ด้านบน (ตัวกรองหน้านี้อิงกล้ามเนื้อหลักเท่านั้น ไม่รวมกล้ามเนื้อรอง — ต่างจากตัวกรองหน้าตารางฝึก
  // หลักที่ยังอิงหลัก+รองตามเดิม เพราะที่นี่คือหน้า "เพิ่มท่าใหม่" ต้องการให้ผลตรงกับกลุ่มที่เลือกจริงๆ)
  Map<int, int> _exercisePrimaryGroupId = {};
  bool _groupsLoading = true;

  void _toggleSelect(Exercise ex) {
    setState(() {
      if (!_selectedIds.remove(ex.exerciseId)) _selectedIds.add(ex.exerciseId);
    });
  }

  void _confirm() {
    final selected = widget.exercises
        .where((e) => _selectedIds.contains(e.exerciseId))
        .toList();
    widget.onConfirm(selected);
  }

  @override
  void initState() {
    super.initState();
    _loadMuscleData();
  }

  Future<void> _loadMuscleData() async {
    final result = await ExerciseService.to.getMuscleGroups();
    if (!mounted) return;

    final groups = result['success'] == true
        ? (result['data'] as List).cast<MuscleGroup>()
        : <MuscleGroup>[];

    // exerciseId → กลุ่มกล้ามเนื้อหลักตัวแรกเท่านั้น (ไม่รวมกล้ามเนื้อรอง) — หน้านี้คือหน้า
    // "เพิ่มท่าใหม่" ตัวกรองต้องอิงกล้ามเนื้อหลักล้วนๆ ไม่งั้นเลือกชิป "ขา" แล้วเจอท่าอกที่ใช้
    // ขาเป็นกล้ามเนื้อรองปนมาด้วย ทำให้ผลกรองดูไม่ตรงกับที่ผู้ใช้ตั้งใจเลือก (เดิมกรองด้วย
    // exercise.muscleGroupIds ซึ่งรวมทั้งหลัก+รอง — แก้ตามที่ผู้ใช้แจ้งให้กรองเฉพาะกล้ามเนื้อหลัก)
    final Map<int, int> primaryMap = {};
    for (final e in widget.exercises) {
      if (e.muscleGroupId != null) primaryMap[e.exerciseId] = e.muscleGroupId!;
    }

    setState(() {
      _muscleGroups = groups;
      _exercisePrimaryGroupId = primaryMap;
      _groupsLoading = false;
    });
  }

  List<Exercise> get _filtered {
    var list = widget.exercises;
    if (_selectedGroupId != null) {
      list = list
          .where((e) => _exercisePrimaryGroupId[e.exerciseId] == _selectedGroupId)
          .toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((e) => e.exerciseName.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    // ลากชีทขึ้นสุดจอได้แล้ว (maxChildSize: 1.0 ที่จุดเรียก) กัน handle/หัวข้อชนสถานะบาร์/เกาะกล้อง
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Column(
            children: [
              // Handle
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              // Title + count
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'เลือกท่าฝึกเวทเทรนนิ่ง',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${filtered.length} ท่า',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Search field
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'ค้นหาท่า...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // ── Muscle group filter chips ── ใช้ StickyFilterChipBar มาตรฐานเดียวกับ
              // ตัวกรองหน้าเพิ่มอาหาร/หน้าหลักออกกำลังกาย (เดิมหน้านี้ใช้ chip แบบเขียนเอง
              // หน้าตาไม่ตรงกับที่อื่นในแอป) ──────────────────────────────────────────
              if (!_groupsLoading && _muscleGroups.isNotEmpty)
                StickyFilterChipBar<int?>(
                  items: [
                    const FilterChipItem<int?>(id: null, label: 'ทั้งหมด'),
                    for (final g in _muscleGroups)
                      FilterChipItem<int?>(
                        id: g.groupId,
                        label: g.groupName,
                        imageUrl: (g.imageUrl != null && g.imageUrl!.isNotEmpty)
                            ? (g.imageUrl!.startsWith('http')
                                  ? g.imageUrl!
                                  : '${ApiClient.serverUrl}/${g.imageUrl}')
                            : null,
                      ),
                  ],
                  selectedId: _selectedGroupId,
                  onSelected: (id) => setState(() => _selectedGroupId = id),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  backgroundColor: Colors.white,
                ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0xFFF2F2F7)),
              // ── Exercise list ──────────────────────────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 48,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'ไม่พบท่าออกกำลังกาย',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _selectedGroupId != null || _muscleGroups.isEmpty
                    ? _flatList(filtered)
                    : _groupedList(filtered),
              ),
            ],
          ),
          // ── แถบยืนยันลอย ── โผล่เมื่อเลือกอย่างน้อย 1 ท่า กด "เพิ่ม N ท่า" ครั้งเดียวจบ
          // แทนที่ต้องปิดชีท-เปิดใหม่ทีละท่า (pattern เดียวกับ FloatingSelectionBar ของหน้าเพิ่มอาหาร)
          if (_selectedIds.isNotEmpty)
            FloatingSelectionBar(
              count: _selectedIds.length,
              confirmLabel: 'เพิ่ม ${_selectedIds.length} ท่า',
              onConfirm: _confirm,
            ),
        ],
      ),
    );
  }

  // ── grouped list (ทั้งหมด mode) ────────────────────────────────────────────
  Widget _groupedList(List<Exercise> exercises) {
    final Map<int, List<Exercise>> grouped = {};
    final List<Exercise> noGroup = [];
    for (final ex in exercises) {
      final gid = _exercisePrimaryGroupId[ex.exerciseId];
      if (gid == null) {
        noGroup.add(ex);
      } else {
        grouped.putIfAbsent(gid, () => []).add(ex);
      }
    }

    final items = <dynamic>[];
    for (final g in _muscleGroups) {
      final list = grouped[g.groupId];
      if (list == null || list.isEmpty) continue;
      items.add(g);
      items.addAll(list);
    }
    if (noGroup.isNotEmpty) {
      items.add('อื่นๆ');
      items.addAll(noGroup);
    }

    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        if (item is MuscleGroup) return _groupHeader(item.groupName);
        if (item is String) return _groupHeader(item, muted: true);
        return _exerciseRow(item as Exercise);
      },
    );
  }

  Widget _groupHeader(String name, {bool muted = false}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 14,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: muted ? AppColors.textMuted : AppColors.primaryGreen,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Text(
          name,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: muted ? AppColors.textMuted : AppColors.textDark,
          ),
        ),
      ],
    ),
  );

  // ── flat list (filtered mode / no group data) ──────────────────────────────
  // การ์ดแต่ละใบมี margin ล่างในตัวเองอยู่แล้ว (เหมือน _buildFoodCard หน้าเพิ่มอาหาร)
  // ไม่ต้องใช้ Divider คั่นอีก
  Widget _flatList(List<Exercise> exercises) => ListView.builder(
    controller: widget.scrollController,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
    itemCount: exercises.length,
    itemBuilder: (ctx, i) => _exerciseRow(exercises[i]),
  );

  // ── single exercise row ── ยึด layout/UX เดียวกับ _buildFoodCard หน้าเพิ่มอาหาร
  // (food_list_view.dart): การ์ดสีขาวมี margin ล่างกันการ์ดติดกัน, ปุ่ม +/check วงกลมเขียว-ขาว
  // มุมขวาเท่านั้นที่กดติ๊กเข้า/ออกตะกร้าได้ (เดิม InkWell ครอบทั้งแถวให้กดได้ทั้งการ์ด)
  Widget _exerciseRow(Exercise ex) {
    final isSelected = _selectedIds.contains(ex.exerciseId);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isSelected
            ? Border.all(color: AppColors.primaryGreen, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: (ex.imageUrl != null && ex.imageUrl!.isNotEmpty)
                      ? cachedImage(ex.imageUrl!, fit: BoxFit.cover)
                      : _placeholder(),
                ),
              ),
              if (isSelected)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ex.exerciseName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ex.equipment.label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _toggleSelect(ex),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                isSelected ? Icons.check_rounded : Icons.add_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
    color: AppColors.primaryGreen.withValues(alpha: 0.08),
    child: const Icon(
      Icons.fitness_center,
      color: AppColors.primaryGreen,
      size: 22,
    ),
  );
}
