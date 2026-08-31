// [PAGE] ADMIN_REPORT : รายงานภาพรวม (เว็บ)
// [PAGE_PURPOSE] แสดงสถิติและรายงานภาพรวมของแอพ เช่น จำนวนสมาชิก กิจกรรมการใช้งาน และแนวโน้มรายเดือน
//                + export PDF (ผ่าน package printing — เปิด print dialog ของ browser บนเว็บ)
// [PAGE_ROUTE] /admin > รายงาน > รายงานข้อมูล
// [USES_FEATURES] REPORT
//
// ย้ายจากแอปมือถือ (lib/views/admin/admin_report_view.dart)
// Logic ดึงข้อมูล/คำนวณ/กราฟ/PDF เหมือนเดิมทุกจุด (COPY) — ตัด AppBar+back button ออก
// (ฝังในหน้า Admin shell แทน) การ์ดสถิติ 2 คอลัมน์ -> Wrap responsive สูงสุด 4 คอลัมน์บนจอกว้าง

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/admin_list_state.dart';
import '../../core/widgets/top_flash.dart';
import '../../services/api_client.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ─────────────────────────────────────────────
//  MODELS
// ─────────────────────────────────────────────

class _AdminOverview {
  final int totalMembers;
  final int newMembersTotal;
  final double totalCalIn;
  final double totalCalOut;
  final int totalWorkouts;
  final double weightPercent;
  final double cardioPercent;
  final int totalDuration;
  final List<_WeekPoint> weeklyData;
  final List<_MenuEntry> popularMenus;
  final List<_DayPoint> chartData;

  _AdminOverview({
    required this.totalMembers,
    required this.newMembersTotal,
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
        totalMembers: (j['total_members'] ?? 0) as int,
        newMembersTotal: (j['new_members_total'] ?? 0) as int,
        totalCalIn: (j['total_cal_in'] ?? 0).toDouble(),
        totalCalOut: (j['total_cal_out'] ?? 0).toDouble(),
        totalWorkouts: (j['total_workouts'] ?? 0) as int,
        weightPercent: (j['weight_percent'] ?? 0).toDouble(),
        cardioPercent: (j['cardio_percent'] ?? 0).toDouble(),
        totalDuration: (j['total_duration_minutes'] ?? 0) as int,
        weeklyData: (j['weekly_data'] as List? ?? []).map((e) => _WeekPoint.fromJson(e)).toList(),
        popularMenus: (j['popular_menus'] as List? ?? []).map((e) => _MenuEntry.fromJson(e)).toList(),
        chartData: (j['chart_data'] as List? ?? []).map((e) => _DayPoint.fromJson(e)).toList(),
      );
}

class _DayPoint {
  final String date;
  final double caloriesIn;
  final double caloriesOut;
  _DayPoint(this.date, this.caloriesIn, this.caloriesOut);
  factory _DayPoint.fromJson(Map<String, dynamic> j) => _DayPoint(j['date'] ?? '', (j['calories_in'] ?? 0).toDouble(), (j['calories_out'] ?? 0).toDouble());
}

class _WeekPoint {
  final String label;
  final double calIn;
  final double calOut;
  _WeekPoint(this.label, this.calIn, this.calOut);
  factory _WeekPoint.fromJson(Map<String, dynamic> j) => _WeekPoint(j['label'] ?? '', (j['cal_in'] ?? 0).toDouble(), (j['cal_out'] ?? 0).toDouble());
}

// จุดกราฟกลาง ไม่สนว่าที่มาเป็นรายวัน (_DayPoint) หรือรายสัปดาห์ (_WeekPoint) — ให้
// _buildWeeklyTrendSection ใช้โครงเดียวกันได้ทั้งสองกรณี
class _ChartPoint {
  final String label;
  final double calIn;
  final double calOut;
  _ChartPoint(this.label, this.calIn, this.calOut);
}

class _MenuEntry {
  final String name;
  final int count;
  _MenuEntry(this.name, this.count);
  factory _MenuEntry.fromJson(Map<String, dynamic> j) => _MenuEntry(j['name'] ?? '', (j['count'] ?? 0) as int);
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

  static Future<_AdminOverview> fetchOverview({required String start, required String end}) async {
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
  static const _green = AppColors.primary;
  static const _card = AppColors.surface;

  static const _calDays = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];

  int _tab = 1; // 1=สัปดาห์ 2=เดือน 3=กำหนด

  _AdminOverview? _data;

  bool get _hasReportData {
    final d = _data;
    if (d == null) return false;
    return d.totalWorkouts > 0 || d.totalCalIn > 0 || d.totalCalOut > 0 || d.newMembersTotal > 0 || d.weeklyData.isNotEmpty || d.popularMenus.isNotEmpty;
  }

  bool _loading = true;
  bool _exporting = false;
  String? _error;
  int _totalExercises = 0;
  int _totalFoods = 0;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // จำนวนวันรวมปลายทั้งสองข้าง (inclusive) — ต้องลบ 1 ตอนคำนวณ start ไม่งั้นได้ช่วงยาวเกิน
  // นิยาม 1 วัน เช่น _weekDays=7 แต่ subtract(days: 7) จะได้ 8 วัน (start ถึง end รวมทั้งคู่)
  static const int _weekDays = 7;
  static const int _monthDays = 30;

  DateTimeRange _rangeForTab() {
    final now = DateTime.now();
    switch (_tab) {
      case 1: return DateTimeRange(start: now.subtract(const Duration(days: _weekDays - 1)), end: now);
      case 2: return DateTimeRange(start: now.subtract(const Duration(days: _monthDays - 1)), end: now);
      case 3: return _customRange ?? DateTimeRange(start: now.subtract(const Duration(days: _monthDays - 1)), end: now);
      default: return DateTimeRange(start: now.subtract(const Duration(days: _monthDays - 1)), end: now);
    }
  }

  // เกณฑ์เลือกความละเอียดกราฟ: สัปดาห์ = รายวัน, เดือน = รายสัปดาห์, กำหนดเอง = ดูตามความยาวช่วง
  // (≤14 วันยังพอมองเป็นรายวันได้ ยาวกว่านั้นย่อเป็นรายสัปดาห์กันแท่งถี่เกินอ่านไม่ออก)
  bool get _chartIsDaily {
    if (_tab == 1) return true;
    if (_tab == 2) return false;
    final range = _rangeForTab();
    return range.end.difference(range.start).inDays + 1 <= 14;
  }

  String _formatDayLabel(String isoDate) {
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return isoDate;
    return '${dt.day}/${dt.month}';
  }

  // chartData จาก API มีแค่วันที่มีข้อมูลจริง (GROUP BY date ฝั่ง SQL ไม่คืนวันว่าง) — เติมวันที่
  // ขาดให้ครบทั้งช่วงตรงนี้แทน (value 0) กันแกน x เหลือแท่งเดียวลอยตอนช่วงส่วนใหญ่ไม่มีบันทึก
  List<_ChartPoint> _chartPoints() {
    final d = _data!;
    if (_chartIsDaily) {
      final range = _rangeForTab();
      final isoFmt = DateFormat('yyyy-MM-dd');
      final byDate = {for (final p in d.chartData) p.date: p};
      final points = <_ChartPoint>[];
      var day = DateTime(range.start.year, range.start.month, range.start.day);
      final last = DateTime(range.end.year, range.end.month, range.end.day);
      while (!day.isAfter(last)) {
        final iso = isoFmt.format(day);
        final p = byDate[iso];
        points.add(_ChartPoint(_formatDayLabel(iso), p?.caloriesIn ?? 0, p?.caloriesOut ?? 0));
        day = day.add(const Duration(days: 1));
      }
      return points;
    }
    return d.weeklyData.map((w) => _ChartPoint(w.label, w.calIn, w.calOut)).toList();
  }

  // เปิดตัวเลือกช่วงวันที่เป็น dialog การ์ดลอยทับหน้ารายงานเดิม (เดิมสลับทั้งหน้าจอไปเป็นปฏิทิน
  // เต็มจอ ทำให้การ์ด/กราฟ/ปุ่ม Export หายไปหมดระหว่างเลือกช่วง) หน้ารายงานด้านหลังยังอยู่เหมือน
  // tab สัปดาห์/เดือนทุกประการ
  Future<void> _openCalendar() async {
    final hadRange = _customRange != null;
    final result = await showDialog<DateTimeRange>(
      context: context,
      builder: (_) => _CustomRangeDialog(initialRange: _customRange),
    );
    if (result != null) {
      setState(() => _customRange = result);
      _load();
    } else if (!hadRange) {
      // ยกเลิกตอนยังไม่เคยเลือกช่วงมาก่อน (เช่น เพิ่งกด tab กำหนดเองครั้งแรก) — ถอยกลับไป tab สัปดาห์
      setState(() => _tab = 1);
      _load();
    }
  }

  // ตัวนับ catalog (ท่าฝึก/อาหาร) ไม่ผูกกับช่วงเวลาที่เลือก โหลดครั้งเดียวพอ ไม่ต้อง reload ตาม tab
  bool _catalogLoaded = false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final range = _rangeForTab();
      final fmt = DateFormat('yyyy-MM-dd');
      final futures = <Future>[
        _AdminApi.fetchOverview(start: fmt.format(range.start), end: fmt.format(range.end)),
        if (!_catalogLoaded) ApiClient().get('/exercises/weights'),
        if (!_catalogLoaded) ApiClient().get('/nutrition/foods'),
      ];
      final results = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        _data = results[0] as _AdminOverview;
        if (!_catalogLoaded && results.length > 2) {
          final exercisesRaw = (results[1] as dynamic).data;
          final foodsRaw = (results[2] as dynamic).data;
          final exerciseList = exercisesRaw is Map ? (exercisesRaw['data'] as List? ?? []) : (exercisesRaw as List? ?? []);
          final foodList = foodsRaw is Map ? (foodsRaw['data'] as List? ?? []) : (foodsRaw as List? ?? []);
          _totalExercises = exerciseList.length;
          _totalFoods = foodList.length;
          _catalogLoaded = true;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
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
      final d = _data!;
      final range = _rangeForTab();
      final dateFmt = DateFormat('d MMM yyyy', 'th');
      final numFmt = NumberFormat('#,###');

      final regular = await PdfGoogleFonts.sarabunRegular();
      final bold = await PdfGoogleFonts.sarabunBold();

      final pdfGreen = PdfColor.fromHex('1BB874');
      final pdfGrey50 = PdfColor.fromHex('FAFAFA');

      final doc = pw.Document(title: 'รายงานภาพรวม Food & Fit');

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 30),
          theme: pw.ThemeData.withFont(base: regular, bold: bold),
          header: (_) => pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: pdfGreen,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Food & Fit App', style: pw.TextStyle(font: bold, fontSize: 17, color: PdfColors.white)),
                  pw.SizedBox(height: 3),
                  pw.Text('รายงานภาพรวมระบบ', style: pw.TextStyle(font: regular, fontSize: 10, color: PdfColors.white)),
                ]),
                pw.Text('${dateFmt.format(range.start)} – ${dateFmt.format(range.end)}', style: pw.TextStyle(font: bold, fontSize: 10, color: PdfColors.white)),
              ],
            ),
          ),
          footer: (context) => pw.Column(children: [
            pw.Divider(color: PdfColors.grey300, height: 1),
            pw.SizedBox(height: 5),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('Food & Fit App — รายงานสร้างโดยระบบอัตโนมัติ', style: pw.TextStyle(font: regular, fontSize: 7.5, color: PdfColors.grey500)),
              pw.Text('สร้างเมื่อ ${dateFmt.format(DateTime.now())}', style: pw.TextStyle(font: regular, fontSize: 7.5, color: PdfColors.grey500)),
              pw.Text('หน้า ${context.pageNumber}/${context.pagesCount}', style: pw.TextStyle(font: regular, fontSize: 7.5, color: PdfColors.grey500)),
            ]),
          ]),
          build: (_) => [
            pw.SizedBox(height: 18),
            pw.Text('สรุปข้อมูลในช่วงเวลา', style: pw.TextStyle(font: bold, fontSize: 12, color: pdfGreen)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: pdfGrey50),
                  children: [
                    _pdfStatCell('ผู้ใช้งานทั้งหมด', '${numFmt.format(d.totalMembers)} คน', bold, regular, pdfGreen),
                    _pdfStatCell('สมาชิกใหม่ในช่วงนี้', '${numFmt.format(d.newMembersTotal)} คน', bold, regular, PdfColors.blue700),
                  ],
                ),
                pw.TableRow(children: [
                  _pdfStatCell('ครั้งที่ออกกำลังกาย', '${numFmt.format(d.totalWorkouts)} ครั้ง', bold, regular, PdfColors.indigo),
                  _pdfStatCell('เวลาคาร์ดิโอรวม (นาที)', '${numFmt.format(d.totalDuration)} นาที', bold, regular, PdfColors.purple),
                ]),
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: pdfGrey50),
                  children: [
                    _pdfStatCell('แคลอรี่รับรวมทั้งระบบ', '${numFmt.format(d.totalCalIn.toInt())} kcal', bold, regular, PdfColors.teal),
                    _pdfStatCell('เผาผลาญรวม (พื้นฐาน + ออกกำลังกาย)', '${numFmt.format(d.totalCalOut.toInt())} kcal', bold, regular, PdfColors.orange),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Text('ประเภทการออกกำลังกาย', style: pw.TextStyle(font: bold, fontSize: 12, color: pdfGreen)),
            pw.Text('(สัดส่วนอิงจำนวนครั้งที่บันทึก)', style: pw.TextStyle(font: regular, fontSize: 8, color: PdfColors.grey500)),
            pw.SizedBox(height: 8),
            pw.Row(children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300, width: 0.5)),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                    pw.Text('เวทเทรนนิ่ง', style: pw.TextStyle(font: regular, fontSize: 10, color: PdfColors.grey600)),
                    pw.SizedBox(height: 4),
                    pw.Text('${d.weightPercent.toStringAsFixed(1)}%', style: pw.TextStyle(font: bold, fontSize: 22, color: PdfColors.grey700)),
                  ]),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: pdfGreen, width: 1)),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                    pw.Text('คาร์ดิโอ', style: pw.TextStyle(font: regular, fontSize: 10, color: pdfGreen)),
                    pw.SizedBox(height: 4),
                    pw.Text('${d.cardioPercent.toStringAsFixed(1)}%', style: pw.TextStyle(font: bold, fontSize: 22, color: pdfGreen)),
                  ]),
                ),
              ),
            ]),
            if (d.popularMenus.isNotEmpty) ...[
              pw.SizedBox(height: 18),
              pw.Text('เมนูอาหารยอดนิยม (Top ${d.popularMenus.length})', style: pw.TextStyle(font: bold, fontSize: 12, color: pdfGreen)),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: ['#', 'ชื่อเมนู', 'บันทึก (ครั้ง)'],
                data: d.popularMenus.asMap().entries.map((e) => ['${e.key + 1}', e.value.name, numFmt.format(e.value.count)]).toList(),
                headerStyle: pw.TextStyle(font: bold, fontSize: 10, color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: pdfGreen),
                cellStyle: pw.TextStyle(font: regular, fontSize: 10),
                oddRowDecoration: pw.BoxDecoration(color: pdfGrey50),
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: {0: const pw.FixedColumnWidth(28), 1: const pw.FlexColumnWidth(3), 2: const pw.FlexColumnWidth(1.5)},
                cellAlignments: {0: pw.Alignment.center, 1: pw.Alignment.centerLeft, 2: pw.Alignment.center},
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
      if (mounted) showAppAlert(context, 'ไม่สามารถสร้าง PDF ได้: $e', type: AppAlertType.error);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  pw.Widget _pdfStatCell(String label, String value, pw.Font bold, pw.Font regular, PdfColor valueColor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(12),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(label, style: pw.TextStyle(font: regular, fontSize: 8.5, color: PdfColors.grey600)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 14, color: valueColor)),
      ]),
    );
  }

  // ─── BUILD ───────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoadingSkeleton();
    if (_error != null) return _buildError();
    return _buildBody();
  }

  // shimmer skeleton แทนจอ CircularProgressIndicator เปล่าเดิม (บรีฟรอบ 3 ข้อ 1) — โครงคร่าวๆ
  // ตรงกับ layout จริงของหน้านี้ (แถบ tab/export, stat grid, กราฟ 3 คอลัมน์)
  Widget _buildLoadingSkeleton() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        physics: const NeverScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: AdminShimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const AdminSkeletonBox(height: 44, width: 360, borderRadius: BorderRadius.all(Radius.circular(14))),
                  const Spacer(),
                  AdminSkeletonBox(height: 44, width: 120, borderRadius: BorderRadius.circular(10)),
                ]),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, constraints) {
                  final columns = constraints.maxWidth > 900 ? 4 : constraints.maxWidth > 560 ? 2 : 1;
                  final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: List.generate(4, (_) => AdminSkeletonBox(height: 118, width: width, borderRadius: BorderRadius.circular(16))),
                  );
                }),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, constraints) {
                  if (constraints.maxWidth < 720) {
                    return Column(children: [
                      AdminSkeletonBox(height: 200, width: double.infinity, borderRadius: BorderRadius.circular(16)),
                      const SizedBox(height: 16),
                      AdminSkeletonBox(height: 260, width: double.infinity, borderRadius: BorderRadius.circular(16)),
                    ]);
                  }
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 2, child: AdminSkeletonBox(height: 260, width: double.infinity, borderRadius: BorderRadius.circular(16))),
                    const SizedBox(width: 16),
                    Expanded(flex: 3, child: AdminSkeletonBox(height: 260, width: double.infinity, borderRadius: BorderRadius.circular(16))),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: AdminSkeletonBox(height: 260, width: double.infinity, borderRadius: BorderRadius.circular(16))),
                  ]);
                }),
              ],
            ),
          ),
        ),
      );

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 56, color: AppColors.textMuted),
              const SizedBox(height: 16),
              const Text('ไม่สามารถโหลดข้อมูลได้', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('ลองอีกครั้ง'),
                style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ],
          ),
        ),
      );

  Widget _buildBody() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: _buildTabBar()),
                const SizedBox(width: 16),
                _buildCatalogChips(),
                const SizedBox(width: 16),
                if (_hasReportData)
                  ElevatedButton.icon(
                    onPressed: _exporting ? null : _exportPDF,
                    icon: _exporting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('Export PDF'),
                    style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
              ]),
              const SizedBox(height: 16),
              _buildStatGrid(),
              const SizedBox(height: 16),
              LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth >= 1100) {
                  return IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(flex: 2, child: _buildWorkoutTypeSection()),
                      const SizedBox(width: 16),
                      Expanded(flex: 3, child: _buildWeeklyTrendSection()),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: _buildPopularMenuSection()),
                    ]),
                  );
                }
                if (constraints.maxWidth >= 720) {
                  return Column(children: [
                    IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(flex: 2, child: _buildWorkoutTypeSection()),
                        const SizedBox(width: 16),
                        Expanded(flex: 3, child: _buildWeeklyTrendSection()),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    _buildPopularMenuSection(),
                  ]);
                }
                return Column(children: [
                  _buildWorkoutTypeSection(),
                  const SizedBox(height: 16),
                  _buildWeeklyTrendSection(),
                  const SizedBox(height: 16),
                  _buildPopularMenuSection(),
                ]);
              }),
            ],
          ),
        ),
      );


  // ── Tab bar ──────────────────────────────────
  Widget _buildTabBar() {
    const tabs = ['สัปดาห์', 'เดือน', 'กำหนดเอง'];
    const tabValues = [1, 2, 3];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 44,
          width: 360,
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
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
                      setState(() => _tab = tabValues[i]);
                      _load();
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(color: sel ? AppColors.primarySurface : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                    alignment: Alignment.center,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                      if (tabValues[i] == 3) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.date_range_rounded, size: 13, color: sel ? AppColors.primaryDark : AppColors.textMuted)),
                      Text(tabs[i], style: TextStyle(color: sel ? AppColors.primaryDark : AppColors.textMuted, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, fontSize: 12)),
                    ]),
                  ),
                ),
              );
            }),
          ),
        ),
        if (_tab == 3 && _customRange != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: _openCalendar,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: _green.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: _green.withValues(alpha: 0.25))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.calendar_month_outlined, size: 14, color: _green),
                  const SizedBox(width: 6),
                  Text(_formatRange(_customRange!), style: const TextStyle(fontSize: 12, color: _green, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit_outlined, size: 13, color: _green),
                ]),
              ),
            ),
          ),
      ],
    );
  }

  // แถบตัวนับ catalog เล็กๆ (ท่าฝึก/อาหารทั้งหมด) — ไม่ผูกกับช่วงเวลาที่เลือก จงใจทำเล็ก/รอง
  // ไม่ให้แย่ง focus จากกราฟ/สถิติหลักที่ผูกกับ tab สัปดาห์-เดือน-กำหนดเอง
  Widget _buildCatalogChips() {
    if (!_catalogLoaded) return const SizedBox();
    Widget chip(IconData icon, String value, String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: AppColors.surfaceHover, borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: AppColors.textMuted),
            const SizedBox(width: 5),
            Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(width: 3),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      chip(Icons.fitness_center, '$_totalExercises', 'ท่าฝึก'),
      const SizedBox(width: 8),
      chip(Icons.restaurant_menu, '$_totalFoods', 'อาหาร'),
    ]);
  }

  String _formatRange(DateTimeRange range) {
    final fmt = DateFormat('d MMM yyyy', 'th');
    return '${fmt.format(range.start)} – ${fmt.format(range.end)}';
  }

  // ── Stat cards: responsive 2-4 คอลัมน์ ──────
  Widget _buildStatGrid() {
    final d = _data!;
    final fmt = NumberFormat('#,###');
    final cards = [
      _statCard(icon: Icons.people_alt_outlined, iconColor: AppColors.textMuted, label: 'ผู้ใช้งาน', value: fmt.format(d.totalMembers), unit: 'คน', subtitle: d.newMembersTotal > 0 ? '+${fmt.format(d.newMembersTotal)} ใหม่ในช่วงนี้' : null),
      _statCard(icon: Icons.fitness_center, iconColor: AppColors.textMuted, label: 'ครั้งที่ออกกำลังกาย', value: fmt.format(d.totalWorkouts), unit: 'ครั้ง'),
      _statCard(icon: Icons.restaurant_menu, iconColor: AppColors.textMuted, label: 'แคลอรี่รับรวมทั้งระบบ', value: fmt.format(d.totalCalIn.toInt()), unit: 'kcal'),
      // ตัวเลขนี้ = Baseline Expenditure (BMR×1.2 ตามบทที่ 2 หัวข้อ 2.1.4.6) + คาร์ดิโอ + เวท
      // ต่างนิยามกับกราฟรายสัปดาห์ด้านล่างที่เป็น Exercise Burn ล้วนๆ (คาร์ดิโอ+เวท ไม่รวม
      // baseline) — ป้ายเดิม "(ทุกกิจกรรม)" ทำให้เข้าใจผิดว่าเทียบกับกราฟได้ตรงๆ จึงแยกคำให้
      // ชัดเจนแทน ตัวเลขการ์ดนี้ไม่เปลี่ยน (เจตนา ไม่ใช่บั๊กที่ต้องรวมตัวเลขให้เท่ากัน)
      _statCard(icon: Icons.local_fire_department_outlined, iconColor: AppColors.textMuted, label: 'เผาผลาญรวม (พื้นฐาน + ออกกำลังกาย)', value: fmt.format(d.totalCalOut.toInt()), unit: 'kcal'),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth > 900 ? 4 : constraints.maxWidth > 560 ? 2 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(spacing: 12, runSpacing: 12, children: cards.map((c) => SizedBox(width: width, child: c)).toList());
    });
  }

  // minHeight คงที่ทุกใบ กันการ์ดที่มี subtitle (delta) สูงกว่าใบที่ไม่มี — ใบที่สั้นกว่าจะเหลือที่ว่าง
  // ด้านล่างแทน ไม่ใส่เลข delta หลอกๆ ให้ใบที่ไม่มีข้อมูลจริง
  Widget _statCard({required IconData icon, required Color iconColor, required String label, required String value, required String unit, String? subtitle}) => Container(
        constraints: const BoxConstraints(minHeight: 118),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(children: [
                TextSpan(text: value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                if (unit.isNotEmpty) TextSpan(text: '  $unit', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(fontSize: 10, color: _green, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      );

  // ── Pie: เวท vs คาร์ดิโอ ─────────────────────
  Widget _buildWorkoutTypeSection() {
    final d = _data!;
    final total = d.weightPercent + d.cardioPercent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('การฝึกออกกำลังกาย', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const Text('(สัดส่วนอิงจำนวนครั้งที่บันทึก)', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 16),
          if (total == 0)
            const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('ยังไม่มีข้อมูลในช่วงเวลานี้', style: TextStyle(color: AppColors.textDisabled, fontSize: 13))))
          else
            Row(children: [
              SizedBox(
                width: 110, height: 110,
                child: PieChart(PieChartData(
                  sections: [
                    PieChartSectionData(value: d.weightPercent, color: AppColors.primary, radius: 28, title: ''),
                    PieChartSectionData(value: d.cardioPercent, color: AppColors.primaryLight, radius: 28, title: ''),
                  ],
                  centerSpaceRadius: 30,
                  sectionsSpace: 2,
                  pieTouchData: PieTouchData(enabled: false),
                )),
              ),
              const SizedBox(width: 20),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _legendItem(AppColors.primary, 'เวทเทรนนิ่ง (${d.weightPercent.toStringAsFixed(0)}%)'),
                const SizedBox(height: 10),
                _legendItem(AppColors.primaryLight, 'คาร์ดิโอ (${d.cardioPercent.toStringAsFixed(0)}%)'),
              ]),
            ]),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
      ]);

  // ── Dual Bar: กิน vs เผาผลาญ ─────────────────
  Widget _buildWeeklyTrendSection() {
    final points = _chartPoints();
    final granularityLabel = _chartIsDaily ? '(รายวัน)' : '(รายสัปดาห์)';

    if (points.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('พลังงานรวมทุกผู้ใช้ $granularityLabel', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 32),
            const Center(child: Text('ยังไม่มีข้อมูลในช่วงเวลานี้', style: TextStyle(color: AppColors.textDisabled, fontSize: 13))),
            const SizedBox(height: 16),
          ],
        ),
      );
    }

    final maxY = points.expand((p) => [p.calIn, p.calOut]).fold<double>(0.0, (a, b) => a > b ? a : b);
    final double yInterval = maxY > 0 ? _niceAxisStep(maxY / 4) : 500.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('พลังงานรวมทุกผู้ใช้ $granularityLabel', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Row(children: [_dotLegend(AppColors.chartBaseline, 'กิน'), const SizedBox(width: 10), _dotLegend(AppColors.chartExercise, 'เผาผลาญจากออกกำลังกาย')]),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: BarChart(BarChartData(
              maxY: maxY * 1.25,
              barGroups: points.asMap().entries.map((e) {
                return BarChartGroupData(x: e.key, barsSpace: 4, barRods: [
                  BarChartRodData(toY: e.value.calIn, color: AppColors.chartBaseline, width: 14, borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4))),
                  BarChartRodData(toY: e.value.calOut, color: AppColors.chartExercise, width: 14, borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4))),
                ]);
              }).toList(),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= points.length) return const SizedBox();
                      return Padding(padding: const EdgeInsets.only(top: 6), child: Text(points[i].label, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)));
                    },
                  ),
                ),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, interval: yInterval, getTitlesWidget: (v, meta) => Text(NumberFormat('#,###').format(v.toInt()), style: const TextStyle(fontSize: 9, color: AppColors.textDisabled)))),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: yInterval, getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 1)),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  tooltipBgColor: Colors.black87,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final label = rodIndex == 0 ? 'กิน' : 'เผาผลาญจากออกกำลังกาย';
                    final val = NumberFormat('#,###').format(rod.toY.toInt());
                    return BarTooltipItem('$label\n$val kcal', const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600));
                  },
                ),
              ),
            )),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _summaryChip(color: AppColors.chartBaseline, label: 'รับรวม', value: '${NumberFormat('#,###').format(points.fold<double>(0.0, (s, p) => s + p.calIn).toInt())} kcal')),
            const SizedBox(width: 8),
            Expanded(child: _summaryChip(color: AppColors.chartExercise, label: 'เผาผลาญจากออกกำลังกาย', value: '${NumberFormat('#,###').format(points.fold<double>(0.0, (s, p) => s + p.calOut).toInt())} kcal')),
          ]),
        ],
      ),
    );
  }

  // ปัดขึ้นเป็นเลขกลม (1/2/5 × เลขยกกำลัง 10) กันแกน Y ออกเลขเศษแบบ 5,035 / 10,070
  double _niceAxisStep(double raw) {
    if (raw <= 0) return 500;
    final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final residual = raw / magnitude;
    double niceResidual;
    if (residual <= 1) {
      niceResidual = 1;
    } else if (residual <= 2) {
      niceResidual = 2;
    } else if (residual <= 5) {
      niceResidual = 5;
    } else {
      niceResidual = 10;
    }
    return niceResidual * magnitude;
  }

  Widget _dotLegend(Color color, String label) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ]);

  Widget _summaryChip({required Color color, required String label, required String value}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color == AppColors.chartBaseline ? AppColors.textPrimary : color)),
        ]),
      );

  // ── เมนูยอดนิยม ──────────────────────────────
  Widget _buildPopularMenuSection() {
    final menus = _data!.popularMenus;

    Color rankColor(int i) => i == 0 ? AppColors.primary : AppColors.textMuted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('เมนูยอดนิยม', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          if (menus.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('ยังไม่มีข้อมูลในช่วงเวลานี้', style: TextStyle(color: AppColors.textDisabled, fontSize: 13)))),
          ...menus.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(color: rankColor(e.key).withValues(alpha: 0.12), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text('${e.key + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: rankColor(e.key))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(e.value.name, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))),
                  Text('บันทึก ${NumberFormat('#,###').format(e.value.count)} ครั้ง', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                ]),
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  CUSTOM RANGE DIALOG (กำหนดเอง)
// ─────────────────────────────────────────────
// การ์ดลอยเลือกช่วงวันที่ — แสดงทับหน้ารายงานเดิม (สถิติ/กราฟ/ปุ่ม Export ยังอยู่ข้างหลัง
// เหมือน tab สัปดาห์/เดือนทุกประการ) แทนที่การสลับทั้งหน้าจอไปเป็นปฏิทินเต็มจอแบบเดิม
// ส่งค่ากลับผ่าน Navigator.pop(context, DateTimeRange) ตอนกดยืนยัน หรือ pop(null) ตอนยกเลิก
class _CustomRangeDialog extends StatefulWidget {
  final DateTimeRange? initialRange;
  const _CustomRangeDialog({this.initialRange});

  @override
  State<_CustomRangeDialog> createState() => _CustomRangeDialogState();
}

class _CustomRangeDialogState extends State<_CustomRangeDialog> {
  static const _green = AppColors.primary;

  DateTime? _calStart;
  DateTime? _calEnd;
  late int _calYear;
  // ช่องที่กำลังแก้ไขอยู่ — แตะช่อง "วันเริ่มต้น"/"วันสิ้นสุด" เพื่อสลับ แล้วแตะปฏิทินจะเขียน
  // ลงช่องนั้นตรงๆ (แก้ทีละช่องอิสระ ไม่บังคับเรียงเริ่มต้น→สิ้นสุดเหมือนเดิม)
  bool _pickingStart = true;

  @override
  void initState() {
    super.initState();
    _calStart = widget.initialRange?.start;
    _calEnd = widget.initialRange?.end;
    _calYear = DateTime.now().year;
    // ยังไม่เลือกอะไรเลย หรือเลือกครบทั้งคู่แล้ว (เปิดมาแก้ไขซ้ำ) ให้โฟกัสวันเริ่มต้นก่อนตามลำดับอ่านธรรมชาติ
    // ระหว่างเลือกค้างไว้ (มีแค่วันเริ่มต้น) ให้โฟกัสวันสิ้นสุดต่อ
    _pickingStart = _calStart == null || _calEnd != null;
  }

  void _onTapDay(DateTime day) {
    setState(() {
      if (_pickingStart) {
        _calStart = day;
        if (_calEnd == null) _pickingStart = false;
      } else {
        _calEnd = day;
        if (_calStart == null) _pickingStart = true;
      }
    });
  }

  // start > end ยืนยันไม่ได้ — DateTimeRange ของ Flutter เอง assert(!start.isAfter(end))
  // เลือกอิสระแล้วสลับกันได้ ต้องกันไว้ก่อนกดยืนยัน ไม่งั้นแอปพังทั้งหน้า
  bool get _orderValid => _calStart == null || _calEnd == null || !_calStart!.isAfter(_calEnd!);

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  bool _isStart(DateTime d) => _calStart != null && _sameDay(d, _calStart!);
  bool _isEnd(DateTime d) => _calEnd != null && _sameDay(d, _calEnd!);
  bool _isInRange(DateTime d) {
    if (_calStart == null || _calEnd == null) return false;
    return d.isAfter(_calStart!) && d.isBefore(_calEnd!);
  }

  Widget _dateBox(String label, DateTime? date, bool active, VoidCallback onTap) {
    final text = date != null ? DateFormat('d MMM yyyy', 'th').format(date) : '—';
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: active ? _green.withValues(alpha: 0.10) : AppColors.surfaceHover, borderRadius: BorderRadius.circular(10), border: active ? Border.all(color: _green, width: 1.5) : const Border.fromBorderSide(BorderSide(color: AppColors.border, width: 1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: active ? _green : AppColors.textMuted, letterSpacing: 0.3)),
          const SizedBox(height: 3),
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: text == '—' ? AppColors.textDisabled : AppColors.textPrimary)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final canConfirm = _calStart != null && _calEnd != null && _orderValid;

    final minYear = now.year - 2;
    final maxYear = now.year;
    final curYear = _calYear;

    final monthList = List.generate(12, (i) => DateTime(curYear, i + 1));

    Widget buildMonthGrid(DateTime monthDate) {
      final firstDay = DateTime(monthDate.year, monthDate.month, 1);
      final lastDay = DateTime(monthDate.year, monthDate.month + 1, 0).day;
      final startWday = firstDay.weekday % 7;
      final isFutureMonth = firstDay.isAfter(today);

      final cells = <Widget>[];
      for (int i = 0; i < startWday; i++) {
        cells.add(const SizedBox());
      }

      for (int d = 1; d <= lastDay; d++) {
        final day = DateTime(monthDate.year, monthDate.month, d);
        final future = day.isAfter(today);
        final isSt = _isStart(day);
        final isEn = _isEnd(day);
        final inRng = _isInRange(day);
        final isToday = _sameDay(day, today);

        cells.add(GestureDetector(
          onTap: future ? null : () => _onTapDay(day),
          child: Center(
            child: Container(
              width: 28, height: 28,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: (isSt || isEn) ? _green : inRng ? _green.withValues(alpha: 0.13) : null,
                shape: BoxShape.circle,
                border: isToday && !isSt && !isEn ? Border.all(color: _green.withValues(alpha: 0.7), width: 1.5) : null,
              ),
              alignment: Alignment.center,
              child: Text('$d',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: (isSt || isEn) ? FontWeight.w800 : FontWeight.w500,
                    color: (isSt || isEn) ? AppColors.textPrimary : future ? AppColors.textDisabled : inRng ? _green : isToday ? _green : AppColors.textPrimary,
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
                Row(children: [
                  Container(width: 3, height: 14, decoration: BoxDecoration(color: isFutureMonth ? AppColors.textDisabled : _green, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Text(DateFormat('MMMM', 'th').format(monthDate), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isFutureMonth ? AppColors.textDisabled : AppColors.textPrimary)),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 10),
                  child: Row(children: _AdminReportViewState._calDays.map((d) => Expanded(child: Center(child: Text(d, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textDisabled))))).toList()),
                ),
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisExtent: 28, mainAxisSpacing: 10),
                  children: cells,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
        ],
      );
    }

    final dialogHeight = math.min(640.0, MediaQuery.of(context).size.height * 0.85);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SizedBox(
          height: dialogHeight,
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  child: Row(children: [
                    const Expanded(child: Text('เลือกช่วงวันที่', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary))),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textMuted)),
                  ]),
                ),
                const Divider(height: 1, color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border, width: 1)),
                    child: Row(children: [
                      Expanded(child: _dateBox('วันเริ่มต้น', _calStart, _pickingStart, () => setState(() => _pickingStart = true))),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.arrow_forward_rounded, color: AppColors.textDisabled, size: 16)),
                      Expanded(child: _dateBox('วันสิ้นสุด', _calEnd, !_pickingStart, () => setState(() => _pickingStart = false))),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    GestureDetector(
                      onTap: curYear > minYear ? () => setState(() => _calYear = curYear - 1) : null,
                      child: Container(width: 36, height: 36, decoration: BoxDecoration(color: curYear > minYear ? AppColors.surfaceHover : AppColors.background, shape: BoxShape.circle), child: Icon(Icons.chevron_left_rounded, size: 22, color: curYear > minYear ? AppColors.textPrimary : AppColors.textDisabled)),
                    ),
                    const SizedBox(width: 20),
                    Text('$curYear', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(width: 20),
                    GestureDetector(
                      onTap: curYear < maxYear ? () => setState(() => _calYear = curYear + 1) : null,
                      child: Container(width: 36, height: 36, decoration: BoxDecoration(color: curYear < maxYear ? AppColors.surfaceHover : AppColors.background, shape: BoxShape.circle), child: Icon(Icons.chevron_right_rounded, size: 22, color: curYear < maxYear ? AppColors.textPrimary : AppColors.textDisabled)),
                    ),
                  ]),
                ),
                const Divider(height: 1, color: AppColors.border),
                Expanded(
                  child: SingleChildScrollView(padding: const EdgeInsets.only(bottom: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: monthList.map(buildMonthGrid).toList())),
                ),
                Container(
                  decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border, width: 1))),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _calStart == null || _calEnd == null
                            ? (_pickingStart ? 'แตะวันที่เพื่อเลือกวันเริ่มต้น' : 'แตะวันที่เพื่อเลือกวันสิ้นสุด')
                            : !_orderValid
                                ? 'วันสิ้นสุดต้องไม่ก่อนวันเริ่มต้น'
                                : 'เลือกช่วงวันที่เรียบร้อยแล้ว',
                        style: TextStyle(
                          fontSize: 12,
                          color: canConfirm ? _green : (!_orderValid && _calStart != null && _calEnd != null) ? AppColors.dangerText : AppColors.textMuted,
                          fontWeight: canConfirm ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary, side: const BorderSide(color: AppColors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), minimumSize: const Size(0, 48)),
                            child: const Text('ยกเลิก', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: canConfirm ? () => Navigator.pop(context, DateTimeRange(start: _calStart!, end: _calEnd!)) : null,
                            style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white, disabledBackgroundColor: AppColors.border, disabledForegroundColor: AppColors.textDisabled, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), minimumSize: const Size(0, 48), elevation: 0),
                            child: const Text('ยืนยัน', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
