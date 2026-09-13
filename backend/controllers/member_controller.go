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
	// optional — ให้หน้าแก้ไขข้อมูลร่างกาย (มือถือ) อัปเดต gender/birth_date พร้อมกันได้ในคำขอเดียว
	// กันไม่ให้ต้องยิง PUT /member/profile แยกก่อน ซึ่งเดิมทำให้เกิดแถว member_bmr_history ซ้ำซ้อน
	Gender    *int    `json:"gender,omitempty"`
	BirthDate *string `json:"birth_date,omitempty"` // รูปแบบ: YYYY-MM-DD
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

// ageFromBirthDate คำนวณอายุเต็มปี ณ เวลาปัจจุบัน จากวันเกิดที่กำหนด
func ageFromBirthDate(birthDate time.Time) int {
	age := time.Now().Year() - birthDate.Year()
	if time.Now().YearDay() < birthDate.YearDay() {
		age--
	}
	return age
}

// UpdateProfile - บันทึกข้อมูลสุขภาพครั้งแรก (หลังจากสมัครสมาชิกและยืนยันตัวตน)
// upsert รายวันเหมือน UpdateBodyStats (D10) — กดย้อนกลับมาแก้ขั้นตอน personalize ในวันเดียวกัน
// ต้องทับแถวเดิมของวันนั้น ไม่ใช่สร้างแถว member_body_stats/member_bmr_history ใหม่ทุกครั้ง
// (เดิม Create() ตรงๆ ไม่มีเงื่อนไข ทำให้กดซ้ำ 2 ครั้งได้แถวผีวันเดียวกัน 2 แถว)
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
	age := ageFromBirthDate(parsedDate)

	// 3. คำนวณเป้าหมาย (BMI, BMR, TDEE)
	bmi, bmr, tdee, targetCal := services.CalculateGoals(
		req.Weight,
		req.Height,
		age,
		req.Gender,
		req.ActivityLevel,
		req.Target,
	)

	// 4. บันทึกข้อมูลด้วย Transaction (เพื่อให้มั่นใจว่าบันทึกครบทุกตาราง) — upsert รายวัน
	now := time.Now()
	todayStr := now.Format("2006-01-02")
	todayDate := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

	err = config.DB.Transaction(func(tx *gorm.DB) error {
		// อัปเดตข้อมูลพื้นฐานในตาราง Member
		if err := tx.Model(&models.Member{}).Where("mb_id = ?", userID).Updates(map[string]interface{}{
			"mb_gender":     req.Gender,
			"mb_birth_date": parsedDate,
		}).Error; err != nil {
			return err
		}

		// Body Stats — upsert รายวัน (ORDER BY mbs_id desc + LIMIT 1 จำเป็นจริง ดูเหตุผลเต็ม
		// ที่คอมเมนต์เดียวกันใน UpdateBodyStats ด้านล่าง)
		var bodyStat models.MemberBodyStat
		var existingStat models.MemberBodyStat
		tx.Where("mb_id = ? AND DATE(mbs_recorded_date) = ?", userID, todayStr).
			Order("mbs_id desc").Limit(1).Find(&existingStat)

		if existingStat.MbsID != 0 {
			bodyStat = existingStat
			bodyStat.MbsWeight = req.Weight
			bodyStat.MbsHeight = req.Height
			bodyStat.MbsActivityLevel = req.ActivityLevel
			bodyStat.MbsTarget = req.Target
			bodyStat.MbsRecordedDate = now
			if err := tx.Model(&models.MemberBodyStat{}).Where("mbs_id = ?", bodyStat.MbsID).Updates(map[string]interface{}{
				"mbs_weight":         bodyStat.MbsWeight,
				"mbs_height":         bodyStat.MbsHeight,
				"mbs_activity_level": bodyStat.MbsActivityLevel,
				"mbs_target":         bodyStat.MbsTarget,
				"mbs_recorded_date":  bodyStat.MbsRecordedDate,
			}).Error; err != nil {
				return err
			}
		} else {
			bodyStat = models.MemberBodyStat{
				MbID:             userID.(int),
				MbsWeight:        req.Weight,
				MbsHeight:        req.Height,
				MbsActivityLevel: req.ActivityLevel,
				MbsTarget:        req.Target,
				MbsRecordedDate:  now,
			}
			if err := tx.Create(&bodyStat).Error; err != nil {
				return err
			}
		}

		// BMR History — upsert รายวันเช่นกัน
		var existingHistory models.MemberBmrHistory
		tx.Where("mb_id = ? AND mbh_record_date = ?", userID, todayStr).
			Order("mbh_id desc").Limit(1).Find(&existingHistory)

		if existingHistory.MbhID != 0 {
			return tx.Model(&models.MemberBmrHistory{}).Where("mbh_id = ?", existingHistory.MbhID).Updates(map[string]interface{}{
				"mbs_id":          bodyStat.MbsID,
				"mbh_bmi":         bmi,
				"mbh_bmr":         bmr,
				"mbh_tdee":        tdee,
				"mbh_tdee_target": targetCal,
			}).Error
		}

		bmrHistory := models.MemberBmrHistory{
			MbID:          userID.(int),
			MbsID:         &bodyStat.MbsID,
			MbhBmi:        bmi,
			MbhBmr:        bmr,
			MbhTdee:       tdee,
			MbhTdeeTarget: targetCal,
			MbhRecordDate: todayDate,
		}
		return tx.Create(&bmrHistory).Error
	})

	if err != nil {
		log.Printf("UpdateProfile: transaction failed: %v", err)
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
// gender/birth_date เข้าสูตร BMR (Mifflin-St Jeor) โดยตรง — recompute + insert member_bmr_history
// เฉพาะตอนอายุเต็มปีเปลี่ยนจริง หรือ gender เปลี่ยนจริงเท่านั้น (เทียบกับค่าเดิมใน DB) กันไม่ให้เกิด
// แถวประวัติซ้ำซ้อนตอนหน้าแก้ไขข้อมูลร่างกาย (มือถือ) เรียก endpoint นี้ตามด้วย UpdateBodyStats ติดกัน
// — ถ้าไม่เปลี่ยนอะไรที่กระทบสูตรเลย จะไม่ insert ประวัติซ้ำ (เดิม insert ทุกครั้งไม่มีเงื่อนไข)
// 2026-09-12: การ insert member_bmr_history เปลี่ยนเป็น upsert รายวันแล้ว (เดิม tx.Create() ดิบ
// ไม่เช็คแถวเดิมของวันนี้ก่อน — เป็น path เดียวใน 3 path ที่เขียนตารางนี้ที่ยังไม่ upsert ตาม D10)
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

	err = config.DB.Transaction(func(tx *gorm.DB) error {
		var oldMember models.Member
		if err := tx.First(&oldMember, userID).Error; err != nil {
			return err
		}

		if err := tx.Model(&models.Member{}).Where("mb_id = ?", userID).Updates(updateData).Error; err != nil {
			return err
		}

		genderChanged := req.Gender != oldMember.MbGender
		ageChanged := ageFromBirthDate(parsedDate) != ageFromBirthDate(oldMember.MbBirthDate)
		if !genderChanged && !ageChanged {
			return nil // เพศ/อายุเต็มปีไม่เปลี่ยน ไม่กระทบสูตร ไม่ต้อง recompute/insert ประวัติซ้ำ
		}

		var bodyStat models.MemberBodyStat
		tx.Where("mb_id = ?", userID).Order("mbs_id desc").Limit(1).Find(&bodyStat)
		if bodyStat.MbsID == 0 {
			return nil // ยังไม่เคยกรอกข้อมูลร่างกาย (onboarding ยังไม่เสร็จ) — ไม่มีอะไรให้ recompute
		}

		bmi, bmr, tdee, targetCal := services.CalculateGoals(
			bodyStat.MbsWeight, bodyStat.MbsHeight, ageFromBirthDate(parsedDate), req.Gender, bodyStat.MbsActivityLevel, bodyStat.MbsTarget,
		)

		// upsert รายวันเหมือน UpdateBodyStats/UpdateProfile (ดู D10) — เดิม Create() ดิบไม่เช็คแถวเดิม
		// ของวันนี้ก่อน ทำให้เพศ/วันเกิดที่แก้ 2 ครั้งในวันเดียวกันได้ประวัติซ้ำ 2 แถว (2026-09-12)
		now := time.Now()
		todayStr := now.Format("2006-01-02")
		todayDate := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

		var existingHistory models.MemberBmrHistory
		tx.Where("mb_id = ? AND mbh_record_date = ?", userID, todayStr).
			Order("mbh_id desc").Limit(1).Find(&existingHistory)

		if existingHistory.MbhID != 0 {
			return tx.Model(&models.MemberBmrHistory{}).Where("mbh_id = ?", existingHistory.MbhID).Updates(map[string]interface{}{
				"mbs_id":          bodyStat.MbsID,
				"mbh_bmi":         bmi,
				"mbh_bmr":         bmr,
				"mbh_tdee":        tdee,
				"mbh_tdee_target": targetCal,
			}).Error
		}

		newHistory := models.MemberBmrHistory{
			MbID:          userID.(int),
			MbsID:         &bodyStat.MbsID,
			MbhBmi:        bmi,
			MbhBmr:        bmr,
			MbhTdee:       tdee,
			MbhTdeeTarget: targetCal,
			MbhRecordDate: todayDate,
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
// gender/birth_date เป็น optional — ถ้าส่งมาด้วย จะอัปเดต member_profile ในทรานแซกชันเดียวกันก่อน
// คำนวณ BMI/BMR/TDEE/Target จากค่าใหม่ทั้งชุด (เดิมหน้าแก้ไขข้อมูลร่างกายฝั่งมือถือต้องยิง
// PUT /member/profile แยกก่อนเพื่อแก้ gender/birth_date ทำให้เกิด member_bmr_history ซ้ำซ้อน)
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
	if valid, msg := helpers.ValidateHeight(req.Height); !valid {
		helpers.RespondBadRequest(c, "height", msg)
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
	if req.Gender != nil {
		if valid, msg := helpers.ValidateGender(*req.Gender); !valid {
			helpers.RespondBadRequest(c, "gender", msg)
			return
		}
	}
	var parsedBirthDate *time.Time
	if req.BirthDate != nil {
		d, err := time.Parse("2006-01-02", *req.BirthDate)
		if err != nil {
			helpers.RespondBadRequest(c, "birth_date", "รูปแบบวันที่ไม่ถูกต้อง (YYYY-MM-DD)")
			return
		}
		if d.After(time.Now()) {
			helpers.RespondBadRequest(c, "birth_date", "วันเกิดไม่สามารถเป็นอนาคตได้")
			return
		}
		parsedBirthDate = &d
	}

	userID, _ := c.Get("user_id")

	var member models.Member
	if err := config.DB.First(&member, userID).Error; err != nil {
		helpers.RespondNotFound(c, "ไม่พบผู้ใช้งาน")
		return
	}

	finalGender := member.MbGender
	if req.Gender != nil {
		finalGender = *req.Gender
	}
	finalBirthDate := member.MbBirthDate
	if parsedBirthDate != nil {
		finalBirthDate = *parsedBirthDate
	}

	var newStat models.MemberBodyStat
	var bmi, bmr, tdee, targetCal float64
	warnings := make([]string, 0)

	err := config.DB.Transaction(func(tx *gorm.DB) error {
		// plausibility check (ไม่ block) — เทียบกับแถวล่าสุดก่อนบันทึกนี้เสมอ ไม่ว่าจะเป็นแถว
		// ของวันก่อนหรือของวันนี้เอง (กรณีแก้ซ้ำในวันเดียวกัน ก็ยังอยากรู้ว่าค่าที่เพิ่งแก้ต่างจาก
		// ค่าที่เพิ่งบันทึกไปมากผิดปกติไหม)
		var prevStat models.MemberBodyStat
		tx.Where("mb_id = ?", userID).Order("mbs_id desc").Limit(1).Find(&prevStat)
		if prevStat.MbsID != 0 {
			if diff := req.Weight - prevStat.MbsWeight; diff > 2 || diff < -2 {
				warnings = append(warnings, fmt.Sprintf("น้ำหนักเปลี่ยนจากครั้งก่อน %.1f กก. มากผิดปกติ กรุณาตรวจสอบความถูกต้อง", diff))
			}
			if diff := req.Height - prevStat.MbsHeight; diff > 1 || diff < -1 {
				warnings = append(warnings, fmt.Sprintf("ส่วนสูงเปลี่ยนจากครั้งก่อน %.1f ซม. มากผิดปกติ กรุณาตรวจสอบความถูกต้อง", diff))
			}
		}

		if req.Gender != nil || parsedBirthDate != nil {
			profileUpdate := map[string]interface{}{}
			if req.Gender != nil {
				profileUpdate["mb_gender"] = finalGender
			}
			if parsedBirthDate != nil {
				profileUpdate["mb_birth_date"] = finalBirthDate
			}
			if err := tx.Model(&models.Member{}).Where("mb_id = ?", userID).Updates(profileUpdate).Error; err != nil {
				return err
			}
		}

		now := time.Now()
		todayStr := now.Format("2006-01-02")
		todayDate := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

		// upsert รายวัน — mbh_record_date เป็น DATE อยู่แล้ว (สคีมาตั้งใจ 1 วัน = 1 จุดข้อมูล)
		// กดบันทึกรัวๆ ในวันเดียวกันจึงทับแถวเดิมของวันนั้น แทนที่จะสร้างแถว noise ใหม่ทุกครั้ง
		// .Order().Limit(1) จำเป็นจริง ไม่ใช่แค่กันไว้เฉยๆ — GORM Find() บน struct เดี่ยว (ไม่ใช่ slice)
		// เรียก rows.Next() แค่ครั้งเดียวแล้วทิ้งแถวที่เหลือ (ดู gorm scan.go: case reflect.Struct
		// ใช้ if ไม่ใช่ for) ถ้าไม่ระบุ ORDER BY แถวที่ได้ขึ้นกับลำดับที่ MySQL คืนมาเฉยๆ (ปกติเป็น
		// ลำดับ PK ต่ำไปสูงถ้าไม่ใช้ index อื่น) ซึ่งตรงข้ามกับที่ต้องการถ้ามีแถวผีเก่าซ้ำวันเดียวกัน
		// ค้างอยู่ (ก่อนรัน cleanup script) — ต้องบังคับเอาแถว mbs_id สูงสุดของวันนั้นเสมอ
		var existingStat models.MemberBodyStat
		tx.Where("mb_id = ? AND DATE(mbs_recorded_date) = ?", userID, todayStr).
			Order("mbs_id desc").Limit(1).Find(&existingStat)

		if existingStat.MbsID != 0 {
			newStat = existingStat
			newStat.MbsWeight = req.Weight
			newStat.MbsHeight = req.Height
			newStat.MbsActivityLevel = req.ActivityLevel
			newStat.MbsTarget = req.Target
			newStat.MbsRecordedDate = now
			if err := tx.Model(&models.MemberBodyStat{}).Where("mbs_id = ?", newStat.MbsID).Updates(map[string]interface{}{
				"mbs_weight":         newStat.MbsWeight,
				"mbs_height":         newStat.MbsHeight,
				"mbs_activity_level": newStat.MbsActivityLevel,
				"mbs_target":         newStat.MbsTarget,
				"mbs_recorded_date":  newStat.MbsRecordedDate,
			}).Error; err != nil {
				return err
			}
		} else {
			newStat = models.MemberBodyStat{
				MbID:             userID.(int),
				MbsWeight:        req.Weight,
				MbsHeight:        req.Height,
				MbsActivityLevel: req.ActivityLevel,
				MbsTarget:        req.Target,
				MbsRecordedDate:  now,
			}
			if err := tx.Create(&newStat).Error; err != nil {
				return err
			}
		}

		bmi, bmr, tdee, targetCal = services.CalculateGoals(
			req.Weight,
			req.Height,
			ageFromBirthDate(finalBirthDate),
			finalGender,
			req.ActivityLevel,
			req.Target,
		)

		// ORDER BY mbh_id desc + LIMIT 1 เหตุผลเดียวกับ existingStat ด้านบน
		var existingHistory models.MemberBmrHistory
		tx.Where("mb_id = ? AND mbh_record_date = ?", userID, todayStr).
			Order("mbh_id desc").Limit(1).Find(&existingHistory)

		if existingHistory.MbhID != 0 {
			return tx.Model(&models.MemberBmrHistory{}).Where("mbh_id = ?", existingHistory.MbhID).Updates(map[string]interface{}{
				"mbs_id":          newStat.MbsID,
				"mbh_bmi":         bmi,
				"mbh_bmr":         bmr,
				"mbh_tdee":        tdee,
				"mbh_tdee_target": targetCal,
			}).Error
		}

		newHistory := models.MemberBmrHistory{
			MbID:          userID.(int),
			MbsID:         &newStat.MbsID,
			MbhBmi:        bmi,
			MbhBmr:        bmr,
			MbhTdee:       tdee,
			MbhTdeeTarget: targetCal,
			MbhRecordDate: todayDate,
		}
		return tx.Create(&newHistory).Error
	})

	if err != nil {
		helpers.RespondInternalError(c, "ไม่สามารถบันทึกข้อมูลร่างกายได้")
		return
	}

	helpers.RespondSuccess(c, "อัปเดตน้ำหนักและคำนวณเป้าหมายใหม่เรียบร้อยแล้ว", gin.H{
		"bmi":        bmi,
		"bmr":        bmr,
		"tdee":       tdee,
		"target_cal": targetCal,
		"warnings":   warnings, // plausibility warning เท่านั้น ไม่ block การบันทึก
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
