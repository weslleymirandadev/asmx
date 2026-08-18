; src/asmx/send.asm
; asmx response senders - build header in resp_buf, write header + body.
; The status line comes from [resp_status] (state.asm, default 200) so
; the router can send a custom 404 body (not-found route).

%include "common/common.inc"

extern client_fd
extern resp_buf
extern itoa_buf
extern resp_status
extern ct_json, ct_json_len, ct_text, ct_text_len, ct_html, ct_html_len
extern cl_prefix, crlf2, conn_close
extern http_prefix, cl_zero
extern status_table, status_count
extern memcpy_adv, strcpy_adv

; asmx_send_json/text/html(rdi = body) - respond with the current status
global asmx_send_json
asmx_send_json:
    lea rsi, [ct_json]
    mov rdx, ct_json_len
    jmp asmx_send_common

global asmx_send_text
asmx_send_text:
    lea rsi, [ct_text]
    mov rdx, ct_text_len
    jmp asmx_send_common

global asmx_send_html
asmx_send_html:
    lea rsi, [ct_html]
    mov rdx, ct_html_len
    jmp asmx_send_common

; write_status_line() - writes "HTTP/1.1 <code><reason>\r\n" at [r15]
; using [resp_status] and status_table; r15 = advanced pos.
; Clobbers rax, rcx, rdx, rdi, rsi, r10 - preserves r12/r13/r14/rbx.
; Exported so static.asm can build file response headers with it.
global write_status_line
write_status_line:
    mov rdi, r15
    lea rsi, [http_prefix]
    call strcpy_adv
    mov r15, rax

    ; code ascii (itoa clobbers rdi/rsi - recompute)
    mov rdi, [resp_status]
    lea rsi, [itoa_buf]
    call itoa
    mov rsi, rax
    lea rdx, [itoa_buf + 11]
    sub rdx, rsi
    mov rdi, r15
    call memcpy_adv
    mov r15, rax

    ; reason: search status_table for the code (r10 walker)
    mov r10, status_table
    mov ecx, status_count
.lookup:
    test ecx, ecx
    jz .done
    mov eax, [resp_status]
    cmp [r10], eax
    je .found
    add r10, 16                   ; dq code + dq ptr
    dec ecx
    jmp .lookup
.found:
    mov rsi, [r10 + 8]            ; reason ptr (includes CRLF)
    mov rdi, r15
    call strcpy_adv
    mov r15, rax
.done:
    ; Connection: close - the server handles ONE request per connection.
    ; Without it, HTTP/1.1 keep-alive makes the browser REUSE the socket
    ; on refresh: the accept loop waits for a NEW connection and never
    ; reads the reused one -> browser timeout. With Connection: close the
    ; browser opens a fresh connection for every request.
    mov rdi, r15
    lea rsi, [conn_close]
    call strcpy_adv
    mov r15, rax
    ret

; asmx_send_common(rdi = body, rsi = content-type, rdx = ct_len)
; asmx_send_bytes(rdi = body, rsi = body_len, rdx = content-type, rcx = ct_len)
; Both build the header in resp_buf (write pos tracked in r15), then write
; header + body to client_fd. send_bytes takes an explicit length so raw
; request bodies (no null terminator) can be echoed back.
asmx_send_common:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                  ; body
    mov r13, rsi                  ; content-type ptr
    mov r14, rdx                  ; content-type len

    ; body length (null-terminated string)
    mov rdi, r12
    call strlen
    mov rbx, rax                  ; body len
    jmp send_build

global asmx_send_bytes
asmx_send_bytes:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                  ; body ptr
    mov rbx, rsi                  ; body len (explicit)
    mov r13, rdx                  ; content-type ptr
    mov r14, rcx                  ; content-type len

send_build:
    ; Build header in resp_buf, tracking write pos in r15
    lea r15, [resp_buf]
    call write_status_line        ; "HTTP/1.1 <code><reason>\r\n" from resp_status
    mov rdi, r15
    mov rsi, r13
    mov rdx, r14
    call memcpy_adv
    mov r15, rax
    mov rdi, r15
    lea rsi, [cl_prefix]
    call strcpy_adv
    mov r15, rax

    ; Content-Length number (itoa clobbers rdi/rsi - use saved r15)
    mov rdi, rbx
    lea rsi, [itoa_buf]
    call itoa                     ; rax = ptr to first digit
    mov rsi, rax
    lea rdx, [itoa_buf + 11]
    sub rdx, rsi                  ; number length
    mov rdi, r15
    call memcpy_adv
    mov r15, rax

    ; end of headers
    mov rdi, r15
    lea rsi, [crlf2]
    mov rdx, 4
    call memcpy_adv
    mov r15, rax

    ; header length = write pos - resp_buf
    lea rax, [resp_buf]
    sub r15, rax

    ; write header
    mov rax, SYS_write
    mov rdi, [client_fd]
    lea rsi, [resp_buf]
    mov rdx, r15
    syscall

    ; write body
    mov rax, SYS_write
    mov rdi, [client_fd]
    mov rsi, r12
    mov rdx, rbx
    syscall

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; asmx_send_status(rdi = code) - respond with a status code, empty body
global asmx_send_status
asmx_send_status:
    push rbx
    push r12
    push r13
    push r15
    mov [resp_status], rdi

    ; Build header: status line + "Content-Length: 0\r\n\r\n"
    lea r15, [resp_buf]
    call write_status_line

    mov rdi, r15
    lea rsi, [cl_zero]
    call strcpy_adv
    mov r15, rax

    ; header length = write pos - resp_buf
    lea rax, [resp_buf]
    sub r15, rax

    ; write
    mov rax, SYS_write
    mov rdi, [client_fd]
    lea rsi, [resp_buf]
    mov rdx, r15
    syscall

    pop r15
    pop r13
    pop r12
    pop rbx
    ret
