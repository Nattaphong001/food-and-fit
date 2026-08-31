package controllers

import (
	"net/http"
	"strconv"
	"strings"

	"food_and_fit_api/config"
	"food_and_fit_api/models"
	"food_and_fit_api/utils"

	"github.com/gin-gonic/gin"
)

// endpoint ใหม่สำหรับหน้าท่าฝึกเวทฝั่ง Admin Web — กรอง+pagination ระดับ SQL แยกจาก
// GetWeightExercises (/api/exercises/weights) เพราะตัวนั้นแอปมือถือเรียกใช้อยู่จริง (ดู
// exercise_service.dart) ห้ามแก้ signature/response เดิม (CLAUDE.md ข้อ 2) จึงเพิ่ม endpoint
// ใหม่นี้แทน อยู่ใต้ adminProtected เท่านั้น
//
// ไม่มี sort_by/sort_order ตามสเปกฝั่ง Flutter (หน้านี้ไม่มี sort control ให้ผู้ใช้เลือกเอง) —
// แต่ "ไม่มี sort control" ไม่ได้แปลว่า default ordering เลือกตามใจได้ ต้องคงความหมายเดิมที่
// client-side เคยทำไว้ (เรียงตามระดับความยาก ง่าย→ยาก เสมอ) ไม่ใช่ wet_id ASC เฉยๆ ซึ่งไม่มี
// ความหมายกับผู้ใช้ (regression ที่แก้ตามคำสั่ง 2026-08-30) จึงเรียงตาม wet_difficulty ASC ก่อน
// แล้วค่อย wet_id ASC ในระดับเดียวกัน (ลำดับคงที่ ไม่ผูกกับ query param ใดๆ)
//
// หมายเหตุ: wet_difficulty เป็น column tinyint ธรรมดาอยู่ในตาราง weight_exercises เอง ไม่ใช่ FK
// ไปตาราง lookup แยก (ต่างจากที่ร่าง ER concept สมมติไว้) filter จึงเทียบค่าตรงคอลัมน์นี้ได้เลย
//
// muscle_group_id **ห้าม filter จาก weight_exercises.mug_id ตรงๆ** แม้จะดูเหมือนใช่ที่สุด —
// ตรวจข้อมูลจริงแล้วพบว่า mug_id เป็นแค่กล้ามเนื้อ "หลัก" เดียว แต่ Flutter (เดิม, client-side
// filter ก่อน integration phase นี้) กรองจาก exercise_muscle_details (many-to-many หลัก+รอง)
// ต่างกันจริงถึง 34/48 ท่าฝึก (71%) ถ้า filter จาก mug_id ตรงๆ ผลลัพธ์การกรอง/drill-down ตาม
// กลุ่มกล้ามเนื้อจะเปลี่ยนไปจาก UX เดิมทันที (ยืนยันกับผู้ใช้แล้ว 2026-08-30 ให้ยึด
// exercise_muscle_details เป็นหลักเหมือน UX เดิม) จึงใช้ EXISTS join ตารางนั้นแทน

// [FEATURE] WEIGHT_TRAINING
// [FUNCTION] GetAdminWeightExercises
// [DESCRIPTION] ดึงรายการท่าฝึกเวทแบบกรอง+pagination ระดับ SQL สำหรับหน้าท่าฝึกเวทฝั่ง Admin Web
//
//	(ตารางข้อมูลโตไม่จำกัด ห้ามดึงทั้งหมดมากรองที่ Dart)
//
// [INPUT] query: search, muscle_group_id, difficulty_id, page, page_size
// [OUTPUT] {data: []WeightExercise (พร้อม muscle_group), total, page, page_size}
func GetAdminWeightExercises(c *gin.Context) {
	page, pageSize, offset := utils.ParsePagination(c)

	query := config.DB.Model(&models.WeightExercise{})

	if search := strings.TrimSpace(c.Query("search")); search != "" {
		query = query.Where("wet_name LIKE ?", "%"+search+"%")
	}
	if mugIDStr := c.Query("muscle_group_id"); mugIDStr != "" {
		if mugID, err := strconv.Atoi(mugIDStr); err == nil {
			query = query.Where(
				"EXISTS (SELECT 1 FROM exercise_muscle_details emd WHERE emd.wet_id = weight_exercises.wet_id AND emd.mug_id = ?)",
				mugID,
			)
		}
	}
	if diffIDStr := c.Query("difficulty_id"); diffIDStr != "" {
		if diffID, err := strconv.Atoi(diffIDStr); err == nil {
			query = query.Where("wet_difficulty = ?", diffID)
		}
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "นับจำนวนรายการไม่สำเร็จ"})
		return
	}

	var exercises []models.WeightExercise
	if err := query.Preload("MuscleGroup").Order("wet_difficulty ASC, wet_id ASC").Offset(offset).Limit(pageSize).Find(&exercises).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถดึงข้อมูลท่าฝึกเวทได้"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data":      exercises,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}
