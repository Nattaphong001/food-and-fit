// หน้า: Admin Report (รายงานภาพรวม)
// ทำหน้าที่: แสดงสถิติและรายงานภาพรวมของแอพ เช่น จำนวนสมาชิก กิจกรรมการใช้งาน และแนวโน้มรายเดือน

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:myapp/core/constants/app_colors.dart';
import 'package:myapp/core/widgets/app_back_button.dart';
import 'package:myapp/core/widgets/top_flash.dart';
import 'package:myapp/services/api_client.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ─────────────────────────────────────────────
//  MODELS
// ─────────────────────────────────────────────

class _RegPoint {
  final String date;
  final int    count;
  _RegPoint(this.date, this.count);
  factory _RegPoint.fromJson(Map<String, dynamic> j) =>
      _RegPoint(j['date'] ?? '', (j['count'] ?? 0) as int);
}

class _AdminOverview {
  final int    totalMembers;
  final int    newMembersTotal;
  final List<_RegPoint>  newMembersTimeline;
  final double totalCalIn;
  final double totalCalOut;
  final int    totalWorkouts;
  final double weightPercent;
  final double cardioPercent;
  final int    totalDuration;
  final List<_WeekPoint> weeklyData;
  final List<_MenuEntry> popularMenus;
  final List<_DayPoint>  chartData;

  _AdminOverview({
    required this.totalMembers,
    required this.newMembersTotal,
    required this.newMembersTimeline,
    required this.totalCalIn,
    required this.totalCalOut,
    required this.totalWorkouts,
    required this.weightPercent,
    required this.cardioPercent,
    required this.totalDuration,
    required this.weeklyData,
    required this.popularMenus,
    required this.chartData,
  });

  factory _AdminOverview.fromJson(Map<String, dynamic> j) => _AdminOverview(
        totalMembers:       (j['total_members']      ?? 0) as int,
        newMembersTotal:    (j['new_members_total']  ?? 0) as int,
        newMembersTimeline: (j['new_members_timeline'] as List? ?? [])
            .map((e) => _RegPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalCalIn:    (j['total_cal_in']           ?? 0).toDouble(),
        totalCalOut:   (j['total_cal_out']          ?? 0).toDouble(),
        totalWorkouts: (j['total_workouts']         ?? 0) as int,
        weightPercent: (j['weight_percent']         ?? 0).toDouble(),
        cardioPercent: (j['cardio_percent']         ?? 0).toDouble(),
        totalDuration: (j['total_duration_minutes'] ?? 0) as int,
        weeklyData:   (j['weekly_data']   as List? ?? []).map((e) => _WeekPoint.fromJson(e)).toList(),
        popularMenus: (j['popular_menus'] as List? ?? []).map((e) => _MenuEntry.fromJson(e)).toList(),
        chartData:    (j['chart_data']    as List? ?? []).map((e) => _DayPoint.fromJson(e)).toList(),
      );
}

class _DayPoint {
  final String date;
  final double caloriesIn;
  final double caloriesOut;
  _DayPoint(this.date, this.caloriesIn, this.caloriesOut);
  factory _DayPoint.fromJson(Map<String, dynamic> j) => _DayPoint(
        j['date'] ?? '',
        (j['calories_in']  ?? 0).toDouble(),
        (j['calories_out'] ?? 0).toDouble(),
      );
}

class _WeekPoint {
  final String label;
  final double calIn;
  final double calOut;
  _WeekPoint(this.label, this.calIn, this.calOut);
  factory _WeekPoint.fromJson(Map<String, dynamic> j) => _WeekPoint(
        j['label'] ?? '',
        (j['cal_in']  ?? 0).toDouble(),
        (j['cal_out'] ?? 0).toDouble(),
      );
}

class _MenuEntry {
  final String name;
  final int    count;
  _MenuEntry(this.name, this.count);
  factory _MenuEntry.fromJson(Map<String, dynamic> j) =>
      _MenuEntry(j['name'] ?? '', (j['count'] ?? 0) as int);
}

// ─────────────────────────────────────────────
//  API
// ─────────────────────────────────────────────

class _AdminApi {
  static String get _base => '${ApiClient.serverUrl}/api/admin';

  static Map<String, String> get _headers => {
        'Authorization': 'Bearer ${GetStorage().read('auth_token') ?? ''}',
        'Content-Type': 'application/json',
      };

  static Future<_AdminOverview> fetchOverview({
    required String start,
    required String end,
  }) async {
    final uri = Uri.parse('$_base/analytics/overview?start=$start&end=$end');
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw Exception('API Error ${res.statusCode}');
    return _AdminOverview.fromJson(jsonDecode(res.body));
  }
}

// ─────────────────────────────────────────────
//  VIEW
// ─────────────────────────────────────────────

class AdminReportView extends StatefulWidget {
  const AdminReportView({super.key});
  @override
  State<AdminReportView> createState() => _AdminReportViewState();
}

class _AdminReportViewState extends State<AdminReportView> {
  static const _green = Color(0xFF1884A8);
  static const _bg    = Color(0xFFF2F2F7);
  static const _card  = Colors.white;

  static const _shortMonths = [
    'ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.',
    'ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.',
  ];
  static const _calMonths = [
    'มกราคม','กุมภาพันธ์','มีนาคม','เมษายน',
    'พฤษภาคม','มิถุนายน','กรกฎาคม','สิงหาคม',
    'กันยายน','ตุลาคม','พฤศจิกายน','ธันวาคม',
  ];
  static const _calDays = ['อา','จ','อ','พ','พฤ','ศ','ส'];

  int _tab = 2; // 1=สัปดาห์ 2=เดือน 3=กำหนด

  _AdminOverview?  _data;

  bool get _hasReportData {
    final d = _data;
    if (d == null) return false;
    return d.totalWorkouts > 0 ||
        d.totalCalIn > 0 ||
        d.totalCalOut > 0 ||
        d.newMembersTotal > 0 ||
        d.weeklyData.isNotEmpty ||
        d.popularMenus.isNotEmpty;
  }
  bool             _loading      = true;
  bool             _exporting    = false;
  String?          _error;
  DateTimeRange?   _customRange;
  bool             _showCalendar = false;
  DateTime?        _calStart;
  DateTime?        _calEnd;
  int?             _calYear;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTimeRange _rangeForTab() {
    final now = DateTime.now();
    switch (_tab) {
      case 1:  return DateTimeRange(start: now.subtract(const Duration(days: 7)),  end: now);
      case 2:  return DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
      case 3:  return _customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
      default: return DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
    }
  }

  void _openCalendar() {
    setState(() {
      _calStart     = _customRange?.start;
      _calEnd       = _customRange?.end;
      _calYear      = DateTime.now().year;
      _showCalendar = true;
    });
  }

  void _calOnTapDay(DateTime day) {
    setState(() {
      if (_calStart == null || (_calStart != null && _calEnd != null)) {
        _calStart = day; _calEnd = null;
      } else {
        if (day.isBefore(_calStart!)) { _calEnd = _calStart; _calStart = day; }
        else { _calEnd = day; }
      }
    });
  }

  bool _calSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  bool _calIsStart(DateTime d)   => _calStart != null && _calSameDay(d, _calStart!);
  bool _calIsEnd(DateTime d)     => _calEnd   != null && _calSameDay(d, _calEnd!);
  bool _calIsInRange(DateTime d) {
    if (_calStart == null || _calEnd == null) return false;
    return d.isAfter(_calStart!) && d.isBefore(_calEnd!);
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final range = _rangeForTab();
      final fmt   = DateFormat('yyyy-MM-dd');
      final data  = await _AdminApi.fetchOverview(
        start: fmt.format(range.start),
        end:   fmt.format(range.end),
      );
      setState(() { _data = data; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ─── PDF Export ──────────────────────────────

  Future<void> _exportPDF() async {
    if (_data == null) return;
    if (!_hasReportData) {
      showAppAlert(context, 'ไม่มีข้อมูลในช่วงเวลานี้ให้ export', type: AppAlertType.warning);
      return;
    }
    setState(() => _exporting = true);
    try {
      final d       = _data!;
      final range   = _rangeForTab();
      final dateFmt = DateFormat('dd/MM/yyyy');
      final numFmt  = NumberFormat('#,###');

      final regular = await PdfGoogleFonts.sarabunRegular();
      final bold    = await PdfGoogleFonts.sarabunBold();

      final pdfGreen   = PdfColor.fromHex('1BB874');
      final pdfGrey50  = PdfColor.fromHex('FAFAFA');

      final doc = pw.Document(title: 'รายงานภาพรวม Food & Fit');

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 30),
          theme: pw.ThemeData.withFont(base: regular, bold: bold),

          header: (_) => pw.Container(
            width:   double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color:   pdfGreen,
            child:   pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Food & Fit App',
                        style: pw.TextStyle(font: bold, fontSize: 17, color: PdfColors.white)),
                    pw.SizedBox(height: 3),
                    pw.Text('รายงานภาพรวมระบบ',
                        style: pw.TextStyle(font: regular, fontSize: 10, color: PdfColors.white)),
                  ],
                ),
                pw.Text(
                  '${dateFmt.format(range.start)} – ${dateFmt.format(range.end)}',
                  style: pw.TextStyle(font: bold, fontSize: 10, color: PdfColors.white),
                ),
              ],
            ),
          ),

          footer: (_) => pw.Column(
            children: [
              pw.Divider(color: PdfColors.grey300, height: 1),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Food & Fit App — รายงานสร้างโดยระบบอัตโนมัติ',
                      style: pw.TextStyle(font: regular, fontSize: 7.5, color: PdfColors.grey500)),
                  pw.Text('สร้างเมื่อ ${dateFmt.format(DateTime.now())}',
                      style: pw.TextStyle(font: regular, fontSize: 7.5, color: PdfColors.grey500)),
                ],
              ),
            ],
          ),

          build: (_) => [
            pw.SizedBox(height: 18),

            pw.Text('สรุปข้อมูลในช่วงเวลา',
                style: pw.TextStyle(font: bold, fontSize: 12, color: pdfGreen)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: pdfGrey50),
                  children: [
                    _pdfStatCell('ผู้ใช้งานทั้งหมด',
                        '${numFmt.format(d.totalMembers)} คน', bold, regular, pdfGreen),
                    _pdfStatCell('สมาชิกใหม่ในช่วงนี้',
                        '${numFmt.format(d.newMembersTotal)} คน', bold, regular, PdfColors.blue700),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _pdfStatCell('ครั้งที่ออกกำลังกาย',
                        '${numFmt.format(d.totalWorkouts)} ครั้ง', bold, regular, PdfColors.indigo),
                    _pdfStatCell('เวลาออกกำลังกายรวม',
                        '${numFmt.format(d.totalDuration)} นาที', bold, regular, PdfColors.purple),
                  ],
                ),
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: pdfGrey50),
                  children: [
                    _pdfStatCell('แคลอรีรับรวม',
                        '${numFmt.format(d.totalCalIn.toInt())} kcal', bold, regular, PdfColors.teal),
                    _pdfStatCell('แคลอรีเผาผลาญรวม',
                        '${numFmt.format(d.totalCalOut.toInt())} kcal', bold, regular, PdfColors.orange),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 18),

            pw.Text('ประเภทการออกกำลังกาย',
                style: pw.TextStyle(font: bold, fontSize: 12, color: pdfGreen)),
            pw.SizedBox(height: 8),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey300, width: 0.5)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('เวทเทรนนิ่ง',
                            style: pw.TextStyle(font: regular, fontSize: 10, color: PdfColors.grey600)),
                        pw.SizedBox(height: 4),
                        pw.Text('${d.weightPercent.toStringAsFixed(1)}%',
                            style: pw.TextStyle(font: bold, fontSize: 22, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: pdfGreen, width: 1)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('คาร์ดิโอ',
                            style: pw.TextStyle(font: regular, fontSize: 10, color: pdfGreen)),
                        pw.SizedBox(height: 4),
                        pw.Text('${d.cardioPercent.toStringAsFixed(1)}%',
                            style: pw.TextStyle(font: bold, fontSize: 22, color: pdfGreen)),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            if (d.popularMenus.isNotEmpty) ...[
              pw.SizedBox(height: 18),
              pw.Text('เมนูอาหารยอดนิยม (Top ${d.popularMenus.length})',
                  style: pw.TextStyle(font: bold, fontSize: 12, color: pdfGreen)),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: ['#', 'ชื่อเมนู', 'บันทึก (ครั้ง)'],
                data: d.popularMenus.asMap().entries.map((e) => [
                  '${e.key + 1}',
                  e.value.name,
                  numFmt.format(e.value.count),
                ]).toList(),
                headerStyle:      pw.TextStyle(font: bold, fontSize: 10, color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: pdfGreen),
                cellStyle:        pw.TextStyle(font: regular, fontSize: 10),
                oddRowDecoration: pw.BoxDecoration(color: pdfGrey50),
                border:           pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FixedColumnWidth(28),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FlexColumnWidth(1.5),
                },
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.center,
                },
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              ),
            ],
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: 'FoodFit_${DateFormat('yyyyMMdd').format(range.start)}_${DateFormat('yyyyMMdd').format(range.end)}.pdf',
      );
    } catch (e) {
      if (mounted) {
        showAppAlert(context, 'ไม่สามารถสร้าง PDF ได้: $e', type: AppAlertType.error);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  pw.Widget _pdfStatCell(
    String label,
    String value,
    pw.Font bold,
    pw.Font regular,
    PdfColor valueColor,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(font: regular, fontSize: 8.5, color: PdfColors.grey600)),
          pw.SizedBox(height: 4),
          pw.Text(value,
              style: pw.TextStyle(font: bold, fontSize: 14, color: valueColor)),
        ],
      ),
    );
  }

  // ─── BUILD ───────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: _showCalendar
          ? _buildCalendarView()
          : _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
              : _error != null
                  ? _buildError()
                  : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Center(child: AppBackButton()),
        ),
        title: const Column(
          children: [
            Text('รายงานภาพรวม',
                style: TextStyle(color: _green, fontWeight: FontWeight.bold, fontSize: 20)),
            Text('ภาพรวมการใช้งานระบบ',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
        actions: [
          if (_hasReportData)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: _exporting
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined, color: _green, size: 26),
                tooltip: 'Export PDF',
                onPressed: _exporting ? null : _exportPDF,
              ),
            ),
        ],
      );

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('ไม่สามารถโหลดข้อมูลได้',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
              const SizedBox(height: 8),
              Text(_error ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('ลองอีกครั้ง'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildBody() => RefreshIndicator(
        color: _green,
        onRefresh: () async {
          ApiClient.clearCache();
          await _load();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),
              _buildTabBar(),
              const SizedBox(height: 16),
              _buildTopRow(),
              const SizedBox(height: 12),
              _buildCalorieRow(),
              const SizedBox(height: 16),
              _buildWorkoutTypeSection(),
              const SizedBox(height: 16),
              _buildWeeklyTrendSection(),
              const SizedBox(height: 16),
              _buildPopularMenuSection(),
            ],
          ),
        ),
      );

  // ── Inline calendar (กำหนดเอง) ──────────────
  Widget _buildCalendarView() {
    final now        = DateTime.now();
    final today      = DateTime(now.year, now.month, now.day);
    final canConfirm = _calStart != null && _calEnd != null;
    final pickingEnd = _calStart != null && _calEnd == null;
    final safeTop    = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    final minYear   = now.year - 2;
    final maxYear   = now.year;
    final curYear   = _calYear ?? now.year;

    // แสดงครบ 12 เดือนเสมอ (เดือนอนาคตจะเป็นสีเทา)
    final monthList = List.generate(12, (i) => DateTime(curYear, i + 1));

    Widget buildMonthGrid(DateTime monthDate) {
      final firstDay      = DateTime(monthDate.year, monthDate.month, 1);
      final lastDay       = DateTime(monthDate.year, monthDate.month + 1, 0).day;
      final startWday     = firstDay.weekday % 7;
      final isFutureMonth = firstDay.isAfter(today);

      final cells = <Widget>[];

      // ── offset ──
      for (int i = 0; i < startWday; i++) cells.add(const SizedBox());

      // ── วันที่: วงกลมชิดบนของเซลล์ (ติดกับ อา-ส ด้านบน) ──
      for (int d = 1; d <= lastDay; d++) {
        final day     = DateTime(monthDate.year, monthDate.month, d);
        final future  = day.isAfter(today);
        final isSt    = _calIsStart(day);
        final isEn    = _calIsEnd(day);
        final inRng   = _calIsInRange(day);
        final isToday = _calSameDay(day, today);

        cells.add(GestureDetector(
          onTap: future ? null : () => _calOnTapDay(day),
          child: Center(
            child: Container(
              width: 28, height: 28,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: (isSt || isEn) ? _green
                    : inRng ? _green.withValues(alpha: 0.13) : null,
                shape: BoxShape.circle,
                border: isToday && !isSt && !isEn
                    ? Border.all(color: _green.withValues(alpha: 0.7), width: 1.5)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text('$d', style: TextStyle(
                fontSize: 13,
                fontWeight: (isSt || isEn) ? FontWeight.w800 : FontWeight.w500,
                color: (isSt || isEn) ? Colors.black87
                    : future ? Colors.grey[300]
                    : inRng ? _green
                    : isToday ? _green : Colors.black87,
              )),
            ),
          ),
        ));
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── ชื่อเดือน ──
                Row(
                  children: [
                    Container(
                      width: 3, height: 14,
                      decoration: BoxDecoration(
                        color: isFutureMonth ? Colors.grey[300] : _green,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _calMonths[monthDate.month - 1],
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: isFutureMonth ? Colors.grey[400] : Colors.black87,
                      ),
                    ),
                  ],
                ),
                // ── แถว อา-ส ──
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 10),
                  child: Row(
                    children: _calDays.map((d) => Expanded(
                      child: Center(
                        child: Text(d, style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: (d == 'อา' || d == 'ส')
                              ? Colors.red[300] : Colors.grey[400],
                        )),
                      ),
                    )).toList(),
                  ),
                ),
                // ── วันที่ ──
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: 28,
                    mainAxisSpacing: 10,
                  ),
                  children: cells,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[100]),
        ],
      );
    }

    return Column(
      children: [
        // ── AppBar space + tab bar ──
        SizedBox(height: safeTop + kToolbarHeight),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: _buildTabBar(),
        ),

        // ── Date range card ──
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8, offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(child: _calDateBox('วันเริ่มต้น', _calStart, !pickingEnd && _calStart == null)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.arrow_forward_rounded,
                    color: Colors.grey[400], size: 16),
              ),
              Expanded(child: _calDateBox('วันสิ้นสุด', _calEnd, pickingEnd)),
            ],
          ),
        ),

        // ── Year navigator ──
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: curYear > minYear
                    ? () => setState(() => _calYear = curYear - 1)
                    : null,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: curYear > minYear ? Colors.grey[100] : Colors.grey[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.chevron_left_rounded, size: 22,
                      color: curYear > minYear ? Colors.black87 : Colors.grey[300]),
                ),
              ),
              const SizedBox(width: 20),
              Text(
                'พ.ศ. ${curYear + 543}',
                style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87,
                ),
              ),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: curYear < maxYear
                    ? () => setState(() => _calYear = curYear + 1)
                    : null,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: curYear < maxYear ? Colors.grey[100] : Colors.grey[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.chevron_right_rounded, size: 22,
                      color: curYear < maxYear ? Colors.black87 : Colors.grey[300]),
                ),
              ),
            ],
          ),
        ),

        Divider(height: 1, color: Colors.grey[100]),

        // ── Scrollable months ──
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: monthList.map(buildMonthGrid).toList(),
            ),
          ),
        ),

        // ── Bottom: status + buttons ──
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey[200]!, width: 1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12, offset: const Offset(0, -3),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(16, 12, 16, safeBottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  key: ValueKey(_calStart == null ? 0 : _calEnd == null ? 1 : 2),
                  _calStart == null
                      ? 'แตะวันที่เพื่อเลือกวันเริ่มต้น'
                      : _calEnd == null
                          ? 'แตะวันที่เพื่อเลือกวันสิ้นสุด'
                          : 'เลือกช่วงวันที่เรียบร้อยแล้ว ✓',
                  style: TextStyle(
                    fontSize: 12,
                    color: canConfirm ? _green : Colors.grey[500],
                    fontWeight: canConfirm ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        _showCalendar = false;
                        if (_customRange == null) _tab = 2;
                      }),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        side: BorderSide(color: Colors.grey[300]!),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        minimumSize: const Size(0, 48),
                      ),
                      child: const Text('ยกเลิก',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: canConfirm
                          ? () {
                              setState(() {
                                _customRange = DateTimeRange(
                                    start: _calStart!, end: _calEnd!);
                                _showCalendar = false;
                              });
                              _load();
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.black87,
                        disabledBackgroundColor: Colors.grey[200],
                        disabledForegroundColor: Colors.grey[400],
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        minimumSize: const Size(0, 48),
                        elevation: 0,
                      ),
                      child: const Text('ยืนยัน',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _calDateBox(String label, DateTime? date, bool active) {
    final text = date != null
        ? '${date.day} ${_shortMonths[date.month - 1]} ${date.year + 543}'
        : '—';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? _green.withValues(alpha: 0.10) : Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: active ? Border.all(color: _green, width: 1.5) : Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w700,
            color: active ? _green : Colors.grey[500], letterSpacing: 0.3,
          )),
          const SizedBox(height: 3),
          Text(text, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700,
            color: text == '—' ? Colors.grey[400] : Colors.black87,
          )),
        ],
      ),
    );
  }

  // ── Tab bar ──────────────────────────────────
  Widget _buildTabBar() {
    const tabs      = ['สัปดาห์', 'เดือน', 'กำหนดเอง'];
    const tabValues = [1, 2, 3];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 44,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: List.generate(tabs.length, (i) {
              final sel = _tab == tabValues[i];
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (tabValues[i] == 3) {
                      setState(() => _tab = 3);
                      if (_customRange == null) {
                        _openCalendar();
                      } else {
                        _load();
                      }
                    } else {
                      setState(() { _tab = tabValues[i]; _showCalendar = false; });
                      _load();
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: sel ? _green : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (tabValues[i] == 3)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.date_range_rounded,
                              size: 13,
                              color: sel ? Colors.black87 : Colors.grey[500],
                            ),
                          ),
                        Text(
                          tabs[i],
                          style: TextStyle(
                            color: sel ? Colors.black87 : Colors.grey[500],
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        if (_tab == 3 && _customRange != null && !_showCalendar)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: _openCalendar,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _green.withOpacity(0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_month_outlined, size: 14, color: _green),
                    const SizedBox(width: 6),
                    Text(
                      _formatRange(_customRange!),
                      style: const TextStyle(fontSize: 12, color: _green, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.edit_outlined, size: 13, color: _green),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatRange(DateTimeRange range) {
    final s = range.start;
    final e = range.end;
    return '${s.day} ${_shortMonths[s.month - 1]} ${s.year + 543}'
        ' – ${e.day} ${_shortMonths[e.month - 1]} ${e.year + 543}';
  }

  // ── Row 1: ผู้ใช้งาน | ครั้งออกกำลังกาย ─────
  Widget _buildTopRow() {
    final d   = _data!;
    final fmt = NumberFormat('#,###');
    return Row(
      children: [
        Expanded(child: _statCard(
          icon:      Icons.people_alt_outlined,
          iconColor: _green,
          label:     'ผู้ใช้งาน',
          value:     fmt.format(d.totalMembers),
          unit:      'คน',
          subtitle:  d.newMembersTotal > 0
              ? '+${fmt.format(d.newMembersTotal)} ใหม่ในช่วงนี้'
              : null,
        )),
        const SizedBox(width: 12),
        Expanded(child: _statCard(
          icon:      Icons.fitness_center,
          iconColor: Colors.blue,
          label:     'ครั้งที่ออกกำลังกาย',
          value:     fmt.format(d.totalWorkouts),
          unit:      'ครั้ง',
        )),
      ],
    );
  }

  // ── Row 2: แคลอรีรับ | แคลอรีเผาผลาญ ────────
  Widget _buildCalorieRow() {
    final d   = _data!;
    final fmt = NumberFormat('#,###');
    return Row(
      children: [
        Expanded(child: _statCard(
          icon:      Icons.restaurant_menu,
          iconColor: Colors.teal,
          label:     'แคลอรีที่รับรวม',
          value:     fmt.format(d.totalCalIn.toInt()),
          unit:      'kcal',
        )),
        const SizedBox(width: 12),
        Expanded(child: _statCard(
          icon:      Icons.local_fire_department_outlined,
          iconColor: Colors.orange,
          label:     'แคลอรีเผาผลาญรวม',
          value:     fmt.format(d.totalCalOut.toInt()),
          unit:      'kcal',
        )),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color    iconColor,
    required String   label,
    required String   value,
    required String   unit,
    String?           subtitle,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black87),
                  ),
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: '  $unit',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                ],
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 10, color: _green, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      );

  // ── Pie: เวท vs คาร์ดิโอ ─────────────────────
  Widget _buildWorkoutTypeSection() {
    final d     = _data!;
    final total = d.weightPercent + d.cardioPercent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('การฝึกออกกำลังกาย',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 16),
          if (total == 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('ยังไม่มีข้อมูลในช่วงเวลานี้',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13)),
              ),
            )
          else
            Row(
              children: [
                SizedBox(
                  width: 110, height: 110,
                  child: PieChart(
                    PieChartData(
                      sections: [
                        PieChartSectionData(
                          value: d.weightPercent,
                          color: Colors.grey[300]!,
                          radius: 28,
                          title: '',
                        ),
                        PieChartSectionData(
                          value: d.cardioPercent,
                          color: _green,
                          radius: 28,
                          title: '',
                        ),
                      ],
                      centerSpaceRadius: 30,
                      sectionsSpace: 2,
                      pieTouchData: PieTouchData(enabled: false),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _legendItem(Colors.grey[300]!,
                        'เวทเทรนนิ่ง (${d.weightPercent.toStringAsFixed(0)}%)'),
                    const SizedBox(height: 10),
                    _legendItem(_green,
                        'คาร์ดิโอ (${d.cardioPercent.toStringAsFixed(0)}%)'),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) => Row(
        children: [
          Container(
              width: 10, height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.black87)),
        ],
      );

  // ── Dual Bar: กิน vs เผาผลาญ ─────────────────
  Widget _buildWeeklyTrendSection() {
    final weeks = _data!.weeklyData;

    if (weeks.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('พลังงานรวมทุกผู้ใช้',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 32),
            Center(
              child: Text('ยังไม่มีข้อมูลในช่วงเวลานี้',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13)),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    }

    final maxY = weeks
        .expand((w) => [w.calIn, w.calOut])
        .fold<double>(0.0, (a, b) => a > b ? a : b);

    final double yInterval = maxY > 0 ? (maxY / 4).ceil().toDouble() : 500.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('พลังงานรวมทุกผู้ใช้',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Row(
                children: [
                  _dotLegend(Colors.grey[350]!, 'กิน'),
                  const SizedBox(width: 10),
                  _dotLegend(_green, 'เผาผลาญ'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                maxY: maxY * 1.25,
                barGroups: weeks.asMap().entries.map((e) {
                  return BarChartGroupData(
                    x: e.key,
                    barsSpace: 4,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.calIn,
                        color: Colors.grey[300]!,
                        width: 14,
                        borderRadius: const BorderRadius.only(
                          topLeft:  Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                      BarChartRodData(
                        toY: e.value.calOut,
                        color: _green,
                        width: 14,
                        borderRadius: const BorderRadius.only(
                          topLeft:  Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                    ],
                  );
                }).toList(),

                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= weeks.length) return const SizedBox();
                        final parts = weeks[i].label.split(' ');
                        final num   = parts.length >= 3 ? parts[2] : '${i + 1}';
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('สัปดาห์$num',
                              style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      interval: yInterval,
                      getTitlesWidget: (v, meta) => Text(
                        NumberFormat('#,###').format(v.toInt()),
                        style: TextStyle(fontSize: 9, color: Colors.grey[400]),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),

                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: Colors.grey[200]!, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),

                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: Colors.black87,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final label = rodIndex == 0 ? '🍽 กิน' : '🔥 เผาผลาญ';
                      final val   = NumberFormat('#,###').format(rod.toY.toInt());
                      return BarTooltipItem(
                        '$label\n$val kcal',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _summaryChip(
                color: Colors.grey[300]!,
                label: 'รับรวม',
                value: '${NumberFormat('#,###').format(
                  weeks.fold<double>(0.0, (s, w) => s + w.calIn).toInt(),
                )} kcal',
              )),
              const SizedBox(width: 8),
              Expanded(child: _summaryChip(
                color: _green,
                label: 'เผาผลาญรวม',
                value: '${NumberFormat('#,###').format(
                  weeks.fold<double>(0.0, (s, w) => s + w.calOut).toInt(),
                )} kcal',
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dotLegend(Color color, String label) => Row(
        children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      );

  Widget _summaryChip({
    required Color  color,
    required String label,
    required String value,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color == Colors.grey[300] ? Colors.black54 : color,
              ),
            ),
          ],
        ),
      );

  // ── เมนูยอดนิยม ──────────────────────────────
  Widget _buildPopularMenuSection() {
    final menus = _data!.popularMenus;

    Color rankColor(int i) {
      switch (i) {
        case 0:  return _green;
        case 1:  return Colors.blue;
        default: return Colors.orange;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('เมนูยอดนิยม',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          if (menus.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('ยังไม่มีข้อมูลในช่วงเวลานี้',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13)),
              ),
            ),
          ...menus.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: rankColor(e.key).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${e.key + 1}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: rankColor(e.key)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(e.value.name,
                          style: const TextStyle(fontSize: 13, color: Colors.black87)),
                    ),
                    Text(
                      'บันทึก ${NumberFormat('#,###').format(e.value.count)} ครั้ง',
                      style: TextStyle(
                          fontSize: 12,
                          color: rankColor(e.key),
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
