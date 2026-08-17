; src/http/getters.asm
; Accessors for parsed request state
; Uses http.inc (interface) - state symbols come from http_state.asm

%include "http/http.inc"

extern http_req_method
extern http_req_path
extern http_req_method_idx
extern http_body_offset
extern http_body_len
extern buffer

; http_get_method() -> rax = pointer to method string
global http_get_method
http_get_method:
    lea rax, [http_req_method]
    ret

; http_get_path() -> rax = pointer to path string
global http_get_path
http_get_path:
    lea rax, [http_req_path]
    ret

; http_get_method_idx() -> rax = method index or -1
global http_get_method_idx
http_get_method_idx:
    mov rax, [http_req_method_idx]
    ret

; http_get_body() -> rax = pointer to body in request buffer
global http_get_body
http_get_body:
    mov rax, [http_body_offset]
    add rax, buffer         ; body is at buffer + offset
    ret

; http_get_body_len() -> rax = body length in bytes
global http_get_body_len
http_get_body_len:
    mov rax, [http_body_len]
    ret
