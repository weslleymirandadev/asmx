const boot = async () => {
  const ui = document.getElementById("ui") || (() => { const d = document.createElement("div"); d.id = "ui"; document.body.appendChild(d); return d; })();
  ui.style.cssText = "position:relative;width:100%;max-width:720px;margin:0 auto";
  const mod = (ui.dataset.modules || "/app.wasm").split(",")[0];
  // cache-bust the module with the SSR checksum (?v=<checksum>): the
  // wasm URL changes whenever the page changes, so a stale cached
  // module can never hydrate over a newer SSR shell (transitions/
  // classes/checksum would silently diverge). CSR (no checksum) =
  // no-store fetch like the hot-reload path.
  const hasCk = ui.hasAttribute("data-asx-checksum");
  const modV = hasCk ? mod + "?v=" + ui.getAttribute("data-asx-checksum") : mod;
  // RPC (ROADMAP item 4): the wasm module imports env.fetch_req. The
  // glue runs a SYNCHRONOUS XHR (the wasm call blocks, so async fetch
  // cannot work on the main thread - the event loop would never
  // resume) and writes the response body into the module memory at
  // resp_area(), setting resp_len.value. Returns the HTTP status.
  // The wasm side owns when/what: it passes url/method/body pointers
  // and reads the response buffer afterwards.
  const fetch_req = (up, ul, mp, ml, bp, bl) => {
    const buf = mem();
    const url = location.origin + dec.decode(new Uint8Array(buf, up, ul));
    const method = dec.decode(new Uint8Array(buf, mp, ml));
    const body = bl ? dec.decode(new Uint8Array(buf, bp, bl)) : null;
    const xhr = new XMLHttpRequest();
    xhr.open(method, url, false);
    if (body !== null) xhr.setRequestHeader("Content-Type", "application/json");
    xhr.send(body);
    const txt = xhr.responseText || "";
    const enc = new TextEncoder().encode(txt);
    const cap = (e.resp_cap && e.resp_cap()) || 4096;
    const n = Math.min(enc.length, cap);
    const dst = e.resp_area ? e.resp_area() : 0;
    new Uint8Array(mem()).set(enc.subarray(0, n), dst);
    if (e.resp_len) e.resp_len.value = n;
    return xhr.status || 0;
  };
  const { instance } = await WebAssembly.instantiateStreaming(fetch(modV, hasCk ? {} : { cache: "no-store" }), { env: { fetch_req } });
  let e = instance.exports;
  const mem = () => e.memory.buffer;
  const dec = new TextDecoder();
  // ---- SSR + hydration (phase machine: SSR -> HYDRATING -> INTERACTIVE) ----
  // SSR: the DOM came from the server (data-asx-root on #ui). The glue
  // assumes that DOM, validates it and connects behavior - it does NOT
  // rebuild the page. HYDRATING: first sync reusing the SSR nodes.
  // INTERACTIVE: normal reactive rendering may start.
  let phase = ui.hasAttribute("data-asx-root") ? "SSR" : "CSR";
  // hydration snapshot: minimal render state produced by the SSR pass
  // (<script type="application/asx-state">). Restored BEFORE the first
  // render so the first paint is exactly what the server produced.
  const snap = (() => { let s = null; for (const sc of document.scripts) { if (sc.type === "application/asx-state") { s = sc; break; } } try { return s ? JSON.parse(s.textContent) : {}; } catch (err) { return {}; } })();
  // every snapshot key (except "root") maps to a set_<name> export
  // (declarative states) or set_count (legacy): ssr.state values
  // injected by the server are restored before the first render
  for (const k in snap) { if (k === "root") continue; const fn = e["set_" + k]; if (typeof fn === "function") fn(snap[k]); }
  // dynamic route slug: "/profile/joao" -> "joao" (last path
  // segment). Written into the wasm memory (slug_area) so the
  // module can read it; "{slug}" in any text is replaced below.
  const slug = location.pathname.split("/").filter(Boolean).pop() || "";
  if (e.slug_area) { const sa = e.slug_area(); const b = new TextEncoder().encode(slug); new Uint8Array(mem()).set(b, sa); new Uint8Array(mem())[sa + b.length] = 0; }
  const hex = (v) => "#" + ((v>>16)&255).toString(16).padStart(2,"0") + ((v>>8)&255).toString(16).padStart(2,"0") + (v&255).toString(16).padStart(2,"0");
  // the SSR shell already carries the base css (style[data-asx-base]
  // with reset + theme) so the first paint is the final layout -
  // only inject our copy when rendering client-side (no SSR shell)
  if (!document.querySelector("style[data-asx-base]")) {
    const st = document.createElement("style");
    st.setAttribute("data-asx-base", "");
    st.textContent = "*{margin:0;padding:0;box-sizing:border-box}button{border:none;background:none;font:inherit}body{min-height:100vh;font-family:ui-sans-serif,system-ui,sans-serif;padding:48px 24px}";
    document.head.appendChild(st);
  }
  if (e.ui_theme_bg) document.body.style.background = hex(e.ui_theme_bg());
  if (e.ui_theme_text) document.body.style.color = hex(e.ui_theme_text());
  const els = [];
  // map the SSR DOM by data-asx-id (stable compiler-generated ids).
  // hydration REUSES these nodes - no structural DOM change unless a
  // node is missing or its tag type diverges (partial re-render).
  const byId = new Map();
  for (const el of ui.querySelectorAll("[data-asx-id]")) byId.set(el.getAttribute("data-asx-id"), el);
  // real HTML tag per widget: index = record byte 1 (tag id from
  // the tags table in ui/tables.inc - keep in sync!). id 0 = div.
  const TAG_NAMES = ["div","main","div","section","nav","header","footer","article","aside","figure","blockquote","ul","ol","li","form","table","thead","tbody","tfoot","tr","td","th","details","dialog","video","audio","picture","iframe","canvas","select","textarea","fieldset","dl","dt","dd","menu","hgroup","h1","h2","h3","h4","h5","h6","p","span","a","label","strong","em","code","pre","small","b","i","u","mark","time","cite","q","abbr","sub","sup","kbd","samp","var","del","ins","s","option","figcaption","legend","caption","summary","button","img","input","br","hr","source","meta","link","area","base","col","embed","track","wbr"];
  const tagFor = (type, tagId) => tagId ? (TAG_NAMES[tagId] || "DIV").toUpperCase() : (type === 1 ? "SPAN" : type === 2 ? "CANVAS" : "DIV");
  // html attributes from the record (bytes 26..29 = absolute address
  // of a name="value" ... string; 0 = none). Applied on creation
  // so CSR nodes carry the same attributes as the SSR ones.
  const applyAttrs = (el, o, v) => {
    const ap = v.getUint32(o+26, true);
    if (!ap) return;
    let s = "", p = ap; while (v.getUint8(p) !== 0) s += String.fromCharCode(v.getUint8(p++));
    const re = /([a-zA-Z][a-zA-Z0-9-]*)="([^"]*)"/g; let m;
    while ((m = re.exec(s))) { try { el.setAttribute(m[1], m[2]); } catch (e) {} }
  };
  // flexbox layout: views are flex containers, texts flow
  // inside them. x/y from the module are the fallback size.
  const syncDOM = () => {
    const buf = mem(), v = new DataView(buf);
    const n = e.widget_count(), base = e.widgets();
    const stBase = e.styles ? e.styles() : 0;
    const TPROP = ["","","none","all","color,background-color,border-color,outline-color,text-decoration-color,fill,stroke,--tw-gradient-from,--tw-gradient-via,--tw-gradient-to","opacity","box-shadow","transform,translate,scale,rotate"];
    const TEASE = ["","linear","cubic-bezier(0.4,0,1,1)","cubic-bezier(0,0,0.2,1)","cubic-bezier(0.4,0,0.2,1)"];
    const STRETCH = ["","ultra-condensed","extra-condensed","condensed","semi-condensed","normal","semi-expanded","expanded","extra-expanded","ultra-expanded"];
    const VARNUM = ["","normal","ordinal","slashed-zero","lining-nums","oldstyle-nums","proportional-nums","tabular-nums","diagonal-fractions","stacked-fractions"];
    const TRACK = ["","-0.05em","-0.025em","0em","0.025em","0.05em","0.1em"];
    const LEAD = ["","1","1.25","1.375","1.5","1.625","2","0.75rem","1rem","1.25rem","1.5rem","1.75rem","2rem","2.25rem","2.5rem"];
    const WS = ["","normal","nowrap","pre","pre-line","pre-wrap","break-spaces"];
    const WB = ["","normal","break-word","break-all","keep-all"];
    const OW = ["","","","","","normal","break-word","anywhere"];
    const VALIGN = ["","normal","top","middle","bottom","text-top","text-bottom","sub","super"];
    const DSTYLE = ["","solid","double","dotted","dashed","wavy"];
    const TW = ["","wrap","nowrap","balance","pretty"];
    const HYPHENS = ["","none","manual","auto"];
    const ANIM = ["","spin 1s linear infinite","ping 1s cubic-bezier(0,0,0.2,1) infinite","pulse 2s cubic-bezier(0.4,0,0.6,1) infinite","bounce 1s infinite"];
    const FAM = ["","ui-sans-serif,system-ui,sans-serif,\"Apple Color Emoji\",\"Segoe UI Emoji\",\"Segoe UI Symbol\",\"Noto Color Emoji\"","ui-serif,Georgia,Cambria,\"Times New Roman\",Times,serif","ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,\"Liberation Mono\",\"Courier New\",monospace"];
    for (let i = 0; i < n; i++) {
      const o = base + i*32;
      const type = v.getUint8(o);
      const tagId = v.getUint8(o+1);
      const w = v.getInt16(o+6,true), h = v.getInt16(o+8,true);
      const r = v.getUint8(o+12), g = v.getUint8(o+13), b = v.getUint8(o+14);
      const parent = v.getInt32(o+20,true);
      let el = els[i];
      if (!el) el = byId.get(String(i)) || null;
      const want = tagFor(type, tagId);
      if (!el || el.tagName !== want) {
        if (el) console.error("ASX Hydration Error: node " + i + " structural mismatch expected <" + want.toLowerCase() + "> got <" + el.tagName.toLowerCase() + "> (re-created, subtree client-rendered)");
        el = document.createElement(want.toLowerCase());
        el.setAttribute("data-asx-id", String(i));
        byId.set(String(i), el);
        applyAttrs(el, o, v);
      }
      els[i] = el;
      const so = stBase + i*64;
      const flags = stBase ? v.getUint32(so,true) : 0;
      const weight = stBase ? v.getUint16(so+4,true) : 0;
      const align = stBase ? v.getUint8(so+6) : 0;
      const gap = stBase ? v.getUint8(so+7) : 0;
      const radius = stBase ? v.getUint8(so+8) : 0;
      const px = stBase ? v.getUint8(so+9) : 0;
      const py = stBase ? v.getUint8(so+10) : 0;
      const border = stBase ? v.getUint8(so+11) : 0;
      const opacity = stBase ? v.getUint8(so+12) : 0;
      const shadow = stBase ? v.getUint8(so+13) : 0;
      const role = stBase ? v.getUint8(so+14) : 0;
      const pad = stBase ? v.getUint8(so+15) : 0;
      const mt = stBase ? v.getUint8(so+16) : 0;
      const mb = stBase ? v.getUint8(so+17) : 0;
      const hh = stBase ? v.getUint8(so+18) : 0;
      const gcols = stBase ? v.getUint8(so+19) : 0;
      const ml = stBase ? v.getUint8(so+20) : 0;
      const mr = stBase ? v.getUint8(so+21) : 0;
      const pl = stBase ? v.getUint8(so+22) : 0;
      const pr = stBase ? v.getUint8(so+23) : 0;
      const pt = stBase ? v.getUint8(so+24) : 0;
      const pb = stBase ? v.getUint8(so+25) : 0;
      const trans = stBase ? v.getUint8(so+26) : 0;
      const ease = stBase ? v.getUint8(so+27) : 0;
      const dur = stBase ? v.getUint16(so+28,true) : 0;
      const delay = stBase ? v.getUint16(so+30,true) : 0;
      const anim = stBase ? v.getUint8(so+32) : 0;
      const tbehav = stBase ? v.getUint8(so+33) : 0;
      const family = stBase ? v.getUint8(so+34) : 0;
      const stretch = stBase ? v.getUint8(so+35) : 0;
      const varnum = stBase ? v.getUint8(so+36) : 0;
      const tracking = stBase ? v.getUint8(so+37) : 0;
      const lead = stBase ? v.getUint8(so+38) : 0;
      const wss = stBase ? v.getUint8(so+39) : 0;
      const wbr = stBase ? v.getUint8(so+40) : 0;
      const overflow = stBase ? v.getUint8(so+41) : 0;
      const valign = stBase ? v.getUint8(so+42) : 0;
      const indent = stBase ? v.getUint8(so+43) : 0;
      const dstyle = stBase ? v.getUint8(so+44) : 0;
      const dthick = stBase ? v.getUint8(so+45) : 0;
      const dcolor = stBase ? v.getUint32(so+46,true) : 0xFFFFFFFF;
      const uo2 = stBase ? v.getUint8(so+50) : 0;
      const clamp = stBase ? v.getUint8(so+51) : 0;
      const lsp = stBase ? v.getUint8(so+52) : 0;
      const lst = stBase ? v.getUint8(so+53) : 0;
      const hyphens = stBase ? v.getUint8(so+54) : 0;
      const tabsize = stBase ? v.getUint8(so+55) : 0;
      const content = stBase ? v.getUint8(so+56) : 0;
      const textwrap = stBase ? v.getUint8(so+57) : 0;
      const smooth = stBase ? v.getUint8(so+58) : 0;
      const bg = type === 0 && !(r === 0 && g === 0 && b === 0 && v.getUint8(o+15) === 0) ? "background:" + hex((r<<16)|(g<<8)|b) + ";" : "";
      const rad = radius === 255 ? "border-radius:9999px;" : (radius ? "border-radius:" + radius + "px;" : "");
      const bd = border ? "border:" + border + "px solid rgba(255,255,255,.2);" : "";
      const op = opacity ? "opacity:" + (opacity/100) + ";" : "";
      const sh = shadow ? "box-shadow:0 8px 24px rgba(0,0,0,.35);" : "";
      const tr = trans === 2 ? "transition-property:none;" : (trans ? "transition-property:" + TPROP[trans] + ";transition-duration:" + (dur || 150) + "ms;transition-timing-function:" + (TEASE[ease] || "cubic-bezier(0.4,0,0.2,1)") + ";" + (delay ? "transition-delay:" + delay + "ms;" : "") : "");
      const tbh = tbehav === 2 ? "transition-behavior:allow-discrete;" : tbehav ? "transition-behavior:normal;" : "";
      const ls = (lsp === 2 ? "list-style-position:outside;" : lsp ? "list-style-position:inside;" : "") + (lst === 2 ? "list-style-type:disc;" : lst === 3 ? "list-style-type:decimal;" : lst ? "list-style-type:none;" : "");
      const anv = anim ? "animation:" + ANIM[anim] + ";" : "";
      const padCss = (pl||pr||pt||pb) ? "padding:" + (pt||py||pad) + "px " + (pr||px||pad) + "px " + (pb||py||pad) + "px " + (pl||px||pad) + "px;" : ((px||pad) ? "padding:" + (py||pad) + "px " + (px||pad) + "px;" : "");
      const gapCss = gap ? "gap:" + gap + "px;" : "";
      const mg = (ml||mr) ? "margin:" + mt + "px " + mr + "px " + mb + "px " + ml + "px;" : ((mt||mb) ? "margin:" + mt + "px 0 " + mb + "px;" : "");
      const flexDir = (flags & 1) ? ((flags & 2) ? "column" : "row") : "column";
      const items = (flags & 4) ? "center" : (flags & 8) ? "flex-end" : (flags & 4194304) ? "flex-start" : "stretch";
      const just = (flags & 16) ? "center" : (flags & 32) ? "space-between" : (flags & 64) ? "flex-end" : (flags & 131072) ? "space-around" : (flags & 262144) ? "space-evenly" : "flex-start";
      if (type === 1) {
        const fs = v.getUint8(o+24) || 13;
        const col = "color:" + hex((r<<16)|(g<<8)|b) + ";";
        const fam = family ? "font-family:" + FAM[family] + ";" : "";
        const str = stretch ? "font-stretch:" + STRETCH[stretch] + ";" : "";
        const vn = varnum ? "font-variant-numeric:" + VARNUM[varnum] + ";" : "";
        const sm = smooth === 2 ? "-webkit-font-smoothing:auto;" : smooth ? "-webkit-font-smoothing:antialiased;" : "";
        const fw = weight ? "font-weight:" + weight + ";" : "";
        const trk = tracking ? "letter-spacing:" + TRACK[tracking] + ";" : "";
        const ta = align === 1 ? "text-align:center;" : align === 2 ? "text-align:right;" : align === 3 ? "text-align:justify;" : align === 4 ? "text-align:start;" : align === 5 ? "text-align:end;" : "";
        const tt = (flags & 8192) ? "text-transform:uppercase;" : (flags & 1048576) ? "text-transform:lowercase;" : (flags & 134217728) ? "text-transform:capitalize;" : (flags & 16777216) ? "text-transform:none;" : "";
        const it = (flags & 16384) ? "font-style:italic;" : (flags & 8388608) ? "font-style:normal;" : "";
        const un = (flags & 32768) ? "text-decoration:underline;" : (flags & 2097152) ? "text-decoration:line-through;" : (flags & 67108864) ? "text-decoration-line:overline;" : (flags & 33554432) ? "text-decoration-line:none;" : "";
        const dcl = dcolor !== 0xFFFFFFFF ? "text-decoration-color:" + hex(dcolor) + ";" : "";
        const dst = dstyle ? "text-decoration-style:" + DSTYLE[dstyle] + ";" : "";
        const dth = dthick === 1 ? "text-decoration-thickness:auto;" : dthick === 2 ? "text-decoration-thickness:from-font;" : dthick ? "text-decoration-thickness:" + (dthick-2) + "px;" : "";
        const uo = uo2 === 1 ? "text-underline-offset:auto;" : uo2 ? "text-underline-offset:" + uo2 + "px;" : "";
        const mgL = (ml||mr) ? "margin:" + mt + "px " + mr + "px " + mb + "px " + ml + "px;" : ((mt||mb) ? "margin:" + mt + "px 0 " + mb + "px;" : "");
        const ws = wss ? "white-space:" + WS[wss] + ";" : "";
        const wb = (wbr === 2 || wbr >= 5) ? "overflow-wrap:" + OW[wbr] + ";" : wbr ? "word-break:" + WB[wbr] + ";" : "";
        const ov = overflow === 3 ? "overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" : overflow ? "text-overflow:" + (overflow === 2 ? "clip" : "ellipsis") + ";" : "";
        const tw = textwrap ? "text-wrap:" + TW[textwrap] + ";" : "";
        const va = valign ? "vertical-align:" + VALIGN[valign] + ";" : "";
        const ind = indent ? "text-indent:" + indent + "px;" : "";
        const hy = hyphens ? "hyphens:" + HYPHENS[hyphens] + ";" : "";
        const tab = tabsize ? "tab-size:" + tabsize + ";" : "";
        const cl = clamp ? "-webkit-line-clamp:" + clamp + ";overflow:hidden;" : "";
        const cont = content ? "content:none;" : "";
        const an = anim ? "animation:" + ANIM[anim] + ";" : "";
        const lh = lead ? "line-height:" + LEAD[lead] + ";" : "line-height:1.4;";
        const disp = clamp ? "display:-webkit-box;-webkit-box-orient:vertical;font-size:" : "display:block;font-size:";
        const css = disp + fs + "px;" + col + fam + str + vn + sm + fw + trk + ta + tt + it + un + dcl + dst + dth + uo + mgL + ws + wb + ov + tw + va + ind + hy + tab + cl + cont + tr + an + lh;
        if (el.style.cssText !== css) el.style.cssText = css;
        const tp = v.getUint32(o+16,true);
        let end = tp; while (v.getUint8(end) !== 0) end++;
        let txt = dec.decode(new Uint8Array(buf, tp, end-tp));
        if (txt.includes("{slug}")) txt = txt.split("{slug}").join(slug);
        if (el.textContent !== txt) {
          if (phase === "HYDRATING" && !el.textContent.includes("{slug}")) console.error("ASX Hydration Error: node " + i + " text mismatch server=" + JSON.stringify(el.textContent) + " client=" + JSON.stringify(txt) + " (fixed)");
          el.textContent = txt;
        }
      } else if (type === 2) {
        const css = "display:block;width:" + w + "px;height:" + h + "px;border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,.4);";
        if (el.style.cssText !== css) el.style.cssText = css;
      } else {
        // buttons (role 1) shrink to fit their label and
        // get a pointer cursor; plain views stretch 100%
        const ww = (w && w < 720) ? "width:" + w + "px;" : (role === 1 ? "width:auto;align-self:flex-start;cursor:pointer;" : "width:100%;min-width:0;");
        const hid = (flags & 128) ? "display:none;" : "";
        const grd = (flags & 65536) ? "position:relative;display:grid;" + (gcols ? "grid-template-columns:repeat(" + gcols + ",1fr);" : "") : "";
        const wrp = (flags & 256) ? "flex-wrap:wrap;" : "";
        const grw = (flags & 512) ? "flex:1 1 0%;" : "";
        const rest = bg + padCss + gapCss + mg + rad + bd + op + sh + tr + tbh + ww + ls + anv;
        const css = hid ? "display:none;" : (grd ? grd + rest : "position:relative;display:flex;flex-direction:" + flexDir + ";" + wrp + grw + "align-items:" + items + ";justify-content:" + just + ";" + rest);
        if (el.style.cssText !== css) el.style.cssText = css;
        if (hh) { if (el.style.minHeight !== hh + "px") el.style.minHeight = hh + "px"; }
      }
      // buttons carry data-asx-role="button" (SSR emits it; CSR sets
      // it here) so the click handler can resolve the target with
      // ev.target.closest instead of scanning every widget rect
      if (role === 1) el.setAttribute("data-asx-role", "button");
      const pe = (parent >= 0 && els[parent]) ? els[parent] : ui;
      if (el.parentNode !== pe) pe.appendChild(el);
    }
    // SSR leftovers: nodes the module no longer produces are removed
    for (const [id, el] of byId) { const k = parseInt(id, 10); if (k >= n && el.parentNode) el.remove(); }
    for (let i = n; i < els.length; i++) { if (els[i]) { els[i].remove(); els[i] = null; } }
  };
  if (e.init) e.init();
  if (e.render) e.render();
  if (phase === "SSR") phase = "HYDRATING";
  // checksum: the server embeds data-asx-checksum = FNV-1a over the
  // canonical IR (records + strings). The module recomputes the same
  // hash (ssr_checksum) over the records it produced (AFTER render
  // populated the widget array). mismatch = the SSR DOM and this
  // module disagree -> diagnostic; syncDOM repairs the diverging
  // nodes one by one (partial recovery).
  if (phase === "HYDRATING" && e.ssr_checksum && ui.dataset.asxChecksum) {
    const want = parseInt(ui.dataset.asxChecksum, 16);
    const got = e.ssr_checksum() >>> 0;
    if (got !== want) console.error("ASX Hydration Error: root=" + (ui.dataset.asxRoot || "?") + " server checksum=" + ui.dataset.asxChecksum + " client checksum=" + got.toString(16));
  }
  syncDOM();
  phase = "INTERACTIVE";
  if (e.frame && e.pixels) {
    const loop = () => {
      e.frame();
      if (e.ui_dirty && e.ui_dirty()) { e.render(); syncDOM(); }
      const cv = ui.querySelector("canvas");
      if (cv) {
        const ctx = cv.getContext("2d");
        const img = ctx.createImageData(e.width(), e.height());
        img.data.set(new Uint8ClampedArray(mem(), e.pixels(), e.width()*e.height()*4));
        ctx.putImageData(img, 0, 0);
      }
      requestAnimationFrame(loop);
    };
    loop();
  }
  if (e.handle_event) {
    const rp = () => ui.getBoundingClientRect();
    // the browser resolves the click target: only a real
    // button (data-asx-role="button") gets a click dispatch,
    // with coordinates relative to it - no rect scanning
    // over every widget. clicks outside any button are
    // dropped (the wasm handler only acts on t==1 clicks)
    const fire = (t, ev) => {
      if (t === 1) {
        const btn = ev.target.closest ? ev.target.closest("[data-asx-role=button]") : null;
        if (!btn) return;
        // the wasm dispatches actions by widget id
        const id = parseInt(btn.dataset.asxId, 10);
        e.handle_event(1, id, 0, 0, 0);
      } else {
        e.handle_event(t, -1, ev.clientX - rp().left, ev.clientY - rp().top, 0);
      }
      if (e.ui_dirty && e.ui_dirty()) { e.render(); syncDOM(); }
    };
    ui.addEventListener("mousemove", (ev) => fire(0, ev));
    ui.addEventListener("mousedown", (ev) => fire(1, ev));
    window.addEventListener("keydown", (ev) => {
      e.handle_event(2, -1, 0, 0, ev.keyCode || ev.which);
      if (e.ui_dirty && e.ui_dirty()) { e.render(); syncDOM(); }
    });
  }
  // hot reload: EventSource with auto-reconnect; each open
  // means the server (re)started, so re-check the wasm bytes
  let snapBytes = new Uint8Array(await fetch(mod + "?t=" + Date.now(), { cache: "no-store" }).then((r) => r.arrayBuffer()));
  const check = async () => {
    try {
      const r = await fetch(mod + "?t=" + Date.now(), { cache: "no-store" });
      const b = new Uint8Array(await r.arrayBuffer());
      if (b.byteLength !== snapBytes.byteLength || b.some((v, i) => v !== snapBytes[i])) {
        snapBytes = b;
        const { instance: nxt } = await WebAssembly.instantiate(b, { env: { fetch_req } });
        e = nxt.exports;
        if (e.init) e.init();
        if (e.render) e.render();
        syncDOM();
      }
    } catch (err) {}
  };
  new EventSource("/_asx/events").onopen = () => check();
};
boot();