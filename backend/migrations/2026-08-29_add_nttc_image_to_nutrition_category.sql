-- เพิ่ม nttc_image ให้ nutrition_category (ตาราง 4.10) — เดิมไม่มีคอลัมน์รูป ใช้แค่ไอคอนแทน
-- ทำให้แอดมินดูหมวดหมู่จากรูปจริงไม่ได้ ตามคำขอ admin web ให้เพิ่มรูปหมวดหมู่โภชนาการ
-- เหมือน cdc_image ของ cardio_category (ตาราง 4.8) — ต้อง sync ER Diagram + เอกสารบทที่ 4 ตามไปด้วย
-- ไม่เพิ่มคำอธิบาย (ตัดสินใจแล้วว่าเอาแค่รูป)
-- ได้ backup ตาราง nutrition_category ไว้ที่ migrations/backups/backup_nutrition_category_before_nttc_image_20260829.sql ก่อนรันไฟล์นี้แล้ว

ALTER TABLE nutrition_category
  ADD COLUMN nttc_image VARCHAR(255) DEFAULT NULL
  COMMENT 'รูปหมวดหมู่โภชนาการ (path)' AFTER nttc_name;
