; =============================================================================
; io.asm - die, read_file, write_buf_file
; =============================================================================

; read_file(rdi = path) -> rax = 0 ok / -1 err; fills in_buf/in_len
; ----------------------------------------------------------------------
read_file:
    push rbx
    push r12
    push r13
    mov rax, SYS_open
    mov rsi, O_RDONLY
    syscall
    test rax, rax
    js .err
    mov r12, rax                ; fd
    xor r13, r13                ; pos
.read:
    cmp r13, IN_CAP
    jge .full
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [in_buf + r13]
    mov rdx, IN_CAP
    sub rdx, r13
    syscall
    test rax, rax
    jz .done
    js .err_read
    add r13, rax
    jmp .read
.full:
    lea rdi, [msg_big]
    mov rsi, msg_big_len
    call die
.err_read:
    mov r13, -1
    jmp .close
.done:
    mov [in_len], r13
    xor r13, r13                ; ok
.close:
    mov rax, SYS_close
    mov rdi, r12
    syscall
    mov rax, r13
    pop r13
    pop r12
    pop rbx
    ret
.err:
    mov rax, -1
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; write_buf_file(rdi = path, rsi = buf, rdx = len) -> rax = 0 ok / -1 err
; ----------------------------------------------------------------------
write_buf_file:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rax, SYS_open
    mov rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov rdx, OUT_MODE
    syscall
    test rax, rax
    js .err
    mov rbx, rax
    mov rax, SYS_write
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    syscall
    mov rax, SYS_close
    mov rdi, rbx
    syscall
    xor rax, rax
    jmp .done
.err:
    mov rax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; process - scans the src, copies lines and replaces @ DSL blocks
