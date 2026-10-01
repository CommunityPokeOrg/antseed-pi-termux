#!/usr/bin/env node
// Minimal stand-in for the AntSeed buyer proxy used by tests.
//   GET  /v1/models              -> {} (readiness probe)
//   GET  /_antseed/peers         -> fixture JSON
//   POST /_antseed/peers/refresh -> { ok: true }
// Prints "PORT <n>" on stdout once listening.
import http from 'node:http';
import { readFileSync } from 'node:fs';

const fixture = process.env.STUB_PEERS_FILE || new URL('./fixtures/peers.json', import.meta.url).pathname;
const peers = readFileSync(fixture, 'utf8');

const server = http.createServer((req, res) => {
    const send = (status, body) => {
        res.writeHead(status, { 'content-type': 'application/json' });
        res.end(typeof body === 'string' ? body : JSON.stringify(body));
    };
    if (req.method === 'GET' && req.url === '/v1/models') return send(200, { data: [] });
    if (req.method === 'GET' && req.url === '/_antseed/peers') return send(200, peers);
    if (req.method === 'POST' && req.url === '/_antseed/peers/refresh') return send(200, { ok: true, total: 1 });
    send(404, { error: 'not found' });
});

server.listen(0, '127.0.0.1', () => {
    console.log(`PORT ${server.address().port}`);
});
