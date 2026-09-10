# SPEC — ข้อกำหนดทางเทคนิคของระบบ Food & Fit

เอกสารนี้คือแหล่งอ้างอิงเดียวของกติกาที่ต้องตรงกันทั้ง 3 ส่วน (`backend/`, `mobile/`, `admin-web/`)
คอมเมนต์ในโค้ดที่เขียนว่า "ดู docs/SPEC.md ข้อ N" ชี้มาที่หัวข้อในไฟล์นี้

---

## 1. ขอบเขตและสถาปัตยกรรม

| ส่วน | เทคโนโลยี | หน้าที่ |
|---|---|---|
| `backend/` | Go 1.25 + Gin + GORM + MySQL/MariaDB | REST API (port 8081) แหล่งความจริงของสูตรคำนวณทั้งหมด |
| `mobile/` | Flutter (Dart SDK ^3.9.2) | แอปฝั่งสมาชิก — บันทึกอาหาร/การฝึก ดูรายงาน |
| `admin-web/` | Flutter Web (port 8090) | แอปฝั่งผู้ดูแลระบบ — จัดการข้อมูลหลักและสมาชิก |

**หลักการสำคัญ:** สูตรคำนวณสุขภาพทุกตัวเป็นเจ้าของโดย `backend/services/calculator.go`
(`CalculateGoals`, `CalculateBaselineExpenditure`, `CalculateAge`, `CalculateWeightTrainingCalories`)
ฝั่ง Dart **ห้ามคำนวณซ้ำ** ต้องเรียก API เสมอ ยกเว้น Training Volume และ Estimated 1RM
ที่อนุญาตให้คำนวณฝั่ง Dart เพื่อแสดงผลสดก่อนบันทึก (ไม่เขียนลงฐานข้อมูล)

---

## 2. กติกา API Contract

- รูปแบบ response เดียวกันทั้งระบบ: `{ "success": bool, "message": string, "data": object }`
- **ห้ามแก้ signature หรือรูปแบบ response ของ endpoint ที่แอปเวอร์ชันเผยแพร่แล้วเรียกใช้อยู่**
  ต้องการข้อมูลเพิ่ม ให้เพิ่ม endpoint ใหม่หรือเพิ่มคีย์ใหม่แบบ backward compatible เท่านั้น
- ยืนยันตัวตนด้วย JWT + denylist (`revoked_tokens.jti`) — logout และเปลี่ยนรหัสผ่านต้องบันทึก `jti`
- ทุก action ที่แก้ข้อมูลสำคัญต้องเขียน `audit_logs`
- ทุก query ใช้ parameter binding ห้ามต่อ string ดิบ

---

## 3. ฐานข้อมูล (`food_and_fit_db`)

Engine InnoDB · Charset `utf8mb4` · Collation `utf8mb4_unicode_ci` ทุกตาราง

### 3.1 กติกาตั้งชื่อคอลัมน์

แต่ละตารางมี prefix ของตัวเอง และใช้ `<prefix>_id` เป็น PK เสมอ

| prefix | ตาราง | prefix | ตาราง |
|---|---|---|---|
| `sys_` | system_data | `wsch_` | workout_schedules |
| `mb_` | member_profile | `wpt_` | workout_plan_template |
| `mbs_` | member_body_stats | `ptd_` | plan_template_detail |
| `mbh_` | member_bmr_history | `wet_` | weight_exercises |
| `mug_` | muscle_group | `emd_` | exercise_muscle_details |
| `dntt_` | daily_nutrition | `cdo_` | cardio |
| `ntt_` | nutrition | `cdc_` | cardio_category |
| `nttc_` | nutrition_category | `wtrs_` | weight_training_result |
| | | `cdors_` | cardio_result |

### 3.2 กติกาแปลงชนิดข้อมูลฝั่ง Go

- คอลัมน์ `int unsigned` ใช้ `uint`/`uint32` ห้ามใช้ `int` (bind ไม่ผ่าน)
- คอลัมน์ nullable ที่ค่า NULL มีความหมายต่างจาก 0 ให้ใช้ `*T` หรือ `sql.NullXxx` ห้าม default 0
- `DECIMAL` ของค่าพลังงานรับเป็น `float64` ปัดเศษตอนแสดงผลเท่านั้น ห้ามปัดตอนเก็บ
- ตารางที่สคีมานิ่งแล้วให้ถอดออกจาก `AutoMigrate` และจัดการผ่าน migration script อย่างเดียว (ดูข้อ 6 D10.1)

### 3.3 ตารางในระบบ

ตารางธุรกิจ 18 ตารางตามพจนานุกรมข้อมูล ได้แก่ `system_data`, `member_profile`,
`member_body_stats`, `member_bmr_history`, `muscle_group`, `weight_exercises`,
`exercise_muscle_details`, `cardio_category`, `cardio`, `nutrition_category`, `nutrition`,
`workout_plan_template`, `plan_template_detail`, `workout_schedules`, `daily_nutrition`,
`weight_training_result`, `cardio_result` และตารางเชื่อมกล้ามเนื้อของท่าฝึก
นอกจากนี้มีตารางภายในระบบอีก 2 ตารางที่ไม่อยู่ใน ER คือ `audit_logs` และ `revoked_tokens`

### 3.4 กติกา Foreign Key (ต้องรู้ก่อนเขียน DELETE)

| ลบอะไร | ผลที่ตามมา |
|---|---|
| `member_profile` | CASCADE ลบ body_stats, bmr_history, daily_nutrition, wtrs, cdors, wsch ทั้งหมด |
| `nutrition` | `daily_nutrition.ntt_id` → SET NULL (ประวัติการกินยังอยู่) |
| `weight_exercises` | `wtrs.wet_id`, `ptd.wet_id` → SET NULL · `wsch.wet_id` → CASCADE |
| `cardio` | `cdors.cdo_id` → SET NULL |
| `workout_plan_template` | `wsch.wpt_id` → SET NULL · `ptd` → CASCADE |
| `workout_schedules` | `wtrs.wsch_id` → SET NULL (ประวัติผลการฝึกไม่หายตามแผน) |
| `muscle_group` | `wet.mug_id` → SET NULL · `emd` → CASCADE |
| `member_body_stats` | `mbh.mbs_id` → SET NULL |

### 3.5 คำศัพท์มาตรฐาน — เป้าหมายสุขภาพ

ระบบมีเป้าหมายสุขภาพ 3 ค่าเท่านั้น (`mbs_target` = 1/2/3) ใช้คำเหล่านี้ทุกที่ทั้งใน UI และคอมเมนต์

| ค่า | เป้าหมาย | Target Calories | สัดส่วนมาโคร C:P:F |
|---|---|---|---|
| 1 | ลดน้ำหนัก | TDEE − 20% (ไม่ต่ำกว่า BMR) | 35 : 40 : 25 |
| 2 | เพิ่มน้ำหนัก | TDEE + 15% | 50 : 30 : 20 |
| 3 | รักษาน้ำหนัก | TDEE | 50 : 20 : 30 |

### 3.6 ตารางแบบ append-only

`member_bmr_history` เป็น append-only โดยตั้งใจ (1 วัน = 1 จุดข้อมูลบนกราฟแนวโน้ม)
**ห้ามเพิ่ม UNIQUE constraint บน `(mb_id, mbh_record_date)`** เพราะขัดกับดีไซน์ของกราฟประวัติ
การกันแถวซ้ำใช้วิธี upsert รายวันในโค้ดแทน (ดูข้อ 6 D10)

`audit_logs` และ `revoked_tokens` ยังอยู่ใน `AutoMigrate` — ข้อความใน `comment:` ของ gorm tag
(`models/security.go`) ต้องตรงกับ migration แบบตัวอักษรต่อตัวอักษร ไม่งั้น GORM จะสั่ง `ALTER`
แก้ไปมาทุกครั้งที่ start server

---

## 4. FEATURE_TAG มาตรฐาน

ใช้ชุดเดียวกันทั้ง Go และ Dart เพื่อค้นข้ามฝั่งได้ (`grep -rn "[FEATURE] CARDIO"`) ห้ามตั้ง tag ใหม่

`AUTH` · `PROFILE` · `BMR_TDEE` · `WORKOUT_PLAN` · `FOOD_LOG` · `WEIGHT_TRAINING` · `CARDIO` ·
`ENERGY_BALANCE` · `REPORT` · `COMMON_UI`

---

## 5. สูตรคำนวณ

ตัวเลขทุกตัวในหัวข้อนี้ตรงกับที่ระบุไว้ในเอกสารประกอบปริญญานิพนธ์ **ห้ามแก้**

### 5.1 คำนวณตอนตั้งค่าหรือแก้ไขข้อมูลร่างกาย เก็บที่ `member_bmr_history`

| สูตร | สมการ | คอลัมน์ |
|---|---|---|
| BMI | น้ำหนัก(kg) ÷ ส่วนสูง(m)² | `mbh_bmi` |
| BMR ชาย | (10 × kg) + (6.25 × cm) − (5 × อายุ) + 5 | `mbh_bmr` |
| BMR หญิง | (10 × kg) + (6.25 × cm) − (5 × อายุ) − 161 | `mbh_bmr` |
| TDEE | BMR × Activity Factor (1.2 / 1.375 / 1.55 / 1.725 / 1.9) | `mbh_tdee` |
| Target ลดน้ำหนัก | TDEE − (TDEE × 20%) ถ้าได้ค่าต่ำกว่า BMR ให้ใช้ BMR | `mbh_tdee_target` |
| Target เพิ่มน้ำหนัก | TDEE + (TDEE × 15%) | `mbh_tdee_target` |
| Target รักษาน้ำหนัก | เท่ากับ TDEE | `mbh_tdee_target` |
| โปรตีน / คาร์บ (g) | (Target × %สารอาหาร) ÷ 4 | ไม่เก็บฐานข้อมูล |
| ไขมัน (g) | (Target × %ไขมัน) ÷ 9 | ไม่เก็บฐานข้อมูล |

ใช้สูตร BMR ของ Mifflin-St Jeor · เกณฑ์ BMI แบบเอเชีย-แปซิฟิก:
น้อยกว่า 18.5 ผอมเกินไป · 18.5–22.9 สมส่วน · 23.0–24.9 น้ำหนักเกิน · ตั้งแต่ 25.0 ขึ้นไป โรคอ้วน

### 5.2 คำนวณตอนบันทึกกิจกรรม

| สูตร | สมการ | คอลัมน์ |
|---|---|---|
| Cardio Burn | (METs − 1) × น้ำหนัก(kg) × เวลา(ชม.) — METs อ่านจากตาราง `cardio` ห้าม hardcode | `cdors_calories` |
| Weight Burn | (Final MET − 1) × น้ำหนัก(kg) × เวลา(ชม.) — Final MET มาจากข้อ 5.3 | `wtrs_calories` |

ทั้งสองค่าเก็บเป็นพลังงานสุทธิ (NET) คือหักฐาน 1 MET ออกแล้ว เพื่อไม่ให้ซ้ำกับ
Baseline Expenditure ที่นับพลังงานพื้นฐานไปแล้ว

### 5.3 Weight Training — Smart Auto Calorie

แทนการให้ผู้ใช้เลือกระดับความหนักเอง ระบบอนุมานค่า MET จากข้อมูลที่มีอยู่แล้ว 3 อย่าง
(ท่าที่ฝึก ความหนาแน่นของเซสชัน และสัดส่วนน้ำหนักที่ยกเทียบ 1RM) โดยคงสูตรฐาน
`(MET − 1) × kg × ชม.` เดิมทุกประการ สิ่งที่เปลี่ยนคือวิธีหาค่า MET เท่านั้น

```
Session Base MET   = Σ(Si × Mi) / Σ(Si)      Si = จำนวนเซตของท่า i, Mi = wet_base_met ของท่า i

T_eff (นาที)       = min(เวลารวมจริง, จำนวนเซตรวม × 4 นาที)   เพดานกันการนับเวลาพักซ้ำ
Density (นาที/เซต)  = T_eff / จำนวนเซตรวม

k_density : Density ≤ 1.0         → 1.20
            1.0 < Density < 3.0   → 1.20 − 0.15 × (Density − 1.0)
            Density ≥ 3.0         → 0.90

RI (%1RM) = น้ำหนักเฉลี่ยที่ยกในเซสชัน / Estimated 1RM ที่ดีที่สุดของสมาชิกในท่านั้น
            (ไม่มีประวัติ 1RM หรือเป็นท่า bodyweight → k_load = 1.00 ไม่เดา)
k_load    : RI < 50% → 0.90 · 50% ≤ RI < 70% → 1.00 · RI ≥ 70% → 1.10

Final MET = Session Base MET × k_load × k_density    จำกัดช่วง [1.5, 9.5]
Kcal      = (Final MET − 1) × น้ำหนักตัว(kg) × (T_eff ÷ 60)
```

ค่าที่ได้คำนวณครั้งเดียวทั้งเซสชันแล้วหารเท่ากันทุกเซตลง `wtrs_calories` เพื่อให้
`SUM(wtrs_calories) GROUP BY wtrs_date` ที่หน้ารายงานใช้อยู่ยังถูกต้องโดยไม่ต้องแก้ query

`wet_base_met` ในตาราง `weight_exercises` แบ่ง 4 กลุ่ม อิงช่วง 3.5–6.0 ของรหัสเวทเทรนนิ่ง
ใน Compendium of Physical Activities

| กลุ่ม | ค่า | เกณฑ์ |
|---|---|---|
| ท่าเดี่ยวข้อต่อเดียว (Isolation) | 3.0 | `wet_exercise_type = 2` |
| ท่าผสมหลายข้อต่อช่วงบน | 4.5 | `wet_exercise_type = 1` กล้ามเนื้อหลักอยู่ช่วงบน |
| ท่าผสมหลายข้อต่อช่วงล่าง | 5.5 | `wet_exercise_type = 1` กล้ามเนื้อหลักอยู่ช่วงล่าง |
| ทั้งตัว หรือยกลักษณะ Olympic | 7.0 | ใช้กล้ามเนื้อครบทั้งบน ล่าง และแกนกลาง เช่น Deadlift |

### 5.4 คำนวณตอนแสดงรายงาน (ไม่เก็บฐานข้อมูล)

| สูตร | สมการ |
|---|---|
| Energy In | SUM(อาหาร) + SUM(เครื่องดื่ม) |
| Baseline Expenditure | BMR × 1.2 (คงที่เสมอ ไม่ใช่ Activity Factor ของผู้ใช้) |
| Exercise Burn | SUM(Cardio) + SUM(Weight) |
| Total Daily Energy Output | Baseline Expenditure + Exercise Burn |
| Energy Balance | Energy In − Total Daily Energy Output |
| สถานะ Over | Energy In มากกว่า Target + 10% |
| สถานะ On Target | Target − 10% ≤ Energy In ≤ Target + 10% |
| สถานะ Under | Energy In น้อยกว่า Target − 10% |
| Training Volume (kg) | น้ำหนักที่ยก × Reps × Sets |
| Estimated 1RM | น้ำหนักที่ยก × (1 + Reps ÷ 30) แม่นยำที่สุดช่วง Reps 2–10 |

Training Volume และ Estimated 1RM เป็นค่าคำนวณเพื่อแสดงผลเท่านั้น **ห้ามสร้างคอลัมน์เก็บในฐานข้อมูล**

---

## 6. บันทึกการตัดสินใจด้านสคีมา

ใช้อ้างอิงเวลาพบว่าโค้ดหรือเอกสารไม่ตรงกับฐานข้อมูลจริง เก็บเฉพาะรายการที่ยังถูกอ้างถึงในคอมเมนต์โค้ด

### D3.2 — `workout_schedules` ถูกตัด `mb_id` / `wpt_id` / `wsch_date` ออกในรอบยุบตาราง

คอลัมน์เหล่านี้ derive ได้จากตารางแม่ทั้งหมด และ `wsch_date` ไม่เคยเก็บ "วันที่ฝึกจริง"
(ทุกแถวในแผนเดียวกันมีค่าเท่ากันหมด คือวันที่สร้างแผน) วันที่ฝึกจริงอยู่ที่ `wtrs_date` อยู่แล้ว
เป็นการ DROP ที่ตั้งใจ ไม่ใช่คอลัมน์หาย — ห้ามเติมกลับ

รอบเดียวกันนี้ `weight_exercises.mug_id` ถูกย้ายไปเป็นความสัมพันธ์หลายต่อหลายผ่าน
`exercise_muscle_details` ทำให้ JSON response เปลี่ยนจาก `muscle_group` (object)
เป็น `muscle_details` (array)

### D3.3 — ยุบ `member_workout_plans` กลับเข้า `workout_schedules` (สถานะปัจจุบัน)

1 สมาชิกมีแผนส่วนตัวได้สูงสุด 1 แผนเสมอ จึงไม่จำเป็นต้องมีตาราง header แยก
ข้อมูลระดับแผน (`wsch_plan_name`, `wsch_days_per_week`, `wsch_plan_created_at/updated_at`)
denormalize ซ้ำไว้ทุกแถวของสมาชิกคนเดียวกัน

**แถวหัวแผน (plan header)** คือแถวที่ `wet_id IS NULL` (`wsch_day_number = 0`) ใช้เก็บชื่อแผน
ตอนที่ยังไม่มีท่าฝึกสักท่า — query ที่ต้องการเฉพาะท่าฝึกจริงต้องกรอง `wet_id IS NOT NULL` เสมอ

หมายเหตุความเข้ากันได้: คีย์ `mwp_id` ที่ยังส่งอยู่ใน JSON response ไม่ใช่ FK จริงอีกต่อไป
แต่ส่งค่า `mb_id` ของสมาชิกเองแทน (คงคีย์ไว้เพื่อไม่ให้แอปเวอร์ชันเก่าพัง) ห้ามนำไป join ต่อ

### D5 — ความหมายของ `mbs_activity_level`

เก็บ **Activity Factor** (ตัวคูณ TDEE คือ 1.2 / 1.375 / 1.55 / 1.725 / 1.9) ไม่ใช่ "ความถี่การ
ออกกำลังกายต่อสัปดาห์" ตามที่พจนานุกรมข้อมูลฉบับแรกเขียนไว้ ค่าที่รับต้องเป็น 1 ใน 5 ค่ามาตรฐาน
เท่านั้น (`helpers.ValidateActivityLevel`) คอลัมน์เป็น `DECIMAL(4,3)` เพื่อเก็บ 1.375 / 1.725 ได้เต็มค่า

### D8 — ฟีเจอร์ลบบัญชีแบบ Grace Period ถูกตัดออกทั้งระบบ

`mb_status` และ `mb_deleted_at` ถูก DROP ออกจาก `member_profile` แล้ว ไม่มีคอลัมน์สถานะบัญชี
เหลืออยู่ — query สมาชิกจึงไม่ต้องกรองสถานะอีกต่อไป และห้ามเพิ่มคอลัมน์เหล่านี้กลับโดยไม่ได้ตัดสินใจใหม่

### D10 — Default value, COMMENT และการกันประวัติซ้ำ

- หน้าแก้ไขข้อมูลร่างกายเคยเขียน `member_bmr_history` 2 แถวต่อการกดบันทึก 1 ครั้ง
  (`EditProfile` และ `UpdateBodyStats` ยิงต่อกัน) แก้แล้วโดยให้ `UpdateBodyStats` รับ `gender`
  และ `birth_date` แบบ optional คำนวณทั้งชุดในทรานแซกชันเดียว ส่วน `EditProfile` จะคำนวณใหม่
  เฉพาะตอน **อายุเต็มปีเปลี่ยนจริงหรือเพศเปลี่ยนจริง** เท่านั้น
- `member_body_stats` และ `member_bmr_history` เปลี่ยนเป็น **upsert รายวัน** (มีแถวของวันนี้แล้วให้ UPDATE ทับ)
- เพิ่ม plausibility warning (ไม่บล็อกการบันทึก) เมื่อน้ำหนักเปลี่ยนเกิน 2 กก. หรือส่วนสูงเปลี่ยนเกิน 1 ซม.
- ข้อความ COMMENT ภาษาไทยต้องเขียนผ่านไฟล์ `.sql` แบบ UTF-8 แล้วสั่ง `mysql < file.sql` เท่านั้น
  การส่งผ่าน `mysql -e "..."` บน Windows ทำให้ข้อความ double-encode เพี้ยน

### D10.1 — GORM AutoMigrate เคยเขียนทับสคีมาเงียบทุกครั้งที่ restart

`MemberBodyStat`, `WeightTrainingResult`, `CardioResult` เคยอยู่ใน `AutoMigrate` และ gorm tag
ไม่ตรงกับฐานข้อมูลจริง ทำให้ทุกครั้งที่ start server คอลัมน์ถูกเด้งกลับ (`NOT NULL` หลุด,
`tinyint`/`smallint unsigned` กลายเป็น `bigint`, `decimal(6,2)` ขยายเป็น `decimal(7,2)`)

**แก้ถาวร 2 ชั้น:** แก้ gorm tag ให้ตรงฐานข้อมูลจริงทุกตัว **และ** ถอด 3 struct นี้ออกจาก
`AutoMigrate` ใน `config/database.go` ถาวร (เหลือเพียง `RevokedToken` และ `AuditLog`)
จากนี้ไปจัดการสคีมาผ่าน migration script เท่านั้น

**บทเรียน:** ถ้าตารางยังอยู่ใน `AutoMigrate` ห้ามเชื่อว่า "เอกสารบอกว่าแก้แล้ว" เท่ากับ
"ฐานข้อมูลยังเป็นแบบนั้นจริง" ต้อง query `information_schema.COLUMNS` สดก่อนเสมอ
