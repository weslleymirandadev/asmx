; src/http/headers.asm
; Request header accessors - for the middleware (and any handler).
; header_parse.asm only extracts Content-Length; these scan the raw
; request buffer for any header by name (case-insensitive) and for a
; cookie by name (case-sensitive value, like the browser).
;
;   http_get_header(rdi = name) -> rax = value ptr (hdr_val), rdx = len
;                                  rax = 0 if the header is absent
;   http_get_cookie(rdi = name) -> rax = value ptr (hdr_val), rdx = len
;                                  rax = 0 if the cookie is absent
;
; Both write into hdr_val (http/state.asm, 256 bytes, null-terminated).
; The name must be a null-terminated string (string literal or label).
; Header names are matched case-insensitively ("cookie" == "Cookie").
; Cookie names are matched exactly, up to ';' (the cookie-pair separator).

%include "http/http.inc"

extern buffer
extern http_body_offset
extern hdr_val
extern strcpy_adv
extern strstr

section .text

; ----------------------------------------------------------------------
; tolower(rdi = char ptr) -> al = lowercase char
; ----------------------------------------------------------------------
tolower:
    mov al, [rdi]
    cmp al, 'A'
    jb .done
    cmp al, 'Z'
    ja .done
    add al, 32
.done:
    ret

; ----------------------------------------------------------------------
; http_get_header(rdi = name) -> rax = value ptr / 0, rdx = len
; Scans the request buffer line by line (after the request line, before
; the body) for "<name>:" (case-insensitive), copies the trimmed value
; into hdr_val and returns its pointer + length.
; ----------------------------------------------------------------------
global http_get_header
http_get_header:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi              ; header name (callee-saved)
    mov r13, buffer
    mov r14, [http_body_offset]

    ; find the end of the request line (first LF)
    xor r15, r15
.req_line:
    cmp r15, r14
    jge .not_found
    cmp byte [r13 + r15], 10
    je .req_line_end
    inc r15
    jmp .req_line
.req_line_end:
    inc r15                   ; start of the first header line

.header_loop:
    ; reached the body / end of headers?
    cmp r15, r14
    jge .not_found
    ; blank line (CRLF or bare LF) = end of headers
    cmp byte [r13 + r15], 13
    je .not_found
    cmp byte [r13 + r15], 10
    je .not_found

    ; line = [r15, line_end); keep ABSOLUTE pointers
    lea rbx, [r13 + r15]      ; line start ptr (callee-saved)
.line_scan:
    cmp r15, r14
    jge .line_done
    cmp byte [r13 + r15], 10
    je .line_done
    inc r15
    jmp .line_scan
.line_done:
    lea r9, [r13 + r15]       ; line end ptr (at LF, absolute)

    ; compare the name prefix, case-insensitive
    mov rcx, r12              ; name ptr
    mov rdx, rbx              ; line ptr
.cmp_name:
    cmp byte [rcx], 0
    je .name_matched          ; name fully consumed
    ; tolower(line char)
    mov rdi, rdx
    call tolower              ; al = tolower(line)
    mov r8b, al
    ; tolower(name char)
    mov rdi, rcx
    call tolower              ; al = tolower(name)
    cmp r8b, al
    jne .next_header
    inc rcx
    inc rdx
    jmp .cmp_name
.name_matched:
    ; expect ':' after the name
    cmp byte [rdx], ':'
    jne .next_header
    inc rdx                   ; skip ':'
.skip_sp:
    cmp rdx, r9
    jge .not_found
    cmp byte [rdx], ' '
    jne .value_start
    inc rdx
    jmp .skip_sp
.value_start:
    ; value = [rdx, r9), trimmed of trailing CR
    mov r8, rdx               ; value start
.value_copy:
    cmp r8, r9
    jge .value_done
    mov al, [r8]
    cmp al, 13
    je .value_done
    cmp al, 10
    je .value_done
    inc r8
    jmp .value_copy
.value_done:
    ; len = r8 - rdx, cap at 255
    mov rax, r8
    sub rax, rdx
    test rax, rax
    jle .not_found            ; empty value = treat as absent
    cmp rax, 255
    jle .len_ok
    mov rax, 255
.len_ok:
    mov rbx, rax              ; save len (rbx was line start, dead now)
    ; copy into hdr_val
    xor rcx, rcx
.copy_loop:
    cmp rcx, rbx
    jge .copy_done
    mov al, [rdx + rcx]
    mov [hdr_val + rcx], al
    inc rcx
    jmp .copy_loop
.copy_done:
    mov byte [hdr_val + rcx], 0
    lea rax, [hdr_val]
    mov rdx, rbx              ; len
    jmp .out

.next_header:
    inc r15                   ; skip the LF
    jmp .header_loop

.not_found:
    xor rax, rax
    xor rdx, rdx
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; http_get_cookie(rdi = name) -> rax = value ptr / 0, rdx = len
; Looks for the Cookie header, searches it for "<name>=" (strstr) and
; copies the value up to the next ';' into hdr_val.
; ----------------------------------------------------------------------
global http_get_cookie
http_get_cookie:
    push rbx
    push r12
    push r13
    mov r12, rdi              ; cookie name (callee-saved)

    ; find the Cookie header (case-insensitive)
    lea rdi, [cookie_hdr]
    call http_get_header
    test rax, rax
    jz .not_found
    ; rax = cookie header value ptr (hdr_val, null-terminated)
    mov rbx, rax              ; cookie string ptr (callee-saved)

    ; build "<name>=" in cookie_needle
    lea rdi, [cookie_needle]
    mov rsi, r12
    call strcpy_adv           ; rax = needle end
    mov byte [rax], '='
    mov byte [rax + 1], 0

    ; strstr(cookie, "<name>=")
    mov rdi, rbx
    lea rsi, [cookie_needle]
    call strstr
    test rax, rax
    jz .not_found

    ; value starts after "<name>=" (strstr ptr in rax)
    mov rbx, rax              ; save match ptr (callee-saved)
    mov rdi, r12
    call strlen
    lea rbx, [rbx + rax + 1]  ; value start ptr (skip name + '=')

    ; copy value up to ';' or end of the cookie string
    xor rcx, rcx
.copy_loop:
    cmp rcx, 255
    jge .copy_done
    mov al, [rbx + rcx]
    test al, al
    jz .copy_done
    cmp al, ';'
    je .copy_done
    mov [hdr_val + rcx], al
    inc rcx
    jmp .copy_loop
.copy_done:
    test rcx, rcx
    jle .not_found
    mov byte [hdr_val + rcx], 0
    lea rax, [hdr_val]
    mov rdx, rcx
    jmp .out

.not_found:
    xor rax, rax
    xor rdx, rdx
.out:
    pop r13
    pop r12
    pop rbx
    ret

section .data
    cookie_hdr db "Cookie", 0

section .bss
    cookie_needle resb 64
