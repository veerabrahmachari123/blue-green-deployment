# orders-api — Incident Recovery, Pipeline Repair & Blue-Green Deployment

This repository is the deliverable for the "Production Incident, Pipeline
Recovery and Blue-Green Style Deployment" training exercise. It contains a
real (if intentionally small) application, Dockerfile, Jenkinsfile, a set
of composable deployment scripts implementing a blue-green rollout behind
an nginx router, and the documentation/evidence the exercise requires.

## Layout

```
app/                    Node.js app: /health, /version, /db-check
Dockerfile               Immutable version/commit baked in via build args
docker-compose.yml        Static layer: orders-network, orders-db, orders-router
router/                  nginx traffic router (owns host port 8080)
Jenkinsfile               Full pipeline: Checkout -> ... -> Deployment Verification
scripts/                  One script per pipeline stage (also runnable by hand)
docs/                     Root cause, architecture, flow, evidence
.evidence/                Deployment manifests written by the pipeline
```

## Quick start (local, without Jenkins)

```bash
cp scripts/secrets/orders-api.env.example scripts/secrets/orders-api.env
# edit scripts/secrets/orders-api.env with a real ORDERS_API_SECRET

scripts/bootstrap-initial-state.sh          # brings up network/db/router + orders-blue (7.8)
curl http://localhost:8080/version          # -> version 7.8, color blue

scripts/validate-version.sh 7.9 $(git rev-parse HEAD)
IMAGE_TAG=$(scripts/build-image.sh 7.9 $(git rev-parse HEAD) | tail -1)
scripts/validate-image.sh "$IMAGE_TAG" 7.9 $(git rev-parse HEAD)
scripts/start-candidate.sh "$IMAGE_TAG" 7.9 $(git rev-parse HEAD)
# note the CANDIDATE_NAME / CANDIDATE_PORT printed above, then:
scripts/container-validation.sh orders-green 8082
scripts/health-check.sh 8082 orders-green
scripts/integration-check.sh 8082 7.9 $(git rev-parse HEAD)
scripts/switch-traffic.sh green 7.9
scripts/cleanup-old.sh blue
scripts/deployment-verification.sh 7.9 $(git rev-parse HEAD) green

curl http://localhost:8080/version          # -> version 7.9, color green
```

If any check between `start-candidate.sh` and `switch-traffic.sh` fails,
run `scripts/rollback-candidate.sh <candidate_color> <current_color>`
exactly as the Jenkinsfile's `post{failure{}}` block does — the candidate
is removed and the current color is re-verified as still live.

## Quick start (Jenkins)

Point a Jenkins pipeline job at this repository's `Jenkinsfile`, supply a
Credentials **file** binding named `orders-api-secret-env` containing
`ORDERS_API_SECRET=...` (wire it into the `Start Candidate` stage as shown
in the Jenkinsfile's comments), and run the job with parameter
`APP_VERSION=7.9`.

## Documentation index (Final Deliverables)

| Requirement | Location |
|---|---|
| Incident root-cause document | [`docs/incident-root-cause.md`](docs/incident-root-cause.md) |
| Final architecture diagram | [`docs/architecture-diagram.md`](docs/architecture-diagram.md) |
| Git → Jenkins → Docker flow explanation | [`docs/git-jenkins-docker-flow.md`](docs/git-jenkins-docker-flow.md) |
| Successful deployment evidence | [`docs/successful-deployment-evidence.md`](docs/successful-deployment-evidence.md) |
| At least two failed deployment investigations | [`docs/failure-scenario-investigations.md`](docs/failure-scenario-investigations.md) |
| Rollback evidence | [`docs/rollback-evidence.md`](docs/rollback-evidence.md) |
| Docker network and volume evidence | [`docs/network-and-volume-evidence.md`](docs/network-and-volume-evidence.md) |
| Jenkins job / Jenkinsfile | [`Jenkinsfile`](Jenkinsfile) |
| Dockerfile | [`Dockerfile`](Dockerfile) |
| Docker Compose file | [`docker-compose.yml`](docker-compose.yml) |
| Application source | [`app/`](app/) |
| Deployment configuration | [`scripts/`](scripts/), [`router/`](router/) |
| Git branch and tag history | see `git log --all --decorate --oneline` and `git tag` in this repo |

## How each phase requirement maps to something concrete here

- **Phase 1 (Investigation):** `docs/incident-root-cause.md` walks through
  every check in the exercise's list against this app's actual symptoms.
- **Phase 2 (Pipeline Repair):** `Jenkinsfile` implements exactly the stage
  list from the exercise, each backed by a script in `scripts/`.
- **Phase 3 (Blue-Green):** `orders-blue`/`orders-green` on ports
  8081/8082, fronted by `orders-router` on 8080; see `scripts/start-candidate.sh`,
  `switch-traffic.sh`, `cleanup-old.sh`, `rollback-candidate.sh`.
- **Phase 4 (Version/Release Management):** `Dockerfile` LABELs +
  `scripts/validate-version.sh` + `scripts/validate-image.sh` +
  `app/server.js`'s `/version` endpoint + `scripts/deployment-verification.sh`'s
  manifest. Tag a release with `git tag -a v7.9 -m "orders-api 7.9"`.
- **Phase 5 (Failure Scenarios):** each `scripts/*.sh` stage comments
  reference the specific numbered scenario(s) it is designed to catch;
  two full worked examples are in `docs/failure-scenario-investigations.md`.
- **Phase 6 (Recovery Requirement):** `scripts/rollback-candidate.sh`
  implements the PASS/FAIL branch from the exercise diagram exactly.
- **Phase 7 (Jenkins Quality):** `disableConcurrentBuilds()`, `set -euo
  pipefail` in every script, `redact_env` for secret-safe logging,
  `scripts/cleanup-images.sh` documents the image retention policy, and
  `post { failure / success / always }` in the Jenkinsfile.
