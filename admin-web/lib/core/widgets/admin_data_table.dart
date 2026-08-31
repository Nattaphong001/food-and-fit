// AdminDataTable — ตารางกลางของหน้าจัดการข้อมูล Admin (จอกว้าง)
// แทนที่ DataTable ดิบที่เคยเขียนซ้ำแยกไฟล์ ให้พฤติกรรมตรงตามสเปกจอกว้างของทุกหน้า:
//   - header sticky ตอนเลื่อนแนวตั้ง (อยู่นอก vertical scroll ของแถวข้อมูล)
//   - คอลัมน์ "จัดการ" ปักไว้ขวาสุดเสมอ แม้เลื่อนแนวนอน
//   - เส้นคั่นบางระหว่างแถว (AppColors.border) แยกแถวแทนการสลับสีพื้น
//   - ตัวเลขชิดขวา ข้อความชิดซ้าย ตาม AdminDataColumn.numeric
//   - คลิกหัวคอลัมน์ที่ sortable = true เพื่อสลับ asc/desc พร้อมลูกศรบอกทิศทาง
//
// เทคนิค sync scroll (ไม่พึ่ง package ไหน): แกนหลักแต่ละแกนมี ScrollController ตัวขับ (interactive)
// ตัวเดียว ส่วนตัวตาม (follower) ใช้ NeverScrollableScrollPhysics + listener คอย jumpTo ให้ offset
// ตรงกันเสมอ — เพราะ ScrollController ตัวเดียวที่ attach หลาย Scrollable ไม่ได้ sync กันอัตโนมัติ
// เวลาผู้ใช้ลากแค่อันเดียว (ข้อจำกัดจริงของ Flutter) จึงต้องมี listener sync มือเอง
//
// ทุกคอลัมน์ต้องมี width คงที่ (จำเป็นสำหรับเทคนิคนี้)

import 'package:flutter/material.dart';
import '../theme/theme.dart';

class AdminDataColumn {
  final String key;
  final String label;
  final double width;
  final bool numeric;
  final bool sortable;

  const AdminDataColumn({
    required this.key,
    required this.label,
    required this.width,
    this.numeric = false,
    this.sortable = false,
  });
}

class AdminDataTable extends StatefulWidget {
  final List<AdminDataColumn> columns;
  final int rowCount;
  final Widget Function(BuildContext context, int rowIndex) cellsBuilder;
  final Widget Function(BuildContext context, int rowIndex) actionsBuilder;
  final String? sortKey;
  final bool sortAscending;
  final ValueChanged<String>? onSort;
  final double actionColumnWidth;
  final double rowHeight;

  const AdminDataTable({
    super.key,
    required this.columns,
    required this.rowCount,
    required this.cellsBuilder,
    required this.actionsBuilder,
    this.sortKey,
    this.sortAscending = true,
    this.onSort,
    this.actionColumnWidth = 96,
    this.rowHeight = 56,
  });

  @override
  State<AdminDataTable> createState() => _AdminDataTableState();
}

class _AdminDataTableState extends State<AdminDataTable> {
  // แกนนอน: body คือตัวขับ, header คือตัวตาม
  final ScrollController _hBody = ScrollController();
  final ScrollController _hHeader = ScrollController();
  // แกนตั้ง: body คือตัวขับ, actions column คือตัวตาม
  final ScrollController _vBody = ScrollController();
  final ScrollController _vActions = ScrollController();

  // index แถวที่ mouse hover อยู่ (dataArea หรือ actionsArea ก็ได้ ไกด์ทั้งคู่ให้ sync สีกัน) —
  // ไฮไลต์ทั้งแถว + cursor pointer ตามมาตรฐานตารางทั่วไป
  int? _hoveredIndex;
  static const _rowDividerColor = Color(0xFFF1F3F5);

  double get _tableWidth => widget.columns.fold<double>(0, (sum, c) => sum + c.width);

  @override
  void initState() {
    super.initState();
    _hBody.addListener(_syncHorizontal);
    _vBody.addListener(_syncVertical);
  }

  void _syncHorizontal() {
    if (_hHeader.hasClients && _hHeader.offset != _hBody.offset) {
      _hHeader.jumpTo(_hBody.offset.clamp(0, _hHeader.position.maxScrollExtent));
    }
  }

  void _syncVertical() {
    if (_vActions.hasClients && _vActions.offset != _vBody.offset) {
      _vActions.jumpTo(_vBody.offset.clamp(0, _vActions.position.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    _hBody.removeListener(_syncHorizontal);
    _vBody.removeListener(_syncVertical);
    _hBody.dispose();
    _hHeader.dispose();
    _vBody.dispose();
    _vActions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // ถ้าคอลัมน์รวมกันแคบกว่าพื้นที่ที่มี ให้ตารางหุบตามความกว้างจริง (คอลัมน์ "จัดการ" ชิดคอลัมน์
        // สุดท้ายทันที ไม่ปักที่ขอบ container) แทนที่จะยืด data area เต็มจอแล้วเหลือช่องว่างคั่นก่อนคอลัมน์
        // "จัดการ" — ช่องว่างนั้นเดิมทำให้ zebra stripe ขาดเป็น 2 ท่อนที่กึ่งกลางจอด้วย
        //
        // หัก _borderInset (เส้นขอบ container ซ้าย+ขวารวม 2px) ออกจากพื้นที่ใช้ได้ก่อนเทียบ — Container
        // ด้านล่างมี BoxDecoration.border แบบ uniform ซึ่ง Flutter ใส่ padding ให้ child อัตโนมัติเท่ากับ
        // ความหนาเส้นขอบ (ดู BoxDecoration.padding) ถ้าไม่หักตรงนี้ ตอนคอลัมน์รวมกันพอดีเป๊ะกับ maxWidth
        // (เช่นหน้าที่คำนวณคอลัมน์แบบ responsive ให้เต็มความกว้างพอดี) จะเกิด "RIGHT OVERFLOWED BY 2.0
        // PIXELS" เพราะพื้นที่จริงข้างในแคบกว่าที่ widget เห็นตอนคำนวณ needsHorizontalScroll อยู่ 2px
        const borderInset = 2.0;
        final needsHorizontalScroll = _tableWidth + widget.actionColumnWidth > constraints.maxWidth - borderInset;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeaderRow(needsHorizontalScroll),
              const Divider(height: 1, color: AppColors.border),
              Expanded(child: _buildBody(needsHorizontalScroll)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(bool needsHorizontalScroll) {
    // dataListView ไม่มี Scrollbar ของตัวเอง — ห่อ Scrollbar แนวตั้งไว้ชั้นนอกสุดรอบทั้ง Row
    // (dataListView + actionsArea) แทน เพื่อให้แท่งเลื่อนไปอยู่ขอบขวาสุดจริงของตาราง หลังคอลัมน์
    // "จัดการ" ไม่ใช่โผล่มาคั่นอยู่ก่อนคอลัมน์ "จัดการ" แบบเดิม (Scrollbar วาดที่ขอบขวาของ child
    // มันเอง — ถ้าห่อแค่ dataArea แท่งจะไปโผล่ตรงขอบขวาของ dataArea แทนที่จะเป็นขอบขวาของตาราง)
    final dataListView = SizedBox(
      width: _tableWidth,
      child: ListView.builder(
        controller: _vBody,
        itemCount: widget.rowCount,
        itemExtent: widget.rowHeight,
        itemBuilder: (context, index) => _buildDataRowContent(context, index),
      ),
    );
    final actionsArea = SizedBox(
      width: widget.actionColumnWidth,
      child: ListView.builder(
        controller: _vActions,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: widget.rowCount,
        itemExtent: widget.rowHeight,
        itemBuilder: (context, index) => _HoverableRow(
          hovered: _hoveredIndex == index,
          onHoverChange: (v) => setState(() => _hoveredIndex = v ? index : (_hoveredIndex == index ? null : _hoveredIndex)),
          child: Container(
            decoration: BoxDecoration(
              border: const Border(bottom: BorderSide(color: _rowDividerColor, width: 1)),
            ),
            alignment: Alignment.center,
            child: widget.actionsBuilder(context, index),
          ),
        ),
      ),
    );

    final Widget combined = needsHorizontalScroll
        ? Row(
            children: [
              Expanded(
                child: Scrollbar(
                  controller: _hBody,
                  notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _hBody,
                    scrollDirection: Axis.horizontal,
                    child: dataListView,
                  ),
                ),
              ),
              actionsArea,
            ],
          )
        : Row(children: [dataListView, actionsArea]);

    return Scrollbar(controller: _vBody, child: combined);
  }

  Widget _buildHeaderRow(bool needsHorizontalScroll) {
    final dataHeader = SizedBox(
      width: _tableWidth,
      child: Row(children: widget.columns.map(_buildHeaderCell).toList()),
    );
    final actionsHeader = SizedBox(
      width: widget.actionColumnWidth,
      height: 48,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          // เดิม centerLeft แต่ actionsArea (แถวข้อมูล) จัด icon ไว้กึ่งกลางคอลัมน์ (alignment: Alignment.center
          // ใน _buildBody) ทำให้หัวคอลัมน์ "จัดการ" เยื้องซ้ายไม่ตรงกับปุ่มด้านล่าง — เปลี่ยนให้กึ่งกลางตรงกัน
          alignment: Alignment.center,
          child: Text('จัดการ', style: AppTextStyles.tableHeader, maxLines: 1, softWrap: false, overflow: TextOverflow.visible),
        ),
      ),
    );

    return Container(
      color: AppColors.surfaceHover,
      child: needsHorizontalScroll
          ? Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: _hHeader,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: dataHeader,
                  ),
                ),
                actionsHeader,
              ],
            )
          : Row(children: [dataHeader, actionsHeader]),
    );
  }

  Widget _buildHeaderCell(AdminDataColumn col) {
    final isActive = widget.sortKey == col.key;
    final content = Row(
      mainAxisAlignment: col.numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Text(col.label, style: AppTextStyles.tableHeader),
        if (col.sortable) ...[
          const SizedBox(width: 2),
          Icon(
            isActive ? (widget.sortAscending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
            size: 14,
            color: isActive ? AppColors.primary : AppColors.textMuted,
          ),
        ],
      ],
    );

    return SizedBox(
      width: col.width,
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: col.numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: col.sortable
              ? InkWell(onTap: () => widget.onSort?.call(col.key), child: content)
              : content,
        ),
      ),
    );
  }

  Widget _buildDataRowContent(BuildContext context, int index) {
    return _HoverableRow(
      hovered: _hoveredIndex == index,
      onHoverChange: (v) => setState(() => _hoveredIndex = v ? index : (_hoveredIndex == index ? null : _hoveredIndex)),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _rowDividerColor, width: 1)),
        ),
        child: widget.cellsBuilder(context, index),
      ),
    );
  }
}

// ไฮไลต์ทั้งแถว (พื้นหลังเปลี่ยนตอน hover) + cursor pointer — ใช้ร่วมกันทั้ง dataArea/actionsArea
// เพื่อให้ 2 ListView คนละตัว (แยกกันเพราะ sync scroll คนละแกน) เห็นแถวเดียวกันไฮไลต์พร้อมกัน
class _HoverableRow extends StatelessWidget {
  final bool hovered;
  final ValueChanged<bool> onHoverChange;
  final Widget child;

  const _HoverableRow({required this.hovered, required this.onHoverChange, required this.child});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChange(true),
      onExit: (_) => onHoverChange(false),
      child: ColoredBox(
        color: hovered ? AppColors.surfaceHover : AppColors.surface,
        child: child,
      ),
    );
  }
}

// AdminDataCell — helper สร้าง cell เดี่ยวให้ตรง width/alignment ของ AdminDataColumn
// ใช้ประกอบ Row ใน cellsBuilder ของแต่ละหน้า
class AdminDataCell extends StatelessWidget {
  final double width;
  final bool numeric;
  final Widget child;

  const AdminDataCell({super.key, required this.width, this.numeric = false, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        ),
      ),
    );
  }
}
