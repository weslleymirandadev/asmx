// Build-error overlay (Next.js style).
// Polls /_asx/error (the dev loop writes build/asx-error.txt on a failed
// build). When it returns 200, mounts the framework-internal
// error-overlay module (compiled from asx/ui/error-overlay.asx) into a fixed
// full-screen container on top of the page and fills in the error text.
// When it returns 404, removes the overlay.
// ---------------------------------------------------------------------------
let errorOverlayLive = null;   // the overlay's mount() handle (or null)
let errorHost = null;          // the fixed full-screen container
let savedBodyBg = null;        // the page's body background (restored on remove)
let savedBodyColor = null;

const refreshErrorOverlay = async () => {
  let has = false;
  let text = "";
  try {
    const r = await fetch("/_asx/error", { cache: "no-store" });
    if (r.ok) { has = true; text = await r.text(); }
  } catch { has = false; }

  if (!has) {
    if (errorHost) {
      if (errorOverlayLive && errorOverlayLive.stop) errorOverlayLive.stop();
      errorHost.remove();
      errorHost = null;
      errorOverlayLive = null;
      if (savedBodyBg !== null) { document.body.style.background = savedBodyBg; savedBodyBg = null; }
      if (savedBodyColor !== null) { document.body.style.color = savedBodyColor; savedBodyColor = null; }
    }
    return;
  }

  // strip ANSI color escapes from the error text (the ui-compile writes
  // \x1b[...m codes for the terminal; the browser overlay shows plain text)
  const clean = text.replace(/\x1b\[[0-9;]*m/g, "");

  if (!errorHost) {
    errorHost = document.createElement("div");
    errorHost.id = "asx-error-overlay";
    errorHost.style.cssText =
      "position:fixed;inset:0;z-index:9999;background:rgba(0,0,0,.72);" +
      "backdrop-filter:blur(6px);display:flex;align-items:center;" +
      "justify-content:center;padding:32px;overflow:auto;";
    document.body.appendChild(errorHost);

    const ui = document.createElement("div");
    ui.id = "asx-error-ui";
    ui.style.cssText = "position:relative;width:100%;max-width:720px;margin:0 auto;" +
      "background:#09090b;border:1px solid rgba(239,68,68,.35);border-radius:16px;" +
      "box-shadow:0 24px 64px rgba(0,0,0,.6);";
    errorHost.appendChild(ui);

    // fetch + instantiate the overlay module, then mount it into the ui
    // element with the REAL mount() (full syncDOM: styles, text, layout)
    try {
      const r = await fetch("/_asx/error-overlay.wasm", { cache: "no-store" });
      if (!r.ok) { errorHost.remove(); errorHost = null; return; }
      const bytes = await r.arrayBuffer();
      const { instance } = await WebAssembly.instantiate(bytes, { env: { fetch_req } });
      // mount() repaints the body with the overlay theme; save + restore
      savedBodyBg = document.body.style.background;
      savedBodyColor = document.body.style.color;
      errorOverlayLive = mount(instance, ui, {});
      // fill the error text: replace the ASX_ERROR_TEXT marker node.
      // Only LEAF nodes: a parent's textContent concatenates its children,
      // so <main> would also match (and destroy the h1/p subtree).
      for (const el of ui.querySelectorAll("[data-asx-id]")) {
        if (!el.children.length && el.textContent && el.textContent.includes("ASX_ERROR_TEXT")) {
          el.textContent = clean;
          el.style.whiteSpace = "pre-wrap";
          el.style.wordBreak = "break-word";
          break;
        }
      }
    } catch (err) {
      if (errorHost) { errorHost.remove(); errorHost = null; }
    }
  } else {
    // overlay already mounted: just refresh the text
    for (const el of errorHost.querySelectorAll("[data-asx-id]")) {
      if (!el.children.length && el.textContent && el.textContent.includes("ASX_ERROR_TEXT")) {
        el.textContent = clean;
        break;
      }
    }
  }
};

// ---------------------------------------------------------------------------
