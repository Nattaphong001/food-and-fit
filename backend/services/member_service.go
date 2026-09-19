package services

import (
	"food_and_fit_api/models"
	"time"

	"gorm.io/gorm"
)

// AgeFromBirthDate คำนวณอายุเต็มปี ณ เวลาปัจจุบัน จากวันเกิดที่กำหนด
func AgeFromBirthDate(birthDate time.Time) int {
	return AgeOn(birthDate, time.Now())
}

// AgeOn คำนวณอายุเต็มปี ณ วันที่ on เทียบ "เดือน+วัน" ของวันเกิด ไม่ใช่ YearDay
// (เดิมเทียบ YearDay คลาด 1 วันรอบวันเกิดเมื่อปีเกิดกับปีปัจจุบันต่างกันที่ปีอธิกสุรทิน เพราะ
// หลัง 29 ก.พ. ลำดับวันในปีเลื่อนไป 1 เช่น เกิด 1 มี.ค. 2000 (วันที่ 61) เทียบกับ 1 มี.ค. 2025
// (วันที่ 60) ได้ว่ายังไม่ถึงวันเกิด) — ผู้ที่เกิด 29 ก.พ. ปีที่ไม่ใช่ปีอธิกสุรทิน ถือว่าครบรอบวันที่ 1 มี.ค.
func AgeOn(birthDate, on time.Time) int {
	age := on.Year() - birthDate.Year()
	if on.Month() < birthDate.Month() ||
		(on.Month() == birthDate.Month() && on.Day() < birthDate.Day()) {
		age--
	}
	return age
}

// UpsertBodyStatToday - upsert รายวัน (D10, ดู mobile/CLAUDE.md ข้อ D10) ของ member_body_stats:
// ถ้ามีแถวของวันนี้ (DATE(mbs_recorded_date) = วันนี้) อยู่แล้ว อัปเดตทับแถวเดิม ไม่สร้างแถวใหม่
// กันไม่ให้กดบันทึกรัวๆ ในวันเดียวกันได้แถว noise ซ้อนกันหลายแถว — ต้องเรียกใน transaction เสมอ
// (caller เป็นคนครอบ tx) เดิมโค้ดนี้อินไลน์ซ้ำ 2 จุด (UpdateProfile/UpdateBodyStats) รวมมาไว้จุดเดียว
// เพื่อกันบั๊กแบบที่เคยเกิดมาแล้วจาก D10 (แก้จุดหนึ่งแล้วลืมอีกจุด)
//
// .Order().Limit(1) จำเป็นจริง ไม่ใช่แค่กันไว้เฉยๆ — GORM Find() บน struct เดี่ยว (ไม่ใช่ slice)
// เรียก rows.Next() แค่ครั้งเดียวแล้วทิ้งแถวที่เหลือ (ดู gorm scan.go: case reflect.Struct ใช้ if
// ไม่ใช่ for) ถ้าไม่ระบุ ORDER BY แถวที่ได้ขึ้นกับลำดับที่ MySQL คืนมาเฉยๆ ซึ่งตรงข้ามกับที่ต้องการ
// ถ้ามีแถวผีเก่าซ้ำวันเดียวกันค้างอยู่ — ต้องบังคับเอาแถว mbs_id สูงสุดของวันนั้นเสมอ
func UpsertBodyStatToday(tx *gorm.DB, mbID int, weight, height, activityLevel float64, target int) (models.MemberBodyStat, error) {
	now := time.Now()
	todayStr := now.Format("2006-01-02")

	var existingStat models.MemberBodyStat
	tx.Where("mb_id = ? AND DATE(mbs_recorded_date) = ?", mbID, todayStr).
		Order("mbs_id desc").Limit(1).Find(&existingStat)

	if existingStat.MbsID != 0 {
		bodyStat := existingStat
		bodyStat.MbsWeight = weight
		bodyStat.MbsHeight = height
		bodyStat.MbsActivityLevel = activityLevel
		bodyStat.MbsTarget = target
		bodyStat.MbsRecordedDate = now
		if err := tx.Model(&models.MemberBodyStat{}).Where("mbs_id = ?", bodyStat.MbsID).Updates(map[string]interface{}{
			"mbs_weight":         bodyStat.MbsWeight,
			"mbs_height":         bodyStat.MbsHeight,
			"mbs_activity_level": bodyStat.MbsActivityLevel,
			"mbs_target":         bodyStat.MbsTarget,
			"mbs_recorded_date":  bodyStat.MbsRecordedDate,
		}).Error; err != nil {
			return bodyStat, err
		}
		return bodyStat, nil
	}

	bodyStat := models.MemberBodyStat{
		MbID:             mbID,
		MbsWeight:        weight,
		MbsHeight:        height,
		MbsActivityLevel: activityLevel,
		MbsTarget:        target,
		MbsRecordedDate:  now,
	}
	if err := tx.Create(&bodyStat).Error; err != nil {
		return bodyStat, err
	}
	return bodyStat, nil
}

// UpsertBmrHistoryToday - upsert รายวัน (D10) ของ member_bmr_history เหตุผล/กติกาเดียวกับ
// UpsertBodyStatToday ด้านบนทุกประการ ต้องเรียกใน transaction เสมอ — เดิมโค้ดนี้อินไลน์ซ้ำ 3 จุด
// (UpdateProfile/EditProfile/UpdateBodyStats) รวมมาไว้จุดเดียว
func UpsertBmrHistoryToday(tx *gorm.DB, mbID int, mbsID int, bmi, bmr, tdee, targetCal float64) error {
	now := time.Now()
	todayStr := now.Format("2006-01-02")
	todayDate := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

	var existingHistory models.MemberBmrHistory
	tx.Where("mb_id = ? AND mbh_record_date = ?", mbID, todayStr).
		Order("mbh_id desc").Limit(1).Find(&existingHistory)

	if existingHistory.MbhID != 0 {
		return tx.Model(&models.MemberBmrHistory{}).Where("mbh_id = ?", existingHistory.MbhID).Updates(map[string]interface{}{
			"mbs_id":          mbsID,
			"mbh_bmi":         bmi,
			"mbh_bmr":         bmr,
			"mbh_tdee":        tdee,
			"mbh_tdee_target": targetCal,
		}).Error
	}

	newHistory := models.MemberBmrHistory{
		MbID:          mbID,
		MbsID:         &mbsID,
		MbhBmi:        bmi,
		MbhBmr:        bmr,
		MbhTdee:       tdee,
		MbhTdeeTarget: targetCal,
		MbhRecordDate: todayDate,
	}
	return tx.Create(&newHistory).Error
}
