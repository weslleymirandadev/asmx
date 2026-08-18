; =============================================================================
; io.asm - die, read_file, write_buf_file
; =============================================================================

; read_file(rdi = path) -> rax = 0 ok / -1 err; fills in_buf/in_len
; ----------------------------------------------------------------------
read_file:
    push r12
    mov r12, rdi
    lea rsi, [in_buf]
    mov rdx, IN_CAP
    call read_file_to
    test rax, rax
    js .err
    mov [in_len], rax
    xor rax, rax
    pop r12
    ret
.err:
    mov rax, -1
    pop r12
    ret

; read_file_to(rdi = path, rsi = buf, rdx = cap) -> rax = len or -1
; ----------------------------------------------------------------------
read_file_to:
    push rbx
    push r12
    push r13
    push r14
    mov r13, rsi                ; buf
    mov rbx, rdx                ; cap
    mov rax, SYS_open
    mov rsi, O_RDONLY
    syscall
    test rax, rax
    js .err
    mov r12, rax                ; fd
    xor r14, r14                ; pos
.read:
    cmp r14, rbx
    jge .full
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [r13 + r14]
    mov rdx, rbx
    sub rdx, r14
    syscall
    test rax, rax
    jz .done
    js .err_read
    add r14, rax
    jmp .read
.full:
    mov r14, -1
    jmp .close
.err_read:
    mov r14, -1
.done:
    mov rax, r14
.close:
    push rax
    mov rax, SYS_close
    mov rdi, r12
    syscall
    pop rax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.err:
    mov rax, -1
    pop r14
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
