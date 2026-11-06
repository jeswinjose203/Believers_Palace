package chat

import (
	"context"
	"testing"

	"believers_palace/internal/auth"
)

// fakeStore is an in-memory messageStore for tests.
type fakeStore struct {
	msgs    map[string]*Message
	deleted []string
}

func newFakeStore() *fakeStore {
	return &fakeStore{msgs: map[string]*Message{}}
}

func (f *fakeStore) Create(_ context.Context, eventID string, userID *string, name string, pic *string, content string) (*Message, error) {
	m := &Message{ID: "m-new", EventID: eventID, UserID: userID, AuthorName: name, AuthorPic: pic, Content: content}
	f.msgs[m.ID] = m
	return m, nil
}

func (f *fakeStore) GetByID(_ context.Context, id string) (*Message, error) {
	m, ok := f.msgs[id]
	if !ok {
		return nil, ErrNotFound
	}
	return m, nil
}

func (f *fakeStore) ListByEvent(_ context.Context, eventID string, _, _ int) ([]Message, int, error) {
	var out []Message
	for _, m := range f.msgs {
		if m.EventID == eventID {
			out = append(out, *m)
		}
	}
	return out, len(out), nil
}

func (f *fakeStore) Delete(_ context.Context, id string) error {
	if _, ok := f.msgs[id]; !ok {
		return ErrNotFound
	}
	delete(f.msgs, id)
	f.deleted = append(f.deleted, id)
	return nil
}

// fakeEvents maps event IDs to church IDs. Events are treated as requiring
// registration unless listed in openEvents.
type fakeEvents map[string]string

// openEvents lists event IDs that do NOT require registration.
var openEvents = map[string]bool{}

func (f fakeEvents) LookupEvent(_ context.Context, eventID string) (EventInfo, bool, error) {
	c, ok := f[eventID]
	return EventInfo{ChurchID: c, RegistrationRequired: !openEvents[eventID]}, ok, nil
}

type fakeUsers struct{}

func (fakeUsers) DisplayOf(_ context.Context, userID string) (string, *string, bool, error) {
	return "Tester", nil, true, nil
}

// allRegistered treats every user as registered.
type allRegistered struct{}

func (allRegistered) IsRegistered(context.Context, string, string) (bool, error) { return true, nil }

// fakeRegs is a set of "eventID/userID" keys that are registered.
type fakeRegs map[string]bool

func (f fakeRegs) IsRegistered(_ context.Context, eventID, userID string) (bool, error) {
	return f[eventID+"/"+userID], nil
}

func strptr(s string) *string { return &s }

func TestPostValidation(t *testing.T) {
	store := newFakeStore()
	svc := NewService(store, fakeEvents{"e1": "c1"}, fakeUsers{}, allRegistered{})
	id := auth.Identity{UserID: "u1", Role: auth.RoleUser}

	if _, err := svc.Post(context.Background(), id, "e1", CreateRequest{Content: "   "}); err == nil {
		t.Error("expected error for blank content")
	}
	if _, err := svc.Post(context.Background(), id, "missing", CreateRequest{Content: "hi"}); err != ErrEventNotFound {
		t.Errorf("expected ErrEventNotFound, got %v", err)
	}
	msg, err := svc.Post(context.Background(), id, "e1", CreateRequest{Content: "hello"})
	if err != nil {
		t.Fatalf("Post: %v", err)
	}
	if msg.AuthorName != "Tester" || msg.Content != "hello" {
		t.Errorf("unexpected message: %+v", msg)
	}
}

func TestDeleteAuthorization(t *testing.T) {
	events := fakeEvents{"e1": "c1"}

	seed := func() *fakeStore {
		s := newFakeStore()
		s.msgs["msg-author"] = &Message{ID: "msg-author", EventID: "e1", UserID: strptr("owner"), Content: "x"}
		return s
	}

	cases := []struct {
		name     string
		id       auth.Identity
		msgID    string
		wantErr  error
		wantGone bool
	}{
		{"author deletes own", auth.Identity{UserID: "owner", Role: auth.RoleUser}, "msg-author", nil, true},
		{"super_admin deletes any", auth.Identity{UserID: "x", Role: auth.RoleSuperAdmin}, "msg-author", nil, true},
		{"church_admin same church", auth.Identity{UserID: "x", Role: auth.RoleChurchAdmin, ChurchID: "c1"}, "msg-author", nil, true},
		{"church_admin other church", auth.Identity{UserID: "x", Role: auth.RoleChurchAdmin, ChurchID: "c2"}, "msg-author", ErrForbidden, false},
		{"other user forbidden", auth.Identity{UserID: "stranger", Role: auth.RoleUser}, "msg-author", ErrForbidden, false},
		{"missing message", auth.Identity{UserID: "owner", Role: auth.RoleUser}, "nope", ErrNotFound, false},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			store := seed()
			svc := NewService(store, events, fakeUsers{}, allRegistered{})
			err := svc.Delete(context.Background(), c.id, "e1", c.msgID)
			if err != c.wantErr {
				t.Fatalf("err = %v, want %v", err, c.wantErr)
			}
			_, exists := store.msgs[c.msgID]
			if c.wantGone && exists {
				t.Error("message should have been deleted")
			}
			if !c.wantGone && c.msgID == "msg-author" && !exists {
				t.Error("message should NOT have been deleted")
			}
		})
	}
}

// TestDeleteWrongEvent ensures a message cannot be deleted via a mismatched
// event ID in the path.
func TestDeleteWrongEvent(t *testing.T) {
	store := newFakeStore()
	store.msgs["m1"] = &Message{ID: "m1", EventID: "e1", UserID: strptr("owner"), Content: "x"}
	svc := NewService(store, fakeEvents{"e1": "c1", "e2": "c1"}, fakeUsers{}, allRegistered{})

	err := svc.Delete(context.Background(), auth.Identity{UserID: "owner", Role: auth.RoleUser}, "e2", "m1")
	if err != ErrNotFound {
		t.Fatalf("err = %v, want ErrNotFound", err)
	}
}

// TestChatRequiresRegistration verifies only registered attendees and church
// staff may read or post.
func TestChatRequiresRegistration(t *testing.T) {
	events := fakeEvents{"e1": "c1"}
	regs := fakeRegs{"e1/member": true}

	cases := []struct {
		name    string
		id      auth.Identity
		wantErr error
	}{
		{"registered user", auth.Identity{UserID: "member", Role: auth.RoleUser}, nil},
		{"unregistered user", auth.Identity{UserID: "stranger", Role: auth.RoleUser}, ErrNotRegistered},
		{"super_admin", auth.Identity{UserID: "sa", Role: auth.RoleSuperAdmin}, nil},
		{"church_admin same church", auth.Identity{UserID: "a", Role: auth.RoleChurchAdmin, ChurchID: "c1"}, nil},
		{"priest same church", auth.Identity{UserID: "p", Role: auth.RolePriest, ChurchID: "c1"}, nil},
		{"church_admin other church", auth.Identity{UserID: "a2", Role: auth.RoleChurchAdmin, ChurchID: "c2"}, ErrNotRegistered},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			svc := NewService(newFakeStore(), events, fakeUsers{}, regs)
			_, _, err := svc.List(context.Background(), c.id, "e1", 10, 0)
			if err != c.wantErr {
				t.Errorf("List err = %v, want %v", err, c.wantErr)
			}
			_, err = svc.Post(context.Background(), c.id, "e1", CreateRequest{Content: "hi"})
			if err != c.wantErr {
				t.Errorf("Post err = %v, want %v", err, c.wantErr)
			}
		})
	}
}

// TestChatOpenWhenRegistrationNotRequired verifies that events without the
// registrationRequired flag allow any authenticated user to chat.
func TestChatOpenWhenRegistrationNotRequired(t *testing.T) {
	openEvents["open"] = true
	defer delete(openEvents, "open")

	svc := NewService(newFakeStore(), fakeEvents{"open": "c1", "closed": "c1"}, fakeUsers{}, fakeRegs{})
	stranger := auth.Identity{UserID: "stranger", Role: auth.RoleUser}

	if _, err := svc.Post(context.Background(), stranger, "open", CreateRequest{Content: "hi"}); err != nil {
		t.Errorf("open event: Post err = %v, want nil", err)
	}
	if _, _, err := svc.List(context.Background(), stranger, "open", 10, 0); err != nil {
		t.Errorf("open event: List err = %v, want nil", err)
	}
	if _, err := svc.Post(context.Background(), stranger, "closed", CreateRequest{Content: "hi"}); err != ErrNotRegistered {
		t.Errorf("registration-required event: Post err = %v, want ErrNotRegistered", err)
	}
}
