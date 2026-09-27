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
//  5. พลังงานเวทเทรนนิ่ง — Session MET ตามตาราง 2.2 + RIR (Reps in Reserve)
//     (แก้ 2026-09-27 จาก Effort Ratio ≥ 0.90 — ดูเหตุผลและประวัติสูตรเดิมใน ../../CLAUDE.md ข้อ 7[B-1])
//
// ═══════════════════════════════════════════════════════════════════════
//
// 3 ระดับ MET ประมาณจากตาราง Conditioning Exercise ของ 2024 Adult Compendium of Physical
// Activities (Herrmann et al., 2567): 02056=3.0 เบา / 02054=3.5 ปานกลาง / 02050=6.0 หนัก — ใช้
// เป็นค่าประมาณร่วมแบบที่ระบบ/แอปทั่วไปใช้กัน (Compendium ให้เฉพาะค่า METs กับคำบรรยายเชิงคุณภาพ
// ของแต่ละรหัส ไม่ได้กำหนดเกณฑ์ตัวเลขไว้ว่าเซสชันแบบไหนควรได้ระดับใด)
// เวลาเซสชัน = เริ่มเซตแรกถึงจบเซตสุดท้าย รวมพักระหว่างเซต (มาตรฐาน Apple Watch/Garmin/Strava —
// MET ของ Compendium เป็นค่าเฉลี่ยที่ครอบคลุมช่วงพักสั้นอยู่แล้ว, ACSM 2561) กันยืดเวลาได้พลังงานฟรี
// ด้วยชั้นรับข้อมูลแทนเพดานในสูตร: มือถือเด้งเตือนเมื่อไม่บันทึกเซตเกิน 10 นาที
// (weight_training_exercise_view.dart _promptIfIdle) + backend ปฏิเสธเซสชัน > 7200 วิ
// (helpers.WeightSessionMaxSeconds)
//
// ระดับ "หนัก" ใช้ RIR (Reps in Reserve — จำนวนครั้งที่ยังยกต่อได้ก่อนกล้ามเนื้อล้า) แทน %1RM
// ตรงๆ ตามถ้อยแถลงร่วมของ American College of Sports Medicine และ Exercise and Sport Science
// Australia (Bishop et al., 2568 — ACSM–ESSA Physical Activity and Exercise Intensity
// Terminology, Table 2) ซึ่งเสนอ RIR แทนร้อยละของ 1RM เป็นตัวบ่งชี้ความหนักของการฝึกแรงต้าน และ
// จำแนกระดับ High ไว้ที่ RIR 2-3 ครั้ง, Very high ที่ < 2 ครั้ง, Moderate ที่ 4-6 ครั้ง (ถ้อยแถลง
// เสนอให้ใช้คำว่า "High" แทน "vigorous" ที่ใช้กันมาแต่เดิม) RIR ประมาณจากสูตร Epley (ข้อ 2.1.4.13,
// เดียวกับที่ใช้หา Best 1RM) โดยกลับสมการหาจำนวนครั้งสูงสุดที่ยกได้ ณ น้ำหนักหนึ่ง:
//
//	จำนวนครั้งสูงสุดที่ภาระ w (เซต) = 30 × (Best 1RM ÷ น้ำหนักที่ยก − 1)
//	RIR (เซต) = จำนวนครั้งสูงสุดที่ภาระ w − จำนวนครั้งที่ทำได้จริง (ค่าติดลบถือเป็น 0)
//
// เกณฑ์ RIR เฉลี่ยทั้งเซสชัน ≤ 3 ครั้ง (High/Very high ตาม ACSM–ESSA) ตรงกับ Effort Ratio เดิม
// ≈ 0.92-0.93 (สูงกว่า 0.90 เดิมเล็กน้อย เพราะ 0.90 แปลงกลับเป็น RIR ได้ประมาณ 3.9-4.7 ครั้ง ซึ่งอยู่
// ในช่วง Moderate ของ ACSM–ESSA ไม่ใช่ High — เกณฑ์เดิมตั้งไว้หลวมกว่าที่ตั้งใจ)
//
// ⚠️ ยังเป็นการออกแบบ/การตีความของผู้วิจัย 6 จุด ไม่มีเอกสารใดกำหนดตรงๆ ทั้งหมด ต้องระบุในเล่ม:
//  1. การกลับสมการ Epley เพื่อประมาณ RIR ทั้งที่สมการสร้างมาเพื่อประมาณ 1RM จากเซตที่ยกจนหมดแรง
//  2. ใช้ Best e1RM จากประวัติ (อาจไม่ได้ยกจนหมดแรง จึงอาจต่ำกว่า 1RM จริง) แทน 1RM ปัจจุบัน
//  3. สรุปทั้งเซสชันด้วยค่าเฉลี่ยเลขคณิตของ RIR แต่ละเซต ไม่มีเอกสารกำหนดวิธีรวมค่าไว้
//  4. ค่า RIR เฉลี่ยที่อยู่ระหว่าง 3 กับ 4 (ไม่ใช่จำนวนเต็ม) จัดไว้ในระดับ Moderate (ต่ำกว่า)
//  5. การจับคู่ระดับ High ของ ACSM–ESSA เข้ากับรหัส 02050 (6.0 METs) ของ Compendium — ACSM–ESSA
//     รองรับแค่ความสมมูลของคำว่า High กับ vigorous เท่านั้น ไม่ได้รองรับการใช้ METs เป็นตัวชี้วัด
//  6. ท่าน้ำหนักตัว (wet_equipment=5) ได้ 02056=3.0 (General) เสมอ ไม่เคยขึ้นถึง 02057=6.5 (High
//     intensity) เพราะไม่มีเอกสารกำหนดเกณฑ์ตัวเลขแยกสองรหัสนี้
// ข้อ 1-2 เอนเอียงไปทางเดียวกัน (ทำให้ RIR ประมาณได้ต่ำกว่าจริง) จึงมีแนวโน้มจัดเซสชันเป็น High
// มากกว่าน้อยเกินจริง — รายละเอียดงานวิจัยที่ตรวจสอบมาทั้งหมด (Compendium, ACSM/ACSM–ESSA, NSCA,
// การวัดแคลอริเมตรีจริง, ตัวเลือกที่ตัดออก) → docs/reports/เกณฑ์เลือก METs เวทเทรนนิ่ง.md
const (
	metResistanceHigh     = 6.0 // 02050 หนัก - พาวเวอร์ลิฟติ้งหรือเพาะกาย ความพยายามระดับหนักมาก
	metResistanceModerate = 3.5 // 02054 กลาง - ยกน้ำหนัก หลากหลายท่า 8-15 ครั้งต่อเซต
	metBodyweightGeneral  = 3.0 // 02056 เบา - แรงต้านด้วยน้ำหนักตัว ระดับทั่วไป
)

const (
	// RIR เฉลี่ยทั้งเซสชัน ≤ ค่านี้ = ระดับ High/Very high ตาม ACSM–ESSA 2025 Table 2 (เมื่อมี
	// Best 1RM จากประวัติ) — ดูที่มาและจุดตีความที่เหลือในหัวบล็อกด้านบน
	weightTrainingRIRHighMax = 3.0
)

// WeightTrainingBodyweightEquipment คือค่า wet_equipment ของหมวดน้ำหนักตัว/แคลิสเทนิกส์ — ตาราง 2.2
// มีแถวน้ำหนักตัวแถวเดียว (3.0) จึงได้ระดับนี้เสมอแม้ถ่วงน้ำหนักเพิ่ม (เช่น Weighted Pull-up)
// ตีความของผู้วิจัย: schema ไม่มีหมวดแยกสำหรับ "น้ำหนักตัว+ถ่วงน้ำหนัก"
const WeightTrainingBodyweightEquipment = 5

// resolveSessionMET เลือก MET ระดับเซสชัน (1 คำขอ = 1 wet_id) ตามตาราง 2.2
// bestOneRepMax: Estimated 1RM ที่ดีที่สุดของสมาชิกในท่านี้ จากประวัติก่อนเซสชันนี้ (0 = ไม่มีประวัติ
// — GetBestOneRepMax กรอง Reps 1-10 มาแล้ว)
//
// ไม่มีประวัติ Best 1RM (ครั้งแรกที่ฝึกท่านี้) → ประมาณ RIR ไม่ได้ (ไม่มีตัวหารสำหรับ Epley ย้อนกลับ)
// ใช้ระดับปานกลาง (02054) เป็นค่าเริ่มต้นแทน — เดิมมีทางสำรองอิง Reps เฉลี่ย ≤ 7 → หนัก แต่ตัดออกแล้ว
// (2026-09-27) เพราะไม่มีข้อมูลว่าเซตนั้นยกจนหมดแรงหรือไม่ ACSM–ESSA ชี้ว่า Reps อย่างเดียวบอกความหนัก
// ไม่ได้ ภาระเดียวกันอาจเป็นระดับ Low หรือ Very high ก็ได้ขึ้นกับว่าใกล้หมดแรงแค่ไหน
func resolveSessionMET(equipment int8, bestOneRepMax float64, sets []helpers.WeightSetCheck) (met float64, intensityLevel int8) {
	if equipment == WeightTrainingBodyweightEquipment {
		return metBodyweightGeneral, 1 // เบา
	}

	if bestOneRepMax <= 0 {
		return metResistanceModerate, 2 // ไม่มีประวัติ — ปานกลาง (ค่าเริ่มต้น)
	}

	sumRIR, countRIR := 0.0, 0
	for _, s := range sets {
		if s.WeightKg > 0 {
			maxRepsAtWeight := 30.0 * (bestOneRepMax/s.WeightKg - 1) // กลับสมการ Epley
			rir := maxRepsAtWeight - float64(s.Reps)
			if rir < 0 {
				rir = 0
			}
			sumRIR += rir
			countRIR++
		}
	}
	if countRIR == 0 {
		return metResistanceModerate, 2 // ไม่มีเซตที่มีน้ำหนักยกจริง — ปานกลาง (ค่าเริ่มต้น)
	}

	avgRIR := sumRIR / float64(countRIR)
	if avgRIR <= weightTrainingRIRHighMax {
		return metResistanceHigh, 3 // หนัก — RIR เฉลี่ย ≤ 3 ครั้ง (High/Very high ตาม ACSM–ESSA)
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
