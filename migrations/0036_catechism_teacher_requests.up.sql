CREATE TABLE catechism_teacher_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id UUID NOT NULL REFERENCES churches(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    class_id UUID REFERENCES catechism_classes(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX catechism_teacher_requests_pending
    ON catechism_teacher_requests(church_id, user_id) WHERE status='pending';
CREATE INDEX catechism_teacher_requests_church
    ON catechism_teacher_requests(church_id, created_at DESC);
