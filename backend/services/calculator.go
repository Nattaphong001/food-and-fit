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
	// 1. BMI [cite: 370]
	heightInMeters := height / 100
	bmi = weight / (heightInMeters * heightInMeters)

	// 2. BMR [cite: 383, 384]
	if gender == 1 { // ชาย
		bmr = (10 * weight) + (6.25 * height) - float64(5*age) + 5
	} else { // หญิง
		bmr = (10 * weight) + (6.25 * height) - float64(5*age) - 161
	}

	// 3. TDEE [cite: 388]
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