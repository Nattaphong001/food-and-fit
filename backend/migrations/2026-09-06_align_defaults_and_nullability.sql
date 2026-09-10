-- =====================================================================
-- 2026-09-06 : ปรับ DEFAULT / NULL ให้ตรงกับ workflow จริงของระบบ
-- ---------------------------------------------------------------------
-- ขอบเขต : แก้เฉพาะ NULL/NOT NULL และ DEFAULT เท่านั้น
--          ไม่แตะ PRIMARY KEY / FOREIGN KEY / INDEX / ลำดับคอลัมน์ / ชนิดข้อมูล
--          ทุกคำสั่งคง COMMENT และ COLUMN_TYPE เดิมไว้ครบ (generate จาก
--          information_schema ของ DB จริง ไม่ได้พิมพ์เอง)
--
-- หลักการที่ใช้ตัดสิน (อ้างอิง flow จริงในโค้ด ไม่ใช่เอกสาร)
--   1) ค่าที่เซิร์ฟเวอร์คำนวณเองทุกครั้ง (แคลอรี่, BMI/BMR/TDEE, เลขเซ็ต,
--      สารอาหารรวม) -> NOT NULL และไม่มี DEFAULT เพราะถ้าว่างคือบั๊ก
--   2) ค่าที่ผ่าน validation ก่อน insert เสมอ -> NOT NULL และถอด DEFAULT
--      ที่เคยใส่ไว้เพื่อ "ให้ INSERT ผ่าน" ออก (กันค่าเดาแทนค่าจริง)
--   3) ค่าที่ "ไม่มี" มีความหมายจริง -> ปล่อยเป็น NULL และห้ามมี DEFAULT 0
--      (cardio_result.cdors_distance : กิจกรรมที่ไม่วัดระยะทาง)
--   4) คอลัมน์ข้อความ/ไฟล์ที่ Go ประกาศเป็น string (ไม่ใช่ pointer) จะเขียน
--      '' เสมอ -> รวมให้เหลือรูปแบบเดียว NOT NULL DEFAULT '' (TEXT ไม่ใส่
--      DEFAULT เพราะเลี่ยงความต่างระหว่าง MySQL/MariaDB)
--
-- backup ก่อนรัน : migrations/backups/backup_before_20260906_defaults_nullability.sql
-- rollback       : migrations/2026-09-06_align_defaults_and_nullability_rollback.sql
--
-- คำเตือน: ไฟล์นี้ต้องรันด้วย  mysql -u root food_and_fit_db < <ไฟล์นี้>
--          ห้ามส่งผ่าน mysql -e "..." เพราะ codepage ของ Windows console
--          ทำให้ข้อความไทยใน COMMENT เพี้ยน (บทเรียน docs/SPEC.md ข้อ 6 D10)
-- =====================================================================

-- ---------------------------------------------------------------------
-- STEP 1 : เปลี่ยนค่า NULL เดิมของคอลัมน์ข้อความ/ไฟล์ให้เป็น '' ก่อน
--          (ต้องทำก่อน ALTER ไม่งั้นแถวเดิมจะบล็อกการบังคับ NOT NULL)
-- ---------------------------------------------------------------------
UPDATE member_profile        SET mb_otp = ''           WHERE mb_otp IS NULL;
UPDATE member_profile        SET mb_profile_pic = ''   WHERE mb_profile_pic IS NULL;
UPDATE daily_nutrition       SET dntt_image = ''       WHERE dntt_image IS NULL;
UPDATE nutrition             SET ntt_food_image = ''   WHERE ntt_food_image IS NULL;
UPDATE nutrition_category    SET nttc_image = ''       WHERE nttc_image IS NULL;
UPDATE cardio                SET cdo_image = ''        WHERE cdo_image IS NULL;
UPDATE cardio                SET cdo_video = ''        WHERE cdo_video IS NULL;
UPDATE cardio                SET cdo_loop_video = ''   WHERE cdo_loop_video IS NULL;
UPDATE cardio                SET cdo_description = ''  WHERE cdo_description IS NULL;
UPDATE cardio                SET cdo_technique = ''    WHERE cdo_technique IS NULL;
UPDATE cardio_category       SET cdc_image = ''        WHERE cdc_image IS NULL;
UPDATE cardio_category       SET cdc_description = ''  WHERE cdc_description IS NULL;
UPDATE muscle_group          SET mug_image = ''        WHERE mug_image IS NULL;
UPDATE weight_exercises      SET wet_image = ''        WHERE wet_image IS NULL;
UPDATE weight_exercises      SET wet_video = ''        WHERE wet_video IS NULL;
UPDATE weight_exercises      SET wet_loop_video = ''   WHERE wet_loop_video IS NULL;
UPDATE weight_exercises      SET wet_description = ''  WHERE wet_description IS NULL;
UPDATE weight_exercises      SET wet_technique = ''    WHERE wet_technique IS NULL;
UPDATE workout_plan_template SET wpt_image = ''        WHERE wpt_image IS NULL;
UPDATE workout_plan_template SET wpt_description = ''  WHERE wpt_description IS NULL;
UPDATE system_data           SET sys_organization = '' WHERE sys_organization IS NULL;
UPDATE audit_logs            SET detail = ''           WHERE detail IS NULL;

-- ---------------------------------------------------------------------
-- STEP 2 : ปรับ NULL / DEFAULT ทีละคอลัมน์ (72 คอลัมน์ / 15 ตาราง)
-- ---------------------------------------------------------------------
ALTER TABLE `member_body_stats` MODIFY COLUMN `mbs_height` decimal(4,1) NOT NULL COMMENT 'ส่วนสูง (ซม.)';
ALTER TABLE `member_body_stats` MODIFY COLUMN `mbs_weight` decimal(5,2) NOT NULL COMMENT 'น้ำหนัก (กก.)';
ALTER TABLE `member_body_stats` MODIFY COLUMN `mbs_activity_level` decimal(4,3) NOT NULL COMMENT 'Activity Factor ตัวคูณ TDEE (ไม่ใช่ความถี่การออกกำลังกายต่อสัปดาห์) ค่าที่เป็นไปได้: 1.2 / 1.375 / 1.55 / 1.725 / 1.9';
ALTER TABLE `member_body_stats` MODIFY COLUMN `mbs_target` tinyint(4) NOT NULL COMMENT 'เป้าหมาย (1=ลดน้ำหนัก, 2=เพิ่มน้ำหนัก, 3=รักษาน้ำหนัก)';
ALTER TABLE `member_body_stats` MODIFY COLUMN `mbs_recorded_date` datetime NOT NULL COMMENT 'วันและเวลาที่บันทึกข้อมูล (upsert ระดับแอป 1 วันต่อ 1 แถวเป็นหลัก)';
ALTER TABLE `member_bmr_history` MODIFY COLUMN `mbh_bmi` decimal(5,2) NOT NULL COMMENT 'ค่าดัชนีมวลกาย';
ALTER TABLE `member_bmr_history` MODIFY COLUMN `mbh_bmr` decimal(6,2) NOT NULL COMMENT 'อัตราการเผาผลาญพื้นฐาน';
ALTER TABLE `member_bmr_history` MODIFY COLUMN `mbh_tdee` decimal(6,2) NOT NULL COMMENT 'พลังงานที่ใช้ต่อวัน';
ALTER TABLE `member_bmr_history` MODIFY COLUMN `mbh_tdee_target` decimal(6,2) NOT NULL COMMENT 'พลังงานที่ใช้ต่อวันตามเป้าหมาย';
ALTER TABLE `member_profile` MODIFY COLUMN `mb_otp` char(6) NOT NULL DEFAULT '' COMMENT 'รหัสยืนยันตัวตน 6 หลัก (OTP)';
ALTER TABLE `member_profile` MODIFY COLUMN `mb_profile_pic` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปโปรไฟล์';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_food_name` varchar(100) NOT NULL COMMENT 'ชื่ออาหารที่บันทึก';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_quantity` decimal(5,2) NOT NULL COMMENT 'จำนวนที่บริโภค';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_unit` varchar(20) NOT NULL COMMENT 'หน่วยนับ (กรัม,ออนซ์)';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_meal_type` tinyint(4) NOT NULL COMMENT 'มื้ออาหาร (1=มื้อเช้า, 2=มื้อกลางวัน, 3=มื้อเย็น, 4=มื้อว่าง)';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_time` time NOT NULL COMMENT 'เวลาที่กิน';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_total_calories` decimal(6,2) NOT NULL COMMENT 'แคลอรี่รวมของรายการนี้';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_total_protein` decimal(6,2) NOT NULL COMMENT 'โปรตีนรวมของรายการนี้';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_total_carb` decimal(6,2) NOT NULL COMMENT 'คาร์โบไฮเดรตรวมของรายการนี้';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_total_fat` decimal(6,2) NOT NULL COMMENT 'ไขมันรวมของรายการนี้';
ALTER TABLE `daily_nutrition` MODIFY COLUMN `dntt_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปภาพอาหารที่บันทึก';
ALTER TABLE `nutrition` MODIFY COLUMN `ntt_calories` decimal(6,2) NOT NULL COMMENT 'แคลอรี่ต่อหน่วย';
ALTER TABLE `nutrition` MODIFY COLUMN `ntt_protein` decimal(6,2) NOT NULL COMMENT 'โปรตีน (กรัม)';
ALTER TABLE `nutrition` MODIFY COLUMN `ntt_carbs` decimal(6,2) NOT NULL COMMENT 'คาร์โบไฮเดรต (กรัม)';
ALTER TABLE `nutrition` MODIFY COLUMN `ntt_fat` decimal(6,2) NOT NULL COMMENT 'ไขมัน (กรัม)';
ALTER TABLE `nutrition` MODIFY COLUMN `ntt_serving_weight` smallint(5) unsigned NOT NULL COMMENT 'ขนาดต่อหน่วยบริโภค';
ALTER TABLE `nutrition` MODIFY COLUMN `ntt_unit` varchar(20) NOT NULL COMMENT 'หน่วยนับ (กรัม,ออนซ์)';
ALTER TABLE `nutrition` MODIFY COLUMN `ntt_food_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปภาพโภชนาการ';
ALTER TABLE `nutrition_category` MODIFY COLUMN `nttc_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปภาพประเภทโภชนาการ';
ALTER TABLE `cardio` MODIFY COLUMN `cdo_mets` decimal(4,2) NOT NULL COMMENT 'ค่าความหนักของกิจกรรม (METs)';
ALTER TABLE `cardio` MODIFY COLUMN `cdo_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปกิจกรรมคาร์ดิโอ';
ALTER TABLE `cardio` MODIFY COLUMN `cdo_video` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path วิดีโอแนะนำวิธีฝึก';
ALTER TABLE `cardio` MODIFY COLUMN `cdo_loop_video` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path วิดีโอ Loop คาร์ดิโอ';
ALTER TABLE `cardio` MODIFY COLUMN `cdo_description` text NOT NULL COMMENT 'คำอธิบายวิธีฝึก';
ALTER TABLE `cardio` MODIFY COLUMN `cdo_technique` text NOT NULL COMMENT 'เทคนิคในการฝึก';
ALTER TABLE `cardio_category` MODIFY COLUMN `cdc_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปประเภทคาร์ดิโอ';
ALTER TABLE `cardio_category` MODIFY COLUMN `cdc_description` text NOT NULL COMMENT 'คำอธิบายประเภทคาร์ดิโอ';
ALTER TABLE `muscle_group` MODIFY COLUMN `mug_zone` tinyint(4) NOT NULL COMMENT 'ส่วนของกล้ามเนื้อ (1=ร่างกายส่วนบน, 2=ร่างกายส่วนล่าง, 3=แกนกลางลำตัว)';
ALTER TABLE `muscle_group` MODIFY COLUMN `mug_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปภาพกลุ่มกล้ามเนื้อ';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_difficulty` tinyint(4) NOT NULL COMMENT 'ระดับของท่าฝึก (1=ง่าย, 2=ปานกลาง, 3=ยาก)';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_equipment` tinyint(4) NOT NULL COMMENT 'อุปกรณ์ที่ใช้ฝึก (1=Barbell, 2=Dumbbell, 3=Machine, 4=Cable, 5=Bodyweight)';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_exercise_type` tinyint(4) NOT NULL COMMENT 'ประเภทของท่าฝึกตามกลุ่มกล้ามเนื้อ (1=หลายกลุ่ม, 2=เฉพาะส่วน)';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปภาพท่าฝึกเวทเทรนนิ่ง';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_video` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path วิดีโอแนะนำวิธีฝึก';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_loop_video` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path วิดีโอ Loop เวทเทรนนิ่ง';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_description` text NOT NULL COMMENT 'คำอธิบายวิธีฝึก';
ALTER TABLE `weight_exercises` MODIFY COLUMN `wet_technique` text NOT NULL COMMENT 'เทคนิคในการฝึก';
ALTER TABLE `workout_plan_template` MODIFY COLUMN `wpt_days_per_week` tinyint(3) unsigned NOT NULL COMMENT 'จำนวนวันฝึกต่อสัปดาห์';
ALTER TABLE `workout_plan_template` MODIFY COLUMN `wpt_difficulty` tinyint(4) NOT NULL COMMENT 'ระดับความยาก (1=ระดับเริ่มต้น, 2=ระดับกลาง, 3=ระดับสูง)';
ALTER TABLE `workout_plan_template` MODIFY COLUMN `wpt_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปภาพแผน';
ALTER TABLE `workout_plan_template` MODIFY COLUMN `wpt_description` text NOT NULL COMMENT 'คำอธิบายแผน';
ALTER TABLE `plan_template_detail` MODIFY COLUMN `ptd_day_name` varchar(50) NOT NULL COMMENT 'ชื่อเรียกวันฝึก';
ALTER TABLE `plan_template_detail` MODIFY COLUMN `ptd_sets` tinyint(3) unsigned NOT NULL COMMENT 'จำนวนเซต';
ALTER TABLE `plan_template_detail` MODIFY COLUMN `ptd_reps` varchar(10) NOT NULL COMMENT 'จำนวนครั้ง';
ALTER TABLE `plan_template_detail` MODIFY COLUMN `ptd_order` tinyint(3) unsigned NOT NULL COMMENT 'ลำดับท่าในวันนั้น';
ALTER TABLE `workout_schedules` MODIFY COLUMN `wsch_order` tinyint(4) NOT NULL COMMENT 'ลำดับท่าในวันนั้น';
ALTER TABLE `weight_training_result` MODIFY COLUMN `wtrs_set_no` tinyint(3) unsigned NOT NULL COMMENT 'หมายเลขเซต';
ALTER TABLE `weight_training_result` MODIFY COLUMN `wtrs_reps` smallint(5) unsigned NOT NULL COMMENT 'จำนวนครั้งที่ยกได้';
ALTER TABLE `weight_training_result` MODIFY COLUMN `wtrs_weight` decimal(5,2) NOT NULL COMMENT 'น้ำหนักที่ยกได้';
ALTER TABLE `weight_training_result` MODIFY COLUMN `wtrs_intensity_level` tinyint(4) NOT NULL COMMENT 'ระดับความหนักของการฝึก';
ALTER TABLE `weight_training_result` MODIFY COLUMN `wtrs_calories` decimal(6,2) NOT NULL COMMENT 'แคลอรี่ที่เผาผลาญ (สุทธิ)';
ALTER TABLE `cardio_result` MODIFY COLUMN `cdors_duration` smallint(5) unsigned NOT NULL COMMENT 'ระยะเวลา (นาที)';
ALTER TABLE `cardio_result` MODIFY COLUMN `cdors_calories` decimal(6,2) NOT NULL COMMENT 'แคลอรี่ที่เผาผลาญ (สุทธิ)';
ALTER TABLE `cardio_result` MODIFY COLUMN `cdors_distance` decimal(5,2) NULL COMMENT 'ระยะทาง (กม., ส่งมาเฉพาะกิจกรรมที่ cdo_has_distance=1)';
ALTER TABLE `system_data` MODIFY COLUMN `sys_organization` varchar(100) NOT NULL DEFAULT '' COMMENT 'หน่วยงานเจ้าของระบบ';
ALTER TABLE `audit_logs` MODIFY COLUMN `actor_type` varchar(20) NOT NULL COMMENT 'ประเภทผู้กระทำ (member=สมาชิก, admin=ผู้ดูแลระบบ, guest=ยังไม่ระบุตัวตน)';
ALTER TABLE `audit_logs` MODIFY COLUMN `actor_id` bigint(20) NOT NULL COMMENT 'รหัสผู้กระทำ (mb_id หรือ sys_id ตาม actor_type, 0 = guest)';
ALTER TABLE `audit_logs` MODIFY COLUMN `action` varchar(50) NOT NULL COMMENT 'ชื่อการกระทำ (login_success, login_failed, logout, change_password_success, create, update, delete)';
ALTER TABLE `audit_logs` MODIFY COLUMN `detail` varchar(255) NOT NULL COMMENT 'รายละเอียดเพิ่มเติมของเหตุการณ์';
ALTER TABLE `audit_logs` MODIFY COLUMN `ip_address` varchar(45) NOT NULL COMMENT 'หมายเลข IP ของผู้กระทำ (รองรับ IPv6)';
ALTER TABLE `audit_logs` MODIFY COLUMN `created_at` datetime(3) NOT NULL COMMENT 'วันและเวลาที่บันทึกเหตุการณ์';
ALTER TABLE `revoked_tokens` MODIFY COLUMN `created_at` datetime(3) NOT NULL COMMENT 'วันและเวลาที่เพิกถอนโทเคน';

