// หน้า: Weight Training Detail (รายละเอียดท่าฝึก)
// ทำหน้าที่: แสดงข้อมูลท่าฝึก วิดีโอสาธิต กลุ่มกล้ามเนื้อที่ใช้ ประวัติการฝึก และกราฟพัฒนาการน้ำหนัก

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/history_range.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_date_picker_sheet.dart';
import '../../../core/widgets/cached_image.dart';
import '../../../core/widgets/sticky_filter_chip_bar.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../models/exercise_model.dart';
import '../../../models/workout_model.dart';
import '../../../services/exercise_service.dart';
import '../../../services/workout_service.dart';
import 'weight_training_exercise_view.dart';

class WeightTrainingDetailView extends StatefulWidget {
  final int exerciseId;
  final String exerciseName;
  final String imageUrl;
  final int suggestedSets;
  final String suggestedReps;
  final String description;
  final String technique;
  final String difficulty;
  final String videoUrl;
  final String loopVideoUrl;
  final bool isToday;
  final int exerciseType;
  final String muscleGroupName;
  final EquipmentType equipment;
  final int? wschId;    // wsch_id จริงจาก workout_schedules ถ้าท่านี้อยู่ในแผน
  final int? planId;    // ใช้เฉพาะตอนไม่มี wschId (ad-hoc path) คู่กับ isCustomPlan
  final bool isCustomPlan;

  const WeightTrainingDetailView({
    super.key,
    this.exerciseId = 0,
    this.exerciseName = 'Exercise',
    this.imageUrl = '',
    this.suggestedSets = 4,
    this.suggestedReps = '10',
    this.description = '',
    this.technique = '',
    this.difficulty = 'beginner',
    this.videoUrl = '',
    this.loopVideoUrl = '',
    this.isToday = true,
    this.exerciseType = 1,
    this.muscleGroupName = '',
    this.equipment = EquipmentType.bodyweight,
    this.wschId,
    this.planId,
    this.isCustomPlan = false,
  });

  @override
  State<WeightTrainingDetailView> createState() => _WeightTrainingDetailViewState();
}

class _WeightTrainingDetailViewState extends State<WeightTrainingDetailView>
    with SingleTickerProviderStateMixin {
  int _selectedTab = 0;
  late final TabController _tabController;

  List<ExerciseMuscle> _muscles = [];
  bool _isLoadingMuscles = true;

  final List<String> _tabLabels = ['ภาพรวม', 'เทคนิค', 'กล้ามเนื้อ', 'วิดีโอ'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedTab = _tabController.index);
      }
    });
    _loadMuscles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMuscles() async {
    if (widget.exerciseId == 0) {
      setState(() => _isLoadingMuscles = false);
      return;
    }
    final result = await ExerciseService.to.getExerciseMuscles(exerciseId: widget.exerciseId);
    if (!mounted) return;
    setState(() {
      _isLoadingMuscles = false;
      if (result['success'] == true) {
        _muscles = (result['data'] as List).cast<ExerciseMuscle>();
      }
    });
  }

  List<ExerciseMuscle> get _primaryMuscles => _muscles.where((m) => m.isPrimary).toList();
  List<ExerciseMuscle> get _secondaryMuscles => _muscles.where((m) => !m.isPrimary).toList();

  void _onTabTapped(int index) {
    HapticFeedback.lightImpact();
    setState(() => _selectedTab = index);
    _tabController.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: _buildBottomBar(),
      body: Stack(
        children: [
          NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                expandedHeight: 360,
                pinned: true,
                floating: false,
                toolbarHeight: 0,
                automaticallyImplyLeading: false,
                backgroundColor: Colors.white,
                elevation: 0,
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  background: _buildImageHeaderContent(screenSize),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(56),
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: _buildTabs(screenSize),
                  ),
                ),
              ),
            ],
            body: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF0F0F0),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                child: TabBarView(
                  controller: _tabController,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildOverviewContent(),
                    _buildTechniqueContent(),
                    _buildMuscleContent(),
                    _buildVideoContent(),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20, top: topPadding + 10,
            child: AppBackButton(),
          ),
        ],
      ),
    );
  }

  // ─── Header Image ──────────────────────────────────────────────────────────

  Widget _buildImageHeaderContent(Size size) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.imageUrl.isNotEmpty
            ? cachedImage(widget.imageUrl, fit: BoxFit.cover)
            : _imageFallback(),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.4, 1.0],
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 76,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF00F28A), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(
                    () {
                      final type = widget.exerciseType == 2 ? 'เฉพาะส่วน' : 'หลายกลุ่ม';
                      final group = widget.muscleGroupName.isNotEmpty ? ' • ${widget.muscleGroupName}' : '';
                      return '$type$group';
                    }(),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.exerciseName,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28, height: 1.1, color: Colors.white),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _imageFallback() => Container(
    color: Colors.grey.shade900,
    child: const Center(child: Icon(Icons.fitness_center, size: 80, color: Colors.white24)),
  );

  // ─── Tab Bar ───────────────────────────────────────────────────────────────

  Widget _buildTabs(Size size) {
    final double totalWidth = size.width - 40;
    final double tabWidth = totalWidth / 4;
    const double lineWidth = 80.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(_tabLabels.length, (i) {
              final isActive = _selectedTab == i;
              return GestureDetector(
                onTap: () => _onTabTapped(i),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: tabWidth,
                  child: Center(
                    child: Text(_tabLabels[i],
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                          color: isActive ? Colors.black : const Color(0xFFA0A1A5),
                        )),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 3,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(height: 1, color: const Color(0xFFEEEEEE)),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  left: _selectedTab * tabWidth + (tabWidth - lineWidth) / 2,
                  top: -1,
                  child: Container(
                    width: lineWidth, height: 3,
                    decoration: BoxDecoration(color: const Color(0xFF2BEE8C), borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Tab 0: Overview ──────────────────────────────────────────────────────

  Widget _buildOverviewContent() {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // FIX: แก้ไขรูปแบบของ Sets และ Reps ให้ตรงเป๊ะ
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${widget.suggestedSets} เซ็ท',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 26, color: Colors.black)),
              const SizedBox(width: 20),
              Column(children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFA0A1A5), shape: BoxShape.circle)),
                const SizedBox(height: 6),
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFA0A1A5), shape: BoxShape.circle)),
              ]),
              const SizedBox(width: 20),
              Text('${widget.suggestedReps} ครั้ง',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 26, color: Colors.black)),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFD0D0D2)),
          const SizedBox(height: 20),

          // กล้ามเนื้อที่ใช้
          const Text('กล้ามเนื้อที่ใช้', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: Colors.black)),
          const SizedBox(height: 12),
          if (_isLoadingMuscles)
            const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 12), child: CircularProgressIndicator(color: AppColors.primaryGreen)))
          else if (_muscles.isNotEmpty)
            Wrap(
              spacing: 16, runSpacing: 8,
              children: _muscles.map((m) => _bulletChip(
                m.muscleName,
                m.isPrimary ? const Color(0xFF00F28A) : Colors.grey.shade400,
              )).toList(),
            )
          else
            Text('ยังไม่มีข้อมูลกล้ามเนื้อ', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
          const SizedBox(height: 20),

          // คำอธิบาย
          const Text('คำอธิบาย', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: Colors.black)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF00F28A)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.description.isNotEmpty ? widget.description : 'ยังไม่มีข้อมูลคำอธิบาย',
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: Color(0xFF686868), height: 1.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, color: Color(0xFFD0D0D2)),
          const SizedBox(height: 24),

          // Link to video tab
          // FIX: ออกแบบปุ่มวิดีโอให้ตรงกับรูปเป๊ะๆ
          GestureDetector(
            onTap: () => _onTabTapped(3),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: const Center(child: Icon(Icons.play_arrow_rounded, color: Color(0xFF00F28A), size: 28)),
                ),
                const SizedBox(width: 14),
                const Text('วิดีโอสอนท่าฝึก', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: Colors.black)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward, size: 20, color: Colors.black),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Tab 1: Technique ────────────────────────────────────────────────────

  Widget _buildTechniqueContent() {
    final lines = widget.technique.isNotEmpty
        ? widget.technique
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : <String>[];

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('วิธีทำท่าที่ถูกต้อง', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20, color: Colors.black)),
          const SizedBox(height: 16),
          if (lines.isNotEmpty)
            ...lines.asMap().entries.map((e) => _buildTechniqueItem(e.key + 1, e.value))
          else
            Text('ยังไม่มีข้อมูลเทคนิค', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildTechniqueItem(int step, String line) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            margin: const EdgeInsets.only(top: 1, right: 14),
            decoration: const BoxDecoration(color: Color(0xFF00F28A), shape: BoxShape.circle),
            child: Center(
              child: Text('$step', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.black)),
            ),
          ),
          Expanded(
            child: Text(
              line,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15, color: Color(0xFF686868), height: 1.55),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Tab 2: Muscles ───────────────────────────────────────────────────────

  Widget _buildMuscleContent() {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoadingMuscles)
            const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 40), child: CircularProgressIndicator(color: AppColors.primaryGreen)))
          else if (_muscles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('ยังไม่มีข้อมูลกล้ามเนื้อ', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            )
          else ...[
            // กล้ามเนื้อหลัก
            if (_primaryMuscles.isNotEmpty) ...[
              const Text('กล้ามเนื้อหลัก', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16, runSpacing: 8,
                children: _primaryMuscles.map((m) => _bulletChip(m.muscleName, const Color(0xFF00F28A))).toList(),
              ),
              const SizedBox(height: 20),
            ],
            // กล้ามเนื้อรอง
            if (_secondaryMuscles.isNotEmpty) ...[
              const Text('กล้ามเนื้อรอง', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16, runSpacing: 8,
                children: _secondaryMuscles.map((m) => _bulletChip(m.muscleName, const Color(0xFFA0A1A5))).toList(),
              ),
              const SizedBox(height: 20),
            ],
          ],
        ],
      ),
    );
  }

  // ─── Tab 3: Video ─────────────────────────────────────────────────────────

  Widget _buildVideoContent() {
    final videoUrl = widget.videoUrl;
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('วิดีโอสอนท่าฝึก',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20, color: Colors.black)),
          const SizedBox(height: 16),
          if (videoUrl.isNotEmpty)
            _VideoPlayerWithThumbnail(
              videoUrl: videoUrl,
              exerciseName: widget.exerciseName,
            )
          else
            Container(
              width: double.infinity,
              height: 160,
              decoration: BoxDecoration(
                  color: Colors.grey.shade200, borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_off_rounded, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('ยังไม่มีวิดีโอสอนท่า',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ─── Shared Widgets ───────────────────────────────────────────────────────

  Widget _bulletChip(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: Color(0xFF686868))),
      ],
    );
  }

  // ─── Bottom Bar ───────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    final canTrain = widget.isToday;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => _showHistorySheet(),
                child: Text('ประวัติการฝึก',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: canTrain
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WeightTrainingExerciseView(
                          exerciseId: widget.exerciseId,
                          exerciseName: widget.exerciseName,
                          imageUrl: widget.imageUrl,
                          loopVideoUrl: widget.loopVideoUrl,
                          exerciseType: widget.exerciseType,
                          muscleGroupName: widget.muscleGroupName,
                          wschId: widget.wschId,
                          planId: widget.planId,
                          isCustomPlan: widget.isCustomPlan,
                        ),
                      ),
                    )
                : () => showAppAlert(context, 'สามารถบันทึกการฝึกได้เฉพาะวันนี้เท่านั้น', type: AppAlertType.info),
            child: Container(
              width: double.infinity, height: 56,
              decoration: BoxDecoration(
                color: canTrain ? const Color(0xFF2BEE8C) : const Color(0xFFD0D0D0),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  canTrain ? 'เริ่มต้นการฝึก' : 'ดูได้เฉพาะวันนี้เท่านั้น',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 18,
                    color: canTrain ? Colors.black : Colors.white70,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── History Bottom Sheet ─────────────────────────────────────────────────

  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ExerciseHistorySheet(
        exerciseId: widget.exerciseId,
        exerciseName: widget.exerciseName,
        muscleGroupName: widget.muscleGroupName,
        exerciseType: widget.exerciseType,
        equipment: widget.equipment,
        difficulty: widget.difficulty,
      ),
    );
  }
}

// ─── Exercise History Bottom Sheet ───────────────────────────────────────────

class _ExerciseHistorySheet extends StatefulWidget {
  final int exerciseId;
  final String exerciseName;
  final String muscleGroupName;
  final int exerciseType; // 1=หลายกลุ่ม, 2=เฉพาะส่วน
  final EquipmentType equipment;
  final String difficulty;

  const _ExerciseHistorySheet({
    required this.exerciseId,
    required this.exerciseName,
    this.muscleGroupName = '',
    this.exerciseType = 1,
    this.equipment = EquipmentType.bodyweight,
    this.difficulty = '',
  });

  @override
  State<_ExerciseHistorySheet> createState() => _ExerciseHistorySheetState();
}

enum _ChartMetric { oneRM, volume }

class _ExerciseHistorySheetState extends State<_ExerciseHistorySheet> {
  List<WorkoutResult> _history = [];
  bool _loading = true;

  HistoryRangeOption _range = HistoryRangeOption.thirtyDays;
  DateTimeRange? _customRange;
  _ChartMetric _metric = _ChartMetric.oneRM;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await WorkoutService.to.getExerciseHistory(widget.exerciseId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _history = (result['data'] as List).cast<WorkoutResult>();
      }
    });
  }

  Future<void> _pickCustomRange() async {
    final start = await showAppCalendarPicker(context,
        initialDate: DateTime.now(), lastDate: DateTime.now(), title: 'เลือกวันเริ่มต้น');
    if (start == null || !mounted) return;
    final end = await showAppCalendarPicker(context,
        initialDate: DateTime.now(), firstDate: start, lastDate: DateTime.now(), title: 'เลือกวันสิ้นสุด');
    if (end == null || !mounted) return;
    setState(() {
      _range = HistoryRangeOption.custom;
      _customRange = DateTimeRange(start: start, end: end);
    });
  }

  // ── computed (สโคปตามแถบกรองช่วงเวลาที่เลือกด้านบนเสมอ) ─────────────────────
  List<WorkoutResult> get _filtered {
    return _history.where((r) {
      final d = parseHistoryDate(r.date);
      return d != null && isDateWithinHistoryRange(d, _range, _customRange);
    }).toList();
  }

  Map<String, List<WorkoutResult>> get _grouped {
    final map = <String, List<WorkoutResult>>{};
    for (final r in _filtered) {
      map.putIfAbsent(r.date.split('T').first, () => []).add(r);
    }
    return map;
  }

  // เรียงใหม่กันเหนียว แม้ backend จะคืนมาเรียง wtrs_date desc อยู่แล้วก็ตาม
  List<String> get _dates => _grouped.keys.toList()..sort((a, b) => b.compareTo(a));

  double _sessionMax(String date) {
    final sets = _grouped[date] ?? [];
    if (sets.isEmpty) return 0;
    return sets.map((s) => s.weight).reduce(math.max);
  }

  double _sessionVolume(String date) =>
      (_grouped[date] ?? []).fold(0.0, (sum, s) => sum + s.weight * s.reps);

  double _sessionCalories(String date) =>
      (_grouped[date] ?? []).fold(0.0, (sum, s) => sum + s.calories);

  double _session1RM(String date) {
    final valid = (_grouped[date] ?? []).where((s) => s.weight > 0 && s.reps > 0);
    if (valid.isEmpty) return 0;
    return valid.map((s) => s.weight * (1 + s.reps / 30.0)).reduce(math.max);
  }

  double get _overallMax {
    if (_filtered.isEmpty) return 0;
    return _filtered.map((r) => r.weight).reduce(math.max);
  }

  // 1RM = weight × (1 + reps/30) — ใช้ค่าสูงสุดจากประวัติในช่วงที่กรอง
  double get _best1RM {
    if (_filtered.isEmpty) return 0;
    return _filtered
        .where((r) => r.weight > 0 && r.reps > 0)
        .map((r) => r.weight * (1 + r.reps / 30.0))
        .fold(0.0, math.max);
  }

  double get _maxDailyVolume =>
      _dates.isEmpty ? 0 : _dates.map(_sessionVolume).reduce(math.max);

  double get _totalCalories => _filtered.fold(0.0, (sum, r) => sum + r.calories);

  double get _latestMax => _dates.isEmpty ? 0 : _sessionMax(_dates.first);

  String get _latestDateLabel => _dates.isEmpty ? '—' : _formatDate(_dates.first);

  // น้ำหนักสูงสุดครั้งล่าสุด − ครั้งก่อนหน้า (null ถ้า < 2 ครั้ง)
  double? get _trend =>
      _dates.length < 2 ? null : _latestMax - _sessionMax(_dates[1]);

  String _intensityLabel(int? level) {
    switch (level) {
      case 1: return 'เบา';
      case 2: return 'กลาง';
      case 3: return 'หนัก';
      default: return '-';
    }
  }

  // wet_difficulty ใน DB เป็น tinyint 1=ง่าย/2=กลาง/3=ยาก แต่ Exercise.difficulty
  // เก็บเป็น String มาจากทั้ง 2 รูปแบบ (เลขหรือ 'beginner' fallback) — กันไว้ทั้งคู่
  String _difficultyLabel(String raw) {
    switch (raw) {
      case '1': case 'beginner': return 'ง่าย';
      case '2': case 'intermediate': return 'กลาง';
      case '3': case 'advanced': return 'ยาก';
      default: return raw.isEmpty ? '-' : raw;
    }
  }

  String _formatDate(String raw) {
    try {
      final p = raw.split('T').first.split('-');
      const months = ['', 'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
                      'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
      return '${int.parse(p[2])} ${months[int.parse(p[1])]} ${int.parse(p[0]) + 543}';
    } catch (_) { return raw; }
  }

  String _shortDate(String raw) {
    try {
      final p = raw.split('T').first.split('-');
      return '${int.parse(p[2])}/${int.parse(p[1])}';
    } catch (_) { return raw; }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final dates = _dates;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(
              children: [
                const Icon(Icons.bar_chart_rounded, size: 20, color: Color(0xFF00C978)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.exerciseName,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 16, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
          if (widget.muscleGroupName.isNotEmpty || widget.difficulty.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Wrap(
                spacing: 8, runSpacing: 6,
                children: [
                  if (widget.muscleGroupName.isNotEmpty)
                    _infoChip(
                      widget.exerciseType == 2
                          ? 'เฉพาะส่วน • ${widget.muscleGroupName}'
                          : 'หลายกลุ่ม • ${widget.muscleGroupName}',
                      Icons.accessibility_new_rounded,
                    ),
                  _infoChip(widget.equipment.label, Icons.fitness_center_rounded),
                  if (widget.difficulty.isNotEmpty)
                    _infoChip(_difficultyLabel(widget.difficulty), Icons.speed_rounded),
                ],
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: StickyFilterChipBar<HistoryRangeOption>(
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              items: HistoryRangeOption.values
                  .map((o) => FilterChipItem(id: o, label: historyRangeLabels[o]!))
                  .toList(),
              selectedId: _range,
              onSelected: (o) {
                if (o == HistoryRangeOption.custom) {
                  _pickCustomRange();
                } else {
                  setState(() => _range = o);
                }
              },
            ),
          ),
          Flexible(
            child: _loading
                ? const Center(child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: Color(0xFF00C978)),
                  ))
                : _history.isEmpty
                    ? _emptyState(Icons.fitness_center, 'ยังไม่มีประวัติการฝึกท่านี้', 'เริ่มฝึกเพื่อเก็บสถิติของคุณ')
                    : dates.isEmpty
                        ? _emptyState(Icons.event_busy_rounded, 'ไม่มีข้อมูลในช่วงเวลานี้', 'ลองเลือกช่วงเวลาอื่น')
                        : SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 36),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildStats(dates),
                                if (dates.length >= 2) _buildChart(dates),
                                _buildHistoryList(dates, grouped),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: Colors.grey.shade600),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
    ]),
  );

  Widget _emptyState(IconData icon, String title, String subtitle) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(title, style: TextStyle(color: Colors.grey.shade500, fontSize: 15, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
      ]),
    ),
  );

  // ── Stats section (4 cards) ───────────────────────────────────────────────
  Widget _buildStats(List<String> dates) {
    final trend = _trend;
    final trendColor = trend == null
        ? Colors.grey.shade500
        : trend > 0 ? Colors.green.shade600
        : trend < 0 ? Colors.red.shade500
        : Colors.grey.shade500;
    final trendIcon = trend == null || trend == 0
        ? Icons.remove_rounded
        : trend > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded;
    final trendText = trend == null
        ? 'ยังไม่มีข้อมูล'
        : trend == 0 ? 'เท่าเดิม'
        : '${trend > 0 ? '+' : ''}${trend.toStringAsFixed(1)} กก.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(children: [
        Row(children: [
          _statCard(
            label: 'ฝึกทั้งหมด',
            value: '${dates.length}',
            unit: 'ครั้ง',
            icon: Icons.calendar_today_rounded,
            iconColor: const Color(0xFF00C978),
          ),
          const SizedBox(width: 10),
          _statCard(
            label: 'ล่าสุดเมื่อ',
            value: _latestDateLabel,
            unit: '',
            icon: Icons.event_available_rounded,
            iconColor: Colors.blue.shade400,
            isDate: true,
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _statCard(
            label: 'น้ำหนักสูงสุด (PR)',
            value: _overallMax > 0 ? _overallMax.toStringAsFixed(1) : '—',
            unit: 'กก.',
            icon: Icons.emoji_events_rounded,
            iconColor: Colors.amber.shade600,
          ),
          const SizedBox(width: 10),
          _statCard(
            label: 'ปริมาตรการฝึกสูงสุด/วัน',
            value: _maxDailyVolume > 0 ? _maxDailyVolume.toStringAsFixed(0) : '—',
            unit: 'กก.',
            icon: Icons.bar_chart_rounded,
            iconColor: Colors.deepPurple.shade300,
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _statCard(
            label: 'แคลอรี่สะสม',
            value: _totalCalories > 0 ? _totalCalories.toStringAsFixed(0) : '—',
            unit: 'kcal',
            icon: Icons.local_fire_department_rounded,
            iconColor: Colors.orange.shade400,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(trendIcon, size: 14, color: trendColor),
                  const SizedBox(width: 6),
                  Text('เทียบครั้งก่อน',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500)),
                ]),
                const SizedBox(height: 6),
                Text(trendText,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: trendColor)),
              ]),
            ),
          ),
        ]),
        if (_best1RM > 0) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF00C978).withOpacity(0.12), const Color(0xFF00C978).withOpacity(0.04)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF00C978).withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.bolt_rounded, color: Color(0xFF00C978), size: 22),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('1RM โดยประมาณ (สูงสุด)',
                    style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('${_best1RM.toStringAsFixed(1)} กก.',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF00C978))),
              ]),
              const Spacer(),
              const Text('weight × (1 + reps/30)',
                  style: TextStyle(fontSize: 10, color: Colors.grey)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required String unit,
    required IconData icon,
    required Color iconColor,
    bool isDate = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 13, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500)),
            ),
          ]),
          const SizedBox(height: 6),
          isDate
              ? Text(value,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                      color: Colors.black87, fontFamily: 'Inter'))
              : RichText(
                  text: TextSpan(children: [
                    TextSpan(text: value,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                            color: Colors.black87, fontFamily: 'Inter')),
                    if (value != '—')
                      TextSpan(text: ' $unit',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500,
                              fontWeight: FontWeight.w500, fontFamily: 'Inter')),
                  ]),
                ),
        ]),
      ),
    );
  }

  // ── กราฟแนวโน้ม: สลับแท็บ 1RM โดยประมาณ ↔ ปริมาตรการฝึกรวม ───────────────────
  Widget _buildChart(List<String> allDatesDesc) {
    final chartDates = allDatesDesc.reversed.toList(); // oldest → newest
    const green = Color(0xFF00C978);
    final values = chartDates
        .map((d) => _metric == _ChartMetric.oneRM ? _session1RM(d) : _sessionVolume(d))
        .toList();
    final maxV = values.isEmpty ? 0.0 : values.reduce(math.max);
    final spots = List.generate(values.length, (i) => FlSpot(i.toDouble(), values[i]));
    final interval = chartDates.length <= 6 ? 1.0 : (chartDates.length / 6).ceilToDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.show_chart_rounded, size: 14, color: green),
            const SizedBox(width: 6),
            Text('ความก้าวหน้า', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
            const Spacer(),
            _metricToggle(),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: maxV <= 0
                ? Center(child: Text('ยังไม่มีข้อมูลสำหรับกราฟนี้', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)))
                : LineChart(
                    LineChartData(
                      minY: 0,
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: green,
                          barWidth: 3,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(show: true, color: green.withValues(alpha: 0.1)),
                        ),
                      ],
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            interval: interval,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= chartDates.length) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(_shortDate(chartDates[i]),
                                    style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                              );
                            },
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      lineTouchData: const LineTouchData(enabled: true),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _metricToggle() {
    const green = Color(0xFF00C978);
    Widget seg(String label, _ChartMetric m) {
      final active = _metric == m;
      return GestureDetector(
        onTap: () => setState(() => _metric = m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: active ? green : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700,
                  color: active ? Colors.black : Colors.grey.shade500)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(22)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('1RM', _ChartMetric.oneRM),
        seg('ปริมาตร', _ChartMetric.volume),
      ]),
    );
  }

  // ── History list ──────────────────────────────────────────────────────────
  Widget _buildHistoryList(List<String> dates, Map<String, List<WorkoutResult>> grouped) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            const Icon(Icons.history_rounded, size: 14, color: Colors.black54),
            const SizedBox(width: 6),
            Text('ประวัติทั้งหมด',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
            const Spacer(),
            Text('${dates.length} ครั้ง',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ]),
        ),
        ...dates.asMap().entries.map((entry) {
          final i = entry.key;
          final date = entry.value;
          final sets = grouped[date]!;
          final isLatest = i == 0;
          final maxW = sets.map((s) => s.weight).reduce(math.max);
          final isPR = _overallMax > 0 && maxW >= _overallMax;
          final volume = _sessionVolume(date);
          final calories = _sessionCalories(date);
          final intensity = _intensityLabel(sets.first.intensityLevel);
          const green = Color(0xFF00C978);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isLatest ? green.withValues(alpha: 0.05) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isLatest ? green.withValues(alpha: 0.25) : Colors.grey.shade200,
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(_formatDate(date),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                        color: isLatest ? green : Colors.black87)),
                if (isLatest) ...[
                  const SizedBox(width: 6),
                  _historyBadge('ล่าสุด', green),
                ],
                if (isPR) ...[
                  const SizedBox(width: 6),
                  _historyBadge('สถิติใหม่ (PR)', Colors.amber.shade700),
                ],
              ]),
              const SizedBox(height: 4),
              Text(
                '${sets.length} เซ็ต · สูงสุด ${maxW.toStringAsFixed(0)} กก. · ปริมาตร ${volume.toStringAsFixed(0)} กก. · '
                '${calories.toStringAsFixed(0)} kcal · ระดับ$intensity',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 8),
              ...sets.map((s) {
                final oneRM = (s.weight > 0 && s.reps > 0) ? s.weight * (1 + s.reps / 30.0) : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: isLatest ? green.withValues(alpha: 0.12) : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Center(
                        child: Text('${s.setNo}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                color: isLatest ? green : Colors.black54)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('${s.weight} กก.  ×  ${s.reps} ครั้ง',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                    if (oneRM > 0)
                      Text('1RM ≈ ${oneRM.toStringAsFixed(1)} กก.',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ]),
                );
              }),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _historyBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
  );
}

// ─── Thumbnail card → กดแล้วเปิดเต็มจอ ──────────────────────────────────────

class _VideoPlayerWithThumbnail extends StatefulWidget {
  final String videoUrl;
  final String exerciseName;

  const _VideoPlayerWithThumbnail({
    required this.videoUrl,
    required this.exerciseName,
  });

  @override
  State<_VideoPlayerWithThumbnail> createState() => _VideoPlayerWithThumbnailState();
}

class _VideoPlayerWithThumbnailState extends State<_VideoPlayerWithThumbnail> {
  late VideoPlayerController _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) async {
        await _ctrl.seekTo(Duration.zero);
        if (mounted) setState(() => _ready = true);
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _FullScreenVideoPage(
            videoUrl: widget.videoUrl,
            exerciseName: widget.exerciseName,
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: _ready ? _ctrl.value.aspectRatio : 9 / 16,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_ready)
                VideoPlayer(_ctrl)
              else
                Container(color: Colors.grey.shade900,
                    child: const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2))),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 46),
                ),
              ),
              Positioned(
                left: 16, right: 16, bottom: 14,
                child: Text(widget.exerciseName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black54)]),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Full-Screen Video Page (MP4 via video_player + chewie) ──────────────────

class _FullScreenVideoPage extends StatefulWidget {
  final String videoUrl;
  final String exerciseName;

  const _FullScreenVideoPage({required this.videoUrl, required this.exerciseName});

  @override
  State<_FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<_FullScreenVideoPage> {
  late final VideoPlayerController _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (!mounted) return;
        _chewieController = ChewieController(
          videoPlayerController: _videoController,
          autoPlay: true,
          looping: false,
          aspectRatio: _videoController.value.aspectRatio,
          allowFullScreen: false,
          allowMuting: true,
          showControlsOnInitialize: true,
        );
        setState(() {});
      });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _chewieController?.dispose();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _chewieController != null
              ? Center(child: Chewie(controller: _chewieController!))
              : const Center(child: CircularProgressIndicator(color: Colors.white)),
          Positioned(
            left: 12, top: topPadding + 8,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}