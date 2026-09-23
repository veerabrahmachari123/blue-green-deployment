'use strict';
// Minimal smoke/unit test for the pipeline's "Unit/Application Test" stage.
// Spawns the server on an ephemeral port with test env vars and checks
// that /version and /health behave correctly. No external test framework
// so the pipeline has zero dependency-install surface.

const { spawn } = require('child_process');
const http = require('http');
const path = require('path');

function get(port, urlPath) {
  return new Promise((resolve, reject) => {
    const req = http.get({ host: '127.0.0.1', port, path: urlPath, timeout: 3000 }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(data) });
        } catch (e) {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
  });
}

async function main() {
  const port = 4009;
  const child = spawn(process.execPath, [path.join(__dirname, 'server.js')], {
    env: {
      ...process.env,
      PORT: String(port),
      VERSION: 'test',
      GIT_COMMIT: 'testsha',
      COLOR: 'test',
      ORDERS_API_SECRET: 'test-secret',
      DB_HOST: '127.0.0.1',
      DB_PORT: '1', // intentionally closed -> exercises the /db-check failure path
    },
  });

  let failed = false;
  try {
    await new Promise((r) => setTimeout(r, 2000)); // let it warm up

    const version = await get(port, '/version');
    if (version.status !== 200 || version.body.version !== 'test') {
      console.error('FAIL: /version did not return expected payload', version);
      failed = true;
    } else {
      console.log('PASS: /version returned expected payload');
    }

    const health = await get(port, '/health');
    if (health.status !== 200 || health.body.status !== 'ok') {
      console.error('FAIL: /health did not report ok', health);
      failed = true;
    } else {
      console.log('PASS: /health reports ok after warm-up');
    }

    const db = await get(port, '/db-check');
    if (db.status !== 500 || db.body.db !== 'unreachable') {
      console.error('FAIL: /db-check should report unreachable against closed port', db);
      failed = true;
    } else {
      console.log('PASS: /db-check correctly detects an unreachable database');
    }
  } catch (err) {
    console.error('FAIL: unexpected error during tests:', err.message);
    failed = true;
  } finally {
    child.kill('SIGTERM');
  }

  process.exit(failed ? 1 : 0);
}

main();
