// asx/tests/fuzz_http.mjs
// Black-box fuzz of the HTTP parser (ROADMAP item 5). afl++ cannot
// instrument pure NASM (no compiler pass to hook), so the equivalent is
// socket fuzzing against the live server: throw malformed requests at it
// and verify the accept loop survives (fork-per-connection: a crashed
// child must never take the parent down - the health check proves it).
//
// Usage: node tests/fuzz_http.mjs [iterations] [host] [port]
// Exit 0 = server survived N malformed requests + health checks passed.

import net from "node:net";

const N = parseInt(process.argv[2] || "500", 10);
const HOST = process.argv[3] || "localhost";
const PORT = parseInt(process.argv[4] || "3000", 10);

// deterministic PRNG so failures are reproducible
let seed = 0x5eed1234;
const rnd = () => {
  seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  return seed / 0x7fffffff;
};

const pick = (arr) => arr[Math.floor(rnd() * arr.length)];

// structured malformed inputs (targeted at request_line/header_parse/json)
const badLines = [
  "", "\r\n", "\n", " ", "GARBAGE NOT HTTP\r\n\r\n",
  "GET\r\n\r\n", "GET  /  HTTP/1.1", "GET / HTTP/9.9\r\n\r\n",
  "GET / HTTP/1.1", "GET /\r\n\r\n", "GET / HTTP/1.1\r\n",
  "POST /api/hello HTTP/1.1\r\nContent-Length: -5\r\n\r\n",
  "POST /api/hello HTTP/1.1\r\nContent-Length: 99999999999999999999\r\n\r\n",
  "GET / HTTP/1.1\r\nHost:\r\n\r\n", "GET / HTTP/1.1\r\nHost\r\n\r\n",
  "GET / HTTP/1.1\r\n: value\r\n\r\n", "GET / HTTP/1.1\r\nX-: y\r\n\r\n",
  "GET / HTTP/1.1\r\nContent-Length: abc\r\n\r\n",
  "GET / HTTP/1.1\r\nContent-Length: 5\r\n\r\nabc",  // truncated body
  "GET / HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 5\r\n\r\n",
  "GET / HTTP/1.1\r\n\r\nGET /about HTTP/1.1\r\n\r\n", // pipelining
  "GET /%00 HTTP/1.1\r\n\r\n", "GET /\x7f HTTP/1.1\r\n\r\n",
  "GET / HTTP/1.1\r\nCookie: a=b; c=d;;;\r\n\r\n",
];
const badBodies = [
  "{", "}", "[]", "null", '"unterminated', '{"a":}', '{"a":1,}',
  "{\"a\":1}{\"b\":2}", "[1,2,", "{\"a\":\"\\x\"}", "\x00\x01\x02",
];
const methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS",
  "GeT", "get", "FOO", "A".repeat(7000), "POSTPOST", "GET / HTTP/1.1\r\nX"];
const paths = ["/", "/about", "/api/hello", "/profile/joao", "/x".repeat(8000),
  "/%2e%2e/", "/a b", "/a\tb", "/\x01\x02", "/missing", "/admin/about"];

function genPayload() {
  const kind = Math.floor(rnd() * 4);
  if (kind === 0) {
    // pure random bytes (up to 2KB)
    const len = Math.floor(rnd() * 2048);
    const b = Buffer.alloc(len);
    for (let i = 0; i < len; i++) b[i] = Math.floor(rnd() * 256);
    return b;
  }
  if (kind === 1) {
    const method = pick(methods);
    const path = pick(paths);
    let req = `${method} ${path} HTTP/1.1\r\nHost: ${HOST}:${PORT}\r\n`;
    if (rnd() > 0.5) req += `X-Fuzz: ${"y".repeat(Math.floor(rnd() * 500))}\r\n`;
    if (rnd() > 0.7) req += `Content-Length: ${Math.floor(rnd() * 100)}\r\n`;
    return Buffer.from(req + "\r\n", "latin1");
  }
  if (kind === 2) {
    // POST with malformed JSON body
    const body = Buffer.from(pick(badBodies), "latin1");
    return Buffer.concat([
      Buffer.from(`POST /api/hello HTTP/1.1\r\nHost: ${HOST}\r\nContent-Type: application/json\r\nContent-Length: ${body.length}\r\n\r\n`, "latin1"),
      body,
    ]);
  }
  // structured bad input
  return Buffer.from(pick(badLines), "latin1");
}

function oneShot(payload) {
  return new Promise((resolve) => {
    const s = net.connect(PORT, HOST);
    s.setTimeout(2000, () => { s.destroy(); resolve(0); });
    s.on("connect", () => { try { s.write(payload); } catch {} });
    s.on("data", () => { s.destroy(); resolve(1); });
    s.on("error", () => { s.destroy(); resolve(0); });
    s.on("close", () => resolve(0));
  });
}

function healthCheck() {
  return new Promise((resolve) => {
    const s = net.connect(PORT, HOST);
    s.setTimeout(2000, () => { s.destroy(); resolve(false); });
    s.on("connect", () => {
      s.write("GET / HTTP/1.1\r\nHost: " + HOST + "\r\n\r\n");
    });
    let buf = "";
    s.on("data", (d) => {
      buf += d.toString("latin1");
      if (buf.includes("200 OK")) { s.destroy(); resolve(true); }
      else if (buf.length > 512) { s.destroy(); resolve(false); }
    });
    s.on("error", () => resolve(false));
    s.on("close", () => resolve(buf.includes("200 OK")));
  });
}

const start = Date.now();
let responded = 0;
for (let i = 0; i < N; i++) {
  responded += await oneShot(genPayload());
  if (i % 100 === 99) {
    const alive = await healthCheck();
    if (!alive) {
      console.log(`FAIL: server died at iteration ${i + 1}`);
      process.exit(1);
    }
  }
}
const alive = await healthCheck();
const ms = Date.now() - start;
console.log(`fuzz: ${N} requests in ${ms}ms (${Math.round((N / ms) * 1000)}/s), ${responded} got a response`);
console.log(alive ? "PASS: server survived + health check OK" : "FAIL: health check failed");
process.exit(alive ? 0 : 1);
