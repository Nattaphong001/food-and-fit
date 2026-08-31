// หน้า: Food List
// ทำหน้าที่: หน้ารายการอาหารทั้งหมด กรองด้วยหมวดหมู่ (ค้างแสดงตลอด) + ค้นหาแบบใกล้เคียง
// เลือกรายการเพื่อบันทึกการกิน — แทนที่ FoodCategoryView เดิม (เข้าตรงหน้านี้ทีเดียว)

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_page_header.dart';
import '../../../core/widgets/cached_image.dart';
import '../../../core/widgets/floating_selection_bar.dart';
import '../../../core/widgets/sticky_filter_chip_bar.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../models/nutrition_model.dart';
import '../../../services/nutrition_service.dart';

class FoodListView extends StatefulWidget {
  final DateTime targetDate;

  const FoodListView({super.key, required this.targetDate});

  @override
  State<FoodListView> createState() => _FoodListViewState();
}

class _FoodListViewState extends State<FoodListView> {
  List<Food> _foods = [];
  List<NutritionCategory> _categories = [];
  List<Food> _filtered = [];
  int _selectedCategoryId = 0; // 0 = ทั้งหมด
  bool _isLoading = true;
  bool _isSaving = false;
  final _searchCtrl = TextEditingController();
  final Map<int, double> _selectedQty = {};

  static const _mealTypeLabels = {1: 'เช้า', 2: 'กลางวัน', 3: 'เย็น', 4: 'ว่าง'};

  @override
  void initState() {
    super.initState();
    _loadAll();
    _searchCtrl.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_applyFilters);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      NutritionService.to.getAllFoods(),
      NutritionService.to.getCategories(),
    ]);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (results[0]['success'] == true) {
        _foods = results[0]['data'] as List<Food>;
      }
      if (results[1]['success'] == true) {
        _categories = results[1]['data'] as List<NutritionCategory>;
      }
      _applyFilters();
    });
  }

  List<Food> get _categoryScoped => _selectedCategoryId == 0
      ? _foods
      : _foods.where((f) => f.categoryId == _selectedCategoryId).toList();

  void _onCategorySelected(int id) {
    setState(() {
      _selectedCategoryId = id;
      _applyFilters();
    });
  }

  // ค้นหาแบบจัดอันดับความใกล้เคียง: ชื่อตรงเป๊ะ > ขึ้นต้นด้วยคำค้น > มีคำค้นอยู่ในชื่อ
  // > ใกล้เคียง (พิมพ์ผิด/สะกดคลาดเคลื่อนไม่กี่ตัวอักษร ใช้ Levenshtein distance)
  void _applyFilters() {
    final scoped = _categoryScoped;
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = List.from(scoped));
      return;
    }
    final scored = scoped
        .map((f) => MapEntry(f, _matchScore(f.foodName.toLowerCase(), q)))
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    setState(() => _filtered = scored.map((e) => e.key).toList());
  }

  int _matchScore(String name, String query) {
    if (name == query) return 1000;
    if (name.startsWith(query)) return 800;
    if (name.contains(query)) return 600;
    final dist = _levenshteinDistance(name, query);
    final maxLen = math.max(name.length, query.length);
    if (maxLen == 0) return 0;
    final similarity = 1 - (dist / maxLen);
    return similarity >= 0.5 ? (similarity * 500).round() : 0;
  }

  int _levenshteinDistance(String a, String b) {
    final la = a.length, lb = b.length;
    if (la == 0) return lb;
    if (lb == 0) return la;
    var prev = List<int>.generate(lb + 1, (j) => j);
    for (var i = 1; i <= la; i++) {
      final cur = List<int>.filled(lb + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost].reduce(math.min);
      }
      prev = cur;
    }
    return prev[lb];
  }

  // helper: เช็คว่าเป็นกรัมหรือไม่
  bool _isGram(Food food) => food.unit == 'กรัม';

  // จำนวนที่โชว์ในตะกร้า — แปลง qty (หน่วยนับ) เป็นข้อความที่ผู้ใช้อ่านเข้าใจ (กรัมจริง/แก้ว)
  String _qtyLabel(Food food, double qty) {
    if (_isGram(food)) return '${(qty * 100).toStringAsFixed(0)} กรัม';
    return '${qty % 1 == 0 ? qty.toInt() : qty.toStringAsFixed(1)} แก้ว';
  }

  Widget _mealTypeChips(int? selected, ValueChanged<int> onSelect) {
    return Wrap(
      spacing: 8,
      children: _mealTypeLabels.entries.map((e) {
        final isSelected = selected == e.key;
        return GestureDetector(
          onTap: () => onSelect(e.key),
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
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: AppColors.primaryGreen.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.primaryGreen, size: 20),
      ),
    );
  }

  // เพิ่ม/ถอดออกจากตะกร้า — กด "+" ครั้งแรกเพิ่มเข้าตะกร้า (qty เริ่ม 1) กดซ้ำ (ตอนนั้นไอคอนเป็นติ๊กถูก) ถอดออก
  // ปรับจำนวนต่อรายการทำในชีทตะกร้า (_openReviewSheet) แทน ไม่มี dialog เฉพาะรายการอีกต่อไป
  void _toggleCart(Food food) {
    setState(() {
      if (_selectedQty.containsKey(food.foodId)) {
        _selectedQty.remove(food.foodId);
      } else {
        _selectedQty[food.foodId] = 1.0;
      }
    });
  }

  // เปิดชีทดูรายการที่เลือกไว้ทั้งหมดก่อนยืนยันบันทึกจริง — ปรับจำนวน/ถอดรายการได้
  // ที่นี่ก่อนกดยืนยัน (ตามที่ขอ: เลือกหลายรายการ → ดูรีวิว → ค่อยยืนยันบันทึก)
  Future<void> _openReviewSheet() async {
    if (_selectedQty.isEmpty) return;
    int? mealType;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final selectedFoods = _foods.where((f) => _selectedQty.containsKey(f.foodId)).toList();
          final totalCal = selectedFoods.fold<double>(
              0, (sum, f) => sum + f.calories * (_selectedQty[f.foodId] ?? 0));

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        const Text('ตะกร้าอาหาร',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87)),
                        const Spacer(),
                        Text('${selectedFoods.length} รายการ  ·  ${totalCal.round()} kcal',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: selectedFoods.length,
                      separatorBuilder: (_, __) => const Divider(height: 20),
                      itemBuilder: (ctx, i) {
                        final food = selectedFoods[i];
                        final qty = _selectedQty[food.foodId] ?? 1.0;
                        return Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(food.foodName,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  Text('${_qtyLabel(food, qty)}  ·  ${(food.calories * qty).round()} kcal',
                                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                            _stepBtn(Icons.remove_rounded, () {
                              if (qty <= 0.5) return;
                              setSheet(() => _selectedQty[food.foodId] = qty - 0.5);
                            }),
                            SizedBox(
                              width: 44,
                              child: Text(qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(1),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            ),
                            _stepBtn(Icons.add_rounded, () => setSheet(() => _selectedQty[food.foodId] = qty + 0.5)),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                              onPressed: () {
                                setSheet(() => _selectedQty.remove(food.foodId));
                                setState(() {});
                                if (_selectedQty.isEmpty) Navigator.pop(ctx);
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('มื้ออาหาร', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                        const SizedBox(height: 8),
                        _mealTypeChips(mealType, (v) => setSheet(() => mealType = v)),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: mealType == null || saving ? null : () async {
                              setSheet(() => saving = true);
                              final ok = await _saveAllSelected(mealType!);
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (ok && mounted) Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGreen,
                              disabledBackgroundColor: AppColors.primaryGreen.withValues(alpha: 0.35),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: Text(
                              saving
                                  ? 'กำลังบันทึก...'
                                  : mealType == null
                                      ? 'เลือกมื้ออาหารก่อน'
                                      : 'ยืนยันบันทึก ${selectedFoods.length} รายการ',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
                            ),
                          ),
                        ),
                      ],
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

  // (ไม่มี batch endpoint ฝั่ง backend เลยยิง addDailyNutrition แยกทีละตัวพร้อมกัน)
  // คืนค่า true ถ้าบันทึกสำเร็จครบทุกรายการ — ผู้เรียกเป็นคนตัดสินใจว่าจะปิดหน้านี้ต่อไหม
  // (ห้าม pop เองในนี้ เพราะตอนเรียกยังมี review sheet ลอยอยู่บนสุด pop context ตอนนั้นจะไปปิด sheet แทนหน้า)
  Future<bool> _saveAllSelected(int mealType) async {
    if (_selectedQty.isEmpty || _isSaving) return false;
    setState(() => _isSaving = true);
    final selected = _foods.where((f) => _selectedQty.containsKey(f.foodId)).toList();
    final results = await Future.wait(selected.map((food) => NutritionService.to.addDailyNutrition(
          foodId: food.foodId,
          quantity: _selectedQty[food.foodId] ?? 1.0,
          date: widget.targetDate,
          food: food,
          mealType: mealType,
        )));
    if (!mounted) return false;
    final failedCount = results.where((r) => r['success'] != true).length;
    setState(() {
      _isSaving = false;
      _selectedQty.clear();
    });
    if (failedCount == 0) {
      showAppAlert(context, 'บันทึก ${selected.length} รายการแล้ว 🎉', type: AppAlertType.success);
      return true;
    } else {
      showAppAlert(context, 'บันทึกไม่สำเร็จ $failedCount รายการ', type: AppAlertType.error);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filterItems = [
      const FilterChipItem(id: 0, label: 'ทั้งหมด'),
      ..._categories.map((c) => FilterChipItem(id: c.categoryId, label: c.categoryName)),
    ];
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
        children: [
        Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: AppPageHeader(
              title: 'อาหารทั้งหมด',
              trailing: _cartIconButton(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TextField(
              controller: _searchCtrl,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: "ค้นหาเมนูอาหาร",
                hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 15),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 22),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.divider.withValues(alpha: 0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.primaryGreen),
                ),
              ),
            ),
          ),
          // ตัวกรองหมวดหมู่ — ค้างแสดงตลอด ครบทุกหมวดที่ระบบมี (ไม่ใช่แค่ที่มีรายการอยู่)
          if (_categories.isNotEmpty)
            StickyFilterChipBar<int>(
              items: filterItems,
              selectedId: _selectedCategoryId,
              onSelected: _onCategorySelected,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("รายการอาหาร", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                Text('${_filtered.length} รายการ',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryGreen)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
                : _filtered.isEmpty
                    ? const Center(child: Text('ไม่พบรายการอาหาร', style: TextStyle(color: AppColors.textMuted)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) => _buildFoodCard(_filtered[index]),
                      ),
          ),
        ],
        ),
        if (_selectedQty.isNotEmpty)
          FloatingSelectionBar(
            count: _selectedQty.length,
            confirmLabel: _isSaving ? 'กำลังบันทึก...' : 'ดูตะกร้า',
            onConfirm: _openReviewSheet,
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildFoodCard(Food food) {
    final isSelected = _selectedQty.containsKey(food.foodId);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isSelected ? Border.all(color: AppColors.primaryGreen, width: 2) : null,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: food.imageUrl != null
                    ? cachedImage(food.imageUrl!, width: 56, height: 56, fit: BoxFit.cover)
                    : _foodIconPlaceholder(),
              ),
              if (isSelected)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.primaryGreen, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(food.foodName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 5, runSpacing: 4,
                  children: [
                    _tag('${food.calories.round()} kcal', const Color(0xFFFFF3E0), const Color(0xFFF77019)),
                    _tag('P ${food.protein.round()}g', const Color(0xFFEEF3FF), const Color(0xFF5B8CFF)),
                    _tag('C ${food.carbs.round()}g', const Color(0xFFFFF8ED), const Color(0xFFFFAB2E)),
                    _tag('F ${food.fat.round()}g', const Color(0xFFFFEEEE), const Color(0xFFFF6B6B)),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _toggleCart(food),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(color: AppColors.primaryGreen.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3)),
                ],
              ),
              child: Icon(isSelected ? Icons.check_rounded : Icons.add_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ไอคอนตะกร้ามุมขวาบนของหัวข้อ — โชว์เฉพาะตอนมีของในตะกร้า กดเปิด review sheet เดียวกับแถบลอยล่าง
  Widget? _cartIconButton() {
    if (_selectedQty.isEmpty) return null;
    return GestureDetector(
      onTap: _openReviewSheet,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38, height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.shopping_basket_rounded, color: AppColors.primaryGreen, size: 20),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              width: 18, height: 18,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.primaryGreen, shape: BoxShape.circle),
              child: Text('${_selectedQty.length}',
                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w800, fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
  );

  Widget _foodIconPlaceholder() {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.restaurant_rounded, color: AppColors.primaryGreen, size: 26),
    );
  }
}
