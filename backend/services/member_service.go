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

// AgeOn คำนวณอายุเต็มปี ณ วันที่ on โดยเทียบเดือน+วันของวันเกิด (ไม่ใช่นับจำนวนวันในปีดิบๆ ซึ่งจะ
// คลาดเคลื่อนช่วงปีอธิกสุรทิน — รายละเอียด → formula-comments-history.md)
func AgeOn(birthDate, on time.Time) int {
	age := on.Year() - birthDate.Year()
	// ยังไม่ถึงวันเกิดของปีนี้ (เดือนน้อยกว่า หรือเดือนเท่ากันแต่วันยังไม่ถึง) → อายุยังไม่ครบปีนี้ ลบ 1
	if on.Month() < birthDate.Month() ||
		(on.Month() == birthDate.Month() && on.Day() < birthDate.Day()) {
		age--
	}
	return age
}

// UpsertBodyStatToday บันทึกข้อมูลร่างกาย (น้ำหนัก/ส่วนสูง/ระดับกิจกรรม/เป้าหมาย) ของวันนี้
// ถ้าวันนี้มีแถวอยู่แล้ว → แก้ไขแถวเดิมทับ (ไม่สร้างแถวใหม่ซ้ำ) ถ้ายังไม่มี → สร้างแถวใหม่
// ต้องเรียกภายใน transaction เสมอ (ฝั่งที่เรียกใช้เป็นคนเปิด/ปิด transaction เอง)
// รายละเอียดเหตุผล (ทำไมต้อง upsert, ทำไมต้องมี Order().Limit(1)) → formula-comments-history.md
func UpsertBodyStatToday(tx *gorm.DB, mbID int, weight, height, activityLevel float64, target int) (models.MemberBodyStat, error) {
	now := time.Now()
	todayStr := now.Format("2006-01-02")

	// หาแถวของวันนี้ (ถ้ามีหลายแถวซ้ำวันเดียวกัน เอาแถวล่าสุด mbs_id สูงสุด)
	var existingStat models.MemberBodyStat
	tx.Where("mb_id = ? AND DATE(mbs_recorded_date) = ?", mbID, todayStr).
		Order("mbs_id desc").Limit(1).Find(&existingStat)

	if existingStat.MbsID != 0 { // มีแถวของวันนี้แล้ว → อัปเดตทับ
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

	// ยังไม่มีแถวของวันนี้ → สร้างแถวใหม่
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

// UpsertBmrHistoryToday บันทึกผล BMI/BMR/TDEE/Target ที่คำนวณได้ของวันนี้ ลง member_bmr_history
// เหตุผล/กติกา upsert รายวันเหมือน UpsertBodyStatToday ด้านบนทุกประการ ต้องเรียกใน transaction เสมอ
func UpsertBmrHistoryToday(tx *gorm.DB, mbID int, mbsID int, bmi, bmr, tdee, targetCal float64) error {
	now := time.Now()
	todayStr := now.Format("2006-01-02")
	todayDate := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

	// หาแถวของวันนี้ (ถ้ามีหลายแถวซ้ำวันเดียวกัน เอาแถวล่าสุด mbh_id สูงสุด)
	var existingHistory models.MemberBmrHistory
	tx.Where("mb_id = ? AND mbh_record_date = ?", mbID, todayStr).
		Order("mbh_id desc").Limit(1).Find(&existingHistory)

	if existingHistory.MbhID != 0 { // มีแถวของวันนี้แล้ว → อัปเดตทับ
		return tx.Model(&models.MemberBmrHistory{}).Where("mbh_id = ?", existingHistory.MbhID).Updates(map[string]interface{}{
			"mbs_id":          mbsID,
			"mbh_bmi":         bmi,
			"mbh_bmr":         bmr,
			"mbh_tdee":        tdee,
			"mbh_tdee_target": targetCal,
		}).Error
	}

	// ยังไม่มีแถวของวันนี้ → สร้างแถวใหม่
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
