// asx/tests/spa_test.mjs
// SPA navigation + hot-reload regression suite. Runs the REAL glue.js
// (served by the asx server) against the REAL SSR HTML + REAL wasm modules
// served over HTTP (the server must be running on :3000, like the other
// suites), with a fake DOM that supports what the SPA path touches:
// replaceChild (swapUI), closest("a[href]"), history, location.origin.
//
// Cases:
//   1. boot home -> home widget tree rendered (count: 0)
//   2. click <a href="/about"> -> SPA navigate: DOM swapped to the about
//      module, URL updated, history.pushState called, no full reload
//   3. click <a href="/"> back -> home module mounted again
//   4. popstate (back) -> navigate with replaceState (no duplicate entry)
//   5. hot reload with CHANGED wasm bytes -> new content rendered and
//      NOT reverted (regression: closures must read the NEW module memory)
//   6. hot reload with UNCHANGED bytes -> no-op (no re-render storm)
//
// Usage: node spa_test.mjs [port]
// Exit 0 = all pass. No deps, no DOM lib.
// The glue bundle comes from glue-bundle.mjs (the 7 wasm/glue modules
// concatenated in the same order as the incbins in glue.asm - the
// framework has no generated glue.js file).

import { glueBundle } from "./glue-bundle.mjs";

const [portStr] = process.argv.slice(2);
const PORT = parseInt(portStr || "3000", 10);
const ORIGIN = "http://localhost:" + PORT;
const glue = glueBundle();

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
  get id() { return this.attrs["id"] || null; }
  set id(v) { this.attrs["id"] = String(v); }
  get innerHTML() { return this._innerHTML || ""; }
  set innerHTML(v) {
    this._innerHTML = String(v);
    // parse the fragment into children (SSR paint: navigate() pre-fills
    // the new #ui with the SSR markup so the swap is instant; mount()
    // then hydrates over these nodes by data-asx-id)
    this.children = [];
    parseInto(this, String(v));
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
      asxId: this.attrs["data-asx-id"] || null,
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
  replaceChild(newEl, oldEl) {
    const i = this.children.indexOf(oldEl);
    if (i < 0) throw new Error("replaceChild: old not a child");
    this.children[i] = newEl;
    newEl.parentNode = this;
    oldEl.parentNode = null;
    return oldEl;
  }
  remove() { if (this.parentNode) this.parentNode.removeChild(this); }
  addEventListener(t, fn) { (this.listeners[t] ||= []).push(fn); }
  getBoundingClientRect() { return { left: 0, top: 0, width: 100, height: 100 }; }
  closest(sel) {
    let n = this;
    while (n) {
      if (n.getAttribute) {
        if (sel === "a[href]" && n.tagName === "A" && n.getAttribute("href") !== null) return n;
        if (sel === "[data-asx-role=button]" && n.getAttribute("data-asx-role") === "button") return n;
      }
      n = n.parentNode;
    }
    return null;
  }
  querySelectorAll(sel) { return walk(this, sel); }
  querySelector(sel) {
    if (sel === "canvas") return null;
    return walk(this, sel)[0] || null;
  }
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

// parse an HTML fragment into an existing FakeEl's children (widgets with
// data-asx-id + attrs + text). Used by parseHtml() and by the innerHTML
// setter, which the glue's navigate() relies on for instant SSR paint.
function parseInto(el, src) {
  const stack = [el];
  const tagRe = /<\/(script|style|[a-z][a-z0-9]*)\s*>|<(script|style|[a-z][a-z0-9]*)([^>]*)>/g;
  let m;
  while ((m = tagRe.exec(src))) {
    if (m[1] === "script" || m[1] === "style" || m[2] === "script" || m[2] === "style") continue;
    if (m[1]) { stack.pop(); continue; }
    const tag = m[2], attrs = m[3] || "";
    const n = new FakeEl(tag);
    const idm = attrs.match(/data-asx-id="([0-9]+)"/);
    if (idm) n.setAttribute("data-asx-id", idm[1]);
    const rolem = attrs.match(/data-asx-role="([^"]*)"/);
    if (rolem) n.setAttribute("data-asx-role", rolem[1]);
    const hrefm = attrs.match(/href="([^"]*)"/);
    if (hrefm) n.setAttribute("href", hrefm[1]);
    const tgt = attrs.match(/target="([^"]*)"/);
    if (tgt) n.setAttribute("target", tgt[1]);
    const stm = attrs.match(/style="([^"]*)"/);
    if (stm) n.style.cssText = stm[1];
    const next = src.indexOf("<", tagRe.lastIndex);
    if (next >= 0) {
      const txt = src.slice(tagRe.lastIndex, next);
      if (txt.trim().length > 0) n.textContent = txt;
      tagRe.lastIndex = next;
    }
    stack[stack.length - 1].appendChild(n);
    stack.push(n);
  }
}

// parse SSR HTML into a fake DOM tree (widgets with data-asx-id + attrs).
function parseHtml(src) {
  const root = new FakeEl("div");
  root.attrs["id"] = "ui";
  const attr = (name) => (src.match(new RegExp(name + '="([^"]*)"')) || [])[1] || "";
  root.attrs["data-asx-root"] = attr("data-asx-root");
  root.attrs["data-asx-checksum"] = attr("data-asx-checksum");
  root.attrs["data-modules"] = attr("data-modules") || "/app/page.wasm";
  parseInto(root, src);
  const snapM = src.match(/<script type="application\/asx-state">([^<]*)<\/script>/);
  const snapEl = new FakeEl("script");
  snapEl.attrs["type"] = "application/asx-state";
  snapEl.textContent = snapM ? snapM[1] : "{}";
  document.scripts = [snapEl];
  return root;
}

function findByAttr(root, name, value) {
  let found = null;
  (function rec(n) {
    for (const c of n.children) {
      if (c.getAttribute(name) === value) { found = c; return; }
      if (!found) rec(c);
    }
  })(root);
  return found;
}
function allText(ui) {
  const out = [];
  (function rec(n) {
    for (const c of n.children) {
      if (c.children.length === 0 && c.textContent) out.push(c.textContent);
      rec(c);
    }
  })(ui);
  return out;
}
function hasText(ui, re) { return allText(ui).some((t) => re.test(t)); }

// ------------------------------------------------------------- environment
const errors = [];
const winListeners = {};
const document = {
  body: new FakeEl("body"),
  head: new FakeEl("head"),
  scripts: [],
  getElementById(id) {
    // find the live #ui (swapUI replaces the element in body)
    let found = null;
    (function rec(n) {
      for (const c of n.children) {
        if (c.attrs && c.attrs["id"] === id) { found = c; return; }
        if (!found) rec(c);
      }
    })(document.body);
    return found;
  },
  createElement(tag) { return new FakeEl(tag); },
  querySelector(sel) {
    if (sel === "style[data-asx-base]") return document._styleBase;
    if (sel === "style[data-asx-variants]") return document._styleVar;
    return null;
  },
  querySelectorAll(sel) {
    const ui = document.getElementById("ui");
    return ui ? walk(ui, sel) : [];
  },
};
const location = { pathname: "/", origin: ORIGIN, search: "" };
const history = { entries: [], pushState(s, t, url) { this.entries.push(url); location.pathname = url; }, replaceState(s, t, url) { this.entries[this.entries.length - 1] = url; location.pathname = url; } };
const window = {
  addEventListener(t, fn) { (winListeners[t] ||= []).push(fn); },
  removeEventListener(t, fn) { const a = winListeners[t]; if (a) { const i = a.indexOf(fn); if (i >= 0) a.splice(i, 1); } },
};
let lastEventSource = null;
class FakeEventSource {
  constructor() { lastEventSource = this; this.onopen = null; }
  close() { this.closed = true; }
}
const EventSource = FakeEventSource;

// ---------------------------------------------------------------- HTTP
// Real HTTP to the running server for HTML + wasm (end-to-end), with a
// rebuild switch: after boot, `wasmChanged` makes /app/page.wasm serve the
// about module's bytes (simulating a dev rebuild of the home page).
const realFetch = globalThis.fetch;
let wasmChanged = false;
let wasmDelayMs = 0;   // simulated wasm network latency (SSR-paint test)
let aboutRebuilt = false; // /about serves a DIFFERENT checksum (rebuild sim)
// fetch counters: prove the pageCache makes revisits cheap (no re-fetch)
const fetchLog = [];
const fetchImpl = async (url, opts) => {
  const u = String(url);
  const abs = u.startsWith("http") ? u : ORIGIN + u;
  const pu = new URL(abs);
  fetchLog.push(pu.pathname + pu.search);
  if (u.includes(".wasm")) {
    if (wasmDelayMs > 0) await new Promise((r) => setTimeout(r, wasmDelayMs));
    const src = wasmChanged && pu.pathname === "/app/page.wasm" ? ORIGIN + "/app/about/page.wasm" : abs;
    const bytes = await realFetch(src).then((r) => {
      if (!r.ok) throw new Error("wasm fetch " + src + " -> " + r.status);
      return r.arrayBuffer();
    });
    return new Response(bytes, { headers: { "content-type": "application/wasm" } });
  }
  const r = await realFetch(abs, opts);
  let body = await r.arrayBuffer();
  if (aboutRebuilt && pu.pathname === "/about") {
    // simulate a dev rebuild: same page, DIFFERENT checksum in the SSR shell
    body = Buffer.from(
      Buffer.from(body).toString("utf8").replace(
        /data-asx-checksum="[0-9a-f]+"/,
        'data-asx-checksum="0badc0de"'
      ),
      "utf8"
    );
  }
  return new Response(body, { status: r.status, headers: r.headers });
};
const countFetches = (p) => fetchLog.filter((x) => x.startsWith(p)).length;
const sandbox = {
  document, window, location, history, EventSource,
  TextDecoder, TextEncoder, WebAssembly, console: { error: (...a) => errors.push(a.join(" ")), log: () => {}, warn: () => {}, info: () => {}, debug: () => {} },
  fetch: fetchImpl,
  XMLHttpRequest: class { open() {} setRequestHeader() {} send() {} },
  setInterval, clearInterval, requestAnimationFrame: (fn) => setTimeout(fn, 0),
};

const code = glue.replace(/boot\(\);\s*$/, "return boot();");
const run = new Function(...Object.keys(sandbox), code + "\nreturn {};");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const waitFor = async (fn, ms = 2000) => {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    if (fn()) return true;
    await sleep(20);
  }
  return fn();
};

let ok = 0, total = 0;
const t = (name, pass, detail) => {
  total++;
  console.log((pass ? "PASS" : "FAIL") + "  " + name + (detail ? "  [" + detail + "]" : ""));
  if (pass) ok++;
};

// ------------------------------------------------------------------ tests
// mount the parsed home SSR tree as the live #ui BEFORE boot (the glue's
// getElementById("ui") must find it, else boot() creates a blank one)
const uiHome0 = parseHtml(await realFetch(ORIGIN + "/").then((r) => r.text()));
document.body.appendChild(uiHome0);
document._styleBase = null;
document._styleVar = null;

// boot() runs now - the #ui is already in the document
const bootPromise = run(...Object.values(sandbox));

try {
  await Promise.resolve(bootPromise);
  await waitFor(() => hasText(document.getElementById("ui"), /count:/));

  // 1. boot: home rendered
  const uiHome = document.getElementById("ui");
  t("1 boot home -> home widget tree rendered", uiHome && hasText(uiHome, /count: 0/),
    uiHome ? allText(uiHome).join(" | ") : "no ui");

  // 2. click the /about link -> SPA navigate
  const linkAbout = findByAttr(uiHome, "href", "/about");
  t("2 home has <a href=/about>", !!linkAbout);
  const clicks = uiHome.listeners["click"] || [];
  t("2 nav click listener wired on #ui", clicks.length > 0);
  const navClick = clicks[0];
  const beforeEntries = history.entries.length;
  // make the wasm module "slow" (simulated network): the SSR content must
  // paint immediately after the click, well before the module resolves -
  // this is the no-blank-flash guarantee
  wasmDelayMs = 400;
  navClick({ target: linkAbout, preventDefault() {} });
  const ssrPainted = await waitFor(() =>
    document.getElementById("ui") !== uiHome &&
    hasText(document.getElementById("ui"), /About Page/), 300);
  t("3a first paint is the SSR content (no blank flash while wasm loads)",
    ssrPainted,
    ssrPainted ? "SSR visible before wasm finished" :
      "content: " + allText(document.getElementById("ui")).join(" | "));
  wasmDelayMs = 0;   // let the module fetch complete
  const navOk = await waitFor(() =>
    location.pathname === "/about" &&
    hasText(document.getElementById("ui"), /About Page/)
  );
  t("3 click /about -> SPA navigate swaps DOM + URL",
    navOk && history.entries.length === beforeEntries + 1,
    "url=" + location.pathname + " entries=" + history.entries.length);
  t("3 about content rendered (no full reload)",
    hasText(document.getElementById("ui"), /SPA-navigated/),
    allText(document.getElementById("ui")).join(" | "));
  t("3 home content gone", !hasText(document.getElementById("ui"), /count:/));

  // the about page has a link back to /
  const uiAbout = document.getElementById("ui");
  const linkHome = findByAttr(uiAbout, "href", "/");
  t("4 about has <a href=/>", !!linkHome);
  const aboutClicks = uiAbout ? uiAbout.listeners["click"] || [] : [];
  const aboutNavClick = aboutClicks[0];
  if (aboutNavClick && linkHome) {
    const entriesBeforeBack = history.entries.length;
    aboutNavClick({ target: linkHome, preventDefault() {} });
    const backOk = await waitFor(() =>
      location.pathname === "/" &&
      hasText(document.getElementById("ui"), /count: 0/)
    );
    t("4 click / -> back to home via SPA",
      backOk && history.entries.length === entriesBeforeBack + 1,
      "url=" + location.pathname + " entries=" + history.entries.length);
  } else {
    t("4 click / -> back to home via SPA", false, "about page not mounted");
  }

  // 4b. pageCache: a SECOND visit to /about restores the SAME #ui element.
  // The restore re-validates the checksum with ONE lightweight SSR fetch
  // (never a stale old build), but does NOT re-fetch the wasm, re-instantiate
  // or re-render - the cached module is still the current build.
  const uiAboutRef = uiAbout;                    // element from the first visit
  const aboutWasmFetches = countFetches("/app/about/page.wasm?v=");
  const homeLink = findByAttr(document.getElementById("ui"), "href", "/about");
  const homeClicks = document.getElementById("ui").listeners["click"] || [];
  if (homeClicks[0] && homeLink) {
    homeClicks[0]({ target: homeLink, preventDefault() {} });
    const revisitOk = await waitFor(() =>
      hasText(document.getElementById("ui"), /About Page/) &&
      location.pathname === "/about"
    );
    const uiAbout2 = document.getElementById("ui");
    t("4b revisit /about -> restored from cache (same element, checksum-validated)",
      revisitOk && uiAbout2 === uiAboutRef && countFetches("/app/about/page.wasm?v=") === aboutWasmFetches,
      "same ui=" + (uiAbout2 === uiAboutRef) +
      " wasm fetches=" + (countFetches("/app/about/page.wasm?v=") - aboutWasmFetches));
  } else {
    t("4b revisit /about -> restored from cache", false, "home link/listener missing");
  }

  // 4c. hover prefetch -> click: a NEVER-visited route (/contact) navigates
  // with ZERO network on click. The hover downloads the SSR shell (htmlCache)
  // + the module bytes (wasmBytesCache); the click instantiates from them.
  // We are on /about now; go back home first, hover the /contact link, click.
  const uiAbout4c = document.getElementById("ui");
  const backHomeLink = uiAbout4c ? findByAttr(uiAbout4c, "href", "/") : null;
  const aboutClicks4c = uiAbout4c ? uiAbout4c.listeners["click"] || [] : [];
  if (aboutClicks4c[0] && backHomeLink) {
    aboutClicks4c[0]({ target: backHomeLink, preventDefault() {} });
    await waitFor(() => hasText(document.getElementById("ui"), /count: 0/));
    const uiHome4c = document.getElementById("ui");
    const contactLink = findByAttr(uiHome4c, "href", "/contact");
    const homeClicks4c = uiHome4c.listeners["click"] || [];
    const overCbs = uiHome4c.listeners["pointerover"] || [];
    const htmlBefore = countFetches("/contact");
    const wasmBefore = countFetches("/app/contact/page.wasm");
    if (contactLink && overCbs[0]) {
      // hover: prefetches shell + module bytes
      overCbs[0]({ target: contactLink });
      const hovered = await waitFor(() =>
        countFetches("/app/contact/page.wasm") > wasmBefore, 3000);
      const wasmAfterHover = countFetches("/app/contact/page.wasm");
      const htmlAfterHover = countFetches("/contact");
      t("4c hover prefetch downloads shell + wasm bytes",
        hovered && htmlAfterHover > htmlBefore && wasmAfterHover > wasmBefore,
        "html=" + (htmlAfterHover - htmlBefore) + " wasm=" + (wasmAfterHover - wasmBefore));
      // click: navigate must NOT re-fetch the module for instantiation.
      // A fetch WITH ?v= checksum means the instantiate path fetched it;
      // the hot-reload byte-check (no query) may still run once - that is
      // a legit snapshot, not a module re-download.
      const wasmVAtClick = countFetches("/app/contact/page.wasm?v=");
      homeClicks4c[0]({ target: contactLink, preventDefault() {} });
      const contactOk = await waitFor(() =>
        hasText(document.getElementById("ui"), /Contact Page/) &&
        location.pathname === "/contact"
      );
      t("4c click /contact -> ZERO network (shell+bytes from hover)",
        contactOk && countFetches("/app/contact/page.wasm?v=") === wasmVAtClick,
        "module fetches=" + (countFetches("/app/contact/page.wasm?v=") - wasmVAtClick));
    } else {
      t("4c hover prefetch", false, "contact link/pointerover missing");
      t("4c click /contact -> ZERO network", false, "contact link/pointerover missing");
    }
  } else {
    t("4c hover prefetch", false, "about back link/listener missing");
    t("4c click /contact -> ZERO network", false, "about back link/listener missing");
  }

  // 4d. rebuild invalidation: the pageCache must NEVER show an old layout.
  // Simulate the server rebuilding /about (new data-asx-checksum in the SSR
  // shell) while the old /about is still cached. Clicking /about must NOT
  // restore the stale cached page - it must re-mount from the new build.
  const uiContact4d = document.getElementById("ui");
  const homeLink4d = uiContact4d ? findByAttr(uiContact4d, "href", "/") : null;
  const contactClicks4d = uiContact4d ? uiContact4d.listeners["click"] || [] : [];
  if (contactClicks4d[0] && homeLink4d) {
    contactClicks4d[0]({ target: homeLink4d, preventDefault() {} });
    await waitFor(() => hasText(document.getElementById("ui"), /count: 0/));
    const uiHome4d = document.getElementById("ui");
    const aboutLink4d = findByAttr(uiHome4d, "href", "/about");
    const homeClicks4d = uiHome4d.listeners["click"] || [];
    if (aboutLink4d && homeClicks4d[0]) {
      // "rebuild": /about now serves a shell with a DIFFERENT checksum
      aboutRebuilt = true;
      const wasmBeforeRebuild = countFetches("/app/about/page.wasm?v=");
      homeClicks4d[0]({ target: aboutLink4d, preventDefault() {} });
      // wait for the NEW module fetch (the SSR paint is instant, so the
      // text alone would pass before the re-mount actually fetched the
      // rebuilt module - we must wait for the network evidence)
      const rebuiltOk = await waitFor(() =>
        hasText(document.getElementById("ui"), /About Page/) &&
        location.pathname === "/about" &&
        countFetches("/app/about/page.wasm?v=") > wasmBeforeRebuild, 3000);
      const uiAbout4d = document.getElementById("ui");
      aboutRebuilt = false;
      t("4d rebuilt route -> stale cache dropped, re-mounted fresh",
        rebuiltOk && uiAbout4d !== uiAboutRef &&
        countFetches("/app/about/page.wasm?v=") > wasmBeforeRebuild,
        "new ui=" + (uiAbout4d !== uiAboutRef) +
        " wasm fetches=" + (countFetches("/app/about/page.wasm?v=") - wasmBeforeRebuild));
    } else {
      t("4d rebuilt route -> stale cache dropped", false, "about link missing");
    }
  } else {
    t("4d rebuilt route -> stale cache dropped", false, "contact back link missing");
  }

  // 5. popstate: simulate browser back (URL already changed)
  const popHandlers = winListeners["popstate"] || [];
  t("5 popstate listener registered", popHandlers.length > 0);
  location.pathname = "/about";
  const entriesBeforePop = history.entries.length;
  popHandlers[0]();
  const popOk = await waitFor(() => hasText(document.getElementById("ui"), /About Page/));
  t("5 popstate -> navigate back to /about",
    popOk && history.entries.length === entriesBeforePop,
    "entries before=" + entriesBeforePop + " after=" + history.entries.length + " (replaceState, no new entry)");

  // 6. hot reload with CHANGED bytes -> new content must render (and stay)
  location.pathname = "/";
  const backToHome = await waitFor(() => {
    // navigate home again via the popstate handler (replace)
    return true;
  });
  popHandlers[0]();
  await waitFor(() => hasText(document.getElementById("ui"), /count: 0/));
  t("6 back to home for hot-reload test", hasText(document.getElementById("ui"), /count: 0/));

  // prime snapBytes has settled (wireHotReload fetched /app/page.wasm)
  await sleep(150);
  const es = lastEventSource;
  wasmChanged = true;                    // server "rebuilt": different bytes now
  es.onopen();                           // fires the byte check + hot reload
  const hotOk = await waitFor(() => hasText(document.getElementById("ui"), /About Page/), 3000);
  t("7 hot reload (changed bytes) -> NEW content rendered, not reverted",
    hotOk,
    hotOk ? "about content shown after swap" : "content: " + allText(document.getElementById("ui")).join(" | "));
  t("7 old content gone after hot reload", !hasText(document.getElementById("ui"), /count:/));

  // 8. hot reload with UNCHANGED bytes -> no-op (no errors, content stable).
  // wasmChanged stays true: /app/page.wasm still serves the about bytes, so
  // this onopen re-check sees the same bytes as snapBytes -> no reload.
  const errsBefore = errors.length;
  const textBefore = allText(document.getElementById("ui")).join(" | ");
  es.onopen();
  await sleep(200);
  const textAfter = allText(document.getElementById("ui")).join(" | ");
  const stillAbout = hasText(document.getElementById("ui"), /About Page/);
  t("8 hot reload (unchanged bytes) -> no-op, content stable",
    stillAbout && textBefore === textAfter && errors.length === errsBefore,
    "changed: " + (textBefore !== textAfter) + " errors: " + (errors.length - errsBefore));
} catch (err) {
  t("suite crashed", false, err.message + "\n" + err.stack);
}

console.log("\n" + ok + "/" + total + " SPA cases passed");
process.exit(ok === total ? 0 : 1);
