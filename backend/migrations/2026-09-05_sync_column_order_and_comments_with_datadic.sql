-- =============================================================================
-- เรียงลำดับคอลัมน์ + แก้ COMMENT ให้ตรงกับ Datadic_edit.dart (อัปเดต 2026-09-05 20:07)
-- ผลกระทบ: เปลี่ยนแค่ ORDER ทางกายภาพของคอลัมน์ + COMMENT เท่านั้น
-- ไม่เปลี่ยนชนิดข้อมูล, NULL/NOT NULL, DEFAULT, PK/FK/INDEX ใดๆ ทั้งสิ้น
-- (ยกเว้นระบุไว้ชัดเจนเป็นอย่างอื่น)
-- Backup ก่อนรัน: migrations/backups/backup_full_before_datadic_column_sync_20260905.sql
-- Rollback: mysql -u root food_and_fit_db < migrations/backups/backup_full_before_datadic_column_sync_20260905.sql
-- =============================================================================

-- -----------------------------------------------------------------------------
-- system_data
-- -----------------------------------------------------------------------------
ALTER TABLE system_data
  MODIFY COLUMN sys_full_name varchar(100) NOT NULL COMMENT 'ชื่อ-นามสกุล' AFTER sys_email,
  MODIFY COLUMN sys_organization varchar(100) DEFAULT NULL COMMENT 'หน่วยงานเจ้าของระบบ' AFTER sys_full_name,
  MODIFY COLUMN sys_start_date date DEFAULT NULL COMMENT 'วันที่เริ่มใช้ระบบ (ตั้งอัตโนมัติตอน login ครั้งแรกจริง ไม่ใช่ตอนสร้างบัญชี — NULL จนกว่าเจ้าของบัญชีจะ login ครั้งแรก)' AFTER sys_organization,
  MODIFY COLUMN sys_password_hash varchar(255) NOT NULL COMMENT 'รหัสผ่าน' AFTER sys_start_date;

-- -----------------------------------------------------------------------------
-- muscle_group
-- -----------------------------------------------------------------------------
ALTER TABLE muscle_group
  MODIFY COLUMN mug_image varchar(255) DEFAULT NULL COMMENT 'Path รูปภาพ' AFTER mug_id,
  MODIFY COLUMN mug_name varchar(100) NOT NULL COMMENT 'ชื่อกลุ่มกล้ามเนื้อ' AFTER mug_image,
  MODIFY COLUMN mug_zone tinyint(4) NOT NULL DEFAULT 1 COMMENT 'ส่วนของกล้ามเนื้อ (1=ร่างกายส่วนบน, 2=ร่างกายส่วนล่าง, 3=แกนกลางลำตัว)' AFTER mug_name;

-- -----------------------------------------------------------------------------
-- weight_exercises
-- -----------------------------------------------------------------------------
ALTER TABLE weight_exercises
  MODIFY COLUMN wet_image varchar(255) DEFAULT NULL COMMENT 'Path รูปกิจกรรม' AFTER wet_id,
  MODIFY COLUMN wet_name varchar(100) NOT NULL COMMENT 'ชื่อท่าฝึกเวทเทรนนิ่ง' AFTER wet_image,
  MODIFY COLUMN wet_difficulty tinyint(4) NOT NULL DEFAULT 1 COMMENT 'ระดับของท่าฝึก (1=ง่าย, 2=ปานกลาง, 3=ยาก)' AFTER wet_name,
  MODIFY COLUMN wet_equipment tinyint(4) NOT NULL DEFAULT 5 COMMENT 'อุปกรณ์ที่ใช้ฝึก (1=Barbell, 2=Dumbbell, 3=Machine, 4=Cable, 5=Bodyweight)' AFTER wet_difficulty,
  MODIFY COLUMN wet_exercise_type tinyint(4) NOT NULL DEFAULT 1 COMMENT 'ประเภทของท่าฝึกตามกลุ่มกล้ามเนื้อ (1=หลายกลุ่ม, 2=เฉพาะส่วน)' AFTER wet_equipment,
  MODIFY COLUMN wet_description text DEFAULT NULL COMMENT 'คำอธิบายวิธีฝึก' AFTER wet_exercise_type,
  MODIFY COLUMN wet_technique text DEFAULT NULL COMMENT 'เทคนิคในการฝึก' AFTER wet_description,
  MODIFY COLUMN wet_video varchar(255) DEFAULT NULL COMMENT 'Path วิดีโอแนะนำวิธีฝึก' AFTER wet_technique,
  MODIFY COLUMN wet_loop_video varchar(255) DEFAULT NULL COMMENT 'Path ไฟล์วิดีโอเวทเทรนนิ่ง loop' AFTER wet_video;

-- -----------------------------------------------------------------------------
-- exercise_muscle_details
-- -----------------------------------------------------------------------------
ALTER TABLE exercise_muscle_details
  MODIFY COLUMN exm_type tinyint(4) NOT NULL COMMENT 'ประเภทของกลุ่มกล้ามเนื้อในการฝึก (1=หลัก, 2=รอง)' AFTER emd_id,
  MODIFY COLUMN wet_id int(10) unsigned NOT NULL COMMENT 'รหัสท่าฝึกเวทเทรนนิ่ง [FK -> weight_exercises]' AFTER exm_type,
  MODIFY COLUMN mug_id int(10) unsigned NOT NULL COMMENT 'รหัสกลุ่มกล้ามเนื้อ [FK -> muscle_group]' AFTER wet_id;

-- -----------------------------------------------------------------------------
-- cardio_category
-- -----------------------------------------------------------------------------
ALTER TABLE cardio_category
  MODIFY COLUMN cdc_image varchar(255) DEFAULT NULL COMMENT 'Path รูปภาพหมวดหมู่' AFTER cdc_id,
  MODIFY COLUMN cdc_name varchar(100) NOT NULL COMMENT 'ประเภทกิจกรรม' AFTER cdc_image,
  MODIFY COLUMN cdc_description text DEFAULT NULL COMMENT 'คำอธิบายประเภทของกิจกรรม' AFTER cdc_name;

-- -----------------------------------------------------------------------------
-- cardio
-- -----------------------------------------------------------------------------
ALTER TABLE cardio
  MODIFY COLUMN cdo_image varchar(255) DEFAULT NULL COMMENT 'Path รูปกิจกรรม' AFTER cdo_id,
  MODIFY COLUMN cdo_name varchar(100) NOT NULL COMMENT 'ชื่อกิจกรรม' AFTER cdo_image,
  MODIFY COLUMN cdo_mets decimal(4,2) NOT NULL DEFAULT 0.00 COMMENT 'ค่าความหนักของกิจกรรม (METs)' AFTER cdo_name,
  MODIFY COLUMN cdo_has_distance tinyint(4) NOT NULL DEFAULT 0 COMMENT 'แสดงช่องกรอกระยะทาง (0=ไม่แสดง, 1=แสดง)' AFTER cdo_mets,
  MODIFY COLUMN cdo_description text DEFAULT NULL COMMENT 'คำอธิบายวิธีฝึก' AFTER cdo_has_distance,
  MODIFY COLUMN cdo_technique text DEFAULT NULL COMMENT 'เทคนิคในการฝึก' AFTER cdo_description,
  MODIFY COLUMN cdo_video varchar(255) DEFAULT NULL COMMENT 'Path วิดีโอแนะนำวิธีฝึก' AFTER cdo_technique,
  MODIFY COLUMN cdo_loop_video varchar(255) DEFAULT NULL COMMENT 'Path ไฟล์วิดีโอ Loop คาร์ดิโอ' AFTER cdo_video,
  MODIFY COLUMN cdc_id int(10) unsigned NOT NULL DEFAULT 1 COMMENT 'รหัสประเภทคาร์ดิโอ [FK -> cardio_category]' AFTER cdo_loop_video;

-- -----------------------------------------------------------------------------
-- nutrition_category
-- -----------------------------------------------------------------------------
ALTER TABLE nutrition_category
  MODIFY COLUMN nttc_image varchar(255) DEFAULT NULL COMMENT 'Path รูปภาพหมวดหมู่' AFTER nttc_id,
  MODIFY COLUMN nttc_name varchar(100) NOT NULL COMMENT 'ชื่อประเภทอาหาร' AFTER nttc_image;

-- -----------------------------------------------------------------------------
-- nutrition
-- -----------------------------------------------------------------------------
ALTER TABLE nutrition
  MODIFY COLUMN ntt_id int(11) NOT NULL AUTO_INCREMENT COMMENT 'รหัสโภชนาการ [PK]',
  MODIFY COLUMN ntt_food_image varchar(255) DEFAULT NULL COMMENT 'Path รูปอาหาร' AFTER ntt_id,
  MODIFY COLUMN ntt_food_name varchar(100) NOT NULL COMMENT 'ชื่ออาหาร' AFTER ntt_food_image,
  MODIFY COLUMN ntt_protein decimal(5,1) DEFAULT NULL COMMENT 'โปรตีน (กรัม)' AFTER ntt_food_name,
  MODIFY COLUMN ntt_carbs decimal(5,1) DEFAULT NULL COMMENT 'คาร์โบไฮเดรต (กรัม)' AFTER ntt_protein,
  MODIFY COLUMN ntt_fat decimal(5,1) DEFAULT NULL COMMENT 'ไขมัน (กรัม)' AFTER ntt_carbs,
  MODIFY COLUMN ntt_calories decimal(7,2) DEFAULT NULL COMMENT 'แคลอรี่ต่อหน่วย' AFTER ntt_fat,
  MODIFY COLUMN ntt_serving_weight int(11) DEFAULT NULL COMMENT 'ขนาดต่อหน่วยบริโภค' AFTER ntt_calories,
  MODIFY COLUMN ntt_unit varchar(50) DEFAULT NULL COMMENT 'หน่วยนับ' AFTER ntt_serving_weight,
  MODIFY COLUMN nttc_id int(11) NOT NULL COMMENT 'รหัสประเภทอาหาร [FK -> nutrition_category]' AFTER ntt_unit;

-- -----------------------------------------------------------------------------
-- workout_plan_template
-- -----------------------------------------------------------------------------
ALTER TABLE workout_plan_template
  MODIFY COLUMN wpt_id int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสแผนแนะนำ [PK]',
  MODIFY COLUMN wpt_image varchar(255) DEFAULT NULL COMMENT 'Path รูปภาพแผน' AFTER wpt_id,
  MODIFY COLUMN wpt_name varchar(100) NOT NULL COMMENT 'ชื่อแผนการฝึก' AFTER wpt_image,
  MODIFY COLUMN wpt_description text DEFAULT NULL COMMENT 'คำอธิบายแผน' AFTER wpt_name,
  MODIFY COLUMN wpt_days_per_week int(11) NOT NULL DEFAULT 3 COMMENT 'จำนวนวันฝึกต่อสัปดาห์' AFTER wpt_description,
  MODIFY COLUMN wpt_difficulty tinyint(4) NOT NULL DEFAULT 1 COMMENT 'ระดับความยาก (1=ระดับเริ่มต้น, 2=ระดับกลาง, 3=ระดับสูง)' AFTER wpt_days_per_week;

-- -----------------------------------------------------------------------------
-- plan_template_detail
-- -----------------------------------------------------------------------------
ALTER TABLE plan_template_detail
  MODIFY COLUMN ptd_id int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสรายละเอียดแผนแนะนำ [PK]',
  MODIFY COLUMN ptd_day_number int(11) NOT NULL COMMENT 'ลำดับวันที่ในแผน' AFTER ptd_id,
  MODIFY COLUMN ptd_day_name varchar(50) DEFAULT NULL COMMENT 'ชื่อเรียกวันฝึก' AFTER ptd_day_number,
  MODIFY COLUMN ptd_sets int(11) DEFAULT NULL COMMENT 'จำนวนเซต' AFTER ptd_day_name,
  MODIFY COLUMN ptd_reps varchar(20) DEFAULT NULL COMMENT 'จำนวนครั้ง' AFTER ptd_sets,
  MODIFY COLUMN ptd_rest_seconds int(11) DEFAULT 90 COMMENT 'เวลาพัก' AFTER ptd_reps,
  MODIFY COLUMN ptd_order int(11) NOT NULL DEFAULT 1 COMMENT 'ลำดับท่าในวันนั้น (คำนวณโดย server เสมอ ไม่รับค่าจาก client)' AFTER ptd_rest_seconds,
  MODIFY COLUMN wpt_id int(10) unsigned NOT NULL COMMENT 'รหัสแผนแนะนำ [FK -> workout_plan_template]' AFTER ptd_order,
  MODIFY COLUMN wet_id int(10) unsigned DEFAULT NULL COMMENT 'รหัสท่าฝึกเวทเทรนนิ่ง [FK -> weight_exercises]' AFTER wpt_id;

-- -----------------------------------------------------------------------------
-- member_profile (ลำดับใหม่: mb_id, mb_full_name, mb_email, mb_password_hash, mb_otp,
-- mb_otp_expired, mb_is_verified, mb_birth_date, mb_gender, mb_profile_pic, mb_created_at, mb_updated_at)
-- -----------------------------------------------------------------------------
ALTER TABLE member_profile
  MODIFY COLUMN mb_full_name varchar(100) NOT NULL COMMENT 'ชื่อ - นามสกุล' AFTER mb_id,
  MODIFY COLUMN mb_email varchar(100) NOT NULL COMMENT 'อีเมลผู้ใช้งาน' AFTER mb_full_name,
  MODIFY COLUMN mb_password_hash varchar(255) NOT NULL COMMENT 'รหัสผ่าน' AFTER mb_email,
  MODIFY COLUMN mb_otp varchar(6) DEFAULT NULL COMMENT 'รหัสยืนยันตัวตน 6 หลัก (OTP)' AFTER mb_password_hash,
  MODIFY COLUMN mb_otp_expired datetime DEFAULT NULL COMMENT 'วันและเวลาที่รหัส OTP หมดอายุ' AFTER mb_otp,
  MODIFY COLUMN mb_is_verified tinyint(4) DEFAULT 0 COMMENT 'สถานะการยืนยันตัวตน (0=ยังไม่ยืนยัน, 1=ยืนยันแล้ว)' AFTER mb_otp_expired,
  MODIFY COLUMN mb_birth_date date DEFAULT NULL COMMENT 'วัน เดือน ปีเกิด' AFTER mb_is_verified,
  MODIFY COLUMN mb_gender tinyint(4) DEFAULT NULL COMMENT 'เพศ (1=ชาย, 2=หญิง)' AFTER mb_birth_date,
  MODIFY COLUMN mb_profile_pic varchar(255) DEFAULT NULL COMMENT 'รูปโปรไฟล์' AFTER mb_gender,
  MODIFY COLUMN mb_created_at timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'วันที่สมัครสมาชิก' AFTER mb_profile_pic;

-- -----------------------------------------------------------------------------
-- member_body_stats (ลำดับใหม่: mbs_id, mbs_height, mbs_weight, mbs_activity_level,
-- mbs_target, mbs_recorded_date, mb_id) — เดิมไม่มี comment เลยยกเว้น mbs_id, เติมให้ครบ
-- -----------------------------------------------------------------------------
ALTER TABLE member_body_stats
  MODIFY COLUMN mbs_height decimal(5,2) DEFAULT NULL COMMENT 'ส่วนสูง (ซม.)' AFTER mbs_id,
  MODIFY COLUMN mbs_weight decimal(5,2) DEFAULT NULL COMMENT 'น้ำหนัก (กก.)' AFTER mbs_height,
  MODIFY COLUMN mbs_activity_level decimal(4,3) DEFAULT NULL COMMENT 'Activity Factor ตัวคูณ TDEE (ไม่ใช่ความถี่การออกกำลังกายต่อสัปดาห์) ค่าที่เป็นไปได้: 1.2 / 1.375 / 1.55 / 1.725 / 1.9' AFTER mbs_weight,
  MODIFY COLUMN mbs_target tinyint(4) DEFAULT NULL COMMENT 'เป้าหมาย (1=ลดน้ำหนัก, 2=เพิ่มน้ำหนัก, 3=รักษาน้ำหนัก)' AFTER mbs_activity_level,
  MODIFY COLUMN mbs_recorded_date datetime DEFAULT NULL COMMENT 'วันและเวลาที่บันทึกข้อมูล (ระบบ auto-set ตอนบันทึกไม่ใช่ช่องกรอกในฟอร์ม)' AFTER mbs_target,
  MODIFY COLUMN mb_id int(11) DEFAULT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]' AFTER mbs_recorded_date;

-- -----------------------------------------------------------------------------
-- member_bmr_history — ลำดับคอลัมน์ตรงกับ Datadic อยู่แล้ว แก้แค่ comment 2 ช่อง
-- -----------------------------------------------------------------------------
ALTER TABLE member_bmr_history
  MODIFY COLUMN mbh_bmr decimal(7,2) DEFAULT NULL COMMENT 'อัตราการเผาผลาญพื้นฐาน',
  MODIFY COLUMN mbh_tdee decimal(7,2) DEFAULT NULL COMMENT 'พลังงานที่ใช้ต่อวัน';

-- -----------------------------------------------------------------------------
-- workout_schedules — ลำดับคอลัมน์ตรงกับ Datadic อยู่แล้ว แก้แค่ comment
-- -----------------------------------------------------------------------------
ALTER TABLE workout_schedules
  MODIFY COLUMN wsch_plan_name varchar(100) NOT NULL COMMENT 'ชื่อแผนที่สมาชิกกำหนด (denormalized ซ้ำทุกแถวของ mb_id เดียวกัน)',
  MODIFY COLUMN wsch_days_per_week tinyint(4) NOT NULL DEFAULT 3 COMMENT 'จำนวนวันฝึกต่อสัปดาห์ของแผน (1-7)',
  MODIFY COLUMN wsch_day_number tinyint(4) NOT NULL DEFAULT 0 COMMENT 'ลำดับวันที่ในแผน (1-7, 0=แถวหัวแผนที่ยังไม่มีท่าฝึก)',
  MODIFY COLUMN wsch_day_name varchar(50) DEFAULT NULL COMMENT 'ชื่อเรียกวันฝึก',
  MODIFY COLUMN wsch_order tinyint(4) NOT NULL DEFAULT 1 COMMENT 'ลำดับท่าในวันนั้น (คำนวณโดย server เสมอ)',
  MODIFY COLUMN wsch_sets tinyint(4) NOT NULL DEFAULT 3 COMMENT 'จำนวนเซต',
  MODIFY COLUMN wsch_reps varchar(20) NOT NULL DEFAULT '10' COMMENT 'จำนวนครั้ง',
  MODIFY COLUMN wsch_rest_seconds smallint(6) NOT NULL DEFAULT 90 COMMENT 'เวลาพัก (วินาที)',
  MODIFY COLUMN wsch_plan_created_at datetime DEFAULT current_timestamp() COMMENT 'วันที่สร้างแผน (denormalized ซ้ำทุกแถวของ mb_id เดียวกัน)',
  MODIFY COLUMN wsch_plan_updated_at datetime DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'วันที่แก้ไขแผนล่าสุด (denormalized เช่นกัน)',
  MODIFY COLUMN mb_id int(11) NOT NULL COMMENT 'รหัสสมาชิกเจ้าของแผน [FK -> member_profile] 1 สมาชิกมีแผนได้แค่ 1 แผนเสมอ',
  MODIFY COLUMN wpt_id int(10) unsigned DEFAULT NULL COMMENT 'แผนแนะนำต้นทางถ้าคัดลอกมาจากแม่แบบ [FK -> workout_plan_template] NULL = สร้างแผนเอง',
  MODIFY COLUMN wet_id int(10) unsigned DEFAULT NULL COMMENT 'รหัสท่าฝึกเวทเทรนนิ่ง [FK -> weight_exercises] NULL = แถวหัวแผน (ยังไม่มีท่าฝึก)';

-- -----------------------------------------------------------------------------
-- daily_nutrition (ลำดับใหม่: dntt_id, dntt_date, dntt_image, dntt_food_name, dntt_quantity,
-- dntt_unit, dntt_meal_type, dntt_total_calories, dntt_total_protein, dntt_total_carb,
-- dntt_total_fat, dntt_time, dntt_created_at, dntt_updated_at, mb_id, ntt_id)
-- -----------------------------------------------------------------------------
ALTER TABLE daily_nutrition
  MODIFY COLUMN dntt_image varchar(255) DEFAULT NULL COMMENT 'Path รูปภาพอาหาร' AFTER dntt_date,
  MODIFY COLUMN dntt_food_name varchar(100) DEFAULT NULL COMMENT 'ชื่ออาหาร' AFTER dntt_image,
  MODIFY COLUMN dntt_quantity decimal(5,2) DEFAULT NULL COMMENT 'จำนวนที่บริโภค' AFTER dntt_food_name,
  MODIFY COLUMN dntt_unit varchar(50) DEFAULT NULL COMMENT 'หน่วยนับของอาหาร' AFTER dntt_quantity,
  MODIFY COLUMN dntt_meal_type tinyint(4) DEFAULT NULL COMMENT 'มื้ออาหาร (1=มื้อเช้า, 2=มื้อกลางวัน, 3=มื้อเย็น, 4=มื้อว่าง)' AFTER dntt_unit,
  MODIFY COLUMN dntt_total_calories decimal(7,2) DEFAULT NULL COMMENT 'ผลรวมแคลอรี่สุทธิ' AFTER dntt_meal_type,
  MODIFY COLUMN dntt_total_protein decimal(5,2) DEFAULT NULL COMMENT 'ผลรวมโปรตีนสุทธิ (กรัม)' AFTER dntt_total_calories,
  MODIFY COLUMN dntt_total_carb decimal(5,2) DEFAULT NULL COMMENT 'ผลรวมคาร์โบไฮเดรตสุทธิ (กรัม)' AFTER dntt_total_protein,
  MODIFY COLUMN dntt_total_fat decimal(5,2) DEFAULT NULL COMMENT 'ผลรวมไขมันสุทธิ (กรัม)' AFTER dntt_total_carb,
  MODIFY COLUMN dntt_time time DEFAULT NULL COMMENT 'เวลาที่กิน (ระบบ auto-set ตอนบันทึก ไม่ใช่ช่องกรอกในฟอร์ม)' AFTER dntt_total_fat,
  MODIFY COLUMN dntt_created_at timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'วันที่บันทึกรายการ' AFTER dntt_time,
  MODIFY COLUMN dntt_updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'วันที่แก้ไขข้อมูลล่าสุด' AFTER dntt_created_at,
  MODIFY COLUMN mb_id int(11) NOT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]' AFTER dntt_updated_at,
  MODIFY COLUMN ntt_id int(11) DEFAULT NULL COMMENT 'รหัสโภชนาการ [FK -> nutrition]' AFTER mb_id;

-- -----------------------------------------------------------------------------
-- weight_training_result — ลำดับคอลัมน์เกือบตรงแล้ว สลับแค่ wtrs_weight/wtrs_reps
-- (target: wtrs_id, wtrs_date, wtrs_set_no, wtrs_weight, wtrs_reps, wtrs_intensity_level,
-- wtrs_calories, mb_id, wet_id, wsch_id) — เดิมไม่มี comment เลยยกเว้น wtrs_id เติมให้ครบ
-- -----------------------------------------------------------------------------
ALTER TABLE weight_training_result
  MODIFY COLUMN wtrs_date date DEFAULT NULL COMMENT 'วันที่บันทึกผลการฝึก',
  MODIFY COLUMN wtrs_set_no bigint(20) DEFAULT NULL COMMENT 'หมายเลขเซต',
  MODIFY COLUMN wtrs_weight decimal(5,2) DEFAULT NULL COMMENT 'น้ำหนักที่ยก (กก.)' AFTER wtrs_set_no,
  MODIFY COLUMN wtrs_reps bigint(20) DEFAULT NULL COMMENT 'จำนวนครั้งที่ยกได้' AFTER wtrs_weight,
  MODIFY COLUMN wtrs_intensity_level tinyint(4) DEFAULT 2 COMMENT 'ระดับความหนักของการฝึก (1=เบา, 2=กลาง, 3=หนัก) ใช้กำหนดค่า MET เพื่อคำนวณแคลอรี่',
  MODIFY COLUMN wtrs_calories decimal(7,2) DEFAULT NULL COMMENT 'แคลอรี่ที่เผาผลาญ (สุทธิ หักฐาน 1 MET แล้ว)',
  MODIFY COLUMN mb_id int(11) DEFAULT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]',
  MODIFY COLUMN wet_id int(10) unsigned DEFAULT NULL COMMENT 'รหัสท่าฝึกเวทเทรนนิ่ง [FK -> weight_exercises]',
  MODIFY COLUMN wsch_id int(10) unsigned DEFAULT NULL COMMENT 'รหัสตารางกำหนดการออกกำลังกาย [FK -> workout_schedules]';

-- -----------------------------------------------------------------------------
-- cardio_result — ลำดับคอลัมน์ตรงกับ Datadic อยู่แล้ว เดิมไม่มี comment เลยยกเว้น cdors_id
-- เติมให้ครบ
-- -----------------------------------------------------------------------------
ALTER TABLE cardio_result
  MODIFY COLUMN cdors_date date DEFAULT NULL COMMENT 'วันที่คาร์ดิโอ',
  MODIFY COLUMN cdors_duration bigint(20) DEFAULT NULL COMMENT 'ระยะเวลา (นาที)',
  MODIFY COLUMN cdors_distance decimal(5,2) DEFAULT 0.00 COMMENT 'ระยะทาง (กม., ส่งมาเฉพาะกิจกรรมที่ cdo_has_distance=1)',
  MODIFY COLUMN cdors_calories decimal(7,2) DEFAULT NULL COMMENT 'แคลอรี่ที่เผาผลาญ (สุทธิ หักฐาน 1 MET แล้ว)',
  MODIFY COLUMN mb_id int(11) DEFAULT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]',
  MODIFY COLUMN cdo_id int(10) unsigned DEFAULT NULL COMMENT 'รหัสคาร์ดิโอ [FK -> cardio]';
