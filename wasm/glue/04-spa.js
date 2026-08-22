// wireNav(ui) - intercept <a> clicks inside `ui` for SPA navigation.
// Same-origin links only; external/anchor/mailto/tel are left to the browser.
// ---------------------------------------------------------------------------
const wireNav = (ui) => {
  ui.addEventListener("click", (ev) => {
    const a = ev.target.closest("a[href]");
    if (!a) return;
    const href = a.getAttribute("href");
    if (!href || href.startsWith("#") || href.startsWith("mailto:") || href.startsWith("tel:")) return;
    // target=_blank links open a new tab - leave them to the browser
    if (a.target === "_blank") return;
    // external links: let the browser handle them
    if ((href.startsWith("http://") || href.startsWith("https://")) && !href.startsWith(location.origin)) return;
    // resolve to a same-origin pathname
    let path;
    try { path = new URL(href, location.origin).pathname; } catch { return; }
    // skip navigation to the current route
    if (path === location.pathname) return;
    ev.preventDefault();
    navigate(path);
  });
};

// ---------------------------------------------------------------------------
// wirePrefetch(ui) - on link hover (pointerover), warm the caches for the
// target route: fetch its SSR HTML shell (kept in htmlCache) and the wasm
// module it DECLARES (data-modules from the shell, kept in wasmBytesCache).
// The wasm is fetched with a cache-bust (?v=checksum) and NO browser cache
// (no-store): a bare path like /about/page.wasm could be served from the
// browser HTTP cache with STALE bytes from an old build (force-cache never
// revalidates), which is exactly the "jurassic layout" bug - the glue must
// always download the CURRENT module, never trust the HTTP cache.
// ---------------------------------------------------------------------------
const wirePrefetch = (ui) => {
  ui.addEventListener("pointerover", (ev) => {
    const a = ev.target.closest("a[href]");
    if (!a) return;
    const href = a.getAttribute("href");
    if (!href || href.startsWith("#") || href.startsWith("mailto:") || href.startsWith("tel:")) return;
    let path;
    try { path = new URL(href, location.origin).pathname; } catch { return; }
    if (path === location.pathname) return;
    if (prefetchCache.has(path)) return;
    prefetchCache.set(path, true);
    // pre-fetch the SSR HTML shell (navigation will reuse it)
    fetch(path, { cache: "no-store" })
      .then((r) => (r.ok ? r.text() : null))
      .then((h) => {
        if (!h) return;
        htmlCache.set(path, h);
        // pre-fetch the wasm the shell declares, keeping its bytes so
        // navigation instantiates with no extra network round-trip.
        // Cache-bust with the shell's checksum + no-store: always the
        // CURRENT module, never a stale HTTP-cached copy.
        const dm = h.match(/data-modules="([^"]*)"/);
        const ck = h.match(/data-asx-checksum="([0-9a-f]+)"/);
        const wasmPath = dm ? dm[1] : null;
        const wasmUrl = wasmPath ? wasmPath + (ck ? "?v=" + ck[1] : "") : null;
        if (wasmUrl && !wasmBytesCache.has(wasmUrl)) {
          fetch(wasmUrl, { cache: "no-store" })
            .then((r) => (r.ok ? r.arrayBuffer() : null))
            .then((b) => { if (b) wasmBytesCache.set(wasmUrl, b); })
            .catch(() => {});
        }
      })
      .catch(() => {});
  });
};

// ---------------------------------------------------------------------------
// wireHotReload(mod) - EventSource to /_asx/events; each onopen means the
// server (re)started, so re-check the wasm bytes and hot-reload if changed.
// The swap goes through live.state.e (the mutable holder shared with every
// mount() closure) so syncDOM/input handlers read the NEW module's memory.
// A stale EventSource (from a previous page) is ignored: onopen bails when
// the stream's mod differs from the current module or live was torn down.
// ---------------------------------------------------------------------------
let hotEs = null;
const wireHotReload = (mod) => {
  if (hotEs) hotEs.close();
  // prime the byte snapshot
  fetch(mod, { cache: "no-store" })
    .then((r) => r.arrayBuffer())
    .then((b) => { snapBytes = new Uint8Array(b); })
    .catch(() => {});
  hotEs = new EventSource("/_asx/events");
  hotEs.onopen = () => {
    // stale stream from a previous page: ignore
    if (!live || currentMod !== mod) return;
    fetch(mod, { cache: "no-store" })
      .then((r) => r.arrayBuffer())
      .then((b) => {
        const nb = new Uint8Array(b);
        if (snapBytes && (nb.byteLength !== snapBytes.byteLength || nb.some((v, i) => v !== snapBytes[i]))) {
          // the server rebuilt: EVERY cached page may now be stale (its
          // module bytes, SSR shell, or mounted DOM). Drop all caches so
          // the next navigation re-fetches the current build - this is
          // what guarantees a click never shows an old layout while a
          // reload would show the new one.
          snapBytes = nb;
          pageCache.clear();
          htmlCache.clear();
          wasmBytesCache.clear();
          prefetchCache.clear();
          WebAssembly.instantiate(b, { env: { fetch_req } })
            .then(({ instance: nxt }) => {
              // hot reload: swap the shared exports holder + re-sync DOM.
              // All mount() closures read through live.state.e, so the new
              // module's widget tree/memory is what syncDOM renders now.
              live.state.e = nxt.exports;
              if (live.e.init) live.e.init();
              if (live.e.render) live.e.render();
              live.syncDOM();
            })
            .catch(() => {});
        }
      })
      .catch(() => {});
  };
};

// ---------------------------------------------------------------------------
// navigate(path, opts) - SPA: fetch the route's SSR HTML, parse the shell,
// swap the DOM, instantiate the new wasm module, mount, update history.
// opts.replace = true -> history.replaceState (popstate/back-forward);
// otherwise history.pushState (link click).
// ---------------------------------------------------------------------------
let navLock = false;
const navigate = async (path, opts) => {
  if (navLock) return;
  navLock = true;
  try {
    // already showing this page? (currentPath, NOT location.pathname:
    // during popstate the browser already moved location before navigate)
    if (path === currentPath) return;

    // restore a previously mounted page from the cache: the cached #ui is
    // the SAME element (listeners wireNav/wirePrefetch persist on it), and
    // the cached live keeps the wasm instance + DOM state - so revisiting
    // a page costs no re-instantiate, no re-render. BUT the cache must be
    // validated: if the server rebuilt since we cached it (the asx dev
    // recompiles on every save), the cached module would render an OLD
    // layout. Re-fetch the SSR shell (lightweight) and compare its
    // data-asx-checksum against the one the cached module was built with
    // (baked into cached.url as ?v=). Checksums match -> restore instantly;
    // they differ -> drop the stale entry and re-mount fresh below.
    const cached = pageCache.get(path);
    if (cached) {
      let stale = false;
      try {
        const r = await fetch(path, { cache: "no-store" });
        if (r.ok) {
          const html = await r.text();
          const ck = html.match(/data-asx-checksum="([0-9a-f]+)"/);
          const cachedCk = (cached.url || "").match(/[?&]v=([0-9a-f]+)/);
          stale = !ck || !cachedCk || ck[1] !== cachedCk[1];
        }
      } catch { stale = true; }
      if (!stale) {
        if (live) { if (live.stop) live.stop(); live = null; }
        swapUI(cached.ui);
        live = cached.live;
        currentMod = cached.mod;
        modV = cached.url;
        currentPath = path;
        snapBytes = null;
        if (live.start) live.start();       // resume the canvas loop if any
        wireHotReload(cached.mod);          // point the SSE at this page's module
        if (history.pushState) {
          const st = { path: path };
          if (opts && opts.replace) history.replaceState(st, "", path);
          else history.pushState(st, "", path);
        }
        return;
      }
      // stale: the server rebuilt this page - drop the cache entry AND the
      // pre-fetched shell/bytes (they belong to the same old build), then
      // fall through to the normal first-visit flow (fresh SSR + module)
      pageCache.delete(path);
      htmlCache.delete(path);
      wasmBytesCache.clear();
    }
    {
      // first visit: use the pre-fetched shell if hover already got it
      const r = htmlCache.has(path)
        ? { ok: true, text: async () => htmlCache.get(path) }
        : await fetch(path, { cache: "no-store" });
      if (!r.ok) { console.error("ASX Navigate: "+path+" -> "+(r.status||"cached")); return; }
      const html = await r.text();
      const shell = parseShell(html);
      if (!shell) { console.error("ASX Navigate: no #ui shell in "+path); return; }

    // cleanup old module: stop canvas loop + remove old event listeners +
    // close old EventSource so stale handlers don't write to the DOM.
    // The old ui is detached by swapUI below; its animation loop (if any)
    // would keep calling syncDOM on detached elements, and window-level
    // listeners would fire on the old e/syncDOM closure.
    if (live) {
      if (live.stop) live.stop();
      live = null;
    }

    // build the new #ui element and pre-fill it with the SSR content that
    // the server already sent. This makes the swap paint INSTANTLY (the
    // route's real HTML appears immediately, no blank flash while the wasm
    // downloads/instantiates). mount() then hydrates over it (phase SSR ->
    // HYDRATING): syncDOM reuses the SSR nodes by data-asx-id, so the wasm
    // is the source of truth and the SSR markup is reconciled away. The old
    // cache-latente revert bug was a stale-closure issue (fixed via the
    // mutable state.e holder) - not caused by pre-filling innerHTML.
    const newUi = document.createElement("div");
    newUi.id = "ui";
    newUi.style.cssText = "position:relative;width:100%;max-width:720px;margin:0 auto";
    if (shell.innerHTML) newUi.innerHTML = shell.innerHTML;

    // copy attributes from the SSR shell to the new #ui element
    // (data-asx-root, data-asx-checksum, data-modules, etc.)
    if (shell.uiAttrs) {
      // regex fallback path: uiAttrs is a raw attribute string
      const attrRe = /([a-zA-Z][a-zA-Z0-9-]*)="([^"]*)"/g;
      let m;
      while ((m = attrRe.exec(shell.uiAttrs))) newUi.setAttribute(m[1], m[2]);
    } else if (shell.doc) {
      // DOMParser path: copy attributes from the parsed <ui> element
      const parsedUi = shell.doc.getElementById("ui");
      if (parsedUi) {
        for (const attr of parsedUi.attributes) newUi.setAttribute(attr.name, attr.value);
      }
    }

    // swap the DOM
    swapUI(newUi);

    // copy over <style data-asx-base> and <style data-asx-variants> from the
    // parsed doc head into the live head (replace existing ones). Guard for
    // the regex fallback path where shell.doc is unavailable.
    if (shell.doc) {
      const liveBase = document.querySelector("style[data-asx-base]");
      if (liveBase) liveBase.remove();
      const newBase = shell.doc.querySelector("style[data-asx-base]");
      if (newBase) document.head.appendChild(newBase);
      const liveVar = document.querySelector("style[data-asx-variants]");
      if (liveVar) liveVar.remove();
      const newVar = shell.doc.querySelector("style[data-asx-variants]");
      if (newVar) document.head.appendChild(newVar);
    }

    // instantiate + mount the new module. If the hover prefetch already
    // downloaded this module's bytes, instantiate from them (no re-fetch);
    // otherwise fetch. The cache key is the CACHE-BUSTED url (?v=checksum):
    // when the server rebuilds the checksum changes, so a stale entry can
    // never be hit - no "old layout on click, new layout on reload" bugs.
    const { mod, url, hasCk } = wasmPathFor(newUi);
    modV = url;
    currentMod = mod;
    currentPath = path;
    let bytes = wasmBytesCache.get(url);
    if (!bytes) {
      const r = await fetch(url, hasCk ? {} : { cache: "no-store" });
      if (!r.ok) { console.error("ASX Navigate: module "+url+" -> "+r.status); return; }
      bytes = await r.arrayBuffer();
      wasmBytesCache.set(url, bytes);
    }
    const { instance } = await WebAssembly.instantiate(bytes, { env: { fetch_req } });
    live = mount(instance, newUi, shell.snap);
    snapBytes = null;

    // keep the mounted page so a later visit restores it instantly
    pageCache.set(path, { ui: newUi, live, mod, url });
    if (pageCache.size > PAGE_CACHE_MAX) pageCache.delete(pageCache.keys().next().value);

    // re-wire SPA nav + prefetch + hot reload on the new ui
    wireNav(newUi);
    wirePrefetch(newUi);
    wireHotReload(mod);
    }

    // update browser history: link click pushes, back/forward replaces
    if (history.pushState) {
      const st = { path: path };
      if (opts && opts.replace) history.replaceState(st, "", path);
      else history.pushState(st, "", path);
    }
  } catch (err) {
    console.error("ASX Navigate: " + err.message);
  } finally {
    navLock = false;
  }
};

// ---------------------------------------------------------------------------
