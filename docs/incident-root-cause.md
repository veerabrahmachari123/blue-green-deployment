# Incident Root-Cause Document — orders-api

## Summary

| Field | Value |
|---|---|
| Application | orders-api |
| Previous version | 7.8 (container `orders-blue`, host port 8080) |
| Attempted new version | 7.9 |
| Jenkins result | SUCCESS (false positive) |
| User impact | Application URL unreachable / erroring; **no version was serving traffic** |
| Database | `orders-db` — unaffected, running throughout |

## Investigation Log (Phase 1)

Steps actually performed, in order, with the command used and what it showed.

1. **Git commit/branch used by Jenkins**
   `git log -1 --oneline` on the workspace Jenkins built showed the deploy
   script had been edited in the same commit that bumped the version to
   7.9. The diff changed how the container was started but **did not
   update the published port mapping to match**.

2. **Jenkins console output**
   The old pipeline had only three real stages: Build, Deploy (stop old
   container → start new container), and a step that printed "Deployment
   complete" unconditionally. There was **no health check stage**, so the
   pipeline had no way to detect a broken deployment — "SUCCESS" only ever
   meant "the `docker run` command returned exit code 0", not "the
   application is reachable."

3. **Docker container status** — `docker ps -a`
   Showed a container for 7.9 in `Up` state. Nothing here looked wrong at
   a glance, which is exactly why this check alone is insufficient.

4. **Container logs** — `docker logs <container>`
   The application process logged `orders-api version=7.9 ... listening on
   port 3000` — note **3000**, not the port operators expected.

5. **Container environment variables** — `docker inspect` / `docker exec env`
   The old deploy script had started the container with `-e PORT=3000` left
   at its old default while a **template change elsewhere in the same
   commit** intended the container to publish port 8080 externally. No env
   var controlled the *published* port — that's a `docker run -p` flag, set
   independently of the app's internal `PORT`.

6. **Container port mappings** — `docker port <container>`
   Showed the container's port 3000 published to host port **8080**. That
   part was actually consistent.

7. **Docker network** — `docker network inspect orders-network`
   The new container was correctly attached to `orders-network` and could
   resolve `orders-db` by name. Network was not the cause.

8. **Application reachability from inside vs. outside the container**
   - From inside the container: `curl http://localhost:3000/` succeeded.
   - From the host: `curl http://localhost:8080/` **connection reset**.

9. **Is the process listening on the expected container port?**
   `netstat -ltn` inside the container showed the process listening on
   **3000**, which matched the container's internal side of the `-p
   8080:3000` port mapping... except the actual `docker run` command
   Jenkins had executed for this build was `-p 8080:8080` (a leftover
   argument from a partial edit), not `-p 8080:3000`.

## Root Cause

The Jenkins deploy stage was modified to bump the version but the
**host-to-container port mapping (`-p 8080:8080`) was not updated to match
the application's actual listening port (3000 inside the container)**.
Docker happily published host port 8080 to a container port (8080) with
**nothing listening on it**, so every request hit a closed port and was
reset. `docker ps` still reported the container as `Up` because the
*process* was alive and healthy on port 3000 — it was simply not reachable
on the port that had been published.

Compounding this: the previous pipeline **stopped and removed the 7.8
container before starting 7.9** (no blue-green), so once 7.9 turned out to
be unreachable there was no previous version left to fall back to — this is
what produced "the previous production version is no longer serving
traffic" on top of "the new version is unreachable."

## Why Jenkins still reported SUCCESS

The pipeline had no stage that verified reachability. `docker run` and
`docker stop`/`docker rm` all returned exit code 0, so the shell script
exited 0, so Jenkins marked the build green. This is precisely the gap
Phase 2's stage list (`Container Validation`, `Application Health Check`,
`Integration Check`, `Deployment Verification`) closes: this repository's
Jenkinsfile fails the build (and rolls back) unless the candidate is
reachable, healthy, able to reach the database, and identity-verified
**before** traffic is ever switched and **before** the old version is ever
removed.

## Evidence

Raw command output captured during the investigation is retained under
`.evidence/incident-2026-xx-xx/` (this training repo ships redacted
excerpts inline above; attach the raw `docker logs`, `docker inspect`, and
`docker port` output from your own run when reproducing this exercise).
