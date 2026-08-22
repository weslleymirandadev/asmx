// ---------------------------------------------------------------------------
// SPA navigation state (module-level so boot/navigate/hot-reload share it)
// ---------------------------------------------------------------------------
let live = null;          // { e, mem, syncDOM, els, byId, phase } from mount()
let currentMod = null;    // the wasm module URL currently loaded
let currentPath = null;   // the route currently mounted (differs from
                          // location.pathname during popstate, which the
                          // browser already changed before navigate() runs)
let snapBytes = null;     // bytes for hot-reload byte comparison
let modV = null;          // the cache-busted wasm URL currently loaded
const prefetchCache = new Map();  // wasm paths already pre-fetched (dedup)
const htmlCache = new Map();      // path -> SSR HTML (pre-fetched shells)
const wasmBytesCache = new Map(); // wasm path -> ArrayBuffer (shared by
                                  // hover prefetch and navigate: a hovered
                                  // link's module is instantiated from the
                                  // bytes already downloaded - no re-fetch)
const pageCache = new Map();      // path -> { ui, live, mod, url } (mounted pages)
const PAGE_CACHE_MAX = 20;        // evict oldest beyond this
const dec = new TextDecoder();

// ---------------------------------------------------------------------------
// wasmPathFor(ui) - derive the wasm module URL from a #ui element's
// data-modules attribute (same logic as boot).
// ---------------------------------------------------------------------------
const wasmPathFor = (ui) => {
  const mod = (ui.dataset.modules || "/app.wasm").split(",")[0];
  const hasCk = ui.hasAttribute("data-asx-checksum");
  const url = hasCk ? mod + "?v=" + ui.getAttribute("data-asx-checksum") : mod;
  return { mod, url, hasCk };
};

// ---------------------------------------------------------------------------
// fetch_req - the synchronous XHR import the wasm module calls for
// client->server requests (ROADMAP item 4). The wasm call blocks, so
// async fetch cannot work on the main thread - the event loop would
// never resume. Defined here so boot, navigate, and hot-reload share it.
// ---------------------------------------------------------------------------
const fetch_req = (up, ul, mp, ml, bp, bl) => {
  if (!live) return 0;
  const buf = live.mem();
  const url = location.origin + dec.decode(new Uint8Array(buf, up, ul));
  const method = dec.decode(new Uint8Array(buf, mp, ml));
  const body = bl ? dec.decode(new Uint8Array(buf, bp, bl)) : null;
  const xhr = new XMLHttpRequest();
  xhr.open(method, url, false);
  if (body !== null) xhr.setRequestHeader("Content-Type", "application/json");
  xhr.send(body);
  if (xhr.status >= 200 && xhr.status < 300) {
    const r = new TextEncoder().encode(xhr.responseText);
    const m = live.mem();
    const arr = new Uint8Array(m);
    arr.set(r, 0);
    return r.length;
  }
  return 0;
};
