package services

import "food_and_fit_api/models"

// NutrientTotals คือพลังงานและสารอาหารรวมของอาหาร 1 รายการที่กิน (หน่วย: kcal และกรัม)
type NutrientTotals struct {
	Calories float64
	Protein  float64
	Carb     float64
	Fat      float64
}

// CalculateNutrientTotals คำนวณพลังงาน/สารอาหารรวมของอาหาร 1 รายการที่กิน
// = ค่าต่อ 1 หน่วย (จากตาราง nutrition) × จำนวนหน่วยที่กิน (quantity)
// จุดเดียวที่มีสูตรนี้ — เรียกจากทั้ง AddDailyNutrition และ UpdateDailyNutrition
func CalculateNutrientTotals(food models.Nutrition, quantity float64) NutrientTotals {
	return NutrientTotals{
		Calories: food.NttCalories * quantity,
		Protein:  food.NttProtein * quantity,
		Carb:     food.NttCarbs * quantity,
		Fat:      food.NttFat * quantity,
	}
}
