package services

import (
	"fmt"
	"food_and_fit_api/config"
	"food_and_fit_api/models"

	"gorm.io/gorm"
)

// isSystemPlanModified เทียบท่าฝึกจริงของ user (workout_schedules ของสมาชิกคนนั้น กรองเฉพาะแถวที่
// เป็นท่าฝึกจริง wet_id IS NOT NULL ตัดแถวหัวแผน/placeholder ออก — ดูคอมเมนต์ WorkoutSchedule
// ใน models/exercise.go) กับแม่แบบระบบ (plan_template_detail) ทีละท่า/วัน/เซ็ต/ครั้ง — ไม่ใช่แค่
// นับจำนวนแถวเหมือนเดิม เพราะนับจำนวนอย่างเดียวพลาด 2 เคส:
// 1) แก้ sets/reps ของท่าเดิมเฉยๆ (UpdateWorkoutSchedule ไม่เพิ่ม/ลดแถว นับจำนวนไม่เปลี่ยน)
// 2) ลบท่า A แล้วเพิ่มท่า B แทนวันเดียวกัน (จำนวนรวมเท่าเดิมพอดี นับจำนวนตรวจไม่เจอว่าสลับท่าไปแล้ว)
// mbID = สมาชิกที่กำลังเช็ค, wptID = แม่แบบต้นทาง (workout_schedules.wpt_id ของแผนนั้น)
// daysPerWeek: wpt_days_per_week ของแผนต้นทาง — ต้องแปลง ptd_day_number (1..N วันในแผน) เป็น
// weekday (1-7) ก่อนเทียบกับ wsch_day_number เสมอ เพราะ CopySystemPlanToSchedule เขียน weekday
// ลง DB ไม่ใช่วันในแผนดิบๆ (บั๊กเดิม: เทียบกันตรงๆ โดยไม่แปลง ทำให้ is_modified ขึ้น true เท็จ
// สำหรับทุกแผนที่ daysPerWeek != 7)
func IsSystemPlanModified(db *gorm.DB, mbID uint, wptID uint, daysPerWeek int) bool {
	type scheduleRow struct {
		DayNumber int
		WetID     uint
		Sets      int
		Reps      string
	}

	var actual []scheduleRow
	db.Model(&models.WorkoutSchedule{}).
		Select("wsch_day_number as day_number, wet_id, wsch_sets as sets, wsch_reps as reps").
		Where("mb_id = ? AND wet_id IS NOT NULL", mbID).
		Scan(&actual)

	var template []scheduleRow
	db.Model(&models.PlanTemplateDetail{}).
		Select("ptd_day_number as day_number, wet_id, ptd_sets as sets, ptd_reps as reps").
		Where("wpt_id = ?", wptID).
		Scan(&template)

	if len(actual) != len(template) {
		return true
	}

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
			return true
		}
	}
	return false
}

// planDayWeekday แปลง plan day number (1..N) → weekday number (1=จันทร์...7=อาทิตย์)
// ตรงกับ _workoutDayMap ใน Flutter: 2:[0,3], 3:[0,2,4], 4:[0,1,3,4], 5:[0,1,2,3,4], 6:[0,1,2,3,4,5]
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

// validateTemplateComplete - เช็ก V1-V3 ก่อน copy แผนแม่แบบไปให้สมาชิก:
// ต้องมีวันฝึกอย่างน้อย 1 วัน (V1), แต่ละวันต้องมีท่าฝึกอย่างน้อย 1 ท่า (V2),
// และจำนวนวันที่ตั้งค่าไว้จริงใน plan_template_detail ต้องครบตาม wpt_days_per_week ที่ประกาศไว้ (V3)
// เรียกก่อน copy ทุกจุด (SelectWorkoutPlan / ActivatePlan / ResetWorkoutPlan) กันสำเนาแผนที่แอดมินตั้งค่าไม่ครบไปให้สมาชิก
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

// ClearWorkoutSchedules - ลบ workout_schedules ของ user ทั้งหมด (รวมแถวหัวแผน/placeholder ถ้ามี)
// ใช้ตอนสลับแผน — user มีแผน active ได้แค่ 1 แผนเสมอ ไม่เก็บ history แผนเดิมไว้เลย
// weight_training_result ไม่หายตาม เพราะ wtrs.wsch_id เป็น FK แบบ SET NULL ไม่ใช่ CASCADE
// (2026-09-04 รอบ 2: workout_schedules มีคอลัมน์ mb_id ตรงๆ แล้ว หลังยุบ member_workout_plans เข้ามา
// ไม่ต้องอ้อมผ่านตารางแยกอีกต่อไป)
func ClearWorkoutSchedules(tx *gorm.DB, uid uint) error {
	return tx.Where("mb_id = ?", uid).Delete(&models.WorkoutSchedule{}).Error
}

// StartNewPlan - ล้างแผน+ท่าฝึกเดิมของสมาชิกทั้งหมดทิ้ง แล้วสร้าง "แถวหัวแผน" ใหม่ 1 แถว (wet_id
// เป็น NULL, wsch_day_number = 0) ไว้เก็บชื่อแผน/จำนวนวันต่อสัปดาห์/แม่แบบต้นทาง — จำเป็นต้องมีแถวนี้
// เสมอแม้ยังไม่มีท่าฝึกสักท่า (เช่นตอนเพิ่งสร้างแผนส่วนตัวใหม่) ไม่งั้นไม่มีที่เก็บชื่อแผนเลย
// (workout_schedules ยุบรวม member_workout_plans เข้ามาแล้ว 2026-09-04 รอบ 2 — ดู models/exercise.go)
// คืนค่าแถวหัวแผนนี้ให้ caller ใช้ 1 สมาชิกมีแผนได้แค่ 1 แผนเสมอ จึงไม่ต้องมี "รหัสแผน" แยกจริงๆ
// อีกต่อไป (ตัวตอบ JSON ยังคง key "mwp_id" ไว้เพื่อความเข้ากันได้กับ Flutter เดิม แต่ค่าที่ส่งกลับ
// คือ mb_id ของสมาชิกเอง ไม่ใช่รหัสแถวจริง)
// sourceWptID = nil คือแผนสร้างเอง, ไม่ nil คือ copy จากแม่แบบ
func StartNewPlan(tx *gorm.DB, uid uint, name string, daysPerWeek int, sourceWptID *uint) (models.WorkoutSchedule, error) {
	if err := ClearWorkoutSchedules(tx, uid); err != nil {
		return models.WorkoutSchedule{}, err
	}
	header := models.WorkoutSchedule{
		WschPlanName:    name,
		WschDaysPerWeek: daysPerWeek,
		WschDayNumber:   0,
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

// CopySystemPlanToSchedule - ก็อปท่าฝึกจาก plan_template_detail ของแม่แบบ wptID ไปเป็น
// workout_schedules ของสมาชิก แทนที่แผนเดิมทั้งหมด (ล้าง + สร้างแถวหัวแผนใหม่ผูก wpt_id ไว้ — ดู
// StartNewPlan) ใช้ร่วมกันทั้ง SelectWorkoutPlan / ActivatePlan (สาขา wpt_id) / ResetWorkoutPlan
// (สาขาระบบ) เพราะทั้ง 3 จุดทำสิ่งเดียวกัน — ต้องเรียกใน transaction เสมอ (caller เป็นคนครอบ)
func CopySystemPlanToSchedule(tx *gorm.DB, uid uint, plan models.WorkoutPlanTemplate) (int, error) {
	var details []models.PlanTemplateDetail
	if err := tx.Where("wpt_id = ?", plan.WptID).Find(&details).Error; err != nil {
		return 0, err
	}
	if len(details) == 0 {
		return 0, ErrPlanHasNoDetails
	}

	if _, err := StartNewPlan(tx, uid, plan.WptName, int(plan.WptDaysPerWeek), &plan.WptID); err != nil {
		return 0, err
	}

	inserted := 0
	for _, d := range details {
		if d.WetID == nil {
			continue
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

// GetBestOneRepMax ดึง Estimated 1RM ที่ดีที่สุดของสมาชิกคนนี้ในท่านี้ จากประวัติที่มีอยู่แล้ว
// เท่านั้น (query ก่อนบันทึกเซสชันใหม่เสมอ จึงไม่รวมเซตที่กำลังจะบันทึก) — ใช้ร่วมกันระหว่าง
// GetBest1RM (แสดงผลอย่างเดียว) และ SaveWorkoutResult (แสดง one_rep_max_used ใน response — ไม่ได้ใช้
// คำนวณพลังงานแล้ว หลังลบสูตรเวทออก 2026-09-22) แยกออกมาเพื่อไม่ให้ 2 endpoint สูตรตัน
func GetBestOneRepMax(mbID, wetID uint) (best1RM, bestWeight float64, bestReps int, bestDate string, hasData bool) {
	var row struct {
		BestWeight float64 `gorm:"column:best_weight"`
		BestReps   int     `gorm:"column:best_reps"`
		Date       string  `gorm:"column:date"`
	}
	config.DB.Raw(`
		SELECT wtrs_weight AS best_weight, wtrs_reps AS best_reps, wtrs_date AS date
		FROM weight_training_result
		WHERE mb_id = ? AND wet_id = ? AND wtrs_weight > 0 AND wtrs_reps > 0
		ORDER BY (wtrs_weight * (1 + wtrs_reps / 30.0)) DESC
		LIMIT 1
	`, mbID, wetID).Scan(&row)

	if row.BestWeight == 0 {
		return 0, 0, 0, "", false
	}
	best1RM = EstimateOneRepMax(row.BestWeight, row.BestReps)
	return best1RM, row.BestWeight, row.BestReps, row.Date, true
}
