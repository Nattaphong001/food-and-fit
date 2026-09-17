package services

import (
	"math"
	"time" 
)

// คำนวณอายุจากวันเกิด (รูปแบบ YYYY-MM-DD)
func CalculateAge(birthDate string) int {
	// 1. แปลง string วันเกิดเป็น time.Time
	t, err := time.Parse("2006-01-02", birthDate)
	if err != nil {
		return 25 // ถ้าแปลงไม่ได้ ให้คืนค่า default หรือจัดการ error
	}

	now := time.Now()
	years := now.Year() - t.Year()

	// 2. เช็คว่าถึงวันเกิดในปีนี้หรือยัง ถ้ายังไม่ถึงต้องลบออก 1 ปี
	if now.YearDay() < t.YearDay() {
		years--
	}

	return years
}

// Baseline Expenditure = BMR × 1.2 (ค่าสัมประสิทธิ์ Sedentary ตามเกณฑ์ Institute of Medicine, 2548)
// ใช้หา Total Daily Energy Output รายวัน (บทที่ 2 หัวข้อ 2.1.4.6) — คนละสูตรกับ TDEE ใน
// CalculateGoals ที่คูณด้วย activityLevel จริงของสมาชิก (ใช้หา Target Calories) ห้ามรวมเป็น
// ฟังก์ชันเดียวกัน มิฉะนั้นพลังงานออกกำลังกายจะถูกนับซ้ำสองรอบ
const SedentaryCoefficient = 1.2

func CalculateBaselineExpenditure(bmr float64) float64 {
	return bmr * SedentaryCoefficient
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

	// 4. Target Calories - เป้าหมาย: 1=ลดน้ำหนัก, 2=เพิ่มกล้ามเนื้อ, 3=รักษาน้ำหนัก
	switch target {
	case 1: // ลดน้ำหนัก (Deficit 20%)
		targetCalories = tdee - (tdee * 0.20)
		if targetCalories < bmr { // เงื่อนไขความปลอดภัย ห้ามต่ำกว่า BMR
			targetCalories = bmr
		}
	case 2: // เพิ่มกล้ามเนื้อ (Surplus 15%)
		targetCalories = tdee + (tdee * 0.15)
	default: // 3 = รักษาน้ำหนัก
		targetCalories = tdee
	}

	// ปัดเศษให้เป็นทศนิยม 2 ตำแหน่ง
	return math.Round(bmi*100)/100, math.Round(bmr*100)/100, math.Round(tdee*100)/100, math.Round(targetCalories*100)/100
}

// ═══════════════════════════════════════════════════════════════════════
// Weight Training — Smart Auto Calorie (ออกแบบ 2026-09-08, Step 1 เปลี่ยนเป็น Dynamic Base MET 2026-09-18)
// ═══════════════════════════════════════════════════════════════════════
// แทนที่ระบบเดิมที่ผู้ใช้เลือกความหนัก 3 ระดับเอง (wtrs_intensity_level) ซึ่งไม่เคยทำงานจริง —
// mobile ไม่เคยส่งค่านี้ขึ้น API เลย ทุกแถวใน DB จริงก่อนหน้านี้ fallback เป็น 1 (เบา) หมด
//
// คงสูตรฐาน METs × น้ำหนักตัว(kg) × เวลา(ชม.) เดียวกับสูตรคาร์ดิโอ (ไม่ใช้ ACSM form
// MET×3.5×W/200×T เพื่อไม่ต้องแก้บทที่ 2 และให้สูตรตรงกับคาร์ดิโอ) — MET หาจาก 3 อย่างที่ระบบรู้:
//  (1) Reps + เวลาพักต่อเซต (ดูตาราง Dynamic Base MET ด้านล่าง) → SessionBaseMET
//  (2) น้ำหนักที่ใช้เล่นเทียบ 1RM                                → kLoad
//  (3) ความหนาแน่นของการฝึก (เวลา/เซต)                           → kDensity
//
// [Step 1] Dynamic Base MET ต่อเซต — เลือกจากตาราง lookup ต่อไปนี้ (เฉพาะ 3 แถวแรกมี entry ตรงใน
// สเปกต้นฉบับ ส่วนแถว "Reps > 15" ไม่มี entry ตรงใน Compendium of Physical Activities โดยตรง เป็น
// การตีความขยายของผู้วิจัยเอง ใช้ 02054 (MET 3.5) เป็นค่าประมาณใกล้เคียงที่สุดแทน — ถ้าถูกถามตอนสอบ
// ว่าเลข 3.5 ของ Reps>15 มาจากไหน คำตอบคือ "ไม่มีรายการตรงกัน ใช้รายการใกล้เคียงที่สุดเป็นค่าประมาณ"
// ไม่ใช่ "Compendium ระบุไว้ตรงๆ"):
//
//	พักระหว่างเซต   Reps     MET   หมายเหตุ
//	< 30 วินาที      ใดๆ      8.0   ตามสเปก
//	30–60 วินาที     ใดๆ      4.3   ตามสเปก
//	≥ 60 วินาที      < 8      6.0   ตามสเปก
//	≥ 60 วินาที      8–15     3.5   ตามสเปก (02054)
//	≥ 60 วินาที      > 15     3.5   ส่วนขยาย — ไม่มี entry ตรง ใช้ 02054 ใกล้เคียงสุดแทน (ดูหมายเหตุบน)
//
// เวลาพักต่อเซต: เพิ่งมีคอลัมน์เก็บค่าจริง (wtrs_rest_seconds, migrations/2026-09-18_add_weight_
// training_rest_seconds.sql) มือถือยังไม่ได้แก้ให้ส่งค่านี้ขึ้น API จริง ณ วันที่เพิ่ม — ทุกเซตตอนนี้
// RestSeconds = nil เสมอ ระบบ fallback ไปใช้ "ความหนาแน่นเฉลี่ยทั้งเซสชัน" (cappedMinutes/totalSets
// แปลงเป็นวินาที) แทนเวลาพักต่อเซตจริงเป็น proxy ชั่วคราว — ใช้ค่าจริงต่อเซตทันทีที่มือถือส่งมาให้
const (
	// เพดานเวลาเฉลี่ยต่อเซต (นาที) กันนับเวลาพักเกิน/ลืมกดจบเวิร์กเอาท์ซ้ำกับ Baseline
	// Expenditure (BMR×1.2) ที่นับพลังงานพักนิ่งไปแล้ว — ไม่มีเพดานนี้ พักนานเท่าไหร่ก็ยิ่งได้
	// พลังงานเพิ่มไม่จำกัด ทั้งที่งานที่ทำจริงเท่าเดิม
	WeightTrainingCapMinutesPerSet = 4.0

	// ขอบเขต Final MET กันหลุดขอบจากอินพุตสุดโต่ง (ไม่ใช่ค่าที่ควรชนบ่อยในการใช้งานปกติ)
	WeightTrainingMETFloor = 1.5
	WeightTrainingMETCeil  = 9.5

	// เกณฑ์เวลาพัก (วินาที) ของตาราง Dynamic Base MET ข้างบน — ขอบเขตแบบ [ต่ำสุด, สูงสุด)
	// ดังนั้น 60 วินาทีพอดีตกอยู่ในโซน "≥ 60 วินาที" (แยกด้วย Reps) ไม่ใช่โซน "30–60 วินาที"
	RestShortThresholdSeconds  = 30.0
	RestMediumThresholdSeconds = 60.0

	// เกณฑ์ Reps ของตาราง Dynamic Base MET ข้างบน (เฉพาะโซนพัก ≥ 60 วินาที) — ฝั่ง Reps ≥ 8 ครอบคลุม
	// ทั้งแถว 8-15 (ตามสเปก) และ >15 (ส่วนขยาย) เพราะ MET เท่ากันทั้งคู่ (3.5) ไม่ต้องแยกเงื่อนไข
	LowRepsThreshold = 8
)

// SetLog คือ 1 เซตที่นับรวมในเซสชัน
type SetLog struct {
	WeightKg float64 // น้ำหนักที่ยกจริง (0 = ท่า bodyweight)
	Reps     int
	// RestSeconds คือเวลาพักหลังเซตนี้ (วินาที) ก่อนเริ่มเซตถัดไป — nil = ไม่ทราบ (มือถือยังไม่ส่งมา)
	// ระบบ fallback ไปใช้ความหนาแน่นเฉลี่ยทั้งเซสชันแทน ดูคอมเมนต์หัวไฟล์
	RestSeconds *int
}

// resolveSetBaseMET เลือก Dynamic Base MET ให้ 1 เซต ตามตาราง lookup ในคอมเมนต์หัวไฟล์ — restSeconds
// เป็นค่าจริงถ้ามี ไม่งั้นเป็น proxy จากความหนาแน่นเฉลี่ยทั้งเซสชัน (ผู้เรียกเป็นคนตัดสินใจว่าจะส่งค่าไหนมา)
func resolveSetBaseMET(reps int, restSeconds float64) float64 {
	switch {
	case restSeconds < RestShortThresholdSeconds: // พัก < 30 วินาที
		return 8.0
	case restSeconds < RestMediumThresholdSeconds: // พัก 30–60 วินาที
		return 4.3
	case reps < LowRepsThreshold: // พัก ≥ 60 วินาที, reps < 8
		return 6.0
	default: // พัก ≥ 60 วินาที, reps ≥ 8 (ครอบคลุมทั้ง 8-15 ตามสเปก และ >15 ส่วนขยาย — ดูคอมเมนต์หัวไฟล์)
		return 3.5
	}
}

// WeightTrainingCalorieResult คือผลคำนวณละเอียดของเซสชัน 1 ครั้ง — ทุกฟิลด์ (ไม่ใช่แค่
// TotalCalories) ถูก return ไว้เพื่อความโปร่งใส/ตรวจสอบย้อนหลังได้ (แสดงใน response ให้ debug ได้
// ว่าทำไมได้ค่านี้ ไม่ใช่กล่องดำ)
type WeightTrainingCalorieResult struct {
	SessionBaseMET   float64
	KLoad            float64
	KDensity         float64
	FinalMET         float64
	EffectiveMinutes float64 // เวลาที่ใช้จริงในการคำนวณ (หลังผ่านเพดาน CapMinutesPerSet แล้ว)
	TotalCalories    float64 // NET (หัก 1 MET แล้ว) รวมทั้งเซสชัน
	CaloriesPerSet   float64 // TotalCalories หารเท่ากันทุกเซต — ใช้เก็บลง wtrs_calories รายแถว
	IntensityLevel   int8    // 1=เบา(kLoad 0.90) 2=กลาง(1.00) 3=หนัก(1.10) — ระบบอนุมานเอง ไม่ใช่ผู้ใช้เลือก
}

// CalculateWeightTrainingCalories คำนวณพลังงานเวทเทรนนิ่งทั้งเซสชันในครั้งเดียว (ตรงข้ามกับของเดิม
// ที่คำนวณทีละเซตแยกกัน) — oneRepMax คือ 1RM ที่ดีที่สุดของสมาชิกคนนี้ในท่านี้ (ดึงจาก
// getBestOneRepMax ก่อนเรียกฟังก์ชันนี้ — ฟังก์ชันนี้ไม่แตะ DB) ส่ง 0 ถ้าไม่มีประวัติ, sets[i].RestSeconds
// เป็น nil ได้ (มือถือยังไม่ส่งมา) จะ fallback ไปใช้ความหนาแน่นเฉลี่ยทั้งเซสชันแทนต่อเซตนั้น
func CalculateWeightTrainingCalories(bodyWeightKg float64, totalDurationSeconds int, oneRepMax float64, sets []SetLog) WeightTrainingCalorieResult {
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

	// เพดานเวลา + ความหนาแน่น (นาที/เซต) — คำนวณก่อน Step 1 เพราะใช้เป็น proxy แทนเวลาพักรายเซตจริง
	// เมื่อ SetLog.RestSeconds เป็น nil (ดูคอมเมนต์หัวไฟล์)
	actualMinutes := float64(totalDurationSeconds) / 60.0
	cappedMinutes := math.Min(actualMinutes, totalSets*WeightTrainingCapMinutesPerSet)
	density := cappedMinutes / totalSets
	densityProxySeconds := density * 60.0

	// Step 1: Dynamic Base MET ต่อเซต (ตาราง lookup ในคอมเมนต์หัวไฟล์) แล้วเฉลี่ยเป็น Session Base MET
	sumBaseMET := 0.0
	for _, s := range validSets {
		restSeconds := densityProxySeconds
		if s.RestSeconds != nil {
			restSeconds = float64(*s.RestSeconds)
		}
		sumBaseMET += resolveSetBaseMET(s.Reps, restSeconds)
	}
	sessionBaseMET := sumBaseMET / totalSets

	// Step 2: เพดานเวลา + ความหนาแน่น (นาที/เซต) — แทนตัวคูณขั้นบันได 3 ระดับของสเปกตั้งต้น
	// (1.2/1.0/0.85 ที่กระโดดเป็นหน้าผาตรงรอยต่อ) ด้วยเส้นตรงไล่ระดับต่อเนื่องช่วง 1.0-3.0 นาที/เซต
	var kDensity float64
	switch {
	case density <= 1.0:
		kDensity = 1.20
	case density < 3.0:
		kDensity = 1.20 - 0.15*(density-1.0)
	default:
		kDensity = 0.90
	}

	// Step 3: %1RM เฉลี่ยของเซสชัน → ระดับความหนัก (kLoad) — ไม่มีประวัติ 1RM หรือทุกเซตเป็นท่า
	// bodyweight (weight=0) → ถือเป็นกลาง (kLoad=1.0) ไม่เดาว่าหนักหรือเบาโดยไม่มีข้อมูล
	kLoad := 1.0
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
				kLoad, intensityLevel = 0.90, 1
			case avgRI < 0.70:
				kLoad, intensityLevel = 1.00, 2
			default:
				kLoad, intensityLevel = 1.10, 3
			}
		}
	}

	// Step 4: Final MET + clamp
	finalMET := sessionBaseMET * kLoad * kDensity
	if finalMET < WeightTrainingMETFloor {
		finalMET = WeightTrainingMETFloor
	}
	if finalMET > WeightTrainingMETCeil {
		finalMET = WeightTrainingMETCeil
	}

	// NET calories: หัก 1 MET (=พลังงานพักนิ่ง) ก่อนคืนค่า — เหตุผลเดียวกับ SaveCardioResult กัน
	// นับซ้ำตอนรวมกับ Baseline Expenditure (BMR×1.2) เป็น Total Daily Energy Output
	effectiveHours := cappedMinutes / 60.0
	totalCalories := (finalMET - 1) * bodyWeightKg * effectiveHours
	if totalCalories < 0 {
		totalCalories = 0
	}

	return WeightTrainingCalorieResult{
		SessionBaseMET:   sessionBaseMET,
		KLoad:            kLoad,
		KDensity:         kDensity,
		FinalMET:         finalMET,
		EffectiveMinutes: cappedMinutes,
		TotalCalories:    totalCalories,
		CaloriesPerSet:   totalCalories / totalSets,
		IntensityLevel:   intensityLevel,
	}
}