.PHONY: run build tidy test migrate-up migrate-down db-create seed docker-seed docker-build docker-up docker-down docker-logs

APP_NAME=believers_palace
DB_URL=postgres://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/$(DB_NAME)?sslmode=$(DB_SSLMODE)

# Load .env if present
ifneq (,$(wildcard .env))
include .env
export
endif

run:
	go run ./cmd/api

build:
	go build -o bin/$(APP_NAME) ./cmd/api

tidy:
	go mod tidy

test:
	go test ./...

# Requires golang-migrate: https://github.com/golang-migrate/migrate
migrate-up:
	migrate -path migrations -database "$(DB_URL)" up

migrate-down:
	migrate -path migrations -database "$(DB_URL)" down 1

db-create:
	createdb $(DB_NAME) || true

# ---- Development seed ----
# Inserts the fixed debug user used by SKIP_JWT_VALIDATION. Development only.
seed:
	psql "$(DB_URL)" -f seeds/dev_seed.sql

# Apply the seed inside the Docker Postgres container.
docker-seed:
	docker exec -i $(APP_NAME)_db psql -U $(DB_USER) -d $(DB_NAME) < seeds/dev_seed.sql

# ---- Docker ----
docker-build:
	docker compose build

docker-up:
	docker compose up -d --build

docker-down:
	docker compose down

docker-logs:
	docker compose logs -f api
