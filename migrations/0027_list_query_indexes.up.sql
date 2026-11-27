CREATE INDEX idx_communities_created_id ON communities (created_at DESC, id DESC);
CREATE INDEX idx_events_church_start ON events (church_id, start_date DESC);
CREATE INDEX idx_announcements_church_effective_date
    ON announcements (church_id, (COALESCE(published_at, created_at)) DESC);
CREATE INDEX idx_bookings_user_start ON bookings (user_id, start_date DESC);
CREATE INDEX idx_bookings_church_start ON bookings (church_id, start_date DESC);
