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
; A custom 404 body comes from the reserved "/__not_found" route
; (src/app/not-found.s): when no path matches, the router sets
; resp_status=404 and dispatches to it.

%include "http/http.inc"

extern __start_route
extern __stop_route
extern route            ; current request path (copied by core.asm)
extern http_get_method_idx
extern strcmp
extern asmx_send_status
extern resp_status
extern requests

section .data
    nf_route_path db "/__not_found", 0

section .text

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
    add rbx, 24
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
    call asmx_send_status
    pop r13
    pop r12
    jmp requests
