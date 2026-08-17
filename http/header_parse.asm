; src/http/header_parse.asm
; HTTP headers/body parser
; Skips the request line, scans header lines until the blank line,
; extracts Content-Length and records where the body starts.
; Uses http.inc (interface) - state from state.asm

%include "http/http.inc"

extern http_body_offset
extern http_body_len
extern http_content_length

section .data
    content_length_hdr db "Content-Length:", 0
    content_length_hdr_len equ 15

section .text

; Skip spaces in a string
; Arguments: rdi = pointer
; Returns: rdi = pointer past leading spaces
skip_spaces:
    cmp byte [rdi], ' '
    jne .done
    inc rdi
    jmp skip_spaces
.done:
    ret

; Parse HTTP headers, find body
; Arguments: rdi = buffer, rsi = buffer length
; Returns: rax = 0 on success, -1 on error
; Side effects: sets http_body_offset, http_body_len, http_content_length
; Assumes the request line is the first line; headers follow until a blank
; line (CRLF or bare LF). Body starts right after the blank line.
global http_parse_headers
http_parse_headers:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi              ; buffer
    mov r13, rsi              ; buffer length
    mov qword [http_content_length], -1

    ; ---- Skip request line (find first LF) ----
    xor r14, r14              ; offset
.skip_req_line:
    cmp r14, r13
    jge .error
    cmp byte [r12 + r14], 10
    je .headers_start
    inc r14
    jmp .skip_req_line

.headers_start:
    inc r14                   ; skip the LF

    ; ---- Scan header lines until blank line ----
.header_loop:
    cmp r14, r13
    jge .error

    ; Blank line? Line starts with LF (bare) or CRLF
    mov al, [r12 + r14]
    cmp al, 10
    je .body_found
    cmp al, 13
    jne .parse_header_line

    ; CRLF blank line: expect CR LF
    inc r14
    cmp r14, r13
    jge .error
    cmp byte [r12 + r14], 10
    jne .error
    inc r14
    jmp .body_found

.parse_header_line:
    ; Find end of this line (LF)
    mov rbx, r14              ; line start offset
.find_line_end:
    cmp r14, r13
    jge .error
    cmp byte [r12 + r14], 10
    je .line_end_found
    inc r14
    jmp .find_line_end

.line_end_found:
    ; line = [rbx, r14)
    ; Check "Content-Length:" prefix
    mov rdi, r12
    add rdi, rbx
    mov rsi, content_length_hdr
    mov rdx, content_length_hdr_len
    call strncmp
    test rax, rax
    jnz .next_header

    ; Parse value: skip spaces after colon, then atoi
    lea rdi, [r12 + rbx + content_length_hdr_len]
    call skip_spaces
    call atoi
    mov [http_content_length], rax

.next_header:
    inc r14                   ; skip the LF
    jmp .header_loop

.body_found:
    ; Body starts at r14
    mov [http_body_offset], r14
    mov rax, r13
    sub rax, r14
    mov [http_body_len], rax
    xor rax, rax              ; success
    jmp .done

.error:
    mov rax, -1

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
