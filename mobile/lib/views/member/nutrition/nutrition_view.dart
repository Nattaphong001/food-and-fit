// หน้า: Nutrition (บันทึกอาหาร)
// ทำหน้าที่: หน้าบันทึกและดูรายการอาหารประจำวัน แสดงแคลอรี่และสารอาหาร เพิ่มหรือลบรายการอาหารได้

import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/cached_image.dart';
import '../../../core/widgets/weekly_calendar_component.dart';
import '../../../core/widgets/sticky_filter_chip_bar.dart';
import '../../../core/widgets/swipe_delete_item.dart';
import '../../../core/widgets/undo_snackbar.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../models/analytics_model.dart';
import '../../../models/nutrition_model.dart';
import '../../../services/api_client.dart';
import '../../../services/analytics_service.dart';
import '../../../services/nutrition_service.dart';
import '../../../core/widgets/app_date_picker_sheet.dart';
import 'food_list_view.dart';

class NutritionView extends StatefulWidget {
  final ValueNotifier<int>? dashboardRefreshNotifier;
  // แยกจาก dashboardRefreshNotifier — bump จาก HomeView เมื่อแก้ข้อมูลร่างกาย/เป้าหมายสำเร็จเท่านั้น
  // (dashboardRefreshNotifier ตัวเดิม _loadAll() เองก็ bump มันอยู่แล้ว ใช้ตัวเดียวกันจะวนลูปโหลดซ้ำ)
  final ValueNotifier<int>? profileRefreshNotifier;
  const NutritionView({super.key, this.dashboardRefreshNotifier, this.profileRefreshNotifier});

  @override
  State<NutritionView> createState() => NutritionViewState();
}

class NutritionViewState extends State<NutritionView> with RouteAware {
  late DateTime _selectedDate;
  List<DailyNutrition> _foodLog = [];
  List<NutritionCategory> _categories = [];
  int _selectedCategoryId = 0;
  bool _isLoading = true;
  DailyAnalytics? _analytics;
  final Set<int> _pendingDeleteIds = {}; // รายการที่กำลังรอ undo หลังปัดลบ

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    widget.profileRefreshNotifier?.addListener(_loadAll);
    _loadAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) undoRouteObserver.subscribe(this, route);
  }

  // มีหน้าอื่นถูกดันมาบังหน้านี้ — commit การลบรายการอาหารที่ค้าง undo อยู่ทันที กัน toast ลอยตาม
  // ไปโผล่ทับหน้าถัดไป (Overlay entry ไม่ผูกกับ route เลย ปล่อยไว้จะค้างจนกว่าจะหมดเวลาเองหรือถูกปัดทิ้งเอง)
  @override
  void didPushNext() => commitPendingUndo();

  @override
  void dispose() {
    undoRouteObserver.unsubscribe(this);
    commitPendingUndo(); // ออกจากหน้านี้ไปเลย (กดย้อนกลับ) ก็ commit ทันทีเหมือนกัน
    widget.profileRefreshNotifier?.removeListener(_loadAll);
    super.dispose();
  }

  // ตัดรายการที่กำลังรอ undo (ปัดลบไปแล้ว) ออกจากทุกยอดรวม ไม่งั้นแคล/มาโครจะไม่ลดจนกว่า undo snackbar จะหมดเวลา
  List<DailyNutrition> get _visibleFoodLog =>
      _foodLog.where((item) => !_pendingDeleteIds.contains(item.id)).toList();

  double get _totalCalories => _visibleFoodLog.fold(0.0, (sum, item) => sum + item.totalCalories);
  double get _totalProtein => _visibleFoodLog.fold(0.0, (sum, item) => sum + item.totalProtein);
  double get _totalCarbs   => _visibleFoodLog.fold(0.0, (sum, item) => sum + item.totalCarbs);
  double get _totalFat     => _visibleFoodLog.fold(0.0, (sum, item) => sum + item.totalFat);

  static const _thaiMonthsShort = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];

  // "วันนี้" ถ้าเลือกวันปัจจุบัน ไม่งั้นแสดงวันที่จริงที่เลือก
  String get _dateLabel {
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    if (isToday) return 'วันนี้';
    return 'วันที่ ${_selectedDate.day} ${_thaiMonthsShort[_selectedDate.month - 1]}';
  }

  int get _goalType => _analytics?.goalType ?? 1;

  Map<String, double> get _macroTargetPct {
    switch (_goalType) {
      case 1: return {'protein': 0.40, 'carb': 0.35, 'fat': 0.25}; // ลดน้ำหนัก
      case 2: return {'protein': 0.30, 'carb': 0.50, 'fat': 0.20}; // เพิ่มน้ำหนัก/เพิ่มกล้ามเนื้อ
      default: return {'protein': 0.20, 'carb': 0.50, 'fat': 0.30}; // รักษาน้ำหนัก
    }
  }

  double get _targetCalories => (_analytics?.targetTdee ?? 0) > 0 ? _analytics!.targetTdee : 2000;
  double get _targetProtein => _targetCalories * _macroTargetPct['protein']! / 4;
  double get _targetCarbs   => _targetCalories * _macroTargetPct['carb']! / 4;
  double get _targetFat     => _targetCalories * _macroTargetPct['fat']! / 9;

  List<DailyNutrition> get _filteredFoodLog {
    final byCategory = _selectedCategoryId == 0
        ? _visibleFoodLog
        : _visibleFoodLog.where((item) => item.categoryId == _selectedCategoryId);
    return byCategory.toList().reversed.toList(); // ล่าสุดอยู่บนสุด
  }

  // เฉพาะหมวดที่มีรายการจริงในวันที่เลือก — หมวดที่ไม่มีรายการวันนั้นไม่โผล่เป็นตัวกรอง
  List<NutritionCategory> get _visibleCategories {
    final presentIds = _visibleFoodLog.map((item) => item.categoryId).toSet();
    return _categories.where((c) => presentIds.contains(c.categoryId)).toList();
  }

  // ดูประวัติย้อนหลังได้ไม่จำกัด — แต่ "บันทึกรายการใหม่" ย้อนหลังได้แค่ 7 วัน (ดู _canRecordFor)
  DateTime get _minRecordableDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7));
  }

  bool get _canRecordForSelectedDate => !_selectedDate.isBefore(_minRecordableDate);

  // เรียกจากปุ่ม + กลาง navbar ใน MainShell (ปุ่มย้ายออกไปอยู่นอกหน้านี้ ให้เกาะกับ navbar แทน)
  Future<void> addFood() async {
    if (!_canRecordForSelectedDate) {
      showAppAlert(context, 'บันทึกย้อนหลังได้สูงสุด 7 วัน', type: AppAlertType.error);
      return;
    }
    await Navigator.push(context, MaterialPageRoute(
        builder: (context) => FoodListView(targetDate: _selectedDate)));
    _loadNutrition();
  }

  // ปฏิทิน: ห้ามแค่วันในอนาคต ดูอดีตได้ไม่จำกัด
  bool _isDateDisabled(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    return d.isAfter(todayOnly);
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      NutritionService.to.getDailyNutrition(date: _selectedDate),
      AnalyticsService.to.getDailyAnalytics(date: _selectedDate),
      NutritionService.to.getCategories(),
    ]);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (results[0]['success'] == true) {
        _foodLog = results[0]['data'] as List<DailyNutrition>;
      }
      if (results[1]['success'] == true) {
        _analytics = results[1]['data'] as DailyAnalytics;
      }
      if (results[2]['success'] == true) {
        _categories = results[2]['data'] as List<NutritionCategory>;
      }
    });
    widget.dashboardRefreshNotifier?.value++;
  }

  Future<void> _loadNutrition() => _loadAll();

  // User > ลบรายการอาหารประจำวัน: ลบได้เลยไม่ต้องยืนยันก่อน — ซ่อนออกจากลิสต์ทันที แล้วรอ
  // หน้าต่าง undo (Floating Snackbar) ปิดก่อนค่อยยิง API ลบจริง กด "เลิกทำ" ทันได้ภายในเวลา
  void _handleSwipeDelete(DailyNutrition item) {
    setState(() => _pendingDeleteIds.add(item.id));
    showUndoSnackbar(
      context,
      message: 'ลบ "${item.foodName}" แล้ว',
      onUndo: () {
        if (!mounted) return;
        setState(() => _pendingDeleteIds.remove(item.id));
      },
      onExpire: () => _finalizeDelete(item),
    );
  }

  Future<void> _finalizeDelete(DailyNutrition item) async {
    final result = await NutritionService.to.deleteDailyNutrition(item.id);
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _foodLog.removeWhere((f) => f.id == item.id);
        _pendingDeleteIds.remove(item.id);
      });
      widget.dashboardRefreshNotifier?.value++;
    } else {
      setState(() => _pendingDeleteIds.remove(item.id));
      showAppAlert(context, result['message'] ?? 'ลบไม่สำเร็จ', type: AppAlertType.error);
    }
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
            await _loadNutrition();
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(
                child: WeeklyCalendarComponent(
                  selectedDate: _selectedDate,
                  isDisabled: _isDateDisabled,
                  onDaySelected: (date) {
                    setState(() {
                      _selectedDate = date;
                      _selectedCategoryId = 0; // ล้างตัวกรองเดิม กันเลือกหมวดที่วันใหม่ไม่มีรายการ
                    });
                    _loadNutrition();
                  },
                ),
              ),
              SliverToBoxAdapter(child: _buildCalorieDonut()),
              SliverToBoxAdapter(child: _buildMacrosRow()),
              SliverToBoxAdapter(child: _buildFoodLogHeader()),
              if (_visibleCategories.isNotEmpty)
                stickyFilterChipSliver<int>(
                  items: [
                    const FilterChipItem(id: 0, label: 'ทั้งหมด'),
                    ..._visibleCategories.map((c) => FilterChipItem(id: c.categoryId, label: c.categoryName)),
                  ],
                  selectedId: _selectedCategoryId,
                  onSelected: (id) => setState(() => _selectedCategoryId = id),
                ),
              if (_isLoading)
                const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))))
              else if (_filteredFoodLog.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(child: Text(
                      _selectedCategoryId == 0 ? 'ยังไม่มีรายการอาหารใน$_dateLabel' : 'ไม่มีรายการในหมวดนี้',
                      style: const TextStyle(color: AppColors.textMuted),
                    )),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final item = _filteredFoodLog[i];
                      return _AnimatedFoodCard(
                        key: ValueKey('food_anim_${item.id}'),
                        index: i,
                        child: _buildFoodCard(item),
                      );
                    },
                    childCount: _filteredFoodLog.length,
                  ),
                ),
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
          Expanded(
            child: Text('สรุปภาพรวม$_dateLabel',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textDark)),
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
                  _selectedCategoryId = 0;
                });
                _loadNutrition();
              }
            },
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
              ),
              child: const Icon(Icons.calendar_today_rounded, size: 19, color: AppColors.primaryGreen),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalorieDonut() {
    final consumed = _totalCalories;
    final progress = (consumed / _targetCalories).clamp(0.0, 1.0);
    final remaining = (_targetCalories - consumed).clamp(0.0, double.infinity);
    // สถานะเทียบเป้า ±10% → Over/On/Under Target (สูตรตาม CLAUDE.md ข้อ 5) — ของเดิมเช็คแค่
    // เกิน/ไม่เกิน ไม่มี "ต่ำกว่าเป้า" เลย ไม่ตรงสูตร
    final pctOfTarget = _targetCalories > 0 ? consumed / _targetCalories : 0.0;
    final isOver = pctOfTarget > 1.10;
    final isUnder = pctOfTarget < 0.90;
    final statusLabel = isOver ? 'เกินเป้า' : (isUnder ? 'ต่ำกว่าเป้า' : 'ตามแผน');
    final statusColor = isOver ? Colors.orange : (isUnder ? AppColors.alertInfo : AppColors.primaryGreen);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // ── Title row ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('แคลอรี่$_dateLabel',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Donut centered ──
          SizedBox(
            width: 150, height: 150,
            child: CustomPaint(
              painter: _DonutPainter(progress: progress),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      consumed.round().toString(),
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.textDark),
                    ),
                    const Text('kcal', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── 3 stats row ──
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(child: _buildCalorieStat('เป้าหมาย', _targetCalories.round(), AppColors.textMuted)),
                _buildStatDivider(),
                Expanded(child: _buildCalorieStat('รับแล้ว', consumed.round(), isOver ? Colors.orange : (isUnder ? AppColors.alertInfo : AppColors.textDark))),
                _buildStatDivider(),
                Expanded(child: _buildCalorieStat('คงเหลือ', remaining.round(), AppColors.primaryGreen)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalorieStat(String label, int value, Color valueColor) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: valueColor),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _buildStatDivider() {
    return VerticalDivider(
      width: 1, thickness: 1,
      color: AppColors.divider,
      indent: 4, endIndent: 4,
    );
  }

  Widget _buildMacrosRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(child: _buildMacroCard('โปรตีน', _totalProtein, _targetProtein, const Color(0xFF5B8CFF))),
          const SizedBox(width: 10),
          Expanded(child: _buildMacroCard('คาร์โบไฮเดรต', _totalCarbs, _targetCarbs, const Color(0xFFFFAB2E))),
          const SizedBox(width: 10),
          Expanded(child: _buildMacroCard('ไขมัน', _totalFat, _targetFat, const Color(0xFFFF6B6B))),
        ],
      ),
    );
  }

  Widget _buildMacroCard(String label, double value, double target, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('${value.round()} กรัม',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (value / target).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 6),
          Text('${target.round()} กรัม',
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildFoodLogHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('รายการบันทึกอาหารของ$_dateLabel',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          Text('${_filteredFoodLog.length} รายการ',
              style: const TextStyle(fontSize: 13, color: AppColors.primaryGreen, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildFoodImage(String? imageUrl, {double size = 55}) {
    if (imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: cachedImage(imageUrl, width: size, height: size, fit: BoxFit.cover),
      );
    }
    return _foodIconFallback(size: size);
  }

  Widget _macroTag(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$label $value', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _foodIconFallback({double size = 55}) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.restaurant_rounded, color: AppColors.primaryGreen, size: size * 0.5),
    );
  }

  Widget _buildFoodCard(DailyNutrition item) {
    return SwipeDeleteItem(
      itemKey: Key('food_${item.id}'),
      background: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: () => _handleSwipeDelete(item),
      // มาตรฐานเดียวกับการ์ดกิจกรรมในหน้าออกกำลังกาย: padding 16, รูป 55x55, เงา offset(0,3) alpha 0.05, กดดูรายละเอียดได้
      child: GestureDetector(
        onTap: () => _showFoodDetailSheet(item),
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
              _buildFoodImage(item.imageUrl, size: 55),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.foodName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textDark),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _macroTag('P', '${item.totalProtein.round()}g', const Color(0xFF5B8CFF)),
                        const SizedBox(width: 6),
                        _macroTag('C', '${item.totalCarbs.round()}g', const Color(0xFFFFAB2E)),
                        const SizedBox(width: 6),
                        _macroTag('F', '${item.totalFat.round()}g', const Color(0xFFFF6B6B)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${item.totalCalories.round()} kcal',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textDark)),
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
      ),
    );
  }

  // dntt_quantity คือ "จำนวนหน่วยเสิร์ฟ" (1 หน่วย = 100 กรัม สำหรับอาหารหน่วยกรัม) ตาม
  // ntt_serving_weight ฝั่ง backend ไม่ใช่กรัมจริง ต้องคูณ 100 ก่อนโชว์ให้ผู้ใช้เข้าใจถูก
  String _quantityLabel(DailyNutrition item) {
    if (item.unit == 'กรัม') return '${(item.quantity * 100).round()} กรัม';
    return '${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} ${item.unit}';
  }

  void _showFoodDetailSheet(DailyNutrition item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFoodImage(item.imageUrl, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.foodName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                      Text('${_quantityLabel(item)}'
                          '${item.time != null ? ' • ${item.time}' : ''}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditFoodSheet(item);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_rounded, size: 14, color: AppColors.primaryGreen),
                        SizedBox(width: 4),
                        Text('แก้ไข', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryGreen)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _foodDetailRow(Icons.local_fire_department_rounded, 'แคลอรี่', '${item.totalCalories.round()} kcal', Colors.orange),
            const SizedBox(height: 12),
            _foodDetailRow(Icons.egg_alt_rounded, 'โปรตีน', '${item.totalProtein.round()} กรัม', const Color(0xFF5B8CFF)),
            const SizedBox(height: 12),
            _foodDetailRow(Icons.rice_bowl_rounded, 'คาร์โบไฮเดรต', '${item.totalCarbs.round()} กรัม', const Color(0xFFFFAB2E)),
            const SizedBox(height: 12),
            _foodDetailRow(Icons.water_drop_rounded, 'ไขมัน', '${item.totalFat.round()} กรัม', const Color(0xFFFF6B6B)),
          ],
        ),
      ),
    );
  }

  static const _mealTypeLabels = {1: 'เช้า', 2: 'กลางวัน', 3: 'เย็น', 4: 'ว่าง'};

  Widget _editStepBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: AppColors.primaryGreen.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, color: AppColors.primaryGreen, size: 20),
      ),
    );
  }

  // ชีทแก้ไขรายการอาหารที่บันทึกแล้ว — ปรับจำนวน/มื้ออาหาร แล้วยิง PUT ไปคำนวณสารอาหารใหม่ฝั่ง backend
  Future<void> _showEditFoodSheet(DailyNutrition item) async {
    double qty = item.quantity;
    int mealType = item.mealType;
    bool saving = false;
    final isGram = item.unit == 'กรัม';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final qtyLabel = isGram
              ? '${(qty * 100).toStringAsFixed(0)} กรัม'
              : '${qty % 1 == 0 ? qty.toInt() : qty.toStringAsFixed(1)} แก้ว';

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('แก้ไข ${item.foodName}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
                  const SizedBox(height: 20),
                  const Text('จำนวน', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _editStepBtn(Icons.remove_rounded, () {
                        if (qty <= 0.5) return;
                        setSheet(() => qty -= 0.5);
                      }),
                      SizedBox(
                        width: 96,
                        child: Center(
                          child: Text(qtyLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        ),
                      ),
                      _editStepBtn(Icons.add_rounded, () => setSheet(() => qty += 0.5)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('มื้ออาหาร', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _mealTypeLabels.entries.map((e) {
                      final isSelected = mealType == e.key;
                      return GestureDetector(
                        onTap: () => setSheet(() => mealType = e.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primaryGreen : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(e.value,
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.black87 : AppColors.textMuted)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: saving ? null : () async {
                        setSheet(() => saving = true);
                        final result = await NutritionService.to.updateDailyNutrition(
                          id: item.id,
                          mealType: mealType,
                          quantity: qty,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (!mounted) return;
                        if (result['success'] == true) {
                          showAppAlert(context, 'แก้ไขรายการสำเร็จ', type: AppAlertType.success);
                          _loadNutrition();
                        } else {
                          showAppAlert(context, result['message'] ?? 'แก้ไขไม่สำเร็จ', type: AppAlertType.error);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        disabledBackgroundColor: AppColors.primaryGreen.withValues(alpha: 0.35),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Text(
                        saving ? 'กำลังบันทึก...' : 'บันทึกการแก้ไข',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _foodDetailRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ],
    );
  }
}

// การ์ดอาหาร "ป็อป" เข้ามาตอนโผล่ครั้งแรก (fade + scale ไล่หน่วงตาม index) — คีย์ผูกกับ item.id
// ทำให้การ์ดเดิมที่ยังอยู่ไม่เล่นแอนิเมชันซ้ำตอน rebuild เล่นเฉพาะการ์ดที่เพิ่งโผล่ใหม่จริง ๆ
// (เพิ่มอาหารใหม่ / สลับวัน / เปลี่ยนตัวกรองหมวด) ส่วนตอนลบใช้ swipe collapse ของ Dismissible เดิมอยู่แล้ว
class _AnimatedFoodCard extends StatefulWidget {
  final int index;
  final Widget child;
  const _AnimatedFoodCard({super.key, required this.index, required this.child});

  @override
  State<_AnimatedFoodCard> createState() => _AnimatedFoodCardState();
}

class _AnimatedFoodCardState extends State<_AnimatedFoodCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.88, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    // หน่วงไล่ตาม index (จำกัดที่ 6 ตัวแรก กันลิสต์ยาวรอนาน) ให้การ์ดทยอยป็อปขึ้นทีละใบแทนที่จะโผล่พร้อมกันหมด
    Future.delayed(Duration(milliseconds: 35 * widget.index.clamp(0, 6)), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(scale: _scale, alignment: Alignment.center, child: widget.child),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final double progress;
  _DonutPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 12;
    const strokeWidth = 16.0;

    final bgPaint = Paint()
      ..color = AppColors.primaryGreen.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..color = AppColors.primaryGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.progress != progress;
}
