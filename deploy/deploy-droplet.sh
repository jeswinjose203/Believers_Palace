#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
deploy_dir="$HOME/believers-palace"
env_file="$deploy_dir/.env"
if [[ ! -r "$env_file" ]]; then
    echo "Missing production configuration at $env_file" >&2
    exit 1
fi

export APP_ENV=production
export HTTP_BIND_ADDRESS=127.0.0.1 DB_BIND_ADDRESS=127.0.0.1
compose=(docker compose --project-name believers_palace --env-file "$env_file"
    -f "$source_dir/docker-compose.yml" -f "$source_dir/deploy/docker-compose.production.yml")

cd "$source_dir"
"${compose[@]}" build api
"${compose[@]}" up -d --wait db
"${compose[@]}" run --rm --no-deps migrate
"${compose[@]}" up -d --no-deps --wait --wait-timeout 90 api
