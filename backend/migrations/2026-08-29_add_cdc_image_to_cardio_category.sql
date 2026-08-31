-- เพิ่ม cdc_image ให้ cardio_category (ตาราง 4.4) — เดิมไม่มีคอลัมน์รูป ใช้แค่ไอคอน/สีแทน
-- ทำให้แอดมินดูหมวดหมู่จากรูปจริงไม่ได้ ตามคำขอ admin web ให้เพิ่มรูปหมวดหมู่คาร์ดิโอ
-- เหมือน mug_image ของ muscle_group (ตาราง 4.1) — ต้อง sync ER Diagram + เอกสารบทที่ 4 ตามไปด้วย
-- ได้ backup ตาราง cardio_category ไว้ที่ migrations/backups/backup_cardio_category_before_cdc_image_20260829.sql ก่อนรันไฟล์นี้แล้ว

ALTER TABLE cardio_category
  ADD COLUMN cdc_image VARCHAR(255) DEFAULT NULL
  COMMENT 'รูปหมวดหมู่คาร์ดิโอ (path)' AFTER cdc_description;
