-- =====================================================================
-- Migration: 2026-09-11 เพิ่ม UNIQUE constraint ที่โค้ดคาดหวังอยู่แล้ว + ล้าง index ซ้ำซ้อน
-- =====================================================================
-- เหตุผล:
--   backend เรียก helpers.IsDuplicateKeyError() แล้วคืน HTTP 409 ("มี...ชื่อนี้อยู่แล้ว")
--   รวม 14 จุด ใน exercise_controller.go / nutrition_controller.go / workout_controller.go
--   แต่ DB ไม่เคยมี UNIQUE index บนคอลัมน์ชื่อพวกนั้น -> MySQL ไม่เคยยิง error 1062
--   -> โค้ดดักไว้เปล่า ๆ แอดมินสร้างชื่อซ้ำได้เงียบ ๆ
--   migration นี้ทำให้ constraint ระดับ DB ตรงกับสิ่งที่โค้ดคาดหวัง
--
-- backup ก่อนรัน: backups/backup_full_before_unique_constraints_20260911.sql
-- ตรวจแล้วก่อนรัน: ไม่มีค่าซ้ำในทุกคอลัมน์ด้านล่าง (COUNT ... HAVING COUNT(*)>1 = 0 ทุกตัว)
--
-- วิธีรัน:
--   "C:\xampp\mysql\bin\mysql.exe" -u root food_and_fit_db --default-character-set=utf8mb4 \
--     -e "source backend/migrations/2026-09-11_add_unique_constraints_and_index_cleanup.sql"
-- =====================================================================

-- --- [1] ชื่อข้อมูลหลัก (master data) ต้องไม่ซ้ำ — รองรับ 409 ที่โค้ดคืนอยู่แล้ว ---
ALTER TABLE `muscle_group`          ADD UNIQUE KEY `uq_mug_name`  (`mug_name`);
ALTER TABLE `weight_exercises`      ADD UNIQUE KEY `uq_wet_name`  (`wet_name`);
ALTER TABLE `cardio`                ADD UNIQUE KEY `uq_cdo_name`  (`cdo_name`);
ALTER TABLE `cardio_category`       ADD UNIQUE KEY `uq_cdc_name`  (`cdc_name`);
ALTER TABLE `nutrition_category`    ADD UNIQUE KEY `uq_nttc_name` (`nttc_name`);
ALTER TABLE `nutrition`             ADD UNIQUE KEY `uq_ntt_food_name` (`ntt_food_name`);
ALTER TABLE `workout_plan_template` ADD UNIQUE KEY `uq_wpt_name`  (`wpt_name`);

-- --- [2] อีเมลสมาชิกต้องไม่ซ้ำ ---
-- เดิมกันซ้ำแค่ฝั่ง Go (SELECT ก่อน INSERT ใน Register) ซึ่งไม่ atomic
-- สมัครพร้อมกัน 2 request อีเมลเดียวกัน -> ผ่านทั้งคู่ ได้สมาชิกซ้ำ
-- แอดมิน (system_data.sys_email) มี uq_sys_email กันอยู่แล้ว สมาชิกควรได้มาตรฐานเดียวกัน
ALTER TABLE `member_profile` ADD UNIQUE KEY `uq_mb_email` (`mb_email`);

-- --- [3] (ยกเลิก — ดูหมายเหตุ) เดิมตั้งใจเพิ่ม UNIQUE (mb_id, mbh_record_date) บน member_bmr_history ---
-- รันไปแล้วครั้งแรกแต่ DROP กลับทันทีในเซสชันเดียวกัน (2026-09-11) เพราะขัดกับการตัดสินใจที่มีอยู่แล้ว
-- ใน backend/CLAUDE.md ข้อ 3.6: "member_bmr_history เป็น append-only log โดยตั้งใจ 1 วันมีได้หลายแถวจริง"
-- และ D10.3 เคยมีคนเสนอ UNIQUE ตัวเดียวกันนี้มาก่อนแล้วถูกปฏิเสธด้วยเหตุผลเดียวกัน (2026-09-06)
-- ผมพลาดไม่ได้เช็คข้อ 3.6/D10.3 ก่อนเพิ่มตัวนี้ในรอบแรก — แก้เป็นไม่รันแล้ว (บรรทัดถัดไปคือ no-op คงไว้เพื่อบันทึกประวัติ)
-- ถ้าจะพิจารณาใหม่ในอนาคต ต้องตัดสินใจก่อนว่า D10 (mobile/CLAUDE.md, upsert รายวันฝั่งแอป 2026-09-05)
-- ทำให้ข้อสรุปเดิมใน 3.6 (2026-09-04) ล้าสมัยไปแล้วหรือยัง — เป็นคำถามเชิง business logic ต้องให้ผู้ใช้ตัดสินใจ
-- ALTER TABLE `member_bmr_history` ADD UNIQUE KEY `uq_mbh_member_date` (`mb_id`, `mbh_record_date`); -- ไม่รัน

-- --- [4] ลบ index ซ้ำซ้อน ---
-- idx_audit_logs_target_table (table_name) เป็น leftmost prefix ของ
-- idx_audit_table_record (table_name, record_id) อยู่แล้ว -> ไม่มีประโยชน์ กิน storage + ช้าตอน INSERT
ALTER TABLE `audit_logs` DROP INDEX `idx_audit_logs_target_table`;

-- --- [5] ชนิดข้อมูลเวลาพักให้ตรงกันสองตาราง ---
-- wsch_rest_seconds เป็น smallint(6) signed แต่ ptd_rest_seconds เป็น smallint(5) unsigned
-- เรื่องเดียวกัน (วินาที ค่าติดลบไม่มีความหมาย) ข้อมูลจริงไม่มีค่าติดลบสักแถว
ALTER TABLE `workout_schedules` MODIFY `wsch_rest_seconds` SMALLINT(5) UNSIGNED NOT NULL DEFAULT 90
  COMMENT 'เวลาพัก (วินาที)';


-- =====================================================================
-- ROLLBACK (คัดลอกไปรันถ้าต้องย้อนกลับ)
-- =====================================================================
-- ALTER TABLE `muscle_group`          DROP INDEX `uq_mug_name`;
-- ALTER TABLE `weight_exercises`      DROP INDEX `uq_wet_name`;
-- ALTER TABLE `cardio`                DROP INDEX `uq_cdo_name`;
-- ALTER TABLE `cardio_category`       DROP INDEX `uq_cdc_name`;
-- ALTER TABLE `nutrition_category`    DROP INDEX `uq_nttc_name`;
-- ALTER TABLE `nutrition`             DROP INDEX `uq_ntt_food_name`;
-- ALTER TABLE `workout_plan_template` DROP INDEX `uq_wpt_name`;
-- ALTER TABLE `member_profile`        DROP INDEX `uq_mb_email`;
-- ALTER TABLE `audit_logs`            ADD KEY `idx_audit_logs_target_table` (`table_name`);
-- ALTER TABLE `workout_schedules` MODIFY `wsch_rest_seconds` SMALLINT(6) NOT NULL DEFAULT 90
--   COMMENT 'เวลาพัก (วินาที)';
