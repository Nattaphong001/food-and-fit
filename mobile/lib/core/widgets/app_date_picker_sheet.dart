import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

// ─── Drum roll picker (day / month / year) ───────────────────────────────────
Future<DateTime?> showAppDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AppDatePickerSheet(
      initialDate: initialDate,
      firstDate: firstDate ?? DateTime(1900),
      lastDate: lastDate ?? DateTime.now(),
    ),
  );
}

class _AppDatePickerSheet extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const _AppDatePickerSheet({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_AppDatePickerSheet> createState() => _AppDatePickerSheetState();
}

class _AppDatePickerSheetState extends State<_AppDatePickerSheet> {
  late int _day, _month, _year;
  late FixedExtentScrollController _dayCtrl, _monthCtrl, _yearCtrl;

  static const _thaiMonths = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.',
    'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.',
    'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];

  int get _firstYear => widget.firstDate.year;
  int get _lastYear => widget.lastDate.year;
  int get _yearCount => _lastYear - _firstYear + 1;
  int get _daysInMonth => DateTime(_year, _month + 1, 0).day;

  @override
  void initState() {
    super.initState();
    _day = widget.initialDate.day;
    _month = widget.initialDate.month;
    _year = widget.initialDate.year.clamp(_firstYear, _lastYear);
    _dayCtrl = FixedExtentScrollController(initialItem: _day - 1);
    _monthCtrl = FixedExtentScrollController(initialItem: _month - 1);
    _yearCtrl = FixedExtentScrollController(initialItem: _year - _firstYear);
  }

  @override
  void dispose() {
    _dayCtrl.dispose();
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  void _onDayChanged(int i) => setState(() => _day = i + 1);

  void _onMonthChanged(int i) {
    setState(() {
      _month = i + 1;
      _clampDay();
    });
  }

  void _onYearChanged(int i) {
    setState(() {
      _year = _firstYear + i;
      _clampDay();
    });
  }

  void _clampDay() {
    if (_day > _daysInMonth) {
      _day = _daysInMonth;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_dayCtrl.hasClients) _dayCtrl.jumpToItem(_day - 1);
      });
    }
  }

  Widget _buildWheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int) label,
    required void Function(int) onChanged,
  }) {
    return Expanded(
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 44,
        diameterRatio: 1.6,
        squeeze: 1.1,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: itemCount,
          builder: (_, i) => Center(
            child: Text(
              label(i),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'เลือกวันเกิด',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textDark),
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Expanded(child: Center(child: Text('วัน', style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500)))),
              Expanded(child: Center(child: Text('เดือน', style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500)))),
              Expanded(child: Center(child: Text('ปี (พ.ศ.)', style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500)))),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 44,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                Row(
                  children: [
                    _buildWheel(
                      controller: _dayCtrl,
                      itemCount: _daysInMonth,
                      label: (i) => '${i + 1}',
                      onChanged: _onDayChanged,
                    ),
                    _buildWheel(
                      controller: _monthCtrl,
                      itemCount: 12,
                      label: (i) => _thaiMonths[i],
                      onChanged: _onMonthChanged,
                    ),
                    _buildWheel(
                      controller: _yearCtrl,
                      itemCount: _yearCount,
                      label: (i) => '${_firstYear + i + 543}',
                      onChanged: _onYearChanged,
                    ),
                  ],
                ),
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 70,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white, Colors.white.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 70,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.white, Colors.white.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'ยกเลิก',
                  style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(
                    context,
                    DateTime(_year, _month, _day.clamp(1, _daysInMonth)),
                  ),
                  child: const Text(
                    'ยืนยัน',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Calendar picker (grid style) — shared by food, workout, birthday ────────

Future<DateTime?> showAppCalendarPicker(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = 'วันที่',
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AppCalendarSheet(
      initialDate: initialDate,
      firstDate: firstDate ?? DateTime(1900),
      lastDate: lastDate ?? DateTime.now(),
      title: title,
    ),
  );
}

class _AppCalendarSheet extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  const _AppCalendarSheet({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  @override
  State<_AppCalendarSheet> createState() => _AppCalendarSheetState();
}

class _AppCalendarSheetState extends State<_AppCalendarSheet> {
  late DateTime _selected;
  late DateTime _viewed;
  bool _inMonthYearMode = false;
  late int _pickerMonth;
  late int _pickerYear;
  late FixedExtentScrollController _monthCtrl;
  late FixedExtentScrollController _yearCtrl;

  static const _fullMonths = [
    'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน',
    'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม',
    'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
  ];

  static const _weekdays = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];

  int get _firstYear => widget.firstDate.year;
  int get _lastYear => widget.lastDate.year;
  int get _yearCount => _lastYear - _firstYear + 1;

  bool get _canGoPrev {
    final prev = DateTime(_viewed.year, _viewed.month - 1);
    return !prev.isBefore(DateTime(widget.firstDate.year, widget.firstDate.month));
  }

  bool get _canGoNext {
    final next = DateTime(_viewed.year, _viewed.month + 1);
    return !next.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month));
  }

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _viewed = DateTime(widget.initialDate.year, widget.initialDate.month);
    _pickerMonth = widget.initialDate.month;
    _pickerYear = widget.initialDate.year.clamp(_firstYear, _lastYear);
    _monthCtrl = FixedExtentScrollController(initialItem: _pickerMonth - 1);
    _yearCtrl = FixedExtentScrollController(initialItem: _pickerYear - _firstYear);
  }

  @override
  void dispose() {
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isDisabled(DateTime date) {
    final first = DateTime(widget.firstDate.year, widget.firstDate.month, widget.firstDate.day);
    final last = DateTime(widget.lastDate.year, widget.lastDate.month, widget.lastDate.day);
    return date.isAfter(last) || date.isBefore(first);
  }

  void _enterPickerMode() {
    _pickerMonth = _viewed.month;
    _pickerYear = _viewed.year.clamp(_firstYear, _lastYear);
    setState(() => _inMonthYearMode = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_monthCtrl.hasClients) _monthCtrl.jumpToItem(_pickerMonth - 1);
      if (_yearCtrl.hasClients) _yearCtrl.jumpToItem(_pickerYear - _firstYear);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ──
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
          ),
          // ── Title row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _inMonthYearMode
                      ? () => setState(() {
                            _viewed = DateTime(_pickerYear, _pickerMonth);
                            _inMonthYearMode = false;
                          })
                      : () => Navigator.pop(context, _selected),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _inMonthYearMode ? 'ตกลง' : 'เสร็จสิ้น',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.divider.withValues(alpha: 0.4)),
          // ── Body ──
          if (_inMonthYearMode) _buildRollPicker() else _buildCalendar(),
        ],
      ),
    );
  }

  // ── Calendar view ───────────────────────────────────────────────────────────
  Widget _buildCalendar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Month / year nav
          Row(
            children: [
              _navBtn(Icons.chevron_left_rounded,
                  _canGoPrev ? () => setState(() => _viewed = DateTime(_viewed.year, _viewed.month - 1)) : null),
              Expanded(
                child: GestureDetector(
                  onTap: _enterPickerMode,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_fullMonths[_viewed.month - 1]} ${_viewed.year + 543}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textDark),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Icon(Icons.keyboard_arrow_down_rounded,
                              size: 14, color: AppColors.primaryGreen),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _navBtn(Icons.chevron_right_rounded,
                  _canGoNext ? () => setState(() => _viewed = DateTime(_viewed.year, _viewed.month + 1)) : null),
            ],
          ),
          const SizedBox(height: 10),
          // Weekday header
          Row(
            children: _weekdays
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          // Day grid — each row is exactly 36 px tall
          _buildDayGrid(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback? onTap) {
    final active = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: active ? AppColors.surfaceLight : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon,
            size: 20,
            color: active ? AppColors.primaryGreen : AppColors.divider),
      ),
    );
  }

  Widget _buildDayGrid() {
    final firstDay = DateTime(_viewed.year, _viewed.month, 1);
    final daysInMonth = DateTime(_viewed.year, _viewed.month + 1, 0).day;
    final startOffset = firstDay.weekday % 7; // Sun=0 … Sat=6
    final today = DateTime.now();
    const rowCount = 6; // fixed — prevents layout shift when switching months

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(rowCount, (row) {
        return SizedBox(
          height: 36,
          child: Row(
            children: List.generate(7, (col) {
              final day = row * 7 + col - startOffset + 1;
              if (day < 1 || day > daysInMonth) {
                return const Expanded(child: SizedBox());
              }
              return Expanded(child: _buildDayCell(day, today));
            }),
          ),
        );
      }),
    );
  }

  Widget _buildDayCell(int day, DateTime today) {
    final date = DateTime(_viewed.year, _viewed.month, day);
    final isSel = _isSameDay(date, _selected);
    final isToday = _isSameDay(date, today);
    final disabled = _isDisabled(date);

    return GestureDetector(
      onTap: disabled ? null : () => setState(() => _selected = date),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isSel ? AppColors.primaryGreen : Colors.transparent,
            shape: BoxShape.circle,
            border: isToday && !isSel
                ? Border.all(color: AppColors.primaryGreen, width: 1.5)
                : null,
          ),
          child: Center(
            child: Text(
              '$day',
              style: TextStyle(
                fontSize: 13,
                fontWeight: (isSel || isToday) ? FontWeight.bold : FontWeight.w500,
                color: disabled
                    ? const Color(0xFFCCCCCC)
                    : isSel
                        ? Colors.black
                        : isToday
                            ? AppColors.primaryGreen
                            : AppColors.textDark,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Drum roll month / year picker ───────────────────────────────────────────
  Widget _buildRollPicker() {
    return SizedBox(
      height: 210,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ListWheelScrollView.useDelegate(
                  controller: _monthCtrl,
                  itemExtent: 44,
                  diameterRatio: 1.6,
                  squeeze: 1.1,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: (i) => setState(() => _pickerMonth = i + 1),
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: 12,
                    builder: (_, i) => Center(
                      child: Text(_fullMonths[i],
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: ListWheelScrollView.useDelegate(
                  controller: _yearCtrl,
                  itemExtent: 44,
                  diameterRatio: 1.6,
                  squeeze: 1.1,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: (i) => setState(() => _pickerYear = _firstYear + i),
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: _yearCount,
                    builder: (_, i) => Center(
                      child: Text('${_firstYear + i + 543}',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // top fade
          Positioned(
            top: 0, left: 0, right: 0,
            child: IgnorePointer(
              child: Container(
                height: 66,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.white.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
          // bottom fade
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: IgnorePointer(
              child: Container(
                height: 66,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.white, Colors.white.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
