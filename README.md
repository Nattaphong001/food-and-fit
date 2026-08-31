# Food & Fit

> **EN:** Food & Fit — a fitness and nutrition tracking app that calculates BMR/TDEE, logs meals and workouts, and reports daily energy balance against user goals. Built solo: Flutter mobile app, Flutter Web admin panel, and a Go/Gin REST API on MySQL.

> วันนี้กินเข้าไปเท่าไหร่ เผาผลาญไปเท่าไหร่ และมันพาคุณเข้าใกล้เป้าหมายหรือถอยห่าง — Food & Fit ตอบคำถามนี้ให้คุณทุกวัน

โมบายแอปจัดการการออกกำลังกายและโภชนาการ สร้างขึ้นเพื่อแก้ปัญหาที่คนเริ่มดูแลสุขภาพเจอเหมือนกันหมด: คำนวณ BMR/TDEE เองไม่เป็น จดอาหารและสถิติการฝึกด้วยมือไม่ไหว และไม่เคยเห็นภาพรวมสมดุลพลังงาน (Energy Balance) ที่แท้จริงของตัวเอง

แอปรวมทุกขั้นตอนไว้ที่เดียว: คำนวณพลังงานพื้นฐานจากข้อมูลร่างกาย → บันทึกอาหาร/เวทเทรนนิ่ง/คาร์ดิโอระหว่างวัน → สรุปเป็น Energy Balance เทียบกับเป้าหมาย (ลดน้ำหนัก / เพิ่มกล้ามเนื้อ / รักษาน้ำหนัก) พร้อมรายงานรายวัน/สัปดาห์/เดือน

โปรเจกต์ปริญญานิพนธ์ ทีม 3 คน — รับผิดชอบพัฒนาระบบร่วมกัน ทั้ง backend, mobile app และ admin web

---

## ภาพหน้าจอ

<!--
  ใส่รูปจริงตรงนี้ก่อน publish เช่น:
  | คำนวณ TDEE | บันทึกเวทเทรนนิ่ง | รายงานสัปดาห์ |
  |---|---|---|
  | <img src="docs/screenshots/onboarding.png" width="240"> | <img src="docs/screenshots/workout.png" width="240"> | <img src="docs/screenshots/report.png" width="240"> |
  แนะนำ: หน้า Onboarding คำนวณ BMR/TDEE, หน้าบันทึกอาหารรายวัน, หน้ารายงานสัปดาห์/เดือน, หน้า admin dashboard
-->
_(รอใส่ภาพหน้าจอจริงจากแอป)_

---

## สถาปัตยกรรมระบบ

```
┌─────────────┐     ┌──────────────┐
│  mobile/    │     │  admin-web/  │
│  Flutter    │     │ Flutter Web  │
│  (ผู้ใช้)     │     │  (แอดมิน)     │
└──────┬──────┘     └───────┬──────┘
       │   REST API + JWT   │
       └─────────┬──────────┘
                  ▼
          ┌──────────────┐
          │  backend/    │
          │  Go + Gin    │
          └──────┬───────┘
                  ▼
          ┌──────────────┐
          │    MySQL     │
          │  17 ตาราง     │
          └──────────────┘
```

---

## ฟีเจอร์

### ฝั่งผู้ใช้ (mobile/ — Flutter)
- สมัคร/เข้าสู่ระบบ พร้อมยืนยันอีเมลด้วย OTP, ลืมรหัสผ่าน
- Onboarding คำนวณ BMR/TDEE จากข้อมูลร่างกาย พร้อมตั้งเป้าหมาย (ลด/เพิ่ม/รักษาน้ำหนัก)
- บันทึกน้ำหนัก/สัดส่วนร่างกาย ดูกราฟย้อนหลังทั้งหมด
- เลือกแผนออกกำลังกายสำเร็จรูป (2–6 วัน/สัปดาห์) หรือสร้างแผนส่วนตัวของตัวเอง แก้ไข/fork ได้อิสระ
- บันทึกผลเวทเทรนนิ่งรายเซ็ต พร้อมประเมิน 1RM และดูประวัติ 1RM ย้อนหลัง
- บันทึกผลคาร์ดิโอ
- ค้นหาและบันทึกรายการอาหารรายวัน แยกตามมื้อ
- รายงานสรุป: รายวัน / รายสัปดาห์ / รายเดือน / เทียบเดือนต่อเดือน / สัดส่วนกล้ามเนื้อที่ฝึกครอบคลุม / ภาพรวมความก้าวหน้า

### ฝั่งแอดมิน (admin-web/ — Flutter Web)
- ระบบแอดมินหลายบัญชี (สร้าง/ปิดใช้งานบัญชีแอดมิน)
- Dashboard summary + Analytics overview ภาพรวมสมาชิกทั้งระบบ
- ดูรายชื่อและรายละเอียดสมาชิก
- จัดการ master data ทั้งหมด: เมนูอาหาร + หมวดหมู่, ท่าเวทเทรนนิ่ง + กลุ่มกล้ามเนื้อ, คาร์ดิโอ + หมวดหมู่, แผนออกกำลังกายแม่แบบ
- Bulk action หน้าฐานข้อมูลโภชนาการ: เลือกทั้งหมด / ลบหลายรายการ / ย้ายหมวดหมู่หลายรายการ พร้อม Undo
- อัปโหลดรูปภาพหมวดหมู่อาหาร/คาร์ดิโอ

---

## จุดที่ยากที่สุด: สูตรคำนวณพลังงานจากการออกกำลังกาย

ส่วนที่ยากและใช้เวลาแก้มากที่สุดของโปรเจกต์คือสูตรคำนวณแคลอรี่ที่เผาผลาญจากเวทเทรนนิ่งและคาร์ดิโอ

**ปัญหาเดิม:** ค่าที่บันทึกเป็น "gross calories" (พลังงานเผาผลาญรวมทั้งหมด) ถูกบวกตรงเข้าสูตร Total Daily Energy Output ที่มี Baseline Expenditure (BMR × 1.2) รวมอยู่แล้ว — ทำให้พลังงานพื้นฐานถูกนับซ้ำสองรอบ นอกจากนี้ฐานเวลาที่ใช้คำนวณ (เฉพาะช่วงออกแรงต่อเซต) ก็ไม่ตรงกับนิยามของหน่วย METs ซึ่งควรเป็นค่าเฉลี่ยทั้งเซสชันรวมเวลาพัก

**ทางแก้:** เปลี่ยนสูตรเป็น **net METs**: `(METs − 1) × น้ำหนัก(kg) × เวลา(ชม.)` ใช้เวลาทั้งเซสชัน (รวมพัก) หารเฉลี่ยเท่ากันทุกเซ็ต ใช้หลักการเดียวกันทั้งเวทเทรนนิ่งและคาร์ดิโอ พร้อม clamp ไม่ให้ค่าติดลบเมื่อ METs ≤ 1 ค่า gross เดิมยังคำนวณย้อนกลับได้เสมอ (`gross = net × METs / (METs − 1)`) จึงไม่มีข้อมูลสูญหาย

ค่า METs อ้างอิงจาก 2011 Compendium of Physical Activities (Ainsworth et al.) และยืนยันซ้ำว่าตรงกับ 2024 Adult Compendium ฉบับล่าสุด

---

## เทคโนโลยีที่ใช้

**Backend** (`backend/`)
- Go 1.25 + [Gin](https://github.com/gin-gonic/gin) (REST API)
- [GORM](https://gorm.io/) + MySQL/MariaDB
- JWT (`golang-jwt/jwt`) + token denylist ตอน logout
- bcrypt password hashing (`golang.org/x/crypto`)
- Rate limiting ต่อ IP (เข้มขึ้นเฉพาะ endpoint auth/OTP กัน brute-force)
- CORS แบบ allowlist เจาะจง origin + security headers middleware
- Audit log ทุก action ที่แก้ข้อมูลสำคัญ

**Mobile** (`mobile/`) — Flutter / Dart (iOS + Android)
**Admin Web** (`admin-web/`) — Flutter Web

**Database**
- MySQL/MariaDB — `food_and_fit_db` — 17 ตารางธุรกิจ (โปรไฟล์สมาชิก, ข้อมูลร่างกาย, แผนออกกำลังกาย, ผลเวท/คาร์ดิโอ, โภชนาการรายวัน ฯลฯ) + ตารางระบบสำหรับ audit log / revoked token

---

## เริ่มต้นใช้งาน

### Backend
```bash
cd backend

# 1. import ฐานข้อมูล (schema + master data เท่านั้น — ไม่มีข้อมูลสมาชิก/แอดมินจริง)
mysql -u root -p food_and_fit_db < migrations/schema.sql
mysql -u root -p food_and_fit_db < migrations/seed_master.sql

# 2. ตั้งค่า .env (ดูตัวแปรที่ต้องมีด้านล่าง)

# 3. รันเซิร์ฟเวอร์
go mod tidy
go run main.go
# API: http://localhost:8081/api
```

ตัวแปรที่ต้องตั้งใน `backend/.env`:
```
DB_USER=
DB_PASS=
DB_HOST=
DB_PORT=
DB_NAME=
PORT=
JWT_SECRET=
GIN_MODE=
ALLOWED_ORIGINS=
SMTP_EMAIL=
SMTP_PASSWORD=
```

### แอปฝั่งผู้ใช้ (mobile/)
```bash
cd mobile
flutter pub get
flutter run
```

### แอปฝั่งแอดมิน (admin-web/)
```bash
cd admin-web
flutter pub get
flutter run -d chrome
```

---

## เกี่ยวกับโปรเจกต์

โปรเจกต์ปริญญานิพนธ์ · ทีม 3 คน · ระยะเวลาพัฒนา ~6 เดือน — กำลังพัฒนาต่อเนื่อง

**บทบาทของผม (Nattaphong) — พัฒนาระบบทั้งหมดคนเดียว**

| ส่วน | รายละเอียด |
|---|---|
| Backend | ออกแบบฐานข้อมูล 17 ตาราง, REST API ด้วย Go + Gin, ระบบ JWT authentication, rate limiting, audit log |
| Mobile app | Flutter ฝั่งผู้ใช้ทั้งหมด — onboarding, บันทึกอาหาร/เวท/คาร์ดิโอ, รายงาน |
| Admin web | Flutter Web ฝั่งผู้ดูแลระบบทั้งหมด — dashboard, จัดการ master data, bulk action |

**เพื่อนร่วมทีมอีก 2 คน** รับผิดชอบด้านเอกสารประกอบปริญญานิพนธ์ ออกแบบ UI/UX และรวบรวมข้อมูลโภชนาการ
