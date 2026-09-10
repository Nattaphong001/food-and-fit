-- เติม comment ฟิลด์ที่ยังขาด + จัดลำดับคอลัมน์ฝั่งผู้ใช้งาน (FK อยู่ท้ายสุดเสมอ)
-- ตารางฝั่งแอดมิน/แคตาล็อก (muscle_group, weight_exercises, cardio, nutrition, workout_plan_template ฯลฯ)
-- มี comment ครบและไม่ต้องจัดลำดับใหม่แล้ว — ไม่แตะ (ตามคำสั่ง "ข้อมูลระบบไม่ต้องทำอะไร")
--
-- Backup ก่อนรัน: migrations/backups/backup_full_before_mwp_merge_20260904_201921.sql

-- =========================================================
-- member_body_stats — ฝั่งผู้ใช้งาน: ลำดับตามหน้าบันทึกสัดส่วนร่างกาย, mb_id (FK) ไปท้ายสุด
-- =========================================================
ALTER TABLE member_body_stats
  MODIFY COLUMN mbs_weight decimal(5,2) DEFAULT NULL COMMENT 'น้ำหนักตัว (กก.)' AFTER mbs_id,
  MODIFY COLUMN mbs_height decimal(5,2) DEFAULT NULL COMMENT 'ส่วนสูง (ซม.)' AFTER mbs_weight,
  MODIFY COLUMN mbs_activity_level decimal(4,3) DEFAULT NULL COMMENT 'Activity Factor ใช้คูณ BMR หา TDEE (1.2/1.375/1.55/1.725/1.9) — ไม่ใช่ความถี่ออกกำลังกาย/สัปดาห์' AFTER mbs_height,
  MODIFY COLUMN mbs_target tinyint(4) DEFAULT NULL COMMENT 'เป้าหมาย (1=ลดน้ำหนัก, 2=เพิ่มน้ำหนัก/กล้ามเนื้อ, 3=รักษาน้ำหนัก)' AFTER mbs_activity_level,
  MODIFY COLUMN mbs_recorded_date datetime DEFAULT NULL COMMENT 'วันเวลาที่บันทึกค่านี้' AFTER mbs_target,
  MODIFY COLUMN mb_id int(11) DEFAULT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]' AFTER mbs_recorded_date;

-- =========================================================
-- member_bmr_history — comment ครบอยู่แล้ว จัดลำดับ: ข้อมูลก่อน แล้ว FK (mb_id, mbs_id) ไปท้ายสุด
-- =========================================================
ALTER TABLE member_bmr_history
  MODIFY COLUMN mbh_record_date date NOT NULL COMMENT 'วันที่บันทึกและวิเคราะห์' AFTER mbh_id,
  MODIFY COLUMN mbh_bmi decimal(4,2) DEFAULT NULL COMMENT 'ค่าดัชนีมวลกาย (BMI)' AFTER mbh_record_date,
  MODIFY COLUMN mbh_bmr decimal(7,2) DEFAULT NULL COMMENT 'Basal Metabolic Rate (อัตราการเผาผลาญพื้นฐาน)' AFTER mbh_bmi,
  MODIFY COLUMN mbh_tdee decimal(7,2) DEFAULT NULL COMMENT 'Total Daily Energy Expenditure (พลังงานรวมที่เผาผลาญต่อวัน)' AFTER mbh_bmr,
  MODIFY COLUMN mbh_tdee_target decimal(7,2) DEFAULT NULL COMMENT 'TDEE เป้าหมาย' AFTER mbh_tdee,
  MODIFY COLUMN mb_id int(11) NOT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]' AFTER mbh_tdee_target,
  MODIFY COLUMN mbs_id int(11) DEFAULT NULL COMMENT 'รหัสประวัติร่างกายผู้ใช้ [FK -> member_body_stats]' AFTER mb_id;

-- =========================================================
-- daily_nutrition — comment ครบอยู่แล้ว จัดลำดับ: ข้อมูลก่อน แล้ว FK (mb_id, ntt_id) ไปท้ายสุด
-- =========================================================
ALTER TABLE daily_nutrition
  MODIFY COLUMN dntt_date date NOT NULL COMMENT 'วันที่บันทึก' AFTER dntt_id,
  MODIFY COLUMN dntt_time time DEFAULT NULL COMMENT 'เวลาที่รับประทาน' AFTER dntt_date,
  MODIFY COLUMN dntt_meal_type tinyint(4) DEFAULT NULL COMMENT 'มื้ออาหาร (1=เช้า, 2=กลาง, 3=เย็น, 4=ว่าง)' AFTER dntt_time,
  MODIFY COLUMN dntt_food_name varchar(100) DEFAULT NULL COMMENT 'ชื่ออาหารที่บันทึก' AFTER dntt_meal_type,
  MODIFY COLUMN dntt_quantity decimal(5,2) DEFAULT NULL COMMENT 'จำนวนที่บริโภค' AFTER dntt_food_name,
  MODIFY COLUMN dntt_unit varchar(50) DEFAULT NULL COMMENT 'หน่วยนับของอาหาร' AFTER dntt_quantity,
  MODIFY COLUMN dntt_total_calories decimal(7,2) DEFAULT NULL COMMENT 'ผลรวมแคลอรี่สุทธิ' AFTER dntt_unit,
  MODIFY COLUMN dntt_total_protein decimal(5,2) DEFAULT NULL COMMENT 'ผลรวมโปรตีนสุทธิ (กรัม)' AFTER dntt_total_calories,
  MODIFY COLUMN dntt_total_carb decimal(5,2) DEFAULT NULL COMMENT 'ผลรวมคาร์โบไฮเดรตสุทธิ (กรัม)' AFTER dntt_total_protein,
  MODIFY COLUMN dntt_total_fat decimal(5,2) DEFAULT NULL COMMENT 'ผลรวมไขมันสุทธิ (กรัม)' AFTER dntt_total_carb,
  MODIFY COLUMN dntt_image varchar(255) DEFAULT NULL COMMENT 'Path รูปภาพอาหาร' AFTER dntt_total_fat,
  MODIFY COLUMN dntt_created_at timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'วันที่บันทึกรายการ' AFTER dntt_image,
  MODIFY COLUMN dntt_updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'วันที่แก้ไขข้อมูลล่าสุด' AFTER dntt_created_at,
  MODIFY COLUMN mb_id int(11) NOT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]' AFTER dntt_updated_at,
  MODIFY COLUMN ntt_id int(11) DEFAULT NULL COMMENT 'รหัสโภชนาการอาหาร [FK -> nutrition]' AFTER mb_id;

-- =========================================================
-- weight_training_result — ลำดับ FK ท้ายสุดอยู่แล้ว (mb_id, wet_id, wsch_id) แค่เติม comment ที่ขาด
-- =========================================================
ALTER TABLE weight_training_result
  MODIFY COLUMN wtrs_date date DEFAULT NULL COMMENT 'วันที่ออกกำลังกายจริง',
  MODIFY COLUMN wtrs_set_no bigint(20) DEFAULT NULL COMMENT 'ลำดับเซตที่เท่าไหร่ของท่านี้ในวันนั้น (นับต่อเนื่องไม่รีเซ็ตแม้แบ่งหลายรอบ)',
  MODIFY COLUMN wtrs_reps bigint(20) DEFAULT NULL COMMENT 'จำนวนครั้งที่ทำได้จริงในเซตนี้',
  MODIFY COLUMN wtrs_weight decimal(5,2) DEFAULT NULL COMMENT 'น้ำหนักที่ยกจริง (กก.)',
  MODIFY COLUMN wtrs_intensity_level tinyint(4) DEFAULT 2 COMMENT 'ระดับความหนัก (1=เบา METs 3.5, 2=กลาง METs 5.0, 3=หนัก METs 6.0)',
  MODIFY COLUMN wtrs_calories decimal(7,2) DEFAULT NULL COMMENT 'แคลอรี่ที่เผาผลาญสุทธิ (NET, หัก 1 MET แล้ว)',
  MODIFY COLUMN mb_id int(11) DEFAULT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]',
  MODIFY COLUMN wet_id int(10) unsigned DEFAULT NULL COMMENT 'รหัสท่าฝึกเวท [FK -> weight_exercises]',
  MODIFY COLUMN wsch_id int(10) unsigned DEFAULT NULL COMMENT 'รหัสรายการในแผนฝึกที่ทำท่านี้ [FK -> workout_schedules] NULL = ไม่ได้ผูกกับแผน';

-- =========================================================
-- cardio_result — ลำดับ FK ท้ายสุดอยู่แล้ว (mb_id, cdo_id) แค่เติม comment ที่ขาด
-- =========================================================
ALTER TABLE cardio_result
  MODIFY COLUMN cdors_date date DEFAULT NULL COMMENT 'วันที่ออกกำลังกายจริง',
  MODIFY COLUMN cdors_duration bigint(20) DEFAULT NULL COMMENT 'ระยะเวลาที่ทำ (นาที)',
  MODIFY COLUMN cdors_distance decimal(5,2) DEFAULT 0.00 COMMENT 'ระยะทางที่ทำได้ (กม.) ถ้ากิจกรรมนั้นมีระยะทาง',
  MODIFY COLUMN cdors_calories decimal(7,2) DEFAULT NULL COMMENT 'แคลอรี่ที่เผาผลาญสุทธิ (NET, หัก 1 MET แล้ว)',
  MODIFY COLUMN mb_id int(11) DEFAULT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]',
  MODIFY COLUMN cdo_id int(10) unsigned DEFAULT NULL COMMENT 'รหัสกิจกรรมคาร์ดิโอ [FK -> cardio]';

-- =========================================================
-- audit_logs / revoked_tokens — ตารางภายในระบบ ไม่ใช่ฝั่งผู้ใช้งาน จึงไม่จัดลำดับใหม่ แค่เติม comment
-- =========================================================
ALTER TABLE audit_logs
  MODIFY COLUMN actor_type varchar(20) DEFAULT NULL COMMENT 'ประเภทผู้กระทำ (เช่น admin, member, system)',
  MODIFY COLUMN actor_id bigint(20) DEFAULT NULL COMMENT 'รหัสผู้กระทำ (mb_id หรือ sys_id แล้วแต่ actor_type)',
  MODIFY COLUMN action varchar(50) DEFAULT NULL COMMENT 'ชนิดการกระทำ (create/update/delete)',
  MODIFY COLUMN detail varchar(255) DEFAULT NULL COMMENT 'รายละเอียดเพิ่มเติมของการกระทำ',
  MODIFY COLUMN table_name varchar(64) DEFAULT NULL COMMENT 'ชื่อตารางที่ถูกแก้ไข',
  MODIFY COLUMN record_id varchar(64) DEFAULT NULL COMMENT 'รหัสแถวที่ถูกแก้ไขในตารางนั้น',
  MODIFY COLUMN old_value longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL COMMENT 'ค่าเดิมก่อนแก้ไข (JSON)' CHECK (json_valid(`old_value`)),
  MODIFY COLUMN new_value longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL COMMENT 'ค่าใหม่หลังแก้ไข (JSON)' CHECK (json_valid(`new_value`)),
  MODIFY COLUMN ip_address varchar(45) DEFAULT NULL COMMENT 'IP Address ของผู้กระทำ',
  MODIFY COLUMN created_at datetime(3) DEFAULT NULL COMMENT 'วันเวลาที่เกิดเหตุการณ์นี้';

ALTER TABLE revoked_tokens
  MODIFY COLUMN jti varchar(64) NOT NULL COMMENT 'JWT ID ของโทเคนที่ถูกเพิกถอน',
  MODIFY COLUMN expires_at datetime(3) NOT NULL COMMENT 'วันเวลาหมดอายุเดิมของโทเคน (ลบแถวได้หลังพ้นเวลานี้)',
  MODIFY COLUMN created_at datetime(3) DEFAULT NULL COMMENT 'วันเวลาที่เพิกถอนโทเคนนี้';
