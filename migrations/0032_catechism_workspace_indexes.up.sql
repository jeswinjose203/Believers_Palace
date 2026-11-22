CREATE INDEX catechism_classes_teacher ON catechism_classes (teacher_user_id, id)
    WHERE teacher_user_id IS NOT NULL;
CREATE INDEX catechism_workspace_roster ON catechism_enrollments (class_id, student_name, id)
    WHERE status IN ('approved', 'completed');
CREATE INDEX catechism_workspace_guardian ON catechism_enrollments (class_id, guardian_id, student_name, id)
    WHERE status IN ('approved', 'completed');
CREATE INDEX catechism_workspace_announcements ON catechism_publications (class_id, published_at DESC, id DESC)
    WHERE kind = 'announcement';
CREATE INDEX catechism_workspace_marks ON catechism_marks (enrollment_id, published_at DESC, assessment);
