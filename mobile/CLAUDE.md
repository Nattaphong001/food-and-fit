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

### 3.1 ตารางธุรกิจ 18 ตาราง

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
| `member_workout_plans` (ใหม่ 2026-08-16) | mwp_id | **int unsigned** | — |
| `plan_template_detail` | ptd_id | **int unsigned** | ~218 |
| `workout_schedules` | wsch_id | **int unsigned** | 20 |
| `daily_nutrition` | dntt_id | int | 80 |
| `weight_training_result` | wtrs_id | **int unsigned** | 60 |
| `cardio_result` | cdors_id | **int unsigned** | 7 |

> `member_workout_plans` มาจาก migration `2026081602_member_workout_plans.sql` — ดู D3 ข้อ 4

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

**Soft delete สมาชิก:** `mb_status` (1=Active, 2=Deleted) + `mb_deleted_at` → Grace Period 30 วัน
→ ทุก query ที่ดึงข้อมูลสมาชิก **ต้องกรอง `mb_status = 1` เสมอ** เว้นแต่เป็น job ล้างข้อมูล

### 3.5 กติกาแปลงชนิดข้อมูลฝั่ง Go
- คอลัมน์ `int unsigned` → Go ใช้ `uint` / `uint32` **ห้ามใช้ `int`** (จะพังตอน bind)
- คอลัมน์ที่ nullable และมีความหมาย (`wsch_id`, `wpt_id`, `ntt_id`, `mbs_id`, `mb_deleted_at`)
  → ใช้ `*T` หรือ `sql.NullXxx` **ห้าม default 0** เพราะ 0 กับ NULL ความหมายต่างกัน
- `DECIMAL` ทางการเงิน/พลังงาน → รับเป็น `float64` แล้วปัดตอนแสดงผลเท่านั้น ห้ามปัดตอนเก็บ

---

## 4. ⚠️ ความไม่ตรงกัน เอกสาร vs DB จริง (Discrepancy Log)

**Claude ต้องยึด DB จริงตอนเขียนโค้ด และยึดเอกสารตอนเขียนเล่ม — แต่ต้องเตือนทุกครั้งที่แตะจุดเหล่านี้**

### D1 — `mbs_activity_level` ปัดเศษทำค่าเพี้ยน 🟢 แก้แล้ว (ยืนยัน 2026-08-20)
- เดิม schema `DECIMAL(3,2)` เก็บได้แค่ 2 ตำแหน่ง ปัด 1.375/1.725 เพี้ยนเป็น 1.38/1.73
- **ของจริงตอนนี้:** คอลัมน์เป็น `DECIMAL(4,3)` แล้ว เก็บ 1.375/1.725 เต็มค่าตรงกับที่ใช้คำนวณ `mbh_tdee` จริง (เช็คแล้วใน dump ล่าสุด: mb_id=2 `mbs_activity_level=1.375`, mb_id=11 มี `1.900` ก็เก็บเต็ม)
- ไม่มีจุดไหนต้อง map ค่าปัดกลับอีกต่อไป — ใช้ค่าที่เก็บได้ตรง ๆ
- sync จาก `food_and_fit_api\CLAUDE.md` (backend) ให้ตรงกัน — ไฟล์นี้เพิ่งอัปเดตตาม (2026-08-20)

### D9 — Activity Factor validation ฝั่ง backend หลวมกว่าฝั่ง frontend 🟡 พบใหม่ (audit 2026-08-20)
- `helpers/validation.go` (`ValidateActivityLevel`) เช็คแค่ช่วง `1.2 ≤ level ≤ 1.9` ไม่ได้บังคับว่าต้องเป็น 1 ใน 5 ค่ามาตรฐาน (1.2/1.375/1.55/1.725/1.9)
- `lib/core/utils/health_calculations.dart` (`_snapActivityFactor`) ฝั่ง frontend กลับ snap ค่าเข้าหา 1 ใน 5 ค่านั้นเสมอก่อนคูณ TDEE (fallback path เท่านั้น เวลา API ไม่ส่ง tdee มา)
- ถ้ามีช่องทางส่งค่ากลางๆ เช่น `1.6` เข้า backend ได้ (ปัจจุบัน UI บังคับผ่าน dropdown 5 ตัวเลือกเท่านั้น ยังไม่เกิดจริง) → backend คำนวณ TDEE ด้วย 1.6 แต่ frontend fallback จะ snap เป็น 1.55 แทน ไม่ตรงกัน
- ทางแก้ที่ต้องเลือก (ให้ผู้ใช้ตัดสินใจ ห้าม Claude เลือกเอง): (1) เข้มงวด backend ให้รับเฉพาะ 5 ค่ามาตรฐาน หรือ (2) เอา snap logic ออกจาก frontend แล้วรับค่าจริงตรงๆ

### D2 — ✅ RESOLVED (2026-08-16) — `wsch_date` เดิมเป็น `longtext` ไม่ใช่ `DATE`
- บทที่ 4 ตาราง 4.14 + Datadic ระบุ `DATE` มาตลอด — DB จริงเคยเป็น `longtext DEFAULT NULL` (ร่องรอย GORM auto-migrate จาก `string`)
- ยืนยันด้วย `DESCRIBE workout_schedules` จริงเมื่อ 2026-08-16: คอลัมน์เป็น **`date`** แล้ว ตรงกับ Datadic/struct Go (`gorm:"type:date"`) — แก้เรียบร้อย ไม่ต้องเตือนซ้ำอีก
- หมายเหตุ (คนละเรื่องกัน อย่าสับสน): ความหมายของ `wsch_date` "คือวันอะไร" เพิ่งแก้คำอธิบายใน Datadic เมื่อ 2026-08-16 เช่นกัน — เป็นแค่ **วันที่สร้างรายการ (metadata)** ไม่ใช่วันฝึกจริง (วันฝึกจริงมาจาก `wsch_day_number`) โค้ด `CreateWorkoutSchedule` ยิง `time.Now()` เข้าคอลัมน์นี้เสมอไม่ว่าท่านั้นจะฝึกวันไหน

### D3 — สถาปัตยกรรม "แผนส่วนตัว" เปลี่ยนทั้งหมด (2026-08-16) — เดิม `wpt_id = NULL`, ตอนนี้ตารางแยก + pointer
- **ของเดิม (ก่อน 2026-08-16, ปิดเคสแล้ว):** แผนส่วนตัวฝากไว้ใน `workout_schedules.wpt_id = NULL` เฉยๆ — รองรับได้แค่ 1 แผนส่วนตัวต่อสมาชิก ไม่มีชื่อเก็บแยก ไม่มีตัวชี้ว่า "แผนไหนกำลังใช้งานอยู่จริง" (ต้องเดาจากแถวล่าสุด ซึ่งพังเมื่อมีหลายแผนปนกัน)
- **ของจริงตอนนี้ (migration `2026081602_member_workout_plans.sql`):**
  1. ตารางใหม่ `member_workout_plans` (PK `mwp_id`) — 1 สมาชิกมีได้หลายแผนส่วนตัว ตั้งชื่อเองได้ (`mwp_name`)
  2. `workout_schedules` เพิ่มคอลัมน์ `mwp_id` (nullable, FK → `member_workout_plans`, ON DELETE CASCADE) คู่กับ `wpt_id` เดิม
     - แผนระบบ: `wpt_id = X, mwp_id = NULL`
     - แผนส่วนตัว: `wpt_id = NULL, mwp_id = Y`
     - มีค่าได้แค่ 1 ใน 2 ต่อแถวเสมอ
  3. `member_profile` เพิ่ม `mb_active_wpt_id` / `mb_active_mwp_id` (ทั้งคู่ nullable, มีค่าได้แค่ 1 ใน 2) — เป็นตัวชี้ "แผนที่ใช้งานอยู่จริง" แหล่งเดียวที่เชื่อถือได้ (`GetMemberActivePlan`) แทนการเดาจากแถวล่าสุด
- **ผลกระทบต่อโค้ด/เอกสาร:** เงื่อนไข "แผนระบบ" ยังคงเป็น `wpt_difficulty >= 1` เหมือนเดิม (ไม่เกี่ยวกับการเปลี่ยนนี้) — แต่การเช็คว่า user มีแผนส่วนตัวหรือแผนระบบต้อง query `member_profile.mb_active_wpt_id`/`mb_active_mwp_id` ไม่ใช่เดาจาก `workout_schedules` อีกต่อไป
- **Datadic:** อัปเดตแล้ว (ตาราง 4.2 เพิ่ม attribute 15-16, ตาราง 4.12b ใหม่, ตาราง 4.14 เพิ่ม `mwp_id`) — sync แล้วทั้ง backend/frontend
- **บทที่ 4 (เล่ม):** ยังไม่ได้แก้ — ต้องเพิ่มตาราง 4.12b และ attribute ใหม่ในตาราง 4.2 เมื่อจะเขียนส่วนนี้

### D4 — ⚠️ ยังไม่ได้ยืนยัน (MySQL server ปิดอยู่ตอนตรวจสอบ 2026-08-16) — `wpt_difficulty = 0` อาจไม่มีความหมายแล้ว
- เดิมมีแถว `workout_plan_template` id=10 ชื่อ "แผนส่วนตัวของฉัน" `wpt_difficulty = 0` ใช้เป็นทริคมาร์กแผนส่วนตัวสมัยที่ยังไม่มีตาราง `member_workout_plans`
- ตรวจโค้ดปัจจุบันแล้ว: ไม่มี endpoint ไหนสร้างแถว `wpt_difficulty = 0` อีกต่อไป (`CreatePersonalPlan` สร้างที่ `member_workout_plans` แทน) → ทริคนี้ไม่ได้ใช้ต่อในสถาปัตยกรรมใหม่
- **แต่ยังไม่ได้ `DESCRIBE`/`SELECT` ยืนยันว่าแถว id=10 เดิมยังอยู่ใน DB จริงหรือถูกลบไปแล้ว** — ห้ามเชื่อว่า resolved จนกว่าจะเช็ค DB ได้จริง (ครั้งหน้าที่ MySQL รันอยู่ ให้รัน `SELECT wpt_id, wpt_name, wpt_difficulty FROM workout_plan_template WHERE wpt_difficulty = 0;` ก่อน)
- ถ้ายังมีแถวนี้ค้างอยู่ → เป็น orphan data ไม่ใช่ design ที่ตั้งใจ ต้องตัดสินใจว่าจะลบทิ้งหรือปล่อยไว้

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

### D8 — `workout_schedules` หลายคอลัมน์เป็น `bigint(20)` ทั้งที่ Go struct/Datadic ระบุ `INT` 🟢 เล็กน้อย (พบ 2026-08-16)
- คอลัมน์ที่ไม่ตรง: `wsch_day_number`, `wsch_sets`, `wsch_rest_seconds`, `wsch_order`
- ยืนยันด้วย `DESCRIBE workout_schedules` จริงใน `food_and_fit_db` — ไม่ใช่แค่อนุมานจาก struct
- สาเหตุ: คอลัมน์พวกนี้สร้างไว้ตั้งแต่ก่อนมีคนใส่ `gorm:"type:int"` tag ทีหลัง GORM AutoMigrate ไม่แก้ type คอลัมน์ที่มีอยู่แล้ว (แก้แค่เพิ่มคอลัมน์ที่ขาด) type เดิมเลยค้างเป็น bigint
- ผลกระทบ: ไม่พังการทำงาน (แค่กิน storage เกินความจำเป็น) — Datadic/struct ยังคงเขียน `INT` ไว้ตามค่าที่ตั้งใจ ไม่ใช่ก๊อปบั๊กนี้เข้าไป
- ทางแก้ (ยังไม่ทำ รอสั่ง): `ALTER TABLE workout_schedules MODIFY wsch_day_number INT, MODIFY wsch_sets INT, MODIFY wsch_rest_seconds INT, MODIFY wsch_order INT;` — **ต้อง backup ก่อนเสมอ**

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
| Macro Split — ลดน้ำหนัก (target=1) | คาร์บ 35% · โปรตีน 40% · ไขมัน 25% |
| Macro Split — เพิ่มกล้ามเนื้อ (target=2) | คาร์บ 50% · โปรตีน 30% · ไขมัน 20% |
| Macro Split — รักษาน้ำหนัก (default) | คาร์บ 50% · โปรตีน 20% · ไขมัน 30% |
| Exercise Burn (METs) — เวทเทรนนิ่ง | **(METs − 1)** × น้ำหนัก(kg) × เวลา(ชม.) — เวลา = ทั้งเซสชัน (รวมพัก) หารเฉลี่ยเท่ากันทุกเซ็ต (เปลี่ยน 2026-08-22 ดูรายละเอียดท้ายตาราง) |
| Exercise Burn (METs) — คาร์ดิโอ | **(METs − 1)** × น้ำหนัก(kg) × เวลา(ชม.) — clamp ไม่ให้ติดลบถ้า METs ≤ 1 (เปลี่ยน 2026-08-22 หลักการเดียวกับเวทเทรนนิ่ง ดูรายละเอียดท้ายตาราง) |
| Training Volume | น้ำหนักที่ยก × Reps × Sets |
| Estimated 1RM | น้ำหนักที่ยก × (1 + Reps ÷ 30) — คำนวณแสดงผล **ไม่บันทึก DB** |
| Energy In | Σ(Food Calories) + Σ(Drink Calories) |
| Baseline Expenditure | BMR × 1.2 |
| Total Daily Energy Output | Baseline Expenditure + Σ(Exercise Burn) |
| Energy Balance | Energy In − Total Daily Energy Output |
| สถานะเทียบเป้า | ±10% → Over / On / Under Target |

**Activity Factor:** 1.2 (นั่งโต๊ะ) · 1.375 (เบา) · 1.55 (ปานกลาง) · 1.725 (หนัก) · 1.9 (หนักมาก) — D1 แก้แล้ว ระวัง D9 (validation ฝั่ง backend ไม่บังคับ 5 ค่านี้)

**BMI (เอเชีย-แปซิฟิก):** <18.5 ผอมเกินไป · 18.5–22.9 สมส่วน · 23.0–24.9 น้ำหนักเกิน · ≥25.0 โรคอ้วน — แสดงผล **2 ตำแหน่งทศนิยม** เสมอ (เกณฑ์แบ่งที่ 22.9/23.0 พอดี ปัดเหลือ 1 ตำแหน่งจะขัดกับ label ที่โชว์)

**อ้างอิงสัดส่วนมาโคร (บทที่ 2 หัวข้อ 2.1.4.8):**
- ลดน้ำหนัก 35:40:25 (C:P:F) — Jäger et al., 2560 (ISSN Position Stand)
- เพิ่มกล้ามเนื้อ 50:30:20 — Slater & Phillips, 2554
- รักษาน้ำหนัก 50:20:30 — IOM AMDR, 2548
- Implement เฉพาะฝั่ง frontend (`new_dashboard_view.dart`, `nutrition_view.dart`) — ตรงกับเอกสารเป๊ะ ยืนยันแล้ว 2026-08-20 ไม่ต้องหาอ้างอิงใหม่หรือแก้ตัวเลขอีก
- % ที่แสดงต้องถ่วงน้ำหนักด้วย kcal/g (4/4/9) เป็น **% ของพลังงานรวม** ไม่ใช่สัดส่วนกรัมดิบ (แก้บั๊กนี้แล้วที่ pill ใน `new_dashboard_view.dart` เมื่อ 2026-08-20)

**METs เวทเทรนนิ่งจาก `wtrs_intensity_level`:** 1=เบา (3.5) · 2=กลาง (5.0) · 3=หนัก (6.0)
→ อ้างอิง 2011 Compendium of Physical Activities (Ainsworth et al., 2554) รหัส 02054/02052/02050 — ยืนยันซ้ำแล้วว่าตรงกับ **2024 Adult Compendium** ฉบับล่าสุดทุกค่า (2026-08-22) ค่า METs ทั้ง 3 ระดับไม่เปลี่ยน — implement ที่ backend `workout_controller.go` (`SaveWorkoutResult`) — frontend ไม่มีตารางนี้ซ้ำ ใช้ `wtrs_calories` จาก API เสมอ ถูกต้องตาม single-source-of-truth

**🔴 แก้สูตร (2026-08-22) — `wtrs_calories` เก็บเป็น NET ไม่ใช่ gross อีกต่อไป:**
- **ปัญหาเดิม:** สูตร gross เดิม (`METs × น้ำหนัก × เวลา` ไม่หัก, ฐานเวลา = เฉพาะช่วงออกแรงต่อเซต) มี 2 จุดผิด — (1) `analytics_controller.go` เอา `SUM(wtrs_calories)` บวกตรงๆ เข้า Total Daily Energy Output ที่มี Baseline (BMR×1.2) รวมอยู่แล้ว → นับพลังงานพื้นฐานซ้ำสองรอบ (2) ฐานเวลาไม่ตรงนิยาม METs ซึ่งเป็นค่าเฉลี่ยทั้งเซสชันรวมพักตาม Compendium ไม่ใช่ขณะออกแรงล้วน
- **สูตรใหม่:** `wtrs_calories = (METs − 1) × น้ำหนัก(kg) × เวลา(ชม.)` — เวลา = `_globalSeconds` ทั้งเซสชัน (เดินต่อเนื่องรวมพัก ตั้งแต่เริ่มจนกดจบฝึก) หารเฉลี่ยเท่ากันทุกเซ็ตที่บันทึกจริง (reps>0) ไม่ได้อ้างว่ารู้พลังงานรายเซ็ตจริง — implement แล้วทั้ง `workout_controller.go` (`SaveWorkoutResult`) และ `weight_training_exercise_view.dart` (`_saveWorkoutToApi`)
- **gross ย้อนกลับได้เสมอ ไม่มีข้อมูลสูญหาย:** `gross = net × METs / (METs − 1)` โดยใช้ METs จาก `wtrs_intensity_level` ที่เก็บคู่กันในแถวเดียวกัน
- **ข้อมูลเก่าก่อน 2026-08-22:** คำนวณด้วยสูตร gross แบบเดิม (ฐานเวลารายเซ็ต) — เทียบย้อนหลังข้ามวันนี้ไม่ได้ตรงๆ ต้องรู้ว่าคำนวณคนละสูตร
- **คาร์ดิโอ (`cdors_calories`) — แก้พร้อมกัน (2026-08-22):** นิยาม 1 MET (=อัตราเผาผลาญขณะพักนิ่ง) ไม่ได้ขึ้นกับชนิดกิจกรรม การนับซ้ำกับ Baseline เกิดเหมือนกันทุกประการทั้งคาร์ดิโอและเวท (`exerciseBurn := cardioOut.Total + weightOut.Total` ทั้งคู่โดน SUM เข้า TDEO) — ถ้าหักแค่ฝั่งเวทจะกลายเป็นบวกเลขคนละนิยาม (net + gross) เข้าด้วยกัน อธิบายไม่ได้เลยว่าผลรวมคืออะไร แย่กว่าผิดสม่ำเสมอ สูตรใหม่ `cdors_calories = (METs − 1) × น้ำหนัก × เวลา` — ฐานเวลาคาร์ดิโอไม่มีปัญหาเรื่อง "รายเซ็ต" อยู่แล้ว (นับต่อเนื่องเป็นเซสชันเดียว) จุดที่แก้มีแค่หัก 1 MET + clamp ไม่ให้ติดลบ (METs ต่ำสุดในตาราง `cardio` ตอนนี้ = 7.0 ไม่ชนขอบ แต่กันไว้เผื่ออนาคต) implement แล้วที่ `SaveWorkoutResult` (คาร์ดิโอ) ใน `workout_controller.go`
- **⚠️ ค้าง — ข้อมูลเก่า (backfill):** `wtrs_calories`/`cdors_calories` ที่บันทึกก่อน 2026-08-22 (501 แถวเวท, 18 แถวคาร์ดิโอ ข้ามหลาย mb_id จริง ไม่ใช่แค่บัญชีทดสอบ) ยังเป็น gross ปนอยู่กับข้อมูลใหม่ที่เป็น net ในตารางเดียวกัน — กราฟ/รายงานย้อนหลังข้ามวันที่แก้จะมีรอยสะดุด ยังไม่ตัดสินใจว่าจะ backfill (`UPDATE ... SET calories = calories × (METs−1)/METs`) หรือปล่อยไว้พร้อมหมายเหตุ — **ต้อง backup ก่อนเสมอถ้าจะรัน backfill จริง**
- **⚠️ ค้าง — เอกสารเล่ม:** บทที่ 2 หัวข้อ 2.1.4.10 (คาร์ดิโอ) + 2.1.4.12 (เวทเทรนนิ่ง) และไฟล์สูตร/สมการฯ หัวข้อ 3.3 ต้องแก้ให้ตรงกับโค้ดใหม่ — ยังไม่ทราบพาธไฟล์เล่ม/ไฟล์สูตรที่แก้ได้จริงในเครื่องนี้

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
- query สมาชิกต้องมี `WHERE mb_status = 1`
- ALTER/DROP → **เตือนให้ backup ก่อนเสมอ** และให้คำสั่ง rollback ควบคู่

---

## 7. เมื่อช่วยเขียน/แก้เอกสาร (บทที่ 1-4)

- ภาษาราชการ/วิชาการ ไม่ใช้คาเวแมน
- คำศัพท์ตรงกันทุกบท (BMR, TDEE, Energy Balance, สมดุลพลังงาน)
- ปี พ.ศ. ในการอ้างอิงใช้รูปแบบเดิมของเล่ม (เช่น Ainsworth et al., 2554)
- ตัวเลข/สูตรต้องตรงข้อ 5 และตรงโค้ดจริง
- **ห้ามแต่งผลการทดสอบ/ผลประเมินความพึงพอใจ** — ไม่มีข้อมูลให้บอกว่าไม่มี
- อ้างรูปใช้เลขเดิม (เช่น รูปที่ 4.33 หน้าจอรายงานทั่วไป)
- แก้เอกสารเรื่องโครงสร้างตาราง → ต้องเช็ค D1-D8 ก่อนว่ากำลังเขียนตามของเก่าหรือของจริง

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
| `//check` | ตรวจโค้ด/เอกสารที่ให้มา เทียบสูตรข้อ 5 + Datadic + D1-D8 |
| `//diff` | ตรวจว่า Datadic 2 ฝั่ง (backend/Flutter) ยังตรงกันไหม |
| `//why` | อธิบายเหตุผลเบื้องหลังคำตอบล่าสุด |
| `//normal mode` | ปิดคาเวแมน |

---

## 10. เช็กลิสต์ก่อนส่งคำตอบ

- [ ] ประกาศ workspace แล้ว?
- [ ] ชื่อตาราง/คอลัมน์ตรง DB จริง?
- [ ] ชนิดข้อมูล unsigned / nullable ถูก?
- [ ] สูตร/ตัวเลขตรงข้อ 5?
- [ ] แตะจุด D1-D8 แล้วเตือนหรือยัง?
- [ ] query สมาชิกกรอง `mb_status = 1` แล้ว?
- [ ] ไม่ได้แก้ logic ที่ไม่ได้สั่ง?
- [ ] ไม่มีข้อมูล ได้บอกว่าไม่มี แทนที่จะเดา?
- [ ] คาเวแมนไม่ลามไปโค้ด/สูตร/เอกสาร?

---

## 11. ห้ามทำเด็ดขาด

1. ห้ามแต่งชื่อคอลัมน์/ตารางที่ไม่มีใน Datadic + dump
2. ห้ามอ้างตารางที่ลบแล้ว (`member_notifications`, `daily_water_intake`)
3. ห้ามเปลี่ยนตัวเลขในสูตร (20%, 15%, 1.2, 30, 4/4/9)
4. ห้ามเดาค่า MET ของเวทเทรนนิ่งแต่ละระดับ
5. ห้ามแต่งผลการทดสอบ/ค่าสถิติ/ผลประเมินในบทที่ 4
6. ห้ามแต่งงานวิจัยอ้างอิงหรือปี พ.ศ.
7. ห้ามลบคอมเมนต์เดิมในโค้ด
8. ห้ามเปลี่ยน tech stack (Flutter/Dart, Go, MySQL) โดยไม่ได้สั่ง
9. ห้ามให้คำสั่ง ALTER/DROP โดยไม่เตือน backup
10. ห้ามตอบยาวเวิ่นเว้อในโหมดคาเวแมน