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

// EstimateOneRepMax - สูตร Epley: weight × (1 + reps/30) แม่นยำเฉพาะช่วง reps 2-10
// 1RM = น้ำหนักสูงสุดที่ยกได้ 1 ครั้ง (ประมาณจากเซตที่ยกหลายครั้ง)
// weightKg=น้ำหนักที่ยก, reps=จำนวนครั้งที่ทำได้
func EstimateOneRepMax(weightKg float64, reps int) float64 {
	return math.Round(weightKg*(1+float64(reps)/30.0)*100) / 100
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
// 4. พลังงานคาร์ดิโอ
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

// ═══════════════════════════════════════════════════════════════════════
// 5. พลังงานเวทเทรนนิ่ง
// ═══════════════════════════════════════════════════════════════════════
// CalculateWeightTrainingCalories คำนวณพลังงานที่เผาผลาญของเซสชันเวทเทรนนิ่ง 1 ท่า — mets มาจากตาราง weight_exercises
func CalculateWeightTrainingCalories(
	mets float64, // METs ของท่านี้ (wet_mets)
	bodyWeightKg float64, // น้ำหนักของผู้ออกกำลังกาย
	totalDurationSeconds int, // เวลารวมทั้งเซสชัน (วินาที)
	setCount int, // จำนวนเซตที่บันทึก
) (kcalPerSet []float64, totalKcal float64) {
	kcalPerSet = make([]float64, setCount)
	if setCount == 0 {
		return kcalPerSet, 0 // ไม่มีเซตให้คำนวณ
	}

	// 1. เอา MET ของท่า , น้ำหนักตัว , เวลารวมทั้งเซสชัน เข้าสูตร Net Energy Kcal
	minutes := float64(totalDurationSeconds) / 60.0 // แปลงวินาทีเป็นนาที ให้ตรงหน่วยของสูตร
	// ส่งค่าเข้าสูตรแกนกลาง NetEnergyKcal
	totalKcal = math.Round(NetEnergyKcal(mets, bodyWeightKg, minutes)*100) / 100
	// เรียกฟังก์ชันพร้อมส่งค่าเข้าไป → รับค่าที่ return กลับมา → ปัด 2 ตำแหน่ง → เก็บใส่ totalKcal

	// 2. หารพลังงานรวมเฉลี่ยเท่ากันทุกเซต (perSetShare = พลังงานต่อ 1 เซต)
	perSetShare := totalKcal / float64(setCount)
	for i := range kcalPerSet {
		kcalPerSet[i] = perSetShare
	}

	return kcalPerSet, totalKcal // ค่าพลังงานต่อเซต เเละ พลังงานรวมทั้งหมด
}
