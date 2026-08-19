; src/http/state.asm
; Single source of truth for HTTP shared state (data + bss)
; Do NOT %include this file - reference its symbols via extern.
; This is the ONLY file that defines these symbols.

%include "http/http.inc"

section .data
    ; Method strings - index order MUST match HTTP_M_* in http.inc
    http_method_get     db "GET", 0
    http_method_post    db "POST", 0
    http_method_put     db "PUT", 0
    http_method_patch   db "PATCH", 0
    http_method_delete  db "DELETE", 0
    http_method_head    db "HEAD", 0
    http_method_options db "OPTIONS", 0

    ; PIE-safe method table: 32-bit offsets, resolved with lea
    http_method_table:
        dd http_method_get - http_method_table
        dd http_method_post - http_method_table
        dd http_method_put - http_method_table
        dd http_method_patch - http_method_table
        dd http_method_delete - http_method_table
        dd http_method_head - http_method_table
        dd http_method_options - http_method_table
    http_method_count equ ($ - http_method_table) / 4

    ; Delimiters
    http_space_char   db 32
    http_newline_char db 10
    http_cr_char      db 13

    ; Response templates
    http_response_200:
        db "HTTP/1.1 200 OK", 13, 10
        db "Content-Type: text/plain", 13, 10
        db "Content-Length: 13", 13, 10
        db 13, 10
        db "Hello, World!"
    http_response_200_len equ $ - http_response_200

    http_response_405:
        db "HTTP/1.1 405 Method Not Allowed", 13, 10
        db "Content-Length: 0", 13, 10
        db 13, 10
    http_response_405_len equ $ - http_response_405

    http_response_404:
        db "HTTP/1.1 404 Not Found", 13, 10
        db "Content-Length: 0", 13, 10
        db 13, 10
    http_response_404_len equ $ - http_response_404

section .bss
    ; Parsed request fields
    http_req_method    resb 16
    http_req_path      resb 256
    http_req_version   resb 16
    http_req_method_idx resq 1

    ; Header/body parsing state (set by header_parse.asm)
    http_body_offset   resq 1   ; byte offset of body in request buffer
    http_body_len      resq 1   ; body length in bytes
    http_content_length resq 1  ; parsed Content-Length header (-1 if absent)

    ; Extracted header/cookie value (http/headers.asm) - null-terminated
    hdr_val          resb 256

    ; Line scanning state
    http_line_start    resq 1
    http_line_end      resq 1
    http_line_count    resq 1

; Export everything the package needs
global http_method_get, http_method_post, http_method_put
global http_method_patch, http_method_delete
global http_method_head, http_method_options
global http_method_table, http_method_count
global http_space_char, http_newline_char, http_cr_char
global http_response_200, http_response_200_len
global http_response_405, http_response_405_len
global http_response_404, http_response_404_len
global http_req_method, http_req_path, http_req_version
global http_req_method_idx
global http_body_offset, http_body_len, http_content_length
global hdr_val
global http_line_start, http_line_end, http_line_count
