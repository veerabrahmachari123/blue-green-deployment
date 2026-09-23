#!/usr/bin/env bash
# Brings the environment up to the Phase 3 starting point:
#   orders-network, orders-db, orders-router (port 8080) all running,
#   and orders-blue running version 7.8 on port 8081 as the live color.
# Run this ONCE before the first Jenkins pipeline execution.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
ROOT="$(cd "$DIR/.." && pwd)"

log "Bringing up network, database and router via docker compose"
docker compose -f "$ROOT/docker-compose.yml" up -d

log "Waiting for orders-db to become healthy"
for i in $(seq 1 30); do
  STATUS=$(docker inspect -f '{{.State.Health.Status}}' "$DB_CONTAINER" 2>/dev/null || echo "starting")
  [ "$STATUS" = "healthy" ] && break
  sleep 2
done
[ "$STATUS" = "healthy" ] || fail "orders-db did not become healthy in time"
ok "orders-db is healthy"

if [ ! -f "$DIR/secrets/orders-api.env" ]; then
  fail "create $DIR/secrets/orders-api.env from orders-api.env.example first"
fi

if container_exists "orders-blue"; then
  log "orders-blue already exists - leaving it as-is"
else
  log "Building baseline image orders-api:7.8"
  docker build --build-arg VERSION=7.8 --build-arg GIT_COMMIT=0000000baseline \
    -t orders-api:7.8-0000000 -t orders-api:7.8 -f "$ROOT/Dockerfile" "$ROOT"

  log "Starting orders-blue (version 7.8) on host port 8081"
  docker run -d \
    --name orders-blue \
    --network "$NETWORK_NAME" \
    --network-alias orders-blue \
    -p 8081:3000 \
    --env-file "$DIR/secrets/orders-api.env" \
    -e VERSION=7.8 \
    -e GIT_COMMIT=0000000baseline \
    -e COLOR=blue \
    -e DB_HOST=orders-db \
    -e DB_PORT=5432 \
    -e DB_NAME=orders \
    --restart unless-stopped \
    orders-api:7.8 >/dev/null
fi

ok "baseline is up: orders-blue (7.8) live behind orders-router on port 8080"
log "Verify with: curl http://localhost:8080/version"
