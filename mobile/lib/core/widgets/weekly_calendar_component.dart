import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class WeeklyCalendarComponent extends StatefulWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDaySelected;
  final bool showDates;   // false → hide date numbers, use compact card layout
  final bool showHeader;  // false → hide month/year + nav arrows
  final Set<int>? activeDays; // weekdays 1=Mon..7=Sun that show a green dot
  final bool Function(DateTime date)? isDisabled; // true → วันนั้นสีเทา กดไม่ได้

  const WeeklyCalendarComponent({
    super.key,
    required this.selectedDate,
    required this.onDaySelected,
    this.showDates = true,
    this.showHeader = true,
    this.activeDays,
    this.isDisabled,
  });

  @override
  State<WeeklyCalendarComponent> createState() => _WeeklyCalendarComponentState();
}

class _WeeklyCalendarComponentState extends State<WeeklyCalendarComponent> {
  late DateTime _weekStart; // Monday of the currently displayed week

  static const _dayLabels = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];

  static const _thaiMonths = [
    'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน',
    'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม',
    'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
  ];

  // ── swipe-week paging (full calendar only) ──────────────────────────────
  // ปฏิทินแบบเต็ม (showDates=true) ปัดซ้าย-ขวาเปลี่ยนสัปดาห์ได้ ใช้ PageView แทนการ
  // สลับ _weekStart ตรงๆ เพราะ PageView ให้ momentum/inertia ตามความเร็วนิ้วปัดจริง
  // (fling แล้วไถลลื่นเองก่อนหยุดที่หน้าถัดไป) แบบเดียวกับปฏิทิน iOS โดยธรรมชาติ ไม่ต้อง
  // คำนวณ physics เอง — sentinel เดียวกับ "จ" (จันทร์) ของสัปดาห์อ้างอิงคงที่ (พ.ศ./ค.ศ.
  // ไม่เกี่ยว แค่ใช้เป็นจุดนับ offset เป็นสัปดาห์)
  static final DateTime _epochMonday = _mondayOf(DateTime(2000, 1, 3));
  static const int _pageCenterOffset = 5000; // ~192 ปี ทั้งสองทิศทาง เกินพอสำหรับใช้งานจริง
  static const int _pageCount = _pageCenterOffset * 2;
  late final PageController _pageController;

  int _pageIndexForMonday(DateTime monday) =>
      monday.difference(_epochMonday).inDays ~/ 7 + _pageCenterOffset;

  DateTime _mondayForPageIndex(int index) =>
      _epochMonday.add(Duration(days: (index - _pageCenterOffset) * 7));

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayOf(widget.selectedDate);
    _pageController = PageController(initialPage: _pageIndexForMonday(_weekStart));
  }

  @override
  void didUpdateWidget(WeeklyCalendarComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.showDates) return; // compact mode: week position doesn't matter
    final newStart = _mondayOf(widget.selectedDate);
    if (!_sameDay(newStart, _weekStart)) {
      setState(() => _weekStart = newStart);
      // เปลี่ยนวันจากภายนอก (ไม่ใช่ผู้ใช้ปัดเอง) — สลับหน้าทันทีไม่ต้อง animate ตามพฤติกรรมเดิม
      final targetPage = _pageIndexForMonday(newStart);
      if (_pageController.hasClients &&
          _pageController.page?.round() != targetPage) {
        _pageController.jumpToPage(targetPage);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPreviousWeek() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToNextWeek() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  // ── helpers ─────────────────────────────────────────────────────────────
  static DateTime _mondayOf(DateTime date) =>
      DateTime(date.year, date.month, date.day)
          .subtract(Duration(days: date.weekday - 1));

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isToday(DateTime date) => _sameDay(date, DateTime.now());

  String _headerLabel() {
    // Use Wednesday (middle of week) to determine month label
    final mid = _weekStart.add(const Duration(days: 3));
    final month = _thaiMonths[mid.month - 1];
    final year = mid.year + 543; // พ.ศ.
    return '$month $year';
  }

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Compact weekday-only card (no dates, no header) — used by plan builder
    if (!widget.showDates) return _buildCompact();
    // Full calendar with optional header
    return _buildFull();
  }

  // ── compact card: เฉพาะชื่อวัน + dot (ไม่มีวันที่ / header) ────────────
  Widget _buildCompact() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: List.generate(7, (i) {
            final weekday = i + 1; // 1=Mon..7=Sun
            final isSelected = widget.selectedDate.weekday == weekday;
            final hasActivity = widget.activeDays?.contains(weekday) ?? false;
            final date = _weekStart.add(Duration(days: i));

            return Expanded(
              child: GestureDetector(
                onTap: () => widget.onDaySelected(date),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 42,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.accentGreen : Colors.transparent,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Center(
                        child: Text(
                          _dayLabels[i],
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                            fontSize: 14,
                            color: isSelected ? Colors.white : const Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: hasActivity
                            ? (isSelected ? Colors.white : AppColors.primaryGreen)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ── full calendar: header + date numbers (พฤติกรรมเดิมทุกอย่าง) ─────────
  Widget _buildFull() {
    return Column(
      children: [
        const Divider(height: 1, color: Color(0xFFF2F2F7)),
        const SizedBox(height: 16),

        // Header: Thai month + year and week navigation
        if (widget.showHeader) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _headerLabel(),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: Colors.black,
                  ),
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _goToPreviousWeek,
                      child: const Icon(Icons.chevron_left_rounded,
                          size: 24, color: Colors.black87),
                    ),
                    const SizedBox(width: 20),
                    GestureDetector(
                      onTap: _goToNextWeek,
                      child: const Icon(Icons.chevron_right_rounded,
                          size: 24, color: Colors.black87),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Day cells: จ อ พ พฤ ศ ส อา (Mon → Sun) — ปัดซ้าย-ขวาเปลี่ยนสัปดาห์ได้ ใช้
        // PageScrollPhysics(parent: BouncingScrollPhysics()) ตรงๆ (ไม่พึ่ง physics
        // เริ่มต้นตามแพลตฟอร์ม) ให้ไหลลื่น+มี momentum ตามแรงปัดแบบ iOS เหมือนกันทั้ง
        // iOS/Android ตามที่ต้องการ
        SizedBox(
          height: 88,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _pageCount,
            physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
            onPageChanged: (index) {
              final newStart = _mondayForPageIndex(index);
              if (!_sameDay(newStart, _weekStart)) {
                setState(() => _weekStart = newStart);
              }
            },
            itemBuilder: (context, index) =>
                _buildWeekRow(_mondayForPageIndex(index)),
          ),
        ),

        const SizedBox(height: 10),
        const Divider(height: 1, color: Color(0xFFF2F2F7)),
      ],
    );
  }

  // แถวเซลล์วันของ 1 สัปดาห์ — แยกออกมาจาก _buildFull() รับ weekStart เป็นพารามิเตอร์
  // เพราะ PageView.builder ต้องสร้างได้หลายสัปดาห์พร้อมกัน (หน้าก่อน/หลังหน้าที่กำลังโชว์)
  // ไม่ใช่แค่ _weekStart ตัวเดียวที่ค้างอยู่ใน state
  Widget _buildWeekRow(DateTime weekStart) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(7, (i) {
          final date = weekStart.add(Duration(days: i));
          final isSelected = _sameDay(date, widget.selectedDate);
          final isToday = _isToday(date);
          final hasActivity = widget.activeDays?.contains(date.weekday) ?? false;
          final disabled = widget.isDisabled?.call(date) ?? false;

          return GestureDetector(
            onTap: disabled ? null : () => widget.onDaySelected(date),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 42,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accentGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Day label
                  Text(
                    _dayLabels[i],
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                      color: disabled
                          ? AppColors.textMuted.withValues(alpha: 0.5)
                          : isSelected
                              ? Colors.white
                              : const Color(0xFF8E8E93),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Date number
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: disabled
                          ? AppColors.textMuted.withValues(alpha: 0.5)
                          : isSelected
                              ? Colors.white
                              : isToday
                                  ? AppColors.accentGreen
                                  : Colors.black,
                    ),
                  ),
                  // Indicator dot
                  if (isSelected)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 5, height: 5,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    )
                  else if (isToday || hasActivity)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 5, height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.accentGreen,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    const SizedBox(height: 9),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
