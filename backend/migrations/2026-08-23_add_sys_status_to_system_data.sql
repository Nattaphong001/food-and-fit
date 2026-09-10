-- เพิ่ม sys_status ให้ system_data (ตาราง 4.1 attribute ที่ 7) เพื่อรองรับ
-- multi-admin + ปิดใช้งานบัญชี (soft-disable) แทนการลบจริง — เดิมมี admin แถวเดียว
-- ไม่มีคอลัมน์สถานะเลย ต้องเพิ่มก่อนถึงจะปิดใช้งานบัญชีได้โดยไม่ลบข้อมูลทิ้ง
-- ต้อง backup ตาราง system_data ไว้ที่ migrations/backups/ ก่อนรันไฟล์นี้จริง

ALTER TABLE system_data
  ADD COLUMN sys_status TINYINT(1) NOT NULL DEFAULT 1
  COMMENT 'สถานะบัญชีผู้ดูแลระบบ (1=ใช้งาน, 0=ปิดใช้งาน)' AFTER sys_start_date;
