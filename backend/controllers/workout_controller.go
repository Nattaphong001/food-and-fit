package controllers

import (
	"errors"
	"fmt"
	"food_and_fit_api/config"
	"food_and_fit_api/helpers"
	"food_and_fit_api/models"
	"food_and_fit_api/services"
	"log"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// sentinel error ใช้เทียบผลลัพธ์จาก config.DB.Transaction ใน CreateWorkoutSchedule เพื่อแยก
// เคส error ทางธุรกิจ (คืน 404/400 ตามเดิม) ออกจาก error DB จริงๆ (คืน 500)
var (
	errPlanNotFound      = errors.New("plan_not_found")
	errDuplicateExercise = errors.New("duplicate_exercise")
)

// isSystemPlanModified เทียบท่าฝึกจริงของ user (workout_schedules ของสมาชิกคนนั้น กรองเฉพาะแถวที่
// เป็นท่าฝึกจริง wet_id IS NOT NULL ตัดแถวหัวแผน/placeholder ออก — ดูคอมเมนต์ WorkoutSchedule
// ใน models/exercise.go) กับแม่แบบระบบ (plan_template_detail) ทีละท่า/วัน/เซ็ต/ครั้ง — ไม่ใช่แค่
// นับจำนวนแถวเหมือนเดิม เพราะนับจำนวนอย่างเดียวพลาด 2 เคส:
// 1) แก้ sets/reps ของท่าเดิมเฉยๆ (UpdateWorkoutSchedule ไม่เพิ่ม/ลดแถว นับจำนวนไม่เปลี่ยน)
// 2) ลบท่า A แล้วเพิ่มท่า B แทนวันเดียวกัน (จำนวนรวมเท่าเดิมพอดี นับจำนวนตรวจไม่เจอว่าสลับท่าไปแล้ว)
// mbID = สมาชิกที่กำลังเช็ค, wptID = แม่แบบต้นทาง (workout_schedules.wpt_id ของแผนนั้น)
// daysPerWeek: wpt_days_per_week ของแผนต้นทาง — ต้องแปลง ptd_day_number (1..N วันในแผน) เป็น
// weekday (1-7) ก่อนเทียบกับ wsch_day_number เสมอ เพราะ copySystemPlanToSchedule เขียน weekday
// ลง DB ไม่ใช่วันในแผนดิบๆ (บั๊กเดิม: เทียบกันตรงๆ โดยไม่แปลง ทำให้ is_modified ขึ้น true เท็จ
// สำหรับทุกแผนที่ daysPerWeek != 7 — ดู docs/SPEC.md ข้อ 6 D3.3)
func isSystemPlanModified(db *gorm.DB, mbID uint, wptID uint, daysPerWeek int) bool {
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
		t.DayNumber = toWeekday(daysPerWeek, t.DayNumber)
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

func toWeekday(daysPerWeek, planDayNum int) int {
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
func validateTemplateComplete(wptID uint, daysPerWeek int) error {
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

// GetWorkoutTemplates - ดึงรายการแผนต้นแบบ (2-6 วัน) เพื่อให้ผู้ใช้เลือก
func GetWorkoutTemplates(c *gin.Context) {
	var templates []models.WorkoutPlanTemplate

	// ดึงเฉพาะแผนระบบ (wpt_difficulty > 0) เรียงตามจำนวนวัน
	if err := config.DB.Where("wpt_difficulty > 0").Order("wpt_days_per_week asc").Find(&templates).Error; err != nil {
		log.Printf("GetWorkoutTemplates: query failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": "ไม่สามารถดึงข้อมูลต้นแบบได้",
		})
		return
	}

	// ส่งกลับในรูปแบบมาตรฐานที่ Flutter ของนายรอรับอยู่
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    templates,
	})
}

// =========================================================
// 1. จัดการแม่แบบแผนการฝึก (Workout Plan Template)
// =========================================================

// ใน workout_controller.go หาฟังก์ชัน CreateWorkoutPlan แล้วแก้เป็น:
func CreateWorkoutPlan(c *gin.Context) {
	wptName := c.PostForm("wpt_name")
	wptDays, _ := strconv.Atoi(c.PostForm("wpt_days_per_week"))
	wptDesc := c.PostForm("wpt_description")
	wptDiff, _ := strconv.Atoi(c.PostForm("wpt_difficulty"))

	imagePath := ""
	if file, err := c.FormFile("wpt_image"); err == nil {
		if verr := helpers.ValidateImageUpload(file); verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		uploadDir := "./uploads/workout_plans"
		os.MkdirAll(uploadDir, os.ModePerm)
		newName := fmt.Sprintf("%d%s", time.Now().UnixNano(), filepath.Ext(file.Filename))
		if err := c.SaveUploadedFile(file, filepath.Join(uploadDir, newName)); err == nil {
			imagePath = "uploads/workout_plans/" + newName
		}
	}

	if ok, msg := helpers.ValidateWorkoutPlanTemplate(wptDays, wptDiff); !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}

	plan := models.WorkoutPlanTemplate{
		WptName:        wptName,
		WptDaysPerWeek: wptDays,
		WptDescription: wptDesc,
		WptDifficulty:  int8(wptDiff),
		WptImage:       imagePath,
	}

	result := config.DB.Where(models.WorkoutPlanTemplate{WptName: plan.WptName}).FirstOrCreate(&plan)
	if result.Error != nil {
		if helpers.IsDuplicateKeyError(result.Error) {
			c.JSON(http.StatusConflict, gin.H{"error": "มีแผนชื่อนี้อยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "จัดการแผนไม่สำเร็จ"})
		return
	}
	if result.RowsAffected > 0 {
		helpers.LogAdminMutation(c, "create", "workout_plan_template", plan.WptID, nil, plan)
	}
	c.JSON(http.StatusOK, gin.H{"message": "ดำเนินการสำเร็จ", "data": plan})
}

// CreateMemberPlan - เริ่มแผนส่วนตัวของ member (ไม่มีตารางเก็บ header อีกต่อไป)
// ท่าฝึกที่ผู้ใช้เพิ่มเองจะถูกบันทึกลง workout_schedules โดยตรง (wpt_id = NULL คือแผนส่วนตัว)
// คืนค่า mcp_id แบบ dummy ไว้เพื่อความเข้ากันได้กับ Flutter เดิม (ไม่ได้ใช้เป็น FK อีกแล้ว)
func CreateMemberPlan(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"success": true, "mcp_id": 1, "message": "เริ่มแผนส่วนตัวสำเร็จ"})
}

// ClearMemberPlanDetails - ล้างท่าฝึกทั้งหมดในแผน (ไม่ลบตัวแผน)
func ClearMemberPlanDetails(c *gin.Context) {
	planID := c.Param("id")
	if err := config.DB.Where("wpt_id = ?", planID).Delete(&models.PlanTemplateDetail{}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ล้างท่าฝึกไม่สำเร็จ"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "message": "ล้างท่าฝึกทั้งหมดแล้ว"})
}

// =========================================================
// 2. จัดการรายละเอียดแผน (Plan Template Detail)
// =========================================================

func AddPlanDetail(c *gin.Context) {
	var detail models.PlanTemplateDetail
	if err := c.ShouldBindJSON(&detail); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง กรุณาตรวจสอบข้อมูลที่ส่งมา"})
		return
	}
	// ptd_id/ptd_order ต้องเป็นสิ่งที่ server กำหนดเองเท่านั้น ห้ามให้ client ยัดค่ามาเขียนทับ
	// (เดิม bind ตรงเข้า model ทำให้ client ส่ง ptd_id ไปทับแถวอื่นได้ และ ptd_order ที่ไม่ส่งมา
	// จะได้ 1 ทุกครั้งจาก GORM default tag — ดูรายละเอียดที่ทำให้ ptd_id 238-241 ชนกันใน migration รอบ 2)
	detail.PtdID = 0
	detail.PtdOrder = 0

	// ตรวจสอบว่า plan มีอยู่จริงก่อน insert
	var plan models.WorkoutPlanTemplate
	if err := config.DB.First(&plan, detail.WptID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผนที่ระบุ กรุณาสร้างแผนใหม่", "plan_not_found": true})
		return
	}
	if ok, msg := helpers.ValidatePlanTemplateDetail(detail, plan.WptDaysPerWeek); !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}

	err := config.DB.Transaction(func(tx *gorm.DB) error {
		var maxOrder int
		if err := tx.Model(&models.PlanTemplateDetail{}).
			Where("wpt_id = ? AND ptd_day_number = ?", detail.WptID, detail.PtdDayNumber).
			Select("COALESCE(MAX(ptd_order), 0)").Scan(&maxOrder).Error; err != nil {
			return err
		}
		detail.PtdOrder = maxOrder + 1
		return tx.Create(&detail).Error
	})
	if err != nil {
		if strings.Contains(err.Error(), "uq_ptd_plan_day_order") {
			c.JSON(http.StatusConflict, gin.H{"error": "ลำดับท่าซ้ำ กรุณาลองใหม่อีกครั้ง"})
			return
		}
		log.Printf("AddPlanDetail: create failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "เพิ่มรายละเอียดแผนไม่สำเร็จ"})
		return
	}
	helpers.LogAdminMutation(c, "create", "plan_template_detail", detail.PtdID, nil, detail)
	c.JSON(http.StatusOK, gin.H{"message": "เพิ่มท่าลงในแผนแม่แบบสำเร็จ", "data": detail})
}

func AddExerciseToSchedule(c *gin.Context) {
	AddPlanDetail(c)
}

// SelectWorkoutPlan - copy ท่าฝึกทั้งหมดจาก plan_template_details → workout_schedules (แทน plan เดิมของ user)
// ดีไซน์: user มีแผน active ได้แค่ 1 แผนเสมอ รวมทุกประเภท (ระบบ+ส่วนตัว) ไม่แยกนับทีละ wpt_id — สลับ
// ไปแผนไหนก็ตาม (ระบบตัวอื่น หรือแผนส่วนตัว) แผนเดิมที่ใช้อยู่หายจาก workout_schedules ทันที ไม่เก็บ
// history ท่าที่เคยแก้ไว้อีกต่อไป
//
// (2026-09-04 รอบ 2: ยุบ member_workout_plans เข้า workout_schedules แล้ว — ข้อมูลระดับแผน (ชื่อ/
// จำนวนวัน/แม่แบบต้นทาง) อยู่ตารางเดียวกับท่าฝึกแล้ว เช็ค "แผน active" จาก workout_schedules.wpt_id
// ของสมาชิกได้ตรงๆ ไม่ต้อง join ตารางแยกอีกต่อไป) "เลือกแผนระบบ" กับ "fork แผนระบบเป็นของตัวเอง"
// (ForkWorkoutPlan) ยังเป็น operation เดียวกันเหมือนเดิม — ใช้ copySystemPlanToSchedule ร่วมกัน
func SelectWorkoutPlan(c *gin.Context) {
	userID, _ := c.Get("user_id")
	var req struct {
		PlanID uint `json:"plan_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "ข้อมูลไม่ครบ"})
		return
	}
	uid := uint(userID.(int))

	var plan models.WorkoutPlanTemplate
	if err := config.DB.First(&plan, req.PlanID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผน"})
		return
	}

	// อยู่ระหว่างใช้แผนนี้เป็นแผน active อยู่แล้ว → ไม่ต้องทำอะไร กันรีเซ็ตท่าที่กำลังแก้ทิ้งเปล่าๆ
	// (ต่างจากปุ่ม "คืนค่าเดิม" ที่ตั้งใจล้างจริงๆ — จุดนี้แค่กดเลือกแผนเดิมซ้ำเฉยๆ ไม่ควรมีผลอะไร)
	// เช็คจาก workout_schedules.wpt_id ตรงๆ (1 สมาชิก 1 แผนเสมอ)
	var activeCount int64
	config.DB.Model(&models.WorkoutSchedule{}).Where("mb_id = ? AND wpt_id = ?", uid, plan.WptID).Count(&activeCount)
	if activeCount > 0 {
		c.JSON(200, gin.H{
			"success":        true,
			"message":        "อยู่ระหว่างใช้แผนนี้อยู่แล้ว",
			"plan_id":        plan.WptID,
			"plan_name":      plan.WptName,
			"days_per_week":  plan.WptDaysPerWeek,
			"already_exists": true,
		})
		return
	}

	// เช็ก V1-V3 ก่อน copy: แผนต้องมีวันฝึกครบ ท่าฝึกครบทุกวันตาม wpt_days_per_week ที่ประกาศไว้
	if err := validateTemplateComplete(plan.WptID, plan.WptDaysPerWeek); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	inserted := 0
	err := config.DB.Transaction(func(tx *gorm.DB) error {
		var txErr error
		inserted, txErr = copySystemPlanToSchedule(tx, uid, plan)
		return txErr
	})
	if err != nil {
		if err == errPlanHasNoDetails {
			c.JSON(http.StatusBadRequest, gin.H{"error": "แผนนี้ยังไม่มีท่าฝึก กรุณาติดต่อผู้ดูแลระบบ"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "เลือกแผนไม่สำเร็จ"})
		return
	}

	c.JSON(200, gin.H{
		"success":       true,
		"message":       "คัดลอกแผนสำเร็จ",
		"plan_id":       plan.WptID,
		"plan_name":     plan.WptName,
		"days_per_week": plan.WptDaysPerWeek,
		"inserted":      inserted,
	})
}

// clearWorkoutSchedules - ลบ workout_schedules ของ user ทั้งหมด (รวมแถวหัวแผน/placeholder ถ้ามี)
// ใช้ตอนสลับแผน — user มีแผน active ได้แค่ 1 แผนเสมอ ไม่เก็บ history แผนเดิมไว้เลย
// weight_training_result ไม่หายตาม เพราะ wtrs.wsch_id เป็น FK แบบ SET NULL ไม่ใช่ CASCADE
// (2026-09-04 รอบ 2: workout_schedules มีคอลัมน์ mb_id ตรงๆ แล้ว หลังยุบ member_workout_plans เข้ามา
// ไม่ต้องอ้อมผ่านตารางแยกอีกต่อไป)
func clearWorkoutSchedules(tx *gorm.DB, uid uint) error {
	return tx.Where("mb_id = ?", uid).Delete(&models.WorkoutSchedule{}).Error
}

// startNewPlan - ล้างแผน+ท่าฝึกเดิมของสมาชิกทั้งหมดทิ้ง แล้วสร้าง "แถวหัวแผน" ใหม่ 1 แถว (wet_id
// เป็น NULL, wsch_day_number = 0) ไว้เก็บชื่อแผน/จำนวนวันต่อสัปดาห์/แม่แบบต้นทาง — จำเป็นต้องมีแถวนี้
// เสมอแม้ยังไม่มีท่าฝึกสักท่า (เช่นตอนเพิ่งสร้างแผนส่วนตัวใหม่) ไม่งั้นไม่มีที่เก็บชื่อแผนเลย
// (workout_schedules ยุบรวม member_workout_plans เข้ามาแล้ว 2026-09-04 รอบ 2 — ดู models/exercise.go)
// คืนค่าแถวหัวแผนนี้ให้ caller ใช้ 1 สมาชิกมีแผนได้แค่ 1 แผนเสมอ จึงไม่ต้องมี "รหัสแผน" แยกจริงๆ
// อีกต่อไป (ตัวตอบ JSON ยังคง key "mwp_id" ไว้เพื่อความเข้ากันได้กับ Flutter เดิม แต่ค่าที่ส่งกลับ
// คือ mb_id ของสมาชิกเอง ไม่ใช่รหัสแถวจริง)
// sourceWptID = nil คือแผนสร้างเอง, ไม่ nil คือ copy จากแม่แบบ
func startNewPlan(tx *gorm.DB, uid uint, name string, daysPerWeek int, sourceWptID *uint) (models.WorkoutSchedule, error) {
	if err := clearWorkoutSchedules(tx, uid); err != nil {
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

var errPlanHasNoDetails = fmt.Errorf("แผนนี้ยังไม่มีท่าฝึก")

// copySystemPlanToSchedule - ก็อปท่าฝึกจาก plan_template_detail ของแม่แบบ wptID ไปเป็น
// workout_schedules ของสมาชิก แทนที่แผนเดิมทั้งหมด (ล้าง + สร้างแถวหัวแผนใหม่ผูก wpt_id ไว้ — ดู
// startNewPlan) ใช้ร่วมกันทั้ง SelectWorkoutPlan / ActivatePlan (สาขา wpt_id) / ResetWorkoutPlan
// (สาขาระบบ) เพราะทั้ง 3 จุดทำสิ่งเดียวกัน — ต้องเรียกใน transaction เสมอ (caller เป็นคนครอบ)
func copySystemPlanToSchedule(tx *gorm.DB, uid uint, plan models.WorkoutPlanTemplate) (int, error) {
	var details []models.PlanTemplateDetail
	if err := tx.Where("wpt_id = ?", plan.WptID).Find(&details).Error; err != nil {
		return 0, err
	}
	if len(details) == 0 {
		return 0, errPlanHasNoDetails
	}

	if _, err := startNewPlan(tx, uid, plan.WptName, int(plan.WptDaysPerWeek), &plan.WptID); err != nil {
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
			WschDayNumber:   toWeekday(int(plan.WptDaysPerWeek), int(d.PtdDayNumber)),
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

// ResetWorkoutPlan - รีเซ็ตแผน: ระบบ=copy ใหม่จากต้นฉบับ, custom=ล้างว่างเปล่า
func ResetWorkoutPlan(c *gin.Context) {
	userID, _ := c.Get("user_id")
	var req struct {
		PlanID *uint `json:"plan_id"`
		MwpID  *uint `json:"mwp_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "ข้อมูลไม่ครบ"})
		return
	}
	uid := uint(userID.(int))

	// แผนส่วนตัว → ล้างท่าออก แต่คงชื่อแผน/จำนวนวัน/แม่แบบต้นทางเดิมไว้ (สร้างแถวหัวแผนใหม่แทน)
	// mwp_id ที่ client ส่งมาไม่ใช่ FK จริงอีกต่อไป (1 สมาชิกมีแผนได้แค่ 1 แผนเสมอ) ใช้ uid จาก JWT
	// ระบุความเป็นเจ้าของแทนตรงๆ
	if req.MwpID != nil {
		var existing models.WorkoutSchedule
		if err := config.DB.Where("mb_id = ?", uid).First(&existing).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผนส่วนตัวนี้"})
			return
		}
		err := config.DB.Transaction(func(tx *gorm.DB) error {
			_, txErr := startNewPlan(tx, uid, existing.WschPlanName, existing.WschDaysPerWeek, existing.WptID)
			return txErr
		})
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "ล้างแผนไม่สำเร็จ"})
			return
		}
		c.JSON(200, gin.H{"success": true, "message": "ล้างแผนส่วนตัวสำเร็จ", "is_system": false})
		return
	}

	if req.PlanID == nil {
		c.JSON(400, gin.H{"error": "ต้องระบุ plan_id หรือ mcp_id"})
		return
	}

	var plan models.WorkoutPlanTemplate
	if err := config.DB.First(&plan, req.PlanID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผน"})
		return
	}

	// เช็ก V1-V3 ก่อนลบของเดิม กันข้อมูลหายเปล่าถ้าแผนแม่แบบตั้งค่าไม่ครบ
	if plan.WptDifficulty > 0 {
		if err := validateTemplateComplete(plan.WptID, plan.WptDaysPerWeek); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		err := config.DB.Transaction(func(tx *gorm.DB) error {
			_, txErr := copySystemPlanToSchedule(tx, uid, plan)
			return txErr
		})
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "รีเซ็ตแผนไม่สำเร็จ"})
			return
		}
		c.JSON(200, gin.H{"success": true, "message": "รีเซ็ตแผนระบบสำเร็จ", "is_system": true})
	} else {
		if err := clearWorkoutSchedules(config.DB, uid); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "ล้างแผนไม่สำเร็จ"})
			return
		}
		c.JSON(200, gin.H{"success": true, "message": "ล้างแผนสำเร็จ", "is_system": false})
	}
}

// GetMemberActivePlan - ดึงแผนที่ใช้งานอยู่จริงของ member
// เลิกใช้ member_profile.mb_active_wpt_id/mb_active_mwp_id แล้ว (DROP ออกจาก DB 2026-09-04)
// อ่านจาก workout_schedules ตรงๆ (1 สมาชิกมีแผนได้แค่ 1 แผนเสมอ — mb_id เป็นเจ้าของแผน หลังยุบ
// member_workout_plans เข้ามาในตารางนี้แล้ว 2026-09-04 รอบ 2) แยกประเภทด้วย wpt_id: NULL = แผน
// สร้างเอง, ไม่ NULL = copy มาจากแม่แบบระบบ — อ่านจากแถวไหนก็ได้ของสมาชิกคนนี้ (แถวหัวแผนหรือแถว
// ท่าฝึกจริง) เพราะข้อมูลระดับแผนถูก denormalize ซ้ำไว้ทุกแถวอยู่แล้ว
func GetMemberActivePlan(c *gin.Context) {
	userID, _ := c.Get("user_id")
	uid := uint(userID.(int))

	var plan models.WorkoutSchedule
	if err := config.DB.Where("mb_id = ?", uid).Order("wsch_id asc").First(&plan).Error; err != nil {
		c.JSON(http.StatusOK, gin.H{"success": true, "has_plan": false})
		return
	}

	// แผนส่วนตัว (สร้างเอง ไม่ได้ copy จากแม่แบบระบบ)
	if plan.WptID == nil {
		// has_exercises: มีท่าฝึกจริงอย่างน้อย 1 ท่าหรือยัง (ตัดแถวหัวแผน wet_id IS NULL ออก)
		// ปุ่มรีเซ็ทฝั่ง frontend ต้องโชว์ตามอันนี้ ไม่ใช่ days_per_week (ค่านั้นตั้งไว้ตอนสร้างแผน
		// ไม่เกี่ยวกับว่ามีท่าฝึกแล้วหรือยัง — ใช้ผิดจุดมาก่อนทำให้ปุ่มโชว์ตลอดเวลา)
		var exerciseCount int64
		config.DB.Model(&models.WorkoutSchedule{}).
			Where("mb_id = ? AND wet_id IS NOT NULL", uid).
			Count(&exerciseCount)
		c.JSON(http.StatusOK, gin.H{
			"success":  true,
			"has_plan": true,
			"data": gin.H{
				"plan_id":       uid,
				"mwp_id":        uid,
				"plan_name":     plan.WschPlanName,
				"days_per_week": plan.WschDaysPerWeek,
				"is_custom":     true,
				"has_exercises": exerciseCount > 0,
			},
		})
		return
	}

	// แผนระบบ (copy มาจากแม่แบบ) — ชื่อดึงสดจากแม่แบบทุกครั้ง (ไม่ cache ฝั่ง backend) กันค้างเมื่อ
	// แอดมินแก้ไขแผนภายหลัง จำนวนวันใช้ค่าจริงจาก workout_schedules ของแผนนี้ (เผื่อ user เพิ่ม/ลบวัน
	// ไปจากแม่แบบ)
	var template models.WorkoutPlanTemplate
	if err := config.DB.First(&template, *plan.WptID).Error; err != nil {
		c.JSON(http.StatusOK, gin.H{"success": true, "has_plan": false})
		return
	}

	var dayNums []int
	config.DB.Model(&models.WorkoutSchedule{}).
		Where("mb_id = ? AND wet_id IS NOT NULL", uid).
		Distinct("wsch_day_number").Pluck("wsch_day_number", &dayNums)
	realDays := len(dayNums)
	if realDays == 0 {
		realDays = template.WptDaysPerWeek // กันกรณีข้อมูลว่างผิดปกติ ไม่ให้โชว์ 0 วัน
	}

	isModified := isSystemPlanModified(config.DB, uid, template.WptID, template.WptDaysPerWeek)

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"has_plan": true,
		"data": gin.H{
			"plan_id":       template.WptID,
			"plan_name":     template.WptName,
			"days_per_week": realDays,
			"is_custom":     false,
			"is_modified":   isModified,
		},
	})
}

// CreatePersonalPlan - สร้างแผนส่วนตัวใหม่ (ตั้งชื่อเอง)
// 1 สมาชิกมีแผนได้แค่ 1 แผนเสมอ (workout_schedules.mb_id เป็นเจ้าของแผนโดยตรงหลังยุบ
// member_workout_plans เข้ามาแล้ว 2026-09-04 รอบ 2) จึงล้างแผนเดิมทิ้งก่อนสร้างแผนใหม่เสมอ ไม่ว่า
// แผนเดิมจะเป็นแผนระบบ (wpt_id) หรือแผนส่วนตัวก็ตาม (startNewPlan จัดการล้าง+สร้างแถวหัวแผนใหม่ให้
// ในทรานแซกชันเดียวกัน) ผลการฝึกเก่า (weight_training_result) ไม่หาย เพราะ wtrs.wsch_id เป็น FK
// แบบ SET NULL ไม่ใช่ CASCADE
func CreatePersonalPlan(c *gin.Context) {
	userID, _ := c.Get("user_id")
	uid := uint(userID.(int))

	var req struct {
		Name string `json:"name"`
	}
	c.ShouldBindJSON(&req)
	name := req.Name
	if name == "" {
		name = "แผนส่วนตัวของฉัน"
	}

	err := config.DB.Transaction(func(tx *gorm.DB) error {
		_, txErr := startNewPlan(tx, uid, name, 7, nil)
		return txErr
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "สร้างแผนไม่สำเร็จ"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "mwp_id": uid, "name": name})
}

// RenamePersonalPlan - แก้ชื่อแผนส่วนตัว (ของตัวเองเท่านั้น) — mwp_id ในพาธเดิมไม่ใช่ FK จริงอีกต่อไป
// (1 สมาชิกมีแผนได้แค่ 1 แผนเสมอ) ใช้ uid จาก JWT ระบุความเป็นเจ้าของแทน อัปเดตชื่อแผนซ้ำทุกแถวของ
// สมาชิกคนนี้ (ข้อมูลระดับแผน denormalize ไว้ทุกแถว)
func RenamePersonalPlan(c *gin.Context) {
	userID, _ := c.Get("user_id")
	uid := uint(userID.(int))

	var req struct {
		Name string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ต้องระบุชื่อแผน"})
		return
	}

	result := config.DB.Model(&models.WorkoutSchedule{}).
		Where("mb_id = ?", uid).
		Update("wsch_plan_name", req.Name)
	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผนนี้หรือไม่มีสิทธิ์แก้ไข"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "message": "แก้ชื่อแผนสำเร็จ"})
}

// DeletePersonalPlan - ลบแผนส่วนตัว (ของตัวเองเท่านั้น) — ลบทุกแถว workout_schedules ของสมาชิกคนนี้
// (ทั้งแถวหัวแผนและท่าฝึกจริง) ไม่ต้องเคลียร์ตัวชี้ active แยกอีกต่อไป (เลิกใช้ mb_active_mwp_id แล้ว
// — GetMemberActivePlan อ่านจาก workout_schedules ตรงๆ)
func DeletePersonalPlan(c *gin.Context) {
	userID, _ := c.Get("user_id")
	uid := uint(userID.(int))

	result := config.DB.Where("mb_id = ?", uid).Delete(&models.WorkoutSchedule{})
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ลบไม่สำเร็จ"})
		return
	}
	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผนนี้หรือไม่มีสิทธิ์ลบ"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "ลบแผนสำเร็จ"})
}

// DeleteSystemPlanCopy - ลบสำเนาแผนระบบที่ user copy มาทิ้งทั้งแผน (ไม่แตะ workout_plan_template/
// plan_template_detail ต้นฉบับที่เป็น master data ร่วมกัน) ไม่ต้องเคลียร์ตัวชี้ active แยกอีกต่อไป
// (เลิกใช้ mb_active_wpt_id แล้ว) — workout_schedules มี wpt_id ตรงๆ แล้วหลังยุบ
// member_workout_plans เข้ามา (2026-09-04 รอบ 2) ลบตรงจากตารางนี้เลย ไม่ต้อง join
func DeleteSystemPlanCopy(c *gin.Context) {
	userID, _ := c.Get("user_id")
	uid := uint(userID.(int))
	wptID := c.Param("wpt_id")

	result := config.DB.Where("mb_id = ? AND wpt_id = ?", uid, wptID).Delete(&models.WorkoutSchedule{})
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ลบไม่สำเร็จ"})
		return
	}
	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผนนี้ในรายการของคุณ"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "ลบแผนออกจากรายการสำเร็จ"})
}

// ActivatePlan - ตั้ง "แผนที่ใช้งานอยู่" (แผนระบบ หรือ แผนส่วนตัว) — จุดเดียวที่กันแผนชนกัน
// ถ้าเป็นแผนระบบที่ยังไม่เคย copy ท่ามาก่อน จะ copy ให้ก่อนเหมือน SelectWorkoutPlan
// (branch wpt_id: ตอนนี้ไม่มีจุดไหนในแอปเรียกแล้ว — SelectWorkoutPlan ทำหน้าที่นี้แทน — คงตรรกะ
// ให้สอดคล้องกับดีไซน์ใหม่ (2026-09-04, มีแผน active ได้แค่ 1 แผนเสมอ) ไว้เผื่อยังมีจุดอื่นเรียกอยู่)
func ActivatePlan(c *gin.Context) {
	userID, _ := c.Get("user_id")
	uid := uint(userID.(int))

	var req struct {
		WptID *uint `json:"wpt_id"`
		MwpID *uint `json:"mwp_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ครบ"})
		return
	}
	if (req.WptID == nil) == (req.MwpID == nil) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ต้องระบุ wpt_id หรือ mwp_id อย่างใดอย่างหนึ่งเท่านั้น"})
		return
	}

	if req.MwpID != nil {
		// เช็คแค่ความเป็นเจ้าของก็พอ — 1 สมาชิกมีแผนได้แค่ 1 แผนเสมอ ถ้ามีแถวของ mb_id นี้อยู่แล้ว
		// แปลว่านี่คือแผน active อยู่แล้วโดยนิยาม ไม่มี "แผนอื่น" ให้เลือกอีกต่อไป (mwp_id ที่ client
		// ส่งมาไม่ใช่ FK จริงแล้ว เก็บไว้เพื่อความเข้ากันได้กับ Flutter เดิมเท่านั้น)
		var count int64
		config.DB.Model(&models.WorkoutSchedule{}).Where("mb_id = ?", uid).Count(&count)
		if count == 0 {
			c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผนนี้"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"success": true, "message": "ตั้งเป็นแผนที่ใช้งานสำเร็จ", "is_custom": true})
		return
	}

	var plan models.WorkoutPlanTemplate
	if err := config.DB.First(&plan, *req.WptID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผน"})
		return
	}

	// อยู่ระหว่างใช้แผนนี้อยู่แล้ว → ไม่ต้องทำอะไร (เหมือน SelectWorkoutPlan)
	var activeCount int64
	config.DB.Model(&models.WorkoutSchedule{}).Where("mb_id = ? AND wpt_id = ?", uid, *req.WptID).Count(&activeCount)
	if activeCount > 0 {
		c.JSON(http.StatusOK, gin.H{"success": true, "message": "อยู่ระหว่างใช้แผนนี้อยู่แล้ว", "is_custom": false})
		return
	}

	// เช็ก V1-V3 ก่อน copy
	if err := validateTemplateComplete(plan.WptID, plan.WptDaysPerWeek); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err := config.DB.Transaction(func(tx *gorm.DB) error {
		_, txErr := copySystemPlanToSchedule(tx, uid, plan)
		return txErr
	})
	if err != nil {
		if err == errPlanHasNoDetails {
			c.JSON(http.StatusBadRequest, gin.H{"error": "แผนนี้ยังไม่มีท่าฝึก กรุณาติดต่อผู้ดูแลระบบ"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "สลับแผนไม่สำเร็จ"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "ตั้งเป็นแผนที่ใช้งานสำเร็จ", "is_custom": false})
}

// ForkWorkoutPlan - คัดลอกแผนระบบ (wpt_id) → แผนส่วนตัวใหม่ที่แก้ไขได้อิสระ
// ใช้ day-mapping เดียวกับ SelectWorkoutPlan/ActivatePlan เป๊ะๆ (toWeekday) กันคัดลอกวันฝึกเพี้ยน
// ไม่มีปุ่มเรียกจาก UI แล้ว (endpoint เก็บไว้เผื่อทำฟีเจอร์ "สร้างแผนจากแม่แบบ" ในอนาคต)
// 1 สมาชิกมีแผนได้แค่ 1 แผนเสมอ — ล้างแผนเดิมทิ้งก่อนเสมอผ่าน startNewPlan เหมือน CreatePersonalPlan
func ForkWorkoutPlan(c *gin.Context) {
	userID, _ := c.Get("user_id")
	uid := uint(userID.(int))

	var req struct {
		WptID uint `json:"wpt_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ต้องระบุ wpt_id"})
		return
	}

	var plan models.WorkoutPlanTemplate
	if err := config.DB.First(&plan, req.WptID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผน"})
		return
	}

	// เช็ก V1-V3 ก่อน copy เหมือนจุดอื่นทุกจุด
	if err := validateTemplateComplete(plan.WptID, plan.WptDaysPerWeek); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var details []models.PlanTemplateDetail
	config.DB.Where("wpt_id = ?", req.WptID).Find(&details)

	newName := plan.WptName + " (ของฉัน)"
	sourceWptID := plan.WptID

	inserted := 0
	err := config.DB.Transaction(func(tx *gorm.DB) error {
		if _, txErr := startNewPlan(tx, uid, newName, int(plan.WptDaysPerWeek), &sourceWptID); txErr != nil {
			return txErr
		}

		for _, d := range details {
			if d.WetID == nil {
				continue
			}
			ws := models.WorkoutSchedule{
				WschPlanName:    newName,
				WschDaysPerWeek: int(plan.WptDaysPerWeek),
				WschDayName:     d.PtdDayName,
				WschDayNumber:   toWeekday(int(plan.WptDaysPerWeek), int(d.PtdDayNumber)),
				WschOrder:       d.PtdOrder,
				WschSets:        d.PtdSets,
				WschReps:        d.PtdReps,
				WschRestSeconds: d.PtdRestSeconds,
				MbID:            uid,
				WptID:           &sourceWptID,
				WetID:           d.WetID,
			}
			if err := tx.Create(&ws).Error; err == nil {
				inserted++
			}
		}
		return nil
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "คัดลอกแผนไม่สำเร็จ"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"message":  "คัดลอกแผนเป็นของตัวเองสำเร็จ",
		"mwp_id":   uid,
		"name":     newName,
		"inserted": inserted,
	})
}

// UpdateWorkoutSchedule - แก้ sets/reps ของท่าที่มีอยู่แล้วในแผนของ user เอง (ค่าระบบตั้งมาเป็นแค่ default เริ่มต้น)
func UpdateWorkoutSchedule(c *gin.Context) {
	userID, _ := c.Get("user_id")
	id := c.Param("id")

	var req struct {
		Sets *int    `json:"sets"`
		Reps *string `json:"reps"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง"})
		return
	}
	if req.Sets == nil && req.Reps == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ต้องระบุ sets หรือ reps"})
		return
	}

	updates := map[string]interface{}{}
	if req.Sets != nil {
		if *req.Sets < 1 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "จำนวนเซ็ตต้องมากกว่า 0"})
			return
		}
		updates["wsch_sets"] = *req.Sets
	}
	if req.Reps != nil && *req.Reps != "" {
		updates["wsch_reps"] = *req.Reps
	}

	// workout_schedules มี mb_id ตรงๆ แล้ว (หลังยุบ member_workout_plans เข้ามา 2026-09-04 รอบ 2)
	// เช็คความเป็นเจ้าของด้วย mb_id ตรงๆ ไม่ต้อง subquery ผ่านตารางแยกอีกต่อไป
	result := config.DB.Model(&models.WorkoutSchedule{}).
		Where("wsch_id = ? AND mb_id = ?", id, userID).
		Updates(updates)
	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบรายการหรือไม่มีสิทธิ์แก้ไข"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "message": "แก้ไขสำเร็จ"})
}

// =========================================================
// 3. จัดการตารางฝึกจริงตามวันที่ (Workout & Cardio Schedules)
// =========================================================

// CreateWorkoutSchedule - เพิ่มท่าออกกำลังกายเข้าแผนของ user (workout_schedules)
// 1 สมาชิกมีแผนได้แค่ 1 แผนเสมอ (mb_id เป็นเจ้าของแผนตรงๆ หลังยุบ member_workout_plans เข้ามาแล้ว
// 2026-09-04 รอบ 2) ไม่ต้อง resolve จาก plan_id/mwp_id ที่ client ส่งมาอีกต่อไป — แค่ต้องมีแผน
// (แถวใดก็ได้ของ mb_id นี้) อยู่ก่อนแล้วเท่านั้น (สร้างผ่าน CreatePersonalPlan/SelectWorkoutPlan ก่อน)
func CreateWorkoutSchedule(c *gin.Context) {
	userID, _ := c.Get("user_id")
	uid := uint(userID.(int))

	var req struct {
		DayNumber int    `json:"day_number"`
		WetID     uint   `json:"wet_id" binding:"required,gt=0"`
		Sets      int    `json:"sets"`
		Reps      string `json:"reps"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ครบ กรุณาตรวจสอบข้อมูลที่ส่งมา"})
		return
	}
	// V1: วันฝึกต้องอยู่ในช่วง 1-7 (จันทร์-อาทิตย์)
	if req.DayNumber < 1 || req.DayNumber > 7 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "วันฝึกต้องอยู่ระหว่าง 1-7"})
		return
	}

	sets := 3
	if req.Sets > 0 {
		sets = req.Sets
	}
	reps := "10"
	if req.Reps != "" {
		reps = req.Reps
	}

	// ครอบทั้งหมดในทรานแซกชันเดียว + ล็อกแถวหัวแผน (FOR UPDATE) กันเพิ่มหลายท่าพร้อมกัน (เช่น
	// เพิ่มทีละหลายท่าจากตะกร้าฝั่ง frontend) ชิงอ่าน wsch_order เดิมพร้อมกันแล้วได้ค่าซ้ำกัน —
	// ตาราง workout_schedules มี UNIQUE KEY (mb_id, wsch_day_number, wsch_order) ถ้าไม่ล็อกจะชน
	// duplicate key แบบสุ่มว่า request ไหนตกรอบ (อาการเดิม: "เพิ่มสำเร็จ 2 ท่า ไม่สำเร็จ 1 ท่า")
	var ws models.WorkoutSchedule
	txErr := config.DB.Transaction(func(tx *gorm.DB) error {
		var header models.WorkoutSchedule
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("mb_id = ?", uid).Order("wsch_id asc").First(&header).Error; err != nil {
			return errPlanNotFound
		}

		// V5: ห้ามเพิ่มท่าเดิมซ้ำในวันเดียวกันของแผนเดียวกัน
		var dupCount int64
		tx.Model(&models.WorkoutSchedule{}).
			Where("mb_id = ? AND wsch_day_number = ? AND wet_id = ?", uid, req.DayNumber, req.WetID).
			Count(&dupCount)
		if dupCount > 0 {
			return errDuplicateExercise
		}

		// ลำดับท่าต่อจากท่าสุดท้ายของวันฝึกนี้ในแผนนี้ (ขอบเขตเดียวกับเช็คซ้ำ V5 ด้านบน)
		var maxOrder int
		tx.Model(&models.WorkoutSchedule{}).
			Where("mb_id = ? AND wsch_day_number = ?", uid, req.DayNumber).
			Select("COALESCE(MAX(wsch_order), 0)").Scan(&maxOrder)

		ws = models.WorkoutSchedule{
			WschPlanName:    header.WschPlanName,
			WschDaysPerWeek: header.WschDaysPerWeek,
			WschDayNumber:   req.DayNumber,
			WschSets:        sets,
			WschReps:        reps,
			WschOrder:       maxOrder + 1,
			MbID:            uid,
			WptID:           header.WptID,
			WetID:           &req.WetID,
		}
		return tx.Create(&ws).Error
	})

	switch txErr {
	case nil:
		c.JSON(http.StatusOK, gin.H{"success": true, "data": ws})
	case errPlanNotFound:
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผนของคุณ กรุณาสร้างแผนก่อน", "plan_not_found": true})
	case errDuplicateExercise:
		c.JSON(http.StatusBadRequest, gin.H{"error": "ท่านี้มีอยู่ในวันนี้แล้ว"})
	default:
		log.Printf("CreateWorkoutSchedule: create failed: %v", txErr)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "เพิ่มท่าไม่สำเร็จ"})
	}
}

// DeleteWorkoutSchedule - ลบท่าออกจากแผนของ user (กัน wet_id IS NOT NULL ไม่ให้ลบแถวหัวแผนโดยไม่ตั้งใจ
// เพราะแถวหัวแผนคือที่เก็บชื่อแผน/จำนวนวัน ถ้าหายไปแผนจะไม่มีชื่อเหลือ)
func DeleteWorkoutSchedule(c *gin.Context) {
	userID, _ := c.Get("user_id")
	id := c.Param("id")
	result := config.DB.Where("wsch_id = ? AND mb_id = ? AND wet_id IS NOT NULL", id, userID).
		Delete(&models.WorkoutSchedule{})
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ลบไม่สำเร็จ"})
		return
	}
	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบรายการ"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "message": "ลบท่าออกจากแผนสำเร็จ"})
}

// GetUserSchedules - ดึงท่าออกกำลังกายจากแผนของ user (รองรับทั้ง plan_id และ mwp_id)
// plan_id/mwp_id ไม่ใช่ FK จริงอีกต่อไป (1 สมาชิกมีแผนได้แค่ 1 แผนเสมอ) แต่ยังรับพารามิเตอร์นี้ไว้
// เพื่อเช็คว่าแผนที่ client คิดว่า active ตรงกับแผนจริงปัจจุบันของสมาชิกหรือไม่ กัน client แสดงผลค้าง
// จากแผนเก่าที่ถูกสลับออกไปแล้ว
func GetUserSchedules(c *gin.Context) {
	userID, _ := c.Get("user_id")
	uid := uint(userID.(int))
	planID := c.Query("plan_id")
	mwpID := c.Query("mwp_id")
	dayNumber := c.Query("day_number")

	if planID == "" && mwpID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "ต้องระบุ plan_id หรือ mwp_id"})
		return
	}

	var header models.WorkoutSchedule
	if err := config.DB.Where("mb_id = ?", uid).Order("wsch_id asc").First(&header).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "plan_not_found": true, "message": "ไม่พบแผนของคุณ"})
		return
	}
	if mwpID != "" {
		if header.WptID != nil {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "plan_not_found": true, "message": "ไม่พบแผนส่วนตัวนี้"})
			return
		}
	} else {
		if header.WptID == nil || strconv.FormatUint(uint64(*header.WptID), 10) != planID {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "plan_not_found": true, "message": "ไม่พบแผนนี้ในระบบ"})
			return
		}
	}

	query := config.DB.Preload("WeightExercise").Where("mb_id = ? AND wet_id IS NOT NULL", uid)
	if dayNumber != "" {
		query = query.Where("wsch_day_number = ?", dayNumber)
	}

	var schedules []models.WorkoutSchedule
	// เรียงตาม wsch_order ("ลำดับท่าในวันนั้น" ตาม Datadic) — เดิมไม่มี .Order() เลย ค่าที่บันทึกไว้
	// เลยไม่เคยถูกใช้จริง ต่อท้ายด้วย wsch_id กันแถวเก่าที่ค่า order ชนกัน (เช่นค่า default 1 เดิม)
	// แสดงลำดับไม่นิ่งสลับไปมา
	if err := query.Order("wsch_order asc, wsch_id asc").Find(&schedules).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": "ดึงข้อมูลล้มเหลว"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "data": schedules})
}

// =========================================================
// 4. บันทึกผลการออกกำลังกายจริง (Weight & Cardio)
// =========================================================

// WeightSessionSetInput - 1 เซตที่บันทึกจริงในเซสชัน (ดู weight_training_exercise_view.dart
// _completedSets) — ActiveSeconds มาจาก _activeSetSeconds ต่อเซตจริง ไม่ใช่ค่าเฉลี่ยทั้งเซสชัน
type WeightSessionSetInput struct {
	WtrsSetNo     int     `json:"wtrs_set_no" binding:"required,gt=0"`
	WtrsReps      int     `json:"wtrs_reps" binding:"required,gt=0"`
	WtrsWeight    float64 `json:"wtrs_weight"`
	ActiveSeconds int     `json:"active_seconds"`
}

// WeightSessionRequest - บันทึกผลเวทเทรนนิ่งทั้งเซสชันในคำขอเดียว (แทนที่ของเดิมที่ยิงทีละเซต
// แยกกัน 2026-09-08 — เปลี่ยนเพราะสูตร Smart Auto Calorie คำนวณระดับเซสชัน ไม่ใช่ระดับเซตเดี่ยว
// ต้องรู้ทุกเซต + เวลารวมพร้อมกันครั้งเดียวถึงจะหาค่า MET ที่แท้จริงได้ ผลพลอยได้: กันเน็ตหลุด
// กลางทางแล้วได้ข้อมูลครึ่งๆ เหมือนของเดิมที่ยิงเป็น loop)
type WeightSessionRequest struct {
	Date                 string                  `json:"date" binding:"required"`
	WschID               *uint                   `json:"wsch_id"`
	WetID                uint                    `json:"wet_id" binding:"required,gt=0"`
	TotalDurationSeconds int                     `json:"total_duration_seconds" binding:"required,gt=0"`
	Sets                 []WeightSessionSetInput `json:"sets" binding:"required,min=1,dive"`
}

// CardioResultRequest - บันทึกผล Cardio (ไม่ต้องมี schedule)
type CardioResultRequest struct {
	Date          string  `json:"date" binding:"required"`
	CdoID         uint    `json:"cdo_id" binding:"required"`
	CdorsDuration int     `json:"cdors_duration" binding:"required,gt=0"`
	CdorsDistance float64 `json:"cdors_distance"`
}

// getBestOneRepMax ดึง Estimated 1RM ที่ดีที่สุดของสมาชิกคนนี้ในท่านี้ จากประวัติที่มีอยู่แล้ว
// เท่านั้น (query ก่อนบันทึกเซสชันใหม่เสมอ จึงไม่รวมเซตที่กำลังจะบันทึก) — ใช้ร่วมกันระหว่าง
// GetBest1RM (แสดงผลอย่างเดียว) และ SaveWorkoutResult (หา %1RM ไปคำนวณ kLoad ของ Smart Auto
// Calorie, ดู services.CalculateWeightTrainingCalories) แยกออกมาเพื่อไม่ให้ 2 endpoint สูตรตัน
func getBestOneRepMax(mbID, wetID uint) (best1RM, bestWeight float64, bestReps int, bestDate string, hasData bool) {
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
	best1RM = math.Round(row.BestWeight*(1+float64(row.BestReps)/30.0)*100) / 100
	return best1RM, row.BestWeight, row.BestReps, row.Date, true
}

// SaveWorkoutResult บันทึกผลเวทเทรนนิ่งทั้งเซสชัน (Smart Auto Calorie — ออกแบบ 2026-09-08)
// แทนที่ระบบเดิมที่ผู้ใช้เลือกความหนัก 3 ระดับเอง (wtrs_intensity_level) ซึ่งตรวจแล้วพบว่าไม่เคย
// ทำงานจริง — mobile ไม่เคยส่งค่านี้ขึ้น API เลย ทุกแถวเก่าใน DB จึง fallback เป็น 1 (เบา) หมด
// ต้องรับทั้งเซสชันครั้งเดียว (ไม่ใช่ยิงทีละเซตเหมือนเดิม) เพราะ MET ของโมเดลใหม่คำนวณระดับ
// เซสชัน (ถ่วงน้ำหนัก+ความหนาแน่นตามจำนวนเซตรวม/เวลารวม) ต้องรู้ทุกเซตพร้อมกันถึงจะหาค่าได้
func SaveWorkoutResult(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "ไม่พบข้อมูลผู้ใช้งาน"})
		return
	}
	uid := uint(userID.(int))

	var req WeightSessionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง กรุณาตรวจสอบข้อมูลที่ส่งมา"})
		return
	}

	var exercise models.WeightExercise
	if err := config.DB.First(&exercise, req.WetID).Error; err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ไม่พบท่าฝึกนี้ในระบบ"})
		return
	}

	var bodyStat models.MemberBodyStat
	bodyWeight := 70.0 // default fallback
	if err := config.DB.Where("mb_id = ?", uid).Order("mbs_recorded_date desc").First(&bodyStat).Error; err == nil {
		bodyWeight = bodyStat.MbsWeight
	}

	// %1RM เทียบกับประวัติเดิม (ไม่รวมเซสชันนี้) → kLoad — แทนที่การให้ผู้ใช้เลือกความหนักเอง
	oneRepMax, _, _, _, _ := getBestOneRepMax(uid, req.WetID)

	setLogs := make([]services.SetLog, 0, len(req.Sets))
	for _, s := range req.Sets {
		setLogs = append(setLogs, services.SetLog{
			BaseMET:  exercise.WetBaseMet,
			WeightKg: s.WtrsWeight,
			Reps:     s.WtrsReps,
		})
	}
	calc := services.CalculateWeightTrainingCalories(bodyWeight, req.TotalDurationSeconds, oneRepMax, setLogs)

	// เลขเซ็ทนับต่อเนื่องทั้งวันจาก DB จริง ไม่ใช้เลขเซ็ทจาก client ตรงๆ — client (หน้าจอฝึก) นับ
	// เซ็ทแบบรีเซ็ตเป็น 1 ใหม่ทุกครั้งที่เปิดหน้าจอ (ทุก "รอบ") ถ้าฝึกท่าเดียวกันซ้ำวันเดียวกัน
	// หลายรอบ (เช่น รอบเช้า 1 เซ็ท รอบเย็นอีก 3 เซ็ท) จะได้เลขชนกันเป็น 1,1,2,3 ในประวัติ ดูเหมือน
	// ข้อมูลซ้ำ/ผิดพลาด ทั้งที่จริงบันทึกครบ — คำนวณจากจำนวนแถวที่มีอยู่แล้วของ (สมาชิก, ท่านี้,
	// วันนี้) +1 แทน ได้เลขต่อเนื่อง 1,2,3,4 เสมอไม่ว่าจะแบ่งกี่รอบ
	today := time.Now().Format("2006-01-02")
	var existingSetCount int64
	config.DB.Model(&models.WeightTrainingResult{}).
		Where("mb_id = ? AND wet_id = ? AND wtrs_date = ?", uid, req.WetID, today).
		Count(&existingSetCount)

	rows := make([]models.WeightTrainingResult, 0, len(req.Sets))
	nextSetNo := int(existingSetCount) + 1
	sessionBest1RM := 0.0
	for _, s := range req.Sets {
		if s.WtrsReps <= 0 {
			continue // เซตไม่สมบูรณ์ ข้าม — เหมือนตัวกรองใน CalculateWeightTrainingCalories
		}
		activeSeconds := s.ActiveSeconds
		duration := req.TotalDurationSeconds
		rows = append(rows, models.WeightTrainingResult{
			WtrsDate:           today,
			WtrsSetNo:          nextSetNo,
			WtrsReps:           s.WtrsReps,
			WtrsWeight:         s.WtrsWeight,
			WtrsActiveSeconds:  &activeSeconds,
			WtrsDuration:       &duration,
			WtrsIntensityLevel: calc.IntensityLevel,
			// SessionKcal หารเท่ากันทุกเซต — analytics_controller.go SUM(wtrs_calories) ยังถูกต้อง
			// เป๊ะโดยไม่ต้องแก้ (ผลรวมของเซตทั้งหมด = SessionKcal พอดี)
			WtrsCalories: calc.CaloriesPerSet,
			MbID:         uid,
			WetID:        &req.WetID,
			WschID:       req.WschID,
		})
		nextSetNo++

		// Estimated 1RM = weight × (1 + reps/30) — คำนวณแสดงผลอย่างเดียว ไม่บันทึก DB (กฎเหล็กข้อ 8.2)
		if s.WtrsWeight > 0 {
			est := math.Round(s.WtrsWeight*(1+float64(s.WtrsReps)/30.0)*100) / 100
			if est > sessionBest1RM {
				sessionBest1RM = est
			}
		}
	}

	if len(rows) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ไม่มีเซตที่บันทึกได้ (reps ต้องมากกว่า 0)"})
		return
	}

	if err := config.DB.Create(&rows).Error; err != nil {
		log.Printf("SaveWorkoutResult: create failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "บันทึกผลไม่สำเร็จ กรุณาลองใหม่"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":         "บันทึกผลการฝึกสำเร็จ",
		"data":            rows,
		"calories_burned": calc.TotalCalories,
		"estimated_1rm":   sessionBest1RM,
		// รายละเอียดที่มาของตัวเลข — ให้ debug/ตรวจสอบได้ว่าทำไมได้ค่านี้ ไม่ใช่กล่องดำ
		"calculation": gin.H{
			"session_base_met":  calc.SessionBaseMET,
			"k_load":            calc.KLoad,
			"k_density":         calc.KDensity,
			"final_met":         calc.FinalMET,
			"effective_minutes": calc.EffectiveMinutes,
			"intensity_level":   calc.IntensityLevel,
			"one_rep_max_used":  oneRepMax,
			"body_weight_kg":    bodyWeight,
		},
	})
}

// GetBest1RM - ดึง estimated 1RM สูงสุดของ user สำหรับท่าฝึกที่ระบุ
func GetBest1RM(c *gin.Context) {
	userID, _ := c.Get("user_id")
	uid := uint(userID.(int))
	wetIDStr := c.Param("wet_id")
	wetID64, err := strconv.ParseUint(wetIDStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "wet_id ไม่ถูกต้อง"})
		return
	}

	best1RM, bestWeight, bestReps, date, hasData := getBestOneRepMax(uid, uint(wetID64))
	if !hasData {
		c.JSON(http.StatusOK, gin.H{
			"wet_id":   wetIDStr,
			"best_1rm": 0,
			"has_data": false,
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"wet_id":      wetIDStr,
		"best_1rm":    best1RM,
		"best_weight": bestWeight,
		"best_reps":   bestReps,
		"date":        date,
		"has_data":    true,
	})
}

func SaveCardioResult(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "ไม่พบข้อมูลผู้ใช้งาน"})
		return
	}
	uid := uint(userID.(int))

	var req CardioResultRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง กรุณาตรวจสอบข้อมูลที่ส่งมา"})
		return
	}

	var cardio models.Cardio
	if err := config.DB.First(&cardio, req.CdoID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบกิจกรรมคาร์ดิโอนี้"})
		return
	}

	// ตรวจช่วงค่าหลังรู้แล้วว่ากิจกรรมนี้ต้องกรอกระยะทางไหม (cardio.CdoHasDistance) — เพดานตรงกับ
	// คอลัมน์จริง cdors_duration (SMALLINT UNSIGNED) / cdors_distance (DECIMAL(5,2)) กัน DB error
	if ok, msg := helpers.ValidateCardioResult(req.CdorsDuration, req.CdorsDistance, cardio.CdoHasDistance == 1); !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}

	var bodyStat models.MemberBodyStat
	bodyWeight := 70.0
	if err := config.DB.Where("mb_id = ?", uid).Order("mbs_recorded_date desc").First(&bodyStat).Error; err == nil {
		bodyWeight = bodyStat.MbsWeight
	}

	// NET calories: หัก 1 MET (=ค่าเผาผลาญขณะพักนิ่ง/resting metabolic) ออกก่อนเก็บ DB — เหตุผลผลเดียวกับ
	// เวทเทรนนิ่ง (ดู SaveWorkoutResult ด้านบน) นิยาม 1 MET ไม่ได้ขึ้นกับชนิดกิจกรรม กันนับซ้ำตอนเอาไปรวม
	// กับ Baseline (BMR×1.2) เป็น Total Daily Energy Output ที่ analytics_controller.go SUM(cdors_calories)
	// ตรงๆ เข้า exerciseBurn เหมือนกับฝั่งเวท (2026-08-22)
	// clamp กัน METs ติดลบ/ศูนย์ ถ้าวันหน้ามีกิจกรรมคาร์ดิโอ METs ≤ 1.0 ถูกเพิ่มเข้าระบบ (ปัจจุบัน
	// คาร์ดิโอทุกท่าใน DB METs ต่ำสุด 7.0 ไม่ชนขอบนี้ แต่กันไว้ก่อนเผื่ออนาคต)
	netMets := cardio.CdoMets - 1
	if netMets < 0 {
		netMets = 0
	}
	// Deprecated (2026-08-22): สูตรเดิม `cardio.CdoMets * bodyWeight * เวลา` (ไม่หัก 1 MET) นับพลังงาน
	// พื้นฐานซ้ำกับ Baseline ใน TDEO เหมือนที่เจอฝั่งเวทเทรนนิ่ง — แถวข้อมูลเก่าก่อนวันนี้คำนวณด้วยสูตร
	// gross แบบเดิม ไม่ตรงกับที่นี่ ถ้าต้องเทียบย้อนหลังให้เช็ควันที่ก่อนแก้
	burnedCalories := netMets * bodyWeight * (float64(req.CdorsDuration) / 60.0)

	// cdors_distance เก็บ NULL เมื่อกิจกรรมนั้นไม่ได้วัดระยะทาง (cdo_has_distance = 0) — "ไม่มี
	// ระยะทาง" กับ "ระยะทาง 0 กม." คนละความหมาย DEFAULT 0.00 เดิมถูกถอดออกจาก DB แล้ว
	// (migrations/2026-09-06_align_defaults_and_nullability.sql)
	var distance *float64
	if cardio.CdoHasDistance == 1 {
		d := req.CdorsDistance
		distance = &d
	}

	result := models.CardioResult{
		CdorsDate:     req.Date,
		CdorsDuration: req.CdorsDuration,
		CdorsDistance: distance,
		CdorsCalories: burnedCalories,
		MbID:          uid,
		CdoID:         &req.CdoID,
	}

	if err := config.DB.Create(&result).Error; err != nil {
		log.Printf("SaveResult: create failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "บันทึกผลไม่สำเร็จ กรุณาลองใหม่"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message":         "บันทึกผลคาร์ดิโอสำเร็จ",
		"data":            result,
		"calories_burned": burnedCalories,
		"calculation": gin.H{
			"mets":         cardio.CdoMets,
			"weight_kg":    bodyWeight,
			"duration_min": req.CdorsDuration,
		},
	})
}

// =========================================================
// 5. Get/Update/Delete (Plans, Details, Results)
// =========================================================
func GetWorkoutPlans(c *gin.Context) {
	var plans []models.WorkoutPlanTemplate

	// ดึงเฉพาะแผนระบบ (wpt_difficulty > 0) ไม่รวมแผนส่วนตัวของ member
	if err := config.DB.Where("wpt_difficulty > 0").Order("wpt_days_per_week asc").Find(&plans).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": "ดึงข้อมูลไม่สำเร็จ",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true, // ✅ เพิ่มบรรทัดนี้
		"data":    plans,
	})
}

func GetPlanDetails(c *gin.Context) {
	planID := c.Query("plan_id") // รับค่าจาก ?plan_id=...
	var details []models.PlanTemplateDetail

	// ✅ เพิ่ม .Preload("WeightExercise") และ .Where ถ้ามีการส่ง plan_id มา
	query := config.DB.Preload("WeightExercise")

	if planID != "" {
		query = query.Where("wpt_id = ?", planID)
	}

	if err := query.Find(&details).Error; err != nil {
		log.Printf("GetPlanDetails: query failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ดึงข้อมูลล้มเหลว กรุณาลองใหม่"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "data": details})
}

func UpdateWorkoutPlan(c *gin.Context) {
	id := c.Param("id")
	var plan models.WorkoutPlanTemplate
	if err := config.DB.First(&plan, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผน"})
		return
	}
	before := plan // snapshot ก่อนแก้ ไว้ให้ audit log (S-9 old_value)

	if v := c.PostForm("wpt_name"); v != "" {
		plan.WptName = v
	}
	if v := c.PostForm("wpt_days_per_week"); v != "" {
		d, _ := strconv.Atoi(v)
		plan.WptDaysPerWeek = d
	}
	if v := c.PostForm("wpt_description"); v != "" {
		plan.WptDescription = v
	}
	if v := c.PostForm("wpt_difficulty"); v != "" {
		d, _ := strconv.Atoi(v)
		plan.WptDifficulty = int8(d)
	}

	if file, err := c.FormFile("wpt_image"); err == nil {
		if verr := helpers.ValidateImageUpload(file); verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		uploadDir := "./uploads/workout_plans"
		os.MkdirAll(uploadDir, os.ModePerm)
		newName := fmt.Sprintf("%d%s", time.Now().UnixNano(), filepath.Ext(file.Filename))
		if err := c.SaveUploadedFile(file, filepath.Join(uploadDir, newName)); err == nil {
			if plan.WptImage != "" {
				os.Remove("./" + plan.WptImage)
			}
			plan.WptImage = "uploads/workout_plans/" + newName
		}
	}

	if ok, msg := helpers.ValidateWorkoutPlanTemplate(plan.WptDaysPerWeek, int(plan.WptDifficulty)); !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}

	if err := config.DB.Save(&plan).Error; err != nil {
		if helpers.IsDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "มีแผนชื่อนี้อยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "แก้ไขแผนไม่สำเร็จ"})
		return
	}
	helpers.LogAdminMutation(c, "update", "workout_plan_template", plan.WptID, before, plan)
	c.JSON(http.StatusOK, gin.H{"message": "แก้ไขแผนสำเร็จ", "data": plan})
}

func DeleteWorkoutPlan(c *gin.Context) {
	id := c.Param("id")

	// เช็คการใช้งานจริงจาก member_workout_plans (นับสมาชิกที่เคย/กำลังใช้แผนนี้) แทนการเช็ค
	// plan_template_detail ซึ่งมีแทบทุกแผนอยู่แล้วและ cascade ลบเองอัตโนมัติผ่าน fk_ptd_plan
	// (ON DELETE CASCADE) — เช็คแบบเดิมเลยบล็อกการลบแผนทุกแผนที่มีท่าฝึกโดยไม่จำเป็น
	// นับจาก workout_schedules.wpt_id ตรงๆ (หลังยุบ member_workout_plans เข้ามาแล้ว 2026-09-04 รอบ 2)
	var memberCount int64
	config.DB.Model(&models.WorkoutSchedule{}).
		Where("wpt_id = ?", id).
		Distinct("mb_id").
		Count(&memberCount)
	if memberCount > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("ไม่สามารถลบแผนนี้ได้ เนื่องจากมีสมาชิก %d คนกำลังใช้งานแผนนี้อยู่", memberCount)})
		return
	}

	var before models.WorkoutPlanTemplate
	config.DB.First(&before, id) // best-effort snapshot ก่อนลบ ไว้ให้ audit log

	// plan_template_detail ของแผนนี้ถูกลบอัตโนมัติผ่าน fk_ptd_plan (ON DELETE CASCADE)
	config.DB.Where("wpt_id = ?", id).Delete(&models.WorkoutPlanTemplate{})
	helpers.LogAdminMutation(c, "delete", "workout_plan_template", id, before, nil)
	c.JSON(http.StatusOK, gin.H{"message": "ลบแผนสำเร็จ"})
}

// planTemplateDetailInput คือ DTO whitelist field ที่แก้ไขได้จริงของ plan_template_detail
// (เดิม UpdatePlanDetail bind ตรงเป็น map[string]interface{} แล้วยิง GORM Updates() ด้วย key
// จาก client ตรงๆ — client ส่ง key เป็นชื่อคอลัมน์ใดก็ได้ในตารางนี้ก็แก้ได้หมด รวมถึง wpt_id/wet_id
// ที่ไม่ควรย้ายข้ามแผนแบบเงียบๆ และไม่มีการตรวจช่วงค่าตามสเปกข้อ 3.8 เลย)
type planTemplateDetailInput struct {
	PtdDayNumber   *int    `json:"ptd_day_number"`
	PtdDayName     *string `json:"ptd_day_name"`
	PtdSets        *int    `json:"ptd_sets"`
	PtdReps        *string `json:"ptd_reps"`
	PtdRestSeconds *int    `json:"ptd_rest_seconds"`
	PtdOrder       *int    `json:"ptd_order"`
	WetID          *uint   `json:"wet_id"`
}

func UpdatePlanDetail(c *gin.Context) {
	id := c.Param("id")
	var detail models.PlanTemplateDetail
	if err := config.DB.First(&detail, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบรายละเอียดแผนนี้"})
		return
	}
	before := detail // snapshot ก่อนแก้ ไว้ให้ audit log (S-9 old_value)

	var input planTemplateDetailInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง"})
		return
	}

	if input.PtdDayNumber != nil {
		detail.PtdDayNumber = *input.PtdDayNumber
	}
	if input.PtdDayName != nil {
		detail.PtdDayName = *input.PtdDayName
	}
	if input.PtdSets != nil {
		detail.PtdSets = *input.PtdSets
	}
	if input.PtdReps != nil {
		detail.PtdReps = *input.PtdReps
	}
	if input.PtdRestSeconds != nil {
		detail.PtdRestSeconds = *input.PtdRestSeconds
	}
	if input.PtdOrder != nil {
		detail.PtdOrder = *input.PtdOrder
	}
	if input.WetID != nil {
		detail.WetID = input.WetID
	}

	var plan models.WorkoutPlanTemplate
	config.DB.First(&plan, detail.WptID)
	if ok, msg := helpers.ValidatePlanTemplateDetail(detail, plan.WptDaysPerWeek); !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}

	if err := config.DB.Save(&detail).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "แก้ไขรายละเอียดไม่สำเร็จ"})
		return
	}
	helpers.LogAdminMutation(c, "update", "plan_template_detail", detail.PtdID, before, detail)
	c.JSON(http.StatusOK, gin.H{"message": "แก้ไขรายละเอียดสำเร็จ", "data": detail})
}

func DeletePlanDetail(c *gin.Context) {
	id := c.Param("id")
	var before models.PlanTemplateDetail
	config.DB.First(&before, id) // best-effort snapshot ก่อนลบ ไว้ให้ audit log
	config.DB.Where("ptd_id = ?", id).Delete(&models.PlanTemplateDetail{})
	helpers.LogAdminMutation(c, "delete", "plan_template_detail", id, before, nil)
	c.JSON(http.StatusOK, gin.H{"message": "ลบรายละเอียดสำเร็จ"})
}

func GetUserWorkoutResults(c *gin.Context) {
	userID, _ := c.Get("user_id")
	date := c.Query("date")
	wetID := c.Query("wet_id")
	var results []models.WeightTrainingResult
	query := config.DB.Preload("WeightExercise").Where("mb_id = ?", userID)
	if date != "" {
		query = query.Where("wtrs_date = ?", date)
	}
	if wetID != "" {
		query = query.Where("wet_id = ?", wetID)
	}
	query.Order("wtrs_date desc, wtrs_set_no asc").Find(&results)
	c.JSON(http.StatusOK, gin.H{"data": results})
}

func GetUserCardioResults(c *gin.Context) {
	userID, _ := c.Get("user_id")
	date := c.Query("date")
	var results []models.CardioResult
	query := config.DB.Preload("CardioType").Where("mb_id = ?", userID)
	if date != "" {
		query = query.Where("cdors_date = ?", date)
	}
	query.Order("cdors_id desc").Find(&results)
	c.JSON(http.StatusOK, gin.H{"message": "ดึงข้อมูลสำเร็จ", "data": results})
}

func DeleteWorkoutResult(c *gin.Context) {
	userID, _ := c.Get("user_id")
	id := c.Param("id")

	result := config.DB.Where("wtrs_id = ? AND mb_id = ?", id, userID).Delete(&models.WeightTrainingResult{})
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ลบไม่สำเร็จ"})
		return
	}
	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบรายการหรือไม่มีสิทธิ์ลบ"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "ลบผลการฝึกสำเร็จ"})
}

func DeleteCardioResult(c *gin.Context) {
	userID, _ := c.Get("user_id")
	id := c.Param("id")

	result := config.DB.Where("cdors_id = ? AND mb_id = ?", id, userID).Delete(&models.CardioResult{})
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ลบไม่สำเร็จ"})
		return
	}
	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบรายการหรือไม่มีสิทธิ์ลบ"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "ลบผลคาร์ดิโอสำเร็จ"})
}

// GetMemberPlanDetails - ดึงรายละเอียดท่าฝึกในแผนที่เลือกว่ามีท่าอะไรบ้าง
func GetMemberPlanDetails(c *gin.Context) {
	planID := c.Query("plan_id")
	var details []models.PlanTemplateDetail

	// ตรวจสอบว่า plan มีอยู่จริงก่อน
	var plan models.WorkoutPlanTemplate
	if err := config.DB.First(&plan, planID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"success":        false,
			"plan_not_found": true,
			"message":        "ไม่พบแผนนี้ในระบบ กรุณาเลือกหรือสร้างแผนใหม่",
		})
		return
	}

	if err := config.DB.Preload("WeightExercise").Where("wpt_id = ?", planID).Find(&details).Error; err != nil {
		log.Printf("GetMemberPlanDetails: query failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": "ดึงข้อมูลล้มเหลว กรุณาลองใหม่",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    details,
	})
}
