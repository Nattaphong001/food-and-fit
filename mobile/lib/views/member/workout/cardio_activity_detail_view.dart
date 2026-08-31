// หน้า: Cardio Activity Detail (รายละเอียดกิจกรรมคาร์ดิโอ)
// ทำหน้าที่: แสดงข้อมูลกิจกรรมคาร์ดิโอ สถิติ ประวัติการทำ และกราฟพัฒนาการ ก่อนเริ่มออกกำลังกาย

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/utils/history_range.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_date_picker_sheet.dart';
import '../../../core/widgets/cached_image.dart';
import '../../../core/widgets/sticky_filter_chip_bar.dart';
import '../../../models/exercise_model.dart';
import '../../../models/workout_model.dart';
import '../../../services/exercise_service.dart';
import '../../../services/workout_service.dart';
import 'cardio_activity_exercise_view.dart';

class CardioActivityDetailView extends StatefulWidget {
  final CardioType activity;

  const CardioActivityDetailView({
    super.key,
    required this.activity,
  });

  @override
  State<CardioActivityDetailView> createState() => _CardioActivityDetailViewState();
}

class _CardioActivityDetailViewState extends State<CardioActivityDetailView>
    with SingleTickerProviderStateMixin {
  int _selectedTab = 0;
  late final TabController _tabController;
  final List<String> _tabLabels = ['ภาพรวม', 'เทคนิค', 'วิดีโอ'];

  // ชื่อประเภทกิจกรรม (cdc_name) — CardioType มีแค่ categoryId ต้อง join เอาชื่อเอง
  // ใช้โชว์ใน header ของ history sheet (สเปกข้อ B "Header เพิ่มเติม: ประเภทกิจกรรม")
  String _categoryName = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedTab = _tabController.index);
      }
    });
    _loadCategoryName();
  }

  Future<void> _loadCategoryName() async {
    final result = await ExerciseService.to.getCardioCategories();
    if (!mounted || result['success'] != true) return;
    final categories = (result['data'] as List).cast<CardioCategory>();
    final match = categories.where((c) => c.categoryId == widget.activity.categoryId);
    if (match.isNotEmpty) setState(() => _categoryName = match.first.categoryName);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
    final imageUrl = widget.activity.imageUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        (imageUrl != null && imageUrl.isNotEmpty)
            ? cachedImage(imageUrl, fit: BoxFit.cover)
            : Container(
                color: Colors.grey.shade900,
                child: const Center(child: Icon(Icons.directions_run, size: 80, color: Colors.white24)),
              ),
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
                    'คาร์ดิโอ · MET ${widget.activity.mets.toStringAsFixed(1)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.activity.typeName,
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

  // ─── Tab Bar ───────────────────────────────────────────────────────────────

  Widget _buildTabs(Size size) {
    final double tabWidth = (size.width - 40) / _tabLabels.length;
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
          Stack(
            children: [
              Container(height: 1, color: const Color(0xFFEEEEEE)),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                left: _selectedTab * tabWidth + (tabWidth - lineWidth) / 2,
                child: Container(width: lineWidth, height: 3, color: const Color(0xFF2BEE8C)),
              ),
            ],
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
          Center(
            child: Text(
              'MET: ${widget.activity.mets.toStringAsFixed(1)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 26, color: Colors.black),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFD0D0D2)),
          const SizedBox(height: 20),
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
                    widget.activity.description.isNotEmpty ? widget.activity.description : 'ยังไม่มีข้อมูลคำอธิบาย',
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: Color(0xFF686868), height: 1.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, color: Color(0xFFD0D0D2)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => _onTabTapped(2),
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
    final lines = widget.activity.technique.isNotEmpty
        ? widget.activity.technique.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
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
            child: Text(line, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15, color: Color(0xFF686868), height: 1.55)),
          ),
        ],
      ),
    );
  }

  // ─── Tab 2: Video ─────────────────────────────────────────────────────────

  Widget _buildVideoContent() {
    final videoUrl = widget.activity.videoUrl ?? '';
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('วิดีโอสอนท่าฝึก', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20, color: Colors.black)),
          const SizedBox(height: 16),
          if (videoUrl.isNotEmpty)
            _VideoPlayerWithThumbnail(
              videoUrl: videoUrl,
              exerciseName: widget.activity.typeName,
            )
          else
            Container(
              width: double.infinity, height: 160,
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_off_rounded, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('ยังไม่มีวิดีโอสอนท่า', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ─── History Sheet ─────────────────────────────────────────────────────────

  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CardioHistorySheet(
        cardioTypeId: widget.activity.typeId,
        activityName: widget.activity.typeName,
        categoryName: _categoryName,
        mets: widget.activity.mets,
        hasDistance: widget.activity.hasDistance,
      ),
    );
  }

  // ─── Bottom Bar ───────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
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
          GestureDetector(
            onTap: _showHistorySheet,
            child: Text('ประวัติการฝึก',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CardioActivityExerciseView(
                  cardioTypeId: widget.activity.typeId,
                  activityName: widget.activity.typeName,
                  exerciseName: widget.activity.typeName,
                  imageUrl: widget.activity.imageUrl ?? '',
                  loopVideoUrl: widget.activity.loopVideoUrl ?? '',
                  mets: widget.activity.mets,
                  hasDistance: widget.activity.hasDistance,
                ),
              ),
            ),
            child: Container(
              width: double.infinity, height: 56,
              decoration: BoxDecoration(color: const Color(0xFF2BEE8C), borderRadius: BorderRadius.circular(16)),
              child: const Center(
                child: Text('เริ่มต้นการฝึก', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 18)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Cardio History Bottom Sheet ─────────────────────────────────────────────

class _CardioHistorySheet extends StatefulWidget {
  final int cardioTypeId;
  final String activityName;
  final String categoryName;
  final double mets;
  final bool hasDistance;

  const _CardioHistorySheet({
    required this.cardioTypeId,
    required this.activityName,
    this.categoryName = '',
    this.mets = 0,
    this.hasDistance = false,
  });

  @override
  State<_CardioHistorySheet> createState() => _CardioHistorySheetState();
}

enum _CardioChartMetric { calories, duration, distance }

class _CardioHistorySheetState extends State<_CardioHistorySheet> {
  List<CardioResult> _history = [];
  bool _loading = true;

  HistoryRangeOption _range = HistoryRangeOption.thirtyDays;
  DateTimeRange? _customRange;
  _CardioChartMetric _metric = _CardioChartMetric.calories;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await WorkoutService.to.getCardioResults();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        final all = (result['data'] as List).cast<CardioResult>();
        _history = all.where((r) => r.cardioTypeId == widget.cardioTypeId).toList();
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
  List<CardioResult> get _filtered {
    return _history.where((r) {
      final d = parseHistoryDate(r.date);
      return d != null && isDateWithinHistoryRange(d, _range, _customRange);
    }).toList();
  }

  Map<String, List<CardioResult>> get _grouped {
    final map = <String, List<CardioResult>>{};
    for (final r in _filtered) {
      final key = r.date.split('T').first;
      map.putIfAbsent(key, () => []).add(r);
    }
    return map;
  }

  double _sessionDuration(String date) => (_grouped[date] ?? []).fold(0.0, (sum, r) => sum + r.duration);
  double _sessionDistance(String date) => (_grouped[date] ?? []).fold(0.0, (sum, r) => sum + r.distance);
  double _sessionCalories(String date) => (_grouped[date] ?? []).fold(0.0, (sum, r) => sum + r.caloriesBurned);

  double get _totalDuration => _filtered.fold(0.0, (sum, r) => sum + r.duration);
  double get _totalDistance => _filtered.fold(0.0, (sum, r) => sum + r.distance);
  double get _totalCalories => _filtered.fold(0.0, (sum, r) => sum + r.caloriesBurned);
  double get _maxDuration => _filtered.isEmpty ? 0 : _filtered.map((r) => r.duration).reduce(math.max);
  double get _maxDistance => _filtered.isEmpty ? 0 : _filtered.map((r) => r.distance).reduce(math.max);

  String get _latestDateLabel {
    final dates = _grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return dates.isEmpty ? '—' : _formatDate(dates.first);
  }

  String _formatDate(String raw) {
    try {
      final p = raw.split('T').first.split('-');
      final year = int.parse(p[0]);
      final month = int.parse(p[1]);
      final day = int.parse(p[2]);
      const months = ['', 'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
                      'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
      return '$day ${months[month]} ${year + 543}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    // เรียงตามวันที่จริง (ไม่ใช่ insertion order จาก backend ที่เรียงตาม id) กัน
    // badge "ล่าสุด" ตกที่วันผิดถ้ามี entry ถูก back-date เข้ามาทีหลัง
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, size: 20, color: Color(0xFF00C978)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ประวัติการฝึก — ${widget.activityName}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          if (widget.categoryName.isNotEmpty || widget.mets > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
              child: Wrap(
                spacing: 8, runSpacing: 6,
                children: [
                  if (widget.categoryName.isNotEmpty)
                    _infoChip(widget.categoryName, Icons.category_rounded),
                  if (widget.mets > 0)
                    _infoChip('MET ${widget.mets.toStringAsFixed(1)}', Icons.speed_rounded),
                ],
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
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
          // Content
          Flexible(
            child: _loading
                ? const Center(child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: Color(0xFF00C978)),
                  ))
                : _history.isEmpty
                    ? _emptyState(Icons.directions_run, 'ยังไม่มีประวัติการฝึกท่านี้', 'เริ่มฝึกเพื่อเก็บสถิติของคุณ')
                    : dates.isEmpty
                        ? _emptyState(Icons.event_busy_rounded, 'ไม่มีข้อมูลในช่วงเวลานี้', 'ลองเลือกช่วงเวลาอื่น')
                        : SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildStats(dates),
                                if (dates.length >= 2) _buildChart(dates),
                                Row(children: [
                                  const Icon(Icons.history_rounded, size: 14, color: Colors.black54),
                                  const SizedBox(width: 6),
                                  Text('ประวัติทั้งหมด',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                                  const Spacer(),
                                  Text('${dates.length} ครั้ง',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                                ]),
                                const SizedBox(height: 10),
                                ...dates.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final date = entry.value;
                                  final dayEntries = grouped[date]!;
                                  final isLatest = i == 0;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(_formatDate(date),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                  color: isLatest ? const Color(0xFF00C978) : Colors.black87,
                                                )),
                                            if (isLatest) ...[
                                              const SizedBox(width: 8),
                                              _historyBadge('ล่าสุด', const Color(0xFF00C978)),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        ...dayEntries.map((r) {
                                          final pace = (widget.hasDistance && r.distance > 0)
                                              ? r.duration / r.distance
                                              : 0.0;
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 6),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                      decoration: BoxDecoration(
                                                        color: Colors.grey.shade100,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          const Icon(Icons.timer_outlined, size: 14, color: Colors.black54),
                                                          const SizedBox(width: 4),
                                                          Text('${r.duration.toInt()} นาที',
                                                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.local_fire_department_rounded, size: 14, color: Color(0xFFFF9800)),
                                                        const SizedBox(width: 4),
                                                        Text('${r.caloriesBurned.round()} cal',
                                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54)),
                                                      ],
                                                    ),
                                                    if (r.distance > 0) ...[
                                                      const SizedBox(width: 10),
                                                      Row(
                                                        children: [
                                                          const Icon(Icons.straighten_rounded, size: 14, color: Color(0xFF64B5F6)),
                                                          const SizedBox(width: 4),
                                                          Text('${r.distance} กม.',
                                                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54)),
                                                        ],
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                if (pace > 0)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 3, left: 2),
                                                    child: Text(
                                                      'Pace เฉลี่ย ${_formatPace(pace)} นาที/กม.',
                                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  );
                                }),
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

  Widget _historyBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
  );

  Widget _emptyState(IconData icon, String title, String subtitle) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 44, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(title, style: TextStyle(color: Colors.grey.shade500, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
      ]),
    ),
  );

  // Pace = cdors_duration(นาที) / cdors_distance(กม.) — คำนวณหน้าจอเท่านั้น ไม่บันทึก DB
  String _formatPace(double minutesPerKm) {
    final m = minutesPerKm.floor();
    final s = ((minutesPerKm - m) * 60).round();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // ── Stats section ─────────────────────────────────────────────────────────
  Widget _buildStats(List<String> dates) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(children: [
        Row(children: [
          _statCard(label: 'ทำทั้งหมด', value: '${dates.length}',
              unit: 'ครั้ง', icon: Icons.repeat_rounded, iconColor: const Color(0xFF00C978)),
          const SizedBox(width: 10),
          _statCard(label: 'ล่าสุดเมื่อ', value: _latestDateLabel, unit: '',
              icon: Icons.event_available_rounded, iconColor: Colors.blue.shade400, isDate: true),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _statCard(label: 'เวลาสะสม', value: _totalDuration > 0 ? _totalDuration.toStringAsFixed(0) : '—',
              unit: 'นาที', icon: Icons.timer_outlined, iconColor: Colors.deepPurple.shade300),
          const SizedBox(width: 10),
          _statCard(label: 'แคลอรี่สะสม', value: _totalCalories > 0 ? _totalCalories.toStringAsFixed(0) : '—',
              unit: 'kcal', icon: Icons.local_fire_department_rounded, iconColor: Colors.orange.shade400),
        ]),
        if (widget.hasDistance) ...[
          const SizedBox(height: 10),
          Row(children: [
            _statCard(label: 'ระยะทางสะสม', value: _totalDistance > 0 ? _totalDistance.toStringAsFixed(1) : '—',
                unit: 'กม.', icon: Icons.straighten_rounded, iconColor: const Color(0xFF64B5F6)),
            const SizedBox(width: 10),
            _statCard(label: 'นานสุด/ไกลสุด', value: _maxDuration > 0 ? '${_maxDuration.toStringAsFixed(0)} น.' : '—',
                unit: _maxDistance > 0 ? '/ ${_maxDistance.toStringAsFixed(1)} กม.' : '', icon: Icons.emoji_events_rounded, iconColor: Colors.amber.shade600),
          ]),
        ] else ...[
          const SizedBox(height: 10),
          Row(children: [
            _statCard(label: 'นานสุด', value: _maxDuration > 0 ? _maxDuration.toStringAsFixed(0) : '—',
                unit: 'นาที', icon: Icons.emoji_events_rounded, iconColor: Colors.amber.shade600),
            const SizedBox(width: 10),
            const Expanded(child: SizedBox()),
          ]),
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
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
            ),
          ]),
          const SizedBox(height: 6),
          isDate
              ? Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black87, fontFamily: 'Inter'))
              : RichText(
                  text: TextSpan(children: [
                    TextSpan(text: value,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black87, fontFamily: 'Inter')),
                    if (value != '—' && unit.isNotEmpty)
                      TextSpan(text: ' $unit',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500, fontFamily: 'Inter')),
                  ]),
                ),
        ]),
      ),
    );
  }

  // ── กราฟแนวโน้ม: สลับแท็บ แคลอรี่ / ระยะเวลา / ระยะทาง(ถ้ามี) ───────────────
  Widget _buildChart(List<String> allDatesDesc) {
    final chartDates = allDatesDesc.reversed.toList(); // oldest → newest
    const green = Color(0xFF00C978);
    final values = chartDates.map((d) {
      switch (_metric) {
        case _CardioChartMetric.calories: return _sessionCalories(d);
        case _CardioChartMetric.duration: return _sessionDuration(d);
        case _CardioChartMetric.distance: return _sessionDistance(d);
      }
    }).toList();
    final maxV = values.isEmpty ? 0.0 : values.reduce(math.max);
    final spots = List.generate(values.length, (i) => FlSpot(i.toDouble(), values[i]));
    final interval = chartDates.length <= 6 ? 1.0 : (chartDates.length / 6).ceilToDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
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
            Text('แนวโน้ม', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
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

  String _shortDate(String raw) {
    try {
      final p = raw.split('T').first.split('-');
      return '${int.parse(p[2])}/${int.parse(p[1])}';
    } catch (_) { return raw; }
  }

  Widget _metricToggle() {
    const green = Color(0xFF00C978);
    Widget seg(String label, _CardioChartMetric m) {
      final active = _metric == m;
      return GestureDetector(
        onTap: () => setState(() => _metric = m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: active ? green : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: active ? Colors.black : Colors.grey.shade500)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(22)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('แคลอรี่', _CardioChartMetric.calories),
        seg('เวลา', _CardioChartMetric.duration),
        if (widget.hasDistance) seg('ระยะทาง', _CardioChartMetric.distance),
      ]),
    );
  }
}

// ─── Video Thumbnail (frame แรกของวิดีโอ) ────────────────────────────────────

class _VideoPlayerWithThumbnail extends StatefulWidget {
  final String videoUrl;
  final String exerciseName;

  const _VideoPlayerWithThumbnail({required this.videoUrl, required this.exerciseName});

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
          builder: (_) => _FullScreenVideoPage(videoUrl: widget.videoUrl, exerciseName: widget.exerciseName),
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

// ─── Full-Screen Video Page ───────────────────────────────────────────────────

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
