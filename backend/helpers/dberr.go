package helpers

import (
	"errors"

	"github.com/go-sql-driver/mysql"
)

// IsDuplicateKeyError ตรวจว่า error จาก GORM เป็น MySQL 1062 (Duplicate entry จาก UNIQUE KEY) หรือไม่
// ใช้แปลง error นี้เป็น HTTP 409 แทน 500 (V4)
func IsDuplicateKeyError(err error) bool {
	var mysqlErr *mysql.MySQLError
	if errors.As(err, &mysqlErr) {
		return mysqlErr.Number == 1062
	}
	return false
}
