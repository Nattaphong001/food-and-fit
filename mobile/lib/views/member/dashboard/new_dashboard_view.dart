import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:math' as math;
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../models/analytics_model.dart';
import '../../../models/nutrition_model.dart';
import '../../../models/workout_model.dart';
import '../../../services/analytics_service.dart';
import '../../../services/member_service.dart';
import '../../../services/workout_service.dart';
import '../../../services/nutrition_service.dart';
import '../../../services/api_client.dart';

enum _ViewMode { graph, table }

class NewDashboardView extends StatefulWidget {
  final ValueNotifier<int>? refreshNotifier;
  // แยกจาก refreshNotifier — bump จาก HomeView เมื่อแก้ข้อมูลร่างกาย/เป้าหมายสำเร็จเท่านั้น
  // (refreshNotifier ตัวเดิมถูก bump จาก NutritionView เองด้วย ใช้ตัวเดียวกันจะวนลูปโหลดซ้ำ)
  final ValueNotifier<int>? profileRefreshNotifier;
  const NewDashboardView({super.key, this.refreshNotifier, this.profileRefreshNotifier});

  @override
  State<NewDashboardView> createState() => _NewDashboardViewState();
}

class _NewDashboardViewState extends State<NewDashboardView>
    with SingleTickerProviderStateMixin {
  late TabController _sectionTab;
  int _selectedPeriod = 0;
  _ViewMode _viewMode = _ViewMode.graph;
  DateTime _selectedDate = DateTime.now();
  DateTime _selectedMonth = DateTime.now();
  DateTime _selectedWeekEnd = DateTime.now(); // วันสุดท้ายของช่วง 7 วันที่ดู (คำสั่งที่ 11)

  DailyAnalytics?           _daily;
  List<MealBreakdown>       _meals       = [];
  WeeklyAnalytics?          _weekly;
  MonthlyAnalytics?         _monthly;
  MonthlyAnalytics?         _prevMonthly; // เดือนก่อนหน้า — ใช้ต่อ streak ข้ามเดือน (คำสั่งที่ 14)
  MonthlyComparison?        _comparison;
  ProgressReport?           _progress;
  List<MuscleGroupCoverage> _muscles     = [];
  List<WorkoutResult>       _workoutResults = [];
  List<CardioResult>        _cardioResults  = [];
  List<DailyNutrition>      _foods          = [];
  bool _isLoading = true;
  // ปิดเฉพาะรอบโหลดครั้งแรก — บังทั้งหน้า (header/ปุ่มกรอง/tab bar) ไม่ให้โผล่ก่อนข้อมูลชุดแรก
  // มาครบ ต่างจาก _isLoading ที่คุมแค่พื้นที่เนื้อหาแท็บตอนสลับวัน/สัปดาห์/เดือนทีหลัง
  bool _initialLoading = true;

  String?  _insightMsg;
  Color    _insightColor = AppColors.primaryGreen;
  IconData _insightIcon  = Icons.lightbulb_outline_rounded;

  @override
  void initState() {
    super.initState();
    _sectionTab = TabController(length: 4, vsync: this);
    widget.refreshNotifier?.addListener(_loadData);
    widget.profileRefreshNotifier?.addListener(_loadData);
    _loadData();
  }

  @override
  void dispose() {
    _sectionTab.dispose();
    widget.refreshNotifier?.removeListener(_loadData);
    widget.profileRefreshNotifier?.removeListener(_loadData);
    super.dispose();
  }

  static Map<String, dynamic> _asFailure(Object e) =>
      {'success': false, 'message': e.toString()};

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// เติมวันที่ที่ไม่มีข้อมูลให้เป็นจุดค่า 0 เพื่อให้ชุดข้อมูลมีจำนวนวันครบตามช่วงเวลา
  /// จำเป็นเพราะ date_list ฝั่ง SQL (dailySumRangeSQL/dailySumBetweenSQL) เป็น UNION ของวันที่
  /// ที่มีบันทึกจริงอย่างน้อย 1 รายการ (nutrition/cardio/weight) เท่านั้น — วันที่ไม่มีกิจกรรม
  /// เลยจะหายไปทั้งแถว ไม่ได้คืนมาเป็น 0 ทุกจุดที่สมมติว่าจำนวนแถว = จำนวนวันในช่วงจะพัง
  /// ถ้าไม่เติมช่องว่างนี้ก่อน (คำสั่งที่ 17)
  ///
  /// ⚠️ ห้ามเอาผลลัพธ์จากฟังก์ชันนี้ไปหาร "ค่าเฉลี่ยปริมาณ" (เช่น weeklyAvgCalories) เพราะ
  /// densify เติม 0 ให้วันที่ไม่มีบันทึก ซึ่ง "ไม่มีข้อมูล" ไม่เท่ากับ "ศูนย์" — การหารด้วย
  /// ความยาวชุด dense จะเป็นการยืนยันว่าวันนั้นกิน/เผา 0 kcal จริง ทั้งที่ความจริงคือไม่รู้
  /// (ดูคำสั่งที่ 19) ใช้ผลลัพธ์นี้ได้เฉพาะกับสองประเภทงาน:
  ///   1. กราฟที่ต้องมีจุดครบทุกวันเพื่อไม่ให้เส้น/แท่งบิดเบือน (เว้นช่องว่างให้ถูกวัน)
  ///   2. เมตริกที่ "วัดการปฏิบัติ" ไม่ใช่ "วัดปริมาณ" เช่น เป้าหมายรายสัปดาห์/ความสม่ำเสมอ/
  ///      Adherence/streak ซึ่งวันที่ไม่บันทึก = ไม่ได้ทำตามเป้าจริง ตัวหาร 7 วันปฏิทินถูกต้อง
  ///      (ดู _weeklyGoalDays ด้านล่างเทียบ)
  /// ส่วนค่าเฉลี่ยปริมาณ (weeklyAvgCalories/monthlyAvgCalories/cmp.avgCal) ต้องหารด้วย
  /// "จำนวนวันที่บันทึกจริง" เท่านั้น — คำนวณจากชุดข้อมูลดิบก่อน densify (ดู recordedDays
  /// ใน _buildWeeklyMacroAverages / MonthStat.recordedDays)
  static List<T> _densify<T>({
    required List<T> raw,
    required DateTime start,
    required DateTime end,
    required String Function(T) dateOf,
    required T Function(String date) emptyOf,
  }) {
    final byDate = {for (final item in raw) dateOf(item).split('T').first: item};
    final out = <T>[];
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final key = _isoDate(d);
      out.add(byDate[key] ?? emptyOf(key));
    }
    return out;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await Future.wait([_loadDateScoped(showLoading: false), _loadStatic(showLoading: false)]);
    if (!mounted) return;
    // _loadDateScoped/_loadStatic รันพร้อมกัน — _computeInsight() ในตัวแรกอาจทำงานก่อน
    // _weekly ของตัวหลังมาถึง คำนวณซ้ำอีกครั้งหลังทั้งคู่เสร็จกันค่า insight ค้างผิด
    setState(() {
      _isLoading = false;
      _initialLoading = false;
      _computeInsight();
    });
  }

  /// ชุดข้อมูลที่ขึ้นกับวันที่เลือก (_selectedDate) — เรียกตอนเลื่อน/เลือกวันโดยไม่ต้อง
  /// โหลดชุด static ซ้ำ (คำสั่งที่ 12)
  Future<void> _loadDateScoped({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) setState(() => _isLoading = true);
    final r = await Future.wait([
      AnalyticsService.to.getDailyAnalytics(date: _selectedDate).catchError(_asFailure),
      AnalyticsService.to.getDailyMealBreakdown(date: _selectedDate).catchError(_asFailure),
      WorkoutService.to.getWorkoutResults(date: _selectedDate).catchError(_asFailure),
      WorkoutService.to.getCardioResults(date: _selectedDate).catchError(_asFailure),
      NutritionService.to.getDailyNutrition(date: _selectedDate).catchError(_asFailure),
    ]);
    if (!mounted) return;
    const labels = ['พลังงานรายวัน', 'มื้ออาหาร', 'ผลเวทเทรนนิ่ง', 'ผลคาร์ดิโอ', 'โภชนาการรายวัน'];
    final failed = <String>[];
    setState(() {
      if (showLoading) _isLoading = false;
      if (r[0]['success'] == true) { _daily           = r[0]['data'] as DailyAnalytics; } else { failed.add(labels[0]); }
      if (r[1]['success'] == true) { _meals           = r[1]['data'] as List<MealBreakdown>; } else { failed.add(labels[1]); }
      if (r[2]['success'] == true) { _workoutResults  = r[2]['data'] as List<WorkoutResult>; } else { failed.add(labels[2]); }
      if (r[3]['success'] == true) { _cardioResults   = r[3]['data'] as List<CardioResult>; } else { failed.add(labels[3]); }
      if (r[4]['success'] == true) { _foods           = r[4]['data'] as List<DailyNutrition>; } else { failed.add(labels[4]); }
      _computeInsight();
    });
    if (failed.isNotEmpty && mounted) {
      showAppAlert(context, 'โหลดข้อมูลบางส่วนไม่สำเร็จ: ${failed.join(', ')}',
          type: AppAlertType.error);
    }
  }

  /// ชุดข้อมูลที่ไม่ขึ้นกับ _selectedDate (สัปดาห์/เดือน/เทียบเดือน/ความก้าวหน้า/กล้ามเนื้อ)
  /// (คำสั่งที่ 12) — รวมดึงเดือนก่อนหน้าไว้ต่อ streak ข้ามเดือน (คำสั่งที่ 14)
  Future<void> _loadStatic({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) setState(() => _isLoading = true);
    final monthParam =
        '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';
    final prevMonthDate = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
    final prevMonthParam =
        '${prevMonthDate.year}-${prevMonthDate.month.toString().padLeft(2, '0')}';
    final r = await Future.wait([
      AnalyticsService.to.getWeeklyAnalytics(date: _selectedWeekEnd).catchError(_asFailure),
      AnalyticsService.to.getMonthlyAnalytics(month: monthParam).catchError(_asFailure),
      AnalyticsService.to.getMonthlyAnalytics(month: prevMonthParam).catchError(_asFailure),
      AnalyticsService.to.getMonthlyComparison(month: monthParam).catchError(_asFailure),
      AnalyticsService.to.getProgressReport().catchError(_asFailure),
      AnalyticsService.to.getMuscleGroupCoverage(days: 7).catchError(_asFailure),
    ]);
    if (!mounted) return;
    const labels = [
      'สรุปรายสัปดาห์', 'สรุปรายเดือน', 'สรุปเดือนก่อนหน้า',
      'เทียบเดือนก่อน', 'ความก้าวหน้า', 'กล้ามเนื้อที่ฝึก',
    ];
    final weekStart = _selectedWeekEnd.subtract(const Duration(days: 6));
    final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final monthLastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final today = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == today.year && _selectedMonth.month == today.month;
    // เดือนปัจจุบัน — เติมช่องว่างแค่ถึงวันนี้ ไม่งั้นกราฟจะมีหางแบนยาวไปถึงสิ้นเดือนที่ยังไม่ถึง
    final monthEnd = isCurrentMonth ? DateTime(today.year, today.month, today.day) : monthLastDay;
    final prevMonthStart = DateTime(prevMonthDate.year, prevMonthDate.month, 1);
    final prevMonthLastDay = DateTime(prevMonthDate.year, prevMonthDate.month + 1, 0);

    final failed = <String>[];
    setState(() {
      if (showLoading) _isLoading = false;
      if (r[0]['success'] == true) {
        final wa = r[0]['data'] as WeeklyAnalytics;
        _weekly = WeeklyAnalytics(
          weekData: _densify(
            raw: wa.weekData, start: weekStart, end: _selectedWeekEnd,
            dateOf: (e) => e.date,
            emptyOf: (date) => WeeklyDataPoint(date: date, calories: 0, caloriesOut: 0),
          ),
          weeklyAvgCalories: wa.weeklyAvgCalories,
          weeklyAvgCaloriesOut: wa.weeklyAvgCaloriesOut,
        );
      } else { failed.add(labels[0]); }
      if (r[1]['success'] == true) {
        final ma = r[1]['data'] as MonthlyAnalytics;
        _monthly = MonthlyAnalytics(
          monthData: _densify(
            raw: ma.monthData, start: monthStart, end: monthEnd,
            dateOf: (e) => e.date,
            emptyOf: (date) => MonthlyDataPoint(date: date, calories: 0, caloriesOut: 0),
          ),
          monthlyAvgCalories: ma.monthlyAvgCalories,
          monthlyAvgCaloriesOut: ma.monthlyAvgCaloriesOut,
        );
      } else { failed.add(labels[1]); }
      // เดือนก่อนหน้าใช้เฉพาะต่อ streak — โหลดไม่สำเร็จไม่ต้องรบกวนผู้ใช้ด้วย alert
      if (r[2]['success'] == true) {
        final pma = r[2]['data'] as MonthlyAnalytics;
        _prevMonthly = MonthlyAnalytics(
          monthData: _densify(
            raw: pma.monthData, start: prevMonthStart, end: prevMonthLastDay,
            dateOf: (e) => e.date,
            emptyOf: (date) => MonthlyDataPoint(date: date, calories: 0, caloriesOut: 0),
          ),
          monthlyAvgCalories: pma.monthlyAvgCalories,
          monthlyAvgCaloriesOut: pma.monthlyAvgCaloriesOut,
        );
      }
      if (r[3]['success'] == true) { _comparison  = r[3]['data'] as MonthlyComparison?; } else { failed.add(labels[3]); }
      if (r[4]['success'] == true) { _progress    = r[4]['data'] as ProgressReport; } else { failed.add(labels[4]); }
      if (r[5]['success'] == true) { _muscles     = r[5]['data'] as List<MuscleGroupCoverage>; } else { failed.add(labels[5]); }
    });
    if (failed.isNotEmpty && mounted) {
      showAppAlert(context, 'โหลดข้อมูลบางส่วนไม่สำเร็จ: ${failed.join(', ')}',
          type: AppAlertType.error);
    }
  }

  void _computeInsight() {
    if (_daily == null) { _insightMsg = null; return; }
    final d = _daily!;

    // ยังไม่มีข้อมูลนำเข้า — ไม่ประเมินผล เพื่อไม่ให้แนะนำจากค่า 0
    if (d.totalCaloriesIn <= 0) {
      _insightMsg   = 'ยังไม่ได้บันทึกอาหารวันนี้ — บันทึกเพื่อดูผลวิเคราะห์สมดุลพลังงาน';
      _insightColor = AppColors.textMuted;
      _insightIcon  = Icons.edit_note_rounded;
      return;
    }
    if (d.totalProtein < _targetProtein * 0.6) {
      _insightMsg   = 'โปรตีนน้อยไป — เพิ่มอีก ${(_targetProtein - d.totalProtein).round()}g ช่วยรักษากล้ามเนื้อ';
      _insightColor = const Color(0xFF5B8CFF);
      _insightIcon  = Icons.fitness_center_rounded;
    } else if (d.totalCaloriesIn > _targetCalories * (1 + _kTargetTolerance)) {
      _insightMsg   = 'แคลอรี่เกินเป้า +${(d.totalCaloriesIn - _targetCalories).round()}kcal — ลองเดิน 30 นาทีเพิ่ม';
      _insightColor = Colors.orange;
      _insightIcon  = Icons.directions_walk_rounded;
    } else if (_workoutDaysThisWeek == 0 && (_weekly?.weekData.isNotEmpty ?? false)) {
      _insightMsg   = 'สัปดาห์นี้ยังไม่ได้ออกกำลังกายเลย — เริ่มเบาๆ วันนี้เลย!';
      _insightColor = Colors.orange;
      _insightIcon  = Icons.emoji_events_rounded;
    } else if (d.exerciseBurn > 300) {
      _insightMsg   = 'เผาผลาญจากการออกกำลังกาย ${d.exerciseBurn.round()}kcal — ยอดเยี่ยม! 🔥';
      _insightColor = AppColors.primaryGreen;
      _insightIcon  = Icons.local_fire_department_rounded;
    } else {
      _insightMsg = null;
    }
  }

  // ── Getters ────────────────────────────────────────────────────────────────
  double get _caloriesIn   => _daily?.totalCaloriesIn  ?? 0;
  double get _caloriesOut  => _daily?.totalCaloriesOut ?? 0;
  double get _targetCalories   => (_daily?.targetTdee ?? 0) > 0 ? _daily!.targetTdee : 0;
  bool   get _hasTarget    => _targetCalories > 0;
  double get _bmi          => _daily?.bmi          ?? 0;
  double get _bmr          => _daily?.bmr          ?? 0;
  double get _tdee         => _daily?.tdee         ?? 0;
  double get _exerciseBurn => _daily?.exerciseBurn ?? 0;
  double get _baseline     => _daily?.baseline     ?? 0;
  double get _balance      => _daily?.balance      ?? 0;
  int    get _goalType     => _daily?.goalType     ?? 1;

  int get _workoutDaysThisWeek =>
      _weekly?.weekData.where((e) => e.cardioOut > 0 || e.weightOut > 0).length ?? 0;

  int get _activeStreak {
    // badge นี้โชว์ที่ header เสมอไม่ขึ้นกับ tab/period — ต้องเป็น streak ของ "วันนี้" จริงๆ
    // เท่านั้น ถ้า user เลื่อนดู _monthly ของเดือนอื่นอยู่ (ผ่านโหมดรายเดือน) ต้องไม่เอา
    // monthData ของเดือนที่กำลังดูมาคำนวณ ไม่งั้น badge จะโชว์ streak ของเดือนเก่าแทน
    final now = DateTime.now();
    if (_selectedMonth.year != now.year || _selectedMonth.month != now.month) return 0;
    final pts = _monthly?.monthData ?? [];
    if (pts.isEmpty) return 0;
    bool active(MonthlyDataPoint p) => p.calories > 0 || p.weightOut > 0 || p.cardioOut > 0;

    // pts เป็นชุด densify แล้ว (คำสั่งที่ 17) จึงมีครบทุกวันแบบไม่มีช่องว่าง — pts.last คือ
    // "วันนี้" เสมอ (densify ตัดจบที่วันนี้สำหรับเดือนปัจจุบัน) เดินถอยหลังทีละวันแล้วเจอวันว่าง
    // (ไม่มีบันทึกจริง) เมื่อไหร่ = ขาดตอนจริง หยุดนับทันที (เดิมนับข้ามช่องว่างเพราะ backend
    // ไม่คืนวันว่างมาเลย ตอนนี้ densify เติมให้แล้วลูปเดิมทำงานถูกต้องเอง)
    //
    // ข้อยกเว้น: ถ้า "วันนี้" ยังไม่มีบันทึก ยังไม่ถือว่าขาดตอน (วันนี้ยังไม่จบ) ให้เริ่มนับจาก
    // เมื่อวานแทน ตามมาตรฐานแอปนับ streak ทั่วไป (เช่น Duolingo) — ถือว่าขาดตอนจริงก็ต่อเมื่อ
    // เมื่อวานก็ไม่มีข้อมูลด้วย (ตัดสินใจตามคำสั่งที่ 18 ข้อ 4: เคส "ฝึกล่าสุดคือเมื่อวาน" ยังนับ
    // streak ต่อ ไม่รีเซ็ตเป็น 0)
    int start = pts.length - 1;
    if (!active(pts[start])) start--;

    int s = 0;
    bool continuedFromDay1 = start >= 0;
    for (int i = start; i >= 0; i--) {
      if (active(pts[i])) {
        s++;
      } else {
        continuedFromDay1 = false;
        break;
      }
    }
    // ถ้าฝึกต่อเนื่องตั้งแต่วันที่ 1 ของเดือนนี้ (หรือเมื่อวาน กรณีวันนี้ยังไม่บันทึก) ไม่มีวันขาด
    // เลย ให้นับต่อจาก monthData ของเดือนก่อนหน้า (_prevMonthly) กันไม่ให้ streak รีเซ็ตทุกครั้ง
    // ที่ข้ามเดือน (คำสั่งที่ 14)
    if (continuedFromDay1) {
      final prevPts = _prevMonthly?.monthData ?? [];
      for (int i = prevPts.length - 1; i >= 0; i--) {
        if (active(prevPts[i])) {
          s++;
        } else {
          break;
        }
      }
    }
    return s;
  }

  // ตัวหาร 7 วันปฏิทินที่ใช้ในนี้ถูกต้องแล้ว — คนละนิยามกับค่าเฉลี่ยปริมาณ (weeklyAvgCalories
  // เป็นต้น) ที่ต้องหารด้วยจำนวนวันที่บันทึกจริงเท่านั้น (ดูหมายเหตุเหนือ _densify) เพราะตรงนี้
  // "วัดการปฏิบัติตามเป้า" ไม่ใช่ "วัดปริมาณ" — วันที่ไม่บันทึก = ไม่ได้ทำตามเป้าจริง ไม่ใช่
  // ไม่มีข้อมูล ห้ามแก้ให้ไปหารด้วยจำนวนวันที่บันทึกเพื่อให้ "สอดคล้องกัน" กับตัวหารฝั่งค่าเฉลี่ย
  int get _weeklyGoalDays {
    final pts = _weekly?.weekData ?? [];
    return pts.where((e) {
      final t = _targetCalories;
      return t > 0 &&
          e.calories >= t * (1 - _kTargetTolerance) &&
          e.calories <= t * (1 + _kTargetTolerance);
    }).length;
  }

  double get _adherenceRate {
    final target = math.max(1, WorkoutService.to.activePlanDays);
    return (_workoutDaysThisWeek / target).clamp(0.0, 1.0);
  }

  Map<String, double> get _macroTargetPct {
    switch (_goalType) {
      case 1:  return {'protein': 0.40, 'carb': 0.35, 'fat': 0.25};
      case 2:  return {'protein': 0.30, 'carb': 0.50, 'fat': 0.20};
      default: return {'protein': 0.20, 'carb': 0.50, 'fat': 0.30};
    }
  }

  double get _targetProtein => _targetCalories * _macroTargetPct['protein']! / 4;
  double get _targetCarbs   => _targetCalories * _macroTargetPct['carb']!    / 4;
  double get _targetFat     => _targetCalories * _macroTargetPct['fat']!     / 9;

  String get _bmiCategory {
    if (_bmi <= 0)   return '-';           // ยังไม่มีข้อมูลร่างกาย
    if (_bmi < 18.5) return 'ผอมเกินไป';   // ใช้คำเดียวกับ bands และเอกสารบทที่ 2
    if (_bmi < 23.0) return 'สมส่วน';
    if (_bmi < 25.0) return 'น้ำหนักเกิน';
    return 'โรคอ้วน';
  }

  Color get _bmiColor {
    if (_bmi <= 0)   return AppColors.textMuted;
    if (_bmi < 18.5) return Colors.blueAccent;
    if (_bmi < 23.0) return AppColors.primaryGreen;
    if (_bmi < 25.0) return Colors.orange;
    return Colors.redAccent;
  }

  String get _goalLabel {
    switch (_goalType) {
      case 2:  return 'เพิ่มน้ำหนัก';
      case 3:  return 'รักษาน้ำหนัก';
      default: return 'ลดน้ำหนัก';
    }
  }

  // ใช้ _energyStatus เป็นแหล่งความจริงเดียวกับ badge สถานะบนการ์ดเดียวกัน
  // ทิศทางของ Balance (เพิ่ม/ลด) สื่อผ่านไอคอน 📈/📉 ใน _flowItem แทนสีคนละชุด
  Color get _balanceColor => _energyStatus(_caloriesIn, _targetCalories).$2;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return 'สวัสดีตอนดึก';
    if (h < 12) return 'อรุณสวัสดิ์';
    if (h < 17) return 'สวัสดีตอนบ่าย';
    if (h < 20) return 'สวัสดีตอนเย็น';
    return 'สวัสดีตอนดึก';
  }

  static const _moShort = ['ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.',
                            'ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.'];

  String get _todayLabel {
    final n = DateTime.now();
    return '${n.day} ${_moShort[n.month - 1]} ${n.year + 543}';
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String get _selectedDateLabel {
    if (_isSameDay(_selectedDate, DateTime.now())) return 'วันนี้';
    return '${_selectedDate.day} ${_moShort[_selectedDate.month - 1]} ${_selectedDate.year + 543}';
  }

  String get _selectedMonthLabel {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year && _selectedMonth.month == now.month) return 'เดือนนี้';
    return '${_moShort[_selectedMonth.month - 1]} ${_selectedMonth.year + 543}';
  }

  String get _selectedWeekLabel {
    if (_isSameDay(_selectedWeekEnd, DateTime.now())) return '7 วันล่าสุด';
    final start = _selectedWeekEnd.subtract(const Duration(days: 6));
    final sameMonth = start.month == _selectedWeekEnd.month && start.year == _selectedWeekEnd.year;
    final startLabel = sameMonth ? '${start.day}' : '${start.day} ${_moShort[start.month - 1]}';
    return '$startLabel – ${_selectedWeekEnd.day} ${_moShort[_selectedWeekEnd.month - 1]} ${_selectedWeekEnd.year + 543}';
  }

  /// เกณฑ์ประเมินสถานะสมดุลพลังงาน ±10% ตามบทที่ 2 หัวข้อ 2.1.4.7
  static const double _kTargetTolerance = 0.10;

  /// สถานะ Energy Balance เทียบเป้าหมาย ±10%
  (String, Color) _energyStatus(double caloriesIn, double target) {
    if (target <= 0) return ('-', AppColors.textMuted);
    final ratio = caloriesIn / target;
    if (ratio > 1.1) return ('เกินเป้า', Colors.redAccent);
    if (ratio < 0.9) return ('ต่ำกว่าเป้า', Colors.orange);
    return ('ตามเป้า', AppColors.primaryGreen);
  }

  String _intensityLabel(int? lvl) {
    switch (lvl) {
      case 1:  return 'เบา';
      case 2:  return 'กลาง';
      case 3:  return 'หนัก';
      default: return '-';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    // รอบโหลดครั้งแรก — บังทั้งหน้ารวมปุ่ม/header ไม่ให้โผล่มาก่อนข้อมูลชุดแรกพร้อม
    if (_initialLoading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(bottom: false, child: _buildShimmer()),
      );
    }
    return Scaffold(
      // โปร่งใส — ให้พื้นหลังร่วมของ MainShell โชว์ผ่านตลอด กัน navbar เห็นแต่สีทึบเรียบๆ
      backgroundColor: Colors.transparent,
      // bottom: false — extendBody อัด MediaQuery.padding.bottom เท่าความสูง navbar มาให้ SafeArea
      // กิน ถ้าไม่ปิด content จะหดขึ้นไปหยุดเหนือ navbar เสมอ (extendBody เลยไม่มีผลอะไรเลย)
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _buildHeader(),
          const SizedBox(height: 10),
          _buildPeriodFilter(),
          const SizedBox(height: 8),
          _buildDateSelector(),
          const SizedBox(height: 8),
          _buildSectionTabBar(),
          const SizedBox(height: 4),
          Expanded(
            child: _isLoading
                ? _buildShimmer()
                : TabBarView(
                    controller: _sectionTab,
                    children: [
                      _buildEnergyTab(),
                      _buildNutritionTab(),
                      _buildExerciseTab(),
                      _buildBmiTab(),
                    ],
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _buildShimmer() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
    children: List.generate(4, (_) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 120,
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: const _ShimmerBox(),
    )),
  );

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() => Container(
    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
          colors: [Color(0xFF0F2027), Color(0xFF1C3A2A)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_greeting, style: const TextStyle(fontSize: 11,
            color: AppColors.primaryGreen, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 3),
        Obx(() {
          final name = MemberService.to.currentUser.value?.fullName ?? 'ผู้ใช้';
          return Text(name, style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white));
        }),
        const SizedBox(height: 2),
        Text(_todayLabel, style: TextStyle(
            fontSize: 11, color: Colors.white.withValues(alpha: 0.45))),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _hBadge(_goalLabel, AppColors.primaryGreen, Icons.flag_rounded),
        if (_activeStreak > 1) ...[
          const SizedBox(height: 6),
          _hBadge(' $_activeStreak วันติดกัน', Colors.orange,
              Icons.local_fire_department_rounded),
        ],
      ]),
    ]),
  );

  Widget _hBadge(String text, Color c, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.3))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: c, size: 11),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c)),
    ]),
  );

  // ── Period Filter ──────────────────────────────────────────────────────────
  Widget _buildPeriodFilter() {
    const labels = ['รายวัน', 'สัปดาห์', 'รายเดือน'];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)]),
      child: Row(children: List.generate(3, (i) {
        final sel = _selectedPeriod == i;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedPeriod = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(left: i > 0 ? 4 : 0),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                  color: sel ? AppColors.primaryGreen : Colors.transparent,
                  borderRadius: BorderRadius.circular(10)),
              child: Text(labels[i], textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: sel ? Colors.black87 : AppColors.textMuted)),
            ),
          ),
        );
      })),
    );
  }

  // ── Date / Month Selector ──────────────────────────────────────────────────
  Widget _buildDateSelector() {
    switch (_selectedPeriod) {
      case 0:
        final isToday = _isSameDay(_selectedDate, DateTime.now());
        return _dateNavRow(
          label: _selectedDateLabel,
          onPrev: () => _shiftDate(-1),
          onNext: isToday ? null : () => _shiftDate(1),
          onTap: _pickDate,
        );
      case 2:
        final now = DateTime.now();
        final isThisMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
        return _dateNavRow(
          label: _selectedMonthLabel,
          onPrev: () => _shiftMonth(-1),
          onNext: isThisMonth ? null : () => _shiftMonth(1),
        );
      case 1:
        final isCurrentWeek = _isSameDay(_selectedWeekEnd, DateTime.now());
        return _dateNavRow(
          label: _selectedWeekLabel,
          onPrev: () => _shiftWeek(-1),
          onNext: isCurrentWeek ? null : () => _shiftWeek(1),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _shiftWeek(int deltaWeeks) {
    setState(() => _selectedWeekEnd = _selectedWeekEnd.add(Duration(days: 7 * deltaWeeks)));
    _loadStatic();
  }

  Widget _dateNavRow({
    required String label,
    required VoidCallback onPrev,
    VoidCallback? onNext,
    VoidCallback? onTap,
  }) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      IconButton(
        onPressed: onPrev, icon: const Icon(Icons.chevron_left_rounded, size: 20),
        color: AppColors.textMuted, padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
      GestureDetector(
        onTap: onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_month_rounded, size: 13, color: AppColors.primaryGreen),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textDark)),
        ]),
      ),
      IconButton(
        onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded, size: 20),
        color: onNext == null ? AppColors.divider : AppColors.textMuted, padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    ]),
  );

  void _shiftDate(int deltaDays) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: deltaDays)));
    _loadDateScoped();
  }

  void _shiftMonth(int deltaMonths) {
    setState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + deltaMonths, 1));
    _loadStatic();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadDateScoped();
    }
  }

  // ── Section TabBar + View Mode Toggle ─────────────────────────────────────
  Widget _buildSectionTabBar() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)]),
    child: Row(children: [
      Expanded(
        child: TabBar(
          controller: _sectionTab,
          indicator: BoxDecoration(
              color: AppColors.primaryGreen, borderRadius: BorderRadius.circular(10)),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.black87, unselectedLabelColor: AppColors.textMuted,
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          dividerColor: Colors.transparent,
          tabs: [
            _miniTab(Icons.bolt_rounded, 'พลังงาน'),
            _miniTab(Icons.restaurant_rounded, 'โภชนาการ'),
            _miniTab(Icons.fitness_center_rounded, 'ออกกำลังกาย'),
            _miniTab(Icons.monitor_weight_outlined, 'BMI'),
          ],
        ),
      ),
      const SizedBox(width: 4),
      _viewModeToggle(),
    ]),
  );

  Widget _miniTab(IconData icon, String label) => Tab(
    height: 44,
    child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
          maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );

  Widget _viewModeToggle() => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      _viewModeBtn(Icons.insert_chart_outlined_rounded, _ViewMode.graph),
      _viewModeBtn(Icons.table_rows_rounded, _ViewMode.table),
    ]),
  );

  Widget _viewModeBtn(IconData icon, _ViewMode mode) {
    final sel = _viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = mode),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
            color: sel ? AppColors.primaryGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 16, color: sel ? Colors.black87 : AppColors.textMuted),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1 — ENERGY BALANCE
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildEnergyTab() => RefreshIndicator(
    color: AppColors.primaryGreen,
    onRefresh: () async {
      ApiClient.clearCache();
      await _loadData();
    },
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
      children: [
        if (_insightMsg != null && _selectedPeriod == 0) ...[
          _buildInsightCard(), const SizedBox(height: 12),
        ],
        ...switch (_selectedPeriod) {
          0 => _viewMode == _ViewMode.graph
              ? [
                  _buildCalorieRing(), const SizedBox(height: 12),
                  _buildEnergyFlowCard(),
                ]
              : [_buildEnergyDailyTable()],
          1 => _viewMode == _ViewMode.graph
              ? [
                  _buildWeeklyGoalCompliance(), const SizedBox(height: 12),
                  _buildWeeklyBarChart(),       const SizedBox(height: 12),
                  _buildBalanceTrendCard(_weekly?.weekData.map((e) =>
                      (e.date, e.calories, e.caloriesOut)).toList() ?? []),
                ]
              : [_buildEnergyTable(_weekly?.weekData.map((e) =>
                    (e.date, e.calories, e.caloriesOut)).toList() ?? [])],
          _ => _viewMode == _ViewMode.graph
              ? [
                  _buildMonthlyCalorieChart(), const SizedBox(height: 12),
                  _buildMonthComparisonCard(), const SizedBox(height: 12),
                  _buildBalanceTrendCard(_monthly?.monthData.map((e) =>
                      (e.date, e.calories, e.caloriesOut)).toList() ?? []),
                ]
              : [_buildEnergyTable(_monthly?.monthData.map((e) =>
                    (e.date, e.calories, e.caloriesOut)).toList() ?? [])],
        },
      ],
    ),
  );

  Widget _buildInsightCard() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        _insightColor.withValues(alpha: 0.12), _insightColor.withValues(alpha: 0.04)]),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _insightColor.withValues(alpha: 0.25)),
    ),
    child: Row(children: [
      Icon(_insightIcon, color: _insightColor, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(_insightMsg!,
          style: TextStyle(fontSize: 12, color: _insightColor, fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _buildCalorieRing() {
    if (!_hasTarget) {
      return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('แคลอรี่วันนี้', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        const SizedBox(height: 16),
        _emptyState('ยังไม่ได้ตั้งเป้าหมายพลังงาน — กรุณากรอกข้อมูลร่างกายและเป้าหมายสุขภาพก่อน',
            icon: Icons.flag_outlined),
      ]));
    }
    final progress = (_targetCalories > 0 ? _caloriesIn / _targetCalories : 0.0).clamp(0.0, 1.0);
    final isOver   = _caloriesIn > _targetCalories;
    final excess   = isOver ? _caloriesIn - _targetCalories : 0.0;
    final remain   = isOver ? 0.0 : _targetCalories - _caloriesIn;
    final (statusLabel, statusColor) = _energyStatus(_caloriesIn, _targetCalories);

    return _card(child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('แคลอรี่วันนี้', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        _badge(statusLabel, statusColor),
      ]),
      const SizedBox(height: 18),
      Row(children: [
        SizedBox(width: 140, height: 140, child: CustomPaint(
          painter: _DonutPainter(progress: progress,
              trackColor: AppColors.primaryGreen.withValues(alpha: 0.1),
              fillColor: AppColors.primaryGreen, overColor: Colors.redAccent, isOver: isOver),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${_caloriesIn.round()}', style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.textDark)),
            const Text('kcal', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            const SizedBox(height: 2),
            Text('${(progress * 100).round()}%', style: TextStyle(fontSize: 11,
                color: isOver ? Colors.redAccent : AppColors.primaryGreen,
                fontWeight: FontWeight.w700)),
          ])),
        )),
        const SizedBox(width: 18),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _calRow(Icons.flag_rounded,              'เป้าหมาย',   _targetCalories,  AppColors.textMuted),
          _div(),
          _calRow(Icons.restaurant_rounded,        'กินเข้า',    _caloriesIn,  const Color(0xFF5B8CFF)),
          _div(),
          _calRow(Icons.local_fire_department_rounded, 'เผาผลาญ', _caloriesOut, const Color(0xFFF85B07)),
          _div(),
          _calRow(isOver ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
              isOver ? 'เกิน' : 'เหลือ', isOver ? excess : remain,
              isOver ? Colors.redAccent : AppColors.primaryGreen),
        ])),
      ]),
    ]));
  }

  Widget _calRow(IconData icon, String label, double val, Color c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Icon(icon, color: c, size: 13),
      const SizedBox(width: 6),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
        Text('${val.round()} kcal',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: c)),
      ]),
    ]),
  );

  Widget _div() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 2),
    child: Divider(height: 1, color: AppColors.divider),
  );

  Widget _buildEnergyFlowCard() => _card(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('พลังงานเข้า–ออก', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _flowItem('🍽', 'กินเข้า',   _caloriesIn,   const Color(0xFF5B8CFF))),
        _farrow(),
        Expanded(child: _flowItem('🛏', 'พลังงานพื้นฐาน', _baseline, AppColors.textMuted)),
        _farrow(),
        Expanded(child: _flowItem('🏋️', 'ออกกำลัง', _exerciseBurn, const Color(0xFFF85B07))),
        _farrow(),
        Expanded(child: _flowItem(_balance >= 0 ? '📈' : '📉', 'Balance',
            _balance.abs(), _balanceColor, prefix: _balance >= 0 ? '+' : '-')),
      ]),
      const SizedBox(height: 6),
      const Text('พลังงานพื้นฐาน = BMR × 1.2 (Baseline Expenditure)',
          style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
    ],
  ));

  Widget _flowItem(String e, String l, double v, Color c, {String prefix = ''}) =>
    Column(children: [
      Text(e, style: const TextStyle(fontSize: 20)),
      const SizedBox(height: 5),
      Text('$prefix${v.round()}',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c),
          textAlign: TextAlign.center),
      Text(l, style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
          textAlign: TextAlign.center),
    ]);

  Widget _farrow() => const Padding(
    padding: EdgeInsets.only(bottom: 16),
    child: Icon(Icons.chevron_right_rounded, color: AppColors.divider, size: 18),
  );

  // โหมดตาราง มุมมองรายวัน — สรุปพลังงานเข้า/ออกของวันที่เลือกเป็นตารางเดียว
  Widget _buildEnergyDailyTable() {
    if (!_hasTarget) {
      return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ตารางพลังงานวันนี้', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        const SizedBox(height: 16),
        _emptyState('ยังไม่ได้ตั้งเป้าหมายพลังงาน — กรุณากรอกข้อมูลร่างกายและเป้าหมายสุขภาพก่อน',
            icon: Icons.flag_outlined),
      ]));
    }
    final (statusLabel, _) = _energyStatus(_caloriesIn, _targetCalories);
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ตารางพลังงานวันนี้', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 12),
      _simpleTable(
        ['รายการ', 'kcal'],
        [
          ['กินเข้า', '${_caloriesIn.round()}'],
          ['พลังงานพื้นฐาน (BMR × 1.2)', '${_baseline.round()}'],
          ['เผาผลาญจากออกกำลังกาย', '${_exerciseBurn.round()}'],
          ['เป้าหมาย', '${_targetCalories.round()}'],
          ['สมดุล (${_balance >= 0 ? '+' : ''}${_balance.round()}) — $statusLabel', ''],
        ],
        flex: [4, 2],
      ),
    ]));
  }

  Widget _buildWeeklyGoalCompliance() {
    if (!_hasTarget) {
      return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('เป้าหมายรายสัปดาห์', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        const SizedBox(height: 16),
        _emptyState('ยังไม่ได้ตั้งเป้าหมายพลังงาน — กรุณากรอกข้อมูลร่างกายและเป้าหมายสุขภาพก่อน',
            icon: Icons.flag_outlined),
      ]));
    }
    final days  = _weeklyGoalDays;
    const total = 7; // weekData ถูก densify มาแล้วเสมอ 7 วัน (คำสั่งที่ 17)
    final pct   = days / total;
    final color = days >= 5 ? AppColors.primaryGreen : (days >= 3 ? Colors.orange : Colors.redAccent);

    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('เป้าหมายรายสัปดาห์', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        _badge('$days/$total วัน ✓', color),
      ]),
      const SizedBox(height: 12),
      ClipRRect(borderRadius: BorderRadius.circular(10),
        child: LinearProgressIndicator(value: pct, minHeight: 12,
            backgroundColor: color.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation(color))),
      const SizedBox(height: 8),
      const Text('วันที่แคลอรี่อยู่ในช่วง ±10% ของเป้าหมาย',
          style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
    ]));
  }

  /// เติมช่องว่างของเป้าหมายในวันที่ไม่มีบันทึกอาหาร/ออกกำลังกาย (target_tdee จาก backend = 0
  /// เพราะวันนั้นไม่มีแถวใน date_list เลย) ด้วยค่าจากวันก่อนหน้าที่รู้ค่าจริงล่าสุด (forward-fill)
  /// แทนการปล่อยเป็น 0 ซึ่งจะทำให้เส้น target ตกลงมาที่ 0 ผิดๆ ในวันที่ไม่มีข้อมูล
  List<double> _fillTargetGaps(List<double> raw) {
    final out = List<double>.filled(raw.length, 0);
    double last = 0;
    for (int i = 0; i < raw.length; i++) {
      if (raw[i] > 0) last = raw[i];
      out[i] = last;
    }
    // วันแรกๆ ที่ยังไม่เจอค่าจริงเลย (last ยังเป็น 0) ให้ backfill จากค่าแรกที่เจอแทน
    final firstKnown = out.firstWhere((v) => v > 0, orElse: () => 0);
    for (int i = 0; i < out.length; i++) {
      if (out[i] == 0) out[i] = firstKnown;
    }
    return out;
  }

  Widget _buildWeeklyBarChart() {
    final pts = _weekly?.weekData ?? [];
    const dn  = ['อา','จ','อ','พ','พฤ','ศ','ส'];
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('แคลอรี่ 7 วัน', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        Row(children: [
          _dot(AppColors.primaryGreen, 'กิน'), const SizedBox(width: 10),
          _dot(const Color(0xFFF85B07), 'เผา'),
        ]),
      ]),
      const SizedBox(height: 16),
      SizedBox(height: 160,
        child: pts.isEmpty ? _emptyChart() : CustomPaint(
          painter: _BarChartPainter(
            dataIn: pts.map((e) => e.calories).toList(),
            dataOut: pts.map((e) => e.caloriesOut).toList(),
            targetLine: _fillTargetGaps(pts.map((e) => e.targetTdee).toList()),
            colorIn: AppColors.primaryGreen, colorOut: const Color(0xFFF85B07),
          ), size: Size.infinite)),
      if (pts.isNotEmpty) ...[
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: pts.map((e) {
            final dt = DateTime.tryParse(e.date);
            return Text(dt != null ? dn[dt.weekday % 7] : '',
                style: const TextStyle(fontSize: 10, color: AppColors.textMuted));
          }).toList()),
        const SizedBox(height: 4),
        const Text('แท่งเตี้ยที่ 0 = ยังไม่ได้บันทึกข้อมูลวันนั้น',
            style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
      ],
    ]));
  }

  Widget _buildMonthlyCalorieChart() {
    final pts = _monthly?.monthData ?? [];
    String lbl(String raw) {
      final d = raw.split('T').first;
      return d.length >= 5 ? d.substring(5) : d;
    }
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('แคลอรี่รายเดือน', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        Row(children: [
          _dot(AppColors.primaryGreen, 'กิน'), const SizedBox(width: 10),
          _dot(const Color(0xFFF85B07), 'เผา'),
        ]),
      ]),
      const SizedBox(height: 18),
      SizedBox(height: 160,
        child: pts.length < 2 ? _emptyChart() : CustomPaint(
          painter: _AreaChartPainter(
            pointsIn: pts.map((e) => e.calories).toList(),
            pointsOut: pts.map((e) => e.caloriesOut).toList(),
            targetLine: _fillTargetGaps(pts.map((e) => e.targetTdee).toList()),
            colorIn: AppColors.primaryGreen, colorOut: const Color(0xFFF85B07),
          ), size: Size.infinite)),
      if (pts.length >= 2) ...[
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(lbl(pts.first.date), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          if (pts.length > 4)
            Text(lbl(pts[pts.length ~/ 2].date),
                style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          Text(lbl(pts.last.date), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ]),
        const SizedBox(height: 4),
        const Text('จุดที่แตะ 0 = ยังไม่ได้บันทึกข้อมูลวันนั้น',
            style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
      ],
    ]));
  }

  Widget _buildMonthComparisonCard() {
    final cmp = _comparison;
    if (cmp == null) return const SizedBox.shrink();
    final up = cmp.calChangePct >= 0;
    final goodUp = _goalType == 2 ? up : !up;
    // เดือนไหนบันทึกไม่ครบ 7 วัน = ข้อมูลน้อยเกินจะเทียบ % กันอย่างมีความหมาย (คำสั่งที่ 19.2)
    final enoughData = cmp.thisMonth.recordedDays >= 7 && cmp.lastMonth.recordedDays >= 7;

    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('เทียบกับเดือนที่แล้ว', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _cmpBox('เดือนนี้',
            cmp.thisMonth.recordedDays > 0 ? '${cmp.thisMonth.avgCal.round()} kcal' : '-',
            'เฉลี่ย/วันที่บันทึก (บันทึก ${cmp.thisMonth.recordedDays} วัน)', AppColors.primaryGreen)),
        const SizedBox(width: 10),
        Expanded(child: _cmpBox('เดือนที่แล้ว',
            cmp.lastMonth.recordedDays > 0 ? '${cmp.lastMonth.avgCal.round()} kcal' : '-',
            'เฉลี่ย/วันที่บันทึก (บันทึก ${cmp.lastMonth.recordedDays} วัน)', AppColors.textMuted)),
      ]),
      const SizedBox(height: 12),
      if (enoughData)
        Row(children: [
          Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              color: goodUp ? AppColors.primaryGreen : Colors.orange, size: 18),
          const SizedBox(width: 6),
          Text('${up ? '+' : ''}${cmp.calChangePct.toStringAsFixed(1)}% เทียบเดือนก่อน',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: goodUp ? AppColors.primaryGreen : Colors.orange)),
        ])
      else
        Row(children: [
          Icon(Icons.info_outline_rounded, size: 16,
              color: AppColors.textMuted.withValues(alpha: 0.8)),
          const SizedBox(width: 6),
          const Text('ข้อมูลยังไม่พอสำหรับเปรียบเทียบ',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ]),
    ]));
  }

  Widget _buildBalanceTrendCard(List<(String, double, double)> pts) {
    if (pts.isEmpty) return const SizedBox.shrink();
    final balances = pts.map((e) => e.$2 - e.$3).toList();
    final avg = balances.fold(0.0, (s, v) => s + v) / balances.length;
    // วันที่ทั้งกิน/เผาเป็น 0 คือช่องที่ densify เติมให้ (ไม่ได้บันทึกจริง) ไม่นับสถานะ
    // เกิน/ตาม/ต่ำกว่าเป้า มิฉะนั้นจะถูกนับเป็น "ต่ำกว่าเป้า" ผิดๆ ทุกวันที่ไม่มีข้อมูล (คำสั่งที่ 17)
    // นับแยกเป็นกล่อง "ไม่มีข้อมูล" แทน เพื่อให้ผลรวม 4 กล่อง = จำนวนวันทั้งหมดพอดี ตรวจสอบ
    // ย้อนกลับได้ (คำสั่งที่ 19 — ความเห็นเพิ่มเติม)
    int over = 0, on = 0, under = 0, noData = 0;
    for (final p in pts) {
      if (p.$2 <= 0 && p.$3 <= 0) {
        noData++;
        continue;
      }
      final (label, _) = _energyStatus(p.$2, _targetCalories);
      if (label == 'เกินเป้า') {
        over++;
      } else if (label == 'ตามเป้า') {
        on++;
      } else if (label == 'ต่ำกว่าเป้า') {
        under++;
      }
    }
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('แนวโน้มสมดุลพลังงาน', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        Text('${avg >= 0 ? '+' : ''}${avg.round()} kcal เฉลี่ย', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700,
            color: avg <= 0 ? AppColors.primaryGreen : Colors.orange)),
      ]),
      const SizedBox(height: 14),
      SizedBox(height: 60, child: CustomPaint(
          painter: _LineChartPainter(values: balances, color: AppColors.primaryGreen),
          size: Size.infinite)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _avgBox('เกินเป้า', '$over วัน', '', Colors.redAccent)),
        const SizedBox(width: 6),
        Expanded(child: _avgBox('ตามเป้า', '$on วัน', '', AppColors.primaryGreen)),
        const SizedBox(width: 6),
        Expanded(child: _avgBox('ต่ำกว่าเป้า', '$under วัน', '', Colors.orange)),
        const SizedBox(width: 6),
        Expanded(child: _avgBox('ไม่มีข้อมูล', '$noData วัน', '', AppColors.textMuted)),
      ]),
    ]));
  }

  Widget _buildEnergyTable(List<(String, double, double)> pts) => _card(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ตารางสมดุลพลังงาน', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 12),
      _simpleTable(
        ['วันที่', 'กิน', 'เผา', 'เป้าหมาย', 'สมดุล', 'สถานะ'],
        pts.map((p) {
          final bal = p.$2 - p.$3;
          final (label, _) = _energyStatus(p.$2, _targetCalories);
          return [
            _shortDate(p.$1),
            '${p.$2.round()}',
            '${p.$3.round()}',
            '${_targetCalories.round()}',
            '${bal >= 0 ? '+' : ''}${bal.round()}',
            label,
          ];
        }).toList(),
        flex: [2, 2, 2, 2, 2, 2],
      ),
    ]),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 2 — NUTRITION
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildNutritionTab() => RefreshIndicator(
    color: AppColors.primaryGreen,
    onRefresh: () async {
      ApiClient.clearCache();
      await _loadData();
    },
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
      children: [
        ...switch (_selectedPeriod) {
          0 => _viewMode == _ViewMode.graph
              ? [
                  _buildMealBreakdownCard(),   const SizedBox(height: 12),
                  _buildFoodItemsCard(),       const SizedBox(height: 12),
                  _buildMacrosCard(),
                ]
              : [_buildFoodItemsCard()],
          1 => _viewMode == _ViewMode.graph
              ? [
                  _buildCaloriesInTrendChart(
                      (_weekly?.weekData ?? []).map((e) => (e.date, e.calories)).toList(),
                      'แนวโน้มแคลอรี่ที่ได้รับ 7 วัน'),
                  const SizedBox(height: 12),
                  _buildWeeklyMacroAverages(), const SizedBox(height: 12),
                  _buildBestWorstDayCard(),
                ]
              : [_buildNutritionTable((_weekly?.weekData ?? [])
                    .map((e) => (e.date, e.calories, e.protein, e.carbs, e.fat)).toList())],
          _ => _viewMode == _ViewMode.graph
              ? [_buildCaloriesInTrendChart(
                    (_monthly?.monthData ?? []).map((e) => (e.date, e.calories)).toList(),
                    'แนวโน้มแคลอรี่ที่ได้รับรายเดือน')]
              : [_buildNutritionTable((_monthly?.monthData ?? [])
                    .map((e) => (e.date, e.calories, e.protein, e.carbs, e.fat)).toList())],
        },
      ],
    ),
  );

  Widget _buildMealBreakdownCard() {
    if (_meals.isEmpty) {
      return _card(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('มื้ออาหาร', style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          const SizedBox(height: 16),
          _emptyState('ยังไม่ได้บันทึกอาหาร', icon: Icons.restaurant_menu_rounded),
        ],
      ));
    }

    final mealMap = {for (var m in _meals) m.mealType: m};
    final totalCal = _meals.fold(0.0, (s, m) => s + m.calories);

    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('มื้ออาหาร', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        Text('${totalCal.round()} kcal รวม',
            style: const TextStyle(fontSize: 11, color: AppColors.primaryGreen,
                fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 14),
      ...[1, 2, 3, 4].where(mealMap.containsKey).map((t) {
        final m   = mealMap[t]!;
        final pct = _targetCalories > 0 ? (m.calories / _targetCalories).clamp(0.0, 1.0) : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Text(m.mealEmoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(m.mealName, style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                Text('${m.calories.round()} kcal',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                        color: AppColors.textDark)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: pct, minHeight: 6,
                    backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation(AppColors.primaryGreen))),
              const SizedBox(height: 3),
              Text('P${m.protein.round()}g  C${m.carbs.round()}g  F${m.fat.round()}g  •  ${m.count} รายการ',
                  style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
            ])),
          ]),
        );
      }),
    ]));
  }

  Widget _buildFoodItemsCard() {
    if (_foods.isEmpty) {
      return _card(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('รายการอาหาร', style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          const SizedBox(height: 16),
          _emptyState('ไม่มีรายการอาหารในวันนี้', icon: Icons.receipt_long_rounded),
        ],
      ));
    }
    const mealNames = {1: 'มื้อเช้า 🌅', 2: 'มื้อกลางวัน ☀️', 3: 'มื้อเย็น 🌙', 4: 'ของว่าง 🍎'};
    final byMeal = <int, List<DailyNutrition>>{};
    for (final f in _foods) {
      byMeal.putIfAbsent(f.mealType, () => []).add(f);
    }
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('รายการอาหาร', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 12),
      ...[1, 2, 3, 4].where(byMeal.containsKey).map((t) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(mealNames[t] ?? '', style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          _simpleTable(
            ['อาหาร', 'ปริมาณ', 'kcal'],
            byMeal[t]!.map((f) => [
              f.foodName,
              // dntt_quantity คือ "จำนวนหน่วยเสิร์ฟ" (1 หน่วย = 100 กรัม สำหรับอาหารหน่วยกรัม) ตาม
              // ntt_serving_weight ฝั่ง backend ไม่ใช่กรัมจริง ต้องคูณ 100 ก่อนโชว์ให้ผู้ใช้เข้าใจถูก
              f.unit == 'กรัม'
                  ? '${(f.quantity * 100).round()} กรัม'
                  : '${f.quantity.toStringAsFixed(f.quantity.truncateToDouble() == f.quantity ? 0 : 1)} ${f.unit}',
              '${f.totalCalories.round()}',
            ]).toList(),
            flex: [3, 2, 2],
          ),
        ]),
      )),
    ]));
  }

  Widget _buildMacrosCard() {
    if (!_hasTarget) {
      return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('สัดส่วนสารอาหารหลัก', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        const SizedBox(height: 16),
        _emptyState('ยังไม่ได้ตั้งเป้าหมายพลังงาน — กรุณากรอกข้อมูลร่างกายและเป้าหมายสุขภาพก่อน',
            icon: Icons.flag_outlined),
      ]));
    }
    final p = _daily?.totalProtein ?? 0;
    final c = _daily?.totalCarbs   ?? 0;
    final f = _daily?.totalFat     ?? 0;
    // % ของพลังงานรวม (ตามบทที่ 2 หัวข้อ 2.1.4.8) ต้องถ่วงน้ำหนักด้วย kcal/g (4/4/9)
    // ไม่ใช่สัดส่วนกรัมดิบ — เดิม pill ข้างล่างคิดจากกรัมดิบทำให้ตัวเลขไม่ตรงกับโดนัทชาร์ต
    final pKcal = p * 4;
    final cKcal = c * 4;
    final fKcal = f * 9;
    final total = pKcal + cKcal + fKcal;

    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('สัดส่วนสารอาหารหลัก', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        SizedBox(width: 48, height: 48, child: CustomPaint(
          painter: _MiniDonutPainter(
            values: [pKcal, cKcal, fKcal],
            colors: [const Color(0xFF5B8CFF), const Color(0xFFFFAB2E), const Color(0xFFFF6B6B)],
          ),
        )),
      ]),
      const SizedBox(height: 12),
      _macroBar('โปรตีน',       p, _targetProtein, const Color(0xFF5B8CFF)),
      const SizedBox(height: 12),
      _macroBar('คาร์โบไฮเดรต', c, _targetCarbs,   const Color(0xFFFFAB2E)),
      const SizedBox(height: 12),
      _macroBar('ไขมัน',        f, _targetFat,     const Color(0xFFFF6B6B)),
      if (total > 0) ...[
        const SizedBox(height: 12),
        Row(children: [
          _mpill('P', '${(pKcal / total * 100).round()}%', const Color(0xFF5B8CFF)),
          const SizedBox(width: 6),
          _mpill('C', '${(cKcal / total * 100).round()}%', const Color(0xFFFFAB2E)),
          const SizedBox(width: 6),
          _mpill('F', '${(fKcal / total * 100).round()}%', const Color(0xFFFF6B6B)),
        ]),
      ],
    ]));
  }

  Widget _macroBar(String label, double actual, double target, Color color) {
    final ratio = target > 0 ? (actual / target).clamp(0.0, 1.0) : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Container(width: 8, height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
        ]),
        Text('${actual.round()} / ${target.round()} g',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ]),
      const SizedBox(height: 6),
      Stack(children: [
        Container(height: 8, decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8))),
        FractionallySizedBox(widthFactor: ratio, child: Container(height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 4)]))),
      ]),
    ]);
  }

  Widget _mpill(String l, String v, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20)),
    child: Text('$l $v',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c)),
  );

  Widget _buildCaloriesInTrendChart(List<(String, double)> pts, String title) {
    if (pts.length < 2) {
      return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        const SizedBox(height: 16),
        _emptyState('ยังไม่มีข้อมูลพอ'),
      ]));
    }
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 16),
      SizedBox(height: 140, child: CustomPaint(
          painter: _LineChartPainter(
              values: pts.map((e) => e.$2).toList(), color: const Color(0xFF5B8CFF)),
          size: Size.infinite)),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(_shortDate(pts.first.$1), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        Text(_shortDate(pts.last.$1), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
      ]),
    ]));
  }

  Widget _buildWeeklyMacroAverages() {
    final ai = _weekly?.weeklyAvgCalories    ?? 0;
    final ao = _weekly?.weeklyAvgCaloriesOut ?? 0;
    final d  = ai - ao;
    // นับวันที่มีข้อมูลจริงจาก weekData ที่ densify แล้ว (แถวเติมมีทั้ง calories/caloriesOut
    // เป็น 0 เสมอ ส่วนแถวจริงมี caloriesOut > 0 เสมอเพราะ backend บวก baseline ให้ทุกแถวจริง)
    // ตัวเลข N นี้ตรงกับตัวหารที่ใช้คำนวณ weeklyAvgCalories ไว้แต่ต้นตอนพาร์สอยู่แล้ว
    final recordedDays = _weekly?.weekData
            .where((e) => e.calories > 0 || e.caloriesOut > 0)
            .length ??
        0;
    final hasData = recordedDays > 0;
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ค่าเฉลี่ยสัปดาห์', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _avgBox('กินเฉลี่ย', hasData ? '${ai.round()}' : '-',
            'kcal/วันที่บันทึก', const Color(0xFF5B8CFF))),
        const SizedBox(width: 8),
        Expanded(child: _avgBox('เผาเฉลี่ย', hasData ? '${ao.round()}' : '-',
            'kcal/วันที่บันทึก', const Color(0xFFF85B07))),
        const SizedBox(width: 8),
        Expanded(child: _avgBox('Balance', hasData ? '${d >= 0 ? '+' : ''}${d.round()}' : '-',
            'kcal/วันที่บันทึก', d <= 0 ? AppColors.primaryGreen : Colors.orange)),
      ]),
      const SizedBox(height: 8),
      Text('คำนวณจาก $recordedDays วันที่มีการบันทึก จากทั้งหมด 7 วัน',
          style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
    ]));
  }

  Widget _buildBestWorstDayCard() {
    final pts = _weekly?.weekData.where((e) => e.calories > 0).toList() ?? [];
    if (pts.isEmpty) return const SizedBox.shrink();
    const dn = ['อา','จ','อ','พ','พฤ','ศ','ส'];
    String dayName(String date) {
      final dt = DateTime.tryParse(date);
      return dt != null ? dn[dt.weekday % 7] : '';
    }
    final best  = pts.reduce((a, b) =>
        (a.calories - _targetCalories).abs() < (b.calories - _targetCalories).abs() ? a : b);
    final worst = pts.reduce((a, b) =>
        (a.calories - _targetCalories).abs() > (b.calories - _targetCalories).abs() ? a : b);

    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ดีที่สุด vs แย่ที่สุดสัปดาห์นี้', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _cmpBox('🏆 ${dayName(best.date)}',
            '${best.calories.round()} kcal', 'ใกล้เป้าที่สุด', AppColors.primaryGreen)),
        const SizedBox(width: 10),
        Expanded(child: _cmpBox('😓 ${dayName(worst.date)}',
            '${worst.calories.round()} kcal', 'ห่างเป้ามากสุด', Colors.orange)),
      ]),
    ]));
  }

  Widget _buildNutritionTable(List<(String, double, double, double, double)> pts) => _card(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ตารางแคลอรี่ที่ได้รับ', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 12),
      _simpleTable(
        ['วันที่', 'kcal', 'P (g)', 'C (g)', 'F (g)'],
        pts.map((p) {
          // calories <= 0 ตีความว่าวันนั้นไม่ได้บันทึกอาหาร ไม่ใช่บันทึกแล้วได้ 0 กรัมจริง
          final logged = p.$2 > 0;
          return [
            _shortDate(p.$1),
            '${p.$2.round()}',
            logged ? '${p.$3.round()}' : '-',
            logged ? '${p.$4.round()}' : '-',
            logged ? '${p.$5.round()}' : '-',
          ];
        }).toList(),
        flex: [3, 2, 2, 2, 2],
      ),
    ]),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3 — EXERCISE
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildExerciseTab() => RefreshIndicator(
    color: AppColors.primaryGreen,
    onRefresh: () async {
      ApiClient.clearCache();
      await _loadData();
    },
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
      children: [
        _sectionHeader('เวทเทรนนิ่ง', Icons.fitness_center_rounded, AppColors.weightIcon),
        const SizedBox(height: 10),
        ...switch (_selectedPeriod) {
          0 => _viewMode == _ViewMode.graph
              ? [
                  _buildDailyBurnCard(),          const SizedBox(height: 12),
                  _buildAdherenceCard(),          const SizedBox(height: 12),
                  _buildWeightExerciseDetail(),
                ]
              : [_buildWeightExerciseDetail()],
          1 => _viewMode == _ViewMode.graph
              ? [
                  _buildWorkoutSplitChart(),   const SizedBox(height: 12),
                  _buildAdherenceCard(),       const SizedBox(height: 12),
                  _buildWeeklyExerciseAverages(),
                ]
              : [_buildExerciseTable(_weekly?.weekData.map((e) =>
                    (e.date, e.weightOut, e.cardioOut)).toList() ?? [])],
          _ => _viewMode == _ViewMode.graph
              ? [
                  _buildMonthlyWorkoutAreaChart(),    const SizedBox(height: 12),
                  _buildMonthWorkoutComparisonCard(), const SizedBox(height: 12),
                  _buildMonthlyExerciseSummary(),
                ]
              : [_buildExerciseTable(_monthly?.monthData.map((e) =>
                    (e.date, e.weightOut, e.cardioOut)).toList() ?? [])],
        },
        const SizedBox(height: 20),
        _sectionHeader('คาร์ดิโอ', Icons.directions_run_rounded, AppColors.cardioIcon),
        const SizedBox(height: 10),
        if (_selectedPeriod == 0) _buildCardioDetail(),
        if (_selectedPeriod != 0)
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('สัดส่วนเวท vs คาร์ดิโอ', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
            const SizedBox(height: 8),
            const Text('ดูกราฟรวมเวท/คาร์ดิโอด้านบน — รายละเอียดต่อรายการดูได้ที่มุมมองรายวัน',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ])),
        if (_selectedPeriod != 2) ...[
          const SizedBox(height: 12),
          _buildMuscleGroupBadges(),
        ],
        if (_selectedPeriod == 0 || _selectedPeriod == 1) ...[
          const SizedBox(height: 12),
          _buildConsistencyRow(),
        ],
      ],
    ),
  );

  Widget _sectionHeader(String title, IconData icon, Color color) => Row(children: [
    Icon(icon, size: 16, color: color),
    const SizedBox(width: 8),
    Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color,
        letterSpacing: 0.3)),
    const SizedBox(width: 10),
    Expanded(child: Divider(color: color.withValues(alpha: 0.2))),
  ]);

  Widget _buildDailyBurnCard() {
    final burn  = _exerciseBurn;
    final base  = _baseline;
    final total = burn + base;
    final pct   = total > 0 ? burn / total : 0.0;

    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('พลังงานที่ใช้', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        _badge(burn > 0 ? 'ออกกำลังกายแล้ว 💪' : 'ยังไม่ได้ออกกำลัง',
            burn > 0 ? AppColors.primaryGreen : AppColors.textMuted),
      ]),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: _burnBox(Icons.local_fire_department_rounded,
            'รวมทั้งหมด', '${total.round()}', 'kcal', const Color(0xFFF85B07))),
        const SizedBox(width: 8),
        Expanded(child: _burnBox(Icons.fitness_center_rounded,
            'จากออกกำลังกาย', '${burn.round()}', 'kcal', AppColors.primaryGreen)),
        const SizedBox(width: 8),
        Expanded(child: _burnBox(Icons.bedtime_outlined,
            'พลังงานพื้นฐาน', '${base.round()}', 'kcal', AppColors.textMuted)),
      ]),
      if (burn > 0) ...[
        const SizedBox(height: 16),
        const Text('สัดส่วนจากออกกำลังกาย',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: pct.clamp(0.0, 1.0), minHeight: 8,
              backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation(AppColors.primaryGreen))),
        const SizedBox(height: 4),
        Text('${(pct * 100).round()}% ของการเผาผลาญทั้งหมดมาจากการออกกำลังกาย',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
      ],
    ]));
  }

  Widget _burnBox(IconData icon, String label, String value, String unit, Color color) =>
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(unit, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
      ]),
    );

  Widget _buildAdherenceCard() {
    final rate = _adherenceRate;
    final target = math.max(1, WorkoutService.to.activePlanDays);
    final color = rate >= 0.8 ? AppColors.primaryGreen : (rate >= 0.5 ? Colors.orange : Colors.redAccent);
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Adherence Rate', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        _badge('${(rate * 100).round()}%', color),
      ]),
      const SizedBox(height: 12),
      ClipRRect(borderRadius: BorderRadius.circular(10),
        child: LinearProgressIndicator(value: rate, minHeight: 12,
            backgroundColor: color.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation(color))),
      const SizedBox(height: 8),
      Text('ฝึกจริง $_workoutDaysThisWeek วัน จากเป้าหมาย $target วัน/สัปดาห์',
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
    ]));
  }

  Widget _buildWeightExerciseDetail() {
    if (_workoutResults.isEmpty) {
      return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('รายละเอียดท่าฝึก', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        const SizedBox(height: 16),
        _emptyState('ยังไม่ได้บันทึกเวทเทรนนิ่งวันนี้', icon: Icons.fitness_center_rounded),
      ]));
    }
    final byExercise = <int, List<WorkoutResult>>{};
    final nameById = <int, String>{};
    for (final w in _workoutResults) {
      byExercise.putIfAbsent(w.exerciseId, () => []).add(w);
      nameById[w.exerciseId] = w.exerciseName ?? 'ท่าฝึก';
    }
    return Column(children: byExercise.entries.map((entry) {
      final sets = entry.value..sort((a, b) => a.setNo.compareTo(b.setNo));
      final volume = sets.fold(0.0, (s, w) => s + w.weight * w.reps);
      // สูตร Epley คลาดเคลื่อนมากเมื่อ reps > 12 — คิดเฉพาะเซตที่อยู่ในช่วงที่แม่นยำ
      // 1RM = weight × (1 + reps/30) ตาม CLAUDE.md ข้อ 5 — ไม่จำกัด reps
      // (เดิมกรองเฉพาะ reps<=12 จุดนี้จุดเดียว ทำให้ไม่ตรงกับ backend และอีก 3 จุดใน
      // frontend ที่ไม่จำกัด reps — เอา cap ออกให้สูตรตรงกันทั้งระบบ แม้สูตรจะคลาดเคลื่อน
      // มากขึ้นตาม comment เดิมด้านบนก็ตาม เพื่อให้ตรงกับ backend เป็น single source of truth)
      // เป็นค่าคำนวณแสดงผลเท่านั้น ไม่บันทึกลงฐานข้อมูล (คำสั่งที่ 16)
      final validRepSets = sets.where((w) => w.reps > 0);
      final est1rm = validRepSets.isEmpty
          ? null
          : validRepSets.fold(0.0, (m, w) => math.max(m, w.weight * (1 + w.reps / 30)));
      final calories = sets.fold(0.0, (s, w) => s + w.calories);
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Text(nameById[entry.key] ?? 'ท่าฝึก', style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textDark))),
            _badge('${calories.round()} kcal', AppColors.weightIcon),
          ]),
          const SizedBox(height: 10),
          _simpleTable(
            ['เซต', 'ครั้ง', 'น้ำหนัก', 'ความหนัก'],
            sets.map((s) => [
              '${s.setNo}',
              '${s.reps}',
              '${s.weight.toStringAsFixed(1)} kg',
              _intensityLabel(s.intensityLevel),
            ]).toList(),
            flex: [1, 1, 2, 2],
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _avgBox('ปริมาตรการฝึกรวม', '${volume.round()}', 'kg×reps', AppColors.weightIcon)),
            const SizedBox(width: 8),
            Expanded(child: _avgBox('1RM โดยประมาณ',
                est1rm == null ? '-' : est1rm.toStringAsFixed(1),
                'kg',
                AppColors.primaryGreen)),
          ]),
        ])),
      );
    }).toList());
  }

  Widget _buildCardioDetail() {
    if (_cardioResults.isEmpty) {
      return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('รายละเอียดคาร์ดิโอ', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        const SizedBox(height: 16),
        _emptyState('ยังไม่ได้บันทึกคาร์ดิโอวันนี้', icon: Icons.directions_run_rounded),
      ]));
    }
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('รายละเอียดคาร์ดิโอ', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 12),
      ..._cardioResults.map((c) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.cardioBg, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.directions_run_rounded, size: 16, color: AppColors.cardioIcon),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.cardioTypeName ?? 'คาร์ดิโอ', style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
            Text(
              c.distance > 0
                  ? '${c.duration.toStringAsFixed(0)} นาที • ${c.distance.toStringAsFixed(1)} กม.'
                  : '${c.duration.toStringAsFixed(0)} นาที',
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ])),
          Text('${c.caloriesBurned.round()} kcal', style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.cardioIcon)),
        ]),
      )),
    ]));
  }

  Widget _buildMuscleGroupBadges() {
    if (_muscles.isEmpty) {
      return _card(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('กล้ามเนื้อที่ฝึก 7 วัน', style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          const SizedBox(height: 14),
          _emptyState('ยังไม่ได้ฝึกสัปดาห์นี้', icon: Icons.fitness_center_rounded),
        ],
      ));
    }

    const zn = {1: 'ส่วนบน', 2: 'ส่วนล่าง', 3: 'แกนกลาง'};
    final byZone = <int, List<MuscleGroupCoverage>>{};
    for (final m in _muscles) {
      byZone.putIfAbsent(m.mugZone, () => []).add(m);
    }

    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('กล้ามเนื้อที่ฝึก 7 วัน', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        _badge('${_muscles.length} กลุ่ม', AppColors.primaryGreen),
      ]),
      const SizedBox(height: 14),
      ...byZone.entries.map((entry) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(zn[entry.key] ?? '', style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6,
            children: entry.value.map((m) {
              final ic = m.trainedDays >= 3 ? AppColors.primaryGreen
                  : (m.trainedDays >= 2 ? Colors.orange : AppColors.cardioIcon);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: ic.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: ic.withValues(alpha: 0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6,
                      decoration: BoxDecoration(color: ic, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(m.mugName, style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: ic)),
                  const SizedBox(width: 4),
                  Text('${m.trainedDays}วัน',
                      style: TextStyle(fontSize: 9, color: ic.withValues(alpha: 0.7))),
                ]),
              );
            }).toList()),
        ]),
      )),
    ]));
  }

  Widget _buildConsistencyRow() {
    final pts   = _weekly?.weekData ?? [];
    const dn    = ['อา','จ','อ','พ','พฤ','ศ','ส'];
    final today = DateTime.now();

    // map ด้วยวันที่จริงแทนการอ้าง index — กัน backend ส่งเฉพาะวันที่มีข้อมูล
    // ทำให้วงกลมเลื่อนไปแสดงผิดวัน (คำสั่งที่ 15)
    final byDate = <String, WeeklyDataPoint>{};
    for (final p in pts) {
      final dt = DateTime.tryParse(p.date);
      if (dt != null) byDate['${dt.year}-${dt.month}-${dt.day}'] = p;
    }

    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('ความสม่ำเสมอ 7 วัน', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        _badge('$_workoutDaysThisWeek / 7 วัน',
            _workoutDaysThisWeek >= 4 ? AppColors.primaryGreen : Colors.orange),
      ]),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(7, (i) {
          final day = today.subtract(Duration(days: 6 - i));
          final pt  = byDate['${day.year}-${day.month}-${day.day}'];
          final has = pt != null && (pt.cardioOut > 0 || pt.weightOut > 0);
          final isTd = i == 6; // วันสุดท้ายที่สร้างคือวันนี้เสมอ
          final nm  = dn[day.weekday % 7];
          return Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: has ? AppColors.primaryGreen : AppColors.background,
                shape: BoxShape.circle,
                border: Border.all(
                    color: isTd ? AppColors.primaryGreen
                        : has ? Colors.transparent : AppColors.divider,
                    width: isTd ? 2 : 1)),
              child: Center(child: Icon(
                has ? Icons.fitness_center_rounded : Icons.remove, size: 15,
                color: has ? Colors.black87 : AppColors.divider))),
            const SizedBox(height: 5),
            Text(nm, style: TextStyle(fontSize: 10,
                color: isTd ? AppColors.primaryGreen : AppColors.textMuted,
                fontWeight: isTd ? FontWeight.bold : FontWeight.normal)),
          ]);
        }),
      ),
    ]));
  }

  Widget _buildWorkoutSplitChart() {
    final pts = _weekly?.weekData ?? [];
    const dn  = ['อา','จ','อ','พ','พฤ','ศ','ส'];
    final tw  = pts.fold(0.0, (s, e) => s + e.weightOut);
    final tc  = pts.fold(0.0, (s, e) => s + e.cardioOut);

    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('การออกกำลังกาย 7 วัน', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        _badge('$_workoutDaysThisWeek วัน',
            _workoutDaysThisWeek >= 3 ? AppColors.primaryGreen : Colors.orange),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _dot(AppColors.primaryGreen, 'เวทเทรน'), const SizedBox(width: 12),
        _dot(AppColors.cardioIcon, 'คาร์ดิโอ'),
      ]),
      const SizedBox(height: 14),
      SizedBox(height: 140,
        child: pts.isEmpty ? _emptyChart() : CustomPaint(
          painter: _SplitBarPainter(
            weightData: pts.map((e) => e.weightOut).toList(),
            cardioData: pts.map((e) => e.cardioOut).toList(),
            weightColor: AppColors.primaryGreen, cardioColor: AppColors.cardioIcon,
          ), size: Size.infinite)),
      if (pts.isNotEmpty) ...[
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: pts.map((e) {
            final dt = DateTime.tryParse(e.date);
            return Text(dt != null ? dn[dt.weekday % 7] : '',
                style: const TextStyle(fontSize: 10, color: AppColors.textMuted));
          }).toList()),
      ],
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _avgBox('เวทเทรน', '${tw.round()}', 'kcal/สัปดาห์', AppColors.primaryGreen)),
        const SizedBox(width: 8),
        Expanded(child: _avgBox('คาร์ดิโอ', '${tc.round()}', 'kcal/สัปดาห์', AppColors.cardioIcon)),
        const SizedBox(width: 8),
        Expanded(child: _avgBox('รวม', '${(tw + tc).round()}', 'kcal/สัปดาห์', const Color(0xFFF85B07))),
      ]),
    ]));
  }

  Widget _buildWeeklyExerciseAverages() {
    final pts = _weekly?.weekData ?? [];
    final n   = pts.length.toDouble().clamp(1.0, 7.0);
    final aw  = pts.fold(0.0, (s, e) => s + e.weightOut) / n;
    final ac  = pts.fold(0.0, (s, e) => s + e.cardioOut) / n;

    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ค่าเฉลี่ยการออกกำลังกาย', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _avgBox('เวทเฉลี่ย', '${aw.round()}', 'kcal/วัน', AppColors.primaryGreen)),
        const SizedBox(width: 8),
        Expanded(child: _avgBox('คาร์ดิโอเฉลี่ย', '${ac.round()}', 'kcal/วัน', AppColors.cardioIcon)),
        const SizedBox(width: 8),
        Expanded(child: _avgBox('รวมเฉลี่ย', '${(aw + ac).round()}', 'kcal/วัน', const Color(0xFFF85B07))),
      ]),
    ]));
  }

  Widget _buildMonthlyWorkoutAreaChart() {
    final pts = _monthly?.monthData ?? [];
    String lbl(String raw) {
      final d = raw.split('T').first;
      return d.length >= 5 ? d.substring(5) : d;
    }
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('การออกกำลังกายรายเดือน', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        Row(children: [
          _dot(AppColors.primaryGreen, 'เวท'), const SizedBox(width: 10),
          _dot(AppColors.cardioIcon, 'คาร์ดิโอ'),
        ]),
      ]),
      const SizedBox(height: 18),
      SizedBox(height: 150,
        child: pts.length < 2 ? _emptyChart() : CustomPaint(
          painter: _AreaChartPainter(
            pointsIn: pts.map((e) => e.weightOut).toList(),
            pointsOut: pts.map((e) => e.cardioOut).toList(),
            colorIn: AppColors.primaryGreen, colorOut: AppColors.cardioIcon,
          ), size: Size.infinite)),
      if (pts.length >= 2) ...[
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(lbl(pts.first.date), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          if (pts.length > 4)
            Text(lbl(pts[pts.length ~/ 2].date),
                style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          Text(lbl(pts.last.date), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ]),
        const SizedBox(height: 4),
        const Text('จุดที่แตะ 0 = ยังไม่ได้บันทึกข้อมูลวันนั้น',
            style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
      ],
    ]));
  }

  Widget _buildMonthWorkoutComparisonCard() {
    final cmp = _comparison;
    if (cmp == null) return const SizedBox.shrink();
    final up = cmp.workoutChange >= 0;

    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('เทียบออกกำลังกายเดือนที่แล้ว', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _cmpBox('เดือนนี้', '${cmp.thisMonth.workoutDays} วัน',
            'ออกกำลังกาย', AppColors.primaryGreen)),
        const SizedBox(width: 10),
        Expanded(child: _cmpBox('เดือนที่แล้ว', '${cmp.lastMonth.workoutDays} วัน',
            'ออกกำลังกาย', AppColors.textMuted)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            color: up ? AppColors.primaryGreen : Colors.orange, size: 18),
        const SizedBox(width: 6),
        Text('${up ? '+' : ''}${cmp.workoutChange} วัน เทียบเดือนก่อน',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: up ? AppColors.primaryGreen : Colors.orange)),
      ]),
    ]));
  }

  Widget _buildMonthlyExerciseSummary() {
    final pts = _monthly?.monthData ?? [];
    final tw  = pts.fold(0.0, (s, e) => s + e.weightOut);
    final tc  = pts.fold(0.0, (s, e) => s + e.cardioOut);
    final wc  = _progress?.weightChange ?? 0;
    final cnt = _progress?.workoutCount ?? 0;
    final good = (_goalType == 1 && wc <= 0) || (_goalType == 2 && wc >= 0) || _goalType == 3;

    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('สรุปรายเดือน', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _stBox(Icons.calendar_today_rounded,
            '$cnt ครั้ง', 'วันออกกำลังกาย', AppColors.primaryGreen)),
        const SizedBox(width: 8),
        Expanded(child: _stBox(Icons.fitness_center_rounded,
            '${tw.round()} kcal', 'เวทเทรนรวม', AppColors.weightIcon)),
        const SizedBox(width: 8),
        Expanded(child: _stBox(Icons.directions_run_rounded,
            '${tc.round()} kcal', 'คาร์ดิโอรวม', AppColors.cardioIcon)),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (good ? AppColors.primaryGreen : Colors.orange).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.scale_rounded,
              color: good ? AppColors.primaryGreen : Colors.orange, size: 18),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('น้ำหนักเปลี่ยนแปลง',
                style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            Text('${wc >= 0 ? '+' : ''}${wc.toStringAsFixed(1)} กก.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                    color: good ? AppColors.primaryGreen : Colors.orange)),
          ]),
        ]),
      ),
    ]));
  }

  Widget _buildExerciseTable(List<(String, double, double)> pts) => _card(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ตารางการออกกำลังกาย', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 12),
      _simpleTable(
        ['วันที่', 'เวทเทรน (kcal)', 'คาร์ดิโอ (kcal)'],
        pts.map((p) => [_shortDate(p.$1), '${p.$2.round()}', '${p.$3.round()}']).toList(),
        flex: [2, 2, 2],
      ),
    ]),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 4 — BMI HISTORY
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildBmiTab() => RefreshIndicator(
    color: AppColors.primaryGreen,
    onRefresh: () async {
      ApiClient.clearCache();
      await _loadData();
    },
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
      children: [
        _buildBmiInterpretationCard(), const SizedBox(height: 12),
        _buildBmiBmrTdeeRow(),         const SizedBox(height: 12),
        _buildGoalCard(),              const SizedBox(height: 12),
        if (_viewMode == _ViewMode.graph) ...[
          _buildBmiTrendChart(),       const SizedBox(height: 12),
          _buildWeightHistoryChart(),
        ] else
          _buildBmiHistoryTable(),
      ],
    ),
  );

  Widget _buildBmiInterpretationCard() {
    const bands = [
      ('ผอมเกินไป', '< 18.5', 18.5),
      ('สมส่วน', '18.5 – 22.9', 22.9),
      ('น้ำหนักเกิน', '23.0 – 24.9', 24.9),
      ('โรคอ้วน', '≥ 25.0', double.infinity),
    ];
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('ดัชนีมวลกาย (BMI)', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        Text(_bmi <= 0 ? '-' : _bmi.toStringAsFixed(2), style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.bold, color: _bmiColor)),
      ]),
      const SizedBox(height: 4),
      Text('เกณฑ์เอเชีย-แปซิฟิก', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
      const SizedBox(height: 14),
      ...bands.map((b) {
        final isCurrent = b.$1 == _bmiCategory;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isCurrent ? _bmiColor.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isCurrent ? Border.all(color: _bmiColor.withValues(alpha: 0.3)) : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(b.$1, style: TextStyle(fontSize: 12,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                color: isCurrent ? _bmiColor : AppColors.textBody)),
            Text(b.$2, style: TextStyle(fontSize: 11,
                color: isCurrent ? _bmiColor : AppColors.textMuted)),
          ]),
        );
      }),
    ]));
  }

  Widget _buildGoalCard() => _card(child: Row(children: [
    Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.primaryGreen.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12)),
      child: const Icon(Icons.flag_rounded, color: AppColors.primaryGreen, size: 18),
    ),
    const SizedBox(width: 12),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('เป้าหมายสุขภาพ', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
      Text(_goalLabel, style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
    ]),
  ]));

  Widget _buildBmiBmrTdeeRow() {
    final estSub = _daily?.isBmrEstimated == true ? 'ค่าประมาณ' : 'kcal/วัน';
    return Column(children: [
      Row(children: [
        Expanded(child: _miniCard('BMI',  _bmi.toStringAsFixed(2), _bmiCategory,
            _bmiColor, Icons.monitor_weight_outlined)),
        const SizedBox(width: 10),
        Expanded(child: _miniCard('BMR',  '${_bmr.round()}', estSub,
            AppColors.cardioIcon, Icons.favorite_border_rounded)),
        const SizedBox(width: 10),
        Expanded(child: _miniCard('TDEE', '${_tdee.round()}', estSub,
            AppColors.weightIcon, Icons.bolt_rounded)),
      ]),
      if (_daily?.isBmrEstimated == true) ...[
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.info_outline_rounded, size: 13,
              color: AppColors.textMuted.withValues(alpha: 0.8)),
          const SizedBox(width: 6),
          Expanded(child: Text(
              'ยังไม่มีข้อมูลร่างกายบันทึกไว้ ค่า BMR/TDEE นี้เป็นค่าประมาณเบื้องต้น',
              style: TextStyle(fontSize: 10, color: AppColors.textMuted.withValues(alpha: 0.8)))),
        ]),
      ],
    ]);
  }

  Widget _miniCard(String title, String value, String sub, Color color, IconData icon) =>
    Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title, style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
          Icon(icon, size: 14, color: color),
        ]),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(sub, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
      ]),
    );

  /// กรองประวัติร่างกายตามช่วงเวลาที่เลือกบนแท็บ (รายวัน = ถึงวันที่เลือก,
  /// รายสัปดาห์ = 7 วันล่าสุด, รายเดือน = เดือนที่เลือก) ตามคำสั่งที่ 9
  List<BodyPoint> get _filteredBodyHistory {
    final all = _progress?.bodyHistory ?? [];
    switch (_selectedPeriod) {
      case 1:
        final cutoff = DateTime.now().subtract(const Duration(days: 7));
        return all.where((p) {
          final d = DateTime.tryParse(p.date);
          return d != null && !d.isBefore(cutoff);
        }).toList();
      case 2:
        return all.where((p) {
          final d = DateTime.tryParse(p.date);
          return d != null && d.year == _selectedMonth.year && d.month == _selectedMonth.month;
        }).toList();
      default:
        return all.where((p) {
          final d = DateTime.tryParse(p.date);
          return d != null && !d.isAfter(_selectedDate);
        }).toList();
    }
  }

  /// index ของจุดที่ activity level หรือเป้าหมาย (target) เปลี่ยนจากจุดก่อนหน้า — ใช้ mark บนกราฟ
  /// BMI/น้ำหนัก ให้ผู้ใช้เข้าใจว่าทำไมเส้นแนวโน้มเปลี่ยน ไม่ใช่แค่ลากเส้นเฉยๆ ไม่มีคำอธิบาย
  Set<int> get _bodyChangeIndices {
    final pts = _filteredBodyHistory;
    final out = <int>{};
    for (int i = 1; i < pts.length; i++) {
      if (pts[i].activityLevel != pts[i - 1].activityLevel || pts[i].target != pts[i - 1].target) {
        out.add(i);
      }
    }
    return out;
  }

  Widget _buildBmiTrendChart() {
    final pts = _filteredBodyHistory;
    if (pts.length < 2) {
      return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('แนวโน้ม BMI', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        const SizedBox(height: 16),
        _emptyState('ไม่มีการบันทึกข้อมูลร่างกายในช่วงนี้'),
      ]));
    }
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('แนวโน้ม BMI', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 16),
      SizedBox(height: 130,
        child: CustomPaint(
          painter: _LineChartPainter(
              values: pts.map((e) => e.bmi).toList(), color: _bmiColor,
              changeIndices: _bodyChangeIndices),
          size: Size.infinite)),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('BMI ${pts.first.bmi.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        Text('ปัจจุบัน ${pts.last.bmi.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _bmiColor)),
      ]),
      if (_bodyChangeIndices.isNotEmpty) ...[
        const SizedBox(height: 6),
        const Text('เส้นประ = วันที่เปลี่ยนระดับกิจกรรม/เป้าหมาย',
            style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
      ],
    ]));
  }

  Widget _buildWeightHistoryChart() {
    final pts = _filteredBodyHistory;
    if (pts.length < 2) {
      return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('น้ำหนักรายเดือน', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        const SizedBox(height: 16),
        _emptyState('ไม่มีการบันทึกข้อมูลร่างกายในช่วงนี้'),
      ]));
    }

    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('น้ำหนักรายเดือน', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 16),
      SizedBox(height: 130,
        child: CustomPaint(
          painter: _LineChartPainter(
              values: pts.map((e) => e.weight).toList(), color: AppColors.primaryGreen,
              changeIndices: _bodyChangeIndices),
          size: Size.infinite)),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('${pts.first.weight.toStringAsFixed(1)} กก.',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        Text('ปัจจุบัน ${pts.last.weight.toStringAsFixed(1)} กก.',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: AppColors.primaryGreen)),
      ]),
      if (_bodyChangeIndices.isNotEmpty) ...[
        const SizedBox(height: 6),
        const Text('เส้นประ = วันที่เปลี่ยนระดับกิจกรรม/เป้าหมาย',
            style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
      ],
    ]));
  }

  Widget _buildBmiHistoryTable() {
    final pts = _filteredBodyHistory;
    if (pts.isEmpty) {
      return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ตารางน้ำหนัก / BMI ย้อนหลัง', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        const SizedBox(height: 16),
        _emptyState('ไม่มีการบันทึกข้อมูลร่างกายในช่วงนี้'),
      ]));
    }
    final changeIdx = _bodyChangeIndices;
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ตารางน้ำหนัก / BMI ย้อนหลัง', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      const SizedBox(height: 12),
      _simpleTable(
        ['วันที่', 'น้ำหนัก', 'BMI'],
        pts.asMap().entries.map((e) => [
          changeIdx.contains(e.key) ? '${_shortDate(e.value.date)} ●' : _shortDate(e.value.date),
          '${e.value.weight.toStringAsFixed(1)} กก.',
          e.value.bmi.toStringAsFixed(2),
        ]).toList(),
        flex: [2, 2, 2],
      ),
      if (changeIdx.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('● = วันที่เปลี่ยนระดับกิจกรรม/เป้าหมาย',
            style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
      ],
    ]));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED HELPERS
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _card({required Widget child}) => Container(
    width: double.infinity, padding: const EdgeInsets.all(20),
    decoration: _cardDeco(), child: child,
  );

  BoxDecoration _cardDeco() => BoxDecoration(
    color: Colors.white, borderRadius: BorderRadius.circular(20),
    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 12, offset: const Offset(0, 4))],
  );

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
  );

  Widget _dot(Color color, String label) => Row(children: [
    Container(width: 8, height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
  ]);

  Widget _avgBox(String label, String value, String unit, Color color) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      if (unit.isNotEmpty)
        Text(unit, style: const TextStyle(fontSize: 8, color: AppColors.textMuted)),
    ]),
  );

  Widget _stBox(IconData icon, String value, String label, Color color) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(height: 5),
      Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
      const SizedBox(height: 1),
      Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );

  Widget _cmpBox(String title, String value, String sub, Color color) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
      Text(sub, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
    ]),
  );

  Widget _emptyChart() => const Center(
    child: Text('ยังไม่มีข้อมูล', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
  );

  Widget _emptyState(String msg, {IconData icon = Icons.info_outline_rounded}) => Center(
    child: Column(children: [
      Icon(icon, size: 32, color: AppColors.textMuted.withValues(alpha: 0.4)),
      const SizedBox(height: 8),
      Text(msg, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
    ]),
  );

  String _shortDate(String raw) {
    final d = raw.split('T').first;
    return d.length >= 10 ? d.substring(5) : d;
  }

  Widget _simpleTable(List<String> headers, List<List<String>> rows, {List<int>? flex}) {
    final f = flex ?? List.filled(headers.length, 1);
    Widget row(List<String> cells, {bool isHeader = false}) => Padding(
      padding: EdgeInsets.symmetric(vertical: isHeader ? 4 : 8),
      child: Row(children: List.generate(cells.length, (i) => Expanded(
        flex: i < f.length ? f[i] : 1,
        child: Text(cells[i],
            textAlign: i == 0 ? TextAlign.left : TextAlign.right,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: isHeader ? 10 : 11.5,
                fontWeight: isHeader ? FontWeight.w700 : FontWeight.w500,
                color: isHeader ? AppColors.textMuted : AppColors.textDark)),
      ))),
    );
    return Column(children: [
      row(headers, isHeader: true),
      const Divider(height: 1, color: AppColors.divider),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: _emptyState('ยังไม่มีข้อมูล'),
        )
      else
        ...rows.map((r) => Column(children: [
          row(r),
          const Divider(height: 1, color: AppColors.divider),
        ])),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHIMMER
// ═══════════════════════════════════════════════════════════════════════════════
class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox();
  @override State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(_ctrl);
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [
          Colors.grey.withValues(alpha: _anim.value * 0.15),
          Colors.grey.withValues(alpha: _anim.value * 0.08),
          Colors.grey.withValues(alpha: _anim.value * 0.15),
        ]),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════
class _DonutPainter extends CustomPainter {
  final double progress; final Color trackColor, fillColor, overColor; final bool isOver;
  const _DonutPainter({required this.progress, required this.trackColor,
      required this.fillColor, required this.overColor, required this.isOver});
  @override
  void paint(Canvas canvas, Size size) {
    const sw = 14.0;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - sw / 2;
    canvas.drawCircle(c, r, Paint()..color = trackColor
        ..style = PaintingStyle.stroke..strokeWidth = sw);
    if (progress > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r),
          -math.pi / 2, 2 * math.pi * progress.clamp(0.0, 1.0), false,
          Paint()..color = isOver ? overColor : fillColor
              ..style = PaintingStyle.stroke..strokeWidth = sw..strokeCap = StrokeCap.round);
    }
  }
  @override bool shouldRepaint(_DonutPainter o) => o.progress != progress || o.isOver != isOver;
}

class _MiniDonutPainter extends CustomPainter {
  final List<double> values; final List<Color> colors;
  const _MiniDonutPainter({required this.values, required this.colors});
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0.0, (s, v) => s + v);
    if (total == 0) return;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 5;
    double angle = -math.pi / 2;
    for (int i = 0; i < values.length; i++) {
      final sweep = 2 * math.pi * values[i] / total;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), angle, sweep, false,
          Paint()..color = colors[i % colors.length]
              ..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.butt);
      angle += sweep;
    }
  }
  @override bool shouldRepaint(_MiniDonutPainter o) => o.values != values;
}

class _BarChartPainter extends CustomPainter {
  final List<double> dataIn, dataOut;
  // เป้าหมายต่อวัน (ค่าที่มีผลใช้งานจริง ณ วันนั้น) ยาวเท่า dataIn เสมอ — ไม่ใช่ค่าคงที่ค่าเดียว
  // เพราะถ้าผู้ใช้เปลี่ยนเป้าหมายกลางสัปดาห์ เส้นต้องสลับตรงวันที่เปลี่ยนจริง ไม่ใช่ลากเส้นแบนค่าเดียว
  final List<double> targetLine;
  final Color colorIn, colorOut;
  const _BarChartPainter({required this.dataIn, required this.dataOut,
      required this.targetLine, required this.colorIn, required this.colorOut});
  @override
  void paint(Canvas canvas, Size size) {
    if (dataIn.isEmpty) return;
    final maxVal = [...dataIn, ...dataOut, ...targetLine].reduce(math.max) * 1.15;
    final range  = maxVal.clamp(1.0, double.infinity);
    final gW = size.width / dataIn.length;
    final bW = gW * 0.28;
    const gap = 3.0;
    for (int i = 0; i < dataIn.length; i++) {
      final cx = i * gW + gW / 2;
      final hI = (dataIn[i] / range * size.height).clamp(2.0, size.height);
      canvas.drawRRect(RRect.fromRectAndCorners(
          Rect.fromLTWH(cx - bW - gap, size.height - hI, bW, hI),
          topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
          Paint()..color = colorIn);
      final hO = (dataOut[i] / range * size.height).clamp(0.0, size.height);
      if (hO > 0) {
        canvas.drawRRect(RRect.fromRectAndCorners(
            Rect.fromLTWH(cx + gap, size.height - hO, bW, hO),
            topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
            Paint()..color = colorOut);
      }
    }
    // เส้น target แบบขั้นบันได (step line) — หนึ่งช่วงแนวนอนต่อวัน สลับระดับตรงวันที่ targetLine[i] เปลี่ยน
    final p = Paint()..color = AppColors.textMuted.withValues(alpha: 0.5)
        ..strokeWidth = 1.5..style = PaintingStyle.stroke;
    for (int i = 0; i < targetLine.length && i < dataIn.length; i++) {
      if (targetLine[i] <= 0 || targetLine[i] > maxVal) continue;
      final y = size.height - (targetLine[i] / range * size.height);
      final xStart = i * gW;
      final xEnd = xStart + gW;
      double x = xStart;
      while (x < xEnd) { canvas.drawLine(Offset(x, y), Offset(math.min(x + 8, xEnd), y), p); x += 13; }
      // เส้นแนวตั้งสั้นๆ เชื่อมรอยต่อเมื่อค่าระหว่างวันเปลี่ยน ให้เห็นชัดว่าเป้าหมาย "สลับ" ตรงนี้
      if (i > 0 && targetLine[i - 1] > 0 && (targetLine[i] - targetLine[i - 1]).abs() > 0.01) {
        final yPrev = size.height - (targetLine[i - 1] / range * size.height);
        canvas.drawLine(Offset(xStart, yPrev), Offset(xStart, y), p);
      }
    }
  }
  @override bool shouldRepaint(_BarChartPainter o) =>
      o.dataIn != dataIn || o.dataOut != dataOut || o.targetLine != targetLine;
}

class _AreaChartPainter extends CustomPainter {
  final List<double> pointsIn, pointsOut;
  // เป้าหมายต่อวัน (ค่าที่มีผลใช้งานจริง ณ วันนั้น) — วาดเป็นเส้นขั้นบันไดสลับตรงวันที่เปลี่ยนเป้าหมาย
  // เหมือน _BarChartPainter ไม่ใช่ค่าคงที่ค่าเดียวลากยาวทั้งเดือน
  final List<double> targetLine;
  final Color colorIn, colorOut;
  const _AreaChartPainter({required this.pointsIn, required this.pointsOut,
      this.targetLine = const [], required this.colorIn, required this.colorOut});
  @override
  void paint(Canvas canvas, Size size) {
    if (pointsIn.length < 2) return;
    final maxVal = [...pointsIn, ...pointsOut, ...targetLine].reduce(math.max).clamp(1.0, double.infinity);
    void draw(List<double> pts, Color color) {
      final offs = <Offset>[];
      final sx   = size.width / (pts.length - 1);
      for (int i = 0; i < pts.length; i++) {
        offs.add(Offset(i * sx,
            size.height - (pts[i] / maxVal * size.height * 0.85 + size.height * 0.05)));
      }
      final fill = Path()..moveTo(offs.first.dx, size.height);
      final line = Path()..moveTo(offs.first.dx, offs.first.dy);
      fill.lineTo(offs.first.dx, offs.first.dy);
      for (int i = 0; i < offs.length - 1; i++) {
        final cp1 = Offset((offs[i].dx + offs[i+1].dx) / 2, offs[i].dy);
        final cp2 = Offset((offs[i].dx + offs[i+1].dx) / 2, offs[i+1].dy);
        fill.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, offs[i+1].dx, offs[i+1].dy);
        line.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, offs[i+1].dx, offs[i+1].dy);
      }
      fill..lineTo(offs.last.dx, size.height)..close();
      canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.1)..style = PaintingStyle.fill);
      canvas.drawPath(line, Paint()..color = color..style = PaintingStyle.stroke
          ..strokeWidth = 2.5..strokeCap = StrokeCap.round);
    }
    draw(pointsOut, colorOut);
    draw(pointsIn,  colorIn);

    if (targetLine.length == pointsIn.length && pointsIn.length > 1) {
      final sx = size.width / (pointsIn.length - 1);
      final p = Paint()..color = AppColors.textMuted.withValues(alpha: 0.5)
          ..strokeWidth = 1.5..style = PaintingStyle.stroke;
      for (int i = 0; i < targetLine.length; i++) {
        if (targetLine[i] <= 0 || targetLine[i] > maxVal) continue;
        final y = size.height - (targetLine[i] / maxVal * size.height * 0.85 + size.height * 0.05);
        final xStart = i * sx;
        final xEnd = math.min((i + 1) * sx, size.width);
        double x = xStart;
        while (x < xEnd) { canvas.drawLine(Offset(x, y), Offset(math.min(x + 8, xEnd), y), p); x += 13; }
        if (i > 0 && targetLine[i - 1] > 0 && (targetLine[i] - targetLine[i - 1]).abs() > 0.01) {
          final yPrev = size.height - (targetLine[i - 1] / maxVal * size.height * 0.85 + size.height * 0.05);
          canvas.drawLine(Offset(xStart, yPrev), Offset(xStart, y), p);
        }
      }
    }
  }
  @override bool shouldRepaint(_AreaChartPainter o) =>
      o.pointsIn != pointsIn || o.pointsOut != pointsOut || o.targetLine != targetLine;
}

class _SplitBarPainter extends CustomPainter {
  final List<double> weightData, cardioData; final Color weightColor, cardioColor;
  const _SplitBarPainter({required this.weightData, required this.cardioData,
      required this.weightColor, required this.cardioColor});
  @override
  void paint(Canvas canvas, Size size) {
    if (weightData.isEmpty) return;
    final combined = List.generate(weightData.length, (i) => weightData[i] + cardioData[i]);
    final maxVal = combined.reduce(math.max) * 1.15;
    final range  = maxVal.clamp(1.0, double.infinity);
    final gW = size.width / weightData.length;
    final bW = gW * 0.5;
    for (int i = 0; i < weightData.length; i++) {
      final cx = i * gW + gW / 2;
      final hW = (weightData[i] / range * size.height).clamp(0.0, size.height);
      final hC = (cardioData[i]  / range * size.height).clamp(0.0, size.height);
      if (hW > 0) {
        canvas.drawRRect(RRect.fromRectAndCorners(
            Rect.fromLTWH(cx - bW/2, size.height - hW, bW, hW),
            bottomLeft: const Radius.circular(3), bottomRight: const Radius.circular(3),
            topLeft: hC <= 0 ? const Radius.circular(4) : Radius.zero,
            topRight: hC <= 0 ? const Radius.circular(4) : Radius.zero),
            Paint()..color = weightColor);
      }
      if (hC > 0) {
        canvas.drawRRect(RRect.fromRectAndCorners(
            Rect.fromLTWH(cx - bW/2, size.height - hW - hC, bW, hC),
            topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
            Paint()..color = cardioColor);
      }
    }
  }
  @override bool shouldRepaint(_SplitBarPainter o) =>
      o.weightData != weightData || o.cardioData != cardioData;
}

class _LineChartPainter extends CustomPainter {
  final List<double> values; final Color color;
  // index ของจุดที่ activity level/เป้าหมายเปลี่ยนจากจุดก่อนหน้า — วาดเส้นประแนวตั้ง + วงแหวน mark
  // ให้เห็นว่าทำไมแนวโน้มกราฟเปลี่ยน ไม่ใช่แค่เส้นเรียบเส้นเดียวไม่มีคำอธิบาย
  final Set<int> changeIndices;
  const _LineChartPainter({required this.values, required this.color, this.changeIndices = const {}});
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV  = values.reduce(math.min);
    final maxV  = values.reduce(math.max);
    final range = (maxV - minV).clamp(0.1, double.infinity);
    final sx    = size.width / (values.length - 1);
    Offset toOff(int i) => Offset(i * sx,
        size.height - ((values[i] - minV) / range * size.height * 0.8 + size.height * 0.1));
    final fill = Path()..moveTo(0, size.height)..lineTo(toOff(0).dx, toOff(0).dy);
    final line = Path()..moveTo(toOff(0).dx, toOff(0).dy);
    for (int i = 0; i < values.length - 1; i++) {
      final a = toOff(i); final b = toOff(i + 1);
      final cp1 = Offset((a.dx + b.dx) / 2, a.dy);
      final cp2 = Offset((a.dx + b.dx) / 2, b.dy);
      fill.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, b.dx, b.dy);
      line.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, b.dx, b.dy);
    }
    fill..lineTo(size.width, size.height)..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.1)..style = PaintingStyle.fill);
    canvas.drawPath(line, Paint()..color = color..style = PaintingStyle.stroke
        ..strokeWidth = 2.5..strokeCap = StrokeCap.round);
    for (final i in changeIndices) {
      if (i <= 0 || i >= values.length) continue;
      final off = toOff(i);
      final dash = Paint()..color = Colors.orange.withValues(alpha: 0.6)
          ..strokeWidth = 1.2..style = PaintingStyle.stroke;
      double y = 0;
      while (y < size.height) { canvas.drawLine(Offset(off.dx, y), Offset(off.dx, math.min(y + 4, size.height)), dash); y += 7; }
      canvas.drawCircle(off, 4, Paint()..color = Colors.orange);
      canvas.drawCircle(off, 4, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
    canvas.drawCircle(toOff(0), 4, Paint()..color = color);
    canvas.drawCircle(toOff(values.length - 1), 5, Paint()..color = color);
    canvas.drawCircle(toOff(values.length - 1), 5,
        Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
  }
  @override bool shouldRepaint(_LineChartPainter o) =>
      o.values != values || o.changeIndices != changeIndices;
}
