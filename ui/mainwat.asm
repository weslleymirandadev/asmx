; =============================================================================
; mainwat.asm - final module (append_wat_call, emit_wat_main)
; =============================================================================

append_wat_call:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp qword [main_started], 0
    jne .have_hdr
    mov qword [main_len], 0
    lea rdi, [s_main_h1]
    call out_main_str
    lea rdi, [ui_name_buf]
    mov rsi, [ui_name_len]
    call out_main_bytes
    lea rdi, [s_main_h2]
    call out_main_str
    mov qword [main_started], 1
.have_hdr:
    lea rdi, [s_main_call]
    call out_main_str
    lea rdi, [label_buf]
    mov rsi, [label_len]
    call out_main_bytes
    lea rdi, [s_nl2]
    call out_main_str
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; emit_wat_main - finishes the final module: close + theme + exports
; ----------------------------------------------------------------------
emit_wat_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea rdi, [s_main_t1]
    call out_main_str
    mov rdi, [theme_bg]
    call hex6_main
    lea rdi, [s_main_t2]
    call out_main_str
    mov rdi, [theme_text]
    call hex6_main
    lea rdi, [s_main_t3]
    call out_main_str
    mov rdi, [theme_accent]
    call hex6_main
    lea rdi, [s_main_t4]
    call out_main_str
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; hex6_main(rdi = 0xRRGGBB) - writes 6 hex digits to main_buf
hex6_main:
    push r12
    push r13
    mov r12, rdi
    mov r13, 20
.loop:
    cmp r13, 0
    jl .done
    mov eax, r12d
    mov ecx, r13d
    shr eax, cl
    and eax, 0x0f
    cmp eax, 10
    jl .digit
    add eax, 'a' - 10
    jmp .emit
.digit:
    add eax, '0'
.emit:
    call out_main_byte
    sub r13, 4
    jmp .loop
.done:
    pop r13
    pop r12
    ret

; ----------------------------------------------------------------------
; write_wat_file - writes <out_path>.d/<label>.wat (mkdir of .d once)
