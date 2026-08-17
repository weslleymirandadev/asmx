; src/asmx/core.asm
; asmx runtime - the framework engine
;
; Flow:
;   user code:  listen 8080          -> asmx_listen grabs return address as
;                                      handler, creates socket, falls into
;                                      `requests` accept loop
;   requests:   accept -> read -> parse -> copy path to `route` -> jmp handler
;   handler:    user code (cmp route / send_json / ...) ends with `jmp requests`
;
; Exported for user apps:
;   asmx_listen, requests (accept loop label)

%include "common/common.inc"
%include "net/net.inc"
%include "http/http.inc"

extern socket_bind_listen
extern http_parse_request_line
extern http_parse_headers
extern http_get_path
extern strlen
extern strncpy
extern itoa
extern itoa_buf
extern accept_error
extern read_error
extern server_fd, client_fd, asmx_handler
extern buffer, route, resp_status

section .data
    msg_listen db 0xA, 0xA, "[ASMX]: listening on http://localhost:"
    msg_listen_len equ $ - msg_listen
    msg_nl db 10

section .text

; ----------------------------------------------------------------------
; asmx_listen(port) - never returns
; Arguments: rdi = port (host byte order)
; Grabs the return address (user handler) from the stack, creates the
; listening socket, prints a startup banner, then falls through into
; the `requests` accept loop.
; ----------------------------------------------------------------------
global asmx_listen
asmx_listen:
    pop rax
    mov [asmx_handler], rax
    mov r12, rdi                  ; port (r12 callee-saved)
    call socket_bind_listen       ; rdi = port, rax = server_fd
    mov [server_fd], rax

    ; print "asmx: listening on <port>\n" (itoa clobbers rdi/rsi - recompute)
    mov rax, SYS_write
    mov rdi, 1
    lea rsi, [msg_listen]
    mov rdx, msg_listen_len
    syscall
    mov rdi, r12
    lea rsi, [itoa_buf]
    call itoa                     ; rax = ptr to first digit
    mov rsi, rax
    lea rdx, [itoa_buf + 11]
    sub rdx, rsi                  ; digit count
    mov rax, SYS_write
    mov rdi, 1
    syscall
    mov rax, SYS_write
    mov rdi, 1
    lea rsi, [msg_nl]
    mov rdx, 1
    syscall
    ; fall through to requests

; ----------------------------------------------------------------------
; requests - accept loop (exported so user handlers can `jmp requests`)
; ----------------------------------------------------------------------
global requests
requests:
    ; Close previous client if any (fd > 2)
    cmp qword [client_fd], 2
    jle .no_close
    mov rax, SYS_close
    mov rdi, [client_fd]
    syscall
.no_close:

    ; Accept a connection
    mov rax, SYS_accept
    mov rdi, [server_fd]
    xor rsi, rsi
    xor rdx, rdx
    syscall
    check_syscall accept_error
    mov [client_fd], rax

    ; Read the request
    mov rax, SYS_read
    mov rdi, [client_fd]
    lea rsi, [buffer]
    mov rdx, 4096
    syscall
    check_syscall read_error
    mov rbx, rax                  ; bytes_read (rbx callee-saved)

    ; Parse request line
    mov rdi, buffer
    mov rsi, rbx
    call http_parse_request_line

    ; Copy path into route
    call http_get_path
    mov r12, rax                  ; path ptr (callee-saved)
    mov rdi, rax
    call strlen
    inc rax
    mov rdx, rax
    mov rdi, route
    mov rsi, r12
    call strncpy

    ; Parse headers (Content-Length, body offset)
    mov rdi, buffer
    mov rsi, rbx
    call http_parse_headers

    ; Reset the response status for this request (router may set 404
    ; for the not-found route on the previous one)
    mov qword [resp_status], 200

    ; Dispatch to the user handler (never returns - handler jmps to requests)
    mov rax, [asmx_handler]
    jmp rax
