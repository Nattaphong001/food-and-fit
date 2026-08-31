// หน้า: Cardio Activity (เลือกกิจกรรมคาร์ดิโอ)
// ทำหน้าที่: แสดงรายการประเภทกิจกรรมคาร์ดิโอทั้งหมด ให้ผู้ใช้เลือกก่อนเริ่มออกกำลังกาย

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_page_header.dart';
import '../../../core/widgets/cached_image.dart';
import '../../../core/widgets/sticky_filter_chip_bar.dart';
import '../../../models/exercise_model.dart';
import '../../../services/exercise_service.dart';
import 'cardio_activity_detail_view.dart';

class CardioActivityView extends StatefulWidget {
  const CardioActivityView({super.key});

  @override
  State<CardioActivityView> createState() => _CardioActivityViewState();
}

class _CardioActivityViewState extends State<CardioActivityView> {
  List<CardioType> _allActivities = [];
  List<CardioType> _filtered = [];
  List<CardioCategory> _categories = [];
  int? _selectedCategoryId; // null = ทั้งหมด
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      ExerciseService.to.getCardioActivities(),
      ExerciseService.to.getCardioCategories(),
    ]);
    if (!mounted) return;
    setState(() {
      if (results[0]['success'] == true) {
        _allActivities = results[0]['data'] as List<CardioType>;
      }
      if (results[1]['success'] == true) {
        _categories = results[1]['data'] as List<CardioCategory>;
      }
      _applyFilter();
      _isLoading = false;
    });
  }

  void _applyFilter() {
    _filtered = _selectedCategoryId == null
        ? List.from(_allActivities)
        : _allActivities.where((a) => a.categoryId == _selectedCategoryId).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            const AppPageHeader(title: 'เลือกกิจกรรมคาร์ดิโอ'),
            const SizedBox(height: 20),
            _buildGoalCard(),
            const SizedBox(height: 20),
            _buildCategoryChips(),
            const SizedBox(height: 16),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }


  Widget _buildGoalCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.primaryGreen.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('เลือกกิจกรรมที่ต้องการ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black)),
              SizedBox(height: 4),
              Text('บันทึกผลหลังออกกำลังกายเสร็จ', style: TextStyle(fontSize: 13, color: Colors.black54)),
            ],
          ),
          Icon(Icons.directions_run_rounded, color: Colors.black87, size: 40),
        ],
      ),
    );
  }

  // ตัวกรองหมวดหมู่ — pattern เดียวกับตัวกรองกลุ่มกล้ามเนื้อหน้าตารางเวท (ดู
  // weight_training_schedule_view.dart _buildFilterChips) ต่างกันแค่ CardioCategory
  // ไม่มี imageUrl เลยไม่มีไอคอนวงกลมหน้าชื่อหมวด
  Widget _buildCategoryChips() {
    final items = <FilterChipItem<int?>>[
      const FilterChipItem<int?>(id: null, label: 'ทั้งหมด'),
      for (final cat in _categories)
        FilterChipItem<int?>(id: cat.categoryId, label: cat.categoryName),
    ];
    return StickyFilterChipBar<int?>(
      items: items,
      selectedId: _selectedCategoryId,
      onSelected: (id) => setState(() {
        _selectedCategoryId = id;
        _applyFilter();
      }),
      padding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }

  Widget _buildList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
    }
    if (_filtered.isEmpty) {
      return const Center(child: Text('ไม่มีกิจกรรม', style: TextStyle(color: AppColors.textMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _buildActivityCard(_filtered[i]),
    );
  }

  Widget _buildActivityCard(CardioType activity) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CardioActivityDetailView(activity: activity),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: (activity.imageUrl != null && activity.imageUrl!.isNotEmpty)
                    ? cachedImage(activity.imageUrl!, fit: BoxFit.cover)
                    : const Icon(Icons.directions_run_rounded, color: AppColors.primaryGreen, size: 32),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(activity.typeName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const SizedBox(height: 4),
                  if (activity.mets > 0)
                    Text('MET: ${activity.mets.toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  if (activity.description.isNotEmpty)
                    Text(activity.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.textBody, height: 1.4)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
