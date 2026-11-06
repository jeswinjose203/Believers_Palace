package chat

import (
	"context"
	"errors"
	"strings"

	"believers_palace/internal/auth"
)

// ErrForbidden is returned when the caller lacks permission for the operation.
var ErrForbidden = errors.New("insufficient permissions")

// ErrNotRegistered is returned when a user who is not registered for the event
// (and is not church staff) tries to read or post in its chat.
var ErrNotRegistered = errors.New("register for this event to join the chat")

// ErrEventNotFound is returned when the target event does not exist.
var ErrEventNotFound = errors.New("event not found")

// maxContentLen bounds a single chat message.
const maxContentLen = 4000

// ValidationError describes a request validation failure.
type ValidationError struct{ Message string }

func (e *ValidationError) Error() string { return e.Message }

func invalid(msg string) error { return &ValidationError{Message: msg} }

// eventResolver resolves an event's existence and owning church.
type eventResolver interface {
	// ChurchIDOfEvent returns the church that owns the event and whether it
	// exists.
	ChurchIDOfEvent(ctx context.Context, eventID string) (churchID string, ok bool, err error)
}

// userResolver resolves a user's display name and profile picture for author
// snapshots.
type userResolver interface {
	// DisplayOf returns the user's name and optional profile picture.
	DisplayOf(ctx context.Context, userID string) (name string, profilePic *string, ok bool, err error)
}

// registrationChecker reports whether a user is registered for an event.
type registrationChecker interface {
	IsRegistered(ctx context.Context, eventID, userID string) (bool, error)
}

// messageStore is the subset of the repository the service relies on. It keeps
// the authorization logic testable without a live database.
type messageStore interface {
	Create(ctx context.Context, eventID string, userID *string, authorName string, authorPic *string, content string) (*Message, error)
	GetByID(ctx context.Context, id string) (*Message, error)
	ListByEvent(ctx context.Context, eventID string, limit, offset int) ([]Message, int, error)
	Delete(ctx context.Context, id string) error
}

// Service holds chat business logic and authorization.
type Service struct {
	repo   messageStore
	events eventResolver
	users  userResolver
	regs   registrationChecker
}

// NewService creates a chat service.
func NewService(repo messageStore, events eventResolver, users userResolver, regs registrationChecker) *Service {
	return &Service{repo: repo, events: events, users: users, regs: regs}
}

// authorizeAccess verifies the event exists and that the caller may take part
// in its chat: church staff of the event's church (and super_admin) always may;
// everyone else must be registered for the event.
func (s *Service) authorizeAccess(ctx context.Context, id auth.Identity, eventID string) error {
	churchID, ok, err := s.events.ChurchIDOfEvent(ctx, eventID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrEventNotFound
	}
	if auth.CanManageChurchContent(id, churchID) {
		return nil
	}
	if id.UserID == "" {
		return ErrNotRegistered
	}
	registered, err := s.regs.IsRegistered(ctx, eventID, id.UserID)
	if err != nil {
		return err
	}
	if !registered {
		return ErrNotRegistered
	}
	return nil
}

// List returns a page of messages for an event. Only registered attendees and
// church staff may read the chat.
func (s *Service) List(ctx context.Context, id auth.Identity, eventID string, limit, offset int) ([]Message, int, error) {
	if err := s.authorizeAccess(ctx, id, eventID); err != nil {
		return nil, 0, err
	}
	return s.repo.ListByEvent(ctx, eventID, limit, offset)
}

// Post creates a message authored by the calling user. Only registered
// attendees and church staff may post. The author's name and profile picture
// are snapshotted at insert time.
func (s *Service) Post(ctx context.Context, id auth.Identity, eventID string, in CreateRequest) (*Message, error) {
	if err := s.authorizeAccess(ctx, id, eventID); err != nil {
		return nil, err
	}

	content := strings.TrimSpace(in.Content)
	if content == "" {
		return nil, invalid("message content is required")
	}
	if len(content) > maxContentLen {
		return nil, invalid("message is too long")
	}

	name, pic, ok, err := s.users.DisplayOf(ctx, id.UserID)
	if err != nil {
		return nil, err
	}
	if !ok {
		// Fall back to a generic author if the user row is missing (e.g. the
		// synthetic debug identity before seeding).
		name = "User"
	}

	userID := &id.UserID
	if id.UserID == "" {
		userID = nil
	}
	return s.repo.Create(ctx, eventID, userID, name, pic, content)
}

// Delete removes a message. Permitted for the message author or an
// administrator of the event's church (church_admin scoped to the church, or
// super_admin anywhere).
func (s *Service) Delete(ctx context.Context, id auth.Identity, eventID, messageID string) error {
	msg, err := s.repo.GetByID(ctx, messageID)
	if err != nil {
		return err
	}
	if msg.EventID != eventID {
		return ErrNotFound
	}

	// Author may always delete their own message.
	if msg.UserID != nil && *msg.UserID == id.UserID {
		return s.repo.Delete(ctx, messageID)
	}

	// Otherwise require administrative control of the event's church.
	churchID, ok, err := s.events.ChurchIDOfEvent(ctx, eventID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrEventNotFound
	}
	if auth.CanManageChurch(id, churchID) {
		return s.repo.Delete(ctx, messageID)
	}
	return ErrForbidden
}
