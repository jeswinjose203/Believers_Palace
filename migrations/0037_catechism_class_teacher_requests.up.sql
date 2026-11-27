DROP INDEX IF EXISTS catechism_teacher_requests_pending;

CREATE UNIQUE INDEX catechism_teacher_requests_class_pending
    ON catechism_teacher_requests(church_id, user_id, class_id)
    WHERE status='pending' AND class_id IS NOT NULL;
