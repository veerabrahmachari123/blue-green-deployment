# orders-api image
# Built with immutable identity baked in via build ARGs -> LABELs + ENV,
# so every running container can prove which version/commit it is (Phase 4).

FROM node:20-alpine

ARG VERSION
ARG GIT_COMMIT
# Fail the build early if identity args were not supplied — an image without
# a real version/commit must never be produced (Phase 4 requirement).
RUN test -n "$VERSION" || (echo "ERROR: --build-arg VERSION is required" && exit 1)
RUN test -n "$GIT_COMMIT" || (echo "ERROR: --build-arg GIT_COMMIT is required" && exit 1)

LABEL org.opencontainers.image.title="orders-api" \
      org.opencontainers.image.version="$VERSION" \
      org.opencontainers.image.revision="$GIT_COMMIT" \
      org.opencontainers.image.source="https://example.com/orders-api"

ENV VERSION=$VERSION \
    GIT_COMMIT=$GIT_COMMIT \
    PORT=3000 \
    NODE_ENV=production

WORKDIR /app
COPY app/ .

EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD node healthcheck.js

USER node
CMD ["node", "server.js"]
