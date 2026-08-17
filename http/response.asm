; src/http/response.asm
; HTTP response sender functions
; Uses http.inc (interface) - templates from http_state.asm

%include "http/http.inc"

extern http_response_405
extern http_response_405_len
extern http_response_404
extern http_response_404_len
extern write_error

section .text

; Send HTTP response to client
; Arguments: rdi = client_fd, rsi = response buffer, rdx = response length
global http_send_response
http_send_response:
    push rax
    push rdi
    mov rax, SYS_write
    syscall
    pop rdi
    pop rax
    check_syscall write_error
    ret

; Send 405 Method Not Allowed response
; Arguments: rdi = client_fd
global http_send_method_denied
http_send_method_denied:
    mov rsi, http_response_405
    mov rdx, http_response_405_len
    call http_send_response
    ret

; Send 404 Not Found response
; Arguments: rdi = client_fd
global http_send_not_found
http_send_not_found:
    mov rsi, http_response_404
    mov rdx, http_response_404_len
    call http_send_response
    ret
