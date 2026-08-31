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
  final int dayNumber;   // initial day (1-N = workout day, 0 = rest)
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
  State<WeightTrainingScheduleView> createState() => _WeightTrainingScheduleViewState();
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

class _WeightTrainingScheduleViewState extends State<WeightTrainingScheduleView> with RouteAware {
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

  // ตรวจว่าวันนี้เป็นวันพักตามโครงสร้างแผนหรือเปล่า (ไม่ว่าจะมีท่าหรือไม่)
  bool get _isRestDay {
    if (widget.isWeekdayBased) return false;
    final workoutDays = WorkoutService.workoutDayMap[widget.daysPerWeek] ?? [];
    return !workoutDays.contains(_selectedDate.weekday - 1);
  }

  // ── exercise state ───────────────────────────────────────────────────────
  int? _selectedGroupId; // null = ทั้งหมด
  List<_PlanExercise> _planExercises = [];
  List<Exercise> _allExercises = [];
  bool _isLoading = true;

  // muscle-group filter data (โหลดครั้งเดียว, cache ไว้)
  List<MuscleGroup> _muscleGroups = [];
  Map<int, int> _exercisePrimaryGroup = {}; // exerciseId → primary muscleGroupId
  List<MuscleGroup> _planMuscleGroups = []; // groups ที่มีในแผนวันนี้
  Map<int, List<WorkoutResult>> _resultsByExercise = {};
  final Set<int> _pendingDeleteIds = {}; // detailId ที่กำลังรอ undo หลังปัดลบ

  // ── "ท่าถัดไป" (วันนี้เท่านั้น) ───────────────────────────────────────────
  // ชี้ท่าแรกตามลำดับ wsch_order ที่ยังไม่ครบเซต — ไฮไลต์การ์ด + auto-scroll ไปหาครั้งเดียว
  // ตอนเปิดหน้า ไม่ scroll ซ้ำทุกครั้งที่ผลอัปเดต (เช่น กลับมาจากหน้าบันทึกเซต) กันจอกระโดดรำคาญ
  final GlobalKey _nextUpCardKey = GlobalKey();
  bool _didAutoScrollToday = false;

  _PlanExercise? get _nextUpExercise {
    if (!_isToday) return null;
    for (final e in _filtered) {
      if (_getStatus(e) != _ExerciseStatus.done) return e;
    }
    return null;
  }

  void _scheduleAutoScrollToNextUp() {
    if (!_isToday || _didAutoScrollToday) return;
    if (_nextUpExercise == null) return;
    _didAutoScrollToday = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _nextUpCardKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 400), curve: Curves.easeOut, alignment: 0.3);
      }
    });
  }

  // วันที่มีท่าฝึกอยู่แล้วทั้งสัปดาห์ (ไม่ใช่แค่วันที่เลือกอยู่) — ป้อนให้ WeeklyCalendarComponent
  // วาดจุดเขียวสด real-time ทันทีที่เพิ่ม/ลบท่า ทั้งแผนระบบและแผนส่วนตัว (ก่อนหน้านี้ปฏิทินในหน้านี้
  // ไม่เคยส่ง activeDays เลย จุดสถานะเลยไม่เปลี่ยนแม้เพิ่งเพิ่มท่าไปหมาดๆ)
  Set<int> _daysWithExercises = {};

  // แสดงปุ่มรีเซ็ทเฉพาะตอนมีอะไรให้รีเซ็ทจริง — แผนระบบ: ต้องแก้ไขไปจากแม่แบบแล้ว (is_modified),
  // แผนส่วนตัว: ต้องมีท่าฝึกอยู่แล้วอย่างน้อย 1 ท่า (นับทั้งแผนทุกวัน ไม่ใช่แค่วันนี้)
  // ดึงจาก getMyPlans() ที่ backend คำนวณไว้แล้ว ไม่คำนวณซ้ำฝั่ง client กันตรรกะสองฝั่งเพี้ยนจากกัน
  bool _showReset = false;

  @override
  void initState() {
    super.initState();
    // Initialize with current date but adjust to the workout day
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
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
      WorkoutService.to.getSchedulesForDay(widget.planId, dayNum, isCustom: widget.isCustomPlan),
      ExerciseService.to.getWeightExercises(),
      if (fetchMuscleGroups) ExerciseService.to.getMuscleGroups(),
      WorkoutService.to.getWorkoutResults(date: _selectedDate),
      WorkoutService.to.getMyPlans(), // ใช้เช็คว่าควรโชว์ปุ่มรีเซ็ทมั้ย
      // ดึง schedule ทั้งสัปดาห์ (ไม่กรองวัน) ไว้ท้ายสุดเสมอ — ใช้ป้อนจุดสถานะปฏิทิน (activeDays)
      WorkoutService.to.getAllSchedulesForPlan(widget.planId, isCustom: widget.isCustomPlan),
    ];
    final results = await Future.wait(futures);
    if (!mounted) return;

    final schedulesResult = results[0] as Map<String, dynamic>;

    // แผนหายไปจาก DB → แจ้งและกลับหน้าหลัก
    if (schedulesResult['plan_not_found'] == true) {
      setState(() => _isLoading = false);
      showAppAlert(context, 'แผนหายไปจากระบบ กรุณาเลือกหรือสร้างแผนใหม่', type: AppAlertType.warning);
      Navigator.pop(context);
      return;
    }

    final exercisesResult = results[1] as Map<String, dynamic>;
    final Map<int, Exercise> exerciseMap = {};
    if (exercisesResult['success'] == true) {
      final list = (exercisesResult['data'] as List).cast<Exercise>();
      _allExercises = list;
      for (final e in list) { exerciseMap[e.exerciseId] = e; }
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
      final schedules = (schedulesResult['data'] as List).cast<UserWorkoutSchedule>();
      final seenIds = <int>{};
      for (final s in schedules) {
        if (!seenIds.add(s.exerciseId)) continue;
        final ex = exerciseMap[s.exerciseId] ??
            Exercise(
              exerciseId: s.exerciseId,
              exerciseName: s.exerciseName ?? 'ท่าที่ ${s.exerciseId}',
              description: '',
              difficulty: 'beginner',
              imageUrl: s.imageUrl,
            );
        planExercises.add(_PlanExercise(
          detailId: s.scheduleId,
          exercise: ex,
          suggestedSets: s.sets,
          suggestedReps: s.reps,
        ));
      }
    }

    final groupIdsInPlan = planExercises.map((p) => p.exercise.muscleGroupId).whereType<int>().toSet();
    final planMuscleGroups = _muscleGroups.where((g) => groupIdsInPlan.contains(g.groupId)).toList();

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
    // (นับทั้งแผนทุกวัน) ผลลัพธ์นี้ backend คำนวณไว้ให้แล้วใน getMyPlans() ไม่ต้องคำนวณซ้ำ
    bool showReset = false;
    final myPlansResult = results[results.length - 2] as Map<String, dynamic>;
    if (myPlansResult['success'] == true) {
      final plans = (myPlansResult['data'] as List).cast<Map<String, dynamic>>();
      final match = plans.cast<Map<String, dynamic>?>().firstWhere(
            (p) => widget.isCustomPlan
                ? p!['plan_type'] == 'custom' && (p['mwp_id'] as num?)?.toInt() == widget.planId
                : p!['plan_type'] == 'system' && (p['wpt_id'] as num?)?.toInt() == widget.planId,
            orElse: () => null,
          );
      if (match != null) {
        showReset = widget.isCustomPlan
            ? ((match['days_per_week'] as num?)?.toInt() ?? 0) > 0
            : (match['is_modified'] as bool? ?? false);
      }
    }

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

  // ── filtered list ────────────────────────────────────────────────────────
  List<_PlanExercise> get _filtered {
    final base = _planExercises.where((p) => !_pendingDeleteIds.contains(p.detailId));
    if (_selectedGroupId == null) return base.toList();
    return base
        .where((p) => _exercisePrimaryGroup[p.exercise.exerciseId] == _selectedGroupId)
        .toList();
  }

  // ── exercise status helpers ──────────────────────────────────────────────
  Future<void> _refreshResults() async {
    final result = await WorkoutService.to.getWorkoutResults(date: _selectedDate);
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
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
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
            border: Border.all(color: AppColors.statusDoneText.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 11, color: AppColors.statusDoneText),
              const SizedBox(width: 4),
              Text('ทำแล้ว',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.statusDoneText)),
            ],
          ),
        );
      case _ExerciseStatus.incomplete:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.statusPartialBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.statusPartialText.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timelapse_rounded, size: 11, color: AppColors.statusPartialText),
              const SizedBox(width: 4),
              Text('ทำไม่ครบ',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.statusPartialText)),
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
          child: Text('ยังไม่ได้ทำ',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.statusPendingText)),
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
        final result = await WorkoutService.to.removeExerciseFromSchedule(item.detailId);
        if (!mounted) return;
        if (result['success'] == true) {
          setState(() {
            _planExercises.removeWhere((p) => p.detailId == item.detailId);
            _pendingDeleteIds.remove(item.detailId);
            // _planExercises คือท่าของวันที่เลือกอยู่เท่านั้น (โหลดแบบกรองตามวันมาแล้ว) — ถ้าลบ
            // จนว่างหมด แปลว่าวันนี้ไม่มีท่าฝึกเหลือแล้วจริงๆ ต้องเอาออกจาก _daysWithExercises ด้วย
            // ไม่งั้นจุดเขียวบนปฏิทินจะค้าง (เดิมอัปเดตแค่ _planExercises เฉยๆ ไม่แตะปฏิทินเลย
            // ต่างจากตอนเพิ่มท่าที่เรียก _loadPlanExercises() ทั้งก้อนซึ่งคำนวณจุดใหม่ให้อยู่แล้ว)
            if (_planExercises.isEmpty) {
              _daysWithExercises.remove(_currentDayNumber);
            }
            // ตัวกรองกลุ่มกล้ามเนื้อก็ค้างเหมือนกัน (เดิมคำนวณแค่ตอน _loadPlanExercises() เท่านั้น
            // ดังนั้นลบท่าสุดท้ายของกลุ่มไหนไปแล้ว ชิปกลุ่มนั้นก็ยังค้างโชว์อยู่) คำนวณใหม่จาก
            // _planExercises ที่เพิ่งอัปเดตสดๆ ด้วยตรรกะเดียวกับใน _loadPlanExercises()
            final groupIdsInPlan =
                _planExercises.map((p) => p.exercise.muscleGroupId).whereType<int>().toSet();
            _planMuscleGroups = _muscleGroups.where((g) => groupIdsInPlan.contains(g.groupId)).toList();
            // กำลังกรองค้างอยู่ที่กลุ่มที่เพิ่งว่างไป → เด้งกลับ "ทั้งหมด" กันจอค้างว่างเปล่าไม่รู้สาเหตุ
            if (_selectedGroupId != null && !groupIdsInPlan.contains(_selectedGroupId)) {
              _selectedGroupId = null;
            }
          });
        } else {
          // ลบจริงไม่สำเร็จ (เช่นเครือข่ายล้ม) — ดึงข้อมูลจริงจาก server กลับมาแสดงใหม่ กันรายการหายค้างบนจอ
          setState(() => _pendingDeleteIds.remove(item.detailId));
          showAppAlert(context, result['message'] ?? 'ลบท่าออกกำลังกายไม่สำเร็จ', type: AppAlertType.error);
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
        title: Text('แก้ไข ${item.exercise.exerciseName}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
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
              decoration: const InputDecoration(labelText: 'จำนวนครั้ง (เช่น 8-10)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () {
              final sets = int.tryParse(setsController.text.trim());
              final reps = repsController.text.trim();
              if (sets == null || sets < 1) {
                showAppAlert(ctx, 'จำนวนเซ็ตต้องมากกว่า 0', type: AppAlertType.error);
                return;
              }
              Navigator.pop(ctx, (sets, reps));
            },
            child: const Text('บันทึก'),
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
      showAppAlert(context, saveResult['message'] ?? 'แก้ไขไม่สำเร็จ', type: AppAlertType.error);
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

    final existingIds = _planExercises.map((e) => e.exercise.exerciseId).toSet();
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
        maxChildSize: 0.95,
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

  // เพิ่มหลายท่าพร้อมกัน (ตะกร้า) — ไม่มี batch endpoint ฝั่ง backend เลยยิงทีละท่าพร้อมกัน
  // เหมือน pattern _saveAllSelected ของหน้าเพิ่มอาหาร (food_list_view.dart) โหลดครั้งเดียวตอนจบ
  // แทนที่จะ reload ทุกครั้งที่เพิ่มทีละท่าแบบเดิม (กันปิด-เปิดชีทซ้ำๆ ต่อ 1 ท่า)
  Future<void> _addExercisesToPlan(List<Exercise> exercises) async {
    if (exercises.isEmpty) return;
    setState(() => _isLoading = true);
    final results = await Future.wait(exercises.map((ex) => WorkoutService.to.addExerciseToSchedule(
          planId: widget.planId,
          dayNumber: _currentDayNumber,
          wetId: ex.exerciseId,
          isCustom: widget.isCustomPlan,
        )));
    if (!mounted) return;
    final failCount = results.where((r) => r['success'] != true).length;
    await _loadPlanExercises();
    if (!mounted) return;
    if (failCount == 0) {
      showAppAlert(context, 'เพิ่ม ${exercises.length} ท่าแล้ว', type: AppAlertType.success);
    } else if (failCount == exercises.length) {
      showAppAlert(context, 'เพิ่มท่าออกกำลังกายไม่สำเร็จ', type: AppAlertType.error);
    } else {
      showAppAlert(context, 'เพิ่มสำเร็จ ${exercises.length - failCount} ท่า ไม่สำเร็จ $failCount ท่า', type: AppAlertType.warning);
    }
  }

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final showFab = !_isLoading;

    return Scaffold(
      backgroundColor: AppColors.scaffoldGrey,
      floatingActionButton: showFab ? AppFab(onPressed: _showAddExerciseSheet) : null,
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
                  _didAutoScrollToday = false;
                });
                _loadPlanExercises();
              },
            ),
            if (!_isLoading && _planExercises.isEmpty && !_isRestDay)
              _buildAddExerciseTipBanner(),
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
      title: widget.planName.isNotEmpty ? widget.planName : 'ตารางฝึกเวทเทรนนิ่ง',
      subtitle: widget.isWeekdayBased ? 'แผนส่วนตัว' : '${widget.daysPerWeek} วัน / สัปดาห์',
      trailing: _showReset ? _resetButton() : null,
    );
  }

  // ปุ่มคืนค่าเดิม — ระบบ=คัดลอกท่าจากแม่แบบใหม่ทับของเดิม, ส่วนตัว=ล้างท่าออกให้ว่างเปล่า
  // สำคัญขึ้นมาหลังตัดปุ่มคัดลอกเป็นแผนของฉัน (fork) ออก เพราะไม่มีสำเนาสำรองให้กู้ถ้าลบท่าพลาด
  // กด disable ระหว่าง _isLoading กันกดซ้ำ (ตอนนี้ทั้งลิสต์ก็ถูกสลับเป็น spinner อยู่แล้วเช่นกัน)
  Widget _resetButton() => GestureDetector(
        onTap: _isLoading ? null : _confirmReset,
        child: Container(
          width: 38, height: 38,
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
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('คืนค่า', style: TextStyle(color: Colors.red)),
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
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppColors.accentGreen.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.self_improvement_rounded, size: 40, color: AppColors.accentGreen),
            ),
            const SizedBox(height: 16),
            const Text('วันพักผ่อน',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
            const SizedBox(height: 8),
            const Text(
              'ให้ร่างกายได้พักฟื้น\nกล้ามเนื้อซ่อมแซมได้ดีที่สุดในวันพัก',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.25)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle_outline_rounded, size: 16, color: AppColors.primaryGreen),
                  SizedBox(width: 8),
                  Text(
                    'กด + เพื่อเพิ่มท่าฝึกในวันนี้',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryGreen),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // แสดงเมื่อวันพักแต่ผู้ใช้เพิ่มท่าเองแล้ว
  // แสดงเมื่อวันฝึกแต่ยังไม่มีท่า
  Widget _buildAddExerciseTipBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primaryGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.tips_and_updates_rounded, size: 17, color: AppColors.primaryGreen),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'กด + เพื่อเพิ่มท่าออกกำลังกายวันนี้',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primaryGreen),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildExerciseList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
    }

    // วันพักตามแผนและยังไม่มีท่า → แสดง rest day state (FAB ยังแสดงให้เพิ่มได้)
    if (_isRestDay && _planExercises.isEmpty) return _buildRestDayState();

    final exercises = _filtered;
    if (exercises.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fitness_center_outlined, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(
                _planExercises.isEmpty
                    ? 'กด + เพื่อเพิ่มท่าออกกำลังกายวันนี้'
                    : 'ไม่พบท่าในกลุ่มกล้ามเนื้อที่เลือก',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 15, height: 1.5),
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
        : (List<_PlanExercise>.from(exercises)
            ..sort((a, b) => _getStatus(a).index.compareTo(_getStatus(b).index)));

    _scheduleAutoScrollToNextUp();

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

    _scheduleAutoScrollToNextUp();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(23, 4, 23, 100),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is MuscleGroup) return _sectionHeader(item, grouped[item.groupId]!.length);
        if (item is _OtherGroupMarker) return _sectionHeader(null, noGroup.length);

        final planExercise = item as _PlanExercise;
        final gid = _exercisePrimaryGroup[planExercise.exercise.exerciseId];
        final siblings = gid != null ? grouped[gid]! : noGroup;
        return _exerciseCard(planExercise, ordinal: siblings.indexOf(planExercise) + 1);
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
              child: SizedBox(width: 24, height: 24, child: cachedImage(fullUrl, fit: BoxFit.cover)),
            )
          else
            Container(
              width: 8, height: 18,
              decoration: BoxDecoration(color: AppColors.primaryGreen, borderRadius: BorderRadius.circular(3)),
            ),
          const SizedBox(width: 10),
          Text(
            group?.groupName ?? 'อื่นๆ',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textDark),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: const Color(0xFFECECEC))),
          const SizedBox(width: 8),
          Text('$count ท่า',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  // การ์ดท่าฝึก 1 ท่า — ใช้ทั้งโหมด flat และ grouped (ordinal = เลขลำดับในกลุ่ม แสดงเฉพาะโหมด grouped)
  Widget _exerciseCard(_PlanExercise item, {int? ordinal}) {
    final isNextUp = _isToday && item.detailId == _nextUpExercise?.detailId;
    final card = SwipeDeleteItem(
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
              planId: widget.planId,
              isCustomPlan: widget.isCustomPlan,
            ),
          ),
        ).then((_) => _refreshResults()),
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
            // "ท่าถัดไป" ของวันนี้ — ไฮไลต์ด้วยกรอบแทนตำแหน่ง เพราะลำดับ list ต้องคงที่ตาม wsch_order
            border: isNextUp ? Border.all(color: AppColors.primaryGreen, width: 1.5) : null,
          ),
          child: Row(
            children: [
              if (ordinal != null) ...[
                Container(
                  width: 22, height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Text('$ordinal',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: AppColors.primaryGreen)),
                ),
                const SizedBox(width: 10),
              ],
              Container(
                width: 62, height: 62,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: (item.exercise.imageUrl != null && item.exercise.imageUrl!.isNotEmpty)
                      ? cachedImage(item.exercise.imageUrl!, fit: BoxFit.cover)
                      : const Icon(Icons.fitness_center, color: AppColors.primaryGreen, size: 30),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.exercise.exerciseName,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
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
                        _badge('${item.suggestedReps} ครั้ง', const Color(0xFFF0F0F0), Colors.black54),
                        if (item.exercise.muscleGroupName.isNotEmpty)
                          _badge(item.exercise.muscleGroupName, const Color(0xFFEEF2FF), const Color(0xFF5B6CF6)),
                      ],
                    ),
                    if (item.exercise.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.exercise.description,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
                  child: const Icon(Icons.edit_outlined,
                      size: 18, color: AppColors.primaryGreen),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return isNextUp ? KeyedSubtree(key: _nextUpCardKey, child: card) : card;
  }

  // พื้นหลังตอนปัดลบท่าฝึก — ทรงเดียวกับการ์ดท่าฝึก (margin/borderRadius ตรงกัน) กันมุมโผล่ตอนปัด
  Widget _exerciseDismissBg() => Container(
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(20)),
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
              ? (group.imageUrl!.startsWith('http') ? group.imageUrl! : '${ApiClient.serverUrl}/${group.imageUrl}')
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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
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
  Map<int, Set<int>> _exerciseIdsByGroup = {};
  bool _groupsLoading = true;

  void _toggleSelect(Exercise ex) {
    setState(() {
      if (!_selectedIds.remove(ex.exerciseId)) _selectedIds.add(ex.exerciseId);
    });
  }

  void _confirm() {
    final selected = widget.exercises.where((e) => _selectedIds.contains(e.exerciseId)).toList();
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

    // Build groupId → exerciseIds directly from exercise.muscleGroupId — no extra API call
    final Map<int, Set<int>> map = {};
    for (final e in widget.exercises) {
      if (e.muscleGroupId != null) {
        map.putIfAbsent(e.muscleGroupId!, () => <int>{}).add(e.exerciseId);
      }
    }

    setState(() {
      _muscleGroups = groups;
      _exerciseIdsByGroup = map;
      _groupsLoading = false;
    });
  }

  List<Exercise> get _filtered {
    var list = widget.exercises;
    if (_selectedGroupId != null) {
      final ids = _exerciseIdsByGroup[_selectedGroupId] ?? <int>{};
      list = list.where((e) => ids.contains(e.exerciseId)).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((e) => e.exerciseName.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Stack(
      children: [
      Column(
      children: [
        // Handle
        const SizedBox(height: 12),
        Container(
          width: 36, height: 4,
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
                child: Text('เลือกท่าออกกำลังกาย',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${filtered.length} ท่า',
                  style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
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
                      ? (g.imageUrl!.startsWith('http') ? g.imageUrl! : '${ApiClient.serverUrl}/${g.imageUrl}')
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
                      Icon(Icons.search_off_rounded,
                          size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 10),
                      const Text('ไม่พบท่าออกกำลังกาย',
                          style: TextStyle(color: Colors.black54, fontSize: 14)),
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
    );
  }

  // ── grouped list (ทั้งหมด mode) ────────────────────────────────────────────
  Widget _groupedList(List<Exercise> exercises) {
    // reverse map: exerciseId → groupId
    final Map<int, int> exToGroup = {};
    for (final entry in _exerciseIdsByGroup.entries) {
      for (final id in entry.value) {
        exToGroup[id] = entry.key;
      }
    }

    final Map<int, List<Exercise>> grouped = {};
    final List<Exercise> noGroup = [];
    for (final ex in exercises) {
      final gid = exToGroup[ex.exerciseId];
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
        if (item is String)     return _groupHeader(item, muted: true);
        return _exerciseRow(item as Exercise);
      },
    );
  }

  Widget _groupHeader(String name, {bool muted = false}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Row(
          children: [
            Container(
              width: 4, height: 14,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: muted ? AppColors.textMuted : AppColors.primaryGreen,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: muted ? AppColors.textMuted : AppColors.textDark,
                )),
          ],
        ),
      );

  // ── flat list (filtered mode / no group data) ──────────────────────────────
  Widget _flatList(List<Exercise> exercises) => ListView.separated(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        itemCount: exercises.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Color(0xFFF4F4F6), indent: 72),
        itemBuilder: (ctx, i) => _exerciseRow(exercises[i]),
      );

  // ── single exercise row ── แตะเพื่อติ๊กเข้า/ออกตะกร้า (ไม่ปิดชีท) ───────────────
  Widget _exerciseRow(Exercise ex) {
    final isSelected = _selectedIds.contains(ex.exerciseId);
    return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggleSelect(ex),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isSelected ? Border.all(color: AppColors.primaryGreen, width: 1.5) : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 52, height: 52,
                      child: (ex.imageUrl != null && ex.imageUrl!.isNotEmpty)
                          ? cachedImage(ex.imageUrl!, fit: BoxFit.cover)
                          : _placeholder(),
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      top: -4, right: -4,
                      child: Container(
                        width: 18, height: 18,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: AppColors.primaryGreen, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded, color: Colors.white, size: 13),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ex.exerciseName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F4F6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        ex.equipment.label,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : AppColors.primaryGreen,
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected ? Border.all(color: AppColors.primaryGreen, width: 1.5) : null,
                  boxShadow: isSelected
                      ? null
                      : [BoxShadow(color: AppColors.primaryGreen.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Icon(
                  isSelected ? Icons.check_rounded : Icons.add_rounded,
                  color: isSelected ? AppColors.primaryGreen : Colors.white,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      );
  }

  Widget _placeholder() => Container(
        color: AppColors.primaryGreen.withValues(alpha: 0.08),
        child: const Icon(Icons.fitness_center,
            color: AppColors.primaryGreen, size: 22),
      );

}
