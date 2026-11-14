package community

import (
	"context"
	"errors"
	"strings"

	"believers_palace/internal/auth"
)

var ErrForbidden = errors.New("insufficient permissions")
var ErrNotMember = errors.New("active community membership required")

const (
	defaultCursorLimit = 50
	maxCursorLimit     = 100
	maxMessageLength   = 4000
)

type store interface {
	Create(context.Context, string, string, string) (*Community, error)
	List(context.Context, string) ([]Community, error)
	Get(context.Context, string) (*Community, error)
	Membership(context.Context, string, string) (string, bool, error)
	RequestMembership(context.Context, string, string) (*Membership, error)
	ListMembers(context.Context, string, string) ([]Membership, error)
	ReviewRequest(context.Context, string, string, bool) error
	RemoveMember(context.Context, string, string) error
	Leave(context.Context, string, string) error
	CreateMessage(context.Context, string, string, string, *string, string) (*Message, error)
	ListMessages(context.Context, string, CursorQuery) ([]Message, bool, error)
	DeleteMessage(context.Context, string, string) error
	GetMessage(context.Context, string, string) (*Message, error)
}

type displayResolver interface {
	DisplayOf(context.Context, string) (string, *string, bool, error)
}

type Service struct {
	repo  store
	users displayResolver
}

func NewService(repo store, users displayResolver) *Service {
	return &Service{repo: repo, users: users}
}

func (s *Service) Create(ctx context.Context, id auth.Identity, in CreateRequest) (*Community, error) {
	name := strings.TrimSpace(in.Name)
	if name == "" {
		return nil, &ValidationError{"community name is required"}
	}
	if len(name) > 100 {
		return nil, &ValidationError{"community name is too long"}
	}
	if len(in.Description) > 2000 {
		return nil, &ValidationError{"community description is too long"}
	}
	return s.repo.Create(ctx, id.UserID, name, strings.TrimSpace(in.Description))
}

func (s *Service) List(ctx context.Context, id auth.Identity) ([]Community, error) {
	return s.repo.List(ctx, id.UserID)
}

func (s *Service) requireCommunity(ctx context.Context, cid string) (*Community, error) {
	c, err := s.repo.Get(ctx, cid)
	if errors.Is(err, ErrNotFound) {
		return nil, ErrNotFound
	}
	return c, err
}
func (s *Service) membership(ctx context.Context, id auth.Identity, cid string) (bool, bool, error) {
	status, admin, err := s.repo.Membership(ctx, cid, id.UserID)
	return status == "active", admin && status == "active", err
}
func (s *Service) requireMember(ctx context.Context, id auth.Identity, cid string) (bool, error) {
	if _, err := s.requireCommunity(ctx, cid); err != nil {
		return false, err
	}
	active, admin, err := s.membership(ctx, id, cid)
	if err != nil {
		return false, err
	}
	if !active {
		return false, ErrNotMember
	}
	return admin, nil
}

func (s *Service) Request(ctx context.Context, id auth.Identity, cid string) (*Membership, error) {
	if _, err := s.requireCommunity(ctx, cid); err != nil {
		return nil, err
	}
	m, err := s.repo.RequestMembership(ctx, cid, id.UserID)
	if err != nil {
		return nil, err
	}
	name, _, ok, err := s.users.DisplayOf(ctx, id.UserID)
	if err != nil {
		return nil, err
	}
	if ok {
		m.UserName = name
	}
	return m, nil
}
func (s *Service) Requests(ctx context.Context, id auth.Identity, cid string) ([]Membership, error) {
	if _, err := s.requireCommunity(ctx, cid); err != nil {
		return nil, err
	}
	_, admin, err := s.membership(ctx, id, cid)
	if err != nil {
		return nil, err
	}
	if !admin {
		return nil, ErrForbidden
	}
	return s.repo.ListMembers(ctx, cid, "pending")
}
func (s *Service) Members(ctx context.Context, id auth.Identity, cid string) ([]Membership, error) {
	if _, err := s.requireMember(ctx, id, cid); err != nil {
		return nil, err
	}
	return s.repo.ListMembers(ctx, cid, "active")
}
func (s *Service) Review(ctx context.Context, id auth.Identity, cid, requestID string, approve bool) error {
	if _, err := s.requireCommunity(ctx, cid); err != nil {
		return err
	}
	_, admin, err := s.membership(ctx, id, cid)
	if err != nil {
		return err
	}
	if !admin {
		return ErrForbidden
	}
	return s.repo.ReviewRequest(ctx, cid, requestID, approve)
}
func (s *Service) Remove(ctx context.Context, id auth.Identity, cid, userID string) error {
	if _, err := s.requireCommunity(ctx, cid); err != nil {
		return err
	}
	_, admin, err := s.membership(ctx, id, cid)
	if err != nil {
		return err
	}
	if !admin {
		return ErrForbidden
	}
	if id.UserID == userID {
		return ErrForbidden
	}
	return s.repo.RemoveMember(ctx, cid, userID)
}
func (s *Service) Leave(ctx context.Context, id auth.Identity, cid string) error {
	if _, err := s.requireCommunity(ctx, cid); err != nil {
		return err
	}
	return s.repo.Leave(ctx, cid, id.UserID)
}
func (s *Service) ListMessages(ctx context.Context, id auth.Identity, cid string, q CursorQuery) (*CursorPage, error) {
	if q.Before > 0 && q.After > 0 {
		return nil, &ValidationError{"use either before or after, not both"}
	}
	if q.Limit < 1 {
		q.Limit = defaultCursorLimit
	}
	if q.Limit > maxCursorLimit {
		q.Limit = maxCursorLimit
	}
	if _, err := s.requireMember(ctx, id, cid); err != nil {
		return nil, err
	}
	items, more, err := s.repo.ListMessages(ctx, cid, q)
	if items == nil {
		items = []Message{}
	}
	return &CursorPage{Data: items, HasMore: more}, err
}
func (s *Service) Post(ctx context.Context, id auth.Identity, cid string, in MessageRequest) (*Message, error) {
	if _, err := s.requireMember(ctx, id, cid); err != nil {
		return nil, err
	}
	content := strings.TrimSpace(in.Content)
	if content == "" {
		return nil, &ValidationError{"message content is required"}
	}
	if len(content) > maxMessageLength {
		return nil, &ValidationError{"message is too long"}
	}
	name, pic, ok, err := s.users.DisplayOf(ctx, id.UserID)
	if err != nil {
		return nil, err
	}
	if !ok {
		name = "User"
	}
	return s.repo.CreateMessage(ctx, cid, id.UserID, name, pic, content)
}
func (s *Service) DeleteMessage(ctx context.Context, id auth.Identity, cid, messageID string) error {
	admin, err := s.requireMember(ctx, id, cid)
	if err != nil {
		return err
	}
	msg, err := s.repo.GetMessage(ctx, cid, messageID)
	if err != nil {
		return err
	}
	if !admin && (msg.UserID == nil || *msg.UserID != id.UserID) {
		return ErrForbidden
	}
	return s.repo.DeleteMessage(ctx, cid, messageID)
}

type ValidationError struct{ Message string }

func (e *ValidationError) Error() string { return e.Message }
