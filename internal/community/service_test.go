package community

import (
	"context"
	"errors"
	"testing"

	"believers_palace/internal/auth"
)

type memoryStore struct {
	communities map[string]*Community
	members     map[string]map[string]*Membership
	messages    map[string]*Message
	requestSeq  int
}

func newMemoryStore() *memoryStore {
	return &memoryStore{communities: map[string]*Community{}, members: map[string]map[string]*Membership{}, messages: map[string]*Message{}}
}
func (s *memoryStore) Create(_ context.Context, user, name, description string) (*Community, error) {
	c := &Community{ID: "c1", CreatorID: user, Name: name, Description: description}
	s.communities[c.ID] = c
	s.members[c.ID] = map[string]*Membership{}
	s.members[c.ID][user] = &Membership{ID: "creator", CommunityID: c.ID, UserID: user, Status: "active", IsAdmin: true}
	return c, nil
}
func (s *memoryStore) List(context.Context, string) ([]Community, error) {
	out := make([]Community, 0, len(s.communities))
	for _, c := range s.communities {
		out = append(out, *c)
	}
	return out, nil
}
func (s *memoryStore) Get(_ context.Context, id string) (*Community, error) {
	c := s.communities[id]
	if c == nil {
		return nil, ErrNotFound
	}
	return c, nil
}
func (s *memoryStore) Membership(_ context.Context, cid, uid string) (string, bool, error) {
	m := s.members[cid][uid]
	if m == nil {
		return "", false, nil
	}
	return m.Status, m.IsAdmin, nil
}
func (s *memoryStore) RequestMembership(_ context.Context, cid, uid string) (*Membership, error) {
	if s.members[cid][uid] != nil && s.members[cid][uid].Status != "declined" {
		return nil, ErrConflict
	}
	s.requestSeq++
	m := &Membership{ID: "r" + string(rune('0'+s.requestSeq)), CommunityID: cid, UserID: uid, Status: "pending"}
	s.members[cid][uid] = m
	return m, nil
}
func (s *memoryStore) ListMembers(_ context.Context, cid, status string) ([]Membership, error) {
	out := []Membership{}
	for _, m := range s.members[cid] {
		if status == "" || m.Status == status {
			out = append(out, *m)
		}
	}
	return out, nil
}
func (s *memoryStore) ReviewRequest(_ context.Context, cid, rid string, approve bool) error {
	for _, m := range s.members[cid] {
		if m.ID == rid && m.Status == "pending" {
			if approve {
				m.Status = "active"
			} else {
				m.Status = "declined"
			}
			return nil
		}
	}
	return ErrNotFound
}
func (s *memoryStore) RemoveMember(_ context.Context, cid, uid string) error {
	m := s.members[cid][uid]
	if m == nil || m.IsAdmin {
		return ErrNotFound
	}
	delete(s.members[cid], uid)
	return nil
}
func (s *memoryStore) Leave(_ context.Context, cid, uid string) error {
	m := s.members[cid][uid]
	if m == nil {
		return ErrNotFound
	}
	if m.IsAdmin {
		return errors.New("last admin")
	}
	delete(s.members[cid], uid)
	return nil
}
func (s *memoryStore) CreateMessage(_ context.Context, cid, uid, name string, pic *string, text string) (*Message, error) {
	m := &Message{ID: "m1", CommunityID: cid, UserID: &uid, AuthorName: name, Content: text}
	s.messages[m.ID] = m
	return m, nil
}
func (s *memoryStore) ListMessages(context.Context, string, CursorQuery) ([]Message, bool, error) {
	return []Message{}, false, nil
}
func (s *memoryStore) DeleteMessage(_ context.Context, cid, id string) error {
	if s.messages[id] == nil {
		return ErrNotFound
	}
	delete(s.messages, id)
	return nil
}
func (s *memoryStore) GetMessage(_ context.Context, cid, id string) (*Message, error) {
	m := s.messages[id]
	if m == nil || m.CommunityID != cid {
		return nil, ErrNotFound
	}
	return m, nil
}

type testUsers struct{}

func (testUsers) DisplayOf(context.Context, string) (string, *string, bool, error) {
	return "Tester", nil, true, nil
}

func TestCreatorAdminAndMembershipApproval(t *testing.T) {
	ctx := context.Background()
	store := newMemoryStore()
	svc := NewService(store, testUsers{})
	admin := auth.Identity{UserID: "owner"}
	c, err := svc.Create(ctx, admin, CreateRequest{Name: "  Choir  "})
	if err != nil {
		t.Fatal(err)
	}
	if status, isAdmin, _ := store.Membership(ctx, c.ID, admin.UserID); status != "active" || !isAdmin {
		t.Fatalf("creator membership = %q admin=%v", status, isAdmin)
	}

	member := auth.Identity{UserID: "new-member"}
	if _, err = svc.ListMessages(ctx, member, c.ID, CursorQuery{}); !errors.Is(err, ErrNotMember) {
		t.Fatalf("pending/nonmember read err=%v", err)
	}
	req, err := svc.Request(ctx, member, c.ID)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = svc.Requests(ctx, member, c.ID); !errors.Is(err, ErrForbidden) {
		t.Fatalf("member read requests err=%v", err)
	}
	if err = svc.Review(ctx, member, c.ID, req.ID, true); !errors.Is(err, ErrForbidden) {
		t.Fatalf("member approval err=%v", err)
	}
	if err = svc.Review(ctx, admin, c.ID, req.ID, true); err != nil {
		t.Fatal(err)
	}
	if _, err = svc.Post(ctx, member, c.ID, MessageRequest{Content: "hello"}); err != nil {
		t.Fatalf("approved member post: %v", err)
	}
}

func TestCommunityMessageRequiresActiveMembershipAndAdminModeration(t *testing.T) {
	ctx := context.Background()
	store := newMemoryStore()
	svc := NewService(store, testUsers{})
	c, _ := svc.Create(ctx, auth.Identity{UserID: "admin"}, CreateRequest{Name: "Group"})
	request, err := svc.Request(ctx, auth.Identity{UserID: "member"}, c.ID)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = svc.Post(ctx, auth.Identity{UserID: "member"}, c.ID, MessageRequest{Content: "x"}); !errors.Is(err, ErrNotMember) {
		t.Fatalf("pending post err=%v", err)
	}
	if err = svc.Review(ctx, auth.Identity{UserID: "admin"}, c.ID, request.ID, true); err != nil {
		t.Fatal(err)
	}
	msg, err := svc.Post(ctx, auth.Identity{UserID: "member"}, c.ID, MessageRequest{Content: "hello"})
	if err != nil {
		t.Fatal(err)
	}
	if err = svc.DeleteMessage(ctx, auth.Identity{UserID: "other"}, c.ID, msg.ID); !errors.Is(err, ErrNotMember) {
		t.Fatalf("nonmember moderation err=%v", err)
	}
	other := auth.Identity{UserID: "other-member"}
	otherRequest, err := svc.Request(ctx, other, c.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err = svc.Review(ctx, auth.Identity{UserID: "admin"}, c.ID, otherRequest.ID, true); err != nil {
		t.Fatal(err)
	}
	if err = svc.DeleteMessage(ctx, other, c.ID, msg.ID); !errors.Is(err, ErrForbidden) {
		t.Fatalf("non-author member moderation err=%v", err)
	}
	if err = svc.DeleteMessage(ctx, auth.Identity{UserID: "admin"}, c.ID, msg.ID); err != nil {
		t.Fatalf("admin moderation: %v", err)
	}
}
