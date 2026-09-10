// หน้า: Notifications
// ทำหน้าที่: แสดงรายการแจ้งเตือนทั้งหมดของผู้ใช้ เช่น แจ้งเตือนความสำเร็จ หรือการเตือนออกกำลังกาย

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../models/notification_model.dart';
import '../../../services/notification_service.dart';
import '../../../services/api_client.dart';

class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key});

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  List<AppNotification> _notifs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await NotificationService.to.getNotifications();
    if (!mounted) return;
    setState(() {
      _notifs = data;
      _loading = false;
    });
  }

  Future<void> _onTap(AppNotification n) async {
    // mark as read ทีละอัน
    if (!n.isRead) {
      await NotificationService.to.markOneRead(n.ntfId);
      if (!mounted) return;
      setState(() {
        _notifs = _notifs.map((x) => x.ntfId == n.ntfId ? x.copyWith(isRead: true) : x).toList();
      });
    }

    if (!mounted) return;

    switch (n.ntfType) {
      case 'nutrition':
        Navigator.pop(context);
        NotificationService.to.targetTab.value = 1; // NutritionView
        break;
      case 'workout':
        Navigator.pop(context);
        NotificationService.to.targetTab.value = 2; // WorkoutView
        break;
      // achievement, weekly, bell → อ่านอย่างเดียว ไม่มีหน้าเฉพาะ
    }
  }

  Future<void> _markAllRead() async {
    await NotificationService.to.markAllRead();
    if (!mounted) return;
    setState(() {
      _notifs = _notifs.map((n) => n.copyWith(isRead: true)).toList();
    });
  }

  // Group notifications by ntf_date
  Map<String, List<AppNotification>> get _grouped {
    final map = <String, List<AppNotification>>{};
    for (final n in _notifs) {
      (map[n.ntfDate] ??= []).add(n);
    }
    return map;
  }

  List<String> get _sortedDates {
    final dates = _grouped.keys.toList();
    dates.sort((a, b) => b.compareTo(a));
    return dates;
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifs.any((n) => !n.isRead);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(child: AppBackButton()),
        ),
        title: const Text('การแจ้งเตือน',
            style: AppTextStyles.pageTitle),
        centerTitle: true,
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('อ่านทั้งหมด',
                  style: TextStyle(fontSize: 13, color: AppColors.primaryGreen, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : _notifs.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: AppColors.primaryGreen,
                  onRefresh: () async {
                    ApiClient.clearCache();
                    await _load();
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _sortedDates.length,
                    itemBuilder: (context, i) {
                      final date = _sortedDates[i];
                      final items = _grouped[date]!;
                      return _buildDateGroup(date, items);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications_off_outlined, size: 36, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          const Text('ยังไม่มีการแจ้งเตือน',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDark)),
          const SizedBox(height: 6),
          const Text('เริ่มออกกำลังกายและบันทึกอาหารเพื่อรับแจ้งเตือน',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildDateGroup(String date, List<AppNotification> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
          child: Text(_formatDateLabel(date),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        ),
        ...items.map(_buildNotifCard),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildNotifCard(AppNotification n) {
    final icon = _iconFor(n.ntfIcon);
    final iconBg = _iconBgFor(n.ntfIcon);
    final iconColor = _iconColorFor(n.ntfIcon);
    return InkWell(
      onTap: () => _onTap(n),
      borderRadius: BorderRadius.circular(16),
      child: Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: n.isRead ? Colors.white : const Color(0xFFF0FFF8),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(n.ntfTitle,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
                              color: AppColors.textDark,
                            )),
                      ),
                      if (!n.isRead)
                        Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(n.ntfBody,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4)),
                  if (n.ntfType == 'nutrition' || n.ntfType == 'workout')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        n.ntfType == 'nutrition' ? 'ไปบันทึกอาหาร →' : 'ไปหน้าออกกำลังกาย →',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primaryGreen),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  String _formatDateLabel(String date) {
    try {
      final d = DateTime.parse(date);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final target = DateTime(d.year, d.month, d.day);
      final diff = today.difference(target).inDays;
      if (diff == 0) return 'วันนี้';
      if (diff == 1) return 'เมื่อวาน';
      final thMonths = ['', 'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
      return '${d.day} ${thMonths[d.month]} ${d.year + 543}';
    } catch (_) {
      return date;
    }
  }

  IconData _iconFor(String icon) {
    switch (icon) {
      case 'nutrition': return Icons.restaurant_rounded;
      case 'workout': return Icons.fitness_center_rounded;
      case 'achievement': return Icons.emoji_events_rounded;
      case 'weekly': return Icons.bar_chart_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _iconBgFor(String icon) {
    switch (icon) {
      case 'nutrition': return const Color(0xFFFFF3E0);
      case 'workout': return const Color(0xFFE8F5E9);
      case 'achievement': return const Color(0xFFFFF9C4);
      case 'weekly': return const Color(0xFFE3F2FD);
      default: return AppColors.surfaceLight;
    }
  }

  Color _iconColorFor(String icon) {
    switch (icon) {
      case 'nutrition': return const Color(0xFFF57C00);
      case 'workout': return AppColors.primaryGreen;
      case 'achievement': return const Color(0xFFF9A825);
      case 'weekly': return const Color(0xFF1976D2);
      default: return AppColors.textMuted;
    }
  }
}
