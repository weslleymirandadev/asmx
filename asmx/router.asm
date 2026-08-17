; src/asmx/router.asm
; Next.js-style router - dispatches the current request to the handler
; registered for its path + method.
;
; Route table: the `route` section, filled by src/app/*/route.s via the
; `route` macro (src/app/route.inc). GNU ld defines __start_route and
; __stop_route over it. Each entry is 24 bytes:
;   +0   dq path ptr
;   +8   dq GET handler    (0 = method not supported)
;   +16  dq POST handler   (0 = method not supported)
;
; route_dispatch: never returns. It jmps into the handler (which must
; end with `jmp requests`) or responds 404/405 and jmps to `requests`.

%include "http/http.inc"

extern __start_route
extern __stop_route
extern route            ; current request path (copied by core.asm)
extern http_get_method_idx
extern strcmp
extern asmx_send_status
extern requests

global route_dispatch
route_dispatch:
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
    add r12, 24
    jmp .loop
.found:
    call http_get_method_idx
    test rax, rax
    jz .get
    cmp rax, HTTP_M_POST
    je .post
    jmp .method_not_allowed
.get:
    mov rax, [r12 + 8]
    test rax, rax
    jz .method_not_allowed
    pop r13
    pop r12
    jmp rax
.post:
    mov rax, [r12 + 16]
    test rax, rax
    jz .method_not_allowed
    pop r13
    pop r12
    jmp rax
.method_not_allowed:
    mov rdi, 405
    call asmx_send_status
    pop r13
    pop r12
    jmp requests
.not_found:
    mov rdi, 404
    call asmx_send_status
    pop r13
    pop r12
    jmp requests
