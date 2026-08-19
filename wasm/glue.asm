; asmx/wasm/glue.asm - the WASM UI renderer (framework side).
; Serves the generic glue JS at /_asmx/glue.js (a virtual file - no
; public/ entry needed). The glue loads /app.wasm, applies the module
; theme (ui_theme_*), renders the widget tree to DOM (View -> div,
; Text -> span, canvas widget -> <canvas>) and forwards mouse/keyboard
; events to handle_event(). Apps never write UI code in page.s - the
; page template is just <div id="ui"> + <script src="/_asmx/glue.js">.
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
 db '  const { instance } = await WebAssembly.instantiateStreaming(fetch(mod));', 10
 db '  let e = instance.exports;', 10
 db '  const mem = () => e.memory.buffer;', 10
 db '  const dec = new TextDecoder();', 10
 db '  // dynamic route slug: "/profile/joao" -> "joao" (last path', 10
 db '  // segment). Written into the wasm memory (slug_area) so the', 10
 db '  // module can read it; "{slug}" in any text is replaced below.', 10
 db '  const slug = location.pathname.split("/").filter(Boolean).pop() || "";', 10
 db '  if (e.slug_area) { const sa = e.slug_area(); const b = new TextEncoder().encode(slug); new Uint8Array(mem()).set(b, sa); new Uint8Array(mem())[sa + b.length] = 0; }', 10
 db '  const hex = (v) => "#" + ((v>>16)&255).toString(16).padStart(2,"0") + ((v>>8)&255).toString(16).padStart(2,"0") + (v&255).toString(16).padStart(2,"0");', 10
 db '  const st = document.createElement("style");', 10
 db '  st.textContent = "*{margin:0;padding:0;box-sizing:border-box}body{min-height:100vh;font-family:ui-sans-serif,system-ui,sans-serif;padding:48px 24px}";', 10
 db '  document.head.appendChild(st);', 10
 db '  if (e.ui_theme_bg) document.body.style.background = hex(e.ui_theme_bg());', 10
 db '  if (e.ui_theme_text) document.body.style.color = hex(e.ui_theme_text());', 10
 db '  const els = [];', 10
 db '  const isBtn = [];', 10
 db '  // flexbox layout: views are flex containers, texts flow', 10
 db '  // inside them. x/y from the module are the fallback size.', 10
 db '  const syncDOM = () => {', 10
 db '    const buf = mem(), v = new DataView(buf);', 10
 db '    const n = e.widget_count(), base = e.widgets();', 10
 db '    const stBase = e.styles ? e.styles() : 0;', 10
 db '    for (let i = 0; i < n; i++) {', 10
 db '      const o = base + i*32;', 10
 db '      const type = v.getUint8(o);', 10
 db '      const w = v.getInt16(o+6,true), h = v.getInt16(o+8,true);', 10
 db '      const r = v.getUint8(o+12), g = v.getUint8(o+13), b = v.getUint8(o+14);', 10
 db '      const parent = v.getInt32(o+20,true);', 10
 db '      let el = els[i];', 10
 db '      const so = stBase + i*16;', 10
 db '      const flags = stBase ? v.getUint16(so,true) : 0;', 10
 db '      const weight = stBase ? v.getUint8(so+2) : 0;', 10
 db '      const align = stBase ? v.getUint8(so+3) : 0;', 10
 db '      const gap = stBase ? v.getUint8(so+4) : 0;', 10
 db '      const radius = stBase ? v.getUint8(so+5) : 0;', 10
 db '      const px = stBase ? v.getUint8(so+6) : 0;', 10
 db '      const py = stBase ? v.getUint8(so+7) : 0;', 10
 db '      const border = stBase ? v.getUint8(so+8) : 0;', 10
 db '      const opacity = stBase ? v.getUint8(so+9) : 0;', 10
 db '      const shadow = stBase ? v.getUint8(so+10) : 0;', 10
 db '      const role = stBase ? v.getUint8(so+11) : 0;', 10
 db '      const pad = stBase ? v.getUint8(so+12) : 0;', 10
 db '      const mt = stBase ? v.getUint8(so+13) : 0;', 10
 db '      const mb = stBase ? v.getUint8(so+14) : 0;', 10
 db '      const hh = stBase ? v.getUint8(so+15) : 0;', 10
 db '      const bg = type === 0 && !(r === 0 && g === 0 && b === 0 && v.getUint8(o+15) === 0) ? "background:" + hex((r<<16)|(g<<8)|b) + ";" : "";', 10
 db '      const rad = radius === 255 ? "border-radius:9999px;" : (radius ? "border-radius:" + radius + "px;" : "");', 10
 db '      const bd = border ? "border:" + border + "px solid rgba(255,255,255,.2);" : "";', 10
 db '      const op = opacity ? "opacity:" + (opacity/100) + ";" : "";', 10
 db '      const sh = shadow ? "box-shadow:0 8px 24px rgba(0,0,0,.35);" : "";', 10
 db '      const padCss = (px||pad) ? "padding:" + (py||pad) + "px " + (px||pad) + "px;" : "";', 10
 db '      const gapCss = gap ? "gap:" + gap + "px;" : "";', 10
 db '      const mg = (mt||mb) ? "margin:" + mt + "px 0 " + mb + "px;" : "";', 10
 db '      const flexDir = (flags & 1) ? ((flags & 2) ? "column" : "row") : "column";', 10
 db '      const items = (flags & 4) ? "center" : (flags & 8) ? "flex-end" : "flex-start";', 10
 db '      const just = (flags & 16) ? "center" : (flags & 32) ? "space-between" : (flags & 64) ? "flex-end" : "flex-start";', 10
 db '      if (type === 1) {', 10
 db '        if (!el || el.tagName !== "SPAN") { el = document.createElement("span"); els[i] = el; }', 10
 db '        const fs = v.getUint8(o+24) || 13;', 10
 db '        const col = "color:" + hex((r<<16)|(g<<8)|b) + ";";', 10
 db '        const fw = weight ? "font-weight:" + weight + ";" : "";', 10
 db '        const ta = align === 1 ? "text-align:center;" : align === 2 ? "text-align:right;" : align === 3 ? "text-align:justify;" : "";', 10
 db '        const tt = (flags & 8192) ? "text-transform:uppercase;" : "";', 10
 db '        const it = (flags & 16384) ? "font-style:italic;" : "";', 10
 db '        const un = (flags & 32768) ? "text-decoration:underline;" : "";', 10
 db '        const css = "display:block;font-size:" + fs + "px;" + col + fw + ta + tt + it + un + "line-height:1.4;";', 10
 db '        if (el.style.cssText !== css) el.style.cssText = css;', 10
 db '        const tp = v.getUint32(o+16,true);', 10
 db '        let end = tp; while (v.getUint8(end) !== 0) end++;', 10
 db '        let txt = dec.decode(new Uint8Array(buf, tp, end-tp));', 10
 db '        if (txt.includes("{slug}")) txt = txt.split("{slug}").join(slug);', 10
 db '        if (el.textContent !== txt) el.textContent = txt;', 10
 db '      } else if (type === 2) {', 10
 db '        if (!el || el.tagName !== "CANVAS") { el = document.createElement("canvas"); el.width = w; el.height = h; els[i] = el; }', 10
 db '        el.style.cssText = "display:block;width:" + w + "px;height:" + h + "px;border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,.4);";', 10
 db '      } else {', 10
 db '        if (!el || el.tagName !== "DIV") { el = document.createElement("div"); els[i] = el; }', 10
 db '        // buttons (role 1) shrink to fit their label and', 10
 db '        // get a pointer cursor; plain views stretch 100%', 10
 db '        const ww = (w && w < 720) ? "width:" + w + "px;" : (role === 1 ? "width:auto;align-self:flex-start;cursor:pointer;" : "width:100%;");', 10
 db '        const css = "position:relative;display:flex;flex-direction:" + flexDir + ";align-items:" + items + ";justify-content:" + just + ";" + bg + padCss + gapCss + mg + rad + bd + op + sh + ww;', 10
 db '        if (el.style.cssText !== css) el.style.cssText = css;', 10
 db '        if (hh) { if (el.style.minHeight !== hh + "px") el.style.minHeight = hh + "px"; }', 10
 db '      }', 10
 db '      isBtn[i] = role === 1;', 10
 db '      const pe = (parent >= 0 && els[parent]) ? els[parent] : ui;', 10
 db '      if (el.parentNode !== pe) pe.appendChild(el);', 10
 db '    }', 10
 db '    for (let i = n; i < els.length; i++) { if (els[i]) { els[i].remove(); els[i] = null; } }', 10
 db '  };', 10
            db '  if (e.init) e.init();', 10
            db '  if (e.render) e.render();', 10
            db '  syncDOM();', 10
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
            db '    // click coordinates are sent RELATIVE to the button DOM', 10
            db '    // rect when the target is a button (role 1), else relative', 10
            db '    // to the ui root - matches the generated hit test (0..bw)', 10
            db '    const fire = (t, ev) => {', 10
            db '      let cx = ev.clientX - rp().left, cy = ev.clientY - rp().top;', 10
            db '      if (t === 1) {', 10
            db '        for (let i = 0; i < els.length; i++) {', 10
            db '          if (!isBtn[i] || !els[i]) continue;', 10
            db '          const rc = els[i].getBoundingClientRect();', 10
            db '          if (ev.clientX >= rc.left && ev.clientX <= rc.right && ev.clientY >= rc.top && ev.clientY <= rc.bottom) {', 10
            db '            cx = ev.clientX - rc.left; cy = ev.clientY - rc.top;', 10
            db '            break;', 10
            db '          }', 10
            db '        }', 10
            db '      }', 10
            db '      e.handle_event(t, cx, cy, 0);', 10
            db '      if (e.ui_dirty && e.ui_dirty()) { e.render(); syncDOM(); }', 10
            db '    };', 10
            db '    ui.addEventListener("mousemove", (ev) => fire(0, ev));', 10
            db '    ui.addEventListener("mousedown", (ev) => fire(1, ev));', 10
            db '    window.addEventListener("keydown", (ev) => {', 10
            db '      e.handle_event(2, 0, 0, ev.keyCode || ev.which);', 10
            db '      if (e.ui_dirty && e.ui_dirty()) { e.render(); syncDOM(); }', 10
            db '    });', 10
            db '  }', 10
            db '  // hot reload: EventSource with auto-reconnect; each open', 10
            db '  // means the server (re)started, so re-check the wasm bytes', 10
            db '  let snap = new Uint8Array(await fetch(mod + "?t=" + Date.now(), { cache: "no-store" }).then((r) => r.arrayBuffer()));', 10
            db '  const check = async () => {', 10
            db '    try {', 10
            db '      const r = await fetch(mod + "?t=" + Date.now(), { cache: "no-store" });', 10
            db '      const b = new Uint8Array(await r.arrayBuffer());', 10
            db '      if (b.byteLength !== snap.byteLength || b.some((v, i) => v !== snap[i])) {', 10
            db '        snap = b;', 10
            db '        const { instance: nxt } = await WebAssembly.instantiate(b, {});', 10
            db '        e = nxt.exports;', 10
            db '        if (e.init) e.init();', 10
            db '        if (e.render) e.render();', 10
            db '        syncDOM();', 10
            db '      }', 10
            db '    } catch (err) {}', 10
            db '  };', 10
            db '  new EventSource("/_asmx/events").onopen = () => check();', 10
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
