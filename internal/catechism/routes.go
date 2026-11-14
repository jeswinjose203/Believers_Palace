package catechism

// HTTP routes are registered on Handler:
//   - ChurchRoutes  → /churches/{churchId}/catechism-classes
//   - ClassRoutes   → /catechism-classes/{classId}/...
//   - EnrollmentRoutes → /catechism-enrollments
//   - SessionRoutes → /catechism-sessions/{sessionId}
//
// See handler.go and internal/server/server.go for mounting.