package models

import "time"

// SysUser - โมเดลสำหรับตาราง sys_users (แอดมิน)
type SysUser struct {
	SysID           uint       `gorm:"column:sys_id;primaryKey;autoIncrement" json:"sys_id"`
	SysEmail        string     `gorm:"column:sys_email;not null;unique"       json:"sys_email"`
	SysPasswordHash string     `gorm:"column:sys_password_hash;not null"      json:"-"`
	SysFullName     string     `gorm:"column:sys_full_name;not null"          json:"sys_full_name"`
	SysOrganization *string    `gorm:"column:sys_organization"                json:"sys_organization"`
	SysStartDate    *time.Time `gorm:"column:sys_start_date"                  json:"sys_start_date"`
	SysStatus       int        `gorm:"column:sys_status;not null;default:1"   json:"sys_status"`
	CreatedAt       time.Time  `gorm:"column:sys_created_at;autoCreateTime"   json:"created_at"`
	UpdatedAt       time.Time  `gorm:"column:sys_updated_at;autoUpdateTime"   json:"updated_at"`
}

func (SysUser) TableName() string {
	return "system_data"
}
