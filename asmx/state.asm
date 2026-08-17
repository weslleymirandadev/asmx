; src/asmx/state.asm
; asmx shared state - single source of truth for data/bss
; Do NOT %include this file - reference its symbols via extern.
; This is the ONLY file that defines these symbols.

%include "common/syscalls.inc"

section .data
    ; HTTP response parts
    http_200    db "HTTP/1.1 200 OK", 13, 10
    http_200_len equ $ - http_200
    resp_status dq 200        ; status line code used by send_* (router sets 404 for not-found)

    ct_json     db "Content-Type: application/json", 13, 10
    ct_json_len equ $ - ct_json
    ct_text     db "Content-Type: text/plain", 13, 10
    ct_text_len equ $ - ct_text
    ct_html     db "Content-Type: text/html", 13, 10
    ct_html_len equ $ - ct_html

    cl_prefix   db "Content-Length: ", 0
    crlf2       db 13, 10, 13, 10       ; end of headers

    ; Status code -> reason table (dq code, dq reason_ptr = 16 bytes/entry)
    status_table:
        dq 200, st_200
        dq 400, st_400
        dq 404, st_404
        dq 405, st_405
        dq 500, st_500
    status_count equ ($ - status_table) / 16
    st_200 db " OK", 13, 10, 0
    st_400 db " Bad Request", 13, 10, 0
    st_404 db " Not Found", 13, 10, 0
    st_405 db " Method Not Allowed", 13, 10, 0
    st_500 db " Internal Server Error", 13, 10, 0

    http_prefix db "HTTP/1.1 ", 0
    cl_zero     db "Content-Length: 0", 13, 10, 13, 10, 0

section .bss
    server_fd    resq 1
    client_fd    resq 1
    asmx_handler resq 1
    buffer       resb 4096
    route        resb 256
    resp_buf     resb 512
    itoa_buf     resb 12

; Export everything the framework needs
global http_200, http_200_len
global resp_status
global ct_json, ct_json_len, ct_text, ct_text_len, ct_html, ct_html_len
global cl_prefix, crlf2
global status_table, status_count
global http_prefix, cl_zero
global server_fd, client_fd, asmx_handler
global buffer, route, resp_buf, itoa_buf
