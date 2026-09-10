// ignore_for_file: use_build_context_synchronously

// [PAGE] ADMIN_MANAGE_ADMINS : จัดการผู้ดูแลระบบ (เว็บ)
// [PAGE_PURPOSE] เพิ่มบัญชีผู้ดูแลระบบ (multi-admin) — แอดมินทุกบัญชีสิทธิ์เท่ากัน ไม่มีการ
//                ปิดใช้งานบัญชี/สถานะจากหน้านี้ (ตัดออก 2026-09-01 ตามมติ: ไม่มีลำดับชั้นสิทธิ์
//                ระหว่างแอดมิน จึงไม่มีบัญชีไหน "ปิด" บัญชีอื่นได้)
// [PAGE_ROUTE] /admin > จัดการข้อมูลพื้นฐาน > ผู้ดูแลระบบ > จัดการผู้ดูแลระบบ

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/admin_data_table.dart';
import '../../../core/widgets/admin_filter_bar.dart';
import '../../../core/widgets/admin_list_state.dart';
import '../../../core/widgets/admin_page_header.dart';
import '../../../core/widgets/admin_pagination_bar.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../services/api_client.dart';

class ManageAdminsView extends StatefulWidget {
  const ManageAdminsView({super.key});

  @override
  State<ManageAdminsView> createState() => _ManageAdminsViewState();
}

class _ManageAdminsViewState extends State<ManageAdminsView> {
  final ApiClient _api = ApiClient();

  List<dynamic> _admins = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _search = '';
  int _pageSize = kAdminPageSizeOptions[1];
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _fetchAdmins();
  }

  List<dynamic> get _filtered {
    if (_search.trim().isEmpty) return _admins;
    final q = _search.trim().toLowerCase();
    return _admins.where((a) {
      final name = (a['sys_full_name'] ?? '').toString().toLowerCase();
      final email = (a['sys_email'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  Future<void> _fetchAdmins() async {
    setState(() => _hasError = false);
    try {
      final response = await _api.get('/admin/admins', forceRefresh: true);
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = response.data as Map;
        setState(() {
          _admins = (data['data'] ?? []) as List;
          _isLoading = false;
        });
      } else {
        setState(() { _hasError = true; _isLoading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  Future<void> _showCreateForm() async {
    final result = await showAdminDialog<Map<String, dynamic>>(
      context,
      builder: (_) => const _AddAdminDialog(),
    );
    if (result == null) return;

    try {
      final response = await _api.post('/admin/admins', result);
      if (!mounted) return;
      if (response.statusCode == 201) {
        await _fetchAdmins();
        if (!mounted) return;
        await showAppNoticeDialog(
          context,
          icon: Icons.vpn_key_rounded,
          title: 'สร้างบัญชีสำเร็จ',
          content: 'อีเมล: ${result['email']}\nรหัสผ่าน: ${result['password']}\n\n'
              'กรุณาแจ้งรหัสผ่านนี้แก่เจ้าของบัญชีโดยตรง (นอกระบบ) ระบบจะไม่ส่งอีเมลหรือ OTP ใดๆ ให้',
          color: AppColors.success,
        );
      } else {
        final msg = response.data is Map
            ? (response.data['error'] ?? 'สร้างบัญชีไม่สำเร็จ')
            : 'สร้างบัญชีไม่สำเร็จ';
        showAppAlert(context, msg.toString(), type: AppAlertType.error);
      }
    } catch (e) {
      if (mounted) showAppAlert(context, 'เกิดข้อผิดพลาด: $e', type: AppAlertType.error);
    }
  }

  // คอลัมน์วันที่เป็นเนื้อหาสั้นตายตัว กว้างคงที่พอดีเนื้อหา ส่วน อีเมล/ชื่อ/หน่วยงาน
  // ยืด-หดตามพื้นที่จอจริงเสมอ (สัดส่วน 38/32/30% ของพื้นที่ที่เหลือ) ให้ตารางเต็มความกว้างจอ
  // เหมือนหน้าตารางอื่น (ท่าฝึกเวท/อาหาร/คาร์ดิโอ) แทนที่จะกว้างคงที่แล้วเหลือช่องว่างขวาจอกว้าง
  static const double _startW = 150;
  static const double _emailMin = 220, _nameMin = 180, _orgMin = 160;

  @override
  Widget build(BuildContext context) {
    final allRows = _filtered;
    final totalPages = allRows.isEmpty ? 1 : ((allRows.length - 1) ~/ _pageSize) + 1;
    final safePage = _currentPage > totalPages ? totalPages : _currentPage;
    final rows = allRows.skip((safePage - 1) * _pageSize).take(_pageSize).toList();

    final AdminListState? stateOverride = _isLoading
        ? AdminListState.loading
        : _hasError
            ? AdminListState.error
            : allRows.isEmpty
                ? (_search.isNotEmpty ? AdminListState.noResult : AdminListState.empty)
                : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          breadcrumb: const ['ผู้ดูแลระบบ', 'รายชื่อผู้ดูแลระบบ'],
          onAdd: _showCreateForm,
          addLabel: 'เพิ่มผู้ดูแลระบบ',
        ),
        AdminFilterBar(
          searchHint: 'ค้นหาชื่อหรืออีเมล...',
          onSearchChanged: (v) => setState(() { _search = v; _currentPage = 1; }),
          resultCount: allRows.length,
        ),
        Expanded(
          child: stateOverride != null
              ? AdminListStateView(
                  state: stateOverride,
                  skeletonVariant: AdminSkeletonVariant.table,
                  emptyMessage: 'ยังไม่มีผู้ดูแลระบบในระบบ',
                  onAdd: _showCreateForm,
                  onRetry: _fetchAdmins,
                  onClearFilter: () => setState(() { _search = ''; _currentPage = 1; }),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const reserve = 8;
                      final flexAvailable = constraints.maxWidth - _startW - reserve;
                      final minFlexTotal = _emailMin + _nameMin + _orgMin;
                      final flexTotal = flexAvailable < minFlexTotal ? minFlexTotal : flexAvailable;
                      final emailW = (flexTotal * 0.38) < _emailMin ? _emailMin : flexTotal * 0.38;
                      final nameW = (flexTotal * 0.32) < _nameMin ? _nameMin : flexTotal * 0.32;
                      final orgWRaw = flexTotal - emailW - nameW;
                      final orgW = orgWRaw < _orgMin ? _orgMin : orgWRaw;

                      return AdminDataTable(
                        columns: [
                          AdminDataColumn(key: 'email', label: 'อีเมล', width: emailW),
                          AdminDataColumn(key: 'name', label: 'ชื่อ-นามสกุล', width: nameW),
                          AdminDataColumn(key: 'org', label: 'หน่วยงาน', width: orgW),
                          const AdminDataColumn(key: 'start', label: 'วันที่เริ่มใช้งาน', width: _startW),
                        ],
                        rowCount: rows.length,
                        // ไม่มีปุ่มแก้ไข/ปิดใช้งานอีกแล้ว (แอดมินทุกคนสิทธิ์เท่ากัน) — ไม่มีคอลัมน์ action
                        actionColumnWidth: 0,
                        actionColumnLabel: '',
                        cellsBuilder: (context, index) {
                          final a = rows[index];
                          final email = (a['sys_email'] ?? '').toString();
                          final name = (a['sys_full_name'] ?? '').toString();
                          final org = (a['sys_organization'] ?? '-').toString();
                          final startRaw = (a['sys_start_date'] ?? '').toString();
                          final startDate = DateTime.tryParse(startRaw);

                          return Row(children: [
                            AdminDataCell(width: emailW, child: Tooltip(message: email, child: Text(email, overflow: TextOverflow.ellipsis))),
                            AdminDataCell(width: nameW, child: Text(name.isNotEmpty ? name : '-', overflow: TextOverflow.ellipsis)),
                            AdminDataCell(width: orgW, child: Text(org.isNotEmpty ? org : '-', overflow: TextOverflow.ellipsis)),
                            AdminDataCell(width: _startW, child: Text(startDate != null ? DateFormat('d MMM yyyy', 'th').format(startDate) : '-')),
                          ]);
                        },
                        actionsBuilder: (context, index) => const SizedBox.shrink(),
                      );
                    },
                  ),
                ),
        ),
        if (stateOverride == null)
          AdminPaginationBar(
            totalItems: allRows.length,
            pageSize: _pageSize,
            currentPage: safePage,
            onPageSizeChanged: (v) => setState(() { _pageSize = v; _currentPage = 1; }),
            onPageChanged: (v) => setState(() => _currentPage = v),
          ),
      ],
    );
  }
}

// ฟอร์มเพิ่มผู้ดูแลระบบใหม่ — รหัสผ่านตั้งโดยแอดมินที่เพิ่มเอง แล้วส่งมอบให้เจ้าของบัญชีโดยตรง
// นอกระบบ (ไม่มี OTP/อีเมลยืนยันเหมือนฝั่งสมาชิก)
class _AddAdminDialog extends StatefulWidget {
  const _AddAdminDialog();

  @override
  State<_AddAdminDialog> createState() => _AddAdminDialogState();
}

class _AddAdminDialogState extends State<_AddAdminDialog> {
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _orgCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _orgCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _emailCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'กรุณากรอกอีเมลให้ถูกต้อง');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'กรุณากรอกชื่อ-นามสกุล');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร');
      return;
    }

    Navigator.pop(context, {
      'email': email,
      'full_name': name,
      'organization': _orgCtrl.text.trim().isEmpty ? null : _orgCtrl.text.trim(),
      'password': password,
    });
  }

  InputDecoration _deco({String? hint, IconData? icon}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        prefixIcon: icon != null ? Icon(icon, color: AppColors.primary, size: 18) : null,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.of(context).size.height - 80,
        ),
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(children: [
                  Container(width: 4, height: 20, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('เพิ่มผู้ดูแลระบบ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),
                  IconButton(icon: Icon(Icons.close, color: Colors.grey.shade400, size: 20), onPressed: () => Navigator.pop(context)),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('อีเมล *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                  const SizedBox(height: 6),
                  TextField(controller: _emailCtrl, decoration: _deco(hint: 'เช่น admin@example.com', icon: Icons.email_outlined)),
                  const SizedBox(height: 14),
                  const Text('ชื่อ-นามสกุล *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                  const SizedBox(height: 6),
                  TextField(controller: _nameCtrl, decoration: _deco(hint: 'ชื่อ-นามสกุล', icon: Icons.person_outline)),
                  const SizedBox(height: 14),
                  const Text('หน่วยงาน', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                  const SizedBox(height: 6),
                  TextField(controller: _orgCtrl, decoration: _deco(hint: 'หน่วยงานเจ้าของระบบ (ถ้ามี)', icon: Icons.business_outlined)),
                  const SizedBox(height: 14),
                  const Text('รหัสผ่าน * (อย่างน้อย 8 ตัวอักษร)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: _deco(hint: 'ตั้งรหัสผ่านให้บัญชีนี้', icon: Icons.lock_outline).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: AppColors.textMuted),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(fontSize: 12.5, color: AppColors.dangerText)),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'ระบบจะไม่ส่งรหัสผ่านนี้ให้เจ้าของบัญชีเอง — หลังสร้างสำเร็จ กรุณาแจ้งรหัสผ่านนี้แก่เจ้าของบัญชีโดยตรง',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _submit,
                      child: const Text('สร้างบัญชี', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
