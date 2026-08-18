; =============================================================================
; process.asm - scans the src and replaces @ DSL blocks
; =============================================================================

process:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov qword [out_len], 0
    mov qword [wat_count], 0
    mov qword [str_cursor], 0
    mov qword [main_started], 0
    mov qword [mkdir_done], 0
    mov rdi, [src_path]
    call get_ui_name
    xor r12, r12                ; cur
    mov r13, [in_len]           ; end
.loop:
    cmp r12, r13
    jge .done
    ; end of line [r12, r14)
    mov r14, r12
.scan:
    cmp r14, r13
    jge .have_line
    cmp byte [in_buf + r14], 10
    je .have_line
    inc r14
    jmp .scan
.have_line:
    ; label candidata?
    lea rdi, [in_buf + r12]
    mov rsi, r14
    sub rsi, r12
    call is_label
    test rax, rax
    jz .copy_line
    ; next content
    mov rdi, r14
    cmp rdi, r13
    jge .copy_line
    cmp byte [in_buf + rdi], 10
    jne .copy_line
    inc rdi
    call find_content
    cmp rax, -1
    je .copy_line
    ; r15 = content start; requires '@' with indent > 0
    mov r15, rax
    mov rbx, r15
.indent:
    cmp rbx, r13
    jge .copy_line
    mov al, [in_buf + rbx]
    cmp al, ' '
    je .in_inc
    cmp al, 9
    jne .ic_done
.in_inc:
    inc rbx
    jmp .indent
.ic_done:
    cmp rbx, r15
    jle .copy_line              ; indent == 0
    cmp byte [in_buf + rbx], '@'
    jne .copy_line
    ; BLOCK: [r15, find_block_end)
    mov rdi, r15
    call find_block_end
    mov rbx, rax                ; end of block
    ; expand @comp lines (src/components/*.s, {param} args) - the block
    ; may grow/shrink inside in_buf, so re-find the end afterwards
    mov rdi, r15
    mov rsi, rbx
    call expand_block
    mov rbx, rax                ; end of the expanded block
    mov r13, [in_len]           ; the expansion may have grown in_buf
    ; copy the label line (with \n if any)
    mov rdi, r12
    mov rsi, r14
    cmp r14, r13
    jge .lbl_no_nl
    inc rsi
.lbl_no_nl:
    call copy_range
    ; compile the block and emit: shell (in the .s) + component (.wat file)
    mov rdi, r15
    mov rsi, rbx
    call compile_block
    call emit_shell
    call emit_wat_componente
    call append_wat_call
    call write_wat_file
    inc qword [wat_count]
    mov r12, rbx
    jmp .loop
.copy_line:
    mov rdi, r12
    mov rsi, r14
    cmp r14, r13
    jge .cl_no_nl
    inc rsi
.cl_no_nl:
    call copy_range
    mov r12, r14
    cmp r12, r13
    jge .done
    cmp byte [in_buf + r12], 10
    jne .done
    inc r12
    jmp .loop
.done:
    ; final page module: orchestrator + theme + exports (if any UI)
    cmp qword [wat_count], 0
    je .no_wat
    call emit_wat_main
    call write_main_wat_file
.no_wat:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; copy_range(rdi = from, rsi = to) - copies [from, to) from in_buf to out
; ----------------------------------------------------------------------
copy_range:
    push rbx
    push r12
    mov r12, rdi
    mov rbx, rsi
    sub rbx, rdi
    jle .done
    mov rax, [out_len]
    add rax, rbx
    cmp rax, OUT_CAP
    jg .full
    mov rdi, rax
    sub rdi, rbx                ; dst = out_buf + out_len
    lea rdi, [out_buf + rdi]
    lea rsi, [in_buf + r12]
    mov rdx, rbx
    call memcpy
    add [out_len], rbx
.done:
    pop r12
    pop rbx
    ret
.full:
    lea rdi, [msg_big_out]
    mov rsi, msg_big_out_len
    call die

; ----------------------------------------------------------------------
; is_label(rdi = line, rsi = len) -> rax = 1 if "IDENT:"; copies the name
; into label_buf/label_len
