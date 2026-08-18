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
extern accept_error
extern read_error
extern server_fd, client_fd, asmx_handler
extern buffer, route, resp_status
extern log_banner, log_request, clock_start

section .bss
    sig_action resq 4     ; struct sigaction: sa_handler, sa_flags, sa_restorer, sa_mask

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

    ; Reset SIGINT/SIGTERM to DEFAULT: the parent environment may leave
    ; them IGNORED (SIG_IGN is inherited across fork/exec - observed
    ; SigIgn=0x6), so Ctrl+C would never kill the server and the port
    ; would stay bound forever. SIG_DFL (sa_handler = 0) makes the kernel
    ; kill the process and close the socket; SO_REUSEADDR (net.asm) then
    ; allows an immediate rebind. No custom handler = no signal frame.
    mov qword [sig_action + 0], 0     ; sa_handler = SIG_DFL
    mov qword [sig_action + 8], 0     ; sa_flags
    mov qword [sig_action + 16], 0    ; sa_restorer
    mov qword [sig_action + 24], 0    ; sa_mask
    lea rsi, [sig_action]
    xor rdx, rdx                      ; oldact = NULL
    mov r10, 8                        ; sigsetsize = sizeof(kernel sigset_t)
    mov rdi, 2                        ; SIGINT
    mov rax, SYS_rt_sigaction
    syscall
    mov rdi, 15                       ; SIGTERM
    mov rax, SYS_rt_sigaction
    syscall

    mov rdi, r12                  ; restore port (sigaction clobbered rdi)
    call socket_bind_listen       ; rax = server_fd
    mov [server_fd], rax

    ; print the colored startup banner (log.asm)
    mov rdi, r12
    call log_banner
    ; fall through to requests

; ----------------------------------------------------------------------
; requests - accept loop (exported so user handlers can `jmp requests`)
; ----------------------------------------------------------------------
global requests
requests:
    ; Log the request that just finished (if any) and timestamp this one
    call log_request

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

    ; Start the request timer - the request bytes just arrived, so the
    ; duration covers only actual processing, not idle wait
    call clock_start

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
