package controllers

import (
	"fmt"
	"food_and_fit_api/config"
	"food_and_fit_api/helpers"
	"food_and_fit_api/models"
	"food_and_fit_api/services"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// ==========================================
// Request Structs
// ==========================================

type EditProfileRequest struct {
	FullName  string `json:"full_name" binding:"required"`
	Gender    int    `json:"gender" binding:"required"`     // 1=ชาย, 2=หญิง
	BirthDate string `json:"birth_date" binding:"required"` // รูปแบบ: YYYY-MM-DD
}

type UpdateBodyStatsRequest struct {
	Weight        float64 `json:"weight" binding:"required"`
	Height        float64 `json:"height" binding:"required"`
	ActivityLevel float64 `json:"activity_level" binding:"required"`
	Target        int     `json:"target" binding:"required"` // 1=ลดน้ำหนัก, 2=เพิ่มกล้ามเนื้อ, 3=รักษาน้ำหนัก
}

// เพิ่ม Struct สำหรับรับค่าจากหน้า Personalize Profile
type UpdateProfileRequest struct {
	Gender        int     `json:"gender" binding:"required"`
	BirthDate     string  `json:"birth_date" binding:"required"`
	Weight        float64 `json:"weight" binding:"required"`
	Height        float64 `json:"height" binding:"required"`
	ActivityLevel float64 `json:"activity_level" binding:"required"`
	Target        int     `json:"target" binding:"required"`
}

// ==========================================
// Handlers
// ==========================================

// UpdateProfile - บันทึกข้อมูลสุขภาพครั้งแรก (หลังจากสมัครสมาชิกและยืนยันตัวตน)
func UpdateProfile(c *gin.Context) {
	var req UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง กรุณาตรวจสอบข้อมูลที่กรอก"})
		return
	}

	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "ไม่พบข้อมูลผู้ใช้งาน"})
		return
	}

	if valid, msg := helpers.ValidateGender(req.Gender); !valid {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	if valid, msg := helpers.ValidateWeight(req.Weight); !valid {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	if valid, msg := helpers.ValidateHeight(req.Height); !valid {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	if valid, msg := helpers.ValidateActivityLevel(req.ActivityLevel); !valid {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	if valid, msg := helpers.ValidateTarget(req.Target); !valid {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}

	// 1. จัดการวันที่
	parsedDate, err := time.Parse("2006-01-02", req.BirthDate)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "รูปแบบวันที่ไม่ถูกต้อง (YYYY-MM-DD)"})
		return
	}

	// 2. คำนวณอายุ
	age := time.Now().Year() - parsedDate.Year()
	if time.Now().YearDay() < parsedDate.YearDay() {
		age--
	}

	// 3. คำนวณเป้าหมาย (BMI, BMR, TDEE)
	bmi, bmr, tdee, targetCal := services.CalculateGoals(
		req.Weight,
		req.Height,
		age,
		req.Gender,
		req.ActivityLevel,
		req.Target,
	)

	// 4. บันทึกข้อมูลด้วย Transaction (เพื่อให้มั่นใจว่าบันทึกครบทุกตาราง)
	err = config.DB.Transaction(func(tx *gorm.DB) error {
		// อัปเดตข้อมูลพื้นฐานในตาราง Member
		if err := tx.Model(&models.Member{}).Where("mb_id = ?", userID).Updates(map[string]interface{}{
			"mb_gender":     req.Gender,
			"mb_birth_date": parsedDate,
		}).Error; err != nil {
			return err
		}

		// บันทึก Body Stats
		bodyStat := models.MemberBodyStat{
			MbID:             userID.(int),
			MbsWeight:        req.Weight,
			MbsHeight:        req.Height,
			MbsActivityLevel: req.ActivityLevel,
			MbsTarget:        req.Target,
			MbsRecordedDate:  time.Now(),
		}
		if err := tx.Create(&bodyStat).Error; err != nil {
			return err
		}

		// บันทึก BMR History
		bmrHistory := models.MemberBmrHistory{
			MbID:          userID.(int),
			MbsID:         &bodyStat.MbsID,
			MbhBmi:        bmi,
			MbhBmr:        bmr,
			MbhTdee:       tdee,
			MbhTdeeTarget: targetCal,
			MbhRecordDate: time.Now(),
		}
		if err := tx.Create(&bmrHistory).Error; err != nil {
			return err
		}

		return nil
	})

	if err != nil {
		log.Printf("UpdateBodyStats: transaction failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถบันทึกข้อมูลได้ กรุณาลองใหม่"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "บันทึกข้อมูลสุขภาพสำเร็จ",
		"goals": gin.H{
			"bmi":        bmi,
			"bmr":        bmr,
			"tdee":       tdee,
			"target_cal": targetCal,
		},
	})
}

// GetProfile - ดึงข้อมูลโปรไฟล์ผู้ใช้ พร้อมค่าสถิติร่างกายล่าสุด
func GetProfile(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		helpers.RespondUnauthorized(c, "ไม่พบข้อมูลผู้ใช้งานในระบบ")
		return
	}

	var member models.Member
	if err := config.DB.First(&member, userID).Error; err != nil {
		helpers.RespondNotFound(c, "ไม่พบข้อมูลสมาชิก")
		return
	}

	var bodyStat models.MemberBodyStat
	config.DB.Where("mb_id = ?", userID).Order("mbs_id desc").Limit(1).Find(&bodyStat)

	var bmrHistory models.MemberBmrHistory
	config.DB.Where("mb_id = ?", userID).Order("mbh_id desc").Limit(1).Find(&bmrHistory)

	c.JSON(http.StatusOK, gin.H{
		"profile": gin.H{
			"id":          member.MbID,
			"email":       member.MbEmail,
			"full_name":   member.MbFullName,
			"gender":      member.MbGender,
			"birth_date":  member.MbBirthDate.Format("2006-01-02"),
			"profile_pic": member.MbProfilePic,
		},
		"body_stats": gin.H{
			"weight":         bodyStat.MbsWeight,
			"height":         bodyStat.MbsHeight,
			"activity_level": bodyStat.MbsActivityLevel,
			"target":         bodyStat.MbsTarget,
			"last_updated":   bodyStat.MbsRecordedDate.Format("2006-01-02 15:04:05"),
		},
		"goals": gin.H{
			"bmi":           bmrHistory.MbhBmi,
			"bmr":           bmrHistory.MbhBmr,
			"tdee":          bmrHistory.MbhTdee,
			"target_cal":    bmrHistory.MbhTdeeTarget,
			"last_analyzed": bmrHistory.MbhRecordDate.Format("2006-01-02"),
		},
	})
}

// EditProfile - แก้ไขข้อมูลส่วนตัวพื้นฐาน
func EditProfile(c *gin.Context) {
	var req EditProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		helpers.RespondBadRequest(c, "request", "รูปแบบข้อมูลไม่ถูกต้อง")
		return
	}

	userID, _ := c.Get("user_id")

	parsedDate, err := time.Parse("2006-01-02", req.BirthDate)
	if err != nil {
		helpers.RespondBadRequest(c, "birth_date", "รูปแบบวันที่ไม่ถูกต้อง (YYYY-MM-DD)")
		return
	}

	if parsedDate.After(time.Now()) {
		helpers.RespondBadRequest(c, "birth_date", "วันเกิดไม่สามารถเป็นอนาคตได้")
		return
	}

	updateData := map[string]interface{}{
		"mb_full_name":  req.FullName,
		"mb_gender":     req.Gender,
		"mb_birth_date": parsedDate,
	}

	// gender/birth_date เข้าสูตร BMR (Mifflin-St Jeor) โดยตรง — เปลี่ยนแล้วต้อง recompute
	// BMR/TDEE ใหม่ทันที มิฉะนั้นรายงานจะค้างค่าที่คำนวณจาก gender/อายุเดิม ผูกกับ mbs_id
	// เดิม (ไม่สร้างแถว member_body_stats ใหม่ เพราะน้ำหนัก/ส่วนสูง/กิจกรรม/เป้าหมายไม่ได้เปลี่ยน)
	err = config.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&models.Member{}).Where("mb_id = ?", userID).Updates(updateData).Error; err != nil {
			return err
		}

		var bodyStat models.MemberBodyStat
		tx.Where("mb_id = ?", userID).Order("mbs_id desc").Limit(1).Find(&bodyStat)
		if bodyStat.MbsID == 0 {
			return nil // ยังไม่เคยกรอกข้อมูลร่างกาย (onboarding ยังไม่เสร็จ) — ไม่มีอะไรให้ recompute
		}

		age := time.Now().Year() - parsedDate.Year()
		if time.Now().YearDay() < parsedDate.YearDay() {
			age--
		}
		bmi, bmr, tdee, targetCal := services.CalculateGoals(
			bodyStat.MbsWeight, bodyStat.MbsHeight, age, req.Gender, bodyStat.MbsActivityLevel, bodyStat.MbsTarget,
		)
		newHistory := models.MemberBmrHistory{
			MbID:          userID.(int),
			MbsID:         &bodyStat.MbsID,
			MbhBmi:        bmi,
			MbhBmr:        bmr,
			MbhTdee:       tdee,
			MbhTdeeTarget: targetCal,
			MbhRecordDate: time.Now(),
		}
		return tx.Create(&newHistory).Error
	})

	if err != nil {
		helpers.RespondInternalError(c, "ไม่สามารถอัปเดตข้อมูลโปรไฟล์ได้")
		return
	}

	helpers.RespondSuccess(c, "อัปเดตข้อมูลส่วนตัวสำเร็จ", nil)
}

// UploadProfileImage - อัปโหลดและเปลี่ยนรูปโปรไฟล์
func UploadProfileImage(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		helpers.RespondUnauthorized(c, "ไม่พบข้อมูลผู้ใช้งาน")
		return
	}

	file, err := c.FormFile("image")
	if err != nil {
		helpers.RespondBadRequest(c, "image", "กรุณาแนบไฟล์รูปภาพ")
		return
	}

	ext := strings.ToLower(filepath.Ext(file.Filename))
	if ext != ".jpg" && ext != ".jpeg" && ext != ".png" && ext != ".webp" {
		helpers.RespondBadRequest(c, "image", "รองรับเฉพาะไฟล์ .jpg, .jpeg, .png, .webp เท่านั้น")
		return
	}
	// ตรวจ MIME type จริงของไฟล์ (ไม่เชื่อแค่นามสกุลที่ผู้ใช้ตั้ง) + จำกัดขนาด
	if verr := helpers.ValidateImageUpload(file); verr != nil {
		helpers.RespondBadRequest(c, "image", verr.Error())
		return
	}

	uploadDir := "uploads/profiles"
	if err := os.MkdirAll(uploadDir, os.ModePerm); err != nil {
		helpers.RespondInternalError(c, "ไม่สามารถสร้างแฟ้มจัดเก็บรูปภาพได้")
		return
	}

	newFileName := fmt.Sprintf("user_%v_%v%s", userID, time.Now().Unix(), ext)
	savePath := filepath.Join(uploadDir, newFileName)

	if err := c.SaveUploadedFile(file, savePath); err != nil {
		helpers.RespondInternalError(c, "ไม่สามารถบันทึกรูปภาพได้")
		return
	}

	imageUrl := "/" + filepath.ToSlash(savePath)
	if err := config.DB.Model(&models.Member{}).Where("mb_id = ?", userID).Update("mb_profile_pic", imageUrl).Error; err != nil {
		helpers.RespondInternalError(c, "ไม่สามารถอัปเดตข้อมูลในระบบได้")
		return
	}

	helpers.RespondSuccess(c, "อัปโหลดรูปโปรไฟล์สำเร็จ", gin.H{
		"profile_pic": imageUrl,
	})
}

// UpdateBodyStats - อัปเดตข้อมูลร่างกายและคำนวณเป้าหมายใหม่ (สำหรับใช้ภายหลังเมื่อมีการเปลี่ยนแปลงน้ำหนัก)
func UpdateBodyStats(c *gin.Context) {
	var req UpdateBodyStatsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		helpers.RespondBadRequest(c, "request", "กรุณากรอกข้อมูลร่างกายให้ครบถ้วน")
		return
	}

	if valid, msg := helpers.ValidateWeight(req.Weight); !valid {
		helpers.RespondBadRequest(c, "weight", msg)
		return
	}
	if valid, msg := helpers.ValidateActivityLevel(req.ActivityLevel); !valid {
		helpers.RespondBadRequest(c, "activity_level", msg)
		return
	}
	if valid, msg := helpers.ValidateTarget(req.Target); !valid {
		helpers.RespondBadRequest(c, "target", msg)
		return
	}

	userID, _ := c.Get("user_id")

	var member models.Member
	if err := config.DB.First(&member, userID).Error; err != nil {
		helpers.RespondNotFound(c, "ไม่พบผู้ใช้งาน")
		return
	}

	newStat := models.MemberBodyStat{
		MbID:             userID.(int),
		MbsWeight:        req.Weight,
		MbsHeight:        req.Height,
		MbsActivityLevel: req.ActivityLevel,
		MbsTarget:        req.Target,
		MbsRecordedDate:  time.Now(),
	}
	if err := config.DB.Create(&newStat).Error; err != nil {
		helpers.RespondInternalError(c, "ไม่สามารถบันทึกข้อมูลร่างกายได้")
		return
	}

	age := time.Now().Year() - member.MbBirthDate.Year()
	if time.Now().YearDay() < member.MbBirthDate.YearDay() {
		age--
	}

	bmi, bmr, tdee, targetCal := services.CalculateGoals(
		req.Weight,
		req.Height,
		age,
		member.MbGender,
		req.ActivityLevel,
		req.Target,
	)

	newHistory := models.MemberBmrHistory{
		MbID:          userID.(int),
		MbsID:         &newStat.MbsID,
		MbhBmi:        bmi,
		MbhBmr:        bmr,
		MbhTdee:       tdee,
		MbhTdeeTarget: targetCal,
		MbhRecordDate: time.Now(),
	}
	if err := config.DB.Create(&newHistory).Error; err != nil {
		helpers.RespondInternalError(c, "ไม่สามารถบันทึกเป้าหมายใหม่ได้")
		return
	}

	helpers.RespondSuccess(c, "อัปเดตน้ำหนักและคำนวณเป้าหมายใหม่เรียบร้อยแล้ว", gin.H{
		"bmi":        bmi,
		"bmr":        bmr,
		"tdee":       tdee,
		"target_cal": targetCal,
	})
}

// GetStatsHistory - ดึงประวัติน้ำหนักย้อนหลัง 10 รายการ
func GetStatsHistory(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		helpers.RespondUnauthorized(c, "ไม่พบข้อมูลผู้ใช้งานในระบบ")
		return
	}

	var bodyStats []models.MemberBodyStat
	if err := config.DB.Where("mb_id = ?", userID).Order("mbs_id desc").Limit(10).Find(&bodyStats).Error; err != nil {
		helpers.RespondInternalError(c, "ไม่สามารถดึงข้อมูลประวัติได้")
		return
	}

	var historyResponse []gin.H
	for _, stat := range bodyStats {
		historyResponse = append(historyResponse, gin.H{
			"date":           stat.MbsRecordedDate.Format("2006-01-02"),
			"weight":         stat.MbsWeight,
			"activity_level": stat.MbsActivityLevel,
			"target":         stat.MbsTarget,
		})
	}

	for i, j := 0, len(historyResponse)-1; i < j; i, j = i+1, j-1 {
		historyResponse[i], historyResponse[j] = historyResponse[j], historyResponse[i]
	}

	helpers.RespondSuccess(c, "ดึงข้อมูลประวัติสำเร็จ", historyResponse)
}
