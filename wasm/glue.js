// =============================================================================
// asx/wasm/glue.js - WASM UI renderer + SPA navigation
// =============================================================================
// Served at /_asx/glue.js by the framework (asx/wasm/glue.asm).
// Instantiates the page's WASM module, hydrates the SSR DOM (or falls
// back to CSR), wires up mouse/keyboard events, hot reload, and -- SPA
// navigation: clicking an <a> link inside #ui fetches the target route's
// SSR HTML, swaps the DOM, instantiates the new WASM module, and pushes
// history state. Hovering a link pre-fetches its wasm module.
//
// Phase machine: SSR -> HYDRATING -> INTERACTIVE (per mount).
// =============================================================================

const TAG_NAMES = ["div","main","div","section","nav","header","footer","article","aside","figure","blockquote","ul","ol","li","form","table","thead","tbody","tfoot","tr","td","th","details","dialog","video","audio","picture","iframe","canvas","select","textarea","fieldset","dl","dt","dd","menu","hgroup","h1","h2","h3","h4","h5","h6","p","span","a","label","strong","em","code","pre","small","b","i","u","mark","time","cite","q","abbr","sub","sup","kbd","samp","var","del","ins","s","option","figcaption","legend","caption","summary","button","img","input","br","hr","source","meta","link","area","base","col","embed","track","wbr"];
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

const tagFor = (type, tagId) => tagId ? (TAG_NAMES[tagId] || "DIV").toUpperCase() : (type === 1 ? "SPAN" : type === 2 ? "CANVAS" : "DIV");
const hex = (v) => "#"+((v>>16)&255).toString(16).padStart(2,"0")+((v>>8)&255).toString(16).padStart(2,"0")+(v&255).toString(16).padStart(2,"0");

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
  const txt = xhr.responseText || "";
  const enc = new TextEncoder().encode(txt);
  const e = live.e;
  const cap = (e.resp_cap && e.resp_cap()) || 4096;
  const n = Math.min(enc.length, cap);
  const dst = e.resp_area ? e.resp_area() : 0;
  new Uint8Array(buf).set(enc.subarray(0, n), dst);
  if (e.resp_len) e.resp_len.value = n;
  return xhr.status || 0;
};

// ---------------------------------------------------------------------------
// mount(instance, ui, snap)
// Instantiate a WASM module on the live DOM element `ui`.
//   instance - WebAssembly.Instance (already instantiated)
//   ui       - the <div id="ui"> element to hydrate/render into
//   snap     - hydration snapshot object (from <script type="application/asx-state">)
// Returns { e, mem, syncDOM, els, byId, phase, state, stop }.
// `state` is a MUTABLE holder for the exports: hot reload swaps
// live.state.e and every closure (syncDOM, input handlers, canvas loop)
// reads through state.e - so a hot reload renders the NEW module's data
// instead of reverting to the old module's memory.
// ---------------------------------------------------------------------------
const mount = (instance, ui, snap) => {
  const state = { e: instance.exports };
  const mem = () => state.e.memory.buffer;
  let phase = ui.hasAttribute("data-asx-root") ? "SSR" : "CSR";

  // restore snapshot state before first render (set_<name> exports)
  for (const k in snap) {
    if (k === "root") continue;
    const fn = state.e["set_" + k];
    if (typeof fn === "function") fn(snap[k]);
  }

  // dynamic route slug: "/profile/joao" -> "joao"
  const slug = location.pathname.split("/").filter(Boolean).pop() || "";
  if (state.e.slug_area) {
    const sa = state.e.slug_area();
    const b = new TextEncoder().encode(slug);
    const arr = new Uint8Array(mem());
    arr.set(b, sa);
    arr[sa + b.length] = 0;
  }

  // base css (reset + theme) - only inject when rendering CSR (no SSR shell)
  if (!document.querySelector("style[data-asx-base]")) {
    const st = document.createElement("style");
    st.setAttribute("data-asx-base", "");
    st.textContent = "*{margin:0;padding:0;box-sizing:border-box}button{border:none;background:none;font:inherit}body{min-height:100vh;font-family:ui-sans-serif,system-ui,sans-serif;padding:48px 24px}";
    document.head.appendChild(st);
  }
  if (state.e.ui_theme_bg) document.body.style.background = hex(state.e.ui_theme_bg());
  if (state.e.ui_theme_text) document.body.style.color = hex(state.e.ui_theme_text());

  const els = [];
  const byId = new Map();
  for (const el of ui.querySelectorAll("[data-asx-id]")) byId.set(el.getAttribute("data-asx-id"), el);

  const applyAttrs = (el, o, v) => {
    const ap = v.getUint32(o+26, true);
    if (!ap) return;
    let s = "", p = ap;
    while (v.getUint8(p) !== 0) s += String.fromCharCode(v.getUint8(p++));
    const re = /([a-zA-Z][a-zA-Z0-9-]*)="([^"]*)"/g;
    let m;
    while ((m = re.exec(s))) { try { el.setAttribute(m[1], m[2]); } catch (x) {} }
  };

  // syncDOM: reconcile the wasm widget tree with the DOM
  const syncDOM = () => {
    const buf = mem(), v = new DataView(buf);
    const n = state.e.widget_count(), base = state.e.widgets();
    const stBase = state.e.styles ? state.e.styles() : 0;
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
        if (el) {
          console.error("ASX Hydration Error: node "+i+" structural mismatch expected <"+want.toLowerCase()+"> got <"+el.tagName.toLowerCase()+"> (re-created, subtree client-rendered)");
          // detach the stale element so a re-created node doesn't leave
          // ghost content behind (e.g. after a hot reload to a different
          // module whose tree has the same indices but different tags)
          if (el.parentNode) el.remove();
        }
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
      const gp = stBase ? v.getUint8(so+7) : 0;
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
      const bg = type === 0 && !(r === 0 && g === 0 && b === 0 && v.getUint8(o+15) === 0) ? "background:"+hex((r<<16)|(g<<8)|b)+";" : "";
      const rad = radius === 255 ? "border-radius:9999px;" : (radius ? "border-radius:"+radius+"px;" : "");
      const bd = border ? "border:"+border+"px solid rgba(255,255,255,.2);" : "";
      const op = opacity ? "opacity:"+(opacity/100)+";" : "";
      const sh = shadow ? "box-shadow:0 8px 24px rgba(0,0,0,.35);" : "";
      const tr = trans === 2 ? "transition-property:none;" : (trans ? "transition-property:"+TPROP[trans]+";transition-duration:"+(dur||150)+"ms;transition-timing-function:"+(TEASE[ease]||"cubic-bezier(0.4,0,0.2,1)")+";"+(delay?"transition-delay:"+delay+"ms;":"") : "");
      const tbh = tbehav === 2 ? "transition-behavior:allow-discrete;" : tbehav ? "transition-behavior:normal;" : "";
      const ls = (lsp === 2 ? "list-style-position:outside;" : lsp ? "list-style-position:inside;" : "") + (lst === 2 ? "list-style-type:disc;" : lst === 3 ? "list-style-type:decimal;" : lst ? "list-style-type:none;" : "");
      const anv = anim ? "animation:"+ANIM[anim]+";" : "";
      const padCss = (pl||pr||pt||pb) ? "padding:"+(pt||py||pad)+"px "+(pr||px||pad)+"px "+(pb||py||pad)+"px "+(pl||px||pad)+"px;" : ((px||pad) ? "padding:"+(py||pad)+"px "+(px||pad)+"px;" : "");
      const gapCss = gp ? "gap:"+gp+"px;" : "";
      const mg = (ml||mr) ? "margin:"+mt+"px "+mr+"px "+mb+"px "+ml+"px;" : ((mt||mb) ? "margin:"+mt+"px 0 "+mb+"px;" : "");
      const flexDir = (flags & 1) ? ((flags & 2) ? "column" : "row") : "column";
      const items = (flags & 4) ? "center" : (flags & 8) ? "flex-end" : (flags & 4194304) ? "flex-start" : "stretch";
      const just = (flags & 16) ? "center" : (flags & 32) ? "space-between" : (flags & 64) ? "flex-end" : (flags & 131072) ? "space-around" : (flags & 262144) ? "space-evenly" : "flex-start";
      if (type === 1) {
        const fs = v.getUint8(o+24) || 13;
        const col = "color:"+hex((r<<16)|(g<<8)|b)+";";
        const fam = family ? "font-family:"+FAM[family]+";" : "";
        const str = stretch ? "font-stretch:"+STRETCH[stretch]+";" : "";
        const vn = varnum ? "font-variant-numeric:"+VARNUM[varnum]+";" : "";
        const sm = smooth === 2 ? "-webkit-font-smoothing:auto;" : smooth ? "-webkit-font-smoothing:antialiased;" : "";
        const fw = weight ? "font-weight:"+weight+";" : "";
        const trk = tracking ? "letter-spacing:"+TRACK[tracking]+";" : "";
        const ta = align === 1 ? "text-align:center;" : align === 2 ? "text-align:right;" : align === 3 ? "text-align:justify;" : align === 4 ? "text-align:start;" : align === 5 ? "text-align:end;" : "";
        const tt = (flags & 8192) ? "text-transform:uppercase;" : (flags & 1048576) ? "text-transform:lowercase;" : (flags & 134217728) ? "text-transform:capitalize;" : (flags & 16777216) ? "text-transform:none;" : "";
        const it = (flags & 16384) ? "font-style:italic;" : (flags & 8388608) ? "font-style:normal;" : "";
        const un = (flags & 32768) ? "text-decoration:underline;" : (flags & 2097152) ? "text-decoration:line-through;" : (flags & 67108864) ? "text-decoration-line:overline;" : (flags & 33554432) ? "text-decoration-line:none;" : "";
        const dcl = dcolor !== 0xFFFFFFFF ? "text-decoration-color:"+hex(dcolor)+";" : "";
        const dst = dstyle ? "text-decoration-style:"+DSTYLE[dstyle]+";" : "";
        const dth = dthick === 1 ? "text-decoration-thickness:auto;" : dthick === 2 ? "text-decoration-thickness:from-font;" : dthick ? "text-decoration-thickness:"+(dthick-2)+"px;" : "";
        const uo = uo2 === 1 ? "text-underline-offset:auto;" : uo2 ? "text-underline-offset:"+uo2+"px;" : "";
        const mgL = (ml||mr) ? "margin:"+mt+"px "+mr+"px "+mb+"px "+ml+"px;" : ((mt||mb) ? "margin:"+mt+"px 0 "+mb+"px;" : "");
        const ws = wss ? "white-space:"+WS[wss]+";" : "";
        const wb = (wbr === 2 || wbr >= 5) ? "overflow-wrap:"+OW[wbr]+";" : wbr ? "word-break:"+WB[wbr]+";" : "";
        const ov = overflow === 3 ? "overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" : overflow ? "text-overflow:"+(overflow === 2 ? "clip" : "ellipsis")+";" : "";
        const tw = textwrap ? "text-wrap:"+TW[textwrap]+";" : "";
        const va = valign ? "vertical-align:"+VALIGN[valign]+";" : "";
        const ind = indent ? "text-indent:"+indent+"px;" : "";
        const hy = hyphens ? "hyphens:"+HYPHENS[hyphens]+";" : "";
        const tab = tabsize ? "tab-size:"+tabsize+";" : "";
        const cl = clamp ? "-webkit-line-clamp:"+clamp+";overflow:hidden;" : "";
        const cont = content ? "content:none;" : "";
        const an = anim ? "animation:"+ANIM[anim]+";" : "";
        const lh = lead ? "line-height:"+LEAD[lead]+";" : "line-height:1.4;";
        const disp = clamp ? "display:-webkit-box;-webkit-box-orient:vertical;font-size:" : "display:block;font-size:";
        const css = disp+fs+"px;"+col+fam+str+vn+sm+fw+trk+ta+tt+it+un+dcl+dst+dth+uo+mgL+ws+wb+ov+tw+va+ind+hy+tab+cl+cont+tr+an+lh;
        if (el.style.cssText !== css) el.style.cssText = css;
        const tp = v.getUint32(o+16,true);
        let end = tp; while (v.getUint8(end) !== 0) end++;
        let txt = dec.decode(new Uint8Array(buf, tp, end-tp));
        if (txt.includes("{slug}")) txt = txt.split("{slug}").join(slug);
        if (el.textContent !== txt) {
          if (phase === "HYDRATING" && !el.textContent.includes("{slug}")) console.error("ASX Hydration Error: node "+i+" text mismatch server="+JSON.stringify(el.textContent)+" client="+JSON.stringify(txt)+" (fixed)");
          el.textContent = txt;
        }
      } else if (type === 2) {
        const css = "display:block;width:"+w+"px;height:"+h+"px;border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,.4);";
        if (el.style.cssText !== css) el.style.cssText = css;
      } else {
        const ww = (w && w < 720) ? "width:"+w+"px;" : (role === 1 ? "width:auto;align-self:flex-start;cursor:pointer;" : "width:100%;min-width:0;");
        const hid = (flags & 128) ? "display:none;" : "";
        const grd = (flags & 65536) ? "position:relative;display:grid;"+(gcols?"grid-template-columns:repeat("+gcols+",1fr);":"") : "";
        const wrp = (flags & 256) ? "flex-wrap:wrap;" : "";
        const grw = (flags & 512) ? "flex:1 1 0%;" : "";
        const rest = bg+padCss+gapCss+mg+rad+bd+op+sh+tr+tbh+ww+ls+anv;
        const css = hid ? "display:none;" : (grd ? grd+rest : "position:relative;display:flex;flex-direction:"+flexDir+";"+wrp+grw+"align-items:"+items+";justify-content:"+just+";"+rest);
        if (el.style.cssText !== css) el.style.cssText = css;
        if (h) { if (el.style.minHeight !== h+"px") el.style.minHeight = h+"px"; }
      }
      if (role === 1) el.setAttribute("data-asx-role", "button");
      const pe = (parent >= 0 && els[parent]) ? els[parent] : ui;
      if (el.parentNode !== pe) pe.appendChild(el);
    }
    // SSR leftovers: nodes the module no longer produces are removed
    for (const [id, el] of byId) { const k = parseInt(id, 10); if (k >= n) { if (el.parentNode) el.remove(); byId.delete(id); } }
    for (let i = n; i < els.length; i++) { if (els[i]) { els[i].remove(); els[i] = null; } }
  };

  if (state.e.init) state.e.init();
  if (state.e.render) state.e.render();
  if (phase === "SSR") phase = "HYDRATING";

  // checksum: FNV-1a over the canonical IR; mismatch = SSR DOM and module disagree
  if (phase === "HYDRATING" && state.e.ssr_checksum && ui.dataset.asxChecksum) {
    const want = parseInt(ui.dataset.asxChecksum, 16);
    const got = state.e.ssr_checksum() >>> 0;
    if (got !== want) console.error("ASX Hydration Error: root="+(ui.dataset.asxRoot||"?")+" server checksum="+ui.dataset.asxChecksum+" client checksum="+got.toString(16));
  }
  syncDOM();
  phase = "INTERACTIVE";

  // canvas loop (for widget type 2 / canvas-based UIs)
  // stop/start let navigate() pause the loop when the page is detached and
  // resume it when the page is restored from the pageCache
  let rafId = null;
  let loop = null;
  if (state.e.frame && state.e.pixels) {
    loop = () => {
      state.e.frame();
      if (state.e.ui_dirty && state.e.ui_dirty()) { state.e.render(); syncDOM(); }
      const cv = ui.querySelector("canvas");
      if (cv) {
        const ctx = cv.getContext("2d");
        const img = ctx.createImageData(state.e.width(), state.e.height());
        img.data.set(new Uint8ClampedArray(mem(), state.e.pixels(), state.e.width()*state.e.height()*4));
        ctx.putImageData(img, 0, 0);
      }
      rafId = requestAnimationFrame(loop);
    };
    loop();
  }

  // ---- input handling (mouse + keyboard) ----
  // mouse listeners live on the #ui element (they move with it when the
  // page is cached/restored). The keydown listener is registered ONCE
  // globally in boot() and dispatches through the current `live`, so a
  // page restored from the cache keeps working without re-registering.
  if (state.e.handle_event) {
    const rp = () => ui.getBoundingClientRect();
    const fire = (t, ev) => {
      if (t === 1) {
        const btn = ev.target.closest ? ev.target.closest("[data-asx-role=button]") : null;
        if (!btn) return;
        const id = parseInt(btn.dataset.asxId, 10);
        state.e.handle_event(1, id, 0, 0, 0);
      } else {
        state.e.handle_event(t, -1, ev.clientX - rp().left, ev.clientY - rp().top, 0);
      }
      if (state.e.ui_dirty && state.e.ui_dirty()) { state.e.render(); syncDOM(); }
    };
    ui.addEventListener("mousemove", (ev) => fire(0, ev));
    ui.addEventListener("mousedown", (ev) => fire(1, ev));
  }

  return {
    get e() { return state.e; },
    state, mem, syncDOM, els, byId, phase,
    stop: () => {
      if (rafId !== null) { cancelAnimationFrame(rafId); rafId = null; }
    },
    start: () => {
      if (loop && rafId === null) loop();
    }
  };
};

// ---------------------------------------------------------------------------
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