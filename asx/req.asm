; src/asx/req.asm
; Request object wrappers - hide the http state behind the dot-notation
; API (req.body, req.get, ...). The json domain stays pure: these wrappers
; are the only glue between http state and json_find.
;
; Exported:
;   asx_req_body()    -> rax = POST body ptr
;   asx_req_body_len() -> rax = POST body len
;   asx_req_get(rdi = key)  -> json_find over the body
;                               rax = value ptr, rdx = len, rcx = type,
;                               rax = -1 if missing
;   asx_req_has(rdi = key)  -> rax = 1 if the key exists, 0 otherwise

%include "common/common.inc"

extern http_get_body
extern http_get_body_len
extern json_find

section .text

global asx_req_body
asx_req_body:
    jmp http_get_body         ; tail call: rax = body ptr

global asx_req_body_len
asx_req_body_len:
    jmp http_get_body_len     ; tail call: rax = body len

global asx_req_get
asx_req_get:
    push rbx
    push r12
    mov r12, rdi              ; key (callee-saved)
    call http_get_body
    mov rbx, rax              ; body ptr
    call http_get_body_len
    mov rsi, rax              ; body len
    mov rdi, rbx
    mov rdx, r12              ; key
    call json_find
    pop r12
    pop rbx
    ret

global asx_req_has
asx_req_has:
    call asx_req_get
    cmp rax, -1
    je .no
    mov rax, 1
    ret
.no:
    xor rax, rax
    ret
