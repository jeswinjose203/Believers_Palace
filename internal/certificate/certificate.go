// Package certificate implements per-user certificate storage: PDF files are
// stored on disk while metadata lives in the database. Users manage their own
// certificates; administrators may manage certificates for users they oversee.
package certificate

import "time"

// Type is the category of a certificate.
type Type string

const (
	TypeBaptism        Type = "baptism"
	TypeConfirmation   Type = "confirmation"
	TypeMarriage       Type = "marriage"
	TypeFirstCommunion Type = "first_communion"
	TypeDeath          Type = "death"
	TypeOther          Type = "other"
)

// ValidType reports whether t is a recognized certificate type.
func ValidType(t Type) bool {
	switch t {
	case TypeBaptism, TypeConfirmation, TypeMarriage, TypeFirstCommunion, TypeDeath, TypeOther:
		return true
	default:
		return false
	}
}

// Certificate is the metadata for a stored certificate. The on-disk path is
// internal and never serialized.
type Certificate struct {
	ID                string     `json:"id"`
	UserID            string     `json:"userId"`
	UploadedByUserID  string     `json:"uploadedByUserId"`
	Type              Type       `json:"type"`
	CertificateNumber string     `json:"certificateNumber"`
	FullName          string     `json:"fullName"`
	IssueDate         *time.Time `json:"issueDate"`
	FileName          string     `json:"fileName"`
	MimeType          string     `json:"mimeType"`
	FileSize          int64      `json:"fileSize"`
	Notes             *string    `json:"notes"`
	CreatedAt         time.Time  `json:"createdAt"`

	// StoredPath is the internal filesystem path and is never serialized.
	StoredPath string `json:"-"`
}

// UploadMetadata carries the parsed non-file fields of an upload request.
type UploadMetadata struct {
	Type              Type
	CertificateNumber string
	FullName          string
	IssueDate         *time.Time
	Notes             string
}
