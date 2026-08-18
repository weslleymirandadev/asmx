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
            db '  const e = instance.exports;', 10
            db '  const mem = () => e.memory.buffer;', 10
            db '  const dec = new TextDecoder();', 10
            db '  const hex = (v) => "#" + ((v>>16)&255).toString(16).padStart(2,"0") + ((v>>8)&255).toString(16).padStart(2,"0") + (v&255).toString(16).padStart(2,"0");', 10
            db '  const st = document.createElement("style");', 10
            db '  st.textContent = "*{margin:0;padding:0;box-sizing:border-box}body{min-height:100vh;font-family:ui-sans-serif,system-ui,sans-serif;padding:48px 24px}";', 10
            db '  document.head.appendChild(st);', 10
            db '  if (e.ui_theme_bg) document.body.style.background = hex(e.ui_theme_bg());', 10
            db '  if (e.ui_theme_text) document.body.style.color = hex(e.ui_theme_text());', 10
            db '  const els = [];', 10
            db '  const syncDOM = () => {', 10
            db '    const buf = mem(), v = new DataView(buf);', 10
            db '    const n = e.widget_count(), base = e.widgets();', 10
            db '    for (let i = 0; i < n; i++) {', 10
            db '      const o = base + i*32;', 10
            db '      const type = v.getUint8(o);', 10
            db '      const x = v.getInt16(o+2,true), y = v.getInt16(o+4,true), w = v.getInt16(o+6,true), h = v.getInt16(o+8,true);', 10
            db '      const r = v.getUint8(o+12), g = v.getUint8(o+13), b = v.getUint8(o+14);', 10
            db '      const parent = v.getInt32(o+20,true);', 10
            db '      let el = els[i];', 10
            db '      if (type === 1) {', 10
            db '        if (!el || el.tagName !== "SPAN") { el = document.createElement("span"); els[i] = el; }', 10
            db '        const fs = v.getUint8(o+24) || 13;', 10
            db '        const css = "position:absolute;left:"+x+"px;top:"+y+"px;width:"+w+"px;height:"+h+"px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:"+fs+"px;color:rgb("+r+","+g+","+b+")";', 10
            db '        if (el.style.cssText !== css) el.style.cssText = css;', 10
            db '        const tp = v.getUint32(o+16,true);', 10
            db '        let end = tp; while (v.getUint8(end) !== 0) end++;', 10
            db '        const txt = dec.decode(new Uint8Array(buf, tp, end-tp));', 10
            db '        if (el.textContent !== txt) el.textContent = txt;', 10
            db '      } else if (type === 2) {', 10
            db '        if (!el || el.tagName !== "CANVAS") { el = document.createElement("canvas"); el.width = w; el.height = h; els[i] = el; }', 10
            db '        el.style.cssText = "position:absolute;left:"+x+"px;top:"+y+"px;border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,.4)";', 10
            db '      } else {', 10
            db '        if (!el || el.tagName !== "DIV") { el = document.createElement("div"); els[i] = el; }', 10
            db '        const css = "position:absolute;left:"+x+"px;top:"+y+"px;width:"+w+"px;height:"+h+"px;background:rgba("+r+","+g+","+b+",1);border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,.4)";', 10
            db '        if (el.style.cssText !== css) el.style.cssText = css;', 10
            db '      }', 10
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
            db '    const fire = (t, ev) => {', 10
            db '      e.handle_event(t, ev.clientX - rp().left, ev.clientY - rp().top, 0);', 10
            db '      if (e.ui_dirty && e.ui_dirty()) { e.render(); syncDOM(); }', 10
            db '    };', 10
            db '    ui.addEventListener("mousemove", (ev) => fire(0, ev));', 10
            db '    ui.addEventListener("mousedown", (ev) => fire(1, ev));', 10
            db '    window.addEventListener("keydown", (ev) => {', 10
            db '      e.handle_event(2, 0, 0, ev.keyCode || ev.which);', 10
            db '      if (e.ui_dirty && e.ui_dirty()) { e.render(); syncDOM(); }', 10
            db '    });', 10
            db '  }', 10
            db '};', 10
            db 'boot();', 0
    glue_js_len equ $ - glue_js - 1
    glue_ct db "Content-Type: text/javascript", 13, 10, 0

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
