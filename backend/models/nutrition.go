package models

// [TOC]
// [SECTION] Imports
// [STRUCT] Nutrition
// [FUNCTION] Nutrition.TableName
// [STRUCT] DailyNutrition
// [FUNCTION] DailyNutrition.TableName

// [SECTION]: Imports — standard library deps used by structs below.
// #region [SECTION] Imports
import "time"

// #endregion

// [STRUCT]: Nutrition mirrors DB table `nutrition` — master food/nutrition-info records
// (name, calories, macros, serving info, image) plus its category relation.
// Fields: NttID (PK), NttFoodName, NttCalories, NttServingWeight, NttUnit, NttProtein,
// NttCarbs, NttFat, NttFoodImage, NttcID (FK), Category (belongs-to NutritionCategory).
// #region [STRUCT] Nutrition
type Nutrition struct {
	NttID            uint    `gorm:"primaryKey;column:ntt_id;autoIncrement" json:"ntt_id"`
	NttFoodName      string  `gorm:"column:ntt_food_name;type:varchar(100);not null" json:"ntt_food_name"`
	NttCalories      float64 `gorm:"column:ntt_calories;type:decimal(7,2)" json:"ntt_calories"`
	NttServingWeight int     `gorm:"column:ntt_serving_weight" json:"ntt_serving_weight"`
	NttUnit          string  `gorm:"column:ntt_unit;type:varchar(50)" json:"ntt_unit"`
	NttProtein       float64 `gorm:"column:ntt_protein;type:decimal(5,1)" json:"ntt_protein"`
	NttCarbs         float64 `gorm:"column:ntt_carbs;type:decimal(5,1)" json:"ntt_carbs"`
	NttFat           float64 `gorm:"column:ntt_fat;type:decimal(5,1)" json:"ntt_fat"`
	NttFoodImage     string  `gorm:"column:ntt_food_image;type:varchar(255)" json:"ntt_food_image"`
	NttcID           uint    `gorm:"column:nttc_id" json:"nttc_id"`

	// เชื่อมความสัมพันธ์กับ Category (ถ้าต้องการให้ดึงชื่อประเภทมาโชว์ด้วย)
	Category NutritionCategory `gorm:"foreignKey:NttcID;references:NttcID" json:"category"`
}

// #endregion

// [FUNCTION]: TableName returns the DB table name for GORM mapping.
// Outputs: string — "nutrition".
// กำหนดชื่อตารางให้ตรงกับใน DB
// #region [FUNCTION] Nutrition.TableName
func (Nutrition) TableName() string {
	return "nutrition"
}

// #endregion

// [STRUCT]: DailyNutrition mirrors DB table `daily_nutrition` — a member's per-meal logged intake
// for a given date (meal type, quantity, computed totals, optional photo, optional link to Nutrition).
// Fields: DnttID (PK), MbID (FK member), NttID (nullable FK nutrition), DnttDate, DnttTime,
// DnttMealType, DnttFoodName, DnttQuantity, DnttUnit, DnttTotalCalories/Protein/Carb/Fat,
// DnttImage, CreatedAt, UpdatedAt, Nutrition (belongs-to Nutrition).
// #region [STRUCT] DailyNutrition
type DailyNutrition struct {
	DnttID            uint      `gorm:"primaryKey;column:dntt_id;autoIncrement" json:"dntt_id"`
	MbID              int       `gorm:"column:mb_id" json:"mb_id"`
	NttID             *uint     `gorm:"column:ntt_id" json:"ntt_id"`
	DnttDate          string    `gorm:"column:dntt_date;type:date" json:"dntt_date"`
	DnttTime          string    `gorm:"column:dntt_time" json:"dntt_time"`
	DnttMealType      int8      `gorm:"column:dntt_meal_type;type:tinyint" json:"dntt_meal_type"`
	DnttFoodName      string    `gorm:"column:dntt_food_name;type:varchar(100)" json:"dntt_food_name"`
	DnttQuantity      float64   `gorm:"column:dntt_quantity;type:decimal(5,2)" json:"dntt_quantity"`
	DnttUnit          string    `gorm:"column:dntt_unit;type:varchar(50)" json:"dntt_unit"`
	DnttTotalCalories float64   `gorm:"column:dntt_total_calories;type:decimal(7,2)" json:"dntt_total_calories"`
	DnttTotalProtein  float64   `gorm:"column:dntt_total_protein;type:decimal(5,2)" json:"dntt_total_protein"`
	DnttTotalCarb     float64   `gorm:"column:dntt_total_carb;type:decimal(5,2)" json:"dntt_total_carb"`
	DnttTotalFat      float64   `gorm:"column:dntt_total_fat;type:decimal(5,2)" json:"dntt_total_fat"`
	DnttImage         string    `gorm:"column:dntt_image;type:varchar(255)" json:"dntt_image"`
	CreatedAt         time.Time `gorm:"column:dntt_created_at;autoCreateTime" json:"created_at"`
	UpdatedAt         time.Time `gorm:"column:dntt_updated_at;autoUpdateTime" json:"updated_at"`
	Nutrition         Nutrition `gorm:"foreignKey:NttID;references:NttID" json:"nutrition"`
}

func (DailyNutrition) TableName() string { return "daily_nutrition" }
