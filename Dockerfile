# ---- Build stage ----
FROM golang:1.24-alpine AS builder

WORKDIR /app

# Cache dependencies first
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build a static binary
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app/bin/api ./cmd/api

# ---- Runtime stage ----
FROM alpine:3.20

# ca-certificates for TLS, tzdata for time zones
RUN apk add --no-cache ca-certificates tzdata && \
    adduser -D -u 10001 appuser

WORKDIR /app

COPY --from=builder /app/bin/api /app/api

# Create a writable storage directory owned by the non-root runtime user.
RUN mkdir -p /app/storage && chown -R appuser:appuser /app/storage

USER appuser

EXPOSE 8080

ENTRYPOINT ["/app/api"]
