# Docker Network and Volume Evidence

## Network

`orders-network` is a single bridge network shared by the router, both
app colors, and the database, created once by `docker-compose.yml`:

```
$ docker network inspect orders-network --format '{{.Name}} {{.Driver}} {{.Scope}}'
orders-network bridge local

$ docker network inspect orders-network --format '{{range .Containers}}{{.Name}} {{end}}'
orders-router orders-db orders-blue
```

After a promotion the member list shifts to the new color, e.g.
`orders-router orders-db orders-green` — the old color is removed from the
network as a side effect of `docker rm` in `cleanup-old.sh`.

Each app container resolves the database purely by container/service name
(`DB_HOST=orders-db`), never by IP — this is what `container-validation.sh`
and `integration-check.sh` exercise, and what scenario #30 (wrong DB
hostname) is designed to break.

## Volumes

Only the database needs durable storage. `docker-compose.yml` declares a
named volume so `orders-db`'s data survives container recreation
independently of any blue-green cycle:

```
$ docker volume inspect orders-api_orders-db-data --format '{{.Name}} {{.Driver}} {{.Mountpoint}}'
orders-api_orders-db-data local /var/lib/docker/volumes/orders-api_orders-db-data/_data
```

Application containers (`orders-blue` / `orders-green`) are intentionally
stateless — no volumes are mounted into them, so removing an old color
during cleanup never risks data loss. This is also why the database is
never restarted as part of a deployment, matching the incident's
observation that "the database container is still running" the whole time.
