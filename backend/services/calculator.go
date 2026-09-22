package services

import (
	"math"
)

// ═══════════════════════════════════════════════════════════════════════
// 1. BMI / BMR / TDEE / Target Calories — CalculateGoals
// ═══════════════════════════════════════════════════════════════════════

func CalculateGoals(weight, height float64, age, gender int, activityLevel float64, target int) (bmi, bmr, tdee, targetCalories float64) {
	// 1. BMI - ดัชนีมวลกาย
	heightInMeters := height / 100
	bmi = weight / (heightInMeters * heightInMeters)

	// 2. BMR - อัตราการเผาผลาญพลังงานพื้นฐาน
	if gender == 1 { // ชาย
		bmr = (10 * weight) + (6.25 * height) - float64(5*age) + 5
	} else { // หญิง
		bmr = (10 * weight) + (6.25 * height) - float64(5*age) - 161
	}

	// 3. TDEE - พลังงานที ่ใช้ต่อวัน
	tdee = bmr * activityLevel // activityLevel เป็นตัวคูณที่ได้จากการเลือกระดับกิจกรรม เช่น 1.2, 1.375, 1.55, 1.725, 1.9

	// 4. Target Calories - พลังงานตามเป้าหมาย
	// เป้าหมาย: 1=ลดน้ำหนัก, 2=เพิ่มน้ำหนัก, 3=รักษาน้ำหนัก
	switch target {
	case 1: // ลดน้ำหนัก (Deficit 20%)
		targetCalories = tdee - (tdee * 0.20)
		if targetCalories < bmr { // เงื่อนไขความปลอดภัย ห้ามต่ำกว่า BMR
			targetCalories = bmr
		}
	case 2: // เพิ่มน้ำหนัก (Surplus 15%)
		targetCalories = tdee + (tdee * 0.15)
	default: // 3 = รักษาน้ำหนัก
		targetCalories = tdee
	}

	// ปัดเศษให้เป็นทศนิยม 2 ตำแหน่ง
	return math.Round(bmi*100) / 100, math.Round(bmr*100) / 100, math.Round(tdee*100) / 100, math.Round(targetCalories*100) / 100
}

// ═══════════════════════════════════════════════════════════════════════
// 2. Baseline Expenditure — CalculateBaselineExpenditure
// ═══════════════════════════════════════════════════════════════════════

// Baseline Expenditure - พลังงานพื้นฐานและกิจกรรมทั่วไป
//
//	BMR × 1.2 ค่าสัมประสิทธิ์สำหรับผู้มีกิจกรรมน้อย
const SedentaryCoefficient = 1.2

// ═══════════════════════════════════════════════════════════════════════
// Fallback Constants: ใช้เมื่อยังไม่มีประวัติ member_bmr_history (mbh_id = 0)
//
// สาเหตุที่อาจหลุดมาได้ (แม้ Mobile UI จะบล็อกไว้):
// 1. ผู้ใช้ปิดแอปกลางคันในหน้าตั้งค่าโปรไฟล์ แล้วเข้าใหม่
// 2. ยิง API ตรงๆ (Postman/curl) หรือ ข้อมูลจากระบบ Test (cmd_seed_demo.exe)
//
// ผลลัพธ์: จะติดธง is_bmr_estimated เพื่อให้หน้า Dashboard แสดงป้าย "ค่าประมาณ"
// 
// ข้อห้าม: ห้ามเขียนตัวเลขชุดนี้ตรงๆ ที่อื่น (ใน SQL ให้ใช้ sqlConstReplacer เท่านั้น)
const (
	FallbackBmr        = 1500.0
	FallbackTdee       = 1800.0
	FallbackTargetTdee = 2000.0
)

func CalculateBaselineExpenditure(bmr float64) float64 {
	return bmr * SedentaryCoefficient
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
// NetEnergyKcal คือสูตรพลังงานสุทธิ ACSM
//
//	Kcal (NET) = [(METs − 1) × 3.5 × น้ำหนักตัว(kg) / 200] × ระยะเวลา(นาที)

// หัก 1 MET (พลังงานพักนิ่ง ซึ่ง Baseline BMR×1.2 นับไปแล้ว) กันนับซ้ำเมื่อรวมเป็น Total Daily Energy
// Output — clamp METs ≤ 1 เป็น 0 กันค่าติดลบ (Dart preview ของคาร์ดิโอใช้สูตรเดียวกัน ดู formula-guard)
func NetEnergyKcal(mets, bodyWeightKg, minutes float64) float64 {
	// 3.5 = การใช้ออกซิเจนขณะพัก 1 MET (ml/kg/min)
	// 200 = ตัวหารแปลง (ml O₂/kg/min × kg) เป็น
	// kcal/min (1 L O₂ ≈ 5 kcal)
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
