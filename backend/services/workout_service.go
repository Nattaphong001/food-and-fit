package services

import (
	"fmt"
	"food_and_fit_api/config"
	"food_and_fit_api/models"

	"gorm.io/gorm"
)

// IsSystemPlanModified เช็คว่าสมาชิกแก้แผนฝึกที่ก็อปมาจากแม่แบบระบบไปหรือยัง — เทียบท่าฝึกจริงของ
// สมาชิก (workout_schedules) กับแม่แบบต้นทาง (plan_template_detail) ทีละท่า/วัน/เซ็ต/จำนวนครั้ง
// (ไม่ใช่แค่นับจำนวนแถวเทียบกัน เพราะนับจำนวนอย่างเดียวจับไม่ได้ทั้งกรณีแก้ sets/reps ของท่าเดิม
// และกรณีสลับท่า A เป็นท่า B ในวันเดียวกัน)
// mbID = สมาชิกที่กำลังเช็ค, wptID = แม่แบบต้นทาง, daysPerWeek = จำนวนวันฝึกต่อสัปดาห์ของแผนนั้น
// (ใช้แปลง "วันที่ N ในแผน" เป็น "วันในสัปดาห์" ก่อนเทียบ เพราะ 2 ตารางเก็บเลขวันคนละความหมายกัน)
func IsSystemPlanModified(db *gorm.DB, mbID uint, wptID uint, daysPerWeek int) bool {
	type scheduleRow struct {
		DayNumber int
		WetID     uint
		Sets      int
		Reps      string
	}

	// ท่าฝึกจริงของสมาชิก (กรองตัดแถวหัวแผน/placeholder ที่ wet_id เป็น NULL ออก)
	var actual []scheduleRow
	db.Model(&models.WorkoutSchedule{}).
		Select("wsch_day_number as day_number, wet_id, wsch_sets as sets, wsch_reps as reps").
		Where("mb_id = ? AND wet_id IS NOT NULL", mbID).
		Scan(&actual)

	// ท่าฝึกของแม่แบบระบบต้นทาง
	var template []scheduleRow
	db.Model(&models.PlanTemplateDetail{}).
		Select("ptd_day_number as day_number, wet_id, ptd_sets as sets, ptd_reps as reps").
		Where("wpt_id = ?", wptID).
		Scan(&template)

	// จำนวนท่าไม่เท่ากัน = แก้ไปแล้วแน่นอน
	if len(actual) != len(template) {
		return true
	}

	// เทียบทีละท่า: แปลงวันของแม่แบบเป็น "วันในสัปดาห์" ก่อน แล้วจับคู่ด้วย (วัน, ท่า) เทียบ sets/reps
	type key struct {
		Day   int
		WetID uint
	}
	templateMap := make(map[key]scheduleRow, len(template))
	for _, t := range template {
		t.DayNumber = ToWeekday(daysPerWeek, t.DayNumber)
		templateMap[key{t.DayNumber, t.WetID}] = t
	}
	for _, a := range actual {
		t, ok := templateMap[key{a.DayNumber, a.WetID}]
		if !ok || t.Sets != a.Sets || t.Reps != a.Reps {
			return true // ไม่เจอท่าตรง (วัน,ท่า) เดียวกัน หรือ sets/reps ไม่ตรง = แก้ไปแล้ว
		}
	}
	return false
}

// planDayWeekday แปลง "วันที่ N ในแผน" (1..จำนวนวันฝึกต่อสัปดาห์) → "วันในสัปดาห์" (1=จันทร์...7=อาทิตย์)
// ต้องตรงกับ _workoutDayMap ฝั่ง Flutter เสมอ (ถ้าแก้ต้องแก้ทั้ง 2 ฝั่ง)
var planDayWeekday = map[int][]int{
	2: {1, 4},
	3: {1, 3, 5},
	4: {1, 2, 4, 5},
	5: {1, 2, 3, 4, 5},
	6: {1, 2, 3, 4, 5, 6},
}

func ToWeekday(daysPerWeek, planDayNum int) int {
	wds, ok := planDayWeekday[daysPerWeek]
	if !ok {
		return planDayNum
	}
	idx := planDayNum - 1
	if idx < 0 || idx >= len(wds) {
		return planDayNum
	}
	return wds[idx]
}

// ValidateTemplateComplete เช็คว่าแม่แบบแผนนี้ตั้งค่าครบก่อนจะให้สมาชิกเลือกใช้:
// ต้องกำหนดจำนวนวันฝึกต่อสัปดาห์ไว้แล้ว และทุกวันฝึก (1..daysPerWeek) ต้องมีท่าฝึกอย่างน้อย 1 ท่า
// เรียกก่อน copy แผนให้สมาชิกทุกจุด กันแอดมินตั้งค่าแผนไม่ครบแล้วมีคนเอาไปใช้
func ValidateTemplateComplete(wptID uint, daysPerWeek int) error {
	if daysPerWeek < 1 {
		return fmt.Errorf("แผนนี้ยังไม่ได้กำหนดจำนวนวันฝึกต่อสัปดาห์ กรุณาติดต่อผู้ดูแลระบบ")
	}

	type dayCount struct {
		Day   int
		Total int64
	}
	var counts []dayCount
	config.DB.Model(&models.PlanTemplateDetail{}).
		Select("ptd_day_number as day, COUNT(*) as total").
		Where("wpt_id = ? AND wet_id IS NOT NULL", wptID).
		Group("ptd_day_number").
		Scan(&counts)

	byDay := make(map[int]int64, len(counts))
	for _, dc := range counts {
		byDay[dc.Day] = dc.Total
	}

	for day := 1; day <= daysPerWeek; day++ {
		if byDay[day] == 0 {
			return fmt.Errorf("แผนนี้ยังตั้งค่าไม่ครบ: วันฝึกที่ %d ยังไม่มีท่าฝึก กรุณาติดต่อผู้ดูแลระบบ", day)
		}
	}
	return nil
}

// ClearWorkoutSchedules ลบ workout_schedules ของสมาชิกคนนี้ทั้งหมด (รวมแถวหัวแผนด้วยถ้ามี)
// ใช้ตอนสลับแผน — สมาชิกมีแผน active ได้แค่ 1 แผนเสมอ ไม่เก็บแผนเดิมไว้เป็นประวัติ
// (ผลการฝึกที่บันทึกไปแล้ว weight_training_result ไม่หายตามไปด้วย เพราะ FK เป็นแบบ SET NULL)
func ClearWorkoutSchedules(tx *gorm.DB, uid uint) error {
	return tx.Where("mb_id = ?", uid).Delete(&models.WorkoutSchedule{}).Error
}

// StartNewPlan ล้างแผนเดิมของสมาชิกทิ้งทั้งหมด แล้วสร้าง "แถวหัวแผน" ใหม่ 1 แถว (ยังไม่มีท่าฝึก)
// ไว้เก็บชื่อแผน/จำนวนวันฝึกต่อสัปดาห์/แม่แบบต้นทาง — ต้องมีแถวนี้เสมอแม้ยังไม่เพิ่มท่าฝึกเลยสักท่า
// (เช่นตอนเพิ่งกด "สร้างแผนส่วนตัว") ไม่งั้นไม่มีที่เก็บชื่อแผน
// sourceWptID = nil คือแผนที่สมาชิกสร้างเอง, ไม่ nil คือแผนที่ก็อปมาจากแม่แบบระบบ
func StartNewPlan(tx *gorm.DB, uid uint, name string, daysPerWeek int, sourceWptID *uint) (models.WorkoutSchedule, error) {
	if err := ClearWorkoutSchedules(tx, uid); err != nil {
		return models.WorkoutSchedule{}, err
	}
	header := models.WorkoutSchedule{
		WschPlanName:    name,
		WschDaysPerWeek: daysPerWeek,
		WschDayNumber:   0, // 0 = แถวหัวแผน ไม่ใช่วันฝึกจริง
		WschOrder:       1,
		MbID:            uid,
		WptID:           sourceWptID,
	}
	if err := tx.Create(&header).Error; err != nil {
		return models.WorkoutSchedule{}, err
	}
	return header, nil
}

var ErrPlanHasNoDetails = fmt.Errorf("แผนนี้ยังไม่มีท่าฝึก")

// CopySystemPlanToSchedule ก็อปท่าฝึกทั้งหมดจากแม่แบบระบบ (plan_template_detail) มาเป็นแผนของสมาชิก
// (workout_schedules) แทนที่แผนเดิมทั้งหมด — ใช้ร่วมกันตอนเลือกแผนระบบ/รีเซ็ตแผนกลับเป็นค่าเริ่มต้น
// ต้องเรียกภายใน transaction เสมอ
func CopySystemPlanToSchedule(tx *gorm.DB, uid uint, plan models.WorkoutPlanTemplate) (int, error) {
	var details []models.PlanTemplateDetail
	if err := tx.Where("wpt_id = ?", plan.WptID).Find(&details).Error; err != nil {
		return 0, err
	}
	if len(details) == 0 {
		return 0, ErrPlanHasNoDetails
	}

	// ล้างแผนเดิม + สร้างแถวหัวแผนใหม่ผูกกับแม่แบบนี้ก่อน
	if _, err := StartNewPlan(tx, uid, plan.WptName, int(plan.WptDaysPerWeek), &plan.WptID); err != nil {
		return 0, err
	}

	// ก็อปท่าฝึกทีละท่าจากแม่แบบ
	inserted := 0
	for _, d := range details {
		if d.WetID == nil {
			continue // ข้ามแถวที่ไม่มีท่าฝึกจริง (เช่น placeholder ของแม่แบบ)
		}
		ws := models.WorkoutSchedule{
			WschPlanName:    plan.WptName,
			WschDaysPerWeek: int(plan.WptDaysPerWeek),
			WschDayNumber:   ToWeekday(int(plan.WptDaysPerWeek), int(d.PtdDayNumber)),
			WschDayName:     d.PtdDayName,
			WschOrder:       d.PtdOrder,
			WschSets:        d.PtdSets,
			WschReps:        d.PtdReps,
			WschRestSeconds: d.PtdRestSeconds,
			MbID:            uid,
			WptID:           &plan.WptID,
			WetID:           d.WetID,
		}
		if err := tx.Create(&ws).Error; err != nil {
			return inserted, err
		}
		inserted++
	}
	return inserted, nil
}

var bestOneRepMaxSQL = `
	SELECT wtrs_weight AS best_weight, wtrs_reps AS best_reps, wtrs_date AS date
	FROM weight_training_result
	WHERE mb_id = ? AND wet_id = ? AND wtrs_weight > 0 AND wtrs_reps BETWEEN 1 AND ?
	ORDER BY ` + OneRepMaxSQL("wtrs_weight", "wtrs_reps") + ` DESC
	LIMIT 1
`

// GetBestOneRepMax หาค่า Estimated 1RM ที่ดีที่สุดของสมาชิกคนนี้ในท่านี้ จากประวัติที่บันทึกไว้แล้ว
// เท่านั้น (ไม่รวมเซตที่กำลังจะบันทึกใหม่) — ใช้แสดงผลหน้าจอ 1RM และเป็นค่าฐานสำหรับเตือน (ไม่ block)
// เมื่อ 1RM ที่ประเมินได้ในเซสชันใหม่กระโดดผิดปกติ (ดู workout_controller.go SaveWorkoutResult)
// และเป็น "1RM อ้างอิง" (PR ก่อนเซสชัน) ของสูตรพลังงานเวท — %1RM ของแต่ละเซต = W / ค่านี้
// (ต้องเรียกก่อนบันทึกเซตของเซสชันใหม่เสมอ ดู ../../CLAUDE.md ข้อ 7[B-1])
func GetBestOneRepMax(mbID, wetID uint) (best1RM, bestWeight float64, bestReps int, bestDate string, hasData bool) {
	var row struct {
		BestWeight float64 `gorm:"column:best_weight"`
		BestReps   int     `gorm:"column:best_reps"`
		Date       string  `gorm:"column:date"`
	}
	// Dual-Formula: Epley reps 1-10, Desgorces reps 11-20 (OneRepMaxSQL) — reps > 20 ประเมินไม่ได้
	// เลือกเซตที่ให้ 1RM ประมาณสูงสุดจากทุกเซตที่เคยบันทึกของท่านี้
	config.DB.Raw(bestOneRepMaxSQL, mbID, wetID, DesgorcesMaxReps).Scan(&row)

	if row.BestWeight == 0 {
		return 0, 0, 0, "", false // ไม่เคยฝึกท่านี้มาก่อนเลย
	}
	best1RM = EstimateOneRepMax(row.BestWeight, row.BestReps)
	return best1RM, row.BestWeight, row.BestReps, row.Date, true
}
