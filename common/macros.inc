; macros.inc
; Reusable assembly macros

%ifndef MACROS_INC
%define MACROS_INC

; check_syscall label
; After a syscall, rax holds the return value.
; On Linux x86-64, negative values indicate errors.
; This macro jumps to the given label if an error occurred.
%macro check_syscall 1
    test rax, rax
    js %1
%endmacro


; write_stdout buffer, length
; Write a buffer to stdout (fd 1).
%macro write_stdout 2
    mov rax, SYS_write
    mov rdi, 1
    lea rsi, %1
    mov rdx, %2
    syscall
%endmacro


; write_stderr buffer, length
; Write a buffer to stderr (fd 2).
%macro write_stderr 2
    mov rax, SYS_write
    mov rdi, 2
    lea rsi, %1
    mov rdx, %2
    syscall
%endmacro


; close_fd fd
; Close a file descriptor.
%macro close_fd 1
    mov rax, SYS_close
    mov rdi, %1
    syscall
%endmacro


; exit_code code
; Exit the program with the given exit code.
%macro exit_code 1
    mov rax, SYS_exit
    mov rdi, %1
    syscall
%endmacro

%endif
