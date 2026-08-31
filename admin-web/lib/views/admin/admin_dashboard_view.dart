// [PAGE] ADMIN_DASHBOARD : ภาพรวมระบบ (เว็บ)
// [PAGE_PURPOSE] หน้าแรกหลังเข้าสู่ระบบ — "สแกน 5 วินาทีแล้วรู้ว่าระบบปกติหรือไม่" ไม่ใช่หน้าเจาะข้อมูล
//                จึงไม่มีตัวกรองช่วงเวลาเหมือนหน้ารายงาน (คงที่ 30 วันล่าสุด จากฝั่ง backend)
// [PAGE_ROUTE] /admin > ภาพรวม
// [USES_FEATURES] REPORT

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/admin_list_state.dart';
import '../../services/api_client.dart';

class _RegPoint {
  final DateTime date;
  final int count;
  _RegPoint(this.date, this.count);
  factory _RegPoint.fromJson(Map<String, dynamic> j) => _RegPoint(DateTime.parse(j['date']), (j['count'] ?? 0) as int);
}

class _TargetSlice {
  final int target; // 1=ลดน้ำหนัก 2=เพิ่มกล้ามเนื้อ 3=รักษาน้ำหนัก
  final int count;
  _TargetSlice(this.target, this.count);
  factory _TargetSlice.fromJson(Map<String, dynamic> j) => _TargetSlice((j['target'] ?? 0) as int, (j['count'] ?? 0) as int);
}

class _RecentMember {
  final int mbId;
  final String fullName;
  final DateTime createdAt;
  final bool isVerified;
  _RecentMember(this.mbId, this.fullName, this.createdAt, this.isVerified);
  factory _RecentMember.fromJson(Map<String, dynamic> j) => _RecentMember(
        (j['mb_id'] ?? 0) as int,
        (j['mb_full_name'] ?? '') as String,
        DateTime.parse(j['mb_created_at']),
        (j['mb_is_verified'] ?? 0) == 1,
      );
}

class _DashboardSummary {
  final int totalMembers;
  final double? totalMembersDeltaPercent;
  final int newMembersTotal;
  final double? newMembersDeltaPercent;
  final int activeMembers;
  final double? activeMembersDeltaPercent;
  final double verifiedRate;
  final double? verifiedRateDeltaPoint;
  final List<_RegPoint> newMembersTimeline;
  final List<_TargetSlice> targetDistribution;
  final List<_RecentMember> recentMembers;

  _DashboardSummary({
    required this.totalMembers,
    required this.totalMembersDeltaPercent,
    required this.newMembersTotal,
    required this.newMembersDeltaPercent,
    required this.activeMembers,
    required this.activeMembersDeltaPercent,
    required this.verifiedRate,
    required this.verifiedRateDeltaPoint,
    required this.newMembersTimeline,
    required this.targetDistribution,
    required this.recentMembers,
  });

  factory _DashboardSummary.fromJson(Map<String, dynamic> j) => _DashboardSummary(
        totalMembers: (j['total_members'] ?? 0) as int,
        totalMembersDeltaPercent: (j['total_members_delta_percent'] as num?)?.toDouble(),
        newMembersTotal: (j['new_members_total'] ?? 0) as int,
        newMembersDeltaPercent: (j['new_members_delta_percent'] as num?)?.toDouble(),
        activeMembers: (j['active_members'] ?? 0) as int,
        activeMembersDeltaPercent: (j['active_members_delta_percent'] as num?)?.toDouble(),
        verifiedRate: (j['verified_rate'] ?? 0).toDouble(),
        verifiedRateDeltaPoint: (j['verified_rate_delta_point'] as num?)?.toDouble(),
        newMembersTimeline: (j['new_members_timeline'] as List? ?? []).map((e) => _RegPoint.fromJson(e as Map<String, dynamic>)).toList(),
        targetDistribution: (j['target_distribution'] as List? ?? []).map((e) => _TargetSlice.fromJson(e as Map<String, dynamic>)).toList(),
        recentMembers: (j['recent_members'] as List? ?? []).map((e) => _RecentMember.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class AdminDashboardView extends StatefulWidget {
  final VoidCallback onViewAllMembers;
  const AdminDashboardView({super.key, required this.onViewAllMembers});

  @override
  State<AdminDashboardView> createState() => _AdminDashboardViewState();
}

class _AdminDashboardViewState extends State<AdminDashboardView> {
  static const _green = AppColors.primaryGreen;

  bool _loading = true;
  String? _error;
  _DashboardSummary? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient().get('/admin/dashboard/summary');
      if (res.statusCode != 200) throw Exception('API Error ${res.statusCode}');
      final raw = res.data is String ? jsonDecode(res.data) : res.data;
      if (!mounted) return;
      setState(() {
        _data = _DashboardSummary.fromJson(raw as Map<String, dynamic>);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoadingSkeleton();
    if (_error != null) return _buildError();
    return _buildBody();
  }

  // ── Loading ──────────────────────────────────
  Widget _buildLoadingSkeleton() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        physics: const NeverScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: AdminShimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(builder: (context, constraints) {
                  final columns = constraints.maxWidth > 900 ? 4 : constraints.maxWidth > 560 ? 2 : 1;
                  final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: List.generate(4, (_) => AdminSkeletonBox(height: 110, width: width, borderRadius: BorderRadius.circular(16))),
                  );
                }),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, constraints) {
                  if (constraints.maxWidth < 720) {
                    return Column(children: [
                      AdminSkeletonBox(height: 260, width: double.infinity, borderRadius: BorderRadius.circular(16)),
                      const SizedBox(height: 16),
                      AdminSkeletonBox(height: 200, width: double.infinity, borderRadius: BorderRadius.circular(16)),
                    ]);
                  }
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 8, child: AdminSkeletonBox(height: 260, width: double.infinity, borderRadius: BorderRadius.circular(16))),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: AdminSkeletonBox(height: 260, width: double.infinity, borderRadius: BorderRadius.circular(16))),
                  ]);
                }),
                const SizedBox(height: 16),
                AdminSkeletonBox(height: 280, width: double.infinity, borderRadius: BorderRadius.circular(16)),
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
              const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('ไม่สามารถโหลดข้อมูลได้', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
              const SizedBox(height: 8),
              Text(_error ?? '', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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
              _buildKpiRow(),
              const SizedBox(height: 16),
              LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth < 720) {
                  return Column(children: [
                    _buildNewMembersChart(),
                    const SizedBox(height: 16),
                    _buildTargetDonut(),
                  ]);
                }
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 8, child: _buildNewMembersChart()),
                  const SizedBox(width: 16),
                  Expanded(flex: 4, child: _buildTargetDonut()),
                ]);
              }),
              const SizedBox(height: 16),
              _buildRecentMembersTable(),
            ],
          ),
        ),
      );

  // ── KPI cards: ยึด 4 ใบตายตัวตามสเปก ห้ามยัดเพิ่ม ──
  Widget _buildKpiRow() {
    final d = _data!;
    final fmt = NumberFormat('#,###');
    final cards = [
      _kpiCard(label: 'สมาชิกทั้งหมด', value: fmt.format(d.totalMembers), unit: 'คน', deltaPercent: d.totalMembersDeltaPercent),
      _kpiCard(label: 'สมาชิกใหม่ในช่วงนี้ (30 วัน)', value: fmt.format(d.newMembersTotal), unit: 'คน', deltaPercent: d.newMembersDeltaPercent),
      _kpiCard(label: 'ผู้ใช้งานจริง (Active)', value: fmt.format(d.activeMembers), unit: 'คน', deltaPercent: d.activeMembersDeltaPercent),
      _kpiCard(label: 'อัตรายืนยันตัวตนสำเร็จ', value: d.verifiedRate.toStringAsFixed(1), unit: '%', deltaPoint: d.verifiedRateDeltaPoint),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth > 900 ? 4 : constraints.maxWidth > 560 ? 2 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(spacing: 12, runSpacing: 12, children: cards.map((c) => SizedBox(width: width, child: c)).toList());
    });
  }

  // deltaPercent = การเปลี่ยนแปลงสัมพัทธ์ (%), deltaPoint = ผลต่างหน่วยเปอร์เซ็นต์ (percentage point)
  // ส่งมาแค่แบบเดียวต่อการ์ด — null ทั้งคู่ = ยังไม่มีฐานเทียบ (สมาชิกกลุ่มก่อนหน้าเป็น 0) แสดง "—"
  Widget _kpiCard({required String label, required String value, required String unit, double? deltaPercent, double? deltaPoint}) {
    final delta = deltaPercent ?? deltaPoint;
    final isPoint = deltaPoint != null;
    String deltaText;
    Color deltaColor;
    if (delta == null) {
      deltaText = '—';
      deltaColor = Colors.grey[400]!;
    } else {
      final arrow = delta >= 0 ? '↑' : '↓';
      final suffix = isPoint ? ' จุด' : '%';
      deltaText = '$arrow ${delta.abs().toStringAsFixed(1)}$suffix จากช่วงก่อนหน้า';
      deltaColor = delta >= 0 ? AppColors.primaryGreen : AppColors.error;
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 110),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(children: [
              TextSpan(text: value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.black87)),
              TextSpan(text: '  $unit', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
            ]),
          ),
          const SizedBox(height: 4),
          Text(deltaText, style: TextStyle(fontSize: 12, color: deltaColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── กราฟแท่ง: สมาชิกใหม่รายวัน 30 วันล่าสุด ──
  Widget _buildNewMembersChart() {
    final points = _data!.newMembersTimeline;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('สมาชิกใหม่ (30 วันล่าสุด)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 16),
          if (points.isEmpty)
            SizedBox(height: 180, child: Center(child: Text('ยังไม่มีข้อมูลในช่วงเวลาที่เลือก', style: TextStyle(color: Colors.grey[400], fontSize: 13))))
          else
            SizedBox(
              height: 220,
              child: BarChart(BarChartData(
                barGroups: points.asMap().entries.map((e) {
                  return BarChartGroupData(x: e.key, barRods: [
                    BarChartRodData(toY: e.value.count.toDouble(), color: _green, width: 6, borderRadius: const BorderRadius.only(topLeft: Radius.circular(3), topRight: Radius.circular(3))),
                  ]);
                }).toList(),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: 5,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= points.length) return const SizedBox();
                        final d = points[i].date;
                        return Padding(padding: const EdgeInsets.only(top: 6), child: Text('${d.day}/${d.month}', style: TextStyle(fontSize: 9, color: Colors.grey[500])));
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (v, meta) => v == v.roundToDouble() ? Text(v.toInt().toString(), style: TextStyle(fontSize: 9, color: Colors.grey[400])) : const SizedBox())),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey[200]!, strokeWidth: 1)),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: Colors.black87,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final d = points[group.x.toInt()].date;
                      return BarTooltipItem('${_formatThaiDate(d)}\n${rod.toY.toInt()} คน', const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600));
                    },
                  ),
                ),
              )),
            ),
        ],
      ),
    );
  }

  // ── โดนัทชาร์ต: สัดส่วนเป้าหมายสุขภาพ ──
  static const _targetLabels = {1: 'ลดน้ำหนัก', 2: 'เพิ่มกล้ามเนื้อ', 3: 'รักษาน้ำหนัก'};

  Widget _buildTargetDonut() {
    final slices = List<_TargetSlice>.from(_data!.targetDistribution)..sort((a, b) => b.count.compareTo(a.count));
    final total = slices.fold<int>(0, (s, e) => s + e.count);
    // ส่วนที่สัดส่วนมากกว่าใช้สีเข้มกว่าเสมอ (กฎระบบสี) — เรียงจากมากไปน้อยแล้วไล่โทนเขียวเข้ม -> อ่อน -> เทา
    const palette = [AppColors.primaryGreen, AppColors.primaryLight, Color(0xFFD1D5DB)];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('เป้าหมายสุขภาพของสมาชิก', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 16),
          if (total == 0)
            SizedBox(height: 150, child: Center(child: Text('ยังไม่มีข้อมูลในช่วงเวลาที่เลือก', style: TextStyle(color: Colors.grey[400], fontSize: 13))))
          else ...[
            Center(
              child: SizedBox(
                width: 130,
                height: 130,
                child: PieChart(PieChartData(
                  sections: List.generate(slices.length, (i) {
                    return PieChartSectionData(value: slices[i].count.toDouble(), color: palette[i % palette.length], radius: 26, title: '');
                  }),
                  centerSpaceRadius: 34,
                  sectionsSpace: 2,
                  pieTouchData: PieTouchData(enabled: false),
                )),
              ),
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(slices.length, (i) {
                final pct = slices[i].count / total * 100;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: palette[i % palette.length], shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_targetLabels[slices[i].target] ?? 'ไม่ระบุ', style: const TextStyle(fontSize: 13, color: Colors.black87))),
                    Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                  ]),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  // ── ตารางสมาชิกสมัครล่าสุด ──
  String _formatThaiDate(DateTime d) => DateFormat('d MMM yyyy', 'th').format(d);

  Widget _buildRecentMembersTable() {
    final members = _data!.recentMembers;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('สมาชิกที่สมัครล่าสุด', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            TextButton(onPressed: widget.onViewAllMembers, child: const Text('ดูทั้งหมด')),
          ]),
          const SizedBox(height: 8),
          if (members.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('ยังไม่มีสมาชิกสมัครเข้าใช้งาน', style: TextStyle(color: Colors.grey[400], fontSize: 13))))
          else ...[
            Row(children: [
              Expanded(flex: 3, child: Text('ชื่อ-นามสกุล', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[500]))),
              Expanded(flex: 2, child: Text('สมัครเมื่อ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[500]))),
              Expanded(flex: 2, child: Text('ยืนยันตัวตน', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[500]))),
            ]),
            const Divider(height: 20),
            ...members.map((m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text(m.fullName, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                    Expanded(flex: 2, child: Text(_formatThaiDate(m.createdAt), style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
                    Expanded(
                      flex: 2,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(m.isVerified ? Icons.check_circle : Icons.hourglass_empty, size: 14, color: m.isVerified ? AppColors.primaryGreen : Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(m.isVerified ? 'ยืนยันแล้ว' : 'รอยืนยัน', style: TextStyle(fontSize: 12, color: m.isVerified ? AppColors.primaryGreen : Colors.grey[500])),
                      ]),
                    ),
                  ]),
                )),
          ],
        ],
      ),
    );
  }
}
