; __asmx__/asmx.inc
; asmx - mini web framework over the assembly HTTP server
; Package root: __asmx__/ (npm-style). App code lives in src/
; (src/main.asm + src/app/**/route.s). Include from anywhere with
;   %include "asmx.inc"     (ASFLAGS: -I __asmx__)
;
; Usage in your app:
;
;   section .data
;       my_json db '{"ok": true}', 0
;
;   section .text
;   global _start
;   _start:
;       listen 8080               ; create socket, enter accept loop
;
;       ; handler below runs once per request
;       cmp route, "/api/user"    ; strcmp against current path
;       je r_user
;       send_status 404
;       jmp requests              ; back to accept loop (requests is reserved)
;
;   r_user:
;       send_json my_json
;       jmp requests
;
; NOTE: `requests` is a reserved symbol (the accept loop). Do NOT define
; a label named `requests` in your app - use `jmp requests` to return
; to the accept loop after responding.

%ifndef ASMX_INC
%define ASMX_INC

%include "common/common.inc"
%include "net/net.inc"
%include "http/http.inc"

; ----------------------------------------------------------------------
; Public API (defined in src/asmx/*.asm)
; ----------------------------------------------------------------------
; core.asm    : asmx_listen, requests (accept loop label)
; router.asm  : route_dispatch (Next.js-style path+method dispatch)
; send.asm    : asmx_send_json, asmx_send_text, asmx_send_html, asmx_send_status
; state.asm   : route (current path buffer), buffer, resp_buf, client_fd,
;               http_200, ct_json, ct_text, ct_html, status_table...
; helpers.asm : memcpy_adv, strcpy_adv (internal)
extern asmx_listen
extern asmx_send_json
extern asmx_send_text
extern asmx_send_html
extern asmx_send_status
extern asmx_send_bytes
extern route_dispatch
extern route
extern requests
; Request accessors available to handlers (http/getters.asm)
extern http_get_method_idx
extern http_get_body
extern http_get_body_len
; Content-type templates (asmx/state.asm) - used by send_*_bytes macros
extern ct_json, ct_json_len

; ----------------------------------------------------------------------
; listen PORT - create listening socket and enter the accept loop.
; The code that follows the macro runs once per request.
; ----------------------------------------------------------------------
%macro listen 1
    mov rdi, %1
    call asmx_listen          ; never returns
%endmacro

; ----------------------------------------------------------------------
; cmp a, b - if b is a string literal, compares `route` against it with
; strcmp (ZF set if equal, so `je`/`jne` work). Otherwise falls back to
; the native cmp instruction.
; Strings are emitted inline with a jump-over-data pattern.
; ----------------------------------------------------------------------
%macro cmp 2
    %ifstr %2
        jmp %%skip
    %%str:
        db %2, 0
    %%skip:
        lea rsi, [%%str]
        mov rdi, route
        call strcmp
        test rax, rax
    %else
        cmp %1, %2
    %endif
%endmacro

; ----------------------------------------------------------------------
; Response helpers - send a 200 with the given null-terminated payload.
; ----------------------------------------------------------------------
%macro send_json 1
    mov rdi, %1
    call asmx_send_json
%endmacro

%macro send_text 1
    mov rdi, %1
    call asmx_send_text
%endmacro

%macro send_html 1
    mov rdi, %1
    call asmx_send_html
%endmacro

; ----------------------------------------------------------------------
; send_status CODE - respond with a status code and empty body
; (e.g. send_status 404)
; ----------------------------------------------------------------------
%macro send_status 1
    mov rdi, %1
    call asmx_send_status
%endmacro

; ----------------------------------------------------------------------
; send_json_bytes PTR, LEN - respond 200 with raw JSON of explicit length
; (for request bodies / data without null terminator)
; ----------------------------------------------------------------------
%macro send_json_bytes 2
    mov rdi, %1
    mov rsi, %2
    lea rdx, [ct_json]
    mov rcx, ct_json_len
    call asmx_send_bytes
%endmacro

; ----------------------------------------------------------------------
; body_get_json BODY_PTR_VAR, BODY_LEN_VAR - load the request body into
; two user-reserved qwords (declare them in your .bss, resq 1 each).
;   section .bss
;       req_body resq 1
;       req_len  resq 1
;   section .POST
;   post_user:
;       body_get_json req_body, req_len
;       send_json_bytes [req_body], [req_len]   ; echo the body back
; BODY_LEN_VAR can be 0 (POST without body).
; ----------------------------------------------------------------------
%macro body_get_json 2
    call http_get_body
    mov [%1], rax
    call http_get_body_len
    mov [%2], rax
%endmacro

; ----------------------------------------------------------------------
; File routes (Next.js-style) - route declaration
;   route "/api/user", get_user, post_user   (0 = method not supported)
;
;   section .GET
;   get_user:
;       send_json user_data
;       jmp requests
;
; Emits one 24-byte entry in the `route` section (dq path, GET, POST);
; GNU ld defines __start_route/__stop_route over it and the router
; (asmx/router.asm) scans it to dispatch. `.GET`/`.POST` are pre-declared
; as CODE sections below - NASM defaults unknown section names to DATA,
; which would make handlers non-executable (segfault).
; ----------------------------------------------------------------------
section .GET exec progbits align=16
section .POST exec progbits align=16

%macro route 1-3 0
    section .data
    %%path: db %1, 0
    section route
    dq %%path, %2, %3
    section .text
%endmacro

%endif
