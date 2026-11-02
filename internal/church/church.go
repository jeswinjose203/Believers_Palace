package church

import "time"

// PriestDetails holds priest/associate-priest contact info embedded in a church.
type PriestDetails struct {
	Name       string  `json:"name"`
	Phone      string  `json:"phone,omitempty"`
	Email      string  `json:"email,omitempty"`
	ProfilePic *string `json:"profilePic"`
}

// Church is a full church record.
type Church struct {
	ID              string         `json:"id"`
	Name            string         `json:"name"`
	Address         string         `json:"address,omitempty"`
	Phone           string         `json:"phone,omitempty"`
	Email           string         `json:"email,omitempty"`
	Logo            string         `json:"logo,omitempty"`
	Priest          *PriestDetails `json:"priest,omitempty"`
	AssociatePriest *PriestDetails `json:"associatePriest,omitempty"`
	CreatedAt       time.Time      `json:"createdAt"`
	UpdatedAt       time.Time      `json:"updatedAt"`
}

// ListItem is the condensed church representation returned by list endpoints.
type ListItem struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Address string `json:"address,omitempty"`
	Logo    string `json:"logo,omitempty"`
}

// Request is the payload for creating or updating a church.
type Request struct {
	Name            string         `json:"name"`
	Address         string         `json:"address"`
	Phone           string         `json:"phone"`
	Email           string         `json:"email"`
	Logo            string         `json:"logo"`
	Priest          *PriestDetails `json:"priest"`
	AssociatePriest *PriestDetails `json:"associatePriest"`
}
