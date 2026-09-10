-- =====================================================================
-- ROLLBACK ของ 2026-09-06_align_defaults_and_nullability.sql
-- คืนค่า NULL/DEFAULT ของทั้ง 72 คอลัมน์กลับเป็นสภาพก่อนรัน
-- (generate จาก information_schema ก่อนแก้จริง ไม่ได้พิมพ์เอง)
--
-- หมายเหตุ: ไฟล์นี้คืนได้เฉพาะ "โครงสร้าง" — ค่าที่ STEP 1 เปลี่ยนจาก NULL
-- เป็น '' ไม่ถูกย้อนกลับ (ถ้าต้องการข้อมูลเดิมเป๊ะให้ใช้ backup เต็มแทน:
-- migrations/backups/backup_before_20260906_defaults_nullability.sql)
-- =====================================================================
ALTER TABLE `revoked_tokens` MODIFY COLUMN `created_at` datetime(3) NULL DEFAULT NULL COMMENT 'วันและเวลาที่เพิกถอนโทเคน';
ALTER TABLE `audit_logs` MODIFY COLUMN `created_at` datetime(3) NULL DEFAULT NULL COMMENT 'วันและเวลาที่บันทึกเหตุการณ์';
ALTER TABLE `audit_logs` MODIFY COLUMN `ip_address` varchar(45) NULL DEFAULT NULL COMMENT 'หมายเลข IP ของผู้กระทำ (รองรับ IPv6)';
ALTER TABLE `audit_logs` MODIFY COLUMN `detail` varchar(255) NULL DEFAULT NULL COMMENT 'รายละเอียดเพิ่มเติมของเหตุการณ์';
ALTER TABLE `audit_logs` MODIFY COLUMN `action` varchar(50) NULL DEFAULT NULL COMMENT 'ชื่อการกระทำ (login_success, login_failed, logout, change_password_success, create, update, delete)';
ALTER TABLE `audit_logs` MODIFY COLUMN `actor_id` bigint(20) NULL DEFAULT NULL COMMENT 'รหัสผู้กระทำ (mb_id หรือ sys_id ตาม actor_type, 0 = guest)';
ALTER TABLE `audit_logs` MODIFY COLUMN `actor_type` varchar(20) NULL DEFAULT NULL COMMENT 'ประเภทผู้กระทำ (member=สมาชิก, admin=ผู้ดูแลระบบ, guest=ยังไม่ระบุตัวตน)';
ALTER TABLE `system_data` MODIFY COLUMN `sys_organization` varchar(100) NULL DEFAULT NULL COMMENT 'หน่วยงานเจ้าของระบบ';
ALTER TABLE `cardio_result` MODIFY COLUMN `cdors_distance` decimal(5,2) NULL DEFAULT 0.00 COMMENT 'ระยะทาง (กม., ส่งมาเฉพาะกิจกรรมที่ cdo_has_distance=1)';
ALTER TABLE `cardio_result` MODIFY COLUMN `cdors_calories` decimal(6,2) NULL DEFAULT NULL COMMENT 'แคลอรี่ที่เผาผลาญ (สุทธิ)';
ALTER TABLE `cardio_result` MODIFY COLUMN `cdors_duration` smallint(5) unsigned NULL DEFAULT NULL COMMENT 'ระยะเวลา (นาที)';
ALTER TABLE `weight_training_result` MODIFY COLUMN `wtrs_calories` decimal(6,2) NULL DEFAULT NULL COMMENT 'แคลอรี่ที่เผาผลาญ (สุทธิ)';
ALTER TABLE `weight_training_result` MODIFY COLUMN `wtrs_intensity_level` tinyint(4) NULL DEFAULT 2 COMMENT 'ระดับความหนักของการฝึก';
ALTER TABLE `weight_training_result` MODIFY COLUMN `wtrs_weight` decimal(5,2) NULL DEFAULT NULL COMMENT 'น้ำหนักที่ยกได้';
ALTER TABLE `weight_training_result` MODIFY COLUMN `wtrs_reps` smallint(5) unsigned NULL DEFAULT NULL COMMENT 'จำนวนครั้งที่ยกได้';
ALTER TABLE `weight_training_result` MODIFY COLUMN `wtrs_set_no` tinyint(3) unsigned NULL DEFAULT NULL COMMENT 'หมายเลขเซต';
ALTER TABLE `workout_schedules` MODIFY COLUMN `wsch_order` tinyint(4) NOT NULL DEFAULT 1 COMMENT 'ลำดับท่าในวันนั้น';
ALTER TABLE `plan_template_detail` MODIFY COLUMN `ptd_order` tinyint(3) unsigned NOT NULL DEFAULT 1 COMMENT 'ลำดับท่าในวันนั้น';
ALTER TABLE `plan_template_detail` MODIFY COLUMN `ptd_reps` varchar(10) NULL DEFAULT NULL COMMENT 'จำนวนครั้ง';
ALTER TABLE `plan_template_detail` MODIFY COLUMN `ptd_sets` tinyint(3) unsigned NULL DEFAULT NULL COMMENT 'จำนวนเซต';
ALTER TABLE `plan_template_detail` MODIFY COLUMN `ptd_day_name` varchar(50) NULL DEFAULT NULL COMMENT 'ชื่อเรียกวันฝึก';
ALTER TABLE `workout_plan_template` MODIFY COLUMN `wpt_description` text NULL DEFAULT NULL COMMENT 'คำอธิบายแผน';
ALTER TABLE `workout_plan_template` MODIFY COLUMN `wpt_image` varchar(255) NULL DEFAULT NULL COMMENT 'Path รูปภาพแผน';
ALTER TABLE `workout_plan_template` MODIFY COLUMN `wpt_difficulty` tinyint(4) NOT NULL DEFAULT 1 COMMENT 'ระดับความยาก (1=ระดับเริ่มต้น, 2=ระดับกลาง, 3=ระดับสูง)';
ALTER TABLE `workout_plan_template` MODIFY COLUMN `wpt_days_per_week` tinyint(3) unsigned NOT NULL DEFAULT 3 COMMENT 'จำนวนวันฝึกต่อสัปดาห์';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_technique` text NULL DEFAULT NULL COMMENT 'เทคนิคในการฝึก';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_description` text NULL DEFAULT NULL COMMENT 'คำอธิบายวิธีฝึก';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_loop_video` varchar(255) NULL DEFAULT NULL COMMENT 'Path วิดีโอ Loop เวทเทรนนิ่ง';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_video` varchar(255) NULL DEFAULT NULL COMMENT 'Path วิดีโอแนะนำวิธีฝึก';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_image` varchar(255) NULL DEFAULT NULL COMMENT 'Path รูปภาพท่าฝึกเวทเทรนนิ่ง';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_exercise_type` tinyint(4) NOT NULL DEFAULT 1 COMMENT 'ประเภทของท่าฝึกตามกลุ่มกล้ามเนื้อ (1=หลายกลุ่ม, 2=เฉพาะส่วน)';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_equipment` tinyint(4) NOT NULL DEFAULT 5 COMMENT 'อุปกรณ์ที่ใช้ฝึก (1=Barbell, 2=Dumbbell, 3=Machine, 4=Cable, 5=Bodyweight)';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_difficulty` tinyint(4) NOT NULL DEFAULT 1 COMMENT 'ระดับของท่าฝึก (1=ง่าย, 2=ปานกลาง, 3=ยาก)';
ALTER TABLE `muscle_group` MODIFY COLUMN `mug_image` varchar(255) NULL DEFAULT NULL COMMENT 'Path รูปภาพกลุ่มกล้ามเนื้อ';
ALTER TABLE `muscle_group` MODIFY COLUMN `mug_zone` tinyint(4) NOT NULL DEFAULT 1 COMMENT 'ส่วนของกล้ามเนื้อ (1=ร่างกายส่วนบน, 2=ร่างกายส่วนล่าง, 3=แกนกลางลำตัว)';
ALTER TABLE `cardio_category` MODIFY COLUMN `cdc_description` text NULL DEFAULT NULL COMMENT 'คำอธิบายประเภทคาร์ดิโอ';
ALTER TABLE `cardio_category` MODIFY COLUMN `cdc_image` varchar(255) NULL DEFAULT NULL COMMENT 'Path รูปประเภทคาร์ดิโอ';
ALTER TABLE `cardio` MODIFY COLUMN `cdo_technique` text NULL DEFAULT NULL COMMENT 'เทคนิคในการฝึก';
ALTER TABLE `cardio` MODIFY COLUMN `cdo_description` text NULL DEFAULT NULL COMMENT 'คำอธิบายวิธีฝึก';
ALTER TABLE `cardio` MODIFY COLUMN `cdo_loop_video` varchar(255) NULL DEFAULT NULL COMMENT 'Path วิดีโอ Loop คาร์ดิโอ';
ALTER TABLE `cardio` MODIFY COLUMN `cdo_video` varchar(255) NULL DEFAULT NULL COMMENT 'Path วิดีโอแนะนำวิธีฝึก';
ALTER TABLE `cardio` MODIFY COLUMN `cdo_image` varchar(255) NULL DEFAULT NULL COMMENT 'Path รูปกิจกรรมคาร์ดิโอ';
ALTER TABLE `cardio` MODIFY COLUMN `cdo_mets` decimal(4,2) NOT NULL DEFAULT 0.00 COMMENT 'ค่าความหนักของกิจกรรม (METs)';
ALTER TABLE `nutrition_category` MODIFY COLUMN `nttc_image` varchar(255) NULL DEFAULT NULL COMMENT 'Path รูปภาพประเภทโภชนาการ';
ALTER TABLE `nutrition` MODIFY COLUMN `ntt_food_image` varchar(255) NULL DEFAULT NULL COMMENT 'Path รูปภาพโภชนาการ';
ALTER TABLE `nutrition` MODIFY COLUMN `ntt_unit` varchar(20) NULL DEFAULT NULL COMMENT 'หน่วยนับ (กรัม,ออนซ์)';
ALTER TABLE `nutrition` MODIFY COLUMN `ntt_serving_weight` smallint(5) unsigned NULL DEFAULT NULL COMMENT 'ขนาดต่อหน่วยบริโภค';
ALTER TABLE `nutrition` MODIFY COLUMN `ntt_fat` decimal(6,2) NULL DEFAULT NULL COMMENT 'ไขมัน (กรัม)';
ALTER TABLE `nutrition` MODIFY COLUMN `ntt_carbs` decimal(6,2) NULL DEFAULT NULL COMMENT 'คาร์โบไฮเดรต (กรัม)';
ALTER TABLE `nutrition` MODIFY COLUMN `ntt_protein` decimal(6,2) NULL DEFAULT NULL COMMENT 'โปรตีน (กรัม)';
ALTER TABLE `nutrition` MODIFY COLUMN `ntt_calories` decimal(6,2) NULL DEFAULT NULL COMMENT 'แคลอรี่ต่อหน่วย';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_image` varchar(255) NULL DEFAULT NULL COMMENT 'Path รูปภาพอาหารที่บันทึก';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_total_fat` decimal(6,2) NULL DEFAULT NULL COMMENT 'ไขมันรวมของรายการนี้';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_total_carb` decimal(6,2) NULL DEFAULT NULL COMMENT 'คาร์โบไฮเดรตรวมของรายการนี้';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_total_protein` decimal(6,2) NULL DEFAULT NULL COMMENT 'โปรตีนรวมของรายการนี้';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_total_calories` decimal(6,2) NULL DEFAULT NULL COMMENT 'แคลอรี่รวมของรายการนี้';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_time` time NULL DEFAULT NULL COMMENT 'เวลาที่กิน';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_meal_type` tinyint(4) NULL DEFAULT NULL COMMENT 'มื้ออาหาร (1=มื้อเช้า, 2=มื้อกลางวัน, 3=มื้อเย็น, 4=มื้อว่าง)';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_unit` varchar(20) NULL DEFAULT NULL COMMENT 'หน่วยนับ (กรัม,ออนซ์)';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_quantity` decimal(5,2) NULL DEFAULT NULL COMMENT 'จำนวนที่บริโภค';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_food_name` varchar(100) NULL DEFAULT NULL COMMENT 'ชื่ออาหารที่บันทึก';
ALTER TABLE `member_profile` MODIFY COLUMN `mb_profile_pic` varchar(255) NULL DEFAULT NULL COMMENT 'Path รูปโปรไฟล์';
ALTER TABLE `member_profile` MODIFY COLUMN `mb_otp` char(6) NULL DEFAULT NULL COMMENT 'รหัสยืนยันตัวตน 6 หลัก (OTP)';
ALTER TABLE `member_bmr_history` MODIFY COLUMN `mbh_tdee_target` decimal(6,2) NULL DEFAULT NULL COMMENT 'พลังงานที่ใช้ต่อวันตามเป้าหมาย';
ALTER TABLE `member_bmr_history` MODIFY COLUMN `mbh_tdee` decimal(6,2) NULL DEFAULT NULL COMMENT 'พลังงานที่ใช้ต่อวัน';
ALTER TABLE `member_bmr_history` MODIFY COLUMN `mbh_bmr` decimal(6,2) NULL DEFAULT NULL COMMENT 'อัตราการเผาผลาญพื้นฐาน';
ALTER TABLE `member_bmr_history` MODIFY COLUMN `mbh_bmi` decimal(5,2) NULL DEFAULT NULL COMMENT 'ค่าดัชนีมวลกาย';
ALTER TABLE `member_body_stats` MODIFY COLUMN `mbs_recorded_date` datetime NULL DEFAULT NULL COMMENT 'วันและเวลาที่บันทึกข้อมูล (upsert ระดับแอป 1 วันต่อ 1 แถวเป็นหลัก)';
ALTER TABLE `member_body_stats` MODIFY COLUMN `mbs_target` tinyint(4) NULL DEFAULT NULL COMMENT 'เป้าหมาย (1=ลดน้ำหนัก, 2=เพิ่มน้ำหนัก, 3=รักษาน้ำหนัก)';
ALTER TABLE `member_body_stats` MODIFY COLUMN `mbs_activity_level` decimal(4,3) NULL DEFAULT NULL COMMENT 'Activity Factor ตัวคูณ TDEE (ไม่ใช่ความถี่การออกกำลังกายต่อสัปดาห์) ค่าที่เป็นไปได้: 1.2 / 1.375 / 1.55 / 1.725 / 1.9';
ALTER TABLE `member_body_stats` MODIFY COLUMN `mbs_weight` decimal(5,2) NULL DEFAULT NULL COMMENT 'น้ำหนัก (กก.)';
ALTER TABLE `member_body_stats` MODIFY COLUMN `mbs_height` decimal(4,1) NULL DEFAULT NULL COMMENT 'ส่วนสูง (ซม.)';

