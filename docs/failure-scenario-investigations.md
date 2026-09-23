# Failed Deployment Investigations (Phase 5)

Two scenarios executed by the trainer, investigated without being told the
root cause in advance, per the exercise rules. Each follows the Phase 6
recovery path: candidate removed, current production version kept live.

---

## Investigation A — Scenario #29: Candidate cannot reach the database

**Setup used by trainer:** candidate started with `orders-network` correct,
but `orders-db` temporarily disconnected from that network (simulating a
connectivity fault) before the deploy was triggered.

**Jenkins console (excerpt):**
```
[Container Validation] OK   - container is running
[Container Validation] OK   - attached to network 'orders-network'
[Container Validation] OK   - port mapping confirmed: 0.0.0.0:8082->3000/tcp
[Container Validation] OK   - all required environment variables are present
[Application Health Check] OK   - health check passed on attempt 1
[Integration Check] Checking /version on candidate matches build identity
[Integration Check] OK   - candidate identity confirmed: version=7.9 commit=a1b2c3d
[Integration Check] Checking database connectivity via /db-check
[Integration Check] ---- /db-check response ----
{
  "db": "unreachable",
  "target": "orders-db:5432/orders",
  "detail": "tcp connect to orders-db:5432 timed out"
}
[Integration Check] -----------------------------
[Integration Check] FAIL - candidate cannot reach the database (Phase 5 #29/#30) - see response above
```

**Diagnosis steps taken:**
1. Health check passed — ruled out the process crashing or the HTTP server
   itself being broken.
2. `/version` matched the built image exactly — ruled out a stale/wrong
   image.
3. `/db-check` isolated the failure to network reachability specifically
   between the app and the database, not the app itself.
4. `docker network inspect orders-network` was run manually and showed
   `orders-db` was not currently a member of the network.

**Root cause:** `orders-db` had been disconnected from `orders-network`
(simulating an operational fault, e.g. a manual `docker network disconnect`
or a bad network reattachment during host maintenance).

**Recovery (Phase 6):**
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
Build result: **FAILURE** (correctly). Production continued serving 7.8
on `orders-blue` throughout, unaffected.

---

## Investigation B — Scenario #28: Candidate uses the wrong application port

**Setup used by trainer:** the Jenkinsfile's `start-candidate.sh` call was
temporarily edited to publish the candidate on `-p 8082:8080` (container
port 8080) while the application image still listens on port 3000
internally — reproducing the original incident's exact failure mode inside
the controlled blue-green flow this time.

**Jenkins console (excerpt):**
```
[Container Validation] OK   - container is running
[Container Validation] OK   - attached to network 'orders-network'
[Container Validation] FAIL - container port 3000 is not published on expected host port 8082 (got: '') - Phase 5 #28
```

**Diagnosis steps taken:**
1. `docker port orders-green 3000/tcp` returned nothing — port 3000 was
   never published at all; `docker port orders-green 8080/tcp` showed
   `0.0.0.0:8082->8080/tcp` instead.
2. `docker logs orders-green` confirmed the process was actually listening
   on 3000 inside the container, as expected — the container itself was
   healthy, only the port mapping was wrong.
3. This matches the class of bug that caused the real incident, but here
   it was caught in **Container Validation**, before Health Check, before
   Traffic Switch, and long before any user could be affected.

**Root cause:** a mismatch between the port the application actually
listens on (3000, fixed by the Dockerfile/app) and the port mapping the
deploy script published (8080), i.e. exactly Phase 5 scenario #28.

**Recovery (Phase 6):** identical rollback path to Investigation A —
candidate removed, `orders-blue` (current production) confirmed still
serving traffic on port 8080, build marked **FAILURE**.

---

## Why both were caught before impacting users

In both cases the failure was detected **before Traffic Switch**, so
`orders-router` never stopped pointing at the previously-verified live
color. This is the direct fix for the original incident, where the
previous version was torn down before the new one was ever proven to work.
