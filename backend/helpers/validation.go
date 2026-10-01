package helpers

import (
	"crypto/rand"
	"fmt"
	"math"
	"math/big"
	"net/http"
	"regexp"
	"strings"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
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

// GenerateOTPCode - สุ่มรหัส OTP 6 หลัก (000000-999999) ใช้ร่วมกันทั้งสมัครสมาชิก (Register),
// ส่ง OTP ใหม่ (ResendOTP) และขอรีเซ็ตรหัสผ่าน (RequestOTP) — เดิมโค้ดสุ่มนี้อินไลน์ซ้ำ 3 จุด
// รวมมาไว้จุดเดียว ใช้ crypto/rand (ไม่ใช้ math/rand ที่เดาค่าถัดไปได้ถ้ารู้ state — OTP เป็นความลับ
// ที่ใช้ยืนยันตัวตน/รีเซ็ตรหัสผ่าน ต้องสุ่มแบบ cryptographically secure)
// อายุ OTP (5 นาทีสำหรับรีเซ็ตรหัสผ่าน, 10 นาทีสำหรับสมัคร/ยืนยันอีเมล) ยังกำหนดแยกที่ caller เอง
// เพราะแตกต่างกันจริงตามการออกแบบเดิม ไม่ใช่ความไม่สอดคล้องที่ต้องรวม
func GenerateOTPCode() string {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		panic("crypto/rand unavailable: " + err.Error())
	}
	return fmt.Sprintf("%06d", n.Int64())
}

// HashOTPCode - hash รหัส OTP ด้วย bcrypt ก่อนเก็บลง mb_otp (แก้ 2026-09-29 จากเดิมเก็บ plaintext
// ตรงๆ — DB หลุดแล้วมี OTP ที่ยังไม่หมดอายุคือยืนยันตัวตน/รีเซ็ตรหัสผ่านได้ทันที) ใช้ bcrypt แทน hash
// เร็วแบบ SHA-256 เพราะ OTP มีแค่ 1,000,000 ค่าที่เป็นไปได้ (6 หลัก) ไล่ hash เร็วครบภายในเสี้ยววินาที
// bcrypt ช้าพอที่จะทำให้ไล่ครบไม่ทันก่อน OTP หมดอายุ (5-10 นาที)
func HashOTPCode(otp string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(otp), bcrypt.DefaultCost)
	return string(hash), err
}

// CompareOTPCode - เทียบรหัส OTP ที่ผู้ใช้กรอกกับ hash ที่เก็บไว้ใน mb_otp
func CompareOTPCode(hashedOtp, otp string) bool {
	if hashedOtp == "" {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(hashedOtp), []byte(otp)) == nil
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

// ValidateTarget - ตรวจสอบเป้าหมาย (1=ลดน้ำหนัก, 2=เพิ่มน้ำหนัก, 3=รักษาน้ำหนัก เท่านั้น)
// [USED] member_controller.go (SetupProfile, UpdateWeight)
func ValidateTarget(target int) (bool, string) {
	if target < 1 || target > 3 {
		return false, "เป้าหมายต้องเป็น 1 (ลดน้ำหนัก), 2 (เพิ่มน้ำหนัก) หรือ 3 (รักษาน้ำหนัก) เท่านั้น"
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

// ValidateCardioResult - ตรวจช่วงค่าตอนบันทึกผลคาร์ดิโอ (SaveCardioResult)
// duration: 60-36000 วินาที (1 นาที - 10 ชม.) — เปลี่ยนหน่วยจาก "นาที" เป็น "วินาที" เมื่อ 2026-09-14
// (เดิมเก็บนาทีเต็มเท่านั้น ปัดเศษ 60-89 วิ เป็น "1 นาที" เท่ากันหมด คลาดเคลื่อนได้ถึง ±48% ในเซสชันสั้น)
// ขั้นต่ำ 60 วินาทียังคงไว้เหมือนเดิม — ไม่ใช่แค่กันกดพลาด แต่ MET (Compendium of Physical
// Activities) เป็นค่าที่วัดจาก steady-state VO2 กิจกรรม <1 นาที ไม่ใช่ steady-state จึงไม่มีความหมาย
// ทางสรีรวิทยาที่จะเอา MET มาคูณตรงๆ เพดาน 36000 วินาที (=600 นาทีเดิม) กันกดพลาด/ทดสอบยิงค่าประหลาด
// cardio_result.cdors_duration เป็น SMALLINT UNSIGNED เก็บได้ถึง 65535 แต่ไม่มีเซสชันจริงไหนยาวขนาดนั้น
// distance: 0-999.99 กม. ตรงเพดานจริงของคอลัมน์ cdors_distance DECIMAL(5,2) กัน DB error
// [USED] workout_controller.go (SaveCardioResult)
func ValidateCardioResult(durationSeconds int, distanceKm float64, hasDistance bool) (bool, string) {
	if durationSeconds < 60 {
		return false, "ระยะเวลาต้องไม่น้อยกว่า 1 นาที"
	}
	if durationSeconds > 36000 {
		return false, "ระยะเวลาไม่ถูกต้อง (สูงสุด 600 นาที)"
	}
	if hasDistance {
		if distanceKm < 0 {
			return false, "ระยะทางต้องไม่ติดลบ"
		}
		if distanceKm > 999.99 {
			return false, "ระยะทางไม่ถูกต้อง (สูงสุด 999.99 กม.)"
		}
	}
	return true, ""
}

// ── ขอบเขตของข้อมูลเซสชันเวทเทรนนิ่ง (ValidateWeightSession) ──
// เวลารวมคือตัวที่ทำให้ kcal เพี้ยนได้มากที่สุด: kcal เป็นเส้นตรงกับเวลารวมของเซสชัน (METs คงที่ต่อท่า
// — ดู services.CalculateWeightTrainingCalories, ../../CLAUDE.md ข้อ 7[B-1]) เวลาพักไม่ได้เข้าสูตร
// เลือก MET เลย (ไม่มี MET ให้เลือกอีกต่อไป ท่านั้นๆ ใช้ wet_mets ค่าเดียวเสมอ) เหลือหน้าที่แค่ตรวจว่า
// ค่าที่ส่งมาสมเหตุสมผลไหม ต้องกันค่าที่เป็นไปไม่ได้ตั้งแต่ชั้นรับข้อมูล ค่าเพดานด้านล่างเป็นค่าที่
// ผู้พัฒนาเลือก ไม่ได้มาจากสเปกบทที่ 2
const (
	// เวลาต่ำสุดต่อเซต: 1 เซตที่บันทึกได้จริงต้องใช้เวลาอย่างน้อยกี่วินาที (กันข้อมูลขยะจากการกดรัว)
	WeightSessionMinSecondsPerSet = 5
	// เวลารวมสูงสุดของ 1 ท่า 1 เซสชัน (2 ชม.) — ท่าเดียว 5×5 พัก 5 นาทีก็ราว 35 นาที ยาวกว่า 2 ชม.
	// เกือบแน่นอนว่าลืมกดจบ ต้องไม่เอาไปคิด kcal (wtrs_work_seconds/wtrs_rest_seconds เป็น SMALLINT UNSIGNED เก็บได้ถึง 65535)
	WeightSessionMaxSeconds = 7200
	// เวลารวมสูงสุดต่อเซต (10 นาที) — กันถ่างช่องว่างระหว่างเซตให้นานผิดปกติเพื่อยืดเวลาเซสชันได้ kcal
	// เพิ่มฟรี (เพดานเวลารวมข้างบนอย่างเดียวหลวมเกินไป: 2 เซตก็ยังยัดเข้าไปได้ถึง 7200 วิ) ใช้ 10 นาที
	// เดียวกับ _idlePromptAfter ฝั่งมือถือ (weight_training_exercise_view.dart) ซึ่งเป็นเกณฑ์ที่ระบบ
	// นิยาม "ช่องว่างระหว่างเซตผิดปกติ" ไว้อยู่แล้ว ไม่ใช่ตัวเลขใหม่ที่เดาเพิ่ม
	WeightSessionMaxSecondsPerSet = 600
	// จำนวนเซตสูงสุดต่อคำขอ (wtrs_set_no เป็น TINYINT UNSIGNED)
	WeightSessionMaxSets = 50
	// Reps สูงสุดต่อเซต ให้ตรงกับรูปแบบ Reps 3 หลักของแผนฝึก (RepsPattern)
	WeightSetMaxReps = 999
	// น้ำหนักที่ยกสูงสุด ตรงเพดานจริงของคอลัมน์ wtrs_weight DECIMAL(5,2)
	WeightSetMaxWeightKg = 999.99
	// weight_exercises.wet_equipment ของท่าบอดี้เวท (1=Barbell 2=Dumbbell 3=Machine 4=Cable 5=Bodyweight)
	EquipmentBodyweight = 5
)

// WeightSetCheck - ข้อมูลต่อเซตที่ ValidateWeightSession ตรวจ (ประกาศแยกจาก controller กัน import วน)
type WeightSetCheck struct {
	Reps        int
	WeightKg    float64
	WorkSeconds int  // เวลาที่ใช้ทำเซตนี้ (wtrs_work_seconds)
	RestSeconds *int // เวลาพักหลังเซตนี้ (wtrs_rest_seconds) nil = เซตสุดท้าย หรือไม่เคยกดพัก
}

// WeightSessionTotalSeconds - เวลารวมของเซสชัน = Σ(เวลาทำเซต + เวลาพักหลังเซต) ทุกเซต — ที่เดียวที่นิยาม
// "เวลารวม" ของเวทเทรนนิ่ง ใช้ทั้งเข้าสูตรพลังงาน ตรวจขอบเขต และตรงกับ SUM ในฐานข้อมูล/หน้าจอ
func WeightSessionTotalSeconds(sets []WeightSetCheck) int {
	total := 0
	for _, s := range sets {
		total += s.WorkSeconds
		if s.RestSeconds != nil {
			total += *s.RestSeconds
		}
	}
	return total
}

// ValidateWeightSession - ตรวจความสมเหตุสมผลของเวลาและเซตตอนบันทึกผลเวทเทรนนิ่ง (SaveWorkoutResult)
// ตอบ false พร้อมข้อความเมื่อค่าเป็นไปไม่ได้ ไม่แก้ค่าเงียบๆ (ต่างจากการตัดเพดานในสูตร) เพื่อไม่ให้ผลคำนวณ
// ถูกปรับโดยที่ผู้ใช้ไม่รู้ — ลำดับ: จำนวนเซต → เวลารวม → แต่ละเซต → ผลรวมเวลาพัก
// hasWeight/hasReps คุมตาม UI ของท่านั้น (2 กฎแยกกันไม่ทับซ้อน ดู models.WeightExercise.WetIsTimed):
//   hasWeight=false (wet_equipment=5 Bodyweight) → ไม่มีช่องกรอกน้ำหนัก ทุกเซตต้องเป็นน้ำหนัก 0
//   hasReps=false (wet_is_timed=true เช่น Plank) → ไม่มีช่องกรอกจำนวนครั้ง ทุกเซตต้องเป็น Reps 0
// (0 = ไม่ได้บันทึก ไม่ใช่ "ทำ 0 ครั้ง") พลังงานคิดจาก METs ของท่า × เวลารวมอย่างเดียวอยู่แล้ว ไม่ใช้ทั้งคู่
// [USED] workout_controller.go (SaveWorkoutResult)
func ValidateWeightSession(sets []WeightSetCheck, hasWeight bool, hasReps bool) (bool, string) {
	totalDurationSeconds := WeightSessionTotalSeconds(sets)
	if len(sets) < 1 {
		return false, "ต้องมีอย่างน้อย 1 เซต"
	}
	if len(sets) > WeightSessionMaxSets {
		return false, fmt.Sprintf("จำนวนเซตไม่ถูกต้อง (สูงสุด %d เซต)", WeightSessionMaxSets)
	}
	if totalDurationSeconds < len(sets)*WeightSessionMinSecondsPerSet {
		return false, "เวลารวมสั้นเกินไปเมื่อเทียบกับจำนวนเซต กรุณาตรวจสอบเวลาการฝึก"
	}
	if totalDurationSeconds > WeightSessionMaxSeconds {
		return false, fmt.Sprintf("เวลารวมยาวผิดปกติ (สูงสุด %d นาทีต่อท่า) อาจลืมกดจบการฝึก", WeightSessionMaxSeconds/60)
	}
	if totalDurationSeconds > len(sets)*WeightSessionMaxSecondsPerSet {
		return false, fmt.Sprintf("เวลารวมยาวผิดปกติเมื่อเทียบกับจำนวนเซต (สูงสุด %d นาทีต่อเซต) อาจลืมกดจบการฝึกหรือช่องว่างระหว่างเซตนานเกินไป", WeightSessionMaxSecondsPerSet/60)
	}
	for _, s := range sets {
		if s.WorkSeconds < 1 {
			return false, "เวลาทำเซตไม่ถูกต้อง (ต้องมากกว่า 0 วินาที)"
		}
		if hasReps {
			if s.Reps < 1 || s.Reps > WeightSetMaxReps {
				return false, fmt.Sprintf("จำนวนครั้งต้องอยู่ระหว่าง 1-%d", WeightSetMaxReps)
			}
		} else if s.Reps != 0 {
			return false, "ท่านี้ไม่ต้องบันทึกจำนวนครั้ง"
		}
		if !hasWeight && s.WeightKg != 0 {
			return false, "ท่านี้ไม่ต้องบันทึกน้ำหนัก"
		}
		if s.WeightKg < 0 || s.WeightKg > WeightSetMaxWeightKg {
			return false, fmt.Sprintf("น้ำหนักที่ยกต้องอยู่ระหว่าง 0-%.2f กก.", WeightSetMaxWeightKg)
		}
		if s.RestSeconds != nil {
			if *s.RestSeconds < 0 {
				return false, "เวลาพักไม่ถูกต้อง (ติดลบ)"
			}
		}
	}
	return true, ""
}

// ValidateNutritionMacros - ตรวจช่วงค่าพลังงาน/สารอาหารของ nutrition (V3)
// calories: 0-9000 kcal, protein/carbs/fat: 0-1000 g, serving_weight: 0.1-5000
func ValidateNutritionMacros(calories, protein, carbs, fat float64, servingWeight int) (bool, string) {
	if calories < 0 || calories > 9000 {
		return false, "พลังงานต้องอยู่ระหว่าง 0-9000 kcal"
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

// NutritionMacroMismatchWarning - เตือน (ไม่บล็อก) ถ้าพลังงานที่กรอกต่างจากที่คำนวณจาก
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
		return fmt.Sprintf("พลังงานที่กรอก (%.0f kcal) ต่างจากค่าที่คำนวณจากสารอาหาร (%.0f kcal) เกิน 10%%", calories, computed)
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

// RepsPattern - รูปแบบ "จำนวนครั้ง" ที่ยอมรับทั้ง plan_template_detail (ptd_reps, ฝั่งแอดมิน) และ
// workout_schedules (wsch_reps, ฝั่งสมาชิกแก้แผนส่วนตัวเอง) — เลขเดี่ยว "12" หรือช่วง "8-12" เท่านั้น
var RepsPattern = regexp.MustCompile(`^\d{1,3}(-\d{1,3})?$`)

// planTemplateDetail คือ interface กลางเพื่อไม่ให้ helpers ต้อง import models (กัน import cycle)
type planTemplateDetail interface {
	GetPtdDayNumber() int
	GetPtdDayName() string
	GetPtdSets() int
	GetPtdReps() string
	GetPtdRestSeconds() int
}

// ValidatePlanTemplateDetail - ตรวจ ptd_day_number/ptd_day_name/ptd_sets/ptd_reps/ptd_rest_seconds (สเปกข้อ 3.8)
// dayNumber ต้อง 1-7 และ <= wptDaysPerWeek ของแผนนั้น (กฎนี้เดิมไม่มีการเช็คฝั่ง server เลย)
func ValidatePlanTemplateDetail(d planTemplateDetail, wptDaysPerWeek int) (bool, string) {
	day := d.GetPtdDayNumber()
	if day < 1 || day > 7 {
		return false, "วันที่ฝึกต้องอยู่ระหว่าง 1-7"
	}
	if strings.TrimSpace(d.GetPtdDayName()) == "" {
		return false, "กรุณาระบุชื่อวัน"
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
	if reps := d.GetPtdReps(); reps != "" && !RepsPattern.MatchString(reps) {
		return false, "รูปแบบจำนวนครั้งไม่ถูกต้อง (เช่น \"12\" หรือ \"8-12\")"
	}
	return true, ""
}

// ValidateScheduleSetsReps - ตรวจ wsch_sets/wsch_reps ตอนสมาชิกแก้ไข/เพิ่มท่าในแผนส่วนตัวเอง
// (CreateWorkoutSchedule, UpdateWorkoutSchedule) ใช้ช่วงเซต 1-20 และ pattern reps เดียวกับ
// ValidatePlanTemplateDetail ข้างบน (ptd_sets/ptd_reps ของแผนระบบ) ให้ทั้งสองทางบันทึกข้อมูล
// สอดคล้องกัน — ไม่ต้องเป็น pointer เพราะจุดที่เรียกรู้ค่าที่จะเช็คแน่นอนอยู่แล้ว (ไม่ใช่ optional patch field)
func ValidateScheduleSetsReps(sets int, reps string) (bool, string) {
	if sets < 1 || sets > 20 {
		return false, "จำนวนเซ็ตต้องอยู่ระหว่าง 1-20"
	}
	if reps != "" && !RepsPattern.MatchString(reps) {
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
