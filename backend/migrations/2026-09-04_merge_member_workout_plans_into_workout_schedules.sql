-- รวม member_workout_plans เข้า workout_schedules (ตัดสินใจ 2026-09-04: เลิกใช้ตารางแยก
-- เพราะ 1:1 กับสมาชิกอยู่แล้ว — เก็บข้อมูลแผนซ้ำในทุกแถวท่าฝึกของแผนเดียวกันแทน)
-- แถวที่ wet_id IS NULL (wsch_day_number = 0) คือ "หัวแผน" (plan header) — ใช้ตอนสมาชิกสร้าง
-- แผนส่วนตัวเปล่าๆ ยังไม่มีท่า ต้องมีที่เก็บ wsch_plan_name/wsch_days_per_week ไว้ก่อน
--
-- Backup ก่อนรัน: migrations/backups/backup_full_before_mwp_merge_20260904_201921.sql
-- Rollback: mysql -u root food_and_fit_db < migrations/backups/backup_full_before_mwp_merge_20260904_201921.sql

-- STEP 1: เพิ่มคอลัมน์ใหม่ (nullable ชั่วคราวเพื่อ backfill)
ALTER TABLE workout_schedules
  ADD COLUMN wsch_plan_name varchar(100) DEFAULT NULL COMMENT 'ชื่อแผนที่สมาชิกกำหนด' AFTER wsch_id,
  ADD COLUMN wsch_days_per_week tinyint(4) DEFAULT NULL COMMENT 'จำนวนวันที่ฝึกต่อสัปดาห์ (1-7)' AFTER wsch_plan_name,
  ADD COLUMN wsch_plan_created_at datetime DEFAULT current_timestamp() COMMENT 'วันเวลาที่สร้างแผน' AFTER wsch_order,
  ADD COLUMN wsch_plan_updated_at datetime DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'วันเวลาที่ปรับปรุงแผนล่าสุด' AFTER wsch_plan_created_at,
  ADD COLUMN mb_id int(11) DEFAULT NULL COMMENT 'รหัสสมาชิกเจ้าของแผน [FK -> member_profile] 1 คนมีได้ 1 แผน' AFTER wsch_plan_updated_at,
  ADD COLUMN wpt_id int(10) unsigned DEFAULT NULL COMMENT 'แม่แบบต้นทางที่คัดลอกมา [FK -> workout_plan_template] NULL = สร้างเอง' AFTER mb_id;

-- STEP 2: backfill จาก member_workout_plans ผ่าน mwp_id เดิม
UPDATE workout_schedules ws
JOIN member_workout_plans mwp ON ws.mwp_id = mwp.mwp_id
SET ws.mb_id = mwp.mb_id,
    ws.wpt_id = mwp.mwp_source_wpt_id,
    ws.wsch_plan_name = mwp.mwp_name,
    ws.wsch_days_per_week = mwp.mwp_days_per_week,
    ws.wsch_plan_created_at = mwp.mwp_created_at,
    ws.wsch_plan_updated_at = mwp.mwp_updated_at;

-- STEP 3: ลบ FK/UNIQUE เดิมที่ผูกกับ mwp_id แล้วลบคอลัมน์ mwp_id ทิ้ง
ALTER TABLE workout_schedules
  DROP FOREIGN KEY fk_wsch_mwp,
  DROP INDEX uq_wsch_plan_day_order,
  DROP COLUMN mwp_id;

-- STEP 4: บังคับ NOT NULL คอลัมน์ที่ทุกแถวต้องมีค่าแล้ว (backfill ครบจาก STEP 2)
ALTER TABLE workout_schedules
  MODIFY COLUMN wsch_plan_name varchar(100) NOT NULL COMMENT 'ชื่อแผนที่สมาชิกกำหนด',
  MODIFY COLUMN wsch_days_per_week tinyint(4) NOT NULL DEFAULT 3 COMMENT 'จำนวนวันที่ฝึกต่อสัปดาห์ (1-7)',
  MODIFY COLUMN mb_id int(11) NOT NULL COMMENT 'รหัสสมาชิกเจ้าของแผน [FK -> member_profile] 1 คนมีได้ 1 แผน';

-- STEP 5: เพิ่ม UNIQUE/FK ชุดใหม่อิง mb_id ตรงๆ (แทน mwp_id เดิม)
ALTER TABLE workout_schedules
  ADD UNIQUE KEY uq_wsch_plan_day_order (mb_id, wsch_day_number, wsch_order),
  ADD CONSTRAINT fk_wsch_member FOREIGN KEY (mb_id) REFERENCES member_profile (mb_id) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT fk_wsch_wpt FOREIGN KEY (wpt_id) REFERENCES workout_plan_template (wpt_id) ON DELETE SET NULL ON UPDATE CASCADE;

-- STEP 6: ปรับความหมาย/คอมเมนต์ wsch_day_number, wet_id ให้ตรงดีไซน์ใหม่ (0 = หัวแผน ยังไม่มีท่า)
ALTER TABLE workout_schedules
  MODIFY COLUMN wsch_day_number tinyint(4) NOT NULL DEFAULT 0 COMMENT 'วันที่เท่าใดของแผน (1-7, 0=หัวแผน ยังไม่ผูกกับวันฝึก)',
  MODIFY COLUMN wet_id int(10) unsigned DEFAULT NULL COMMENT 'รหัสท่าฝึกเวท [FK -> weight_exercises] NULL = แถวหัวแผน (ยังไม่มีท่า)';

-- STEP 7: จัดลำดับคอลัมน์ตามหน้า UI (ตั้งชื่อแผน → จำนวนวัน → วันฝึก → ท่า/เซต/เวลาพัก → เวลาบันทึก)
-- แล้วให้ FK อยู่ท้ายสุดเสมอ (mb_id, wpt_id, wet_id)
ALTER TABLE workout_schedules
  MODIFY COLUMN wsch_plan_name varchar(100) NOT NULL COMMENT 'ชื่อแผนที่สมาชิกกำหนด' AFTER wsch_id,
  MODIFY COLUMN wsch_days_per_week tinyint(4) NOT NULL DEFAULT 3 COMMENT 'จำนวนวันที่ฝึกต่อสัปดาห์ (1-7)' AFTER wsch_plan_name,
  MODIFY COLUMN wsch_day_number tinyint(4) NOT NULL DEFAULT 0 COMMENT 'วันที่เท่าใดของแผน (1-7, 0=หัวแผน ยังไม่ผูกกับวันฝึก)' AFTER wsch_days_per_week,
  MODIFY COLUMN wsch_day_name varchar(50) DEFAULT NULL COMMENT 'ชื่อเรียกวัน เช่น Push Day, Upper Body' AFTER wsch_day_number,
  MODIFY COLUMN wsch_order tinyint(4) NOT NULL DEFAULT 1 COMMENT 'ลำดับท่าฝึกภายในวันนั้น' AFTER wsch_day_name,
  MODIFY COLUMN wsch_sets tinyint(4) NOT NULL DEFAULT 3 COMMENT 'จำนวนเซตที่กำหนด' AFTER wsch_order,
  MODIFY COLUMN wsch_reps varchar(20) NOT NULL DEFAULT '10' COMMENT 'จำนวนครั้งที่กำหนด เช่น 8-12' AFTER wsch_sets,
  MODIFY COLUMN wsch_rest_seconds smallint(6) NOT NULL DEFAULT 90 COMMENT 'เวลาพักระหว่างเซต (วินาที)' AFTER wsch_reps,
  MODIFY COLUMN wsch_plan_created_at datetime DEFAULT current_timestamp() COMMENT 'วันเวลาที่สร้างแผน' AFTER wsch_rest_seconds,
  MODIFY COLUMN wsch_plan_updated_at datetime DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'วันเวลาที่ปรับปรุงแผนล่าสุด' AFTER wsch_plan_created_at,
  MODIFY COLUMN mb_id int(11) NOT NULL COMMENT 'รหัสสมาชิกเจ้าของแผน [FK -> member_profile] 1 คนมีได้ 1 แผน' AFTER wsch_plan_updated_at,
  MODIFY COLUMN wpt_id int(10) unsigned DEFAULT NULL COMMENT 'แม่แบบต้นทางที่คัดลอกมา [FK -> workout_plan_template] NULL = สร้างเอง' AFTER mb_id,
  MODIFY COLUMN wet_id int(10) unsigned DEFAULT NULL COMMENT 'รหัสท่าฝึกเวท [FK -> weight_exercises] NULL = แถวหัวแผน (ยังไม่มีท่า)' AFTER wpt_id;

-- STEP 8: ลบตาราง member_workout_plans ทิ้ง (ย้ายข้อมูลเข้า workout_schedules ครบแล้ว)
DROP TABLE member_workout_plans;
