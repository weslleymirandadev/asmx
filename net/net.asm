; src/net/net.asm
; Socket creation: socket -> bind -> listen

%include "net/net.inc"

global socket_bind_listen
global server_addr
extern socket_error
extern bind_error
extern listen_error

section .data
    ; sockaddr_in: AF_INET, port set at runtime, INADDR_ANY
    server_addr:
        dw 2          ; sin_family = AF_INET
        dw 0x5000     ; sin_port (network byte order, patched at runtime)
        dd 0          ; sin_addr = INADDR_ANY
        dq 0          ; padding
    server_addr_len equ $ - server_addr

    ; setsockopt SO_REUSEADDR value (1 = on)
    reuse_on dd 1

section .text

; socket_bind_listen(port) -> rax = server_fd
; Arguments: rdi = port (host byte order, e.g. 3000)
; Sets SO_REUSEADDR before bind so restarts don't fail on TIME_WAIT.
socket_bind_listen:
    ; Convert port to network byte order (swap bytes) and store in sockaddr
    mov rax, rdi
    shl rax, 8          ; port << 8
    and rax, 0xFF00
    mov rdx, rdi
    shr rdx, 8          ; port >> 8
    and rdx, 0xFF
    or rax, rdx
    mov [server_addr + 2], ax

    ; Create the socket
    mov rax, SYS_socket
    mov rdi, 2        ; AF_INET
    mov rsi, 1        ; SOCK_STREAM
    mov rdx, 0        ; protocol 0
    syscall
    check_syscall socket_error

    ; SO_REUSEADDR so rebinding after TIME_WAIT works
    mov rdi, rax      ; rdi = server_fd
    mov rax, SYS_setsockopt
    mov rsi, 1        ; SOL_SOCKET
    mov rdx, 2        ; SO_REUSEADDR
    lea r10, [reuse_on]
    mov r8, 4         ; sizeof(int)
    syscall
    check_syscall socket_error

    ; Bind the socket to the address
    mov rax, SYS_bind
    ; rdi still = server_fd
    lea rsi, [server_addr]
    mov rdx, server_addr_len
    syscall
    test rax, rax
    js .bind_fail               ; EADDRINUSE etc. -> -1, the core retries port+1

    ; Listen for connections
    mov rax, SYS_listen
    ; rdi still = server_fd (syscalls preserve rdi)
    mov rsi, 128      ; backlog
    syscall
    check_syscall listen_error

    mov rax, rdi      ; return server_fd
    ret
.bind_fail:
    ; close the socket of the failed bind (avoids fd leaks across retries)
    mov rax, SYS_close
    syscall                       ; rdi still = server_fd
    mov rax, -1
    ret
