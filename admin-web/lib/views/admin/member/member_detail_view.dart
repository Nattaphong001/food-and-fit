// [PAGE] ADMIN_MEMBER_DETAIL : รายละเอียดสมาชิก (เว็บ)
// [PAGE_PURPOSE] แสดงโปรไฟล์ + ข้อมูลร่างกายล่าสุด + กราฟย้อนหลัง BMI/BMR/TDEE ของสมาชิกคนเดียว
//                อ่านอย่างเดียวทั้งหน้า (D2 ตามสเปก admin UX) ห้ามแสดง mb_password_hash
// [PAGE_ROUTE] /admin > จัดการสมาชิก > รายชื่อสมาชิก > คลิกแถว
// [USES_FEATURES] PROFILE, BMR_TDEE

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/layout_breakpoints.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/admin_page_header.dart';
import '../../../core/widgets/admin_network_image.dart';
import '../../../services/api_client.dart';

class MemberDetailView extends StatefulWidget {
  final int memberId;
  final String fallbackName;
  // เรียกตอนกดปุ่ม back (แทนที่ Navigator.pop เดิม เพราะตอนนี้ฝังเนื้อหาแทนที่ในสล็อตเดิม
  // ของ sidebar shell ไม่ใช่ route ที่ pop ได้แล้ว)
  final VoidCallback? onBack;

  const MemberDetailView({super.key, required this.memberId, required this.fallbackName, this.onBack});

  @override
  State<MemberDetailView> createState() => _MemberDetailViewState();
}

class _MemberDetailViewState extends State<MemberDetailView> {
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  bool _hasError = false;
  Map<String, dynamic>? _profile;
  List<dynamic> _bodyStats = [];
  List<dynamic> _bmrHistory = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _isLoading = true; _hasError = false; });
    try {
      final response = await _api.get('/admin/members/${widget.memberId}', forceRefresh: true);
      if (response.statusCode == 200) {
        final data = response.data as Map;
        setState(() {
          _profile = Map<String, dynamic>.from(data['profile'] ?? {});
          _bodyStats = (data['body_stats'] ?? []) as List;
          _bmrHistory = (data['bmr_history'] ?? []) as List;
          _isLoading = false;
        });
      } else {
        setState(() { _hasError = true; _isLoading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ฝังอยู่ในสล็อตเดิมของ sidebar shell (ไม่ push route ใหม่แล้ว) จึงไม่ต้องมี Scaffold
    // ของตัวเอง — sidebar เห็นตลอด ปุ่ม back เรียก widget.onBack ที่พ่อแม่ส่งมา
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          leading: AppBackButton(onTap: widget.onBack),
          breadcrumb: ['ผู้ใช้งาน', 'รายชื่อสมาชิก', (_profile?['mb_full_name'] ?? widget.fallbackName).toString()],
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
    }
    if (_hasError || _profile == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          const Text('โหลดข้อมูลไม่สำเร็จ', style: TextStyle(color: AppColors.textBody)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _fetch, child: const Text('ลองใหม่')),
        ]),
      );
    }

    final p = _profile!;
    final gender = (p['mb_gender'] as num?)?.toInt();
    final birthDate = DateTime.tryParse((p['mb_birth_date'] ?? '').toString());
    final age = birthDate == null ? null : (DateTime.now().difference(birthDate).inDays / 365.25).floor();
    final avatarUrl = ApiClient.prefixPath(p['mb_profile_pic']);

    final latestStat = _bodyStats.isNotEmpty ? _bodyStats.first as Map : null;
    final latestBmr = _bmrHistory.isNotEmpty ? _bmrHistory.first as Map : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _card(
              child: Row(children: [
                avatarUrl != null
                    ? ClipOval(
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: AdminNetworkImage(
                            avatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.primaryGreen.withValues(alpha: 0.15),
                              alignment: Alignment.center,
                              child: const Icon(Icons.person, size: 30, color: AppColors.primaryGreen),
                            ),
                          ),
                        ),
                      )
                    : CircleAvatar(
                        radius: 32,
                        backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.15),
                        child: const Icon(Icons.person, size: 30, color: AppColors.primaryGreen),
                      ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['mb_full_name'] ?? '-', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                      const SizedBox(height: 4),
                      Text(p['mb_email'] ?? '-', style: const TextStyle(fontSize: 13, color: AppColors.textBody)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        _infoChip(gender == 1 ? 'ชาย' : gender == 2 ? 'หญิง' : 'ไม่ระบุเพศ'),
                        if (age != null) _infoChip('$age ปี'),
                      ]),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            _sectionTitle('ข้อมูลร่างกายล่าสุด'),
            const SizedBox(height: 8),
            if (latestStat == null && latestBmr == null)
              _card(child: const Text('ยังไม่มีข้อมูลร่างกาย', style: TextStyle(color: AppColors.textMuted)))
            else
              LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth > 700 ? 4 : constraints.maxWidth > 420 ? 2 : 1;
                final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
                final cards = [
                  _metricCard(Icons.monitor_weight_outlined, Colors.blue, 'น้ำหนัก', latestStat == null ? '-' : '${latestStat['mbs_weight']}', 'กก.'),
                  _metricCard(Icons.height, Colors.indigo, 'ส่วนสูง', latestStat == null ? '-' : '${latestStat['mbs_height']}', 'ซม.'),
                  _metricCard(Icons.monitor_heart_outlined, Colors.orange, 'BMI ล่าสุด', latestBmr == null ? '-' : ((latestBmr['mbh_bmi'] as num?)?.toStringAsFixed(1) ?? '-'), ''),
                  _metricCard(Icons.flag_outlined, AppColors.primaryGreen, 'เป้าหมาย', latestStat == null ? '-' : _targetLabel((latestStat['mbs_target'] as num?)?.toInt()), ''),
                ];
                return Wrap(spacing: 12, runSpacing: 12, children: cards.map((c) => SizedBox(width: width, child: c)).toList());
              }),
            const SizedBox(height: 16),
            // กราฟ BMI กับ BMR/TDEE share แกน X (เวลา) เดียวกัน วางคู่กัน 2 คอลัมน์บนจอกว้างเทียบกันง่ายกว่า
            LayoutBuilder(builder: (context, constraints) {
              final bmiSection = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _sectionTitle('ประวัติ BMI ย้อนหลัง'),
                const SizedBox(height: 8),
                _card(child: _buildBmiChart()),
              ]);
              final bmrSection = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _sectionTitle('ประวัติ BMR / TDEE ย้อนหลัง (kcal)'),
                const SizedBox(height: 8),
                _card(child: _buildBmrTdeeChart()),
              ]);
              if (constraints.maxWidth < 720) {
                return Column(children: [bmiSection, const SizedBox(height: 16), bmrSection]);
              }
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: bmiSection),
                const SizedBox(width: 16),
                Expanded(child: bmrSection),
              ]);
            }),
          ],
        ),
      ),
    );
  }

  String _targetLabel(int? v) {
    switch (v) {
      case 1: return 'ลดน้ำหนัก';
      case 2: return 'เพิ่มกล้ามเนื้อ';
      case 3: return 'รักษาน้ำหนัก';
      default: return '-';
    }
  }

  Widget _sectionTitle(String text) => Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark));

  Widget _infoChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textBody, fontWeight: FontWeight.w600)),
      );

  // สไตล์เดียวกับ _statCard ใน admin_report_view.dart (minHeight คงที่ + icon + label + value)
  Widget _metricCard(IconData icon, Color color, String label, String value, String unit) => Container(
        constraints: const BoxConstraints(minHeight: 100),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textBody)),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(children: [
                TextSpan(text: value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                if (unit.isNotEmpty) TextSpan(text: '  $unit', style: const TextStyle(fontSize: 12, color: AppColors.textBody)),
              ]),
            ),
          ],
        ),
      );

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
        child: child,
      );

  // --------------------------------------------
  // [FEATURE] REPORT
  // [FUNCTION] _bmrAscending (getter)
  // [DESCRIPTION] safety net ฝั่ง client เท่านั้น — ต้นตอ (backend เคย insert
  //               member_bmr_history ซ้ำ 2 แถวต่อการบันทึกข้อมูลร่างกาย 1 ครั้ง) แก้แล้วที่
  //               member_controller.go (FIX-DOUBLE-WRITE) นี่กันไว้เผื่อแถวผีเก่าที่เกิดก่อน
  //               วันแก้ยังค้างอยู่ใน DB (ไม่ได้ backfill/ลบข้อมูลเก่า) — endpoint นี้ไม่ได้ส่ง
  //               mbs_id มาด้วย จึงจัดกลุ่มตาม mbh_record_date แทน (1 วัน = 1 จุดข้อมูลตาม
  //               สคีมาอยู่แล้ว เป็นคีย์เดียวกับที่แถวผีชนกันจริง) เก็บเฉพาะแถวที่ mbh_id
  //               สูงสุดของแต่ละวัน (แถวจริงที่เกิดทีหลังเสมอ) แล้วเรียง mbh_id ascending
  // [INPUT] _bmrHistory (List จาก GET /admin/members/:id, backend คืนใหม่→เก่า)
  // [OUTPUT] List<Map> เรียงเก่า→ใหม่ตาม mbh_id, ไม่มีวันซ้ำ
  // [TABLES] member_bmr_history
  // [RELATED] BMR_TDEE
  // --------------------------------------------
  List<Map> get _bmrAscending {
    final byDate = <String, Map>{};
    for (final e in _bmrHistory) {
      final row = e as Map;
      final date = (row['mbh_record_date'] ?? '').toString();
      final id = (row['mbh_id'] as num?)?.toInt() ?? 0;
      final existingId = (byDate[date]?['mbh_id'] as num?)?.toInt() ?? -1;
      if (id > existingId) byDate[date] = row;
    }
    final deduped = byDate.values.toList()
      ..sort((a, b) => ((a['mbh_id'] as num?)?.toInt() ?? 0).compareTo((b['mbh_id'] as num?)?.toInt() ?? 0));
    return deduped;
  }

  // --------------------------------------------
  // [FEATURE] REPORT
  // [FUNCTION] _bmiChangePoints (getter)
  // [DESCRIPTION] กรอง _bmrAscending ให้เหลือเฉพาะจุดที่ BMI เปลี่ยนจากแถวก่อนหน้าจริง — BMI
  //               เป็นฟังก์ชันของน้ำหนัก/ส่วนสูงเท่านั้น (ดู docs/SPEC.md ข้อ 5) การแก้
  //               activity_level/target ไม่ทำให้ BMI เปลี่ยน ถ้าพล็อตทุกแถวเหมือนกราฟ
  //               BMR/TDEE จะเห็นจุดแบนราบซ้ำๆ ที่ไม่สื่อความหมายอะไรเพิ่ม
  // [INPUT] _bmrAscending
  // [OUTPUT] List<Map> เฉพาะแถวที่ mbh_bmi ต่างจากแถวก่อนหน้าในลำดับเวลา
  // [RELATED] BMR_TDEE
  // --------------------------------------------
  List<Map> get _bmiChangePoints {
    final result = <Map>[];
    double? lastBmi;
    for (final row in _bmrAscending) {
      final bmi = (row['mbh_bmi'] as num?)?.toDouble();
      if (bmi == null) continue;
      if (lastBmi == null || bmi != lastBmi) {
        result.add(row);
        lastBmi = bmi;
      }
    }
    return result;
  }

  // --------------------------------------------
  // [FEATURE] REPORT
  // [FUNCTION] _niceDayInterval
  // [DESCRIPTION] คำนวณระยะห่าง label แกน X (หน่วยมิลลิวินาที) ให้ได้ประมาณ 6 label กระจาย
  //               ทั่วช่วงวันที่จริง ปัดขึ้นเป็นจำนวนวันเต็มเสมอ กัน label วันที่ซ้ำกันตอนแก้ข้อมูล
  //               ถี่ๆ ในช่วงสั้น (แกน X เดิมใช้ index ทำให้จุดห่าง 1 วันกับ 3 เดือนถูกวาดห่าง
  //               เท่ากัน สัดส่วนแนวโน้มบิด — เปลี่ยนมาใช้ millisecondsSinceEpoch จริงแล้ว)
  // [INPUT] minX, maxX: มิลลิวินาทีของจุดแรก/จุดสุดท้ายบนกราฟ
  // [OUTPUT] double — ค่า interval ส่งให้ SideTitles
  // [RELATED] BMR_TDEE
  // --------------------------------------------
  double _niceDayInterval(double minX, double maxX) {
    const dayMs = 86400000.0;
    final spanDays = ((maxX - minX) / dayMs).ceil();
    if (spanDays <= 6) return dayMs;
    return (spanDays / 6).ceil() * dayMs;
  }

  // --------------------------------------------
  // [FEATURE] REPORT
  // [FUNCTION] _buildBmiChart
  // [DESCRIPTION] กราฟเส้น BMI ย้อนหลัง — พล็อตเฉพาะจุดที่ BMI เปลี่ยนจริง (_bmiChangePoints)
  //               แกน X เป็นวันที่จริงจาก mbh_record_date (ไม่ใช่ index ของแถว) ระยะห่างจุด
  //               บนกราฟจึงตรงกับระยะเวลาจริงที่ห่างกัน มี tooltip โชว์วันที่ + ค่า BMI ตอน
  //               hover/tap (fl_chart handleBuiltInTouches ค่า default เป็น true อยู่แล้ว)
  // [INPUT] _bmiChangePoints (แต่ละแถวมี mbh_record_date, mbh_bmi)
  // [OUTPUT] Widget กราฟเส้น BMI สูง 200 หรือข้อความ "ยังไม่มีประวัติ" ถ้าไม่มีข้อมูล
  // [TABLES] member_bmr_history
  // [RELATED] BMR_TDEE
  // --------------------------------------------
  Widget _buildBmiChart() {
    final points = _bmiChangePoints;
    if (points.isEmpty) {
      return const SizedBox(height: 120, child: Center(child: Text('ยังไม่มีประวัติ BMI', style: TextStyle(color: AppColors.textMuted))));
    }
    final spots = <FlSpot>[];
    for (final row in points) {
      final d = DateTime.tryParse((row['mbh_record_date'] ?? '').toString());
      final bmi = (row['mbh_bmi'] as num?)?.toDouble();
      if (d != null && bmi != null) spots.add(FlSpot(d.millisecondsSinceEpoch.toDouble(), bmi));
    }
    if (spots.isEmpty) {
      return const SizedBox(height: 120, child: Center(child: Text('ยังไม่มีประวัติ BMI', style: TextStyle(color: AppColors.textMuted))));
    }
    final minX = spots.first.x;
    final maxX = spots.last.x;
    return SizedBox(
      height: 200,
      child: LineChart(LineChartData(
        minX: minX,
        maxX: maxX,
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey[200]!, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: AppColors.textDark,
            getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
              final date = DateTime.fromMillisecondsSinceEpoch(s.x.toInt());
              return LineTooltipItem(
                '${DateFormat('d MMM yyyy', 'th').format(date)}\nBMI ${s.y.toStringAsFixed(1)}',
                const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(0), style: TextStyle(fontSize: 9, color: Colors.grey[400])))),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            interval: _niceDayInterval(minX, maxX),
            getTitlesWidget: (v, meta) {
              final d = DateTime.fromMillisecondsSinceEpoch(v.toInt());
              return Padding(padding: const EdgeInsets.only(top: 6), child: Text(DateFormat('d MMM', 'th').format(d), style: TextStyle(fontSize: 9, color: Colors.grey[500])));
            },
          )),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.primaryGreen,
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: AppColors.primaryGreen.withValues(alpha: 0.08)),
          ),
        ],
      )),
    );
  }

  // --------------------------------------------
  // [FEATURE] REPORT
  // [FUNCTION] _buildBmrTdeeChart
  // [DESCRIPTION] กราฟเส้น BMR/TDEE ย้อนหลัง — พล็อตทุกแถวใน _bmrAscending (ต่างจาก BMI เพราะ
  //               activity_level และ target กระทบ TDEE/Target โดยตรง เปลี่ยนทุกครั้งที่แก้
  //               ค่าพวกนี้จึงมีความหมายจริง) แกน X เป็นวันที่จริงเหมือน _buildBmiChart
  //               tooltip โชว์วันที่ + ค่า BMR หรือ TDEE ของเส้นที่ hover/tap พร้อม TDEE เป้าหมาย
  //               แนบท้ายตอน hover เส้น TDEE
  // [INPUT] _bmrAscending (แต่ละแถวมี mbh_record_date, mbh_bmr, mbh_tdee, mbh_tdee_target)
  // [OUTPUT] Widget กราฟเส้น 2 เส้น (BMR/TDEE) สูง 200 พร้อม legend หรือข้อความ "ยังไม่มีประวัติ"
  // [TABLES] member_bmr_history
  // [RELATED] BMR_TDEE
  // --------------------------------------------
  Widget _buildBmrTdeeChart() {
    final points = _bmrAscending;
    if (points.isEmpty) {
      return const SizedBox(height: 120, child: Center(child: Text('ยังไม่มีประวัติ BMR/TDEE', style: TextStyle(color: AppColors.textMuted))));
    }
    final bmrSpots = <FlSpot>[];
    final tdeeSpots = <FlSpot>[];
    final rowByX = <double, Map>{};
    for (final row in points) {
      final d = DateTime.tryParse((row['mbh_record_date'] ?? '').toString());
      if (d == null) continue;
      final x = d.millisecondsSinceEpoch.toDouble();
      rowByX[x] = row;
      final bmr = (row['mbh_bmr'] as num?)?.toDouble();
      final tdee = (row['mbh_tdee'] as num?)?.toDouble();
      if (bmr != null) bmrSpots.add(FlSpot(x, bmr));
      if (tdee != null) tdeeSpots.add(FlSpot(x, tdee));
    }
    if (bmrSpots.isEmpty && tdeeSpots.isEmpty) {
      return const SizedBox(height: 120, child: Center(child: Text('ยังไม่มีประวัติ BMR/TDEE', style: TextStyle(color: AppColors.textMuted))));
    }
    final allX = [...bmrSpots.map((s) => s.x), ...tdeeSpots.map((s) => s.x)]..sort();
    final minX = allX.first;
    final maxX = allX.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [_dotLegend(AppColors.textMuted, 'BMR'), const SizedBox(width: 12), _dotLegend(AppColors.primaryGreen, 'TDEE')]),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: LineChart(LineChartData(
            minX: minX,
            maxX: maxX,
            gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey[200]!, strokeWidth: 1)),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                tooltipBgColor: AppColors.textDark,
                getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                  final isBmr = s.barIndex == 0;
                  final label = isBmr ? 'BMR' : 'TDEE';
                  final targetCal = (rowByX[s.x]?['mbh_tdee_target'] as num?)?.toDouble();
                  final targetLine = !isBmr && targetCal != null ? '\nเป้าหมาย ${targetCal.round()} kcal' : '';
                  final date = DateTime.fromMillisecondsSinceEpoch(s.x.toInt());
                  return LineTooltipItem(
                    '${DateFormat('d MMM yyyy', 'th').format(date)}\n$label ${s.y.round()} kcal$targetLine',
                    const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  );
                }).toList(),
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, meta) => Text(NumberFormat('#,###').format(v.toInt()), style: TextStyle(fontSize: 9, color: Colors.grey[400])))),
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: _niceDayInterval(minX, maxX),
                getTitlesWidget: (v, meta) {
                  final d = DateTime.fromMillisecondsSinceEpoch(v.toInt());
                  return Padding(padding: const EdgeInsets.only(top: 6), child: Text(DateFormat('d/M').format(d), style: TextStyle(fontSize: 9, color: Colors.grey[500])));
                },
              )),
            ),
            lineBarsData: [
              LineChartBarData(spots: bmrSpots, isCurved: true, color: AppColors.textMuted, barWidth: 2, dotData: const FlDotData(show: false)),
              LineChartBarData(spots: tdeeSpots, isCurved: true, color: AppColors.primaryGreen, barWidth: 2.5, dotData: const FlDotData(show: false)),
            ],
          )),
        ),
      ],
    );
  }

  Widget _dotLegend(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ]);
}
