package controllers

import (
	"fmt"
	"food_and_fit_api/config"
	"food_and_fit_api/helpers"
	"food_and_fit_api/models"
	"log"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// isSystemPlanModified เทียบท่าฝึกจริงของ user (workout_schedules) กับแม่แบบระบบ (plan_template_detail)
// ทีละท่า/วัน/เซ็ต/ครั้ง — ไม่ใช่แค่นับจำนวนแถวเหมือนเดิม เพราะนับจำนวนอย่างเดียวพลาด 2 เคส:
// 1) แก้ sets/reps ของท่าเดิมเฉยๆ (UpdateWorkoutSchedule ไม่เพิ่ม/ลดแถว นับจำนวนไม่เปลี่ยน)
// 2) ลบท่า A แล้วเพิ่มท่า B แทนวันเดียวกัน (จำนวนรวมเท่าเดิมพอดี นับจำนวนตรวจไม่เจอว่าสลับท่าไปแล้ว)
func isSystemPlanModified(db *gorm.DB, uid uint, wptID uint) bool {
	type scheduleRow struct {
		DayNumber int
		WetID     uint
		Sets      int
		Reps      string
	}

	var actual []scheduleRow
	db.Model(&models.WorkoutSchedule{}).
		Select("wsch_day_number as day_number, wet_id, wsch_sets as sets, wsch_reps as reps").
		Where("mb_id = ? AND wpt_id = ?", uid, wptID).
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
	if err := config.DB.Create(&detail).Error; err != nil {
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

	// ถ้า user มีแผนนี้อยู่แล้ว (อาจแก้ไขแล้ว) → ใช้อันเดิม ไม่ต้อง copy ทับ
	var existingCount int64
	config.DB.Model(&models.WorkoutSchedule{}).
		Where("mb_id = ? AND wpt_id = ?", uid, req.PlanID).
		Count(&existingCount)

	if existingCount > 0 {
		setActiveSystemPlan(uid, plan.WptID)
		c.JSON(200, gin.H{
			"success":        true,
			"message":        "ใช้แผนที่มีอยู่แล้ว",
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

	// ยังไม่มีแผนนี้ → copy จาก plan_template_details
	var details []models.PlanTemplateDetail
	config.DB.Where("wpt_id = ?", req.PlanID).Find(&details)

	// กันเลือกแผนที่แอดมินสร้างไว้แต่ยังไม่ได้ใส่ท่าฝึก
	if len(details) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "แผนนี้ยังไม่มีท่าฝึก กรุณาติดต่อผู้ดูแลระบบ"})
		return
	}

	inserted := 0
	today := time.Now().Format("2006-01-02")
	for _, d := range details {
		if d.WetID == nil {
			continue
		}
		ws := models.WorkoutSchedule{
			MbID:            uid,
			WschDate:        today,
			WschDayName:     d.PtdDayName,
			WschDayNumber:   toWeekday(int(plan.WptDaysPerWeek), int(d.PtdDayNumber)),
			WetID:           *d.WetID,
			WschSets:        d.PtdSets,
			WschRestSeconds: d.PtdRestSeconds,
			WschReps:        d.PtdReps,
			WschOrder:       d.PtdOrder,
			WptID:           &req.PlanID,
		}
		if err := config.DB.Create(&ws).Error; err == nil {
			inserted++
		}
	}

	setActiveSystemPlan(uid, plan.WptID)
	c.JSON(200, gin.H{
		"success":       true,
		"message":       "คัดลอกแผนสำเร็จ",
		"plan_id":       plan.WptID,
		"plan_name":     plan.WptName,
		"days_per_week": plan.WptDaysPerWeek,
		"inserted":      inserted,
	})
}

// setActiveSystemPlan / setActivePersonalPlan - ตั้ง "แผนที่ใช้งานอยู่" บน member_profile
// มีค่าได้แค่ 1 ใน 2 (wpt/mwp) เสมอ — เป็นตัวเดียวที่ GetMemberActivePlan และหน้าแผนของฉันเชื่อถือ
// แทนการเดาจากแถว workout_schedules ล่าสุดแบบเดิม (ซึ่งพังเมื่อมีหลายแผนปนกัน)
func setActiveSystemPlan(uid uint, wptID uint) {
	config.DB.Model(&models.Member{}).Where("mb_id = ?", uid).
		Updates(map[string]interface{}{"mb_active_wpt_id": wptID, "mb_active_mwp_id": nil})
}

func setActivePersonalPlan(uid uint, mwpID uint) {
	config.DB.Model(&models.Member{}).Where("mb_id = ?", uid).
		Updates(map[string]interface{}{"mb_active_mwp_id": mwpID, "mb_active_wpt_id": nil})
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

	// แผนส่วนตัว → ล้างท่าออกเฉพาะแผนนี้ (ของ user เองเท่านั้น — แต่ละแผนแยกกันด้วย mwp_id)
	if req.MwpID != nil {
		var plan models.MemberWorkoutPlan
		if err := config.DB.Where("mwp_id = ? AND mb_id = ?", *req.MwpID, uid).First(&plan).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผนส่วนตัวนี้"})
			return
		}
		config.DB.Where("mb_id = ? AND mwp_id = ?", uid, *req.MwpID).Delete(&models.WorkoutSchedule{})
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
	}

	config.DB.Where("mb_id = ? AND wpt_id = ?", uid, *req.PlanID).Delete(&models.WorkoutSchedule{})

	if plan.WptDifficulty > 0 {
		var details []models.PlanTemplateDetail
		config.DB.Where("wpt_id = ?", req.PlanID).Find(&details)
		today := time.Now().Format("2006-01-02")
		for _, d := range details {
			if d.WetID == nil {
				continue
			}
			ws := models.WorkoutSchedule{
				MbID:            uid,
				WschDate:        today,
				WschDayName:     d.PtdDayName,
				WschDayNumber:   toWeekday(int(plan.WptDaysPerWeek), int(d.PtdDayNumber)),
				WetID:           *d.WetID,
				WschSets:        d.PtdSets,
				WschRestSeconds: d.PtdRestSeconds,
				WschReps:        d.PtdReps,
				WschOrder:       d.PtdOrder,
				WptID:           req.PlanID,
			}
			config.DB.Create(&ws)
		}
		c.JSON(200, gin.H{"success": true, "message": "รีเซ็ตแผนระบบสำเร็จ", "is_system": true})
	} else {
		c.JSON(200, gin.H{"success": true, "message": "ล้างแผนสำเร็จ", "is_system": false})
	}
}

// GetMemberActivePlan - ดึงแผนที่ใช้งานอยู่จริงของ member จาก member_profile.mb_active_wpt_id/mb_active_mwp_id
// (เดิมเดาจากแถว workout_schedules ล่าสุด ซึ่งพังเมื่อ user มีหลายแผนปนกันในตาราง)
func GetMemberActivePlan(c *gin.Context) {
	userID, _ := c.Get("user_id")
	uid := uint(userID.(int))

	var member models.Member
	if err := config.DB.First(&member, uid).Error; err != nil {
		c.JSON(http.StatusOK, gin.H{"success": true, "has_plan": false})
		return
	}

	// แผนส่วนตัว
	if member.MbActiveMwpID != nil {
		var plan models.MemberWorkoutPlan
		if err := config.DB.First(&plan, *member.MbActiveMwpID).Error; err != nil {
			c.JSON(http.StatusOK, gin.H{"success": true, "has_plan": false})
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"success":  true,
			"has_plan": true,
			"data": gin.H{
				"plan_id":       plan.MwpID,
				"mwp_id":        plan.MwpID,
				"plan_name":     plan.MwpName,
				"days_per_week": plan.MwpDaysPerWeek,
				"is_custom":     true,
			},
		})
		return
	}

	// แผนระบบ — ชื่อ/จำนวนวันดึงสดทุกครั้ง (ไม่ cache ฝั่ง backend) กันค้างเมื่อแอดมินแก้ไขแผนภายหลัง
	// จำนวนวันใช้ค่าจริงจาก workout_schedules ของ user (เผื่อ user เพิ่ม/ลบวันไปจากแม่แบบ) เหมือน
	// GetMyWorkoutPlans เพื่อให้ตัวเลขตรงกันทุกหน้าที่โชว์
	if member.MbActiveWptID != nil {
		var plan models.WorkoutPlanTemplate
		if err := config.DB.First(&plan, *member.MbActiveWptID).Error; err != nil {
			c.JSON(http.StatusOK, gin.H{"success": true, "has_plan": false})
			return
		}

		var dayNums []int
		config.DB.Model(&models.WorkoutSchedule{}).
			Where("mb_id = ? AND wpt_id = ?", uid, plan.WptID).
			Distinct("wsch_day_number").Pluck("wsch_day_number", &dayNums)
		realDays := len(dayNums)
		if realDays == 0 {
			realDays = plan.WptDaysPerWeek // กันกรณีข้อมูลว่างผิดปกติ ไม่ให้โชว์ 0 วัน
		}

		isModified := isSystemPlanModified(config.DB, uid, plan.WptID)

		c.JSON(http.StatusOK, gin.H{
			"success":  true,
			"has_plan": true,
			"data": gin.H{
				"plan_id":       plan.WptID,
				"plan_name":     plan.WptName,
				"days_per_week": realDays,
				"is_custom":     false,
				"is_modified":   isModified,
			},
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "has_plan": false})
}

// GetMyWorkoutPlans - รวมทุกแผนของ user: แผนส่วนตัว (member_workout_plans) + แผนระบบที่เคยเลือกใช้
// (distinct wpt_id ที่มีอยู่ใน workout_schedules ของ user) แต่ละรายการบอกด้วยว่าเป็นแผนที่ใช้งานอยู่หรือไม่
func GetMyWorkoutPlans(c *gin.Context) {
	userID, _ := c.Get("user_id")
	uid := uint(userID.(int))

	var member models.Member
	config.DB.First(&member, uid)

	type planRow struct {
		PlanType    string `json:"plan_type"` // "system" | "custom"
		WptID       *uint  `json:"wpt_id"`
		MwpID       *uint  `json:"mwp_id"`
		Name        string `json:"name"`
		DaysPerWeek int    `json:"days_per_week"`
		IsActive    bool   `json:"is_active"`
		IsModified  bool   `json:"is_modified"` // เฉพาะ system: ท่า/วันที่ user แก้ไม่ตรงแม่แบบต้นฉบับแล้ว
	}
	plans := []planRow{}

	var customPlans []models.MemberWorkoutPlan
	config.DB.Where("mb_id = ?", uid).Order("mwp_id asc").Find(&customPlans)
	for _, p := range customPlans {
		id := p.MwpID

		// จำนวนวันฝึกจริง — นับจาก wsch_day_number ที่มีท่าอยู่จริง เหมือนที่ทำกับแผนระบบด้านล่าง
		// (ไม่ใช้ mwp_days_per_week ตายตัว เพราะฟิลด์นี้ตั้งเป็น 7 ตอนสร้างเสมอ ไม่สะท้อนวันที่ใช้จริง)
		var dayNums []int
		config.DB.Model(&models.WorkoutSchedule{}).
			Where("mb_id = ? AND mwp_id = ?", uid, p.MwpID).
			Distinct("wsch_day_number").Pluck("wsch_day_number", &dayNums)

		plans = append(plans, planRow{
			PlanType:    "custom",
			MwpID:       &id,
			Name:        p.MwpName,
			DaysPerWeek: len(dayNums),
			IsActive:    member.MbActiveMwpID != nil && *member.MbActiveMwpID == p.MwpID,
		})
	}

	var wptIDs []uint
	config.DB.Model(&models.WorkoutSchedule{}).
		Where("mb_id = ? AND wpt_id IS NOT NULL", uid).
		Distinct("wpt_id").Pluck("wpt_id", &wptIDs)
	if len(wptIDs) > 0 {
		var templates []models.WorkoutPlanTemplate
		config.DB.Where("wpt_id IN ?", wptIDs).Order("wpt_id asc").Find(&templates)
		for _, t := range templates {
			id := t.WptID

			// จำนวนวันฝึกจริง — นับจาก wsch_day_number ที่มีท่าอยู่จริงในสำเนาของ user
			// (ไม่ใช่ wpt_days_per_week ตายตัวจากแม่แบบ) เผื่อ user เพิ่ม/ลบวันไปจากเดิม
			var dayNums []int
			config.DB.Model(&models.WorkoutSchedule{}).
				Where("mb_id = ? AND wpt_id = ?", uid, t.WptID).
				Distinct("wsch_day_number").Pluck("wsch_day_number", &dayNums)
			realDays := len(dayNums)

			isModified := isSystemPlanModified(config.DB, uid, t.WptID)

			plans = append(plans, planRow{
				PlanType:    "system",
				WptID:       &id,
				Name:        t.WptName,
				DaysPerWeek: realDays,
				IsActive:    member.MbActiveWptID != nil && *member.MbActiveWptID == t.WptID,
				IsModified:  isModified,
			})
		}
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "data": plans})
}

// CreatePersonalPlan - สร้างแผนส่วนตัวใหม่ (ตั้งชื่อเอง) แทนที่ CreateMemberPlan แบบเดิมที่คืนค่า dummy id ตายตัว
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

	plan := models.MemberWorkoutPlan{MbID: uid, MwpName: name, MwpDaysPerWeek: 7}
	if err := config.DB.Create(&plan).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "สร้างแผนไม่สำเร็จ"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "mwp_id": plan.MwpID, "name": plan.MwpName})
}

// RenamePersonalPlan - แก้ชื่อแผนส่วนตัว (ของตัวเองเท่านั้น)
func RenamePersonalPlan(c *gin.Context) {
	userID, _ := c.Get("user_id")
	id := c.Param("id")

	var req struct {
		Name string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ต้องระบุชื่อแผน"})
		return
	}

	result := config.DB.Model(&models.MemberWorkoutPlan{}).
		Where("mwp_id = ? AND mb_id = ?", id, userID).
		Update("mwp_name", req.Name)
	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผนนี้หรือไม่มีสิทธิ์แก้ไข"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "message": "แก้ชื่อแผนสำเร็จ"})
}

// DeletePersonalPlan - ลบแผนส่วนตัว (ของตัวเองเท่านั้น) — FK fk_wsch_mwp (ON DELETE CASCADE) ลบ
// workout_schedules ของแผนนี้ให้อัตโนมัติ ถ้าแผนนี้กำลัง active อยู่ เคลียร์ mb_active_mwp_id ด้วย
// กันชี้ไปแผนที่ไม่มีอยู่แล้ว
func DeletePersonalPlan(c *gin.Context) {
	userID, _ := c.Get("user_id")
	uid := uint(userID.(int))
	id := c.Param("id")

	result := config.DB.Where("mwp_id = ? AND mb_id = ?", id, uid).Delete(&models.MemberWorkoutPlan{})
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ลบไม่สำเร็จ"})
		return
	}
	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผนนี้หรือไม่มีสิทธิ์ลบ"})
		return
	}

	config.DB.Model(&models.Member{}).
		Where("mb_id = ? AND mb_active_mwp_id = ?", uid, id).
		Update("mb_active_mwp_id", nil)

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "ลบแผนสำเร็จ"})
}

// DeleteSystemPlanCopy - ลบท่าที่ user copy มาจากแผนระบบทิ้ง (ลบเฉพาะสำเนาของ user เอง
// ไม่แตะ workout_plan_template/plan_template_detail ต้นฉบับที่เป็น master data ร่วมกัน)
// ถ้าแผนนี้กำลัง active อยู่ เคลียร์ mb_active_wpt_id ด้วย กันชี้ไปแผนที่ไม่มีข้อมูลแล้ว
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

	config.DB.Model(&models.Member{}).
		Where("mb_id = ? AND mb_active_wpt_id = ?", uid, wptID).
		Update("mb_active_wpt_id", nil)

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "ลบแผนออกจากรายการสำเร็จ"})
}

// ActivatePlan - ตั้ง "แผนที่ใช้งานอยู่" (แผนระบบ หรือ แผนส่วนตัว) — จุดเดียวที่กันแผนชนกัน
// ถ้าเป็นแผนระบบที่ยังไม่เคย copy ท่ามาก่อน จะ copy ให้ก่อนเหมือน SelectWorkoutPlan
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
		var plan models.MemberWorkoutPlan
		if err := config.DB.Where("mwp_id = ? AND mb_id = ?", *req.MwpID, uid).First(&plan).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผนนี้"})
			return
		}
		setActivePersonalPlan(uid, *req.MwpID)
		c.JSON(http.StatusOK, gin.H{"success": true, "message": "ตั้งเป็นแผนที่ใช้งานสำเร็จ", "is_custom": true})
		return
	}

	var plan models.WorkoutPlanTemplate
	if err := config.DB.First(&plan, *req.WptID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผน"})
		return
	}

	var existingCount int64
	config.DB.Model(&models.WorkoutSchedule{}).
		Where("mb_id = ? AND wpt_id = ?", uid, *req.WptID).
		Count(&existingCount)

	if existingCount == 0 {
		// เช็ก V1-V3 ก่อน copy
		if err := validateTemplateComplete(plan.WptID, plan.WptDaysPerWeek); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		var details []models.PlanTemplateDetail
		config.DB.Where("wpt_id = ?", *req.WptID).Find(&details)
		if len(details) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "แผนนี้ยังไม่มีท่าฝึก กรุณาติดต่อผู้ดูแลระบบ"})
			return
		}
		today := time.Now().Format("2006-01-02")
		for _, d := range details {
			if d.WetID == nil {
				continue
			}
			ws := models.WorkoutSchedule{
				MbID:            uid,
				WschDate:        today,
				WschDayName:     d.PtdDayName,
				WschDayNumber:   toWeekday(int(plan.WptDaysPerWeek), int(d.PtdDayNumber)),
				WetID:           *d.WetID,
				WschSets:        d.PtdSets,
				WschRestSeconds: d.PtdRestSeconds,
				WschReps:        d.PtdReps,
				WschOrder:       d.PtdOrder,
				WptID:           req.WptID,
			}
			config.DB.Create(&ws)
		}
	}

	setActiveSystemPlan(uid, *req.WptID)
	c.JSON(http.StatusOK, gin.H{"success": true, "message": "ตั้งเป็นแผนที่ใช้งานสำเร็จ", "is_custom": false})
}

// ForkWorkoutPlan - คัดลอกแผนระบบ (wpt_id) → แผนส่วนตัวใหม่ (mwp_id) ที่แก้ไขได้อิสระ
// ใช้ day-mapping เดียวกับ SelectWorkoutPlan/ActivatePlan เป๊ะๆ (toWeekday) กันคัดลอกวันฝึกเพี้ยน
// ไม่ลบ/ไม่แตะสำเนา wpt_id เดิมของ user (อยู่คู่กันได้ในลิสต์ "แผนของฉัน") และไม่ตั้งเป็นแผน active ให้อัตโนมัติ
// (เหมือน CreatePersonalPlan) ให้ผู้ใช้กด "ตั้งเป็นแผนที่ใช้งาน" เองอีกทีถ้าต้องการ
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

	// กันชื่อชนกันเมื่อ fork แผนเดิมซ้ำ: ครั้งแรก "X (ของฉัน)" ครั้งถัดไป "X (ของฉัน 2)", "X (ของฉัน 3)", ...
	baseLabel := plan.WptName + " (ของฉัน"
	newName := baseLabel + ")"
	var forkedCount int64
	config.DB.Model(&models.MemberWorkoutPlan{}).
		Where("mb_id = ? AND mwp_name LIKE ?", uid, baseLabel+"%").
		Count(&forkedCount)
	if forkedCount > 0 {
		newName = fmt.Sprintf("%s %d)", baseLabel, forkedCount+1)
	}

	newPlan := models.MemberWorkoutPlan{
		MbID:           uid,
		MwpName:        newName,
		MwpDaysPerWeek: plan.WptDaysPerWeek,
	}
	if err := config.DB.Create(&newPlan).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "คัดลอกแผนไม่สำเร็จ"})
		return
	}

	inserted := 0
	today := time.Now().Format("2006-01-02")
	for _, d := range details {
		if d.WetID == nil {
			continue
		}
		ws := models.WorkoutSchedule{
			MbID:            uid,
			WschDate:        today,
			WschDayName:     d.PtdDayName,
			WschDayNumber:   toWeekday(int(plan.WptDaysPerWeek), int(d.PtdDayNumber)),
			WetID:           *d.WetID,
			WschSets:        d.PtdSets,
			WschRestSeconds: d.PtdRestSeconds,
			WschReps:        d.PtdReps,
			WschOrder:       d.PtdOrder,
			MwpID:           &newPlan.MwpID,
		}
		if err := config.DB.Create(&ws).Error; err == nil {
			inserted++
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"message":  "คัดลอกแผนเป็นของตัวเองสำเร็จ",
		"mwp_id":   newPlan.MwpID,
		"name":     newPlan.MwpName,
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
func CreateWorkoutSchedule(c *gin.Context) {
	userID, _ := c.Get("user_id")
	uid := uint(userID.(int))

	var req struct {
		PlanID    *uint  `json:"plan_id"`
		MwpID     *uint  `json:"mwp_id"`
		DayNumber int    `json:"day_number"`
		WetID     uint   `json:"wet_id" binding:"required,gt=0"`
		Sets      int    `json:"sets"`
		Reps      string `json:"reps"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ครบ กรุณาตรวจสอบข้อมูลที่ส่งมา"})
		return
	}
	if req.PlanID == nil && req.MwpID == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ต้องระบุ plan_id หรือ mwp_id"})
		return
	}
	// V1: วันฝึกต้องอยู่ในช่วง 1-7 (จันทร์-อาทิตย์)
	if req.DayNumber < 1 || req.DayNumber > 7 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "วันฝึกต้องอยู่ระหว่าง 1-7"})
		return
	}

	if req.MwpID != nil {
		var plan models.MemberWorkoutPlan
		if err := config.DB.Where("mwp_id = ? AND mb_id = ?", *req.MwpID, uid).First(&plan).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผนส่วนตัวนี้", "plan_not_found": true})
			return
		}
	} else {
		var plan models.WorkoutPlanTemplate
		if err := config.DB.First(&plan, req.PlanID).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบแผนที่ระบุ", "plan_not_found": true})
			return
		}
	}

	// V5: ห้ามเพิ่มท่าเดิมซ้ำในวันเดียวกันของแผนเดียวกัน
	dupQuery := config.DB.Model(&models.WorkoutSchedule{}).
		Where("mb_id = ? AND wsch_day_number = ? AND wet_id = ?", uid, req.DayNumber, req.WetID)
	if req.MwpID != nil {
		dupQuery = dupQuery.Where("mwp_id = ?", *req.MwpID)
	} else {
		dupQuery = dupQuery.Where("wpt_id = ?", *req.PlanID)
	}
	var dupCount int64
	dupQuery.Count(&dupCount)
	if dupCount > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ท่านี้มีอยู่ในวันนี้แล้ว"})
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

	// ลำดับท่าต่อจากท่าสุดท้ายของวันฝึกนี้ในแผนนี้ (ขอบเขตเดียวกับเช็คซ้ำ V5 ด้านบน) — ไม่ใช้
	// wsch_date เพราะคอลัมน์นั้นคือวันที่ "สร้างแถว" ไม่ใช่วันฝึกจริง (ดู D2 ใน CLAUDE.md) ถ้า group
	// ตาม wsch_date จะรวมท่าจากคนละวันฝึกที่บังเอิญเพิ่มในวันปฏิทินเดียวกันเข้าด้วยกันผิดๆ
	orderQuery := config.DB.Model(&models.WorkoutSchedule{}).
		Where("mb_id = ? AND wsch_day_number = ?", uid, req.DayNumber)
	if req.MwpID != nil {
		orderQuery = orderQuery.Where("mwp_id = ?", *req.MwpID)
	} else {
		orderQuery = orderQuery.Where("wpt_id = ?", *req.PlanID)
	}
	var maxOrder int
	orderQuery.Select("COALESCE(MAX(wsch_order), 0)").Scan(&maxOrder)

	ws := models.WorkoutSchedule{
		MbID:          uid,
		WschDate:      time.Now().Format("2006-01-02"),
		WschDayNumber: req.DayNumber,
		WetID:         req.WetID,
		WschSets:      sets,
		WschReps:      reps,
		WschOrder:     maxOrder + 1,
		WptID:         req.PlanID,
		MwpID:         req.MwpID,
	}
	if err := config.DB.Create(&ws).Error; err != nil {
		log.Printf("CreateWorkoutSchedule: create failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "เพิ่มท่าไม่สำเร็จ"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "data": ws})
}

// DeleteWorkoutSchedule - ลบท่าออกจากแผนของ user
func DeleteWorkoutSchedule(c *gin.Context) {
	userID, _ := c.Get("user_id")
	id := c.Param("id")
	result := config.DB.Where("wsch_id = ? AND mb_id = ?", id, userID).Delete(&models.WorkoutSchedule{})
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
func GetUserSchedules(c *gin.Context) {
	userID, _ := c.Get("user_id")
	planID := c.Query("plan_id")
	mwpID := c.Query("mwp_id")
	dayNumber := c.Query("day_number")

	if planID == "" && mwpID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "ต้องระบุ plan_id หรือ mwp_id"})
		return
	}

	var query = config.DB.Preload("WeightExercise")

	if mwpID != "" {
		var plan models.MemberWorkoutPlan
		if err := config.DB.Where("mwp_id = ? AND mb_id = ?", mwpID, userID).First(&plan).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "plan_not_found": true, "message": "ไม่พบแผนส่วนตัวนี้"})
			return
		}
		query = query.Where("mb_id = ? AND mwp_id = ?", userID, mwpID)
	} else {
		var plan models.WorkoutPlanTemplate
		if err := config.DB.First(&plan, planID).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "plan_not_found": true, "message": "ไม่พบแผนนี้ในระบบ"})
			return
		}
		query = query.Where("mb_id = ? AND wpt_id = ?", userID, planID)
	}

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

// WeightResultRequest - บันทึกผลเวทเทรนนิ่ง
type WeightResultRequest struct {
	Date       string  `json:"date" binding:"required"`
	WschID     *uint   `json:"wsch_id"`
	WetID      uint    `json:"wet_id" binding:"required,gt=0"`
	WtrsSetNo  int     `json:"wtrs_set_no" binding:"required,gt=0"`
	WtrsReps   int     `json:"wtrs_reps" binding:"required,gt=0"`
	WtrsWeight float64 `json:"wtrs_weight"`
	// (2026-08-22) เปลี่ยนนิยาม: เวลารวมทั้งเซสชัน (รวมพัก) หารเฉลี่ยเท่ากันทุกเซ็ตจากฝั่ง client
	// (ดู weight_training_exercise_view.dart _saveWorkoutToApi) — ไม่ใช่เวลาออกแรงต่อเซตอีกต่อไป
	// ดูเหตุผลที่ calories ด้านล่าง
	WtrsDuration       int  `json:"wtrs_duration"`
	WtrsIntensityLevel int8 `json:"wtrs_intensity_level"`
}

// CardioResultRequest - บันทึกผล Cardio (ไม่ต้องมี schedule)
type CardioResultRequest struct {
	Date          string  `json:"date" binding:"required"`
	CdoID         uint    `json:"cdo_id" binding:"required"`
	CdorsDuration int     `json:"cdors_duration" binding:"required,gt=0"`
	CdorsDistance float64 `json:"cdors_distance"`
}

func SaveWorkoutResult(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "ไม่พบข้อมูลผู้ใช้งาน"})
		return
	}
	uid := uint(userID.(int))

	var req WeightResultRequest
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

	// MET เวทเทรนนิ่งอ้างอิง 2011 Compendium of Physical Activities (Ainsworth et al., 2554)
	// รหัส 02054 (เบา 3.5) / 02052 (กลาง 5.0) / 02050 (หนัก 6.0 — power lifting/body building)
	// ยืนยันซ้ำแล้วว่าตรงกับ 2024 Adult Compendium ฉบับล่าสุดทุกรหัส/ค่า (2026-08-22) — ไม่ต้องแก้ค่า METs
	// เดิม case 3 = 8.0 ผิด (นั่นคือรหัส vigorous circuit training ไม่ใช่ resistance training)
	// level ไม่ส่งมา/ค่าแปลกปลอม → fallback เป็นเบา (1) — ใช้ level ตัวเดียวกันนี้ทั้งคำนวณแคลอรี่
	// และบันทึกลง wtrs_intensity_level กันค่าที่โชว์ "ระดับความหนัก" ไม่ตรงกับแคลอรี่ที่คำนวณจริง
	level := req.WtrsIntensityLevel
	if level < 1 || level > 3 {
		level = 1
	}
	var weightMets, restSec float64
	switch level {
	case 1:
		weightMets, restSec = 3.5, 60
	case 2:
		weightMets, restSec = 5.0, 90
	case 3:
		weightMets, restSec = 6.0, 120
	}

	durationHours := 2.0 / 60.0 // fallback 2 นาที แปลงเป็นชั่วโมง (เผื่อไม่มีทั้ง duration และ reps)
	if req.WtrsDuration > 0 {
		durationHours = float64(req.WtrsDuration) / 3600.0
	} else if req.WtrsReps > 0 {
		// ไม่ได้ส่ง duration มา → ประมาณเวลาต่อเซตจาก reps + ช่วงพักตามความหนัก: t_set = (reps × 3) + rest
		tSetSeconds := float64(req.WtrsReps)*3.0 + restSec
		durationHours = tSetSeconds / 3600.0
	}
	// NET calories: หัก 1 MET (=ค่าเผาผลาญขณะพักนิ่ง/resting metabolic) ออกก่อนเก็บ DB — กัน
	// นับซ้ำตอนเอาไปรวมกับ Baseline (BMR×1.2) เป็น Total Daily Energy Output (ดู
	// analytics_controller.go บรรทัด ~74-77 ที่ SUM(wtrs_calories) ตรงๆ เข้า exerciseBurn)
	// ค่า gross (ก่อนหัก) คำนวณย้อนได้เสมอไม่มีข้อมูลสูญหาย: gross = net × METs/(METs−1)
	// โดยใช้ METs จาก wtrs_intensity_level ที่เก็บคู่กันไว้ในแถวเดียวกัน
	//
	// Deprecated (2026-08-22): สูตรเดิม `weightMets * bodyWeight * durationHours` (ไม่หัก 1 MET,
	// ฐานเวลาเป็นรายเซ็ตจากการออกแรงจริง) มี 2 ปัญหา — (1) นับพลังงานพื้นฐานซ้ำกับ Baseline ใน TDEO
	// (2) ฐานเวลาไม่ตรงนิยาม METs ซึ่งเป็นค่าเฉลี่ยทั้งเซสชันรวมพักแล้ว ตาม 2024 Adult Compendium
	// of Physical Activities (รหัส 02054/02052/02050 ค่า METs เดิมถูกต้องแล้ว ไม่เปลี่ยน แก้แค่วิธี
	// คำนวณ/ฐานเวลา) — แถวข้อมูลเก่าก่อนวันนี้คำนวณด้วยสูตร gross แบบเดิม ไม่ตรงกับที่นี่ ถ้าต้อง
	// เทียบย้อนหลังให้เช็ควันที่ก่อนแก้
	calories := (weightMets - 1) * bodyWeight * durationHours

	// เลขเซ็ทนับต่อเนื่องทั้งวันจาก DB จริง ไม่ใช้ req.WtrsSetNo ตรงๆ — client (หน้าจอฝึก)
	// นับเซ็ทแบบรีเซ็ตเป็น 1 ใหม่ทุกครั้งที่เปิดหน้าจอ (ทุก "รอบ") ถ้าฝึกท่าเดียวกันซ้ำ
	// วันเดียวกันหลายรอบ (เช่น รอบเช้า 1 เซ็ท รอบเย็นอีก 3 เซ็ท) จะได้ wtrs_set_no ชนกันเป็น
	// 1,1,2,3 ในประวัติ ดูเหมือนข้อมูลซ้ำ/ผิดพลาด ทั้งที่จริงบันทึกครบ — คำนวณจากจำนวนแถวที่
	// มีอยู่แล้วของ (สมาชิก, ท่านี้, วันนี้) +1 แทน ได้เลขต่อเนื่อง 1,2,3,4 เสมอไม่ว่าจะแบ่งกี่รอบ
	today := time.Now().Format("2006-01-02")
	var existingSetCount int64
	config.DB.Model(&models.WeightTrainingResult{}).
		Where("mb_id = ? AND wet_id = ? AND wtrs_date = ?", uid, req.WetID, today).
		Count(&existingSetCount)

	result := models.WeightTrainingResult{
		WtrsDate:           today,
		WtrsSetNo:          int(existingSetCount) + 1,
		WtrsReps:           req.WtrsReps,
		WtrsWeight:         req.WtrsWeight,
		WtrsIntensityLevel: level,
		WtrsCalories:       calories,
		MbID:               uid,
		WetID:              req.WetID,
		WschID:             req.WschID,
	}

	if err := config.DB.Create(&result).Error; err != nil {
		log.Printf("SaveResult: create failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "บันทึกผลไม่สำเร็จ กรุณาลองใหม่"})
		return
	}

	// 1RM = weight × (1 + reps/30)
	estimated1RM := 0.0
	if req.WtrsWeight > 0 && req.WtrsReps > 0 {
		estimated1RM = math.Round(req.WtrsWeight*(1+float64(req.WtrsReps)/30.0)*100) / 100
	}

	c.JSON(http.StatusOK, gin.H{
		"message":         "บันทึกผลการฝึกสำเร็จ",
		"data":            result,
		"calories_burned": calories,
		"estimated_1rm":   estimated1RM,
	})
}

// GetBest1RM - ดึง estimated 1RM สูงสุดของ user สำหรับท่าฝึกที่ระบุ
func GetBest1RM(c *gin.Context) {
	userID, _ := c.Get("user_id")
	wetID := c.Param("wet_id")

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
	`, userID, wetID).Scan(&row)

	if row.BestWeight == 0 {
		c.JSON(http.StatusOK, gin.H{
			"wet_id":   wetID,
			"best_1rm": 0,
			"has_data": false,
		})
		return
	}

	best1RM := math.Round(row.BestWeight*(1+float64(row.BestReps)/30.0)*100) / 100
	c.JSON(http.StatusOK, gin.H{
		"wet_id":      wetID,
		"best_1rm":    best1RM,
		"best_weight": row.BestWeight,
		"best_reps":   row.BestReps,
		"date":        row.Date,
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

	result := models.CardioResult{
		CdorsDate:     req.Date,
		CdorsDuration: req.CdorsDuration,
		CdorsDistance: req.CdorsDistance,
		CdorsCalories: burnedCalories,
		MbID:          uid,
		CdoID:         req.CdoID,
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

	// เช็คการใช้งานจริงจาก workout_schedules (นับสมาชิกที่เคย/กำลังใช้แผนนี้) แทนการเช็ค
	// plan_template_detail ซึ่งมีแทบทุกแผนอยู่แล้วและ cascade ลบเองอัตโนมัติผ่าน fk_ptd_plan
	// (ON DELETE CASCADE) — เช็คแบบเดิมเลยบล็อกการลบแผนทุกแผนที่มีท่าฝึกโดยไม่จำเป็น
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
