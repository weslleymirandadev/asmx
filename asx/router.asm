; src/asx/router.asm
; Next.js-style router - dispatches the current request to the handler
; registered for its path + method.
;
; Route table: the `route` section, filled by src/app/*/route.s via the
; `route` macro (src/app/route.inc). GNU ld defines __start_route and
; __stop_route over it. Each entry is 48 bytes:
;   +0   dq path ptr
;   +8   dq GET handler     (0 = method not supported)
;   +16  dq POST handler
;   +24  dq PUT handler
;   +32  dq PATCH handler
;   +40  dq DELETE handler
;
; route_dispatch: never returns. It jmps into the handler (which must
; end with `jmp requests`) or responds 404/405 and jmps to `requests`.
; A custom 404 body comes from the reserved "/__not_found" route
; (src/app/not-found.s): when no path matches, the router sets
; resp_status=404 and dispatches to it.

%include "http/http.inc"

extern __start_route
extern __stop_route
extern __start_middleware
extern __stop_middleware
extern route            ; current request path (copied by core.asm)
extern http_get_method_idx
extern http_serve_static
extern strcmp
extern strncmp
extern strlen
extern asx_send_status
extern resp_status
extern requests
extern wasm_glue_serve
extern sse_serve
extern error_serve
extern slug_buf
extern slug_len

section .data
    nf_route_path db "/__not_found", 0
    glue_path     db "/_asx/glue.js", 0
    events_path   db "/_asx/events", 0
    error_path    db "/_asx/error", 0

section .text

global route_dispatch
route_dispatch:
    ; ------------------------------------------------------------------
    ; Middleware (src/middleware.s, Next.js middleware.ts style): if a
    ; `middleware` entry exists, run its handler BEFORE routing. We jmp
    ; into it with a CLEAN stack (no pushes above): the handler ends
    ; with `mw.next` (jmp middleware_continue -> back to routing) or
    ; responds itself (mw.redirect/mw.status/... -> jmp requests).
    ; ------------------------------------------------------------------
    mov rax, __start_middleware
    cmp rax, __stop_middleware
    jge middleware_continue   ; no middleware registered
    mov rbx, [__start_middleware]
    test rbx, rbx
    jz middleware_continue
    jmp rbx                   ; mw.next -> jmp middleware_continue

global middleware_continue
middleware_continue:
    push r12
    push r13
    mov r12, __start_route
    mov r13, __stop_route
.loop:
    cmp r12, r13
    jge .not_found
    mov rdi, route
    mov rsi, [r12]            ; entry path ptr
    call strcmp               ; clobbers rdi/rsi/rcx - r12/r13 safe
    test rax, rax
    jz .found
    ; dynamic route? pattern like "/profile/[id]" - the slug segment
    ; (between '[' and ']') matches any non-empty path segment
    mov rdi, route
    mov rsi, [r12]
    call route_match_dynamic  ; rax = 1 match (slug in slug_buf), 0 no
    test rax, rax
    jnz .found
    add r12, 48
    jmp .loop
.found:
    call http_get_method_idx
    test rax, rax
    js .method_not_allowed    ; unknown method (-1)
    cmp rax, HTTP_M_DELETE
    jg .method_not_allowed    ; HEAD/OPTIONS not dispatched yet
    shl rax, 3                ; handler slot = idx * 8
    add rax, 8                ; past the path ptr
    lea rbx, [r12 + rax]
    mov rax, [rbx]
    test rax, rax
    jz .method_not_allowed
    pop r13
    pop r12
    jmp rax
.method_not_allowed:
    mov rdi, 405
    call asx_send_status
    pop r13
    pop r12
    jmp requests
.not_found:
    ; framework virtual file: /_asx/events - the hot-reload event stream
    ; (EventSource; answers + closes, the browser reconnects on its own)
    lea rdi, [events_path]
    lea rsi, [route]
    call strcmp
    test rax, rax
    jnz .glue_check
    call sse_serve
    pop r13
    pop r12
    jmp requests
.glue_check:
    ; framework virtual file: /_asx/error - the build-error endpoint for
    ; the frontend overlay (reads build/asx-error.txt, 200 or 404)
    lea rdi, [error_path]
    lea rsi, [route]
    call strcmp
    test rax, rax
    jnz .glue_js_check
    call error_serve
    pop r13
    pop r12
    jmp requests
.glue_js_check:
    ; framework virtual file: /_asx/glue.js (the WASM UI renderer) -
    ; no public/ entry needed, the glue is part of the framework
    lea rdi, [glue_path]
    lea rsi, [route]
    call strcmp
    test rax, rax
    jnz .static_fallback
    call wasm_glue_serve
    pop r13
    pop r12
    jmp requests
.static_fallback:
    ; Next.js-style static fallback: no route matched, try public/<path>
    ; (user assets - images, videos) then static/<path> (route wasm).
    ; GET and HEAD only - static files are not endpoints for other methods.
    call http_get_method_idx
    test rax, rax
    jz .sf_get
    cmp rax, HTTP_M_HEAD
    jne .nf_route
.sf_get:
    lea rdi, [route]
    call http_serve_static
    test rax, rax
    jz .nf_served
.nf_route:
    ; custom 404: dispatch to the reserved "/__not_found" route if present
    mov rbx, __start_route
    mov r14, __stop_route
.nf_loop:
    cmp rbx, r14
    jge .nf_default
    lea rdi, [nf_route_path]
    mov rsi, [rbx]
    call strcmp
    test rax, rax
    jz .nf_found
    add rbx, 48
    jmp .nf_loop
.nf_found:
    mov qword [resp_status], 404
    mov rax, [rbx + 8]          ; GET handler of the not-found route
    test rax, rax
    jz .nf_default
    pop r13
    pop r12
    jmp rax
.nf_default:
    mov rdi, 404
    call asx_send_status
    pop r13
    pop r12
    jmp requests
.nf_served:
    pop r13
    pop r12
    jmp requests

; ----------------------------------------------------------------------
; route_match_dynamic(rdi = path, rsi = pattern) -> rax = 1 match / 0 no
; Pattern: "/profile/[id]" - the "[...]" segment matches any non-empty
; path segment. On a match the slug value is copied to slug_buf (null
; terminated) and slug_len is set. Only the FIRST bracket pair is used;
; the pattern may have a suffix after "]" (e.g. "/blog/[id]/edit").
; ----------------------------------------------------------------------
global route_match_dynamic
route_match_dynamic:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi              ; path
    mov r13, rsi              ; pattern
    ; find '[' in pattern -> prefix = [0, r14)
    xor r14, r14
.pf_scan:
    mov al, [r13 + r14]
    test al, al
    jz .no_match              ; no '[' -> not a dynamic pattern
    cmp al, '['
    je .pf_found
    inc r14
    jmp .pf_scan
.pf_found:
    ; find ']' after it -> suffix = [r15, ...) (may be empty)
    lea r15, [r13 + r14 + 1]
.sf_scan:
    mov al, [r15]
    test al, al
    jz .no_match              ; no ']' -> malformed pattern
    cmp al, ']'
    je .sf_found
    inc r15
    jmp .sf_scan
.sf_found:
    inc r15                   ; suffix starts after ']'
    ; path must start with the prefix
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call strncmp
    test rax, rax
    jnz .no_match
    ; path must end with the suffix (if any)
    mov rdi, r15
    call strlen               ; suffix len
    mov rbx, rax              ; suffix len (rbx callee-saved)
    mov rdi, r12
    call strlen               ; path len
    mov rcx, rax              ; path len
    ; slug = path[prefix_len .. path_len - suffix_len), must be non-empty
    mov rax, rcx
    sub rax, r14              ; path_len - prefix_len
    sub rax, rbx              ; - suffix_len = slug len
    test rax, rax
    jle .no_match
    cmp rax, 255
    jg .no_match              ; slug too big for slug_buf
    ; check the suffix at path end (only if non-empty)
    test rbx, rbx
    jz .have_suf
    lea rdi, [r12 + rcx]
    sub rdi, rbx              ; path + path_len - suffix_len
    mov rsi, r15
    mov rdx, rbx
    call strncmp
    test rax, rax
    jnz .no_match
.have_suf:
    ; strncmp clobbered rax/rcx - recompute the slug length
    mov rdi, r12
    call strlen               ; path len (rax)
    sub rax, r14              ; - prefix_len
    sub rax, rbx              ; - suffix_len = slug len
    ; a slug with a '.' would be a static asset (e.g. "/profile/page.wasm")
    ; - reject so the static fallback serves the file instead
    mov rcx, rax
    lea rdx, [r12 + r14]      ; slug start (rdx dead after strncmp)
.slug_dot:
    test rcx, rcx
    jz .have_slug
    cmp byte [rdx + rcx - 1], '.'
    je .no_match
    dec rcx
    jmp .slug_dot
.have_slug:
    ; copy the slug into slug_buf (rbx = slug start, rbx no longer
    ; needed for the suffix length)
    mov [slug_len], rax
    lea rbx, [r12 + r14]      ; slug start
    xor rcx, rcx
.cp:
    cmp rcx, [slug_len]
    jge .cp_done
    mov al, [rbx + rcx]
    mov [slug_buf + rcx], al
    inc rcx
    jmp .cp
.cp_done:
    mov byte [slug_buf + rcx], 0
    mov rax, 1
    jmp .out
.no_match:
    xor rax, rax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
