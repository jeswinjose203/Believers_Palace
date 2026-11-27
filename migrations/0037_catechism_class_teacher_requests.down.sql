DROP INDEX IF EXISTS catechism_teacher_requests_class_pending;

WITH duplicate_pending AS (
    SELECT id, row_number() OVER (
        PARTITION BY church_id, user_id ORDER BY created_at, id
    ) AS position
    FROM catechism_teacher_requests
    WHERE status='pending'
)
UPDATE catechism_teacher_requests q
SET status='rejected', reviewed_at=now()
FROM duplicate_pending d
WHERE q.id=d.id AND d.position > 1;

CREATE UNIQUE INDEX catechism_teacher_requests_pending
    ON catechism_teacher_requests(church_id, user_id) WHERE status='pending';
