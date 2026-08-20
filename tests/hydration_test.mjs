// asx/tests/hydration_test.mjs
// Hydration test suite (ROADMAP item 5): runs the REAL glue.js (served by
// the asx server) against the REAL SSR HTML with a minimal fake DOM, and
// exercises the divergence cases documented in the README (SSR+hydration):
//   1. base: clean SSR -> no hydration errors, nodes reused
//   2. text mismatch -> logged + fixed (phase HYDRATING)
//   3. style divergence -> re-applied (attribute differs)
//   4. missing node -> re-created
//   5. extra node (id >= widget_count) -> removed (SSR leftovers)
//   6. tag type divergence -> structural mismatch logged + re-created
//   7. checksum mismatch -> "ASX Hydration Error" with both hashes
//   8. root absent -> CSR fallback (fresh #ui, no data-asx-root)
//   9. snapshot ssr.state -> restored BEFORE first render (count: 42)
//
// Usage: node tests/hydration_test.mjs <html-file> <glue-file> <wasm-file>
// Exit 0 = all pass. No deps, no DOM lib - the fake DOM implements exactly
// what the glue touches (element.style.cssText, setAttribute, appendChild,
// remove, closest, querySelectorAll("[data-asx-id]"), scripts, EventSource).

import { readFileSync } from "node:fs";

const [htmlPath, gluePath, wasmPath] = process.argv.slice(2);
if (!htmlPath || !gluePath || !wasmPath) {
  console.error("usage: node hydration_test.mjs <html> <glue.js> <index.wasm>");
  process.exit(2);
}
const html = readFileSync(htmlPath, "utf8");
const glue = readFileSync(gluePath, "utf8");
const wasmBytes = readFileSync(wasmPath);

// ---------------------------------------------------------------- fake DOM
class FakeStyle {
  constructor() { this._css = ""; }
  set cssText(v) { this._css = v; }
  get cssText() { return this._css; }
}
class FakeEl {
  constructor(tag) {
    this.tagName = tag.toUpperCase();
    this.attrs = {};
    this.style = new FakeStyle();
    this.textContent = "";
    this.parentNode = null;
    this.children = [];
    this.listeners = {};
  }
  setAttribute(k, v) { this.attrs[k] = String(v); }
  getAttribute(k) { return k in this.attrs ? this.attrs[k] : null; }
  hasAttribute(k) { return k in this.attrs; }
  removeAttribute(k) { delete this.attrs[k]; }
  get type() { return this.attrs["type"] || ""; }
  get dataset() {
    return {
      modules: this.attrs["data-modules"] || null,
      asxRoot: this.attrs["data-asx-root"] || null,
      asxChecksum: this.attrs["data-asx-checksum"] || null,
    };
  }
  appendChild(el) {
    if (el.parentNode) el.parentNode.removeChild(el);
    el.parentNode = this;
    this.children.push(el);
    return el;
  }
  removeChild(el) {
    const i = this.children.indexOf(el);
    if (i >= 0) this.children.splice(i, 1);
    el.parentNode = null;
    return el;
  }
  remove() { if (this.parentNode) this.parentNode.removeChild(this); }
  addEventListener(t, fn) { (this.listeners[t] ||= []).push(fn); }
  closest(sel) {
    // only "[data-asx-role=button]" is used by the glue
    let n = this;
    while (n) {
      if (n.getAttribute && n.getAttribute("data-asx-role") === "button") return n;
      n = n.parentNode;
    }
    return null;
  }
  querySelectorAll(sel) { return walk(this, sel); }
}
function walk(root, sel) {
  const out = [];
  (function rec(n) {
    for (const c of n.children) {
      if (sel === "[data-asx-id]" && c.getAttribute("data-asx-id") !== null) out.push(c);
      rec(c);
    }
  })(root);
  return out;
}

// parse the SSR HTML into a fake DOM tree (divs/spans with data-asx-id).
// The SSR output has newlines between tags - a regex with `([^<]*)<` would
// swallow the "<" of a child tag, so scan manually: locate each tag, read
// the text between ">" and the next "<" (only non-whitespace counts).
function parseHtml(src) {
  const root = new FakeEl("div");
  root.attrs["id"] = "ui";
  root.attrs["data-asx-root"] = (src.match(/data-asx-root="([^"]*)"/) || [])[1] || "";
  root.attrs["data-asx-checksum"] = (src.match(/data-asx-checksum="([^"]*)"/) || [])[1] || "";
  root.attrs["data-modules"] = (src.match(/data-modules="([^"]*)"/) || [])[1] || "/index.wasm";
  const stack = [root];
  const tagRe = /<\/(div|span|button)\s*>|<(div|span|button)([^>]*)>/g;
  let m;
  while ((m = tagRe.exec(src))) {
    if (m[1]) { stack.pop(); continue; }       // closing tag
    const tag = m[2], attrs = m[3] || "";
    const el = new FakeEl(tag);
    const idm = attrs.match(/data-asx-id="([0-9]+)"/);
    if (idm) el.setAttribute("data-asx-id", idm[1]);
    const rolem = attrs.match(/data-asx-role="([^"]*)"/);
    if (rolem) el.setAttribute("data-asx-role", rolem[1]);
    const stm = attrs.match(/style="([^"]*)"/);
    if (stm) el.style.cssText = stm[1];
    // text = chars between this ">" and the next "<"
    const next = src.indexOf("<", tagRe.lastIndex);
    if (next >= 0) {
      const txt = src.slice(tagRe.lastIndex, next);
      if (txt.trim().length > 0) el.textContent = txt;
      tagRe.lastIndex = next;
    }
    stack[stack.length - 1].appendChild(el);
    stack.push(el);
  }
  // snapshot script
  const snapM = src.match(/<script type="application\/asx-state">([^<]*)<\/script>/);
  const snapEl = new FakeEl("script");
  snapEl.attrs["type"] = "application/asx-state";
  snapEl.textContent = snapM ? snapM[1] : "{}";
  document.scripts = [snapEl];
  return root;
}

// ------------------------------------------------------------- environment
const errors = [];
const document = {
  body: new FakeEl("body"),
  head: new FakeEl("head"),
  scripts: [],
  styleBase: null,
  getElementById(id) { return id === "ui" ? this.ui : null; },
  createElement(tag) { return new FakeEl(tag); },
  querySelector(sel) {
    if (sel === "style[data-asx-base]") return this.styleBase;
    return null;
  },
  querySelectorAll(sel) {
    const out = [];
    (function rec(n) {
      for (const c of n.children) {
        if (sel === "[data-asx-id]" && c.getAttribute("data-asx-id") !== null) out.push(c);
        rec(c);
      }
    })(this.ui);
    return out;
  },
};
const window = { addEventListener() {} };
const location = { pathname: "/" };
class FakeEventSource { constructor() { this.onopen = null; } }
const EventSource = FakeEventSource;

function runCase(name, mutate, expectError) {
  const errs = [];
  document.ui = parseHtml(html);
  document.styleBase = null;
  document.head = new FakeEl("head");
  if (mutate) mutate(document.ui);

  const mod = (document.ui.dataset.modules || "/app.wasm").split(",")[0];
  const fetchImpl = async (url) => {
    if (url.includes(".wasm")) {
      return new Response(wasmBytes, { headers: { "content-type": "application/wasm" } });
    }
    return new Response("", { status: 404 });
  };
  const fakeConsole = {
    error: (...a) => errs.push(a.join(" ")),
    log: () => {}, warn: () => {}, info: () => {}, debug: () => {},
  };
  const sandbox = {
    document, window, location, EventSource,
    TextDecoder, TextEncoder, WebAssembly, console: fakeConsole,
    fetch: fetchImpl,
    XMLHttpRequest: class { open() {} send() {} },
    setInterval, clearInterval, requestAnimationFrame: (fn) => setTimeout(fn, 0),
  };
  // the glue's boot() is async; run it with the sandbox globals and
  // RETURN the boot promise so the assertion awaits the full hydration
  const code = glue.replace(/boot\(\);/, "return boot();");
  const run = new Function(...Object.keys(sandbox), code + "\nreturn {};");
  const p = run(...Object.values(sandbox));
  // boot() is async - await its completion before asserting
  return Promise.resolve(p).then(() => {
    const pass = expectError ? errs.length > 0 : errs.length === 0;
    const detail = errs.length ? errs[0].replace(/^ASX Hydration Error: /, "") : "clean";
    console.log((pass ? "PASS" : "FAIL") + "  " + name + "  [" + detail + "]");
    if (!pass) {
      console.log("      got " + errs.length + " error(s), expected " + (expectError ? ">=1" : "0"));
    }
    return pass;
  });
}

// ------------------------------------------------------------------ tests
// NOTE: the cases share the global fake `document` (parseHtml resets
// document.ui/scripts per case), so they MUST run serially - Promise.all
// would let case 9 overwrite the snapshot while others are mid-boot.
let ok = 0, total = 0;
let chain = Promise.resolve();
const t = (name, mutate, expectError) => {
  total++;
  chain = chain.then(() => runCase(name, mutate, expectError)).then((p) => { if (p) ok++; });
};

t("1 base: clean SSR hydrates with no errors", null, false);
t("2 text mismatch -> logged + fixed", (ui) => {
  const s = ui.querySelectorAll("[data-asx-id]").find((e) => e.getAttribute("data-asx-id") === "5");
  if (s) s.textContent = "WRONG TEXT";
}, true);
t("3 style divergence -> re-applied", (ui) => {
  const s = ui.querySelectorAll("[data-asx-id]").find((e) => e.getAttribute("data-asx-id") === "0");
  if (s) s.style.cssText = "position:absolute;left:9999px;";
}, false);
t("4 missing leaf node -> re-created (diagnosed)", (ui) => {
  const s = ui.querySelectorAll("[data-asx-id]").find((e) => e.getAttribute("data-asx-id") === "5");
  if (s) s.remove();
}, true);
t("5 extra node (id>=count) -> removed", (ui) => {
  const d = document.createElement("div");
  d.setAttribute("data-asx-id", "99");
  ui.appendChild(d);
}, false);
t("6 tag divergence -> structural mismatch", (ui) => {
  // pick a real text node (SPAN) - the fixture layout differs from the
  // example app, so do not hardcode an id
  const s = ui.querySelectorAll("[data-asx-id]").find((e) => e.tagName === "SPAN");
  if (s) { s.tagName = "DIV"; s.style.cssText = ""; }
}, true);
t("7 checksum mismatch -> ASX Hydration Error", (ui) => {
  ui.setAttribute("data-asx-checksum", "deadbeef");
}, true);
t("8 root absent -> CSR fallback", (ui) => {
  ui.removeAttribute("data-asx-root");
}, false);

// case 9: snapshot ssr.state restored before first render. The home
// carries {"root":"index"} (initial values live in the module) - inject a
// snapshot with count:42 and verify the count widget text becomes "42"
// (the {count} interpolation renders the restored state).
total++;
chain = chain.then(() => runCase("9 snapshot ssr.state restored before render", (ui) => {
  const snapEl = document.createElement("script");
  snapEl.setAttribute("type", "application/asx-state");
  snapEl.textContent = '{"root":"index","count":42}';
  document.scripts = [snapEl];
  // the SSR HTML shows the initial value (0) - the snapshot restore (42)
  // is expected to diverge and be fixed (diagnosed), exactly the
  // ssr.state flow: server injects value -> glue restores -> first paint
  ui.setAttribute("data-asx-checksum", "ffffffff");
}, true)).then((p) => {
  if (p) {
    // find the count widget (the "{count}" interpolation node) and check
    // its text - the fixture renders "count: {count}" -> "count: 42"
    const countNode = document.ui.querySelectorAll("[data-asx-id]").find((e) => {
      return e.textContent && e.textContent.includes("42");
    });
    if (countNode && /count: 42/.test(countNode.textContent)) {
      console.log("PASS  9 snapshot ssr.state restored before render  [count widget shows \"count: 42\"]");
      ok++;
    } else {
      console.log("FAIL  9 snapshot ssr.state restored before render  [count widget = " +
        (countNode ? JSON.stringify(countNode.textContent) : "not found") + "]");
    }
  }
});

chain.then(() => {
  console.log("\n" + ok + "/" + total + " hydration cases passed");
  process.exit(ok === total ? 0 : 1);
});
