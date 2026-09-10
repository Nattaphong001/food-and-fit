package utils

import (
	"strconv"

	"github.com/gin-gonic/gin"
)

// [FEATURE] COMMON_UI
// [FUNCTION] ParsePagination
// [DESCRIPTION] อ่าน query param page/page_size พร้อม default และขอบเขตที่ปลอดภัย (page_size
//
//	สูงสุด 100 กัน query กวาดทั้งตารางถ้ามีคนส่งค่าผิดปกติมา) — endpoint admin list
//	ที่ต้องกรอง+pagination ระดับ SQL ทุกตัวเรียกใช้ร่วมกัน ให้กฎ default/clamp ตรงกันหมด
//
// [INPUT] gin.Context (query param "page", "page_size")
// [OUTPUT] page, pageSize, offset (int)
func ParsePagination(c *gin.Context) (page int, pageSize int, offset int) {
	page, _ = strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 {
		page = 1
	}
	pageSize, _ = strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}
	offset = (page - 1) * pageSize
	return
}
