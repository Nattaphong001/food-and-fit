-- เติม COMMENT ให้ weight_training_result ให้ตรง Datadic_edit.dart
-- (บล็อกนี้เขียนไว้แล้วใน migrations/2026-09-05_sync_column_order_and_comments_with_datadic.sql
--  บรรทัด 197-206 แต่หลุดไม่ถูกรันจริงตอนนั้นเหมือนกับ member_body_stats
--  (ดู migrations/2026-09-06_add_comments_member_body_stats.sql) — เหลือแค่ wtrs_id ที่มี comment เดิม)
-- ไม่เปลี่ยนชนิดข้อมูล, NULL/NOT NULL, DEFAULT, PK/FK/INDEX, ลำดับคอลัมน์ใดๆ ทั้งสิ้น แก้แค่ COMMENT
--
-- ⚠️ ต้องรันด้วย: mysql -u root food_and_fit_db --default-character-set=utf8mb4 < <ไฟล์นี้>
--    ห้ามรันแบบไม่ระบุ --default-character-set=utf8mb4 หรือผ่าน -e เป็น argument ตรงๆ
--    (client บนเครื่องนี้ default เป็น tis620 ทำให้ข้อความไทยเพี้ยนตอนเขียนลง DB จริง)
--
-- Rollback (คืนกลับเป็นไม่มี comment เหมือนก่อนรัน):
--   ALTER TABLE weight_training_result
--     MODIFY COLUMN wtrs_date date DEFAULT NULL,
--     MODIFY COLUMN wtrs_set_no bigint(20) DEFAULT NULL,
--     MODIFY COLUMN wtrs_weight decimal(5,2) DEFAULT NULL,
--     MODIFY COLUMN wtrs_reps bigint(20) DEFAULT NULL,
--     MODIFY COLUMN wtrs_intensity_level tinyint(4) DEFAULT 2,
--     MODIFY COLUMN wtrs_calories decimal(7,2) DEFAULT NULL,
--     MODIFY COLUMN mb_id int(11) DEFAULT NULL,
--     MODIFY COLUMN wet_id int(10) unsigned DEFAULT NULL,
--     MODIFY COLUMN wsch_id int(10) unsigned DEFAULT NULL;

ALTER TABLE weight_training_result
  MODIFY COLUMN wtrs_date date DEFAULT NULL COMMENT 'วันที่บันทึกผลการฝึก',
  MODIFY COLUMN wtrs_set_no bigint(20) DEFAULT NULL COMMENT 'หมายเลขเซต',
  MODIFY COLUMN wtrs_weight decimal(5,2) DEFAULT NULL COMMENT 'น้ำหนักที่ยก (กก.)',
  MODIFY COLUMN wtrs_reps bigint(20) DEFAULT NULL COMMENT 'จำนวนครั้งที่ยกได้',
  MODIFY COLUMN wtrs_intensity_level tinyint(4) DEFAULT 2 COMMENT 'ระดับความหนักของการฝึก (1=เบา, 2=กลาง, 3=หนัก) ใช้กำหนดค่า MET เพื่อคำนวณแคลอรี่',
  MODIFY COLUMN wtrs_calories decimal(7,2) DEFAULT NULL COMMENT 'แคลอรี่ที่เผาผลาญ (สุทธิ หักฐาน 1 MET แล้ว)',
  MODIFY COLUMN mb_id int(11) DEFAULT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]',
  MODIFY COLUMN wet_id int(10) unsigned DEFAULT NULL COMMENT 'รหัสท่าฝึกเวทเทรนนิ่ง [FK -> weight_exercises] ON DELETE SET NULL',
  MODIFY COLUMN wsch_id int(10) unsigned DEFAULT NULL COMMENT 'รหัสตารางกำหนดการออกกำลังกาย [FK -> workout_schedules] ON DELETE SET NULL — nullable เพื่อรองรับกรณีฝึกนอกแผนที่วางไว้ล่วงหน้า';
