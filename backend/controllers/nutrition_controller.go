package controllers

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"time"
	"math"

	"food_and_fit_api/config"
	"food_and_fit_api/helpers"
	"food_and_fit_api/models"

	"github.com/gin-gonic/gin"
)

// ==========================================
// ส่วนจัดการ หมวดหมู่โภชนาการ (Categories)
// ==========================================

// ดึงข้อมูลประเภทอาหาร
func GetNutritionCategories(c *gin.Context) {
	var categories []models.NutritionCategory
	if err := config.DB.Find(&categories).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถดึงข้อมูลประเภทอาหารได้"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": categories})
}

// nutritionCategoryInput คือ DTO รับเฉพาะ nttc_name — ไม่ bind ตรงเข้า models.NutritionCategory
// เพราะ struct นั้นมี nttc_id ด้วย ถ้า client ส่ง nttc_id มาใน body จะเขียนทับ primary key ที่ตั้งใจแก้
type nutritionCategoryInput struct {
	NttcName string `json:"nttc_name"`
}

// เพิ่มประเภทโภชนาการใหม่
func CreateNutritionCategory(c *gin.Context) {
	var input nutritionCategoryInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง"})
		return
	}
	category := models.NutritionCategory{NttcName: input.NttcName}
	if err := config.DB.Create(&category).Error; err != nil {
		if helpers.IsDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "มีประเภทอาหารชื่อนี้อยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถเพิ่มข้อมูลได้"})
		return
	}
	helpers.LogAdminMutation(c, "create", "nutrition_category", category.NttcID, nil, category)
	c.JSON(http.StatusOK, gin.H{"message": "เพิ่มสำเร็จ", "data": category})
}

// แก้ไขประเภทโภชนาการ
func UpdateNutritionCategory(c *gin.Context) {
	id := c.Param("id") // รับ id มาจาก URL (:id)
	var category models.NutritionCategory

	if err := config.DB.First(&category, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบข้อมูล"})
		return
	}
	before := category // snapshot ก่อนแก้ ไว้ให้ audit log (S-9 old_value)

	var input nutritionCategoryInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง"})
		return
	}
	category.NttcName = input.NttcName

	if err := config.DB.Save(&category).Error; err != nil {
		if helpers.IsDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "มีประเภทอาหารชื่อนี้อยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "แก้ไขไม่สำเร็จ"})
		return
	}
	helpers.LogAdminMutation(c, "update", "nutrition_category", category.NttcID, before, category)
	c.JSON(http.StatusOK, gin.H{"message": "แก้ไขสำเร็จ", "data": category})
}

// UpdateNutritionCategoryImage อัปโหลด/แทนที่รูปหมวดหมู่โภชนาการ — แยกเป็นคนละ endpoint จาก
// UpdateNutritionCategory (JSON) ตั้งใจไม่รวมกัน เพราะ endpoint เดิมแอปมือถือส่ง JSON อยู่แล้ว
// เปลี่ยน content-type เป็น multipart จะกระทบของเดิม — เพิ่ง sync คอลัมน์ nttc_image ใหม่
func UpdateNutritionCategoryImage(c *gin.Context) {
	id := c.Param("id")
	var category models.NutritionCategory
	if err := config.DB.First(&category, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบข้อมูล"})
		return
	}
	before := category

	file, err := c.FormFile("nttc_image")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณาแนบไฟล์รูปภาพ (nttc_image)"})
		return
	}
	if verr := helpers.ValidateImageUpload(file); verr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
		return
	}

	uploadDir := "./uploads/nutrition_categories"
	os.MkdirAll(uploadDir, os.ModePerm)
	extension := filepath.Ext(file.Filename)
	newFileName := fmt.Sprintf("%d%s", time.Now().UnixNano(), extension)
	savePath := filepath.Join(uploadDir, newFileName)

	if err := c.SaveUploadedFile(file, savePath); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "อัปโหลดรูปไม่สำเร็จ"})
		return
	}
	if category.NttcImage != "" {
		os.Remove("./" + category.NttcImage)
	}
	category.NttcImage = "uploads/nutrition_categories/" + newFileName

	if err := config.DB.Save(&category).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "บันทึกไม่สำเร็จ"})
		return
	}
	helpers.LogAdminMutation(c, "update", "nutrition_category", category.NttcID, before, category)
	c.JSON(http.StatusOK, gin.H{"message": "อัปเดตรูปสำเร็จ", "data": category})
}

// ลบประเภทโภชนาการ
func DeleteNutritionCategory(c *gin.Context) {
	id := c.Param("id")

	var count int64
	config.DB.Model(&models.Nutrition{}).Where("nttc_id = ?", id).Count(&count)
	if count > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("ไม่สามารถลบได้ เพราะมีรายการอาหาร %d รายการอยู่ในหมวดนี้ กรุณาย้ายหรือลบอาหารก่อน", count)})
		return
	}

	var before models.NutritionCategory
	config.DB.First(&before, id) // best-effort snapshot ก่อนลบ ไว้ให้ audit log

	if err := config.DB.Delete(&models.NutritionCategory{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ลบไม่สำเร็จ"})
		return
	}
	helpers.LogAdminMutation(c, "delete", "nutrition_category", id, before, nil)
	c.JSON(http.StatusOK, gin.H{"message": "ลบสำเร็จ"})
}

// ==========================================
// ส่วนจัดการ ข้อมูลอาหาร (Foods)
// ==========================================

// ดึงข้อมูลอาหารทั้งหมด
func GetAllNutrition(c *gin.Context) {
	var foods []models.Nutrition

	// ใช้ Preload("Category") เพื่อจอยตารางเอาชื่อประเภทอาหารมาด้วย
	if err := config.DB.Preload("Category").Find(&foods).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถดึงข้อมูลโภชนาการได้"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "ดึงข้อมูลสำเร็จ",
		"data":    foods,
	})
}

// 🟢 อัปเดต: เพิ่มข้อมูลอาหารใหม่ รองรับรูปภาพ (POST /api/nutrition/foods)
func CreateFood(c *gin.Context) {
	// 1. รับค่า Text จาก Form
	nttName := c.PostForm("ntt_food_name")
	nttcIDStr := c.PostForm("nttc_id")
	nttCalStr := c.PostForm("ntt_calories")
	nttProtStr := c.PostForm("ntt_protein")
	nttCarbStr := c.PostForm("ntt_carbs")
	nttFatStr := c.PostForm("ntt_fat")
	nttServStr := c.PostForm("ntt_serving_weight")
	nttUnit := c.PostForm("ntt_unit")

	nttcID, _ := strconv.Atoi(nttcIDStr)
	nttCal, _ := strconv.ParseFloat(nttCalStr, 64)
	nttProt, _ := strconv.ParseFloat(nttProtStr, 64)
	nttCarb, _ := strconv.ParseFloat(nttCarbStr, 64)
	nttFat, _ := strconv.ParseFloat(nttFatStr, 64)
	nttServ, _ := strconv.Atoi(nttServStr)

	if nttUnit == "" {
		nttUnit = "กรัม"
	}

	if ok, msg := helpers.ValidateNutritionMacros(nttCal, nttProt, nttCarb, nttFat, nttServ); !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	macroWarning := helpers.NutritionMacroMismatchWarning(nttCal, nttProt, nttCarb, nttFat)

	// 2. รับและบันทึกไฟล์รูปภาพ
	imagePath := ""
	file, err := c.FormFile("ntt_food_image")
	if err == nil {
		if verr := helpers.ValidateImageUpload(file); verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		// สร้างโฟลเดอร์ถ้ายังไม่มี
		uploadDir := "./uploads/foods"
		os.MkdirAll(uploadDir, os.ModePerm)

		// สร้างชื่อไฟล์ใหม่กันซ้ำ (ใช้ Timestamp)
		extension := filepath.Ext(file.Filename)
		newFileName := fmt.Sprintf("%d%s", time.Now().UnixNano(), extension)
		savePath := filepath.Join(uploadDir, newFileName)

		// บันทึกไฟล์ลงเซิร์ฟเวอร์
		if err := c.SaveUploadedFile(file, savePath); err == nil {
			// เก็บ Path สำหรับลง Database
			imagePath = "uploads/foods/" + newFileName
		}
	}

	// 3. สั่งบันทึกลงฐานข้อมูล
	food := models.Nutrition{
		NttFoodName:      nttName,
		NttcID:           uint(nttcID),
		NttCalories:      nttCal,
		NttProtein:       nttProt,
		NttCarbs:         nttCarb,
		NttFat:           nttFat,
		NttServingWeight: nttServ,
		NttUnit:          nttUnit,
		NttFoodImage:     imagePath,
	}

	if err := config.DB.Create(&food).Error; err != nil {
		if helpers.IsDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "มีอาหารชื่อนี้อยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถเพิ่มข้อมูลอาหารได้"})
		return
	}

	helpers.LogAdminMutation(c, "create", "nutrition", food.NttID, nil, food)
	resp := gin.H{"message": "เพิ่มข้อมูลอาหารสำเร็จ", "data": food}
	if macroWarning != "" {
		resp["warning"] = macroWarning
	}
	c.JSON(http.StatusCreated, resp)
}

// 🟢 อัปเดต: แก้ไขข้อมูลอาหาร รองรับรูปภาพ (PUT /api/nutrition/foods/:id)
func UpdateFood(c *gin.Context) {
	id := c.Param("id") // รับ ID จาก URL
	var food models.Nutrition

	// ค้นหาข้อมูลเดิมในฐานข้อมูลก่อนว่ามีอยู่จริงไหม
	if err := config.DB.First(&food, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบข้อมูลอาหารที่ต้องการแก้ไข"})
		return
	}
	before := food // snapshot ก่อนแก้ ไว้ให้ audit log (S-9 old_value)

	// อัปเดตข้อมูล Text
	if name := c.PostForm("ntt_food_name"); name != "" {
		food.NttFoodName = name
	}
	if nttcStr := c.PostForm("nttc_id"); nttcStr != "" {
		nttcID, _ := strconv.Atoi(nttcStr)
		food.NttcID = uint(nttcID)
	}
	if calStr := c.PostForm("ntt_calories"); calStr != "" {
		cal, _ := strconv.ParseFloat(calStr, 64)
		food.NttCalories = cal
	}
	if protStr := c.PostForm("ntt_protein"); protStr != "" {
		prot, _ := strconv.ParseFloat(protStr, 64)
		food.NttProtein = prot
	}
	if carbStr := c.PostForm("ntt_carbs"); carbStr != "" {
		carb, _ := strconv.ParseFloat(carbStr, 64)
		food.NttCarbs = carb
	}
	if fatStr := c.PostForm("ntt_fat"); fatStr != "" {
		fat, _ := strconv.ParseFloat(fatStr, 64)
		food.NttFat = fat
	}
	if servStr := c.PostForm("ntt_serving_weight"); servStr != "" {
		serv, _ := strconv.Atoi(servStr)
		food.NttServingWeight = serv
	}
	if unit := c.PostForm("ntt_unit"); unit != "" {
		food.NttUnit = unit
	}

	// จัดการรูปภาพใหม่ (ถ้ามีการส่งไฟล์ใหม่มา)
	file, err := c.FormFile("ntt_food_image")
	if err == nil {
		if verr := helpers.ValidateImageUpload(file); verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		// สร้างโฟลเดอร์ถ้ายังไม่มี
		uploadDir := "./uploads/foods"
		os.MkdirAll(uploadDir, os.ModePerm)

		// สร้างชื่อไฟล์ใหม่กันซ้ำ (ใช้ Timestamp)
		extension := filepath.Ext(file.Filename)
		newFileName := fmt.Sprintf("%d%s", time.Now().UnixNano(), extension)
		savePath := filepath.Join(uploadDir, newFileName)

		if err := c.SaveUploadedFile(file, savePath); err == nil {
			// ลบรูปเก่าทิ้งเพื่อประหยัดพื้นที่
			if food.NttFoodImage != "" {
				os.Remove("./" + food.NttFoodImage)
			}
			// อัปเดต Path เป็นรูปใหม่
			food.NttFoodImage = "uploads/foods/" + newFileName
		}
	}

	if ok, msg := helpers.ValidateNutritionMacros(food.NttCalories, food.NttProtein, food.NttCarbs, food.NttFat, food.NttServingWeight); !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	macroWarning := helpers.NutritionMacroMismatchWarning(food.NttCalories, food.NttProtein, food.NttCarbs, food.NttFat)

	// บันทึกการเปลี่ยนแปลง
	if err := config.DB.Save(&food).Error; err != nil {
		if helpers.IsDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "มีอาหารชื่อนี้อยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถบันทึกการแก้ไขได้"})
		return
	}

	helpers.LogAdminMutation(c, "update", "nutrition", food.NttID, before, food)
	resp := gin.H{"message": "แก้ไขข้อมูลสำเร็จ", "data": food}
	if macroWarning != "" {
		resp["warning"] = macroWarning
	}
	c.JSON(http.StatusOK, resp)
}

// ลบข้อมูลอาหาร (DELETE /api/nutrition/foods/:id)
func DeleteFood(c *gin.Context) {
	id := c.Param("id")

	var count int64
	config.DB.Model(&models.DailyNutrition{}).Where("ntt_id = ?", id).Count(&count)
	if count > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("ไม่สามารถลบได้ เพราะสมาชิกมีประวัติการกินอาหารนี้ %d รายการอยู่", count)})
		return
	}

	var food models.Nutrition
	if err := config.DB.First(&food, id).Error; err == nil {
		if food.NttFoodImage != "" {
			os.Remove("./" + food.NttFoodImage)
		}
	}

	if err := config.DB.Delete(&models.Nutrition{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถลบข้อมูลได้"})
		return
	}

	helpers.LogAdminMutation(c, "delete", "nutrition", id, food, nil)
	c.JSON(http.StatusOK, gin.H{"message": "ลบข้อมูลเรียบร้อย"})
}

// SearchNutrition - ค้นหาอาหารจากชื่อ
func SearchNutrition(c *gin.Context) {
	q := c.Query("q")
	if len(q) > 100 {
		q = q[:100]
	}
	var foods []models.Nutrition
	query := config.DB.Preload("Category")
	if q != "" {
		query = query.Where("ntt_food_name LIKE ?", "%"+q+"%")
	}
	if err := query.Limit(30).Find(&foods).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ค้นหาไม่สำเร็จ"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": foods})
}

// CreateDailyNutrition - บันทึกอาหารที่กินวันนี้ (เวอร์ชันแก้ไขพร้อมระบบคำนวณ)
func CreateDailyNutrition(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var req struct {
		NttID              *uint   `json:"ntt_id"`
		DnttDate           string  `json:"dntt_date" binding:"required"`
		DnttTime           string  `json:"dntt_time"`
		DnttMealType       int8    `json:"dntt_meal_type" binding:"required"`
		DnttFoodName       string  `json:"dntt_food_name"`
		DnttQuantity       float64 `json:"dntt_quantity" binding:"required,gt=0"`
		DnttUnit           string  `json:"dntt_unit" binding:"required"`
		
		DnttTotalCalories  float64 `json:"dntt_total_calories"`
		DnttTotalProtein   float64 `json:"dntt_total_protein"`
		DnttTotalCarb      float64 `json:"dntt_total_carb"`
		DnttTotalFat       float64 `json:"dntt_total_fat"`
		DnttImage          string  `json:"dntt_image"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		fmt.Println("Binding Error:", err.Error())
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง กรุณาตรวจสอบข้อมูลที่กรอก"})
		return
	}

	// 1. เตรียม Object สำหรับบันทึก
	log := models.DailyNutrition{
		MbID:               userID.(int),
		NttID:               req.NttID,
		DnttDate:           req.DnttDate,
		DnttTime:           req.DnttTime,
		DnttMealType:       req.DnttMealType,
		DnttFoodName:       req.DnttFoodName,
		DnttQuantity:       req.DnttQuantity,
		DnttUnit:           req.DnttUnit,
		DnttImage:          req.DnttImage,
	}

	// 2. LOGIC ตรวจสอบและคำนวณ: ถ้ามีการเลือกอาหารจากฐานข้อมูล (ntt_id ไม่ใช่ null)
	if req.NttID != nil {
		var food models.Nutrition
		if err := config.DB.First(&food, *req.NttID).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบข้อมูลอาหารในระบบ"})
			return
		}

		// คำนวณสารอาหารโดย: (ค่าพื้นฐานในตาราง nutrition * จำนวนที่ผู้ใช้กรอก)
		log.DnttTotalCalories = food.NttCalories * req.DnttQuantity
		log.DnttTotalProtein = food.NttProtein * req.DnttQuantity
		log.DnttTotalCarb = food.NttCarbs * req.DnttQuantity
		log.DnttTotalFat = food.NttFat * req.DnttQuantity

		// ถ้าไม่ได้กรอกชื่ออาหารมา ให้ใช้ชื่อจากระบบ
		if log.DnttFoodName == "" {
			log.DnttFoodName = food.NttFoodName
		}
	} else {
		// กรณีเป็นอาหารที่ผู้ใช้กรอกเอง (Custom) ให้ใช้ค่าที่ส่งมาจาก req ตรงๆ
		log.DnttTotalCalories = req.DnttTotalCalories
		log.DnttTotalProtein = req.DnttTotalProtein
		log.DnttTotalCarb = req.DnttTotalCarb
		log.DnttTotalFat = req.DnttTotalFat
	}

	// 3. บันทึกลงฐานข้อมูล
	if err := config.DB.Table("daily_nutrition").Create(&log).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "บันทึกข้อมูลไม่สำเร็จ"})
		return
	}

	// 4. ดึงข้อมูลตัวที่เพิ่งบันทึก พร้อม Preload ข้อมูล Nutrition เพื่อส่งกลับไปให้ UI
	config.DB.Preload("Nutrition").First(&log, log.DnttID)

	c.JSON(http.StatusCreated, gin.H{
		"message": "บันทึกข้อมูลอาหารสำเร็จ",
		"data":    log,
	})
}

// GetDailyNutrition - ดึงรายการอาหารที่กินในวันที่ระบุ
func GetDailyNutrition(c *gin.Context) {
	userID, _ := c.Get("user_id")
	date := c.Query("date")
	if date == "" {
		date = time.Now().Format("2006-01-02")
	}

	var logs []models.DailyNutrition
	if err := config.DB.Table("daily_nutrition").Preload("Nutrition").Where("mb_id = ? AND dntt_date = ?", userID, date).Order("dntt_time asc").Find(&logs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ดึงข้อมูลไม่สำเร็จ"})
		return
	}

	// สรุปแคลอรี่รวม
	var totalCal, totalProtein, totalCarb, totalFat float64
	for _, l := range logs {
		totalCal += l.DnttTotalCalories
		totalProtein += l.DnttTotalProtein
		totalCarb += l.DnttTotalCarb
		totalFat += l.DnttTotalFat
	}

	c.JSON(http.StatusOK, gin.H{
		"date": date,
		"data": logs,
		"summary": gin.H{
			"total_calories": math.Round(totalCal*100)/100,
        "total_protein":  math.Round(totalProtein*100)/100,
        "total_carb":     math.Round(totalCarb*100)/100,
        "total_fat":      math.Round(totalFat*100)/100,
		},
	})
}

// UpdateDailyNutrition - แก้ไขรายการอาหารที่บันทึกแล้ว (ปรับจำนวน/มื้ออาหาร แล้วคำนวณสารอาหารใหม่)
func UpdateDailyNutrition(c *gin.Context) {
	userID, _ := c.Get("user_id")
	id := c.Param("id")

	var req struct {
		DnttMealType int8    `json:"dntt_meal_type" binding:"required"`
		DnttQuantity float64 `json:"dntt_quantity" binding:"required,gt=0"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง กรุณาตรวจสอบข้อมูลที่กรอก"})
		return
	}

	var log models.DailyNutrition
	if err := config.DB.Table("daily_nutrition").Where("dntt_id = ? AND mb_id = ?", id, userID).First(&log).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบรายการอาหารนี้"})
		return
	}

	updates := map[string]interface{}{
		"dntt_meal_type": req.DnttMealType,
		"dntt_quantity":  req.DnttQuantity,
	}

	if log.NttID != nil {
		// อ้างอิงอาหารจากระบบ — คำนวณสารอาหารใหม่จากค่าต่อหน่วยจริงในตาราง nutrition (เหมือน CreateDailyNutrition)
		var food models.Nutrition
		if err := config.DB.First(&food, *log.NttID).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบข้อมูลอาหารในระบบ"})
			return
		}
		updates["dntt_total_calories"] = food.NttCalories * req.DnttQuantity
		updates["dntt_total_protein"] = food.NttProtein * req.DnttQuantity
		updates["dntt_total_carb"] = food.NttCarbs * req.DnttQuantity
		updates["dntt_total_fat"] = food.NttFat * req.DnttQuantity
	} else if log.DnttQuantity > 0 {
		// อาหารกรอกเอง (custom, ntt_id เป็น NULL) — ไม่มีค่าต่อหน่วยเก็บแยก คิดสัดส่วนย้อนจากยอดเดิม/จำนวนเดิม
		ratio := req.DnttQuantity / log.DnttQuantity
		updates["dntt_total_calories"] = log.DnttTotalCalories * ratio
		updates["dntt_total_protein"] = log.DnttTotalProtein * ratio
		updates["dntt_total_carb"] = log.DnttTotalCarb * ratio
		updates["dntt_total_fat"] = log.DnttTotalFat * ratio
	}

	if err := config.DB.Table("daily_nutrition").Where("dntt_id = ? AND mb_id = ?", id, userID).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "แก้ไขข้อมูลไม่สำเร็จ"})
		return
	}

	config.DB.Table("daily_nutrition").Preload("Nutrition").First(&log, log.DnttID)

	c.JSON(http.StatusOK, gin.H{
		"message": "แก้ไขรายการอาหารสำเร็จ",
		"data":    log,
	})
}

// DeleteDailyNutrition - ลบรายการอาหารที่กิน
func DeleteDailyNutrition(c *gin.Context) {
	userID, _ := c.Get("user_id")
	id := c.Param("id")

	if err := config.DB.Table("daily_nutrition").Where("dntt_id = ? AND mb_id = ?", id, userID).Delete(&models.DailyNutrition{}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ลบไม่สำเร็จ"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "ลบรายการอาหารสำเร็จ"})
}
