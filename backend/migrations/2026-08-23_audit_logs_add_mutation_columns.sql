-- Item 9 (S-9) ต่อ: audit_logs เดิมมีแค่ actor_type/actor_id/action/detail(string)/ip_address
-- ไม่พอสำหรับ "old_value/new_value" ตามสเปก (เดิมยัดสรุปสั้นๆ ไว้ใน detail อย่างเดียว)
-- เพิ่ม 4 คอลัมน์ใหม่แบบ nullable — ไม่แตะ/ไม่ลบคอลัมน์เดิม (detail ยังคงเก็บ backward-compat summary)
-- ปลอดภัยกับแถวเก่า: ทุกคอลัมน์ใหม่ NULL ได้ ไม่มี NOT NULL / ไม่มี default บังคับ

ALTER TABLE audit_logs
  ADD COLUMN table_name VARCHAR(64)  NULL AFTER detail,
  ADD COLUMN record_id  VARCHAR(64)  NULL AFTER table_name,
  ADD COLUMN old_value  JSON         NULL AFTER record_id,
  ADD COLUMN new_value  JSON         NULL AFTER old_value;

ALTER TABLE audit_logs ADD INDEX idx_audit_table_record (table_name, record_id);
