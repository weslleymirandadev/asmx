; asx/wasm/glue.asm - the WASM UI renderer (framework side).
; Serves the generic glue JS at /_asx/glue.js (a virtual file - no
; public/ entry needed). The glue loads /app.wasm, applies the module
; theme (ui_theme_*), renders the widget tree to DOM (View -> div,
; Text -> span, canvas widget -> <canvas>) and forwards mouse/keyboard
; events to handle_event(). Apps never write UI code in page.s - the
; page template is just <div id="ui"> + <script src="/_asx/glue.js">.
;
; SSR + hydration: when the served HTML carries data-asx-root (the
; ui-compile SSR pass renders the FULL widget tree server-side, with
; stable data-asx-id + data-asx-checksum + a state snapshot), the glue
; HYDRATES that DOM instead of rebuilding it: it maps the SSR nodes by
; id, validates types, restores the snapshot state (set_count) and only
; touches nodes that diverge. Phase machine: SSR -> HYDRATING ->
; INTERACTIVE.
; wasm_glue_serve() -> sends 200 + text/javascript + body.

%include "common/syscalls.inc"
%include "common/strings.inc"

extern client_fd
extern resp_buf
extern itoa_buf
extern cl_prefix, crlf2
extern memcpy_adv, strcpy_adv
extern write_status_line

section .data
    ; NOTE: JS uses double quotes only (fits db '...' without escapes)
    glue_js db 'const boot = async () => {', 10
 db '  const ui = document.getElementById("ui") || (() => { const d = document.createElement("div"); d.id = "ui"; document.body.appendChild(d); return d; })();', 10
 db '  ui.style.cssText = "position:relative;width:100%;max-width:720px;margin:0 auto";', 10
 db '  const mod = (ui.dataset.modules || "/app.wasm").split(",")[0];', 10
 db '  // cache-bust the module with the SSR checksum (?v=<checksum>): the', 10
 db '  // wasm URL changes whenever the page changes, so a stale cached', 10
 db '  // module can never hydrate over a newer SSR shell (transitions/', 10
 db '  // classes/checksum would silently diverge). CSR (no checksum) =', 10
 db '  // no-store fetch like the hot-reload path.', 10
 db '  const hasCk = ui.hasAttribute("data-asx-checksum");', 10
 db '  const modV = hasCk ? mod + "?v=" + ui.getAttribute("data-asx-checksum") : mod;', 10
 db '  // RPC (ROADMAP item 4): the wasm module imports env.fetch_req. The', 10
 db '  // glue runs a SYNCHRONOUS XHR (the wasm call blocks, so async fetch', 10
 db '  // cannot work on the main thread - the event loop would never', 10
 db '  // resume) and writes the response body into the module memory at', 10
 db '  // resp_area(), setting resp_len.value. Returns the HTTP status.', 10
 db '  // The wasm side owns when/what: it passes url/method/body pointers', 10
 db '  // and reads the response buffer afterwards.', 10
 db '  const fetch_req = (up, ul, mp, ml, bp, bl) => {', 10
 db '    const buf = mem();', 10
 db '    const url = location.origin + dec.decode(new Uint8Array(buf, up, ul));', 10
 db '    const method = dec.decode(new Uint8Array(buf, mp, ml));', 10
 db '    const body = bl ? dec.decode(new Uint8Array(buf, bp, bl)) : null;', 10
 db '    const xhr = new XMLHttpRequest();', 10
 db '    xhr.open(method, url, false);', 10
 db '    if (body !== null) xhr.setRequestHeader("Content-Type", "application/json");', 10
 db '    xhr.send(body);', 10
 db '    const txt = xhr.responseText || "";', 10
 db '    const enc = new TextEncoder().encode(txt);', 10
 db '    const cap = (e.resp_cap && e.resp_cap()) || 4096;', 10
 db '    const n = Math.min(enc.length, cap);', 10
 db '    const dst = e.resp_area ? e.resp_area() : 0;', 10
 db '    new Uint8Array(mem()).set(enc.subarray(0, n), dst);', 10
 db '    if (e.resp_len) e.resp_len.value = n;', 10
 db '    return xhr.status || 0;', 10
 db '  };', 10
 db '  const { instance } = await WebAssembly.instantiateStreaming(fetch(modV, hasCk ? {} : { cache: "no-store" }), { env: { fetch_req } });', 10
 db '  let e = instance.exports;', 10
 db '  const mem = () => e.memory.buffer;', 10
 db '  const dec = new TextDecoder();', 10
 db '  // ---- SSR + hydration (phase machine: SSR -> HYDRATING -> INTERACTIVE) ----', 10
 db '  // SSR: the DOM came from the server (data-asx-root on #ui). The glue', 10
 db '  // assumes that DOM, validates it and connects behavior - it does NOT', 10
 db '  // rebuild the page. HYDRATING: first sync reusing the SSR nodes.', 10
 db '  // INTERACTIVE: normal reactive rendering may start.', 10
 db '  let phase = ui.hasAttribute("data-asx-root") ? "SSR" : "CSR";', 10
 db '  // hydration snapshot: minimal render state produced by the SSR pass', 10
 db '  // (<script type="application/asx-state">). Restored BEFORE the first', 10
 db '  // render so the first paint is exactly what the server produced.', 10
 db '  const snap = (() => { let s = null; for (const sc of document.scripts) { if (sc.type === "application/asx-state") { s = sc; break; } } try { return s ? JSON.parse(s.textContent) : {}; } catch (err) { return {}; } })();', 10
 db '  // every snapshot key (except "root") maps to a set_<name> export', 10
 db '  // (declarative states) or set_count (legacy): ssr.state values', 10
 db '  // injected by the server are restored before the first render', 10
 db '  for (const k in snap) { if (k === "root") continue; const fn = e["set_" + k]; if (typeof fn === "function") fn(snap[k]); }', 10
 db '  // dynamic route slug: "/profile/joao" -> "joao" (last path', 10
 db '  // segment). Written into the wasm memory (slug_area) so the', 10
 db '  // module can read it; "{slug}" in any text is replaced below.', 10
 db '  const slug = location.pathname.split("/").filter(Boolean).pop() || "";', 10
 db '  if (e.slug_area) { const sa = e.slug_area(); const b = new TextEncoder().encode(slug); new Uint8Array(mem()).set(b, sa); new Uint8Array(mem())[sa + b.length] = 0; }', 10
 db '  const hex = (v) => "#" + ((v>>16)&255).toString(16).padStart(2,"0") + ((v>>8)&255).toString(16).padStart(2,"0") + (v&255).toString(16).padStart(2,"0");', 10
 db '  // the SSR shell already carries the base css (style[data-asx-base]', 10
 db '  // with reset + theme) so the first paint is the final layout -', 10
 db '  // only inject our copy when rendering client-side (no SSR shell)', 10
 db '  if (!document.querySelector("style[data-asx-base]")) {', 10
 db '    const st = document.createElement("style");', 10
 db '    st.setAttribute("data-asx-base", "");', 10
 db '    st.textContent = "*{margin:0;padding:0;box-sizing:border-box}button{border:none;background:none;font:inherit}body{min-height:100vh;font-family:ui-sans-serif,system-ui,sans-serif;padding:48px 24px}";', 10
 db '    document.head.appendChild(st);', 10
 db '  }', 10
 db '  if (e.ui_theme_bg) document.body.style.background = hex(e.ui_theme_bg());', 10
 db '  if (e.ui_theme_text) document.body.style.color = hex(e.ui_theme_text());', 10
 db '  const els = [];', 10
 db '  // map the SSR DOM by data-asx-id (stable compiler-generated ids).', 10
 db '  // hydration REUSES these nodes - no structural DOM change unless a', 10
 db '  // node is missing or its tag type diverges (partial re-render).', 10
 db '  const byId = new Map();', 10
 db '  for (const el of ui.querySelectorAll("[data-asx-id]")) byId.set(el.getAttribute("data-asx-id"), el);', 10
 db '  // real HTML tag per widget: index = record byte 1 (tag id from', 10
 db '  // the tags table in ui/tables.inc - keep in sync!). id 0 = div.', 10
 db '  const TAG_NAMES = ["div","main","div","section","nav","header","footer","article","aside","figure","blockquote","ul","ol","li","form","table","thead","tbody","tfoot","tr","td","th","details","dialog","video","audio","picture","iframe","canvas","select","textarea","fieldset","dl","dt","dd","menu","hgroup","h1","h2","h3","h4","h5","h6","p","span","a","label","strong","em","code","pre","small","b","i","u","mark","time","cite","q","abbr","sub","sup","kbd","samp","var","del","ins","s","option","figcaption","legend","caption","summary","button","img","input","br","hr","source","meta","link","area","base","col","embed","track","wbr"];', 10
 db '  const tagFor = (type, tagId) => tagId ? (TAG_NAMES[tagId] || "DIV").toUpperCase() : (type === 1 ? "SPAN" : type === 2 ? "CANVAS" : "DIV");', 10
 db '  // html attributes from the record (bytes 26..29 = absolute address', 10
 db '  // of a name="value" ... string; 0 = none). Applied on creation', 10
 db '  // so CSR nodes carry the same attributes as the SSR ones.', 10
 db '  const applyAttrs = (el, o, v) => {', 10
 db '    const ap = v.getUint32(o+26, true);', 10
 db '    if (!ap) return;', 10
 db '    let s = "", p = ap; while (v.getUint8(p) !== 0) s += String.fromCharCode(v.getUint8(p++));', 10
 db '    const re = /([a-zA-Z][a-zA-Z0-9-]*)="([^"]*)"/g; let m;', 10
 db '    while ((m = re.exec(s))) { try { el.setAttribute(m[1], m[2]); } catch (e) {} }', 10
 db '  };', 10
 db '  // flexbox layout: views are flex containers, texts flow', 10
 db '  // inside them. x/y from the module are the fallback size.', 10
 db '  const syncDOM = () => {', 10
 db '    const buf = mem(), v = new DataView(buf);', 10
 db '    const n = e.widget_count(), base = e.widgets();', 10
 db '    const stBase = e.styles ? e.styles() : 0;', 10
 db '    const TPROP = ["","","none","all","color,background-color,border-color,outline-color,text-decoration-color,fill,stroke,--tw-gradient-from,--tw-gradient-via,--tw-gradient-to","opacity","box-shadow","transform,translate,scale,rotate"];', 10
 db '    const TEASE = ["","linear","cubic-bezier(0.4,0,1,1)","cubic-bezier(0,0,0.2,1)","cubic-bezier(0.4,0,0.2,1)"];', 10
 db '    const STRETCH = ["","ultra-condensed","extra-condensed","condensed","semi-condensed","normal","semi-expanded","expanded","extra-expanded","ultra-expanded"];', 10
 db '    const VARNUM = ["","normal","ordinal","slashed-zero","lining-nums","oldstyle-nums","proportional-nums","tabular-nums","diagonal-fractions","stacked-fractions"];', 10
 db '    const TRACK = ["","-0.05em","-0.025em","0em","0.025em","0.05em","0.1em"];', 10
 db '    const LEAD = ["","1","1.25","1.375","1.5","1.625","2","0.75rem","1rem","1.25rem","1.5rem","1.75rem","2rem","2.25rem","2.5rem"];', 10
 db '    const WS = ["","normal","nowrap","pre","pre-line","pre-wrap","break-spaces"];', 10
 db '    const WB = ["","normal","break-word","break-all","keep-all"];', 10
 db '    const OW = ["","","","","","normal","break-word","anywhere"];', 10
 db '    const VALIGN = ["","normal","top","middle","bottom","text-top","text-bottom","sub","super"];', 10
 db '    const DSTYLE = ["","solid","double","dotted","dashed","wavy"];', 10
 db '    const TW = ["","wrap","nowrap","balance","pretty"];', 10
 db '    const HYPHENS = ["","none","manual","auto"];', 10
 db '    const ANIM = ["","spin 1s linear infinite","ping 1s cubic-bezier(0,0,0.2,1) infinite","pulse 2s cubic-bezier(0.4,0,0.6,1) infinite","bounce 1s infinite"];', 10
 db '    const FAM = ["","ui-sans-serif,system-ui,sans-serif,\"Apple Color Emoji\",\"Segoe UI Emoji\",\"Segoe UI Symbol\",\"Noto Color Emoji\"","ui-serif,Georgia,Cambria,\"Times New Roman\",Times,serif","ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,\"Liberation Mono\",\"Courier New\",monospace"];', 10
 db '    for (let i = 0; i < n; i++) {', 10
 db '      const o = base + i*32;', 10
 db '      const type = v.getUint8(o);', 10
 db '      const tagId = v.getUint8(o+1);', 10
 db '      const w = v.getInt16(o+6,true), h = v.getInt16(o+8,true);', 10
 db '      const r = v.getUint8(o+12), g = v.getUint8(o+13), b = v.getUint8(o+14);', 10
 db '      const parent = v.getInt32(o+20,true);', 10
 db '      let el = els[i];', 10
 db '      if (!el) el = byId.get(String(i)) || null;', 10
 db '      const want = tagFor(type, tagId);', 10
 db '      if (!el || el.tagName !== want) {', 10
 db '        if (el) console.error("ASX Hydration Error: node " + i + " structural mismatch expected <" + want.toLowerCase() + "> got <" + el.tagName.toLowerCase() + "> (re-created, subtree client-rendered)");', 10
 db '        el = document.createElement(want.toLowerCase());', 10
 db '        el.setAttribute("data-asx-id", String(i));', 10
 db '        byId.set(String(i), el);', 10
 db '        applyAttrs(el, o, v);', 10
 db '      }', 10
 db '      els[i] = el;', 10
 db '      const so = stBase + i*64;', 10
 db '      const flags = stBase ? v.getUint32(so,true) : 0;', 10
 db '      const weight = stBase ? v.getUint16(so+4,true) : 0;', 10
 db '      const align = stBase ? v.getUint8(so+6) : 0;', 10
 db '      const gap = stBase ? v.getUint8(so+7) : 0;', 10
 db '      const radius = stBase ? v.getUint8(so+8) : 0;', 10
 db '      const px = stBase ? v.getUint8(so+9) : 0;', 10
 db '      const py = stBase ? v.getUint8(so+10) : 0;', 10
 db '      const border = stBase ? v.getUint8(so+11) : 0;', 10
 db '      const opacity = stBase ? v.getUint8(so+12) : 0;', 10
 db '      const shadow = stBase ? v.getUint8(so+13) : 0;', 10
 db '      const role = stBase ? v.getUint8(so+14) : 0;', 10
 db '      const pad = stBase ? v.getUint8(so+15) : 0;', 10
 db '      const mt = stBase ? v.getUint8(so+16) : 0;', 10
 db '      const mb = stBase ? v.getUint8(so+17) : 0;', 10
 db '      const hh = stBase ? v.getUint8(so+18) : 0;', 10
 db '      const gcols = stBase ? v.getUint8(so+19) : 0;', 10
 db '      const ml = stBase ? v.getUint8(so+20) : 0;', 10
 db '      const mr = stBase ? v.getUint8(so+21) : 0;', 10
 db '      const pl = stBase ? v.getUint8(so+22) : 0;', 10
 db '      const pr = stBase ? v.getUint8(so+23) : 0;', 10
 db '      const pt = stBase ? v.getUint8(so+24) : 0;', 10
 db '      const pb = stBase ? v.getUint8(so+25) : 0;', 10
 db '      const trans = stBase ? v.getUint8(so+26) : 0;', 10
 db '      const ease = stBase ? v.getUint8(so+27) : 0;', 10
 db '      const dur = stBase ? v.getUint16(so+28,true) : 0;', 10
 db '      const delay = stBase ? v.getUint16(so+30,true) : 0;', 10
 db '      const anim = stBase ? v.getUint8(so+32) : 0;', 10
 db '      const tbehav = stBase ? v.getUint8(so+33) : 0;', 10
 db '      const family = stBase ? v.getUint8(so+34) : 0;', 10
 db '      const stretch = stBase ? v.getUint8(so+35) : 0;', 10
 db '      const varnum = stBase ? v.getUint8(so+36) : 0;', 10
 db '      const tracking = stBase ? v.getUint8(so+37) : 0;', 10
 db '      const lead = stBase ? v.getUint8(so+38) : 0;', 10
 db '      const wss = stBase ? v.getUint8(so+39) : 0;', 10
 db '      const wbr = stBase ? v.getUint8(so+40) : 0;', 10
 db '      const overflow = stBase ? v.getUint8(so+41) : 0;', 10
 db '      const valign = stBase ? v.getUint8(so+42) : 0;', 10
 db '      const indent = stBase ? v.getUint8(so+43) : 0;', 10
 db '      const dstyle = stBase ? v.getUint8(so+44) : 0;', 10
 db '      const dthick = stBase ? v.getUint8(so+45) : 0;', 10
 db '      const dcolor = stBase ? v.getUint32(so+46,true) : 0xFFFFFFFF;', 10
 db '      const uo2 = stBase ? v.getUint8(so+50) : 0;', 10
 db '      const clamp = stBase ? v.getUint8(so+51) : 0;', 10
 db '      const lsp = stBase ? v.getUint8(so+52) : 0;', 10
 db '      const lst = stBase ? v.getUint8(so+53) : 0;', 10
 db '      const hyphens = stBase ? v.getUint8(so+54) : 0;', 10
 db '      const tabsize = stBase ? v.getUint8(so+55) : 0;', 10
 db '      const content = stBase ? v.getUint8(so+56) : 0;', 10
 db '      const textwrap = stBase ? v.getUint8(so+57) : 0;', 10
 db '      const smooth = stBase ? v.getUint8(so+58) : 0;', 10
 db '      const bg = type === 0 && !(r === 0 && g === 0 && b === 0 && v.getUint8(o+15) === 0) ? "background:" + hex((r<<16)|(g<<8)|b) + ";" : "";', 10
 db '      const rad = radius === 255 ? "border-radius:9999px;" : (radius ? "border-radius:" + radius + "px;" : "");', 10
 db '      const bd = border ? "border:" + border + "px solid rgba(255,255,255,.2);" : "";', 10
 db '      const op = opacity ? "opacity:" + (opacity/100) + ";" : "";', 10
 db '      const sh = shadow ? "box-shadow:0 8px 24px rgba(0,0,0,.35);" : "";', 10
 db '      const tr = trans === 2 ? "transition-property:none;" : (trans ? "transition-property:" + TPROP[trans] + ";transition-duration:" + (dur || 150) + "ms;transition-timing-function:" + (TEASE[ease] || "cubic-bezier(0.4,0,0.2,1)") + ";" + (delay ? "transition-delay:" + delay + "ms;" : "") : "");', 10
 db '      const tbh = tbehav === 2 ? "transition-behavior:allow-discrete;" : tbehav ? "transition-behavior:normal;" : "";', 10
 db '      const ls = (lsp === 2 ? "list-style-position:outside;" : lsp ? "list-style-position:inside;" : "") + (lst === 2 ? "list-style-type:disc;" : lst === 3 ? "list-style-type:decimal;" : lst ? "list-style-type:none;" : "");', 10
 db '      const anv = anim ? "animation:" + ANIM[anim] + ";" : "";', 10
 db '      const padCss = (pl||pr||pt||pb) ? "padding:" + (pt||py||pad) + "px " + (pr||px||pad) + "px " + (pb||py||pad) + "px " + (pl||px||pad) + "px;" : ((px||pad) ? "padding:" + (py||pad) + "px " + (px||pad) + "px;" : "");', 10
 db '      const gapCss = gap ? "gap:" + gap + "px;" : "";', 10
 db '      const mg = (ml||mr) ? "margin:" + mt + "px " + mr + "px " + mb + "px " + ml + "px;" : ((mt||mb) ? "margin:" + mt + "px 0 " + mb + "px;" : "");', 10
 db '      const flexDir = (flags & 1) ? ((flags & 2) ? "column" : "row") : "column";', 10
 db '      const items = (flags & 4) ? "center" : (flags & 8) ? "flex-end" : (flags & 4194304) ? "flex-start" : "stretch";', 10
 db '      const just = (flags & 16) ? "center" : (flags & 32) ? "space-between" : (flags & 64) ? "flex-end" : (flags & 131072) ? "space-around" : (flags & 262144) ? "space-evenly" : "flex-start";', 10
 db '      if (type === 1) {', 10
 db '        const fs = v.getUint8(o+24) || 13;', 10
 db '        const col = "color:" + hex((r<<16)|(g<<8)|b) + ";";', 10
 db '        const fam = family ? "font-family:" + FAM[family] + ";" : "";', 10
 db '        const str = stretch ? "font-stretch:" + STRETCH[stretch] + ";" : "";', 10
 db '        const vn = varnum ? "font-variant-numeric:" + VARNUM[varnum] + ";" : "";', 10
 db '        const sm = smooth === 2 ? "-webkit-font-smoothing:auto;" : smooth ? "-webkit-font-smoothing:antialiased;" : "";', 10
 db '        const fw = weight ? "font-weight:" + weight + ";" : "";', 10
 db '        const trk = tracking ? "letter-spacing:" + TRACK[tracking] + ";" : "";', 10
 db '        const ta = align === 1 ? "text-align:center;" : align === 2 ? "text-align:right;" : align === 3 ? "text-align:justify;" : align === 4 ? "text-align:start;" : align === 5 ? "text-align:end;" : "";', 10
 db '        const tt = (flags & 8192) ? "text-transform:uppercase;" : (flags & 1048576) ? "text-transform:lowercase;" : (flags & 134217728) ? "text-transform:capitalize;" : (flags & 16777216) ? "text-transform:none;" : "";', 10
 db '        const it = (flags & 16384) ? "font-style:italic;" : (flags & 8388608) ? "font-style:normal;" : "";', 10
 db '        const un = (flags & 32768) ? "text-decoration:underline;" : (flags & 2097152) ? "text-decoration:line-through;" : (flags & 67108864) ? "text-decoration-line:overline;" : (flags & 33554432) ? "text-decoration-line:none;" : "";', 10
 db '        const dcl = dcolor !== 0xFFFFFFFF ? "text-decoration-color:" + hex(dcolor) + ";" : "";', 10
 db '        const dst = dstyle ? "text-decoration-style:" + DSTYLE[dstyle] + ";" : "";', 10
 db '        const dth = dthick === 1 ? "text-decoration-thickness:auto;" : dthick === 2 ? "text-decoration-thickness:from-font;" : dthick ? "text-decoration-thickness:" + (dthick-2) + "px;" : "";', 10
 db '        const uo = uo2 === 1 ? "text-underline-offset:auto;" : uo2 ? "text-underline-offset:" + uo2 + "px;" : "";', 10
 db '        const mgL = (ml||mr) ? "margin:" + mt + "px " + mr + "px " + mb + "px " + ml + "px;" : ((mt||mb) ? "margin:" + mt + "px 0 " + mb + "px;" : "");', 10
 db '        const ws = wss ? "white-space:" + WS[wss] + ";" : "";', 10
 db '        const wb = (wbr === 2 || wbr >= 5) ? "overflow-wrap:" + OW[wbr] + ";" : wbr ? "word-break:" + WB[wbr] + ";" : "";', 10
 db '        const ov = overflow === 3 ? "overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" : overflow ? "text-overflow:" + (overflow === 2 ? "clip" : "ellipsis") + ";" : "";', 10
 db '        const tw = textwrap ? "text-wrap:" + TW[textwrap] + ";" : "";', 10
 db '        const va = valign ? "vertical-align:" + VALIGN[valign] + ";" : "";', 10
 db '        const ind = indent ? "text-indent:" + indent + "px;" : "";', 10
 db '        const hy = hyphens ? "hyphens:" + HYPHENS[hyphens] + ";" : "";', 10
 db '        const tab = tabsize ? "tab-size:" + tabsize + ";" : "";', 10
 db '        const cl = clamp ? "-webkit-line-clamp:" + clamp + ";overflow:hidden;" : "";', 10
 db '        const cont = content ? "content:none;" : "";', 10
 db '        const an = anim ? "animation:" + ANIM[anim] + ";" : "";', 10
 db '        const lh = lead ? "line-height:" + LEAD[lead] + ";" : "line-height:1.4;";', 10
 db '        const disp = clamp ? "display:-webkit-box;-webkit-box-orient:vertical;font-size:" : "display:block;font-size:";', 10
 db '        const css = disp + fs + "px;" + col + fam + str + vn + sm + fw + trk + ta + tt + it + un + dcl + dst + dth + uo + mgL + ws + wb + ov + tw + va + ind + hy + tab + cl + cont + an + lh;', 10
 db '        if (el.style.cssText !== css) el.style.cssText = css;', 10
 db '        const tp = v.getUint32(o+16,true);', 10
 db '        let end = tp; while (v.getUint8(end) !== 0) end++;', 10
 db '        let txt = dec.decode(new Uint8Array(buf, tp, end-tp));', 10
 db '        if (txt.includes("{slug}")) txt = txt.split("{slug}").join(slug);', 10
 db '        if (el.textContent !== txt) {', 10
 db '          if (phase === "HYDRATING" && !el.textContent.includes("{slug}")) console.error("ASX Hydration Error: node " + i + " text mismatch server=" + JSON.stringify(el.textContent) + " client=" + JSON.stringify(txt) + " (fixed)");', 10
 db '          el.textContent = txt;', 10
 db '        }', 10
 db '      } else if (type === 2) {', 10
 db '        const css = "display:block;width:" + w + "px;height:" + h + "px;border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,.4);";', 10
 db '        if (el.style.cssText !== css) el.style.cssText = css;', 10
 db '      } else {', 10
 db '        // buttons (role 1) shrink to fit their label and', 10
 db '        // get a pointer cursor; plain views stretch 100%', 10
 db '        const ww = (w && w < 720) ? "width:" + w + "px;" : (role === 1 ? "width:auto;align-self:flex-start;cursor:pointer;" : "width:100%;min-width:0;");', 10
 db '        const hid = (flags & 128) ? "display:none;" : "";', 10
 db '        const grd = (flags & 65536) ? "position:relative;display:grid;" + (gcols ? "grid-template-columns:repeat(" + gcols + ",1fr);" : "") : "";', 10
 db '        const wrp = (flags & 256) ? "flex-wrap:wrap;" : "";', 10
 db '        const grw = (flags & 512) ? "flex:1 1 0%;" : "";', 10
 db '        const rest = bg + padCss + gapCss + mg + rad + bd + op + sh + tr + tbh + ww + ls + anv;', 10
 db '        const css = hid ? "display:none;" : (grd ? grd + rest : "position:relative;display:flex;flex-direction:" + flexDir + ";" + wrp + grw + "align-items:" + items + ";justify-content:" + just + ";" + rest);', 10
 db '        if (el.style.cssText !== css) el.style.cssText = css;', 10
 db '        if (hh) { if (el.style.minHeight !== hh + "px") el.style.minHeight = hh + "px"; }', 10
 db '      }', 10
 db '      // buttons carry data-asx-role="button" (SSR emits it; CSR sets', 10
 db '      // it here) so the click handler can resolve the target with', 10
 db '      // ev.target.closest instead of scanning every widget rect', 10
 db '      if (role === 1) el.setAttribute("data-asx-role", "button");', 10
 db '      const pe = (parent >= 0 && els[parent]) ? els[parent] : ui;', 10
 db '      if (el.parentNode !== pe) pe.appendChild(el);', 10
 db '    }', 10
 db '    // SSR leftovers: nodes the module no longer produces are removed', 10
 db '    for (const [id, el] of byId) { const k = parseInt(id, 10); if (k >= n && el.parentNode) el.remove(); }', 10
 db '    for (let i = n; i < els.length; i++) { if (els[i]) { els[i].remove(); els[i] = null; } }', 10
 db '  };', 10
            db '  if (e.init) e.init();', 10
            db '  if (e.render) e.render();', 10
            db '  if (phase === "SSR") phase = "HYDRATING";', 10
            db '  // checksum: the server embeds data-asx-checksum = FNV-1a over the', 10
            db '  // canonical IR (records + strings). The module recomputes the same', 10
            db '  // hash (ssr_checksum) over the records it produced (AFTER render', 10
            db '  // populated the widget array). mismatch = the SSR DOM and this', 10
            db '  // module disagree -> diagnostic; syncDOM repairs the diverging', 10
            db '  // nodes one by one (partial recovery).', 10
            db '  if (phase === "HYDRATING" && e.ssr_checksum && ui.dataset.asxChecksum) {', 10
            db '    const want = parseInt(ui.dataset.asxChecksum, 16);', 10
            db '    const got = e.ssr_checksum() >>> 0;', 10
            db '    if (got !== want) console.error("ASX Hydration Error: root=" + (ui.dataset.asxRoot || "?") + " server checksum=" + ui.dataset.asxChecksum + " client checksum=" + got.toString(16));', 10
            db '  }', 10
            db '  syncDOM();', 10
            db '  phase = "INTERACTIVE";', 10
            db '  if (e.frame && e.pixels) {', 10
            db '    const loop = () => {', 10
            db '      e.frame();', 10
            db '      if (e.ui_dirty && e.ui_dirty()) { e.render(); syncDOM(); }', 10
            db '      const cv = ui.querySelector("canvas");', 10
            db '      if (cv) {', 10
            db '        const ctx = cv.getContext("2d");', 10
            db '        const img = ctx.createImageData(e.width(), e.height());', 10
            db '        img.data.set(new Uint8ClampedArray(mem(), e.pixels(), e.width()*e.height()*4));', 10
            db '        ctx.putImageData(img, 0, 0);', 10
            db '      }', 10
            db '      requestAnimationFrame(loop);', 10
            db '    };', 10
            db '    loop();', 10
            db '  }', 10
            db '  if (e.handle_event) {', 10
            db '    const rp = () => ui.getBoundingClientRect();', 10
            db '    // the browser resolves the click target: only a real', 10
            db '    // button (data-asx-role="button") gets a click dispatch,', 10
            db '    // with coordinates relative to it - no rect scanning', 10
            db '    // over every widget. clicks outside any button are', 10
            db '    // dropped (the wasm handler only acts on t==1 clicks)', 10
            db '    const fire = (t, ev) => {', 10
            db '      if (t === 1) {', 10
            db '        const btn = ev.target.closest ? ev.target.closest("[data-asx-role=button]") : null;', 10
            db '        if (!btn) return;', 10
            db '        // the wasm dispatches actions by widget id', 10
            db '        const id = parseInt(btn.dataset.asxId, 10);', 10
            db '        e.handle_event(1, id, 0, 0, 0);', 10
            db '      } else {', 10
            db '        e.handle_event(t, -1, ev.clientX - rp().left, ev.clientY - rp().top, 0);', 10
            db '      }', 10
            db '      if (e.ui_dirty && e.ui_dirty()) { e.render(); syncDOM(); }', 10
            db '    };', 10
            db '    ui.addEventListener("mousemove", (ev) => fire(0, ev));', 10
            db '    ui.addEventListener("mousedown", (ev) => fire(1, ev));', 10
            db '    window.addEventListener("keydown", (ev) => {', 10
            db '      e.handle_event(2, -1, 0, 0, ev.keyCode || ev.which);', 10
            db '      if (e.ui_dirty && e.ui_dirty()) { e.render(); syncDOM(); }', 10
            db '    });', 10
            db '  }', 10
            db '  // hot reload: EventSource with auto-reconnect; each open', 10
            db '  // means the server (re)started, so re-check the wasm bytes', 10
            db '  let snapBytes = new Uint8Array(await fetch(mod + "?t=" + Date.now(), { cache: "no-store" }).then((r) => r.arrayBuffer()));', 10
            db '  const check = async () => {', 10
            db '    try {', 10
            db '      const r = await fetch(mod + "?t=" + Date.now(), { cache: "no-store" });', 10
            db '      const b = new Uint8Array(await r.arrayBuffer());', 10
            db '      if (b.byteLength !== snapBytes.byteLength || b.some((v, i) => v !== snapBytes[i])) {', 10
            db '        snapBytes = b;', 10
            db '        const { instance: nxt } = await WebAssembly.instantiate(b, { env: { fetch_req } });', 10
            db '        e = nxt.exports;', 10
            db '        if (e.init) e.init();', 10
            db '        if (e.render) e.render();', 10
            db '        syncDOM();', 10
            db '      }', 10
            db '    } catch (err) {}', 10
            db '  };', 10
            db '  new EventSource("/_asx/events").onopen = () => check();', 10
            db '};', 10
            db 'boot();', 0
    glue_js_len equ $ - glue_js - 1
    glue_ct db "Content-Type: text/javascript", 13, 10, 0
    sse_ct  db "Content-Type: text/event-stream", 13, 10, 0
    sse_cc  db "Cache-Control: no-cache", 13, 10, 0
    sse_body db "retry: 250", 10, 10, "data: ok", 10, 10
    sse_body_len equ $ - sse_body

section .text

global wasm_glue_serve
wasm_glue_serve:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; build header in resp_buf
    lea r15, [resp_buf]
    call write_status_line        ; HTTP/1.1 200 OK\r\n
    mov rdi, r15
    lea rsi, [glue_ct]
    call strcpy_adv               ; Content-Type line
    mov r15, rax
    mov rdi, r15
    lea rsi, [cl_prefix]
    call strcpy_adv               ; Content-Length: 
    mov r15, rax
    mov rdi, glue_js_len
    lea rsi, [itoa_buf]
    call itoa                     ; rax = ptr to first digit
    mov rsi, rax
    lea rdx, [itoa_buf + 11]
    sub rdx, rsi
    mov rdi, r15
    call memcpy_adv               ; size digits
    mov r15, rax
    mov rdi, r15
    lea rsi, [crlf2]
    mov rdx, 4
    call memcpy_adv               ; end of headers
    mov r15, rax

    ; write header
    lea rax, [resp_buf]
    sub r15, rax
    mov rax, SYS_write
    mov rdi, [client_fd]
    lea rsi, [resp_buf]
    mov rdx, r15
    syscall
    test rax, rax
    js .err

    ; write body
    mov rax, SYS_write
    mov rdi, [client_fd]
    lea rsi, [glue_js]
    mov rdx, glue_js_len
    syscall
    test rax, rax
    js .err

    xor rax, rax
    jmp .out
.err:
    mov rax, -1
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; sse_serve() - hot-reload event stream. Answers with a tiny
; event-source body (retry: 2000ms) and closes: the server is
; single-threaded, so it can not hold the connection; the browser's
; EventSource reconnects on its own. Each reconnect means the server
; (re)started - the glue.js uses onopen to re-check the wasm bytes.
; ----------------------------------------------------------------------
global sse_serve
sse_serve:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; build header in resp_buf
    lea r15, [resp_buf]
    call write_status_line        ; HTTP/1.1 200 OK\r\n
    mov rdi, r15
    lea rsi, [sse_ct]
    call strcpy_adv               ; Content-Type: text/event-stream
    mov r15, rax
    mov rdi, r15
    lea rsi, [sse_cc]
    call strcpy_adv               ; Cache-Control: no-cache
    mov r15, rax
    mov rdi, r15
    lea rsi, [cl_prefix]
    call strcpy_adv               ; Content-Length: 
    mov r15, rax
    mov rdi, sse_body_len
    lea rsi, [itoa_buf]
    call itoa
    mov rsi, rax
    lea rdx, [itoa_buf + 11]
    sub rdx, rsi
    mov rdi, r15
    call memcpy_adv
    mov r15, rax
    mov rdi, r15
    lea rsi, [crlf2]
    mov rdx, 4
    call memcpy_adv               ; end of headers
    mov r15, rax

    ; write header
    lea rax, [resp_buf]
    sub r15, rax
    mov rax, SYS_write
    mov rdi, [client_fd]
    lea rsi, [resp_buf]
    mov rdx, r15
    syscall
    test rax, rax
    js .err

    ; write body
    mov rax, SYS_write
    mov rdi, [client_fd]
    lea rsi, [sse_body]
    mov rdx, sse_body_len
    syscall
    test rax, rax
    js .err

    xor rax, rax
    jmp .out
.err:
    mov rax, -1
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
