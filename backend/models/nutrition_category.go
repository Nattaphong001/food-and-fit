package models

// [TOC]
// [STRUCT] NutritionCategory
// [FUNCTION] NutritionCategory.TableName

// [STRUCT]: NutritionCategory mirrors DB table `nutrition_category` — lookup table for food categories.
// Fields: NttcID (PK, autoincrement), NttcName (category name, varchar(100)), NttcImage (image path, varchar(255)).
// #region [STRUCT] NutritionCategory
type NutritionCategory struct {
	NttcID    uint   `gorm:"primaryKey;column:nttc_id;autoIncrement" json:"nttc_id"`
	NttcName  string `gorm:"column:nttc_name;type:varchar(100);not null" json:"nttc_name"`
	NttcImage string `gorm:"column:nttc_image;type:varchar(255)" json:"nttc_image"`
}

// #endregion

// [FUNCTION]: TableName tells GORM which DB table this struct maps to.
// Outputs: string — "nutrition_category".
// #region [FUNCTION] NutritionCategory.TableName
func (NutritionCategory) TableName() string {
	return "nutrition_category"
}

// #endregion
