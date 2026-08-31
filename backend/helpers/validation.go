package helpers

import (
	"fmt"
	"math"
	"net/http"
	"regexp"

	"github.com/gin-gonic/gin"
)

// ========================================
// Validation Functions
// ========================================

// ValidateEmail - ตรวจสอบรูปแบบ Email ด้วย regex
// [USED] password_controller.go (ForgotPassword)
func ValidateEmail(email string) bool {
	const emailRegex = `^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`
	re := regexp.MustCompile(emailRegex)
	return re.MatchString(email)
}

// ValidatePassword - ตรวจสอบความยาวรหัสผ่าน (8-100 ตัวอักษร)
// [USED] password_controller.go (ResetPassword, ChangePassword)
func ValidatePassword(password string) (bool, string) {
	if len(password) < 8 {
		return false, "รหัสผ่านต้องมีความยาวอย่างน้อย 8 ตัวอักษร"
	}
	if len(password) > 100 {
		return false, "รหัสผ่านต้องไม่เกิน 100 ตัวอักษร"
	}
	return true, ""
}

// ValidateOTP - ตรวจสอบรูปแบบ OTP (ตัวเลข 6 หลักเท่านั้น)
// [USED] auth_controller.go (VerifyEmail), password_controller.go (ResetPassword)
func ValidateOTP(otp string) (bool, string) {
	if len(otp) != 6 {
		return false, "รหัส OTP ต้องมี 6 หลัก"
	}
	matched, _ := regexp.MatchString(`^\d{6}$`, otp)
	if !matched {
		return false, "รหัส OTP ต้องเป็นตัวเลขเท่านั้น"
	}
	return true, ""
}

// ValidateGender - ตรวจสอบเพศ (1=ชาย, 2=หญิง เท่านั้น)
// [USED] member_controller.go (SetupProfile, EditProfile)
func ValidateGender(gender int) (bool, string) {
	if gender != 1 && gender != 2 {
		return false, "เพศต้องเป็น 1 (ชาย) หรือ 2 (หญิง) เท่านั้น"
	}
	return true, ""
}

// validActivityFactors - 5 ค่ามาตรฐานเท่านั้น (ห้ามแก้ตัวเลขชุดนี้ ต้องตรงกับ
// _activityFactors ใน lib/core/utils/health_calculations.dart ฝั่ง frontend เสมอ — D9)
var validActivityFactors = []float64{1.2, 1.375, 1.55, 1.725, 1.9}

const activityFactorEpsilon = 0.0001

// ValidateActivityLevel - ตรวจสอบระดับกิจกรรม ต้องตรงกับ 1 ใน 5 ค่ามาตรฐานเท่านั้น
// (เดิมเช็คแค่ช่วง 1.2-1.9 ทำให้ค่ากลางๆ เช่น 1.6 ผ่านได้ทั้งที่ Activity Factor ตามบทที่ 2
// มีแค่ 5 ระดับ ไม่ใช่ค่าต่อเนื่อง — D9 แก้แล้ว 2026-08-21 ตามมติทีม) เทียบด้วย epsilon
// เพราะ float ห้าม compare ตรงๆ (decimal(4,3) จาก DB กับ float64 จาก JSON อาจมีเศษปัดต่างกันเล็กน้อย)
// [USED] member_controller.go (UpdateProfile, UpdateBodyStats)
func ValidateActivityLevel(level float64) (bool, string) {
	for _, v := range validActivityFactors {
		if math.Abs(level-v) < activityFactorEpsilon {
			return true, ""
		}
	}
	return false, "ระดับกิจกรรมต้องเป็น 1 ใน 5 ระดับมาตรฐานเท่านั้น (1.2, 1.375, 1.55, 1.725, 1.9)"
}

// ValidateTarget - ตรวจสอบเป้าหมาย (1=ลดน้ำหนัก, 2=เพิ่มกล้ามเนื้อ, 3=รักษาน้ำหนัก เท่านั้น)
// [USED] member_controller.go (SetupProfile, UpdateWeight)
func ValidateTarget(target int) (bool, string) {
	if target < 1 || target > 3 {
		return false, "เป้าหมายต้องเป็น 1 (ลดน้ำหนัก), 2 (เพิ่มกล้ามเนื้อ) หรือ 3 (รักษาน้ำหนัก) เท่านั้น"
	}
	return true, ""
}

// ValidateWeight - ตรวจสอบน้ำหนัก (20-300 กก.)
// [USED] member_controller.go (SetupProfile, UpdateWeight)
func ValidateWeight(weight float64) (bool, string) {
	if weight < 20 {
		return false, "น้ำหนักต้องไม่น้อยกว่า 20 กก."
	}
	if weight > 300 {
		return false, "น้ำหนักไม่ถูกต้อง (สูงสุด 300 กก.)"
	}
	return true, ""
}

// ValidateHeight - ตรวจสอบส่วนสูง (50-250 ซม.)
// [USED] member_controller.go (SetupProfile)
func ValidateHeight(height float64) (bool, string) {
	if height < 50 {
		return false, "ส่วนสูงต้องไม่น้อยกว่า 50 ซม."
	}
	if height > 250 {
		return false, "ส่วนสูงไม่ถูกต้อง (สูงสุด 250 ซม.)"
	}
	return true, ""
}

// ValidateNutritionMacros - ตรวจช่วงค่าพลังงาน/สารอาหารของ nutrition (V3)
// calories: 0-9000 kcal, protein/carbs/fat: 0-1000 g, serving_weight: 0.1-5000
func ValidateNutritionMacros(calories, protein, carbs, fat float64, servingWeight int) (bool, string) {
	if calories < 0 || calories > 9000 {
		return false, "แคลอรี่ต้องอยู่ระหว่าง 0-9000 kcal"
	}
	if protein < 0 || protein > 1000 {
		return false, "โปรตีนต้องอยู่ระหว่าง 0-1000 กรัม"
	}
	if carbs < 0 || carbs > 1000 {
		return false, "คาร์โบไฮเดรตต้องอยู่ระหว่าง 0-1000 กรัม"
	}
	if fat < 0 || fat > 1000 {
		return false, "ไขมันต้องอยู่ระหว่าง 0-1000 กรัม"
	}
	if servingWeight < 1 || servingWeight > 5000 {
		return false, "น้ำหนักต่อหน่วยบริโภคต้องอยู่ระหว่าง 0.1-5000"
	}
	return true, ""
}

// NutritionMacroMismatchWarning - เตือน (ไม่บล็อก) ถ้าแคลอรี่ที่กรอกต่างจากที่คำนวณจาก
// P×4+C×4+F×9 เกิน 10% — คืน string ว่างถ้าไม่มีอะไรผิดปกติ
func NutritionMacroMismatchWarning(calories, protein, carbs, fat float64) string {
	if calories <= 0 {
		return ""
	}
	computed := protein*4 + carbs*4 + fat*9
	if computed <= 0 {
		return ""
	}
	diffPct := math.Abs(calories-computed) / calories * 100
	if diffPct > 10 {
		return fmt.Sprintf("แคลอรี่ที่กรอก (%.0f kcal) ต่างจากค่าที่คำนวณจากสารอาหาร (%.0f kcal) เกิน 10%%", calories, computed)
	}
	return ""
}

// ValidateWorkoutPlanTemplate - ตรวจ wpt_days_per_week (1-7) และ wpt_difficulty (1-3) ตามสเปกข้อ 3.8
func ValidateWorkoutPlanTemplate(daysPerWeek int, difficulty int) (bool, string) {
	if daysPerWeek < 1 || daysPerWeek > 7 {
		return false, "จำนวนวันฝึกต่อสัปดาห์ต้องอยู่ระหว่าง 1-7"
	}
	if difficulty < 1 || difficulty > 3 {
		return false, "ระดับความยากต้องเป็น 1, 2 หรือ 3 เท่านั้น"
	}
	return true, ""
}

// ValidateWeightExerciseCodes - ตรวจรหัสตัวเลขของ weight_exercises ตาม V5 (whitelist ค่าที่อนุญาต)
// difficulty: 1-3, equipment: 1-5, exerciseType: 1-2
func ValidateWeightExerciseCodes(difficulty, equipment, exerciseType int) (bool, string) {
	if difficulty < 1 || difficulty > 3 {
		return false, "ระดับความยากต้องเป็น 1, 2 หรือ 3 เท่านั้น"
	}
	if equipment < 1 || equipment > 5 {
		return false, "อุปกรณ์ต้องเป็นค่า 1-5 เท่านั้น"
	}
	if exerciseType < 1 || exerciseType > 2 {
		return false, "ประเภทท่าฝึกต้องเป็น 1 หรือ 2 เท่านั้น"
	}
	return true, ""
}

// ValidateMuscleGroupZone - ตรวจ mug_zone ตาม V5 (1-3 เท่านั้น)
func ValidateMuscleGroupZone(zone int) (bool, string) {
	if zone < 1 || zone > 3 {
		return false, "โซนกล้ามเนื้อต้องเป็น 1, 2 หรือ 3 เท่านั้น"
	}
	return true, ""
}

var ptdRepsPattern = regexp.MustCompile(`^\d{1,3}(-\d{1,3})?$`)

// planTemplateDetail คือ interface กลางเพื่อไม่ให้ helpers ต้อง import models (กัน import cycle)
type planTemplateDetail interface {
	GetPtdDayNumber() int
	GetPtdSets() int
	GetPtdReps() string
	GetPtdRestSeconds() int
}

// ValidatePlanTemplateDetail - ตรวจ ptd_day_number/ptd_sets/ptd_reps/ptd_rest_seconds (สเปกข้อ 3.8)
// dayNumber ต้อง 1-7 และ <= wptDaysPerWeek ของแผนนั้น (กฎนี้เดิมไม่มีการเช็คฝั่ง server เลย)
func ValidatePlanTemplateDetail(d planTemplateDetail, wptDaysPerWeek int) (bool, string) {
	day := d.GetPtdDayNumber()
	if day < 1 || day > 7 {
		return false, "วันที่ฝึกต้องอยู่ระหว่าง 1-7"
	}
	if wptDaysPerWeek > 0 && day > wptDaysPerWeek {
		return false, fmt.Sprintf("วันที่ฝึก (%d) เกินจำนวนวันฝึกต่อสัปดาห์ของแผนนี้ (%d วัน)", day, wptDaysPerWeek)
	}
	sets := d.GetPtdSets()
	if sets < 1 || sets > 20 {
		return false, "จำนวนเซตต้องอยู่ระหว่าง 1-20"
	}
	rest := d.GetPtdRestSeconds()
	if rest < 0 || rest > 600 {
		return false, "เวลาพักต้องอยู่ระหว่าง 0-600 วินาที"
	}
	if reps := d.GetPtdReps(); reps != "" && !ptdRepsPattern.MatchString(reps) {
		return false, "รูปแบบจำนวนครั้งไม่ถูกต้อง (เช่น \"12\" หรือ \"8-12\")"
	}
	return true, ""
}

// ========================================
// Response Helpers
// ========================================

// RespondBadRequest - ส่ง HTTP 400 พร้อม field ที่มีปัญหาและข้อความ error
// [USED] password_controller.go, member_controller.go
func RespondBadRequest(c *gin.Context, field, message string) {
	c.JSON(http.StatusBadRequest, gin.H{
		"error": message,
		"field": field,
	})
}

// RespondUnauthorized - ส่ง HTTP 401
// [USED] password_controller.go, member_controller.go
func RespondUnauthorized(c *gin.Context, message string) {
	c.JSON(http.StatusUnauthorized, gin.H{"error": message})
}

// RespondNotFound - ส่ง HTTP 404
// [USED] password_controller.go, member_controller.go
func RespondNotFound(c *gin.Context, message string) {
	c.JSON(http.StatusNotFound, gin.H{"error": message})
}

// RespondInternalError - ส่ง HTTP 500
// [USED] password_controller.go, member_controller.go
func RespondInternalError(c *gin.Context, message string) {
	c.JSON(http.StatusInternalServerError, gin.H{"error": message})
}

// RespondSuccess - ส่ง HTTP 200 พร้อม message และ data (ส่ง nil ได้ถ้าไม่มี data)
// [USED] password_controller.go, member_controller.go
func RespondSuccess(c *gin.Context, message string, data interface{}) {
	c.JSON(http.StatusOK, gin.H{
		"message": message,
		"data":    data,
	})
}
