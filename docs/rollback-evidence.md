# Rollback Evidence

This document captures what "rollback" means concretely in this pipeline
and the evidence produced each time it runs (see
`docs/failure-scenario-investigations.md` for two full worked examples).

## What triggers rollback

Any non-zero exit from a stage between **Start Candidate** and **Traffic
Switch** (inclusive of Container Validation, Application Health Check, and
Integration Check) causes the Jenkinsfile's `post { failure { ... } }`
block to run `scripts/rollback-candidate.sh <candidate_color>
<current_color>`.

Because `set -euo pipefail` is sourced into every script via
`scripts/lib/common.sh`, the *first* failing command in any stage aborts
that script immediately — there is no path where a broken check is
silently ignored and the pipeline proceeds anyway.

## What rollback guarantees

1. The failed candidate container is logged (last 100 lines, secrets
   redacted) and then force-removed — no leftover container survives to
   interfere with the next run (Phase 7 repeatability).
2. `router/active-backend.conf`'s `ACTIVE_COLOR` marker is re-read and
   compared against the color that was live before the deployment started.
   If they don't match, the script fails loudly rather than assuming
   production is fine — this is a deliberate hard stop for "trust but
   verify."
3. `curl http://localhost:8080/health` is used to positively confirm
   production is still answering, not just that the router config file
   looks right.
4. The Jenkins build is marked **FAILURE**, never SUCCESS — unlike the
   original incident, a rollback never gets reported as a successful
   deployment.

## Sample evidence artifact

```
[Rollback] ==== ROLLBACK (candidate validation failed) ====
[Rollback] Removing failed candidate: orders-green
[Rollback] Production must remain on: blue
[Rollback] ---- capturing candidate logs before removal ----
orders-api version=7.9 commit=a1b2c3d color=green listening on port 3000
[Rollback] --------------------------------------------------
[Rollback] OK   - removed failed candidate 'orders-green'
[Rollback] OK   - confirmed: production is still being served by 'blue' on port 8080
```

## Post-rollback state check

After every rollback, the following was confirmed manually as part of this
exercise's evidence collection:

```
$ docker ps --filter name=orders- --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
NAMES           IMAGE              STATUS         PORTS
orders-blue     orders-api:7.8     Up 14 minutes  0.0.0.0:8081->3000/tcp
orders-router   nginx:1.27-alpine  Up 20 minutes  0.0.0.0:8080->8080/tcp
orders-db       postgres:16-alpine Up 20 minutes  5432/tcp

$ curl -s http://localhost:8080/version
{
  "version": "7.8",
  "gitCommit": "0000000baseline",
  "color": "blue",
  "port": 3000
}
```

`orders-green` does not appear — it was fully removed by rollback, and
production (`orders-blue`, 7.8) was never interrupted.
