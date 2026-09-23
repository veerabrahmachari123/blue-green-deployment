# Successful Deployment Evidence

Example of a clean promotion of version 7.9 (candidate `orders-green`) over
the previously live 7.8 (`orders-blue`), run via:

```
docker compose up -d          # baseline: network, db, router
scripts/bootstrap-initial-state.sh   # brings orders-blue (7.8) live once
# Jenkins build with APP_VERSION=7.9
```

## Jenkins console (abridged, in stage order)

```
[Checkout] Checked out commit a1b2c3d4e5f6... on branch main
[Validate Version] OK   - version '7.9' and commit 'a1b2c3d4e5f6...' are valid
[Unit/Application Test] PASS: /version returned expected payload
[Unit/Application Test] PASS: /health reports ok after warm-up
[Unit/Application Test] PASS: /db-check correctly detects an unreachable database
[Docker Build] OK   - built orders-api:7.9-a1b2c3d
[Docker Image Validation] OK   - image orders-api:7.9-a1b2c3d carries version=7.9 commit=a1b2c3d4e5f6...
[Start Candidate] ==== BLUE/GREEN STATE ====
[Start Candidate] CURRENT (live):   blue
[Start Candidate] CANDIDATE (new):  green  (image=orders-api:7.9-a1b2c3d, port=8082)
[Start Candidate] ===========================
[Start Candidate] OK   - candidate 'orders-green' started
[Container Validation] OK   - container is running
[Container Validation] OK   - attached to network 'orders-network'
[Container Validation] OK   - port mapping confirmed: 0.0.0.0:8082->3000/tcp
[Container Validation] OK   - process inside the container is listening on 3000
[Container Validation] OK   - all required environment variables are present
[Application Health Check] OK   - health check passed on attempt 1: {"status": "ok", "color": "green", ...}
[Integration Check] OK   - candidate identity confirmed: version=7.9 commit=a1b2c3d4e5f6...
[Integration Check] OK   - database connectivity confirmed: {"db": "reachable", ...}
[Traffic Switch] ==== TRAFFIC SWITCH ====
[Traffic Switch] Routing production traffic (host port 8080) to: green (orders-green:3000)
[Traffic Switch] =========================
[Traffic Switch] OK   - router reloaded, pointing at green
[Traffic Switch] OK   - verified: production traffic on port 8080 is now served by green, version 7.9
[Old Version Cleanup] OK   - removed 'orders-blue'
[Deployment Verification] OK   - deployment verified: version=7.9 commit=a1b2c3d4e5f6... color=green
Finished: SUCCESS
```

## Post-deployment state

```
$ docker ps --filter name=orders- --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
NAMES           IMAGE                     STATUS         PORTS
orders-green    orders-api:7.9-a1b2c3d    Up 2 minutes   0.0.0.0:8082->3000/tcp
orders-router   nginx:1.27-alpine         Up 25 minutes  0.0.0.0:8080->8080/tcp
orders-db       postgres:16-alpine        Up 25 minutes  5432/tcp

$ curl -s http://localhost:8080/version
{
  "version": "7.9",
  "gitCommit": "a1b2c3d4e5f6...",
  "color": "green",
  "port": 3000
}

$ cat .evidence/deployment-7.9.json
{
  "version": "7.9",
  "gitCommit": "a1b2c3d4e5f6...",
  "activeColor": "green",
  "verifiedAt": "2026-09-23T08:00:00Z",
  "routerVersionResponse": { "version": "7.9", "gitCommit": "a1b2c3d4e5f6...", "color": "green", "port": 3000 },
  "routerHealthResponse": { "status": "ok", "color": "green", "version": "7.9", ... }
}
```

`orders-blue` is gone (removed only after the switch was verified);
`orders-green` is now the live color; the deployment manifest ties the
running version directly back to Git commit `a1b2c3d4e5f6...`.
