; =============================================================================
; out.asm - output helpers (out_*/out_wat_*/out_main_*)
; =============================================================================

out_label:
    push rdi
    push rsi
    lea rdi, [label_buf]
    mov rsi, [label_len]
    call out_bytes
    pop rsi
    pop rdi
    jmp out_str

; out_byte(al) - writes 1 byte to out_buf (does NOT clobber al!)
out_byte:
    mov rcx, [out_len]
    cmp rcx, OUT_CAP - 1
    jg .full
    mov [out_buf + rcx], al
    inc qword [out_len]
    ret
.full:
    lea rdi, [msg_big_out]
    mov rsi, msg_big_out_len
    call die

; out_bytes(rdi = src, rsi = len) - NOTE: out_byte clobbers rcx, so
; the loop index lives in r8 (caller-saved, untouched by out_byte).
out_bytes:
    push rbx
    push r12
    mov r12, rdi
    mov rbx, rsi
    xor r8, r8
.loop:
    cmp r8, rbx
    jge .done
    mov al, [r12 + r8]
    call out_byte
    inc r8
    jmp .loop
.done:
    pop r12
    pop rbx
    ret

; out_str(rdi = null-terminated)
out_str:
    push r12
    mov r12, rdi
.loop:
    mov al, [r12]
    test al, al
    jz .done
    call out_byte
    inc r12
    jmp .loop
.done:
    pop r12
    ret

; ----------------------------------------------------------------------
; WAT output (wat_buf/wat_len) - same pattern as the page.s out_*
; ----------------------------------------------------------------------
out_wat_byte:  ; (al)
    mov rcx, [wat_len]
    cmp rcx, WAT_CAP - 1
    jg .full
    mov [wat_buf + rcx], al
    inc qword [wat_len]
    ret
.full:
    lea rdi, [msg_big_out]
    mov rsi, msg_big_out_len
    call die

out_wat_bytes:  ; (rdi = src, rsi = len)
    push rbx
    push r12
    mov r12, rdi
    mov rbx, rsi
    xor r8, r8
.loop:
    cmp r8, rbx
    jge .done
    mov al, [r12 + r8]
    call out_wat_byte
    inc r8
    jmp .loop
.done:
    pop r12
    pop rbx
    ret

out_wat_str:  ; (rdi = null-terminated)
    push r12
    mov r12, rdi
.loop:
    mov al, [r12]
    test al, al
    jz .done
    call out_wat_byte
    inc r12
    jmp .loop
.done:
    pop r12
    ret

; itoa_wat(rdi = val)
itoa_wat:
    lea rsi, [itoa_buf]
    call itoa
    mov rdi, rax
    jmp out_wat_str

; ----------------------------------------------------------------------
; final module output (main_buf/main_len)
; ----------------------------------------------------------------------
out_main_byte:  ; (al)
    mov rcx, [main_len]
    cmp rcx, WAT_CAP - 1
    jg .full
    mov [main_buf + rcx], al
    inc qword [main_len]
    ret
.full:
    lea rdi, [msg_big_out]
    mov rsi, msg_big_out_len
    call die

out_main_bytes:  ; (rdi = src, rsi = len)
    push rbx
    push r12
    mov r12, rdi
    mov rbx, rsi
    xor r8, r8
.loop:
    cmp r8, rbx
    jge .done
    mov al, [r12 + r8]
    call out_main_byte
    inc r8
    jmp .loop
.done:
    pop r12
    pop rbx
    ret

out_main_str:  ; (rdi = null-terminated)
    push r12
    mov r12, rdi
.loop:
    mov al, [r12]
    test al, al
    jz .done
    call out_main_byte
    inc r12
    jmp .loop
.done:
    pop r12
    ret

; itoa_main(rdi = val)
itoa_main:
    lea rsi, [itoa_buf]
    call itoa
    mov rdi, rax
    jmp out_main_str
