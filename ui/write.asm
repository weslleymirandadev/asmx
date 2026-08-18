; =============================================================================
; write.asm - .wat writes, paths, strcpy_l, get_ui_name
; =============================================================================

write_wat_file:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp qword [mkdir_done], 0
    jne .have_dir
    call build_wat_dir_path     ; path_buf = <out>.d
    mov rax, SYS_mkdir
    lea rdi, [path_buf]
    mov rsi, 0x1ED              ; 0755
    syscall
    mov qword [mkdir_done], 1
.have_dir:
    call build_wat_path         ; path_buf = <out>.d/<label>.wat
    lea rdi, [path_buf]
    lea rsi, [wat_buf]
    mov rdx, [wat_len]
    call write_buf_file
    test rax, rax
    jnz .err
    xor rax, rax
    jmp .done
.err:
    lea rdi, [msg_write]
    mov rsi, msg_write_len
    call die
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; write_main_wat_file - writes <out_path>.d/_main.wat
write_main_wat_file:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call build_main_wat_path
    lea rdi, [path_buf]
    lea rsi, [main_buf]
    mov rdx, [main_len]
    call write_buf_file
    test rax, rax
    jnz .err
    xor rax, rax
    jmp .done
.err:
    lea rdi, [msg_write]
    mov rsi, msg_write_len
    call die
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; build_wat_dir_path - path_buf = <out_path>.d
build_wat_dir_path:
    lea rdi, [path_buf]
    mov rsi, [out_path]
    call strcpy_l
    mov rdi, rax
    lea rsi, [s_dot_d_dir]
    call strcpy_l
    ret

; build_wat_path - path_buf = <out_path>.d/<label>.wat
build_wat_path:
    lea rdi, [path_buf]
    mov rsi, [out_path]
    call strcpy_l
    mov rdi, rax
    lea rsi, [s_dot_d]
    call strcpy_l
    mov rdi, rax
    xor rcx, rcx
.l:
    cmp rcx, [label_len]
    jge .ld
    mov al, [label_buf + rcx]
    mov [rdi + rcx], al
    inc rcx
    jmp .l
.ld:
    add rdi, rcx
    lea rsi, [s_dot_wat]
    call strcpy_l
    ret

; build_main_wat_path - path_buf = <out_path>.d/_main.wat
build_main_wat_path:
    lea rdi, [path_buf]
    mov rsi, [out_path]
    call strcpy_l
    mov rdi, rax
    lea rsi, [s_dot_d]
    call strcpy_l
    mov rdi, rax
    lea rsi, [s_main_wat]
    call strcpy_l
    ret

; strcpy_l(rdi = dst, rsi = src) -> rax = dst + len (null copied)
strcpy_l:
    xor rcx, rcx
.loop:
    mov al, [rsi + rcx]
    mov [rdi + rcx], al
    test al, al
    jz .done
    inc rcx
    jmp .loop
.done:
    lea rax, [rdi + rcx]
    ret

; ----------------------------------------------------------------------
; get_ui_name(rdi = path) - page name in ui_name_buf/ui_name_len.
; Derives from the FULL PATH (not just the dir) so routes with the same
; dir name never collide:
;   src/app/sobre/page.s       -> "sobre"          (data-modules="/sobre/page.wasm")
;   src/app/admin/sobre/page.s -> "admin/sobre"    (data-modules="/admin/sobre/page.wasm")
;   src/app/page.s             -> "index"
; ----------------------------------------------------------------------
get_ui_name:
    push rbx
    push r12
    push r13
    mov r12, rdi
    call strlen                 ; rax = len
    mov r13, rax
    ; start = 8 if the path begins with "src/app/" (8 chars)
    xor rbx, rbx                ; inicio = 0
    cmp r13, 8
    jl .have_start
    cmp byte [r12], 's'
    jne .have_start
    cmp byte [r12 + 1], 'r'
    jne .have_start
    cmp byte [r12 + 2], 'c'
    jne .have_start
    cmp byte [r12 + 3], '/'
    jne .have_start
    cmp byte [r12 + 4], 'a'
    jne .have_start
    cmp byte [r12 + 5], 'p'
    jne .have_start
    cmp byte [r12 + 6], 'p'
    jne .have_start
    cmp byte [r12 + 7], '/'
    jne .have_start
    mov rbx, 8
.have_start:
    ; end = len - 7 (strip "/page.s" incl. the slash); name = [start, end)
    lea rcx, [r13 - 7]
    mov rdx, rcx
    sub rdx, rbx
    test rdx, rdx
    jle .index                  ; empty (src/app/page.s) -> "index"
    xor r8, r8
.copy:
    cmp r8, rdx
    jge .copy_done
    mov al, [r12 + rbx]
    mov [ui_name_buf + r8], al
    inc rbx
    inc r8
    jmp .copy
.copy_done:
    mov [ui_name_len], rdx
    jmp .done
.index:
    mov byte [ui_name_buf], 'i'
    mov byte [ui_name_buf + 1], 'n'
    mov byte [ui_name_buf + 2], 'd'
    mov byte [ui_name_buf + 3], 'e'
    mov byte [ui_name_buf + 4], 'x'
    mov qword [ui_name_len], 5
.done:
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; out_label(suffix) - writes label_buf + suffix
