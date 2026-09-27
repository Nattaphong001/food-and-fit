package services

import (
	"food_and_fit_api/helpers"
	"math"
)

// ═══════════════════════════════════════════════════════════════════════
// 1. BMI / BMR / TDEE / Target Calories — CalculateGoals
// ═══════════════════════════════════════════════════════════════════════

func CalculateGoals(weight, height float64, age, gender int, activityLevel float64, target int) (bmi, bmr, tdee, targetCalories float64) {
	// BMI
	heightInMeters := height / 100
	bmi = weight / (heightInMeters * heightInMeters)

	// BMR
	if gender == 1 { // ชาย
		bmr = (10 * weight) + (6.25 * height) - float64(5*age) + 5
	} else { // หญิง
		bmr = (10 * weight) + (6.25 * height) - float64(5*age) - 161
	}

	// TDEE = BMR × activityLevel (1.2 / 1.375 / 1.55 / 1.725 / 1.9)
	tdee = bmr * activityLevel

	// Target Calories: 1=ลดน้ำหนัก, 2=เพิ่มน้ำหนัก, 3=รักษาน้ำหนัก
	switch target {
	case 1: // ลด 20%, ห้ามต่ำกว่า BMR
		targetCalories = tdee - (tdee * 0.20)
		if targetCalories < bmr {
			targetCalories = bmr
		}
	case 2: // เพิ่ม 15%
		targetCalories = tdee + (tdee * 0.15)
	default: // รักษา = TDEE
		targetCalories = tdee
	}

	return math.Round(bmi*100) / 100, math.Round(bmr*100) / 100, math.Round(tdee*100) / 100, math.Round(targetCalories*100) / 100
}

// ═══════════════════════════════════════════════════════════════════════
// 2. Baseline Expenditure — CalculateBaselineExpenditure
// ═══════════════════════════════════════════════════════════════════════

// SedentaryCoefficient: Baseline Expenditure = BMR × 1.2 (ค่าคงที่ ไม่ใช่ activity level ของผู้ใช้)
const SedentaryCoefficient = 1.2

// ═══════════════════════════════════════════════════════════════════════
// Fallback Constants: ใช้เมื่อยังไม่มีประวัติ member_bmr_history (mbh_id = 0)
// เกิดได้จากปิดแอปกลางคันตอนตั้งค่าโปรไฟล์ หรือยิง API ตรง (Postman/seed tool)
// ติดธง is_bmr_estimated ให้ Dashboard โชว์ป้าย "ค่าประมาณ"
// ห้ามเขียนตัวเลขชุดนี้ซ้ำที่อื่น — SQL ใช้ผ่าน sqlConstReplacer เท่านั้น
const (
	FallbackBmr        = 1500.0
	FallbackTdee       = 1800.0
	FallbackTargetTdee = 2000.0
)

func CalculateBaselineExpenditure(bmr float64) float64 {
	return bmr * SedentaryCoefficient
}

// ═══════════════════════════════════════════════════════════════════════
// 2b. สัดส่วนสารอาหารมหัพภาค (Macronutrient Distribution) — CalculateMacroTargets
// ═══════════════════════════════════════════════════════════════════════
// บทที่ 2 ข้อ 2.1.4.8 — สัดส่วน C:P:F คงที่ต่อเป้าหมาย (mbs_target/goal_type) ห้ามแก้ตัวเลข
// ย้ายมาจาก mobile/lib/core/utils/dashboard_insights.dart (macroTargetPct) เมื่อ 2026-09-27 —
// เดิมคำนวณฝั่ง Dart ตั้งแต่ initial commit โดยไม่เคยมีฝั่ง Go เลย ขัดกฎ "backend เป็นเจ้าของสูตร
// ทั้งหมด" ของ formula-guard (Dart อนุญาตแค่ Volume/1RM/Cardio Burn/Energy Balance status)
type macroPercent struct{ protein, carb, fat float64 }

// goalType: 1=ลดน้ำหนัก, 2=เพิ่มน้ำหนัก, 3=รักษาน้ำหนัก (mbs_target) — ไม่มีใน map นี้ = ไม่รู้จัก
var macroPercentByGoal = map[int]macroPercent{
	1: {protein: 0.40, carb: 0.35, fat: 0.25},
	2: {protein: 0.30, carb: 0.50, fat: 0.20},
	3: {protein: 0.20, carb: 0.50, fat: 0.30},
}

// CalculateMacroTargets แปลง Target Calories เป็นกรัมโปรตีน/คาร์บ/ไขมัน ตามสัดส่วนของเป้าหมาย
// (โปรตีน/คาร์บ = kcal/4, ไขมัน = kcal/9 — Atwater General Factor System)
// goalType ที่ไม่ใช่ 1/2/3 หรือ targetCalories <= 0 → คืน 0 ทั้ง 3 ค่า ห้ามเดาสัดส่วนแทนผู้ใช้
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

// EstimateOneRepMax - สูตร Epley: weight × (1 + reps/30) แม่นยำเฉพาะช่วง reps 2-10
func EstimateOneRepMax(weightKg float64, reps int) float64 {
	return math.Round(weightKg*(1+float64(reps)/30.0)*100) / 100
}

// ═══════════════════════════════════════════════════════════════════════
// 4. พลังงานคาร์ดิโอ — NetEnergyKcal / CalculateCardioCalories
// ═══════════════════════════════════════════════════════════════════════
// NetEnergyKcal คือสูตรพลังงานสุทธิ ACSM:
//
//	Kcal (NET) = [(METs − 1) × 3.5 × น้ำหนักตัว(kg) / 200] × ระยะเวลา(นาที)
//
// หัก 1 MET (พลังงานพักนิ่ง ที่ Baseline BMR×1.2 นับไปแล้ว) กันนับซ้ำตอนรวม Total Daily Energy Output
// clamp METs ≤ 1 เป็น 0 กันค่าติดลบ (Dart preview คาร์ดิโอใช้สูตรเดียวกัน ดู formula-guard)
func NetEnergyKcal(mets, bodyWeightKg, minutes float64) float64 {
	// 3.5 = ใช้ออกซิเจนขณะพัก 1 MET (ml/kg/min), 200 = ตัวหารแปลงเป็น kcal/min (1 L O₂ ≈ 5 kcal)
	const metOxygenMlPerKgPerMin = 3.5
	const metKcalDivisor = 200.0

	netMets := mets - 1
	if netMets < 0 {
		netMets = 0
	}
	return (netMets * metOxygenMlPerKgPerMin * bodyWeightKg / metKcalDivisor) * minutes
}

// CalculateCardioCalories คำนวณพลังงานสุทธิของคาร์ดิโอ 1 ครั้ง — mets มาจากตาราง cardio (cdo_mets)
func CalculateCardioCalories(mets, bodyWeightKg float64, durationSeconds int) float64 {
	return NetEnergyKcal(mets, bodyWeightKg, float64(durationSeconds)/60.0)
}

// ═══════════════════════════════════════════════════════════════════════
//  5. พลังงานเวทเทรนนิ่ง — Session MET ตามตาราง 2.2 + Effort Ratio
//     (รายละเอียดประวัติการเปลี่ยนสูตร ดู ../../CLAUDE.md ข้อ 7[B-1])
//
// ═══════════════════════════════════════════════════════════════════════
//
// 3 ระดับตรงตาราง 2.2: 02056=3.0 เบา / 02054=3.5 ปานกลาง / 02050=6.0 หนัก
// เวลาเซสชัน = เริ่มเซตแรกถึงจบเซตสุดท้าย รวมพักระหว่างเซต (มาตรฐาน Apple Watch/Garmin/Strava —
// MET ของ Compendium เป็นค่าเฉลี่ยที่ครอบคลุมช่วงพักสั้นอยู่แล้ว, ACSM 2561) กันยืดเวลาได้พลังงานฟรี
// ด้วยชั้นรับข้อมูลแทนเพดานในสูตร: มือถือเด้งเตือนเมื่อไม่บันทึกเซตเกิน 10 นาที
// (weight_training_exercise_view.dart _promptIfIdle) + backend ปฏิเสธเซสชัน > 7200 วิ
// (helpers.WeightSessionMaxSeconds)
//
// ระดับ "หนัก" ใช้ Effort Ratio แทน %1RM ตรงๆ เพราะตาราง 2.2 ครอบคลุมทั้งพาวเวอร์ลิฟติ้ง (หนักน้อย
// ครั้ง) และเพาะกาย (กลางๆ จนหมดแรง) — %1RM เดี่ยวจับเพาะกายไม่ได้ ใช้สูตร Epley ประมาณ 1RM ของเซต
// เทียบกับ Best 1RM ของสมาชิก:
//
//	Effort Ratio (เซต) = [น้ำหนักที่ยก × (1 + Reps/30)] ÷ Best 1RM
//
// เกณฑ์ ≥ 0.90 ≈ เหลือแรงสำรอง 4-5 ครั้ง (Reps in Reserve) ต่ำกว่าจุดสูงสุดจริง (2-3 ครั้ง) เล็กน้อย
// โดยตั้งใจ ชดเชยกรณี Best 1RM จากประวัติอาจต่ำกว่าความสามารถจริงปัจจุบัน — เป็นการตีความของผู้วิจัย
// ต้องระบุในเล่มว่าเป็นการประยุกต์ ไม่ใช่ตัวเลขจาก Compendium/ACSM ตรงๆ
const (
	metResistanceHigh     = 6.0 // 02050 หนัก - พาวเวอร์ลิฟติ้งหรือเพาะกาย ความพยายามระดับหนักมาก
	metResistanceModerate = 3.5 // 02054 กลาง - ยกน้ำหนัก หลากหลายท่า 8-15 ครั้งต่อเซต
	metBodyweightGeneral  = 3.0 // 02056 เบา - แรงต้านด้วยน้ำหนักตัว ระดับทั่วไป
)

const (
	// Effort Ratio เฉลี่ยทั้งเซสชัน ≥ ค่านี้ = ความพยายามระดับหนักมาก (เมื่อมี Best 1RM จากประวัติ)
	// = เหลือแรงสำรองโดยประมาณ 4-5 ครั้ง (ตีความของผู้วิจัย ดูรายละเอียดเหตุผลหัวบล็อกด้านบน)
	weightTrainingEffortRatioHigh = 0.90
	// ไม่มี Best 1RM (ครั้งแรกที่ฝึกท่านี้) ใช้ Reps เฉลี่ยแทนเป็นทางสำรอง — ต่ำกว่าค่านี้ถือว่าหนัก
	// อิงจากตาราง 2.2 เอง (ระดับปานกลางกำหนดไว้ที่ 8-15 ครั้งต่อเซต ต่ำกว่า 8 จึงเข้าระดับหนัก) ต้องมี
	// น้ำหนักที่ยกจริง (> 0) ด้วย กันท่า bodyweight ที่ทำ Reps น้อยเข้าเกณฑ์นี้ผิดกลุ่ม
	weightTrainingHighIntensityFallbackMaxReps = 7
)

// WeightTrainingBodyweightEquipment คือค่า wet_equipment ของหมวดน้ำหนักตัว/แคลิสเทนิกส์ — ตาราง 2.2
// มีแถวน้ำหนักตัวแถวเดียว (3.0) จึงได้ระดับนี้เสมอแม้ถ่วงน้ำหนักเพิ่ม (เช่น Weighted Pull-up)
// ตีความของผู้วิจัย: schema ไม่มีหมวดแยกสำหรับ "น้ำหนักตัว+ถ่วงน้ำหนัก"
const WeightTrainingBodyweightEquipment = 5

// resolveSessionMET เลือก MET ระดับเซสชัน (1 คำขอ = 1 wet_id) ตามตาราง 2.2
// bestOneRepMax: Estimated 1RM ที่ดีที่สุดของสมาชิกในท่านี้ จากประวัติก่อนเซสชันนี้ (0 = ไม่มีประวัติ
// — GetBestOneRepMax กรอง Reps 1-10 มาแล้ว)
func resolveSessionMET(equipment int8, bestOneRepMax float64, sets []helpers.WeightSetCheck) (met float64, intensityLevel int8) {
	if equipment == WeightTrainingBodyweightEquipment {
		return metBodyweightGeneral, 1 // เบา
	}

	hasHistory := bestOneRepMax > 0

	if hasHistory {
		sumER, countER := 0.0, 0
		for _, s := range sets {
			if s.WeightKg > 0 {
				sumER += EstimateOneRepMax(s.WeightKg, s.Reps) / bestOneRepMax
				countER++
			}
		}
		if countER > 0 && sumER/float64(countER) >= weightTrainingEffortRatioHigh {
			return metResistanceHigh, 3 // หนัก
		}
		return metResistanceModerate, 2 // ปานกลาง
	}

	// ไม่มีประวัติ Best 1RM (ครั้งแรกที่ฝึกท่านี้) — ใช้ Reps เฉลี่ยของเซตที่มีน้ำหนักที่ยกจริงแทน
	sumReps, countWeighted := 0, 0
	for _, s := range sets {
		if s.WeightKg > 0 {
			sumReps += s.Reps
			countWeighted++
		}
	}
	if countWeighted > 0 && float64(sumReps)/float64(countWeighted) <= weightTrainingHighIntensityFallbackMaxReps {
		return metResistanceHigh, 3 // หนัก
	}
	return metResistanceModerate, 2 // ปานกลาง
}

// CalculateWeightTrainingCalories คำนวณพลังงานเวทเทรนนิ่งทั้งเซสชัน — เลือก MET เซสชันเดียวตาม
// ตาราง 2.2 แล้วคูณเวลารวมทั้งเซสชัน
//
// equipment: wet_equipment ของท่านี้
// bestOneRepMax: จากประวัติก่อนเซสชันนี้เท่านั้น (0 = ไม่มีประวัติ)
// totalDurationSeconds: เริ่มเซตแรก-จบเซตสุดท้าย รวมพัก (ดู weight_training_exercise_view.dart
// _sessionDurationSeconds)
// sets: เซตที่จะบันทึกจริงเท่านั้น (ผ่าน filter Reps > 0 จาก controller มาแล้ว)
//
// คืนค่า: kcalPerSet (แจกเท่ากันทุกเซต = totalKcal/len(sets), ให้ SUM GROUP BY wtrs_date ที่
// analytics ใช้ถูกต้องโดยไม่ต้องแก้ query), totalKcal (ปัด 2 ตำแหน่ง), sessionMET, intensityLevel
// (1=เบา 2=กลาง 3=หนัก — ระดับเดียวกับที่ใช้เลือก MET)
func CalculateWeightTrainingCalories(
	equipment int8,
	bodyWeightKg float64,
	bestOneRepMax float64,
	totalDurationSeconds int,
	sets []helpers.WeightSetCheck,
) (kcalPerSet []float64, totalKcal float64, sessionMET float64, intensityLevel int8) {
	n := len(sets)
	kcalPerSet = make([]float64, n)
	if n == 0 {
		return kcalPerSet, 0, 0, 2
	}

	sessionMET, intensityLevel = resolveSessionMET(equipment, bestOneRepMax, sets)

	minutes := float64(totalDurationSeconds) / 60.0
	totalKcal = math.Round(NetEnergyKcal(sessionMET, bodyWeightKg, minutes)*100) / 100

	perSetShare := totalKcal / float64(n)
	for i := range kcalPerSet {
		kcalPerSet[i] = perSetShare
	}

	return kcalPerSet, totalKcal, sessionMET, intensityLevel
}
