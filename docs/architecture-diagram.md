# Final Architecture

```mermaid
flowchart TB
    subgraph Git["Git Repository"]
        GH["orders-api repo<br/>branches + release tags"]
    end

    subgraph CI["Jenkins"]
        JF["Jenkinsfile pipeline<br/>Checkout -> Validate -> Test -> Build -><br/>Image Validation -> Start Candidate -><br/>Container Validation -> Health Check -><br/>Integration Check -> Traffic Switch -><br/>Old Version Cleanup -> Verification"]
    end

    subgraph Host["Docker Host"]
        subgraph Net["orders-network (bridge)"]
            R["orders-router (nginx)<br/>host port 8080<br/>active-backend.conf"]
            B["orders-blue<br/>orders-api:VERSION-SHA<br/>host port 8081"]
            G["orders-green<br/>orders-api:VERSION-SHA<br/>host port 8082"]
            DB[("orders-db<br/>postgres")]
        end
    end

    U["User / client"] -->|"HTTP :8080"| R
    R -->|"active color only"| B
    R -.->|"candidate, direct-tested<br/>before switch"| G
    B --> DB
    G --> DB

    GH -->|"webhook / poll"| JF
    JF -->|"docker build --build-arg VERSION,GIT_COMMIT"| Host
    JF -->|"docker run candidate"| G
    JF -->|"health + integration checks"| G
    JF -->|"rewrite conf + nginx -s reload"| R
    JF -->|"stop/rm old color after verified switch"| B
```

## Notes

- **orders-router** is the only container that ever binds host port 8080.
  It is what makes the switch atomic from the user's point of view: the
  candidate is fully tested on its own port (8081/8082) before the router
  is ever pointed at it.
- **Only one of blue/green is "active"** at a time; the inactive slot is
  either idle (nothing running) or holds a candidate under test.
- **orders-db** is shared by both colors and is never restarted as part of
  a deployment — this matches the incident's observation that "the database
  container is still running" throughout.
- Version identity flows one direction only: **Git commit → image label →
  container env → `/version` HTTP response → deployment manifest**, so any
  running container can always be traced back to the exact commit that
  produced it (Phase 4).
