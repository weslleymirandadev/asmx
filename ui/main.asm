; =============================================================================
; main.asm - entry point (_start)
; =============================================================================

; text
; ----------------------------------------------------------------------
section .text

global _start
_start:
    mov r13, [rsp]              ; argc
    lea r12, [rsp + 8]          ; argv
    cmp r13, 3
    jl .usage
    mov rax, [r12 + 8]          ; src path
    mov [src_path], rax
    mov rax, [r12 + 16]         ; out path (build/.../page.s)
    mov [out_path], rax
    mov rdi, [r12 + 8]          ; src
    call read_file
    test rax, rax
    jnz .read_err
    call process
    mov rdi, [out_path]         ; write the processed page.s
    lea rsi, [out_buf]
    mov rdx, [out_len]
    call write_buf_file
    test rax, rax
    jnz .write_err
    xor rdi, rdi
    jmp .exit
.usage:
    lea rdi, [msg_usage]
    mov rsi, msg_usage_len
    call die
.read_err:
    lea rdi, [msg_read]
    mov rsi, msg_read_len
    call die
.write_err:
    lea rdi, [msg_write]
    mov rsi, msg_write_len
    call die
.exit:
    mov rax, SYS_exit
    syscall

; die(rdi = msg, rsi = len) - writes to stderr and exits 1
die:
    mov rax, SYS_write
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, 2
    syscall
    mov rax, SYS_exit
    mov rdi, 1
    syscall
