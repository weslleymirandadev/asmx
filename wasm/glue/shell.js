// parseShell(html) - extract the #ui div + inline script data + styles
// from a full SSR HTML page. Returns { uiAttrs, innerHTML, snap, doc } or
// null. Uses DOMParser for robust extraction; falls back to regex if
// DOMParser is unavailable.
// ---------------------------------------------------------------------------
const parseShell = (html) => {
  try {
    const doc = new DOMParser().parseFromString(html, "text/html");
    const ui = doc.getElementById("ui");
    if (!ui) return null;
    const snapEl = doc.querySelector('script[type="application/asx-state"]');
    let snap = {};
    if (snapEl) {
      try { snap = JSON.parse(snapEl.textContent || "{}"); } catch { snap = {}; }
    }
    return { uiAttrs: null, innerHTML: ui.innerHTML, snap, doc };
  } catch {
    // fallback: regex extraction if DOMParser unavailable
    // greedy match finds the LAST </div> before the snapshot script (the
    // #ui closing tag), correctly capturing inner widget trees that also
    // contain </div> tags
    const uiMatch = html.match(/<div id="ui"([^>]*)>([\s\S]*)<\/div>\s*<script type="application\/asx-state">/);
    if (!uiMatch) return null;
    const attrStr = uiMatch[1];
    const innerHTML = uiMatch[2];
    const snapMatch = html.match(/<script type="application\/asx-state">([^<]*)<\/script>/);
    const snap = snapMatch ? (() => { try { return JSON.parse(snapMatch[1] || "{}"); } catch { return {}; } })() : {};
    return { uiAttrs: attrStr, innerHTML, snap };
  }
};

// ---------------------------------------------------------------------------
// swapUI(newUi) - replace the current #ui with `newUi` in the document,
// then move all <style> and <script type="application/asx-state"> from the
// new shell's <head> into the live document (base css, variants, snapshot).
// ---------------------------------------------------------------------------
const swapUI = (newUi) => {
  const oldUi = document.getElementById("ui");
  if (oldUi && oldUi.parentNode) {
    oldUi.parentNode.replaceChild(newUi, oldUi);
  } else {
    document.body.appendChild(newUi);
  }
};

// ---------------------------------------------------------------------------
