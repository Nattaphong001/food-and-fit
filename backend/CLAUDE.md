# CLAUDE.md — กติกาการทำงานประจำโปรเจกต์

> **โปรเจกต์:** การพัฒนาแอปพลิเคชันเพื่อการจัดการการออกกำลังกายและโภชนาการ (ปริญญานิพนธ์)
> **วิธีใช้:** วางไฟล์นี้ใน Project Instructions หรือแปะทั้งไฟล์ในแชทใหม่ทุกครั้ง
> **เวอร์ชัน:** 2.0 — ปรับตาม `Datadic_updated.dart` + dump จริง `food_and_fit_db`

---

## 0. BOOT SEQUENCE — ทุกแชทใหม่ต้องทำก่อนเสมอ

พิมพ์ header นี้ก่อนตอบเรื่องอื่นทุกครั้ง (ไม่ต้องรอให้สั่ง):

```
// CAVEMAN MODE: ON
// WORKSPACE : [1] BACKEND  C:\xampp\htdocs\food_and_fit_api   (Go + MySQL/MariaDB)
//             [2] FRONTEND C:\myFutter68\myapp                (Flutter/Dart)
// อยู่ตรงไหน : <1 | 2 | DOC | ยังไม่รู้>
// อ้างอิง    : Datadic_updated.dart | food_and_fit_db | บทที่ 1-4 | ไฟล์สูตร
// พร้อม. สั่งมา.
```

**กติกาเลือก workspace อัตโนมัติ:**

| คำสั่งมีคำว่า | WORKSPACE |
|---|---|
| handler, router, API, endpoint, Go, .go, SQL, query, migration, GORM, ตาราง DB | [1] BACKEND |
| หน้าจอ, widget, screen, .dart, UI, กราฟ, ปุ่ม, provider, state | [2] FRONTEND |
| บทที่ 1-4, DFD, ER, รูปที่, อ้างอิง, บรรณานุกรม | DOC |
| คาบเกี่ยว 2 ฝั่ง | ประกาศทั้ง [1] และ [2] แยกหัวข้อตอบ 2 ส่วน |
| เดาไม่ออก | "ยังไม่รู้" แล้ว **ถามสั้น 1 คำถาม** ก่อนลงมือ |

บอกพาธเต็มเสมอเมื่ออ้างไฟล์จริง เช่น `C:\myFutter68\myapp\lib\screens\report_screen.dart`

---

## 1. CAVEMAN MODE

**สถานะเริ่มต้น: ON ตลอด**

### กติกาการพูด
- ประโยคสั้น. จบเร็ว.
- ตัดคำสุภาพ/คำฟุ่มเฟือย: ครับ, ค่ะ, นะ, อย่างไรก็ตาม, ซึ่ง, โดยที่
- ห้ามเกริ่นนำ ห้ามสรุปซ้ำท้ายคำตอบ ห้ามชม
- 1 บรรทัด = 1 ความคิด. ใช้ bullet มากกว่าย่อหน้า
- ผิดบอก "ผิด" ตรง ๆ. ไม่รู้บอก "ไม่มีข้อมูล" ห้ามแต่ง

| ห้าม | เอาแบบนี้ |
|---|---|
| "แน่นอนครับ! ผมยินดีช่วยเหลือ..." | "ใช้ตัวนี้:" |
| "อาจจะเป็นไปได้ว่ามีความเป็นไปได้..." | "ค่าไม่ตรง. เพราะ X." |
| "หวังว่าจะเป็นประโยชน์นะครับ" | (ไม่พิมพ์อะไร) |

### ข้อยกเว้น — ห้ามคาเวแมน ต้องเต็มรูป 100%
1. โค้ดทุกภาษา (Go, Dart, SQL)
2. สูตรและตัวเลข
3. ชื่อตาราง/คอลัมน์/ฟังก์ชัน
4. ข้อความที่จะใส่เล่มปริญญานิพนธ์ (บทที่ 1-4)
5. คอมเมนต์ในโค้ดตามสเปกข้อ 8

> คาเวแมนใช้กับ "การคุย" ไม่ใช้กับ "ของที่ส่งมอบ"

### คำสั่งสลับโหมด
`//normal mode` ปิด · `//caveman` เปิด · `//verbose` ละเอียดครั้งเดียว

---

## 2. พื้นที่ทำงาน (Workspace)

### [1] BACKEND
```
PS C:\xampp\htdocs\food_and_fit_api>
```
- ภาษา **Go** · DB **MariaDB/MySQL ผ่าน XAMPP** · DB name `food_and_fit_db`
- API: REST / JSON
- คำสั่งบ่อย: `go run main.go` · `go build` · `go mod tidy`

**ร่องรอยที่พบใน dump (สันนิษฐาน — ให้ยืนยันก่อนใช้):**
- ใช้ **GORM** (พบตาราง `audit_logs`, `revoked_tokens` เป็น `datetime(3)` + `bigint unsigned` ตามสไตล์ GORM auto-migrate)
- ใช้ **JWT + denylist** (`revoked_tokens.jti`)
- ใช้ **bcrypt** (hash ขึ้นต้น `$2a$10$`)
- มี **audit log** ระดับ action/ip

### [2] FRONTEND
```
PS C:\myFutter68\myapp>
```
- **Flutter / Dart** (iOS + Android)
- คำสั่งบ่อย: `flutter run` · `flutter pub get` · `flutter clean` · `flutter build apk`
- ไฟล์ Datadic ฝั่งแอป: `lib\core\constants\Datadic.dart` — **ต้องเนื้อหาเหมือนฝั่ง backend เสมอ**

### ยังต้องเติมเอง (Claude ห้ามเดา — ถ้าจำเป็นให้ถาม)
- Go version: `______` · Flutter/Dart SDK: `______`
- Web framework Go (gin / fiber / echo / net-http): `______`
- ORM (GORM? database/sql?): `______`
- Package Flutter (http/dio, provider/riverpod/bloc, fl_chart/syncfusion): `______`
- Base URL ของ API: `______`

---

## 3. โครงสร้างฐานข้อมูลจริง (`food_and_fit_db`)

Engine **InnoDB** · Charset **utf8mb4** (collation ปนกัน 2 แบบ — ดูข้อ 4)

### 3.1 ตารางธุรกิจ 17 ตาราง

| ตาราง | PK | ชนิด PK | ข้อมูล seed |
|---|---|---|---|
| `system_data` | sys_id | int | 1 แอดมิน |
| `member_profile` | mb_id | int | 10 คน (demo) |
| `member_body_stats` | mbs_id | int | 20 |
| `member_bmr_history` | mbh_id | int | 20 |
| `muscle_group` | mug_id | **int unsigned** | 9 |
| `weight_exercises` | wet_id | **int unsigned** | ~49 |
| `exercise_muscle_details` | emd_id | **int unsigned** | ~88 |
| `cardio_category` | cdc_id | **int unsigned** | 7 |
| `cardio` | cdo_id | **int unsigned** | 11 |
| `nutrition_category` | nttc_id | int | 7 |
| `nutrition` | ntt_id | int | ~154 |
| `workout_plan_template` | wpt_id | **int unsigned** | 5 |
| `plan_template_detail` | ptd_id | **int unsigned** | ~218 |
| `workout_schedules` | wsch_id | **int unsigned** | 20 |
| `daily_nutrition` | dntt_id | int | 80 |
| `weight_training_result` | wtrs_id | **int unsigned** | 60 |
| `cardio_result` | cdors_id | **int unsigned** | 7 |

### 3.2 ตารางภายใน backend (ไม่อยู่ใน ER)
`audit_logs` (id bigint unsigned, actor_type, actor_id, action, detail, ip_address, created_at)
`revoked_tokens` (id bigint unsigned, jti, expires_at, created_at)

### 3.3 ตารางที่ถูกลบแล้ว — ห้ามอ้างถึงอีก
- `member_notifications` → ใช้ local notification บนเครื่องแทน
- `daily_water_intake`

### 3.4 กติกา FK ที่ใช้จริง (ต้องรู้ตอนเขียน DELETE)

| ลบอะไร | เกิดอะไร |
|---|---|
| ลบ `member_profile` | CASCADE ลบ body_stats, bmr_history, daily_nutrition, wtrs, cdors, wsch ทั้งหมด |
| ลบ `nutrition` | `daily_nutrition.ntt_id` → SET NULL (ประวัติการกินยังอยู่) |
| ลบ `weight_exercises` | `wtrs.wet_id`, `ptd.wet_id` → SET NULL / **`wsch.wet_id` → CASCADE** |
| ลบ `cardio` | `cdors.cdo_id` → SET NULL |
| ลบ `workout_plan_template` | `wsch.wpt_id` → SET NULL / `ptd` → CASCADE |
| ลบ `workout_schedules` | `wtrs.wsch_id` → SET NULL |
| ลบ `muscle_group` | `wet.mug_id` → SET NULL / `emd` → CASCADE |
| ลบ `member_body_stats` | `mbh.mbs_id` → SET NULL |

**`mb_status`:** เหลือค่าเดียว `1=Active` — เดิมมี `2=Deleted` + `mb_deleted_at` สำหรับฟีเจอร์
"ลบบัญชี" แบบ Grace Period 30 วัน แต่ไม่เคยมี endpoint ไหน trigger จริง (ไม่มีทั้งฝั่งมือถือและ
admin web) ตัดออกทั้งระบบแล้ว 2026-08-29 (ดูหัวข้อ 4 D8) — `mb_deleted_at` ถูก DROP ออกจากตารางแล้ว

### 3.5 กติกาแปลงชนิดข้อมูลฝั่ง Go
- คอลัมน์ `int unsigned` → Go ใช้ `uint` / `uint32` **ห้ามใช้ `int`** (จะพังตอน bind)
- คอลัมน์ที่ nullable และมีความหมาย (`wsch_id`, `wpt_id`, `ntt_id`, `mbs_id`)
  → ใช้ `*T` หรือ `sql.NullXxx` **ห้าม default 0** เพราะ 0 กับ NULL ความหมายต่างกัน
- `DECIMAL` ทางการเงิน/พลังงาน → รับเป็น `float64` แล้วปัดตอนแสดงผลเท่านั้น ห้ามปัดตอนเก็บ

---

## 4. ⚠️ ความไม่ตรงกัน เอกสาร vs DB จริง (Discrepancy Log)

**Claude ต้องยึด DB จริงตอนเขียนโค้ด และยึดเอกสารตอนเขียนเล่ม — แต่ต้องเตือนทุกครั้งที่แตะจุดเหล่านี้**

### D1 — `mbs_activity_level` ปัดเศษทำค่าเพี้ยน 🟢 แก้แล้ว (ยืนยัน 2026-08-20)
- เดิม schema `DECIMAL(3,2)` เก็บได้แค่ 2 ตำแหน่ง ปัด 1.375/1.725 เพี้ยนเป็น 1.38/1.73
- **ของจริงตอนนี้:** คอลัมน์เป็น `DECIMAL(4,3)` แล้ว เก็บ 1.375/1.725 เต็มค่าตรงกับที่ใช้คำนวณ `mbh_tdee` (เช็คแล้วใน dump ล่าสุด: mb_id=2 `mbs_activity_level=1.375`, mb_id=11 มี `1.900` ก็เก็บเต็ม)
- ไม่มีจุดไหนต้อง map ค่าปัดกลับอีกต่อไป — ใช้ค่าที่เก็บได้ตรง ๆ

### D2 — `wsch_date` เป็น `longtext` ไม่ใช่ `DATE` 🟢 แก้แล้ว (2026-08-16)
- บทที่ 4 ตาราง 4.14 + Datadic ระบุ `DATE`
- ~~DB จริง: `wsch_date longtext DEFAULT NULL`~~ → รัน `migrations/2026081603_wsch_date_to_date.sql` แล้ว คอลัมน์เป็น `DATE` จริงแล้ว (141 แถวเดิมแปลงครบ ไม่มี NULL เพิ่ม) backup ไว้ที่ `migrations/backups/backup_wsch_date_20260816.sql`
- โค้ด Go: `models.WorkoutSchedule.WschDate` ยังเป็น Go type `string` (ไม่ได้เปลี่ยนเป็น `time.Time`) แต่เพิ่ม gorm tag `type:date` แล้ว — เลือกแบบนี้เพราะทุกจุดในโค้ด format เป็น `"2006-01-02"` string อยู่แล้ว (ตามแบบ `WtrsDate`/`CdorsDate` ในไฟล์เดียวกัน) ลด blast radius ไม่ต้องรื้อโค้ดที่ใช้ค่านี้ทั้งระบบ
- **ยังต้องอัปเดตบทที่ 4 ตาราง 4.14 ให้ตรง (ยังไม่ทำ — เป็นงานเอกสาร แยกจากตรงนี้)**

### D3 — แผนส่วนตัวไม่ได้ใช้ `wpt_id = NULL` 🟡 สถาปัตยกรรมเปลี่ยนแล้ว (ยึดของจริง)
- Datadic ระบุ: แผนส่วนตัว → `wpt_id = NULL` บน `workout_schedules` (ไม่มีตารางแยก)
- **ของจริงตอนนี้ (ตั้งแต่ 2026-08-16, migration `2026081602_member_workout_plans.sql`):**
  แผนส่วนตัวมีตารางของตัวเอง `member_workout_plans` (`mwp_id`, `mb_id`, `mwp_name`, `mwp_days_per_week`)
  — `workout_schedules` มีคอลัมน์ `mwp_id` (FK → `member_workout_plans`, ON DELETE CASCADE) แยกจาก `wpt_id`
  (FK → `workout_plan_template`, ON DELETE SET NULL) **มีค่าได้แค่ 1 ใน 2 คอลัมน์ต่อแถวเสมอ** ไม่ใช่ "ทั้งคู่เป็น NULL"
- แผนที่ "ใช้งานอยู่" (active) เก็บที่ `member_profile.mb_active_wpt_id` / `mb_active_mwp_id` (mutually exclusive) ไม่ได้เดาจากแถวล่าสุดใน `workout_schedules`
- แถวเก่า `workout_plan_template` id=**10** (`wpt_difficulty=0`, ชื่อ "แผนส่วนตัวของฉัน") — 🟢 **ยืนยันแล้วว่าถูกลบออกจาก DB จริงแล้ว** (เช็ค `migrations/food_and_fit_db.sql` dump 2026-08-20: เหลือแค่ `wpt_id` 1-4, `AUTO_INCREMENT=12` แสดงช่องว่างจากการลบ id 5-11) ไม่ค้างอีกต่อไป
- **ต้องอัปเดต:** Datadic + บทที่ 4 (ER, ตาราง 4.12-4.14) ให้ตรงกับสถาปัตยกรรมนี้ — งานเอกสารยังไม่ได้ทำ
- 🔴 **จุดใหม่ที่ยังไม่แก้:** ไม่มี `CHECK` constraint ระดับ DB บังคับว่า `wpt_id`/`mwp_id` ต้องมีค่าแค่ 1 ใน 2 คอลัมน์ — พึ่ง logic ฝั่ง Go เท่านั้น (ข้อมูลจริง ณ 2026-08-20 ยังไม่มีแถวละเมิด แต่เสี่ยงถ้า handler จุดไหนพลาด)

### D4 — `wpt_difficulty = 0` ไม่มีในเอกสาร 🟢 เลิกใช้แล้ว + แถว dead data ถูกลบแล้ว
- เอกสารนิยามแค่ 1=เริ่มต้น, 2=กลาง, 3=สูง
- เดิม DB มีค่า 0 อยู่ที่แถว `wpt_id=10` (เคยใช้เป็นเครื่องหมายแผนส่วนตัวก่อนมี `member_workout_plans`) — **แถวนี้ถูกลบออกจาก DB แล้ว** (ยืนยัน 2026-08-20)
- **ตั้งแต่มี `member_workout_plans` แล้ว โค้ดปัจจุบันไม่ได้สร้าง/พึ่งพา `wpt_difficulty=0` อีกต่อไป** — `GetWorkoutPlans`/`GetWorkoutTemplates`/`ResetWorkoutPlan` ที่เคยกรอง `wpt_difficulty > 0` ตอนนี้เป็นแค่ safety filter เฉยๆ ไม่มี dead data ให้กรองแล้ว
- ไม่ต้องเพิ่มนิยาม 0 ในเอกสาร

### D5 — คำอธิบาย `mbs_activity_level` ผิด 🟡
- Datadic เขียน "ความถี่การออกกำลังกายต่อสัปดาห์"
- ความจริงเก็บ **Activity Factor** (ตัวคูณ TDEE) ไม่ใช่ความถี่
- ต้องแก้คำอธิบายใน Datadic + บทที่ 4

### D6 — collation ปนกัน 🟢 เล็กน้อย
- `utf8mb4_unicode_ci` (ส่วนใหญ่) vs `utf8mb4_general_ci` (`cardio_result`, `weight_training_result`, `workout_schedules`, `audit_logs`, `revoked_tokens`)
- เสี่ยง error `Illegal mix of collations` ตอน JOIN ด้วยคอลัมน์ข้อความ
- ปัจจุบัน JOIN ผ่าน ID ตัวเลข → ยังไม่พัง แต่ควรทำให้ตรงกัน

### D7 — `nutrition_category` id กระโดด 🟢
- มี 1-6 แล้วข้ามไป 9 ('น้ำ') — 7, 8 หายไป (ลบแล้ว)
- ห้าม hardcode ว่าประเภทอาหารมี 1-7 ให้ query จริงเสมอ

### D8 — `mb_status=2`/`mb_deleted_at` (ฟีเจอร์ลบบัญชี Grace Period) 🟢 ตัดออกแล้ว (2026-08-29)
- เดิม schema มี `mb_status` (1=Active, 2=Deleted) + `mb_deleted_at` รองรับฟีเจอร์ "ลบบัญชี"
  แบบ grace period 30 วัน (auto-restore ตอน login, cron hard-delete หลังพ้นกำหนด)
- ตรวจสอบแล้วว่าไม่เคยมี endpoint ไหน set `mb_status = 2` จริง — ไม่มีปุ่มลบบัญชีทั้งฝั่งมือถือ
  และ admin web มีแต่โครง backend เขียนรอไว้เฉยๆ
- **ของจริงตอนนี้:** ตัดออกทั้งระบบแล้ว — ลบ `helpers/grace_period.go`, cron ใน `main.go`,
  logic ใน `auth_controller.go` (Register/Login), `MbStatusDeleted` const + `MbDeletedAt` field
  ใน `models/member.go`, และ **DROP COLUMN `mb_deleted_at`** ออกจาก `member_profile` จริง
  (backup ไว้ที่ `migrations/backups/backup_member_profile_before_drop_mb_deleted_at_20260829.sql`)
- `mb_status` ยังอยู่ เหลือค่าเดียว `1=Active`

**กติกา:** ถ้า Claude เขียนโค้ด/เอกสารแตะจุด D1-D8 → ต้องเตือนก่อนเสมอ 1 บรรทัด

---

## 5. สูตรคำนวณ — ห้ามแก้เด็ดขาด

| ชื่อ | สูตร |
|---|---|
| BMI | น้ำหนัก(kg) ÷ ส่วนสูง(m)² |
| BMR ชาย | (10 × น้ำหนัก) + (6.25 × ส่วนสูง cm) − (5 × อายุ) + 5 |
| BMR หญิง | (10 × น้ำหนัก) + (6.25 × ส่วนสูง cm) − (5 × อายุ) − 161 |
| TDEE | BMR × Activity Factor |
| Target — ลดน้ำหนัก | TDEE − (TDEE × 20%) **และต้องไม่ต่ำกว่า BMR** (ต่ำกว่า → เท่ากับ BMR) |
| Target — เพิ่มน้ำหนัก/กล้ามเนื้อ | TDEE + (TDEE × 15%) |
| Target — รักษาน้ำหนัก | TDEE |
| Macronutrients | โปรตีน 4 · คาร์บ 4 · ไขมัน 9 kcal/g |
| Exercise Burn (METs) — เวทเทรนนิ่ง | **(METs − 1)** × น้ำหนัก(kg) × เวลา(ชม.) — เวลา = ทั้งเซสชัน (รวมพัก) หารเฉลี่ยเท่ากันทุกเซ็ต (เปลี่ยน 2026-08-22 ดูรายละเอียดท้ายตาราง) |
| Exercise Burn (METs) — คาร์ดิโอ | **(METs − 1)** × น้ำหนัก(kg) × เวลา(ชม.) — clamp ไม่ให้ติดลบถ้า METs ≤ 1 (เปลี่ยน 2026-08-22 หลักการเดียวกับเวทเทรนนิ่ง ดูรายละเอียดท้ายตาราง) |
| Training Volume | น้ำหนักที่ยก × Reps × Sets |
| Estimated 1RM | น้ำหนักที่ยก × (1 + Reps ÷ 30) — คำนวณแสดงผล **ไม่บันทึก DB** |
| Energy In | Σ(Food Calories) + Σ(Drink Calories) |
| Baseline Expenditure | BMR × 1.2 |
| Total Daily Energy Output | Baseline Expenditure + Σ(Exercise Burn) |
| Energy Balance | Energy In − Total Daily Energy Output |
| สถานะเทียบเป้า | ±10% → Over / On / Under Target |

**Activity Factor:** 1.2 (นั่งโต๊ะ) · 1.375 (เบา) · 1.55 (ปานกลาง) · 1.725 (หนัก) · 1.9 (หนักมาก) — ระวัง D1

**BMI (เอเชีย-แปซิฟิก):** <18.5 ผอมเกินไป · 18.5–22.9 สมส่วน · 23.0–24.9 น้ำหนักเกิน · ≥25.0 โรคอ้วน

**METs เวทเทรนนิ่งจาก `wtrs_intensity_level`:** 1=เบา (3.5) · 2=กลาง (5.0) · 3=หนัก (6.0)
อ้างอิง 2011 Compendium of Physical Activities (Ainsworth et al., 2554) รหัสกิจกรรม 02054 / 02052 / 02050 ตามลำดับ — ยืนยันซ้ำแล้วว่าตรงกับ **2024 Adult Compendium** ฉบับล่าสุดทุกค่า (2026-08-22) ค่า METs ไม่เปลี่ยน
ยืนยันแล้วว่าตรงกับบทที่ 2 หัวข้อ 2.1.4.12 (ค่าเบา/หนักถูกระบุไว้อยู่แล้ว แต่ยังไม่มีค่ากลาง 5.0 — ต้องเพิ่มในเล่ม)

**🔴 แก้สูตร (2026-08-22) — `wtrs_calories` เก็บเป็น NET ไม่ใช่ gross อีกต่อไป:**
- **ปัญหาเดิม:** `analytics_controller.go` เอา `SUM(wtrs_calories)` บวกตรงเข้า Total Daily Energy Output ที่มี Baseline (BMR×1.2) รวมอยู่แล้ว → นับพลังงานพื้นฐานซ้ำสองรอบ + ฐานเวลาเดิม (เฉพาะช่วงออกแรงต่อเซต) ไม่ตรงนิยาม METs ซึ่งเป็นค่าเฉลี่ยทั้งเซสชันรวมพัก
- **สูตรใหม่:** `wtrs_calories = (METs − 1) × น้ำหนัก(kg) × เวลา(ชม.)` — เวลาส่งมาจาก frontend เป็นเวลาเซสชันทั้งหมด (รวมพัก) หารเฉลี่ยเท่ากันทุกเซ็ต ไม่ใช่รายเซ็ตจริงอีกต่อไป (ดู `SaveWorkoutResult` ใน `workout_controller.go`)
- **gross ย้อนกลับได้เสมอ:** `gross = net × METs / (METs − 1)` ใช้ METs จาก `wtrs_intensity_level` ในแถวเดียวกัน — ไม่มีข้อมูลสูญหาย
- **ข้อมูลเก่าก่อน 2026-08-22:** คำนวณด้วยสูตร gross แบบเดิม (ฐานเวลารายเซ็ต) เทียบย้อนหลังตรงๆ ไม่ได้
- **คาร์ดิโอ — แก้พร้อมกัน (2026-08-22):** นิยาม 1 MET ไม่ได้ขึ้นกับชนิดกิจกรรม นับซ้ำ Baseline เหมือนกันทุกประการทั้งคาร์ดิโอและเวท (`exerciseBurn := cardioOut.Total + weightOut.Total` โดน SUM เข้า TDEO ทั้งคู่) — หักแค่ฝั่งเวทจะกลายเป็นบวก net+gross ปนกัน อธิบายไม่ได้ว่าผลรวมคืออะไร สูตรใหม่ `cdors_calories = (METs − 1) × น้ำหนัก × เวลา` + clamp ไม่ให้ติดลบ — implement แล้วที่ `SaveWorkoutResult` (คาร์ดิโอ)
- **⚠️ ค้าง — backfill ข้อมูลเก่า:** 501 แถว `weight_training_result` + 18 แถว `cardio_result` (ข้าม mb_id จริงหลายคน ไม่ใช่แค่ทดสอบ) ก่อน 2026-08-22 ยังเป็น gross — ยังไม่ตัดสินใจ backfill หรือปล่อยไว้พร้อมหมายเหตุ ต้อง backup ก่อนถ้าจะรัน UPDATE จริง
- **⚠️ ค้าง — เอกสารเล่ม:** บทที่ 2 หัวข้อ 2.1.4.10/2.1.4.12 + ไฟล์สูตร/สมการฯ 3.3 ยังไม่ sync — ไม่ทราบพาธไฟล์

> เห็นโค้ดใช้ตัวเลขไม่ตรงตารางนี้ → **แจ้งทันที** ว่าไม่ตรงบทที่ 2

---

## 6. กติกาการเขียนโค้ด

### ทั่วไป
- ห้ามแก้ logic เดิมถ้าไม่ได้สั่ง — แก้เฉพาะจุดที่ขอ
- ต้องแก้จุดอื่น → บอกก่อน อย่าแก้เงียบ
- ไฟล์ยาว → แสดง **เฉพาะส่วนที่แก้** + ชื่อฟังก์ชัน/เลขบรรทัด (ยกเว้นสั่ง `//full`)
- ห้ามเพิ่ม package ใหม่โดยไม่บอก — ถ้าต้อง ให้บอกชื่อ + คำสั่งติดตั้ง
- ค่าคงที่ในสูตร → ทำเป็น constant ห้ามฝัง magic number กระจาย

### Go (Backend)
- ชื่อ handler: `GetXxx` / `CreateXxx` / `UpdateXxx` / `DeleteXxx`
- handle error ทุกจุด ห้าม `_ = err`
- Query ใช้ parameter binding เสมอ ห้ามต่อ string ดิบ
- ชนิดข้อมูลตามข้อ 3.5 (unsigned / nullable)
- Response JSON รูปแบบเดียวกันทั้งระบบ:
  ```json
  { "success": true, "message": "", "data": {} }
  ```
- ทุก action ที่แก้ข้อมูลสำคัญ → เขียน `audit_logs` ด้วย
- Logout / เปลี่ยนรหัสผ่าน → ใส่ `jti` ลง `revoked_tokens`

### Dart / Flutter
- แยก UI / logic / service
- เรียก API ผ่าน service class ห้ามเรียกใน widget ตรง ๆ
- ทุกหน้าที่โหลดข้อมูล ต้องมี 3 สถานะ: loading / error / empty
- แสดงผล: แคลอรี่ 0 ตำแหน่ง · น้ำหนัก/ระยะทาง 1-2 ตำแหน่ง · BMI 2 ตำแหน่ง
- แก้ `Datadic.dart` ฝั่งแอปเมื่อไหร่ → ต้องแก้ `Datadic_updated.dart` ฝั่ง backend ให้ตรงกันทันที

### SQL
- keyword ตัวใหญ่ · ระบุชื่อคอลัมน์เสมอ ห้าม `SELECT *`
- ALTER/DROP → **เตือนให้ backup ก่อนเสมอ** และให้คำสั่ง rollback ควบคู่

---

## 7. เมื่อช่วยเขียน/แก้เอกสาร (บทที่ 1-4)

- ภาษาราชการ/วิชาการ ไม่ใช้คาเวแมน
- คำศัพท์ตรงกันทุกบท (BMR, TDEE, Energy Balance, สมดุลพลังงาน)
- ปี พ.ศ. ในการอ้างอิงใช้รูปแบบเดิมของเล่ม (เช่น Ainsworth et al., 2554)
- ตัวเลข/สูตรต้องตรงข้อ 5 และตรงโค้ดจริง
- **ห้ามแต่งผลการทดสอบ/ผลประเมินความพึงพอใจ** — ไม่มีข้อมูลให้บอกว่าไม่มี
- อ้างรูปใช้เลขเดิม (เช่น รูปที่ 4.33 หน้าจอรายงานทั่วไป)
- แก้เอกสารเรื่องโครงสร้างตาราง → ต้องเช็ค D1-D7 ก่อนว่ากำลังเขียนตามของเก่าหรือของจริง

---

## 8. ระบบ Tag คอมเมนต์ในโค้ด (ใช้ตอนสอบ)

### หัวไฟล์หน้าจอ
```dart
// ══════════════════════════════════════════════
// [PAGE] <PAGE_TAG> : <ชื่อหน้าภาษาไทยสั้นๆ>
// [PAGE_PURPOSE] <หน้านี้ทำอะไร>
// [PAGE_ROUTE] <route/ไฟล์>
// [USES_FEATURES] <FEATURE_TAG คั่นด้วย ,>
// ══════════════════════════════════════════════
```

### หัวฟังก์ชัน
```dart
// --------------------------------------------
// [FEATURE] <FEATURE_TAG>
// [FUNCTION] <ชื่อฟังก์ชัน>
// [DESCRIPTION] <ทำอะไร ภาษาไทย>
// [INPUT] <พารามิเตอร์ + หน่วย>
// [OUTPUT] <ค่าที่คืน/widget>
// [TABLES] <ตาราง DB ที่แตะ ถ้ามี>
// [FORMULA] <สูตร เฉพาะจุดที่คำนวณจริง — ห้ามแต่ง>
// [RELATED] <FEATURE_TAG อื่น>
// --------------------------------------------
```

### FEATURE_TAG มาตรฐาน (ห้ามตั้งใหม่)
`AUTH` · `PROFILE` · `BMR_TDEE` · `WORKOUT_PLAN` · `FOOD_LOG` · `WEIGHT_TRAINING` · `CARDIO` · `ENERGY_BALANCE` · `REPORT` · `COMMON_UI`

ใช้ tag ชุดเดียวกันทั้งฝั่ง Go และ Dart เพื่อค้นข้ามฝั่งได้

### ค้นหา
```
VS Code : Ctrl+Shift+F  →  [FEATURE] BMR_TDEE
Terminal: grep -rn "\[FEATURE\] CARDIO" lib/
Backend : findstr /s /n "[FEATURE] CARDIO" *.go
```

---

## 9. คำสั่งลัด

| คำสั่ง | ผล |
|---|---|
| `//1` `//be` | สลับเป็น BACKEND |
| `//2` `//fe` | สลับเป็น FRONTEND |
| `//doc` | โหมดเขียนเอกสารวิชาการ (ปิดคาเวแมนอัตโนมัติ) |
| `//full` | แสดงโค้ดทั้งไฟล์ ไม่ตัด |
| `//tag <ไฟล์>` | เติมคอมเมนต์ tag ตามข้อ 8 + ตารางสรุปท้ายไฟล์ |
| `//sql` | ตอบเป็น SQL อย่างเดียว |
| `//check` | ตรวจโค้ด/เอกสารที่ให้มา เทียบสูตรข้อ 5 + Datadic + D1-D7 |
| `//diff` | ตรวจว่า Datadic 2 ฝั่ง (backend/Flutter) ยังตรงกันไหม |
| `//why` | อธิบายเหตุผลเบื้องหลังคำตอบล่าสุด |
| `//normal mode` | ปิดคาเวแมน |

---

## 10. เช็กลิสต์ก่อนส่งคำตอบ

- [ ] ประกาศ workspace แล้ว?
- [ ] ชื่อตาราง/คอลัมน์ตรง DB จริง?
- [ ] ชนิดข้อมูล unsigned / nullable ถูก?
- [ ] สูตร/ตัวเลขตรงข้อ 5?
- [ ] แตะจุด D1-D7 แล้วเตือนหรือยัง?
- [ ] query สมาชิกกรอง `mb_status = 1` แล้ว?
- [ ] ไม่ได้แก้ logic ที่ไม่ได้สั่ง?
- [ ] ไม่มีข้อมูล ได้บอกว่าไม่มี แทนที่จะเดา?
- [ ] คาเวแมนไม่ลามไปโค้ด/สูตร/เอกสาร?

---

## 11. ห้ามทำเด็ดขาด

1. ห้ามแต่งชื่อคอลัมน์/ตารางที่ไม่มีใน Datadic + dump
2. ห้ามอ้างตารางที่ลบแล้ว (`member_notifications`, `daily_water_intake`)
3. ห้ามเปลี่ยนตัวเลขในสูตร (20%, 15%, 1.2, 30, 4/4/9)
4. ห้ามเปลี่ยนค่า MET เวทเทรนนิ่ง (3.5/5.0/6.0 ตามข้อ 5) โดยไม่มีอ้างอิง Compendium รองรับ
5. ห้ามแต่งผลการทดสอบ/ค่าสถิติ/ผลประเมินในบทที่ 4
6. ห้ามแต่งงานวิจัยอ้างอิงหรือปี พ.ศ.
7. ห้ามลบคอมเมนต์เดิมในโค้ด
8. ห้ามเปลี่ยน tech stack (Flutter/Dart, Go, MySQL) โดยไม่ได้สั่ง
9. ห้ามให้คำสั่ง ALTER/DROP โดยไม่เตือน backup
10. ห้ามตอบยาวเวิ่นเว้อในโหมดคาเวแมน