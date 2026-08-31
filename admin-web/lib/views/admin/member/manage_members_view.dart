// ignore_for_file: use_build_context_synchronously

// [PAGE] ADMIN_MEMBERS : รายชื่อสมาชิก (เว็บ)
// [PAGE_PURPOSE] Admin ค้นหา/ดูรายละเอียดสมาชิก — อ่านอย่างเดียว ไม่มีแก้ไข/ลบจากหน้านี้
//                (D1 ตามสเปก admin UX) ห้ามแสดง mb_password_hash เด็ดขาด
// [PAGE_ROUTE] /admin > จัดการสมาชิก > รายชื่อสมาชิก
// [USES_FEATURES] PROFILE
//
// เดิมมีคอลัมน์/dropdown กรอง "สถานะ" (ใช้งานอยู่/รอลบถาวร) ตัดออกแล้ว 2026-08-29 พร้อม
// mb_status=2 ทั้งระบบ (ดู food_and_fit_api/CLAUDE.md หัวข้อ 4 D8) — mb_status เหลือค่าเดียว
// เสมอ ไม่มีอะไรให้กรอง/แสดงเป็นป้ายสถานะอีกต่อไป

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/api_error.dart';
import '../../../core/widgets/admin_data_table.dart';
import '../../../core/widgets/admin_filter_bar.dart';
import '../../../core/widgets/admin_list_state.dart';
import '../../../core/widgets/admin_network_image.dart';
import '../../../core/widgets/admin_page_header.dart';
import '../../../core/widgets/admin_pagination_bar.dart';
import '../../../services/api_client.dart';
import 'member_detail_view.dart';

// อักษรย่อ + สีตาม hash ของ user_id (บรีฟ P2 ข้อ 12) แทนไอคอนคนเทาซ้ำกันทุกแถวที่แยกด้วยสายตายาก
const _avatarColors = [
  Color(0xFF10B981), Color(0xFF3B82F6), Color(0xFFF59E0B), Color(0xFFEF4444),
  Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFF14B8A6), Color(0xFFF97316),
];
Color _avatarColorFor(int id) => _avatarColors[id.abs() % _avatarColors.length];
String _initialOf(String name) {
  final t = name.trim();
  return t.isEmpty ? '?' : t.substring(0, 1).toUpperCase();
}

class ManageMembersView extends StatefulWidget {
  const ManageMembersView({super.key});

  @override
  State<ManageMembersView> createState() => _ManageMembersViewState();
}

class _ManageMembersViewState extends State<ManageMembersView> {
  final ApiClient _api = ApiClient();

  List<dynamic> _members = [];
  int _total = 0;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isNetworkError = false;
  String _search = '';
  int _pageSize = kAdminPageSizeOptions[1];
  int _currentPage = 1;
  // ไม่ว่างเมื่อคลิกดูรายละเอียดสมาชิก — สลับแสดงเนื้อหาแทนที่ในสล็อตเดิมของ sidebar shell
  int? _drillMemberId;
  String _drillMemberName = '';

  // ยกเลิก request เก่าที่ยังไม่ตอบกลับก่อนยิงใหม่ทุกครั้ง (ค้นหา/เปลี่ยนหน้า/เปลี่ยนตัวกรอง)
  // กัน response เก่ามาทีหลัง response ใหม่แล้วทับผลลัพธ์ผิด (มาตรฐานตัวกรอง Flutter integration ข้อ 2)
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _fetchMembers();
  }

  @override
  void dispose() {
    _cancelToken?.cancel('disposed');
    super.dispose();
  }

  // --------------------------------------------
  // [FEATURE] PROFILE
  // [FUNCTION] _fetchMembers
  // [DESCRIPTION] ดึงรายชื่อสมาชิกจาก GET /api/admin/members ตามตัวกรอง+หน้าปัจจุบัน (server-side
  //               search+pagination แทนการโหลดทั้งหมดมากรองใน Dart แบบเดิม) ยกเลิก request ก่อน
  //               หน้านี้ที่ยังไม่ตอบกลับก่อนยิงใหม่เสมอ กัน race condition
  // [INPUT] _search, _currentPage, _pageSize (state ปัจจุบันของหน้า)
  // [OUTPUT] อัปเดต _members/_total หรือ _hasError/_isNetworkError ตามผลลัพธ์
  // [RELATED] COMMON_UI
  // --------------------------------------------
  Future<void> _fetchMembers() async {
    _cancelToken?.cancel('superseded');
    final token = CancelToken();
    _cancelToken = token;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _isNetworkError = false;
    });

    final params = <String, String>{
      if (_search.trim().isNotEmpty) 'search': _search.trim(),
      'page': '$_currentPage',
      'page_size': '$_pageSize',
    };
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');

    try {
      final response = await _api.get('/admin/members?$query', cancelToken: token);
      if (!mounted || token.isCancelled) return;
      if (response.statusCode == 200) {
        final data = response.data as Map;
        setState(() {
          _members = (data['data'] ?? []) as List;
          _total = (data['total'] as num?)?.toInt() ?? 0;
          _isLoading = false;
        });
      } else {
        setState(() { _hasError = true; _isLoading = false; });
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return; // ถูก request ใหม่กว่าแทนที่ ไม่ต้องทำอะไร
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isNetworkError = isNetworkDioError(e);
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  // --------------------------------------------
  // [FEATURE] PROFILE
  // [FUNCTION] _clearFilters
  // [DESCRIPTION] รีเซ็ตช่องค้นหาและหน้ากลับเป็น 1 แล้วยิง API ใหม่ — ใช้ร่วมกันทั้งปุ่ม
  //               "ล้างตัวกรอง" บน AdminFilterBar และปุ่มในหน้า noResult
  // [INPUT] -
  // [OUTPUT] -
  // [RELATED] COMMON_UI
  // --------------------------------------------
  void _clearFilters() {
    setState(() {
      _search = '';
      _currentPage = 1;
    });
    _fetchMembers();
  }

  // คอลัมน์ ชื่อ/อีเมล ยืด-หดตามพื้นที่จอจริงเสมอ (50/50 ของพื้นที่ที่เหลือ) ส่วนเพศ/สมัครเมื่อ
  // กว้างคงที่พอดีเนื้อหา แบบเดียวกับตารางกิจกรรมคาร์ดิโอ/ท่าฝึกเวท (มาตรฐานเดียวกันทั้งเว็บ) —
  // กว้างไม่พอ (ต่ำกว่า min) ค่อย fallback ไปเปิด scroll แนวนอนของ AdminDataTable เอง
  static const double _genderW = 90;
  static const double _createdW = 150;
  static const double _actionW = 96;
  static const double _nameMin = 220, _emailMin = 220;

  // การ์ดสรุปด้านบน (บรีฟ P2 ข้อ 9) — เดิมมี 2 การ์ด (ทั้งหมด + สมัครใหม่ 7 วัน) คำนวณจาก
  // _members ที่โหลดมาทั้งก้อน พอเปลี่ยนเป็น server-side pagination (Flutter integration phase)
  // _members เหลือแค่ข้อมูลหน้าปัจจุบัน (page_size) คำนวณ "สมัครใหม่ 7 วัน" จากตรงนี้ต่อไปจะผิด
  // ทันที ตัดการ์ดนี้ออกก่อน (ตัดสินใจร่วมกับผู้ใช้ 2026-08-30) เหลือแค่ "ทั้งหมด" ที่ใช้ _total
  // จาก response ตรงๆ ได้ถูกต้องเสมอไม่ว่าจะอยู่หน้าไหน — จะเพิ่มสถิตินี้กลับต้องมี field ใหม่จาก
  // backend endpoint (นอกขอบเขต task นี้)
  Widget _buildSummaryCards() {
    Widget card(String label, String value, IconData icon, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
            ]),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(children: [
        card('สมาชิกทั้งหมด', '$_total', Icons.people_outline, AppColors.primaryGreen),
      ]),
    );
  }

  Widget _buildMembersTable(List<dynamic> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double reserve = 8;
        final double flexAvailable = constraints.maxWidth - _genderW - _createdW - _actionW - reserve;
        final double minFlexTotal = _nameMin + _emailMin;
        final double flexTotal = flexAvailable < minFlexTotal ? minFlexTotal : flexAvailable;
        final double nameW = (flexTotal * 0.5) < _nameMin ? _nameMin : flexTotal * 0.5;
        final double emailWRaw = flexTotal - nameW;
        final double emailW = emailWRaw < _emailMin ? _emailMin : emailWRaw;

        final columns = [
          AdminDataColumn(key: 'name', label: 'สมาชิก', width: nameW),
          AdminDataColumn(key: 'email', label: 'อีเมล', width: emailW),
          AdminDataColumn(key: 'gender', label: 'เพศ', width: _genderW),
          AdminDataColumn(key: 'created', label: 'สมัครเมื่อ', width: _createdW),
        ];

        return AdminDataTable(
          columns: columns,
          rowCount: rows.length,
          actionColumnWidth: _actionW,
          cellsBuilder: (context, index) {
            final m = rows[index];
            final name = (m['mb_full_name'] ?? '').toString();
            final email = (m['mb_email'] ?? '').toString();
            final gender = (m['mb_gender'] as num?)?.toInt();
            final createdRaw = (m['mb_created_at'] ?? '').toString();
            final createdDate = DateTime.tryParse(createdRaw);
            final avatarUrl = ApiClient.prefixPath(m['mb_profile_pic']);
            final mbId = (m['mb_id'] as num?)?.toInt() ?? 0;
            final avatarColor = _avatarColorFor(mbId);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _drillMemberId = (m['mb_id'] as num).toInt();
                _drillMemberName = name;
              }),
              child: Row(children: [
                AdminDataCell(
                  width: nameW,
                  child: Row(children: [
                    avatarUrl != null
                        ? ClipOval(
                            child: SizedBox(
                              width: 36,
                              height: 36,
                              child: AdminNetworkImage(
                                avatarUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: avatarColor.withValues(alpha: 0.15),
                                  alignment: Alignment.center,
                                  child: Text(_initialOf(name), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: avatarColor)),
                                ),
                              ),
                            ),
                          )
                        : CircleAvatar(
                            radius: 18,
                            backgroundColor: avatarColor.withValues(alpha: 0.15),
                            child: Text(_initialOf(name), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: avatarColor)),
                          ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(name.isNotEmpty ? name : '-', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87), overflow: TextOverflow.ellipsis)),
                  ]),
                ),
                AdminDataCell(width: emailW, child: Tooltip(message: email, child: Text(email, overflow: TextOverflow.ellipsis))),
                AdminDataCell(width: _genderW, child: Text(gender == 1 ? 'ชาย' : gender == 2 ? 'หญิง' : '-')),
                AdminDataCell(width: _createdW, child: Text(createdDate != null ? DateFormat('d MMM yyyy', 'th').format(createdDate) : '-')),
              ]),
            );
          },
          actionsBuilder: (context, index) {
            final m = rows[index];
            return IconButton(
              tooltip: 'ดูรายละเอียด',
              icon: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              onPressed: () => setState(() {
                _drillMemberId = (m['mb_id'] as num).toInt();
                _drillMemberName = (m['mb_full_name'] ?? '').toString();
              }),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_drillMemberId != null) {
      return MemberDetailView(
        memberId: _drillMemberId!,
        fallbackName: _drillMemberName,
        onBack: () => setState(() => _drillMemberId = null),
      );
    }
    final rows = _members;

    final AdminListState? stateOverride = _isLoading
        ? AdminListState.loading
        : _hasError
            ? AdminListState.error
            : _total == 0
                ? (_search.isNotEmpty ? AdminListState.noResult : AdminListState.empty)
                : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminPageHeader(breadcrumb: ['ผู้ใช้งาน', 'รายชื่อสมาชิก']),
        if (!_isLoading && !_hasError) _buildSummaryCards(),
        AdminFilterBar(
          searchHint: 'ค้นหาชื่อหรืออีเมล...',
          onSearchChanged: (v) {
            setState(() { _search = v; _currentPage = 1; });
            _fetchMembers();
          },
          resultCount: _total,
          showClearButton: _search.isNotEmpty,
          onClearFilters: _clearFilters,
        ),
        Expanded(
          child: stateOverride != null
              ? AdminListStateView(
                  state: stateOverride,
                  skeletonVariant: AdminSkeletonVariant.table,
                  emptyMessage: 'ยังไม่มีสมาชิกในระบบ',
                  errorMessage: _isNetworkError ? 'เชื่อมต่อไม่ได้ ตรวจสอบอินเทอร์เน็ตแล้วลองใหม่' : 'เกิดข้อผิดพลาดจากเซิร์ฟเวอร์ ลองใหม่อีกครั้ง',
                  onRetry: _fetchMembers,
                  onClearFilter: _clearFilters,
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: _buildMembersTable(rows),
                ),
        ),
        if (stateOverride == null)
          AdminPaginationBar(
            totalItems: _total,
            pageSize: _pageSize,
            currentPage: _currentPage,
            onPageSizeChanged: (v) {
              setState(() { _pageSize = v; _currentPage = 1; });
              _fetchMembers();
            },
            onPageChanged: (v) {
              setState(() => _currentPage = v);
              _fetchMembers();
            },
          ),
      ],
    );
  }
}
