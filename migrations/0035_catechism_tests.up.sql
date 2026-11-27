CREATE TABLE catechism_tests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id UUID NOT NULL REFERENCES catechism_classes(id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 200),
    maximum INTEGER NOT NULL CHECK (maximum > 0),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (class_id, name)
);

INSERT INTO catechism_tests(class_id, name, maximum, created_by)
SELECT c.id, m.assessment, max(m.maximum), c.teacher_user_id
FROM catechism_marks m
JOIN catechism_enrollments e ON e.id=m.enrollment_id
JOIN catechism_classes c ON c.id=e.class_id
GROUP BY c.id, m.assessment, c.teacher_user_id
ON CONFLICT (class_id, name) DO UPDATE SET maximum=GREATEST(catechism_tests.maximum, EXCLUDED.maximum);

CREATE INDEX catechism_tests_class ON catechism_tests(class_id, created_at DESC, id DESC);
