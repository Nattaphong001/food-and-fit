package services

import "food_and_fit_api/models"

// NutrientTotals คือพลังงานและสารอาหารรวมของอาหาร 1 รายการที่กิน (หน่วย: kcal และกรัม)
type NutrientTotals struct {
	Calories float64
	Protein  float64
	Carb     float64
	Fat      float64
}

// CalculateNutrientTotals คำนวณค่าที่เก็บลง daily_nutrition (dntt_total_*) = ค่าต่อ 1 หน่วยเสิร์ฟใน
// ตาราง nutrition (ntt_*) × จำนวนหน่วยที่กิน (dntt_quantity) ครบทั้ง 4 ค่าพร้อมกัน — จุดเดียวที่มีสูตรนี้
// (AddDailyNutrition และ UpdateDailyNutrition เรียกที่นี่ เดิมเขียนซ้ำ 2 จุดใน controller)
func CalculateNutrientTotals(food models.Nutrition, quantity float64) NutrientTotals {
	return NutrientTotals{
		Calories: food.NttCalories * quantity,
		Protein:  food.NttProtein * quantity,
		Carb:     food.NttCarbs * quantity,
		Fat:      food.NttFat * quantity,
	}
}
