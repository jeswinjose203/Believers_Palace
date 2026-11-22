CREATE TABLE catechism_teachers (
    class_id UUID NOT NULL REFERENCES catechism_classes(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    substitute BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (class_id, user_id)
);
CREATE INDEX catechism_teachers_user ON catechism_teachers(user_id);


CREATE TABLE catechism_attendance (
    enrollment_id UUID NOT NULL REFERENCES catechism_enrollments(id) ON DELETE CASCADE,
    lesson_date DATE NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('present', 'absent', 'excused')),
    PRIMARY KEY (enrollment_id, lesson_date)
);

CREATE TABLE catechism_marks (
    enrollment_id UUID NOT NULL REFERENCES catechism_enrollments(id) ON DELETE CASCADE,
    assessment TEXT NOT NULL,
    score INTEGER NOT NULL CHECK (score >= 0),
    maximum INTEGER NOT NULL CHECK (maximum > 0 AND score <= maximum),
    published_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (enrollment_id, assessment)
);

CREATE TABLE catechism_publications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id UUID NOT NULL REFERENCES catechism_classes(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('syllabus', 'announcement')),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    published_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX catechism_current_syllabus ON catechism_publications(class_id)
    WHERE kind = 'syllabus';
CREATE INDEX catechism_publications_class ON catechism_publications(class_id, published_at DESC);
