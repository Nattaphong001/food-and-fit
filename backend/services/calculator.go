package services

import (
	"math"
)

// ═══════════════════════════════════════════════════════════════════════
// 1. BMI / BMR / TDEE / Target Calories — CalculateGoals
// ═══════════════════════════════════════════════════════════════════════

// CalculateGoals คำนวณ BMI, BMR, TDEE, Target Calories จากข้อมูลร่างกาย+เป้าหมาย ทีเดียวครบชุด
// (ค่าที่ได้ ปัดทศนิยม 2 ตำแหน่งก่อนคืนค่าทุกตัว)
//
// ตัวแปร: weight=น้ำหนัก(kg), height=ส่วนสูง(cm), age=อายุ(ปี), gender=เพศ(1=ชาย),
// activityLevel=ตัวคูณระดับกิจกรรม, target=เป้าหมาย(1=ลด 2=เพิ่ม 3=รักษา)
func CalculateGoals(weight, height float64, age, gender int, activityLevel float64, target int) (bmi, bmr, tdee, targetCalories float64) {
	// BMI = น้ำหนัก(kg) ÷ ส่วนสูง(m)²
	heightInMeters := height / 100
	bmi = weight / (heightInMeters * heightInMeters)

	// BMR (พลังงานพื้นฐานที่ร่างกายใช้ตอนพักนิ่ง) สูตร Mifflin-St Jeor แยกสูตรชาย/หญิง
	if gender == 1 { // ชาย
		bmr = (10 * weight) + (6.25 * height) - float64(5*age) + 5
	} else { // หญิง
		bmr = (10 * weight) + (6.25 * height) - float64(5*age) - 161
	}

	// TDEE (พลังงานที่ใช้จริงต่อวันรวมกิจกรรม) = BMR × ตัวคูณระดับกิจกรรม (1.2 / 1.375 / 1.55 / 1.725 / 1.9)
	tdee = bmr * activityLevel

	// Target Calories: เป้าหมายพลังงานต่อวันตามเป้าหมายที่เลือก (1=ลดน้ำหนัก, 2=เพิ่มน้ำหนัก, 3=รักษาน้ำหนัก)
	switch target {
	case 1: // ลดน้ำหนัก = ลด TDEE ลง 20% แต่ห้ามต่ำกว่า BMR (กันกินน้อยเกินไปจนเป็นอันตราย)
		targetCalories = tdee - (tdee * 0.20)
		if targetCalories < bmr {
			targetCalories = bmr
		}
	case 2: // เพิ่มน้ำหนัก = เพิ่ม TDEE ขึ้น 15%
		targetCalories = tdee + (tdee * 0.15)
	default: // รักษาน้ำหนัก = เท่ากับ TDEE พอดี
		targetCalories = tdee
	}

	return math.Round(bmi*100) / 100, math.Round(bmr*100) / 100, math.Round(tdee*100) / 100, math.Round(targetCalories*100) / 100
}

// ═══════════════════════════════════════════════════════════════════════
// 2. Baseline Expenditure — CalculateBaselineExpenditure
// ═══════════════════════════════════════════════════════════════════════

// SedentaryCoefficient: ตัวคูณคงที่คำนวณ Baseline Expenditure จาก BMR (ไม่ใช่ activity level ของผู้ใช้)
const SedentaryCoefficient = 1.2

// ค่าประมาณ (fallback) ใช้ตอนสมาชิกยังไม่มีประวัติ BMR/TDEE เลย — ใช้ร่วมกันทั้ง Go และ SQL
// (ผ่าน sqlConstReplacer ใน analytics_service.go) ห้ามพิมพ์ตัวเลขซ้ำที่อื่น
const (
	FallbackBmr        = 1500.0 // BMR ประมาณ (kcal)
	FallbackTdee       = 1800.0 // TDEE ประมาณ (kcal)
	FallbackTargetTdee = 2000.0 // เป้าหมายพลังงานประมาณ (kcal)
)

// CalculateBaselineExpenditure คำนวณ Baseline Expenditure (พลังงานพื้นฐานตอนพัก ไม่รวมออกกำลังกาย)
// จาก BMR — ใช้ตัวคูณคงที่ 1.2 เสมอ
func CalculateBaselineExpenditure(bmr float64) float64 {
	return bmr * SedentaryCoefficient
}

// ═══════════════════════════════════════════════════════════════════════
// 2b. สัดส่วนสารอาหารมหัพภาค (Macronutrient Distribution) — CalculateMacroTargets
// ═══════════════════════════════════════════════════════════════════════
// สัดส่วนโปรตีน:คาร์บ:ไขมัน คงที่ต่อเป้าหมาย
type macroPercent struct{ protein, carb, fat float64 }

// สัดส่วน % ต่อเป้าหมาย goalType: 1=ลดน้ำหนัก, 2=เพิ่มน้ำหนัก, 3=รักษาน้ำหนัก
var macroPercentByGoal = map[int]macroPercent{
	1: {protein: 0.40, carb: 0.35, fat: 0.25},
	2: {protein: 0.30, carb: 0.50, fat: 0.20},
	3: {protein: 0.20, carb: 0.50, fat: 0.30},
}

// CalculateMacroTargets แปลง Target Calories เป็นกรัมโปรตีน/คาร์บ/ไขมัน ตามสัดส่วนของเป้าหมาย
// โปรตีน/คาร์บ = ปริมาณพลังงาน ÷ 4 (kcal ต่อกรัม), ไขมัน = ปริมาณพลังงาน ÷ 9
// goalType ที่ไม่ใช่ 1/2/3 หรือ targetCalories <= 0 → คืน 0 ทั้ง 3 ค่า (ไม่รู้จักเป้าหมาย ไม่เดาให้)
func CalculateMacroTargets(targetCalories float64, goalType int) (proteinG, carbG, fatG float64) {
	pct, ok := macroPercentByGoal[goalType]
	if !ok || targetCalories <= 0 {
		return 0, 0, 0
	}
	proteinG = targetCalories * pct.protein / 4
	carbG = targetCalories * pct.carb / 4
	fatG = targetCalories * pct.fat / 9
	return math.Round(proteinG*100) / 100, math.Round(carbG*100) / 100, math.Round(fatG*100) / 100
}

// ═══════════════════════════════════════════════════════════════════════
// 3. Estimated 1RM — EstimateOneRepMax
// ═══════════════════════════════════════════════════════════════════════

// ระบบสลับสมการแบบไดนามิก (Dynamic Dual-Formula Model, บทที่ 2 ข้อ 2.1.4.10) — ใช้ร่วมกันทั้ง Go และ SQL
// (ผ่าน OneRepMaxSQL ใน analytics_service.go) ห้ามพิมพ์ตัวเลขซ้ำที่อื่น
const (
	EpleyMaxReps     = 10 // Epley ใช้กับ reps 1-10 (ช่วงจำนวนครั้งต่ำถึงปานกลาง)
	DesgorcesMaxReps = 20 // Desgorces ใช้กับ reps 11-20 (ช่วงจำนวนครั้งสูง) เกิน 20 ไม่ประเมิน 1RM

	EpleyDivisor = 30.0 // Epley: W × (1 + r/30)

	// Desgorces et al. (2553): 1RM = 100W / (83.7677 × e^(−0.0338r) + 17.6846)
	DesgorcesNumerator = 100.0
	DesgorcesA         = 83.7677
	DesgorcesB         = 0.0338
	DesgorcesC         = 17.6846
)

// EstimateOneRepMax - Estimated 1RM แบบ Dual-Formula
//   - reps 1-10  → สมการเอพลีย์ (Epley): W × (1 + r/30)
//   - reps 11-20 → สมการเดสกอร์ส (Desgorces): 100W / (83.7677 × e^(−0.0338r) + 17.6846)
//   - reps > 20, reps < 1 หรือน้ำหนัก ≤ 0 → 0 (ประเมินไม่ได้)
//
// 1RM = น้ำหนักสูงสุดที่ยกได้ 1 ครั้ง (ประมาณจากเซตที่ยกหลายครั้ง)
// weightKg=น้ำหนักที่ยก, reps=จำนวนครั้งที่ทำได้
func EstimateOneRepMax(weightKg float64, reps int) float64 {
	if weightKg <= 0 || reps < 1 || reps > DesgorcesMaxReps {
		return 0
	}
	var est float64
	if reps <= EpleyMaxReps {
		est = weightKg * (1 + float64(reps)/EpleyDivisor)
	} else {
		est = DesgorcesNumerator * weightKg / (DesgorcesA*math.Exp(-DesgorcesB*float64(reps)) + DesgorcesC)
	}
	return math.Round(est*100) / 100
}

// ═══════════════════════════════════════════════════════════════════════
// NetEnergyKcal คือสูตรแกนกลาง (ACSM) — จุดคำนวณพลังงานเพียงจุดเดียวของทั้งระบบ
// ═══════════════════════════════════════════════════════════════════════
// คาร์ดิโอ เเละ เวทเทรนนิ่ง จะใช้ Net Energy Kcal ร่วมกัน
//
// Net Energy Kcal คำนวณพลังงานสุทธิที่เผาผลาญจริง (ไม่รวมพลังงานพักนิ่งที่ Baseline BMR × 1.2 นับไปแล้ว)
// สูตร ACSM: Kcal (NET) = [(METs − 1) × 3.5 × น้ำหนักตัว(kg) / 200] × ระยะเวลา(นาที)
func NetEnergyKcal(mets, bodyWeightKg, minutes float64) float64 {
	const metOxygenMlPerKgPerMin = 3.5 // ออกซิเจนที่ใช้ตอนพัก (1 MET) หน่วย ml/kg/นาที
	const metKcalDivisor = 200.0       // ตัวหารแปลงเป็น kcal/นาที

	// หัก 1 MET ออกก่อน (คือพลังงานตอนพักนิ่งที่ถูกนับใน Baseline ไปแล้ว กันนับซ้ำ)
	netMets := mets - 1
	if netMets < 0 {
		netMets = 0 // METs ≤ 1 ถือว่าไม่เผาผลาญพลังงานเพิ่มเลย (กันค่าติดลบ)
	}
	return (netMets * metOxygenMlPerKgPerMin * bodyWeightKg / metKcalDivisor) * minutes
}

// ═══════════════════════════════════════════════════════════════════════
// 4. พลังงานเวทเทรนนิ่ง — Dynamic METs ตาม %1RM (บทที่ 2 ข้อ 2.1.4.10 ตารางที่ 2.2)
// ═══════════════════════════════════════════════════════════════════════

// ค่า METs จาก 2024 Adult Compendium of Physical Activities (Herrmann et al., 2567) ตามตารางที่ 2.2
const (
	MetsBodyweight = 3.0 // น้ำหนักถ่วง = 0 ในท่าที่ใช้อุปกรณ์ — Compendium 02056 บอดี้เวททั่วไป
	MetsEndurance  = 3.5 // ความทนทานของกล้ามเนื้อ (%1RM < 70) หรือ reps > 20 — Compendium 02054
	MetsHeavy      = 6.0 // เพิ่มขนาดกล้ามเนื้อ/ความแข็งแรง (%1RM ≥ 70) — Compendium 02050

	// ท่าบอดี้เวท/ท่าค้างเวลา แยกตาม wet_difficulty (Compendium 2024, Herrmann et al., 2567)
	MetsBodyweightLight    = 2.8 // ความยาก 1 (Crunch, Plank) — 02024 calisthenics ออกแรงเบา
	MetsBodyweightModerate = 3.8 // ความยาก 2-3 (Pull-up, Dips, Hanging Leg Raise) — 02022 calisthenics ปานกลาง

	// เกณฑ์ตัดระดับความหนัก: ตัดที่ 70% จุดเดียว = ขอบล่างระดับ Vigorous (70-84%) ของ Garber et al. (2554,
	// ตารางที่ 5, น. 1341) ใกล้เคียงขอบ 67% ของตารางที่ 2.1 (NSCA) — ต่ำกว่า = 02054, ตั้งแต่ 70% ขึ้นไป = 02050
	HeavyIntensityPercent = 70.0
	MaxIntensityPercent   = 100.0 // ยกเกิน 1RM อ้างอิง (ทำสถิติใหม่) ถือเป็น 100%

	intensityEpsilon = 1e-9 // ความคลาดเคลื่อนของ float ตอนเทียบ %1RM กับเกณฑ์ (ดู WeightSetMets)
)

// WeightSetMets เลือก METs ของเซตเดียว
//   - hasWeight=false หรือ hasReps=false หรือน้ำหนัก ≤ 0 → MetsBodyweight (ไม่มี 1RM ให้คำนวณ)
//   - reps > 20 → MetsEndurance (เกินขอบเขตสมการ 1RM)
//   - ไม่มี 1RM อ้างอิง → MetsEndurance
//   - %1RM = (W / 1RM อ้างอิง) × 100 → ≥ 70 = MetsHeavy, < 70 = MetsEndurance
func WeightSetMets(weightKg float64, reps int, reference1RM float64, hasWeight, hasReps bool) float64 {
	if !hasWeight || !hasReps || weightKg <= 0 {
		return MetsBodyweight
	}
	if reps > DesgorcesMaxReps || reference1RM <= 0 {
		return MetsEndurance
	}
	pct := math.Min(weightKg/reference1RM*100, MaxIntensityPercent)
	// ทน float คลาดเคลื่อนที่จุดตัดพอดี: W / ref × 100 บางคู่ที่ควรได้ 70.00 พอดี (เช่น 5.81 ÷ 8.30) ออกมา 69.999… ตกไป 3.5
	// ทั้งที่สเปกให้ ≥ 70 = 6.0 — ค่าจริงเป็นทศนิยม 2 ตำแหน่ง ห่างจากจุดตัดที่ใกล้ที่สุดมากกว่า epsilon นี้หลายเท่า จึงไม่กระทบเคสอื่น
	if pct >= HeavyIntensityPercent-intensityEpsilon {
		return MetsHeavy
	}
	return MetsEndurance
}

// BodyweightMets เลือก METs ของท่าบอดี้เวท/ท่าค้างเวลา ตามระดับความยากของท่า (wet_difficulty)
// ความยาก 1 → 2.8 (02024) · ความยาก 2-3 หรือค่าอื่น → 3.8 (02022)
// ไม่ใช้ 02020/02057 (7.5/6.5) เพราะเป็นค่าของ circuit ต่อเนื่อง ระบบแยกไม่ได้ว่าผู้ใช้ทำแบบนั้น
func BodyweightMets(difficulty int) float64 {
	if difficulty <= 1 {
		return MetsBodyweightLight
	}
	return MetsBodyweightModerate
}

// WeightSetEnergyInput ข้อมูล 1 เซตที่เข้าสูตรพลังงาน
type WeightSetEnergyInput struct {
	WeightKg float64 // น้ำหนักที่ยก (kg)
	Reps     int     // จำนวนครั้ง
	Seconds  int     // เวลาของเซตนี้ = เวลาทำเซต + เวลาพักหลังเซต (วินาที)
	// ผู้ใช้ยืนยันว่าเซตนี้ยกจนใกล้หมดแรง (เหลือแรงยกต่อได้ไม่เกิน 2-3 ครั้ง) — ใช้เฉพาะเลือกตัวอ้างอิงตอนไม่มี PR
	NearFailure bool
}

// SessionReferenceOneRepMax หา 1RM อ้างอิง "ครั้งแรกของท่า" (ยังไม่มีประวัติ PR) — ได้ค่าเดียวใช้ร่วมกันทั้งเซสชัน
//
//	ขั้นที่ 1: ดูเฉพาะเซตที่ผู้ใช้กด "หมดแรง" (NearFailure) เซตที่ไม่ได้กดไม่ถูกนับ
//	ขั้นที่ 2: หา Estimated 1RM ของแต่ละเซตนั้นด้วย EstimateOneRepMax (reps 1-10 Epley, 11-20 Desgorces)
//	ขั้นที่ 3: เลือกค่าที่ "สูงที่สุด" ค่าเดียวเป็นตัวอ้างอิง (คืน 0 ถ้าไม่มีเซตที่นับได้)
//
// เซตที่ไม่นับ: reps > 20 (ประเมิน 1RM ไม่ได้), น้ำหนัก ≤ 0, หรือผู้ใช้ไม่ได้กดหมดแรง
// ตัวอย่าง: 40×12 (หมดแรง, e1RM 54.4) + 50×10 (หมดแรง, e1RM 66.7) → ตัวอ้างอิง = 66.7
// ค่านี้ถูกนำไปหารน้ำหนักของ "ทุกเซต" ใน WeightSetMets (%1RM = น้ำหนักเซตนั้น ÷ ตัวอ้างอิงนี้)
// ข้อจำกัด: คำตอบหมดแรงเป็นการประเมินของผู้ใช้เอง ระบบตรวจสอบไม่ได้ (ต้องระบุในเล่ม)
func SessionReferenceOneRepMax(sets []WeightSetEnergyInput) float64 {
	best := 0.0
	for _, s := range sets {
		if s.WeightKg <= 0 || !s.NearFailure {
			continue
		}
		if est := EstimateOneRepMax(s.WeightKg, s.Reps); est > best {
			best = est
		}
	}
	return best
}

// ReferenceOneRepMax แหล่งที่มาของ 1RM อ้างอิง (ตรงกับ response calculation.reference_source)
const (
	ReferenceHistory         = "history"          // PR ก่อนเซสชันนี้
	ReferenceSession         = "session"          // e1RM สูงสุดของเซตที่ผู้ใช้ยืนยันว่ายกใกล้หมดแรง
	ReferenceSessionDeclined = "session_declined" // ไม่มี PR และผู้ใช้ไม่ยืนยัน/ไม่ตอบ → ไม่ใช้ตัวอ้างอิง
	ReferenceNone            = "none"             // ไม่มีเซตที่ประเมิน 1RM ได้ (ทุกเซต reps > 20)
	ReferenceNotApplicable   = "not_applicable"   // บอดี้เวท/ท่าค้างเวลา
)

// ResolveReferenceOneRepMax เลือก "1RM อ้างอิง" ที่ใช้เป็นตัวหารของ %1RM (แก้ 2026-10-02 รอบ 3 — ถามรายเซต)
// มีค่าเดียวต่อเซสชัน ใช้ร่วมกันทุกเซต เลือกตามลำดับนี้:
//
//	1) ท่านี้มีประวัติแล้ว (history > 0)     → ใช้ PR เดิม ไม่สนใจคำตอบหมดแรง
//	                                           (เซสชันที่ทำ PR ใหม่ยังคิดด้วย PR เดิม PR ใหม่มีผลครั้งถัดไป)
//	2) ยังไม่มีประวัติ + มีเซตกดหมดแรง       → e1RM สูงสุดของเซตที่กดหมดแรง (SessionReferenceOneRepMax)
//	3) ยังไม่มีประวัติ + ไม่มีเซตกดหมดแรง    → ไม่มีตัวอ้างอิง (0) ทุกเซตได้ MetsEndurance (3.5)
//	   (กันกรณียกเบาแล้วหยุดทั้งที่ยังไหว ได้ 6.0 เกินจริง — ระบบแยกเองไม่ได้ จึงถามผู้ใช้)
//
// ท่าบอดี้เวท/ท่าค้างเวลา ไม่ใช้ 1RM เลย (not_applicable)
func ResolveReferenceOneRepMax(history float64, sets []WeightSetEnergyInput, hasWeight, hasReps bool) (float64, string) {
	if !hasWeight || !hasReps {
		return 0, ReferenceNotApplicable
	}
	if history > 0 {
		return history, ReferenceHistory
	}
	flagged := false
	for _, s := range sets {
		if s.NearFailure && s.WeightKg > 0 {
			flagged = true
			break
		}
	}
	if !flagged {
		return 0, ReferenceSessionDeclined
	}
	if ref := SessionReferenceOneRepMax(sets); ref > 0 {
		return ref, ReferenceSession
	}
	return 0, ReferenceNone
}

// CalculateWeightTrainingCalories คำนวณพลังงานสุทธิรายเซตของเซสชันเวทเทรนนิ่ง 1 ท่า
//
//	kcal ของเซต i = NetEnergyKcal(METs_i, น้ำหนักตัว, เวลาเซต_i(นาที))
//	kcal ทั้งเซสชัน = Σ kcal ของทุกเซต
//
// แต่ละเซตได้ METs ตามความหนักของตัวเอง (WeightSetMets) — ยกหนักกับยกเบาที่ใช้เวลาเท่ากันจึงได้
// พลังงานต่างกัน kcalPerSet ปัด 2 ตำแหน่งก่อนรวม เพื่อให้ SUM(wtrs_calories) ใน DB เท่ากับ totalKcal พอดี
// reference1RM = 1RM อ้างอิง (PR ก่อนเซสชันนี้) — 0 = ยังไม่มีประวัติ ทุกเซตที่มีน้ำหนักได้ MetsEndurance
func CalculateWeightTrainingCalories(
	sets []WeightSetEnergyInput,
	reference1RM float64,
	bodyWeightKg float64, // น้ำหนักของผู้ออกกำลังกาย
	hasWeight bool, // ท่าใช้อุปกรณ์ (ไม่ใช่บอดี้เวท)
	hasReps bool, // ท่านับจำนวนครั้งได้ (ไม่ใช่ท่าค้างเวลา)
	difficulty int, // wet_difficulty ของท่า — ใช้เลือก METs เฉพาะท่าบอดี้เวท/ท่าค้างเวลา (BodyweightMets)
) (kcalPerSet []float64, metsPerSet []float64, totalKcal float64) {
	kcalPerSet = make([]float64, len(sets))
	metsPerSet = make([]float64, len(sets))
	for i, s := range sets {
		var mets float64
		if !hasWeight || !hasReps {
			mets = BodyweightMets(difficulty)
		} else {
			mets = WeightSetMets(s.WeightKg, s.Reps, reference1RM, hasWeight, hasReps)
		}
		// เวลาติดลบถือเป็น 0 (กันพลังงานติดลบ — defence in depth ต่อจาก ValidateWeightSession ที่ปฏิเสธไว้แล้ว)
		seconds := math.Max(float64(s.Seconds), 0)
		kcal := math.Round(NetEnergyKcal(mets, math.Max(bodyWeightKg, 0), seconds/60.0)*100) / 100
		metsPerSet[i] = mets
		kcalPerSet[i] = kcal
		totalKcal += kcal
	}
	return kcalPerSet, metsPerSet, math.Round(totalKcal*100) / 100
}

// ═══════════════════════════════════════════════════════════════════════
// 5. พลังงานคาร์ดิโอ (บทที่ 2 ข้อ 2.1.4.12 ตารางที่ 2.3)
// ═══════════════════════════════════════════════════════════════════════
// CalculateCardioCalories คำนวณพลังงานสุทธิของคาร์ดิโอ 1 ครั้ง — mets มาจากตาราง cardio
func CalculateCardioCalories(
	mets float64, // METs ของท่านี้
	bodyWeightKg float64, // น้ำหนักของผู้ออกกำลังกาย
	// เวลาที่ฝึก (วินาที)
	durationSeconds int) float64 {
	// ส่งค่าเข้าสูตร Net Energy Kcal : แปลงวินาที → นาที ก่อนส่ง แล้วปัดผลลัพธ์ 2 ตำแหน่ง
	return math.Round(NetEnergyKcal(mets, bodyWeightKg, float64(durationSeconds)/60.0)*100) / 100
}
