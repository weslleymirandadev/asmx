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
