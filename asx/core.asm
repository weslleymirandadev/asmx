; src/asx/core.asm
; asx runtime - the framework engine
;
; Flow:
;   user code:  listen 3000          -> asx_listen grabs return address as
;                                      handler, creates socket, falls into
;                                      `requests` accept loop
;   requests:   accept -> read -> parse -> copy path to `route` -> jmp handler
;   handler:    user code (cmp route / send_json / ...) ends with `jmp requests`
;
; Exported for user apps:
;   asx_listen, requests (accept loop label)

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
extern server_fd, client_fd, asx_handler
extern buffer, route, resp_status
extern asx_ssr_state_reset
extern log_banner, log_bind_retry, log_bind_giveup, log_request, clock_start
extern req_count

section .bss
    sig_action resq 4     ; struct sigaction: sa_handler, sa_flags, sa_restorer, sa_mask
    is_child   resq 1     ; 1 = fork child (processes ONE request then exits)

section .data
    rcv_timeout dq 0, 300000  ; struct timeval { tv_sec = 0, tv_usec = 300ms }
                              ; SO_RCVTIMEO: a legit request arrives in
                              ; <10ms after connect; 300ms just kills
                              ; stale/preconnect sockets fast so the
                              ; next refresh waits at most ~0.3s
    clear_seq db 27, '[', '2', 'J', 27, '[', 'H'   ; ANSI clear screen + home
    clear_seq_len equ $ - clear_seq

%define MAX_PORT 65535

section .text

; ----------------------------------------------------------------------
; asx_listen(port) - never returns
; Arguments: rdi = port (host byte order)
; Grabs the return address (user handler) from the stack, creates the
; listening socket, prints a startup banner, then falls through into
; the `requests` accept loop.
; ----------------------------------------------------------------------
global asx_listen
asx_listen:
    pop rax
    mov [asx_handler], rax
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

    ; Ignore SIGPIPE (13): a client that closes the connection while we
    ; are writing would KILL the server (default SIGPIPE action = die).
    ; This was observed live (exit -13): the browser cancelling a load
    ; or a curl timeout made the whole server vanish. With SIG_IGN the
    ; write just fails with EPIPE and the accept loop continues.
    mov qword [sig_action + 0], 1     ; sa_handler = SIG_IGN
    mov qword [sig_action + 8], 0     ; sa_flags
    mov qword [sig_action + 16], 0    ; sa_restorer
    mov qword [sig_action + 24], 0    ; sa_mask
    lea rsi, [sig_action]
    xor rdx, rdx                      ; oldact = NULL
    mov r10, 8                        ; sigsetsize
    mov rdi, 13                       ; SIGPIPE
    mov rax, SYS_rt_sigaction
    syscall

    ; Ignore SIGCHLD (17): fork-per-connection children that finished
    ; are reaped by the kernel automatically (SIG_IGN on SIGCHLD) - no
    ; zombies, no waitpid in the accept loop. Only the child that is
    ; still processing a request lingers, and it closes server_fd at
    ; fork time so the port never stays bound after the parent dies.
    mov qword [sig_action + 0], 1     ; sa_handler = SIG_IGN
    mov qword [sig_action + 8], 0     ; sa_flags
    mov qword [sig_action + 16], 0    ; sa_restorer
    mov qword [sig_action + 24], 0    ; sa_mask
    lea rsi, [sig_action]
    xor rdx, rdx                      ; oldact = NULL
    mov r10, 8                        ; sigsetsize
    mov rdi, 17                       ; SIGCHLD
    mov rax, SYS_rt_sigaction
    syscall

.listen_loop:
    mov rdi, r12                  ; current port (socket_bind_listen consumes rdi)
    call socket_bind_listen       ; rax = server_fd or -1 (port in use)
    cmp rax, -1
    je .port_retry
    mov [server_fd], rax

    ; clear the terminal so only the banner shows
    mov rax, SYS_write
    mov rdi, 1
    lea rsi, [clear_seq]
    mov rdx, clear_seq_len
    syscall

    ; print the colored startup banner (log.asm)
    mov rdi, r12
    call log_banner
    jmp requests              ; fall through explicitly - the .port_retry
                              ; label below must NOT be on this path
.port_retry:
    ; the port is taken: colored message, then retry on port+1
    mov rdi, r12
    call log_bind_retry
    inc r12
    cmp r12, MAX_PORT         ; never escalate past the ceiling
    jg .give_up
    jmp .listen_loop              ; rdi is re-set at the top of the loop
.give_up:
    mov rdi, MAX_PORT
    call log_bind_giveup       ; colored "no free port up to N"
    mov rax, SYS_exit
    mov rdi, 1
    syscall

; ----------------------------------------------------------------------
; requests - accept loop (exported so user handlers can `jmp requests`)
; ----------------------------------------------------------------------
; Concurrency model: fork-per-connection. The parent accepts and forks;
; the CHILD processes exactly ONE request (parse -> dispatch -> handler)
; and _exits (never accepts). The parent closes its copy of the client
; fd and goes back to accepting immediately - a slow request (upload,
; large static, SSE) can no longer block the queue. No locks, no shared
; state: the fork copies memory (COW), so buffer/route/resp_buf are
; per-connection by construction. SIGCHLD=SIG_IGN (set in asx_listen)
; makes the kernel reap finished children - no zombies, no waitpid.
; ----------------------------------------------------------------------
global requests
requests:
    ; Fork child? the request it processed just finished: log + exit.
    ; (The parent never reaches this branch: it has is_child = 0.)
    cmp qword [is_child], 1
    jne .parent
    call log_request
    mov rax, SYS_exit
    xor rdi, rdi
    syscall
.parent:
    ; Close previous client if any (fd > 2)
    cmp qword [client_fd], 2
    jle .accept
    mov rax, SYS_close
    mov rdi, [client_fd]
    syscall
.accept:
    ; Accept a connection
    mov rax, SYS_accept
    mov rdi, [server_fd]
    xor rsi, rsi
    xor rdx, rdx
    syscall
    check_syscall accept_error
    mov [client_fd], rax

    ; SO_RCVTIMEO on the client socket: a client that connects and never
    ; sends (browser preconnect, stale connection) would block the
    ; child for 5s and the parent would fork endlessly for the same
    ; backlog item. With a receive timeout the read fails with EAGAIN
    ; after 5s and that child closes + exits.
    mov rdi, [client_fd]
    mov rax, SYS_setsockopt
    mov rsi, 1        ; SOL_SOCKET
    mov rdx, 20       ; SO_RCVTIMEO
    lea r10, [rcv_timeout]
    mov r8, 16        ; sizeof(struct timeval)
    syscall

    ; fork: the child owns this connection, the parent keeps accepting
    mov rax, SYS_fork
    syscall
    test rax, rax
    jnz .parent_fork

    ; ================= child: process ONE request =================
    mov qword [is_child], 1
    ; the log's "first request" guard uses req_count, inherited as 0
    ; from the parent (which never processes) - force it so every
    ; child's request is logged
    mov qword [req_count], 1
    ; close the listening socket: a slow child must not keep the port
    ; bound after the parent dies (hot reload rebinds immediately)
    mov rax, SYS_close
    mov rdi, [server_fd]
    syscall

    ; Read the request
    mov rax, SYS_read
    mov rdi, [client_fd]
    lea rsi, [buffer]
    mov rdx, 4096
    syscall
    test rax, rax
    jle .read_close           ; EOF (0) or error (<0): the client never
                              ; sent a request (probe/preconnect/bench
                              ; that closed early) - close and move on,
                              ; do NOT fabricate a 404 in the log
    mov rbx, rax                  ; bytes_read (rbx callee-saved)

    ; Start the request timer - the request bytes just arrived, so the
    ; duration covers only actual processing, not idle wait
    call clock_start

    ; Parse request line
    mov rdi, buffer
    mov rsi, rbx
    call http_parse_request_line
    test rax, rax
    js .read_close            ; garbage that is not a valid request line:
                              ; nothing to route, close without responding

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
    ; for the not-found route on the previous one) and the server state
    ; table (ssr.state values must not leak between requests)
    mov qword [resp_status], 200
    call asx_ssr_state_reset

    ; Dispatch to the user handler (never returns in-process - the
    ; handler responds and `jmp requests`, where the is_child branch
    ; logs + exits)
    mov rax, [asx_handler]
    jmp rax

.parent_fork:
    ; ================= parent: back to accepting =================
    ; close our copy of the client fd (the child inherited it); the
    ; accept of the next connection overwrites client_fd anyway
    mov rax, SYS_close
    mov rdi, [client_fd]
    syscall
    mov qword [client_fd], -1
    jmp .accept

.read_close:
    ; Idle client (EAGAIN from SO_RCVTIMEO) or read error: close the
    ; socket and exit (a child never loops back to accept).
    mov rax, SYS_close
    mov rdi, [client_fd]
    syscall
    mov qword [client_fd], -1
    mov rax, SYS_exit
    xor rdi, rdi
    syscall
