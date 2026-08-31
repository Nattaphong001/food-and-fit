package controllers

import (
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"

	"food_and_fit_api/config"
	"food_and_fit_api/helpers"
	"food_and_fit_api/models"
	"food_and_fit_api/utils"

	"github.com/gin-gonic/gin"
)

// endpoint ใหม่สำหรับหน้าฐานข้อมูลโภชนาการฝั่ง Admin Web — กรอง+เรียง+pagination ระดับ SQL
// แยกจาก GetAllNutrition (/api/nutrition/foods) เพราะตัวนั้นแอปมือถือเรียกใช้อยู่จริง (ดู
// nutrition_service.dart) ห้ามแก้ signature/response เดิม (CLAUDE.md ข้อ 2) จึงเพิ่ม endpoint
// ใหม่นี้แทน อยู่ใต้ adminProtected เท่านั้น

// sort_by ต้องตรงกับ enum จริงใน manage_food_items_view.dart (_sortKeys) ไม่ใช่เดาเอง —
// "category" ต้อง join ไปเรียงตามชื่อประเภท ไม่ใช่เรียงตาม nttc_id (ผู้ใช้ต้องการเรียง ก-ฮ ของชื่อ)
var nutritionSortColumns = map[string]string{
	"name":    "ntt_food_name",
	"kcal":    "ntt_calories",
	"protein": "ntt_protein",
	"carbs":   "ntt_carbs",
	"fat":     "ntt_fat",
}

// [FEATURE] FOOD_LOG
// [FUNCTION] GetAdminNutritionFoods
// [DESCRIPTION] ดึงรายการโภชนาการอาหารแบบกรอง+เรียงลำดับ+pagination ระดับ SQL สำหรับหน้า
//
//	ฐานข้อมูลโภชนาการฝั่ง Admin Web (ตารางข้อมูลโตไม่จำกัด ห้ามดึงทั้งหมดมากรองที่ Dart)
//
// [INPUT] query: search, category_id, kcal_min, kcal_max, sort_by, sort_order, page, page_size
// [OUTPUT] {data: []Nutrition (พร้อม category), total, page, page_size}
func GetAdminNutritionFoods(c *gin.Context) {
	page, pageSize, offset := utils.ParsePagination(c)

	query := config.DB.Model(&models.Nutrition{})

	if search := strings.TrimSpace(c.Query("search")); search != "" {
		query = query.Where("ntt_food_name LIKE ?", "%"+search+"%")
	}
	if catIDStr := c.Query("category_id"); catIDStr != "" {
		if catID, err := strconv.Atoi(catIDStr); err == nil {
			query = query.Where("nttc_id = ?", catID)
		}
	}
	if kcalMinStr := c.Query("kcal_min"); kcalMinStr != "" {
		if kcalMin, err := strconv.Atoi(kcalMinStr); err == nil {
			query = query.Where("ntt_calories >= ?", kcalMin)
		}
	}
	if kcalMaxStr := c.Query("kcal_max"); kcalMaxStr != "" {
		if kcalMax, err := strconv.Atoi(kcalMaxStr); err == nil {
			query = query.Where("ntt_calories <= ?", kcalMax)
		}
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "นับจำนวนรายการไม่สำเร็จ"})
		return
	}

	sortOrder := "ASC"
	if strings.EqualFold(c.Query("sort_order"), "desc") {
		sortOrder = "DESC"
	}

	sortByParam := c.DefaultQuery("sort_by", "name")

	var foods []models.Nutrition
	if sortByParam == "category" {
		query = query.Joins("JOIN nutrition_category ON nutrition_category.nttc_id = nutrition.nttc_id").
			Select("nutrition.*").
			Order("nutrition_category.nttc_name " + sortOrder)
	} else {
		col, ok := nutritionSortColumns[sortByParam]
		if !ok {
			col = "ntt_food_name"
		}
		query = query.Order(col + " " + sortOrder)
	}

	if err := query.Preload("Category").Offset(offset).Limit(pageSize).Find(&foods).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถดึงข้อมูลโภชนาการได้"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data":      foods,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// [FEATURE] FOOD_LOG
// [FUNCTION] GetAdminNutritionFoodIds
// [DESCRIPTION] คืน id ทั้งหมดที่ตรงตัวกรองปัจจุบัน (ไม่แบ่งหน้า) ใช้สำหรับปุ่ม "เลือกทั้งหมด
//               N รายการที่แสดงอยู่" ของ bulk action ฝั่งหน้าเว็บ — ต้องครอบทุกหน้า ไม่ใช่แค่
//               หน้าที่กำลังเปิดดู ตัวกรองต้องตรงกับ GetAdminNutritionFoods เป๊ะ (ใช้เงื่อนไขเดียวกัน)
// [INPUT] query: search, category_id, kcal_min, kcal_max (เหมือน GetAdminNutritionFoods แต่ไม่มี page/sort)
// [OUTPUT] {ids: []uint, total: int}
// [RELATED] FOOD_LOG
func GetAdminNutritionFoodIds(c *gin.Context) {
	query := config.DB.Model(&models.Nutrition{})

	if search := strings.TrimSpace(c.Query("search")); search != "" {
		query = query.Where("ntt_food_name LIKE ?", "%"+search+"%")
	}
	if catIDStr := c.Query("category_id"); catIDStr != "" {
		if catID, err := strconv.Atoi(catIDStr); err == nil {
			query = query.Where("nttc_id = ?", catID)
		}
	}
	if kcalMinStr := c.Query("kcal_min"); kcalMinStr != "" {
		if kcalMin, err := strconv.Atoi(kcalMinStr); err == nil {
			query = query.Where("ntt_calories >= ?", kcalMin)
		}
	}
	if kcalMaxStr := c.Query("kcal_max"); kcalMaxStr != "" {
		if kcalMax, err := strconv.Atoi(kcalMaxStr); err == nil {
			query = query.Where("ntt_calories <= ?", kcalMax)
		}
	}

	var ids []uint
	if err := query.Pluck("ntt_id", &ids).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถดึงรายการ id ได้"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"ids": ids, "total": len(ids)})
}

type bulkIDsRequest struct {
	IDs []uint `json:"ids"`
}

type bulkFailedItem struct {
	ID     uint   `json:"id"`
	Name   string `json:"name"`
	Reason string `json:"reason"`
}

type bulkSucceededItem struct {
	ID   uint   `json:"id"`
	Name string `json:"name"`
}

// [FEATURE] FOOD_LOG
// [FUNCTION] BulkDeleteNutritionFoods
// [DESCRIPTION] ลบรายการอาหารหลายรายการพร้อมกัน — ทำทีละรายการ ไม่ใช้ transaction แบบ all-or-nothing
//               (บรีฟ bulk action ข้อ FK: ลบได้เท่าที่ลบได้ ส่วนที่ติด FK ให้ข้ามแทนที่จะล้มทั้งชุด)
//               เงื่อนไขติด FK เดียวกับ DeleteFood เดี่ยว (มีสมาชิกกินอาหารนี้ไปแล้วใน daily_nutrition)
// [INPUT] body: {ids: []uint}
// [OUTPUT] {succeeded: [{id,name}], failed: [{id,name,reason}]}
// [RELATED] FOOD_LOG
func BulkDeleteNutritionFoods(c *gin.Context) {
	var req bulkIDsRequest
	if err := c.ShouldBindJSON(&req); err != nil || len(req.IDs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณาระบุรายการที่ต้องการลบ"})
		return
	}

	succeeded := []bulkSucceededItem{}
	failed := []bulkFailedItem{}

	for _, id := range req.IDs {
		var food models.Nutrition
		if err := config.DB.First(&food, id).Error; err != nil {
			failed = append(failed, bulkFailedItem{ID: id, Name: "", Reason: "ไม่พบข้อมูลนี้ในระบบแล้ว"})
			continue
		}

		var count int64
		config.DB.Model(&models.DailyNutrition{}).Where("ntt_id = ?", id).Count(&count)
		if count > 0 {
			failed = append(failed, bulkFailedItem{
				ID:     id,
				Name:   food.NttFoodName,
				Reason: fmt.Sprintf("มีสมาชิกใช้บันทึกอาหารนี้อยู่ %d ครั้ง", count),
			})
			continue
		}

		if err := config.DB.Delete(&models.Nutrition{}, id).Error; err != nil {
			failed = append(failed, bulkFailedItem{ID: id, Name: food.NttFoodName, Reason: "ลบไม่สำเร็จ กรุณาลองใหม่"})
			continue
		}

		if food.NttFoodImage != "" {
			os.Remove("./" + food.NttFoodImage)
		}
		helpers.LogAdminMutation(c, "delete", "nutrition", id, food, nil)
		succeeded = append(succeeded, bulkSucceededItem{ID: id, Name: food.NttFoodName})
	}

	c.JSON(http.StatusOK, gin.H{"succeeded": succeeded, "failed": failed})
}

type bulkCategoryUpdate struct {
	ID     uint `json:"id"`
	NttcID uint `json:"nttc_id"`
}

type bulkMoveCategoryRequest struct {
	Updates []bulkCategoryUpdate `json:"updates"`
}

type bulkMoveSucceededItem struct {
	ID        uint   `json:"id"`
	Name      string `json:"name"`
	OldNttcID uint   `json:"old_nttc_id"`
}

// [FEATURE] FOOD_LOG
// [FUNCTION] BulkMoveNutritionFoodsCategory
// [DESCRIPTION] ย้ายหมวดหมู่โภชนาการของหลายรายการพร้อมกัน — รับเป็นคู่ (id, nttc_id ปลายทาง) แทนที่
//               จะรับ nttc_id เดียวใช้ร่วมกันทั้งชุด เพื่อให้ endpoint เดียวกันนี้ใช้ทำ Undo ได้ด้วย
//               (ตอน undo แต่ละรายการต้องย้ายกลับไปหมวดเดิมของตัวเอง ซึ่งอาจไม่เหมือนกัน)
// [INPUT] body: {updates: [{id, nttc_id}]}
// [OUTPUT] {succeeded: [{id,name,old_nttc_id}], failed: [{id,name,reason}]}
// [RELATED] FOOD_LOG
func BulkMoveNutritionFoodsCategory(c *gin.Context) {
	var req bulkMoveCategoryRequest
	if err := c.ShouldBindJSON(&req); err != nil || len(req.Updates) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณาระบุรายการที่ต้องการย้ายหมวดหมู่"})
		return
	}

	succeeded := []bulkMoveSucceededItem{}
	failed := []bulkFailedItem{}

	for _, u := range req.Updates {
		var food models.Nutrition
		if err := config.DB.First(&food, u.ID).Error; err != nil {
			failed = append(failed, bulkFailedItem{ID: u.ID, Name: "", Reason: "ไม่พบข้อมูลนี้ในระบบแล้ว"})
			continue
		}

		var targetCat models.NutritionCategory
		if err := config.DB.First(&targetCat, u.NttcID).Error; err != nil {
			failed = append(failed, bulkFailedItem{ID: u.ID, Name: food.NttFoodName, Reason: "ไม่พบหมวดหมู่ปลายทาง"})
			continue
		}

		oldFood := food
		oldNttcID := food.NttcID
		if err := config.DB.Model(&models.Nutrition{}).Where("ntt_id = ?", u.ID).Update("nttc_id", u.NttcID).Error; err != nil {
			failed = append(failed, bulkFailedItem{ID: u.ID, Name: food.NttFoodName, Reason: "ย้ายหมวดหมู่ไม่สำเร็จ กรุณาลองใหม่"})
			continue
		}

		food.NttcID = u.NttcID
		helpers.LogAdminMutation(c, "update", "nutrition", u.ID, oldFood, food)
		succeeded = append(succeeded, bulkMoveSucceededItem{ID: u.ID, Name: food.NttFoodName, OldNttcID: oldNttcID})
	}

	c.JSON(http.StatusOK, gin.H{"succeeded": succeeded, "failed": failed})
}
