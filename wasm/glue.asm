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
; wasm_glue_serve() -> sends 200 + text/javascript + body. The JS body
; lives in wasm/glue.js (plain file, incbin-embedded below) - this module
; only carries the HTTP serving code.

%include "common/syscalls.inc"
%include "common/strings.inc"

extern client_fd
extern resp_buf
extern itoa_buf
extern cl_prefix, crlf2, cc_nocache
extern memcpy_adv, strcpy_adv
extern write_status_line
extern asx_send_status

section .data
    ; build-error file read by error_serve() (the dev loop writes it)
    err_file_path db "build/asx-error.txt", 0
    err_ct  db "Content-Type: text/plain; charset=utf-8", 13, 10, 0
    ERR_MAX equ 16384
    ; NOTE: JS uses double quotes only (fits db '...' without escapes)
    ; the renderer lives in wasm/glue/*.js - SEVEN plain-JS modules
    ; (real editor syntax highlighting, no db '...' escaping). Embedded
    ; with SEVEN consecutive incbins: nasm emits the bytes contiguously
    ; in this section, so glue_js points at the concatenated bundle and
    ; glue_js_len is their total length - no generated glue.js file, no
    ; Makefile cat step. The module ORDER below is the bundle order
    ; (const -> state -> mount -> shell -> spa -> overlay -> boot: const/
    ; state first, boot last). Paths resolve through -I asx / -I ...
    ; (root and tests Makefiles). The trailing NUL keeps glue_js_len
    ; unchanged (the old db blob ended with 0).
    glue_js:
        incbin "wasm/glue/const.js"
        incbin "wasm/glue/state.js"
        incbin "wasm/glue/mount.js"
        incbin "wasm/glue/shell.js"
        incbin "wasm/glue/spa.js"
        incbin "wasm/glue/overlay.js"
        incbin "wasm/glue/boot.js"
    db 0
    glue_js_len equ $ - glue_js - 1
    glue_ct db "Content-Type: text/javascript", 13, 10, 0
    sse_ct  db "Content-Type: text/event-stream", 13, 10, 0
    sse_cc  db "Cache-Control: no-cache", 13, 10, 0
    sse_body db "retry: 250", 10, 10, "data: ok", 10, 10
    sse_body_len equ $ - sse_body

section .bss
    err_body resb ERR_MAX

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
    call strcpy_adv               ; Content-Type: text/javascript
    mov r15, rax
    mov rdi, r15
    lea rsi, [cc_nocache]
    call strcpy_adv               ; Cache-Control: no-cache
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
; error_serve() - the build-error endpoint for the frontend overlay.
; Reads build/asx-error.txt (written by `asx dev` when a build fails).
; If the file exists: 200 + text/plain + contents. If not: 404. The
; glue polls this endpoint and mounts the error-overlay module.
; ----------------------------------------------------------------------
global error_serve
error_serve:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; open("build/asx-error.txt", O_RDONLY)
    mov rax, SYS_openat
    mov rdi, -100               ; AT_FDCWD
    lea rsi, [err_file_path]
    xor rdx, rdx                ; O_RDONLY
    syscall
    test rax, rax
    js .nf
    mov r12, rax                ; fd

    ; read up to ERR_MAX bytes
    xor r13, r13                ; total
.read:
    cmp r13, ERR_MAX
    jge .read_done
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [err_body + r13]
    mov rdx, ERR_MAX
    sub rdx, r13
    syscall
    test rax, rax
    jle .read_done
    add r13, rax
    jmp .read
.read_done:
    mov rax, SYS_close
    mov rdi, r12
    syscall

    ; build header in resp_buf
    lea r15, [resp_buf]
    call write_status_line        ; HTTP/1.1 200 OK\r\n
    mov rdi, r15
    lea rsi, [err_ct]
    call strcpy_adv               ; Content-Type: text/plain
    mov r15, rax
    mov rdi, r15
    lea rsi, [cc_nocache]
    call strcpy_adv               ; Cache-Control: no-cache
    mov r15, rax
    mov rdi, r15
    lea rsi, [cl_prefix]
    call strcpy_adv               ; Content-Length: 
    mov r15, rax
    mov rdi, r13                  ; body size
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
    lea rsi, [err_body]
    mov rdx, r13
    syscall
    test rax, rax
    js .err

    xor rax, rax
    jmp .out
.nf:
    ; 404 - no build error right now
    mov rdi, 404
    call asx_send_status
    mov rax, -1
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
