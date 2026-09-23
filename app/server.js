'use strict';

const http = require('http');
const net = require('net');
const os = require('os');

const PORT = parseInt(process.env.PORT || '3000', 10);
const VERSION = process.env.VERSION || 'unknown';
const GIT_COMMIT = process.env.GIT_COMMIT || 'unknown';
const COLOR = process.env.COLOR || 'unknown';
const DB_HOST = process.env.DB_HOST || 'orders-db';
const DB_PORT = parseInt(process.env.DB_PORT || '5432', 10);
const DB_NAME = process.env.DB_NAME || 'orders';
const REQUIRED_SECRET = process.env.ORDERS_API_SECRET; // required env var used by Phase 5 scenario #31

let ready = false;
// Simulate app warm-up so "container running" and "process actually serving" are
// distinguishable (this is what Phase 1 investigation should catch).
setTimeout(() => { ready = true; }, 1500);

function checkDb(timeoutMs) {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    let done = false;
    const finish = (ok, detail) => {
      if (done) return;
      done = true;
      try { socket.destroy(); } catch (_) {}
      resolve({ ok, detail });
    };
    socket.setTimeout(timeoutMs || 2000);
    socket.once('connect', () => finish(true, `tcp connect to ${DB_HOST}:${DB_PORT} succeeded`));
    socket.once('timeout', () => finish(false, `tcp connect to ${DB_HOST}:${DB_PORT} timed out`));
    socket.once('error', (err) => finish(false, `tcp connect to ${DB_HOST}:${DB_PORT} failed: ${err.code || err.message}`));
    socket.connect(DB_PORT, DB_HOST);
  });
}

function json(res, code, body) {
  const payload = JSON.stringify(body, null, 2);
  res.writeHead(code, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) });
  res.end(payload);
}

const server = http.createServer(async (req, res) => {
  const url = req.url.split('?')[0];

  // Fail fast if a required secret is missing (Phase 5, scenario #31).
  if (!REQUIRED_SECRET) {
    if (url === '/health') return json(res, 503, { status: 'error', reason: 'ORDERS_API_SECRET not set' });
  }

  if (url === '/health') {
    if (!ready) return json(res, 503, { status: 'starting' });
    return json(res, 200, { status: 'ok', color: COLOR, version: VERSION, pid: process.pid, host: os.hostname() });
  }

  if (url === '/version') {
    return json(res, 200, {
      version: VERSION,
      gitCommit: GIT_COMMIT,
      color: COLOR,
      port: PORT,
      host: os.hostname(),
    });
  }

  if (url === '/db-check') {
    const result = await checkDb(2000);
    return json(res, result.ok ? 200 : 500, {
      db: result.ok ? 'reachable' : 'unreachable',
      target: `${DB_HOST}:${DB_PORT}/${DB_NAME}`,
      detail: result.detail,
    });
  }

  if (url === '/') {
    return json(res, 200, {
      service: 'orders-api',
      version: VERSION,
      color: COLOR,
      message: 'orders-api is running. See /health, /version, /db-check.',
    });
  }

  json(res, 404, { error: 'not found' });
});

server.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`orders-api version=${VERSION} commit=${GIT_COMMIT} color=${COLOR} listening on port ${PORT}`);
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  server.close(() => process.exit(0));
});
