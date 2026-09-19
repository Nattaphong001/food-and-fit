package services

import (
	"math"
)

// อายุจากวันเกิด → services.AgeFromBirthDate (member_service.go) — ฟังก์ชัน CalculateAge เดิมที่
// รับ string ถูกลบแล้ว (2026-09-19) เพราะไม่มีใครเรียก ซ้ำกับตัวนั้น และ fallback คืน 25 ปีเงียบๆ
// เมื่อ parse วันเกิดไม่ได้

// Baseline Expenditure = BMR × 1.2 (ค่าสัมประสิทธิ์ Sedentary ตามเกณฑ์ Institute of Medicine, 2548)
// ใช้หา Total Daily Energy Output รายวัน (บทที่ 2 หัวข้อ 2.1.4.6) — คนละสูตรกับ TDEE ใน
// CalculateGoals ที่คูณด้วย activityLevel จริงของสมาชิก (ใช้หา Target Calories) ห้ามรวมเป็น
// ฟังก์ชันเดียวกัน มิฉะนั้นพลังงานออกกำลังกายจะถูกนับซ้ำสองรอบ
const SedentaryCoefficient = 1.2

// ค่าประมาณตอนสมาชิกยังไม่มีประวัติ BMR เลย (ยังไม่เคยกรอกข้อมูลร่างกาย) — ไม่ใช่ข้อมูลจริงของสมาชิก
// ผลลัพธ์ที่ใช้ค่านี้ติดธง is_bmr_estimated (GetDailyAnalyticsData) ให้ UI บอกผู้ใช้ได้ ใช้ constant
// เดียวกันทั้ง Go และ SQL (analytics_service.go sqlConstReplacer) ห้ามเขียนตัวเลขนี้ตรงๆ ที่อื่น
const (
	FallbackBmr        = 1500.0
	FallbackTdee       = 1800.0
	FallbackTargetTdee = 2000.0
)

func CalculateBaselineExpenditure(bmr float64) float64 {
	return bmr * SedentaryCoefficient
}

// EstimateOneRepMax - สูตร Epley: weight × (1 + reps/30) แม่นยำเฉพาะช่วง reps 2-10 (บทที่ 2 ข้อ
// 2.1.4.13) คำนวณแสดงผลอย่างเดียว ไม่บันทึกลง DB (กฎเหล็กข้อ 8.2) — จุดเดียวที่มีสูตรนี้ใน Go
// (GetBestOneRepMax และ SaveWorkoutResult เรียกจุดนี้) ⚠️ สูตรเดียวกันมีอยู่ใน SQL อีก 3 จุดโดยตั้งใจ
// (analytics_service.go Get1RMHistoryData 3 expression + workout_service.go GetBestOneRepMax
// ORDER BY) เพราะต้องหาค่าสูงสุดใน query เดียวแทนดึงทุกแถวมาคำนวณใน Go — แก้สูตรที่นี่ต้องแก้ SQL
// ให้ตรงกันด้วย (grep "reps / 30" ใน services/)
func EstimateOneRepMax(weightKg float64, reps int) float64 {
	return math.Round(weightKg*(1+float64(reps)/30.0)*100) / 100
}

// คำนวณทุกอย่างตามเอกสารอ้างอิง
func CalculateGoals(weight, height float64, age, gender int, activityLevel float64, target int) (bmi, bmr, tdee, targetCalories float64) {
	// 1. BMI
	heightInMeters := height / 100
	bmi = weight / (heightInMeters * heightInMeters)

	// 2. BMR
	if gender == 1 { // ชาย
		bmr = (10 * weight) + (6.25 * height) - float64(5*age) + 5
	} else { // หญิง
		bmr = (10 * weight) + (6.25 * height) - float64(5*age) - 161
	}

	// 3. TDEE
	tdee = bmr * activityLevel // activityLevel เป็นตัวคูณที่ได้จากการเลือกระดับกิจกรรม เช่น 1.2, 1.375, 1.55, 1.725, 1.9

	// 4. Target Calories - เป้าหมาย: 1=ลดน้ำหนัก, 2=เพิ่มน้ำหนัก, 3=รักษาน้ำหนัก
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
	return math.Round(bmi*100)/100, math.Round(bmr*100)/100, math.Round(tdee*100)/100, math.Round(targetCalories*100)/100
}

// ═══════════════════════════════════════════════════════════════════════
// Weight Training — Smart Auto Calorie (ออกแบบ 2026-09-08, เปลี่ยนเป็น Dynamic METs Logic Matrix
// ตามบทที่ 2 ข้อ 2.1.4.12 ข้อ 2 เมื่อ 2026-09-19)
// ═══════════════════════════════════════════════════════════════════════
// แทนที่ระบบเดิมที่ผู้ใช้เลือกความหนัก 3 ระดับเอง (wtrs_intensity_level) ซึ่งไม่เคยทำงานจริง —
// mobile ไม่เคยส่งค่านี้ขึ้น API เลย ทุกแถวใน DB จริงก่อนหน้านี้ fallback เป็น 1 (เบา) หมด
//
// สูตรพลังงานสุทธิ (บทที่ 2 ข้อ 2.1.4.12 ข้อ 1 — สูตร ACSM เดียวกับคาร์ดิโอ ข้อ 2.1.4.10):
//
//	Kcal (NET) = (METs − 1) × 3.5 × น้ำหนักตัว(kg) / 200 × ระยะเวลา(นาที)
//
// Final MET = Session MET (ค่าเฉลี่ย MET ต่อเซต จาก Logic Matrix ด้านล่าง) ตรงๆ ไม่มีตัวคูณต่อ
//
// [Dynamic METs Logic Matrix] เลือก MET ต่อเซตจาก 3 อย่างที่ระบบวัดได้จริง: หมวดท่า (wet_equipment),
// ประเภทท่า (wet_exercise_type), เวลาพักหลังเซตนั้น + Reps — ไม่ใช้ %1RM/น้ำหนักที่ยก เลือก MET
// (ค่า METs ตรงกับรหัส Compendium 2011 ดู docs/compendium-2011-met-check.md) ตามตารางไล่บนลงล่าง
// เจอข้อแรกที่ตรงแล้วหยุด:
//
//	หมวดแรงต้านและอุปกรณ์ (wet_equipment 1-4)
//	1. Reps < 8                                  6.0   ระดับหนัก (02050)
//	2. Compound หรือ พัก 60–90 วินาที (รวมปลาย)   5.0   ระดับปานกลาง (02052)
//	3. ที่เหลือ                                   3.5   ระดับเบา (02054)
//
//	หมวดน้ำหนักตัว/แคลิสเทนิกส์ (wet_equipment 5)
//	1. ท่า Isolation (เช่น Crunch)                2.8   ระดับเบา หน้าท้อง (02024)
//	2. พัก < 30 วินาที                            8.0   ระดับหนัก ต่อเนื่อง (02020)
//	3. พัก 30–90 วินาที (รวมปลาย)                 3.8   ระดับปานกลาง (02022)
//	4. พัก > 90 วินาที                            3.5   ระดับเบา (02030)
//
// ⚠️ สเปกบทที่ 2 ระบุ METs และคำบรรยายระดับ ไม่ได้ระบุเกณฑ์ตัวเลขทั้งหมด — 5 จุดนี้เป็นการตีความ
// ของผู้วิจัย ต้องระบุในเล่มว่าไม่ใช่ตัวเลขที่สเปกกำหนดตรงๆ:
//  1. "หนักมาก จนหมดแรง" (พาวเวอร์ลิฟติ้ง) → Reps < 8 (ต่ำกว่าช่วง 8–12 ครั้งที่ข้อ 2.1.4.11 แนะนำ)
//  2. สเปกเขียน "หรือ" ทับกัน (Compound พักนาน เข้าได้ทั้งเบาและปานกลาง) → ปานกลางชนะ เพราะเป็น
//     เงื่อนไขที่ระบุตรง ส่วนระดับเบาเป็นค่าที่เหลือ
//  3. "กล้ามเนื้อมัดเล็ก" → ท่า Isolation (wet_exercise_type = 2)
//  4. "ต่อเนื่อง" ของหมวดน้ำหนักตัว → พัก < 30 วินาที
//  5. ช่วงพัก 30 และ 90 วินาทีของหมวดน้ำหนักตัว (สเปกให้เลขพักเฉพาะหมวดแรงต้าน 60–90)
//
// เวลาพักต่อเซต: ใช้ค่าจริงจาก wtrs_rest_seconds (มือถือส่งขึ้น API แล้วตั้งแต่ 2026-09-18) — เซตสุดท้ายของ
// เซสชันไม่มีการพักจริง (ผู้ใช้กรอกเสร็จแล้วจบการฝึกเลย เวลาที่นับได้เป็นแค่เวลากรอกข้อมูล) มือถือจึงส่งเป็น
// nil (2026-09-19) เซตที่เป็น nil ใช้ "ค่าเฉลี่ยเวลาพักของเซตอื่นในเซสชันเดียวกัน" แทน — ถ้าทั้งเซสชันไม่มี
// เวลาพักจริงเลย (แถวเก่าก่อน 2026-09-18 หรือเซสชันเซตเดียว) ค่อย fallback ไปใช้ "ความหนาแน่นเฉลี่ยทั้งเซสชัน"
// (เวลารวมทั้งเซสชัน/จำนวนเซต แปลงเป็นวินาที) เป็น proxy
const (
	// ค่าคงที่สูตรพลังงานสุทธิ ACSM (บทที่ 2 ข้อ 2.1.4.10/2.1.4.12): 3.5 = การใช้ออกซิเจนขณะพัก
	// 1 MET (ml/kg/min), 200 = ตัวหารแปลง (ml O₂/kg/min × kg) เป็น kcal/min (1 L O₂ ≈ 5 kcal)
	METOxygenMlPerKgPerMin = 3.5
	METKcalDivisor         = 200.0

	// ขอบเขต Final MET กันหลุดขอบจากอินพุตสุดโต่ง (ไม่ใช่ค่าที่ควรชนบ่อยในการใช้งานปกติ)
	WeightTrainingMETFloor = 1.5
	WeightTrainingMETCeil  = 9.5

	// ── ค่า wet_equipment / wet_exercise_type (ตรงกับ Data Dictionary) ──
	EquipmentBodyweight   int8 = 5 // wet_equipment: 1=Barbell 2=Dumbbell 3=Machine 4=Cable 5=Bodyweight
	ExerciseTypeCompound  int8 = 1 // wet_exercise_type: 1=หลายกลุ่ม (Compound)
	ExerciseTypeIsolation int8 = 2 // wet_exercise_type: 2=เฉพาะส่วน (Isolation)

	// ── Dynamic METs Logic Matrix: หมวดแรงต้านและอุปกรณ์ ──
	ResistanceMETLight    = 3.5 // ระดับเบา
	ResistanceMETModerate = 5.0 // ระดับปานกลาง
	ResistanceMETHeavy    = 6.0 // ระดับหนัก
	// Reps ต่ำกว่าค่านี้ = "หนักมาก จนหมดแรง" (ตีความข้อ 1 — ต่ำกว่าช่วง 8–12 ครั้ง ข้อ 2.1.4.11)
	ResistanceHeavyRepsBelow = 8
	// ช่วงพักระดับปานกลาง 60–90 วินาที (รวมปลายทั้งสองข้าง ตามที่สเปกเขียน)
	ResistanceRestModerateMinSeconds = 60.0
	ResistanceRestModerateMaxSeconds = 90.0

	// ── Dynamic METs Logic Matrix: หมวดน้ำหนักตัว / แคลิสเทนิกส์ ──
	BodyweightMETLightAbdominal = 2.8 // ระดับเบา — ท่า Isolation เช่น หน้าท้อง
	BodyweightMETLight          = 3.5 // ระดับเบา — ความพยายามน้อย (พักนาน)
	BodyweightMETModerate       = 3.8 // ระดับปานกลาง
	BodyweightMETHeavy          = 8.0 // ระดับหนัก — ทำต่อเนื่อง พักสั้น
	// พักต่ำกว่านี้ = "ต่อเนื่อง" (ตีความข้อ 4) · พักไม่เกินนี้ = ปานกลาง (ตีความข้อ 5)
	BodyweightRestContinuousBelowSeconds = 30.0
	BodyweightRestModerateMaxSeconds     = 90.0
)

// NetEnergyKcal คือสูตรพลังงานสุทธิ ACSM ที่ใช้ร่วมกันทั้งคาร์ดิโอและเวทเทรนนิ่ง (บทที่ 2 ข้อ 2.1.4.10
// และ 2.1.4.12 ข้อ 1) — จุดเดียวใน Go ที่มีสูตรนี้:
//
//	Kcal (NET) = [(METs − 1) × 3.5 × น้ำหนักตัว(kg) / 200] × ระยะเวลา(นาที)
//
// หัก 1 MET (พลังงานพักนิ่ง ซึ่ง Baseline BMR×1.2 นับไปแล้ว) กันนับซ้ำเมื่อรวมเป็น Total Daily Energy
// Output — clamp METs ≤ 1 เป็น 0 กันค่าติดลบ (Dart preview ของคาร์ดิโอใช้สูตรเดียวกัน ดู formula-guard)
func NetEnergyKcal(mets, bodyWeightKg, minutes float64) float64 {
	netMets := mets - 1
	if netMets < 0 {
		netMets = 0
	}
	return (netMets * METOxygenMlPerKgPerMin * bodyWeightKg / METKcalDivisor) * minutes
}

// CalculateCardioCalories คำนวณพลังงานสุทธิของคาร์ดิโอ 1 ครั้ง — mets มาจากตาราง cardio (cdo_mets)
// เสมอ ห้าม hardcode, durationSeconds คือ cdors_duration (หน่วยวินาที, ดู ValidateCardioResult)
func CalculateCardioCalories(mets, bodyWeightKg float64, durationSeconds int) float64 {
	return NetEnergyKcal(mets, bodyWeightKg, float64(durationSeconds)/60.0)
}

// SetLog คือ 1 เซตที่นับรวมในเซสชัน
type SetLog struct {
	WeightKg float64 // น้ำหนักที่ยกจริง (0 = ท่า bodyweight)
	Reps     int
	// RestSeconds คือเวลาพักหลังเซตนี้ (วินาที) ก่อนเริ่มเซตถัดไป — nil = ไม่ทราบ (เซตสุดท้ายของเซสชันที่ไม่มีการพัก
	// จริง หรือแถวเก่าที่มือถือยังไม่ส่งมา) ระบบใช้ค่าเฉลี่ยเวลาพักของเซตอื่นแทน ดูคอมเมนต์หัวไฟล์
	RestSeconds *int
}

// ExerciseProfile คือคุณลักษณะของท่าฝึกที่ Logic Matrix ใช้เลือกหมวด/ระดับ — ค่ามาจากตาราง
// weight_exercises (wet_equipment, wet_exercise_type) ผู้เรียกเป็นคนอ่านจาก DB ฟังก์ชันคำนวณไม่แตะ DB
type ExerciseProfile struct {
	Equipment    int8 // wet_equipment (5 = Bodyweight, อื่นๆ = แรงต้านและอุปกรณ์)
	ExerciseType int8 // wet_exercise_type (1 = Compound, 2 = Isolation)
}

// resolveSetBaseMET เลือก MET ให้ 1 เซตตาม Dynamic METs Logic Matrix (ตารางในคอมเมนต์หัวไฟล์) —
// restSeconds เป็นค่าจริงถ้ามี ไม่งั้นเป็น proxy จากความหนาแน่นเฉลี่ยทั้งเซสชัน (ผู้เรียกเป็นคนตัดสินใจ
// ว่าจะส่งค่าไหนมา) ไล่เงื่อนไขบนลงล่าง เจอข้อแรกที่ตรงแล้วหยุด
func resolveSetBaseMET(profile ExerciseProfile, reps int, restSeconds float64) float64 {
	if profile.Equipment == EquipmentBodyweight {
		switch {
		case profile.ExerciseType == ExerciseTypeIsolation: // หน้าท้อง/ความพยายามน้อย
			return BodyweightMETLightAbdominal
		case restSeconds < BodyweightRestContinuousBelowSeconds: // ต่อเนื่อง ความพยายามอย่างหนัก
			return BodyweightMETHeavy
		case restSeconds <= BodyweightRestModerateMaxSeconds: // ความพยายามปานกลาง
			return BodyweightMETModerate
		default: // พักนาน ความพยายามน้อย
			return BodyweightMETLight
		}
	}

	switch {
	case reps < ResistanceHeavyRepsBelow: // หนักมาก จนหมดแรง (พาวเวอร์ลิฟติ้ง)
		return ResistanceMETHeavy
	case profile.ExerciseType == ExerciseTypeCompound ||
		(restSeconds >= ResistanceRestModerateMinSeconds && restSeconds <= ResistanceRestModerateMaxSeconds):
		return ResistanceMETModerate
	default: // Isolation/น้ำหนักเบา/พักนอกช่วงปานกลาง
		return ResistanceMETLight
	}
}

// WeightTrainingCalorieResult คือผลคำนวณละเอียดของเซสชัน 1 ครั้ง — ทุกฟิลด์ (ไม่ใช่แค่
// TotalCalories) ถูก return ไว้เพื่อความโปร่งใส/ตรวจสอบย้อนหลังได้ (แสดงใน response ให้ debug ได้
// ว่าทำไมได้ค่านี้ ไม่ใช่กล่องดำ)
type WeightTrainingCalorieResult struct {
	SessionBaseMET   float64 // ค่าเฉลี่ย MET ต่อเซตจาก Logic Matrix = FinalMET เสมอ (ไม่มีตัวคูณต่อ)
	FinalMET         float64
	DurationMinutes  float64 // เวลารวมทั้งเซสชัน (นาที) ที่ใช้คำนวณ = total_duration_seconds ÷ 60 ตรงๆ ไม่มีเพดาน
	TotalCalories    float64 // NET (หัก 1 MET แล้ว) รวมทั้งเซสชัน
	CaloriesPerSet   float64 // TotalCalories หารเท่ากันทุกเซต — ใช้เก็บลง wtrs_calories รายแถว
	// IntensityLevel (1=เบา, 2=กลาง, 3=หนัก) เป็น label แสดงผลเท่านั้น มาจาก %1RM เฉลี่ยของเซสชัน
	// เทียบสถิติที่ดีที่สุดของสมาชิก — ไม่คูณเข้ากับ Final MET แล้ว (ดูคอมเมนต์หัวไฟล์)
	IntensityLevel int8
}

// CalculateWeightTrainingCalories คำนวณพลังงานเวทเทรนนิ่งทั้งเซสชันในครั้งเดียว (ตรงข้ามกับของเดิม
// ที่คำนวณทีละเซตแยกกัน) — oneRepMax คือ 1RM ที่ดีที่สุดของสมาชิกคนนี้ในท่านี้ (ดึงจาก
// getBestOneRepMax ก่อนเรียกฟังก์ชันนี้ — ฟังก์ชันนี้ไม่แตะ DB) ส่ง 0 ถ้าไม่มีประวัติ, sets[i].RestSeconds
// เป็น nil ได้ (เซตสุดท้ายที่ไม่มีการพักจริง หรือแถวเก่าก่อน 2026-09-18) จะใช้ค่าเฉลี่ยเวลาพักของเซตอื่น
// (ไม่มีเลยจึงใช้ความหนาแน่นเฉลี่ยทั้งเซสชัน) แทนต่อเซตนั้น —
// oneRepMax ใช้ทำ IntensityLevel (label แสดงผล) เท่านั้น ไม่มีผลต่อการเลือก MET, profile คือหมวด/
// ประเภทของท่าที่ฝึก (Logic Matrix)
func CalculateWeightTrainingCalories(bodyWeightKg float64, totalDurationSeconds int, oneRepMax float64, profile ExerciseProfile, sets []SetLog) WeightTrainingCalorieResult {
	validSets := make([]SetLog, 0, len(sets))
	for _, s := range sets {
		if s.Reps > 0 {
			validSets = append(validSets, s)
		}
	}
	if len(validSets) == 0 {
		return WeightTrainingCalorieResult{}
	}
	totalSets := float64(len(validSets))

	// ฐานเวลา = เวลารวมทั้งเซสชัน (รวมช่วงพัก) ตรงๆ เหมือนคาร์ดิโอ ไม่มีเพดาน ค่านี้ใช้ตามที่รับมา — การตรวจ
	// ความสมเหตุสมผลของเวลาเป็นหน้าที่ของชั้นรับอินพุต ไม่ใช่ของสูตร ความหนาแน่น (นาที/เซต) ใช้เป็น proxy แทนเวลาพัก
	// รายเซตเมื่อไม่มีเวลาพักจริงเลยทั้งเซสชัน (ดูคอมเมนต์หัวไฟล์)
	durationMinutes := float64(totalDurationSeconds) / 60.0
	densityProxySeconds := durationMinutes / totalSets * 60.0

	// เวลาพักที่ใช้แทนเซตที่ไม่ทราบ (RestSeconds = nil) = ค่าเฉลี่ยของเซตที่ทราบในเซสชันเดียวกัน — ไม่มีเซตไหน
	// ทราบเลยจึงใช้ proxy ความหนาแน่น เซตสุดท้ายที่ไม่มีการพักจริงจึงไม่ดึง MET เฉลี่ยไปทางใดทางหนึ่ง
	unknownRestSeconds := densityProxySeconds
	knownRestSum, knownRestCount := 0.0, 0.0
	for _, s := range validSets {
		if s.RestSeconds != nil {
			knownRestSum += float64(*s.RestSeconds)
			knownRestCount++
		}
	}
	if knownRestCount > 0 {
		unknownRestSeconds = knownRestSum / knownRestCount
	}

	// MET ต่อเซตตาม Logic Matrix (ตารางในคอมเมนต์หัวไฟล์) แล้วเฉลี่ยเป็น Session MET
	sumBaseMET := 0.0
	for _, s := range validSets {
		restSeconds := unknownRestSeconds
		if s.RestSeconds != nil {
			restSeconds = float64(*s.RestSeconds)
		}
		sumBaseMET += resolveSetBaseMET(profile, s.Reps, restSeconds)
	}
	sessionBaseMET := sumBaseMET / totalSets

	// IntensityLevel: %1RM เฉลี่ยของเซสชัน → label แสดงผล (เบา/กลาง/หนัก) เท่านั้น ไม่ใช้เลือก MET
	// และไม่คูณเข้ากับ Final MET (Logic Matrix ไม่อิง %1RM ดูคอมเมนต์หัวไฟล์) —
	// ไม่มีประวัติ 1RM หรือทุกเซตเป็นท่า bodyweight (weight=0) → ถือเป็นกลาง ไม่เดาว่าหนักหรือเบา
	intensityLevel := int8(2)
	if oneRepMax > 0 {
		sumRI := 0.0
		countRI := 0.0
		for _, s := range validSets {
			if s.WeightKg > 0 {
				sumRI += s.WeightKg / oneRepMax
				countRI++
			}
		}
		if countRI > 0 {
			avgRI := sumRI / countRI
			switch {
			case avgRI < 0.50:
				intensityLevel = 1
			case avgRI < 0.70:
				intensityLevel = 2
			default:
				intensityLevel = 3
			}
		}
	}

	// Final MET = Session MET ตรงๆ (ไม่มีตัวคูณต่อ) — clamp เป็นเซฟตี้เน็ตเฉยๆ เพราะค่าจาก
	// Logic Matrix (2.8-8.0) ไม่มีวันชนขอบ [1.5, 9.5] อยู่แล้ว
	finalMET := sessionBaseMET
	if finalMET < WeightTrainingMETFloor {
		finalMET = WeightTrainingMETFloor
	}
	if finalMET > WeightTrainingMETCeil {
		finalMET = WeightTrainingMETCeil
	}

	// NET calories: หัก 1 MET (=พลังงานพักนิ่ง) ก่อนคืนค่า — เหตุผลเดียวกับ SaveCardioResult กัน
	// นับซ้ำตอนรวมกับ Baseline Expenditure (BMR×1.2) เป็น Total Daily Energy Output
	totalCalories := NetEnergyKcal(finalMET, bodyWeightKg, durationMinutes)

	return WeightTrainingCalorieResult{
		SessionBaseMET:   sessionBaseMET,
		FinalMET:         finalMET,
		DurationMinutes:  durationMinutes,
		TotalCalories:    totalCalories,
		CaloriesPerSet:   totalCalories / totalSets,
		IntensityLevel:   intensityLevel,
	}
}