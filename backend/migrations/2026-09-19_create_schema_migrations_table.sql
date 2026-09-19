-- สร้างตาราง schema_migrations — ตารางติดตามว่าไฟล์ migration ไหนรันไปแล้วบ้าง
--
-- เหตุผล: โปรเจกต์นี้รัน migration ด้วยมือทุกไฟล์ผ่าน `mysql -e "source ..."` (ไม่มี framework/
-- migration runner) ไม่เคยมีตารางติดตามมาก่อน (.claude/skills/mysql-schema ยืนยัน 2026-09-17) —
-- เคยเกิดบั๊กจริงจากเรื่องนี้: migration `2026-09-17_add_weight_training_met_code.sql` เขียนไฟล์
-- เสร็จ ผ่าน go build/test หมด แต่ไม่เคยถูกรันจริง ทำให้ SaveWorkoutResult พังเงียบๆ นานหลายวัน
-- โดยไม่มีระบบไหนเตือน — ตารางนี้ไม่ได้ป้องกันบั๊กแบบนั้นอัตโนมัติ (ยังต้องรันมือเหมือนเดิม) แต่
-- ให้มีที่เดียวเช็คได้ว่า "ไฟล์นี้เคยรันบน DB เครื่องนี้หรือยัง" แทนการเดา/ไล่ query schema เอง
--
-- ตั้งใจให้เรียบง่ายที่สุด (ไม่ทำ auto-runner เพราะไม่คุ้มสำหรับโปรเจกต์เดี่ยว/เล่มจบ) — filename
-- เป็น PK ตรงๆ ตรงกับชื่อไฟล์จริงใน backend/migrations/ (ไม่รวม backups/) เวลารัน migration ใหม่
-- ให้ INSERT แถวนี้เข้าไปเองท้ายไฟล์ migration นั้น (ดูตัวอย่างการ backfill ด้านล่าง)

CREATE TABLE IF NOT EXISTS schema_migrations (
  filename   varchar(255) NOT NULL COMMENT 'ชื่อไฟล์ migration ตรงกับใน backend/migrations/ เป๊ะ',
  applied_at datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'เวลาที่รัน migration นี้บน DB เครื่องนี้',
  note       varchar(255) DEFAULT NULL COMMENT 'หมายเหตุเพิ่มเติม (เช่น backfill ประมาณเวลาจาก file mtime)',
  PRIMARY KEY (filename)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='ติดตามว่าไฟล์ backend/migrations/*.sql ไหนรันไปแล้วบน DB เครื่องนี้ (รันมือ ไม่มี auto-runner)';

-- Backfill: ไฟล์ migration ที่มีอยู่จริงตอนสร้างตารางนี้ (2026-09-19) และยืนยันแล้วว่าผลของมันมีอยู่
-- ใน schema/ข้อมูลจริงของ DB เครื่องนี้ (ตรวจทีละไฟล์ผ่าน SHOW COLUMNS/ข้อมูลจริง ไม่ใช่เดา) —
-- applied_at ของ 4 แถวแรกเป็นการประมาณจาก file mtime (ไม่ทราบเวลารันจริงเป๊ะ) ส่วน 2 แถวสุดท้าย
-- เป็นเวลารันจริงวันนี้ FORMULAS_AND_LOGIC.sql ไม่รวมในนี้ — เป็นไฟล์เอกสารอ้างอิงสูตร (คอมเมนต์ล้วน
-- ไม่มี DDL/DML ให้รัน) ไม่ใช่ migration จริง
INSERT INTO schema_migrations (filename, applied_at, note) VALUES
  ('2026-09-14_cardio_duration_to_seconds.sql', '2026-09-14 06:08:00',
    'backfill — ประมาณจาก file mtime, ยืนยันผลจริงจาก cdors_duration range ปัจจุบัน (60-2700 วินาที)'),
  ('2026-09-18_add_weight_training_rest_seconds.sql', '2026-09-18 04:48:00',
    'backfill — ประมาณจาก file mtime, ยืนยันคอลัมน์ wtrs_rest_seconds มีอยู่จริง'),
  ('2026-09-19_drop_wet_base_met.sql', '2026-09-18 20:52:00',
    'backfill — ประมาณจาก file mtime, ยืนยัน weight_exercises.wet_base_met ไม่มีอยู่แล้ว'),
  ('2026-09-19_fix_cardio_result_duration_minutes_to_seconds.sql', '2026-09-18 21:58:00',
    'backfill — ประมาณจาก file mtime, ยืนยันจาก cdors_duration range ปัจจุบันตรงกับที่ migration นี้คาดไว้ (900-2700 ในกลุ่มข้อมูล demo เดิม)'),
  ('2026-09-19_repair_audit_logs_orphaned_tablespace.sql', NOW(),
    'รันจริงวันนี้ — ซ่อม orphaned tablespace, ยืนยัน AutoMigrate สร้างตารางใหม่สำเร็จ'),
  ('2026-09-19_fix_audit_logs_collation_after_recreate.sql', NOW(),
    'รันจริงวันนี้ — แก้ collation ที่เพี้ยนหลัง AutoMigrate recreate, ยืนยัน utf8mb4_unicode_ci ตรงกับตารางอื่นทั้งหมด (D6)');

-- Rollback:
-- DROP TABLE IF EXISTS schema_migrations;
