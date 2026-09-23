# Git → Jenkins → Docker Flow

A short walkthrough of what happens end-to-end for one deployment.

1. **Git.** A change is merged/pushed to the deploy branch. Every commit
   that reaches production has an immutable SHA — this is the only value
   ever used to prove what code is running (never "whatever main happened
   to be at the time").

2. **Checkout stage.** Jenkins checks out that exact commit and records
   `GIT_COMMIT_SHA` and `GIT_BRANCH_NAME` as build metadata. This is the
   first link in the traceability chain required by Phase 4.

3. **Validate Version stage.** The pipeline requires an explicit,
   human-supplied `APP_VERSION` build parameter (e.g. `7.9`). Versions must
   match `<major>.<minor>[.<patch>]`; `latest` is explicitly rejected as a
   production identifier.

4. **Unit/Application Test stage.** `node app/test.js` boots the app
   in-process against a closed DB port and asserts `/version`, `/health`,
   and `/db-check` all behave correctly — catching regressions in the
   app's own logic before anything is containerized.

5. **Docker Build stage.** `docker build --build-arg VERSION=<v> --build-arg
   GIT_COMMIT=<sha>` bakes both values into OCI image labels and into the
   container's environment at `ENV`. The image is tagged **twice**:
   `orders-api:<version>-<short-sha>` (the immutable, unambiguous tag that
   is actually deployed) and `orders-api:<version>` (a human-friendly
   alias). `latest` is never produced or used.

6. **Docker Image Validation stage.** Before the image is ever run, its
   labels are read back and compared against the expected version/commit —
   this is what would catch a stale or mis-tagged image (Phase 5 #36)
   before it ever becomes a running container.

7. **Start Candidate stage.** The pipeline asks the router which color is
   currently live, computes the *other* color as the candidate, and starts
   it with `docker run` on the shared `orders-network`, publishing it on
   its own dedicated host port (8081 or 8082) — **not** port 8080. The
   currently-live color is not touched.

8. **Container Validation, Application Health Check, Integration Check.**
   Three independent, increasingly strict checks: is the container even
   running; does its `/health` endpoint return 200; can it actually reach
   `orders-db` and does `/version` echo back the exact version/commit that
   was built. Any failure here stops the pipeline and triggers rollback —
   production traffic has not moved yet, so users are never affected.

9. **Traffic Switch stage.** Only once all three checks pass does the
   pipeline rewrite `router/active-backend.conf` to point nginx's upstream
   at the candidate and reload nginx (`nginx -s reload`, zero-downtime).
   It then re-verifies `/version` **through the router's own port 8080** —
   the same path a real user takes — before declaring the switch done.

10. **Old Version Cleanup stage.** Only now, with the new color proven live
    on port 8080, is the previous color's container stopped and removed.
    Old, unused images are pruned according to the documented retention
    policy (keep the current version + last 3 previous versions).

11. **Deployment Verification stage.** A final round-trip through the
    router confirms the active color, confirms the old container is
    actually gone, and writes a JSON deployment manifest (version, commit,
    color, timestamp, live `/version` and `/health` responses) archived as
    a Jenkins build artifact — the durable evidence trail back to the exact
    Git commit.

12. **Failure at any stage before Traffic Switch** runs
    `rollback-candidate.sh` from the pipeline's `post { failure { ... } }`
    block: the failed candidate is removed, its logs are captured, and the
    script re-confirms the original color is still serving traffic on port
    8080 before the build is allowed to finish failing.

The net effect: a green Jenkins build is only possible if every step above
succeeded in order, which is what makes "Jenkins says SUCCESS" actually
mean "users can reach the new version" — the exact guarantee that was
missing during the original incident.
