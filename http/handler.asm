; src/http/handler.asm
; HTTP request handler - orchestrator
; Integrates request_line, header_parse, method_check, response modules
; Called by main.asm with client_fd in rdi

%include "http/http.inc"

global handle_client
extern buffer
extern read_error
extern write_error
extern http_parse_request_line
extern http_parse_headers
extern http_get_path
extern http_get_method_idx
extern http_get_body
extern http_get_body_len
extern http_send_response
extern http_send_method_denied
extern http_send_not_found
extern http_response_200
extern http_response_200_len

section .data
    body_prefix db "[POST body] "
    body_prefix_len equ $ - body_prefix
    nl db 10

section .text

; write_stderr_buf(rdi = buffer, rsi = len) - write raw bytes to fd 2
write_stderr_buf:
    mov rax, SYS_write
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, 2
    syscall
    ret

; handle_client(client_fd) - read request, parse, respond
handle_client:
    ; Save client_fd and bytes_read across calls (callee-saved)
    push r12
    push r13
    mov r12, rdi              ; client_fd
    xor r13, r13              ; bytes_read

    ; Read the HTTP request
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buffer]
    mov rdx, 4096
    syscall
    check_syscall read_error
    mov r13, rax              ; save bytes read

    ; Parse the request line (buffer, bytes_read)
    mov rdi, buffer
    mov rsi, r13
    call http_parse_request_line
    test rax, rax
    js .send_method_denied

    ; Parse headers + find body
    mov rdi, buffer
    mov rsi, r13
    call http_parse_headers
    test rax, rax
    js .send_not_found

    ; If POST, dump the body to stderr (proves header/body parsing works)
    call http_get_method_idx
    cmp rax, HTTP_M_POST
    jne .check_path

    mov rdi, body_prefix
    mov rsi, body_prefix_len
    call write_stderr_buf
    call http_get_body
    mov rdi, rax
    call http_get_body_len
    mov rsi, rax
    call write_stderr_buf
    mov rdi, nl
    mov rsi, 1
    call write_stderr_buf

.check_path:
    ; Check if path is valid (non-empty)
    call http_get_path
    mov rdi, rax
    call strlen
    test rax, rax
    jz .send_not_found

    ; Send 200 OK response
    mov rdi, r12
    lea rsi, [http_response_200]
    mov rdx, http_response_200_len
    call http_send_response
    jmp .done

.send_method_denied:
    mov rdi, r12
    call http_send_method_denied
    jmp .done

.send_not_found:
    mov rdi, r12
    call http_send_not_found

.done:
    pop r13
    pop r12
    ret
