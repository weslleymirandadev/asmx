// boot - initial page load
// ---------------------------------------------------------------------------
const boot = async () => {
  const ui = document.getElementById("ui") || (() => { const d = document.createElement("div"); d.id = "ui"; document.body.appendChild(d); return d; })();
  ui.style.cssText = "position:relative;width:100%;max-width:720px;margin:0 auto";
  const { mod, url, hasCk } = wasmPathFor(ui);
  currentMod = mod;
  currentPath = location.pathname || "/";
  modV = url;

  const { instance } = await WebAssembly.instantiateStreaming(
    fetch(url, hasCk ? {} : { cache: "no-store" }),
    { env: { fetch_req } }
  );
  const snap = (() => {
    let s = null;
    for (const sc of document.scripts) {
      if (sc.type === "application/asx-state") { s = sc; break; }
    }
    try { return s ? JSON.parse(s.textContent) : {}; } catch (err) { return {}; }
  })();

  live = mount(instance, ui, snap);

  // wire SPA navigation + pre-fetch + hot reload on the initial page
  wireNav(ui);
  wirePrefetch(ui);
  wireHotReload(mod);

  // keep the initial page in the cache so back-navigation restores it
  // (same element, same instance - no re-mount)
  pageCache.set(location.pathname || "/", { ui, live, mod, url });

  // build-error overlay: show/hide based on /_asx/error
  refreshErrorOverlay();
  // poll every 1.5s while the dev server is running (the SSE reconnect
  // also triggers a check, but a failed build never restarts the server,
  // so the EventSource stays open and would miss the error appearing)
  setInterval(refreshErrorOverlay, 1500);

  // one global keyboard handler - dispatches through the current `live`
  // so cached/restored pages keep working without duplicate listeners
  window.addEventListener("keydown", (ev) => {
    if (!live || !live.e.handle_event) return;
    live.e.handle_event(2, -1, 0, 0, ev.keyCode || ev.which);
    if (live.e.ui_dirty && live.e.ui_dirty()) { live.e.render(); live.syncDOM(); }
  });

  // back/forward - the URL already changed, so replace (no new entry)
  window.addEventListener("popstate", () => {
    navigate(location.pathname + (location.search || ""), { replace: true });
  });
};
boot();
