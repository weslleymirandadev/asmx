; =============================================================================
; serialize.asm - binary blob + records
; =============================================================================

visit:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    imul rax, r12, NODE_SIZE
    lea r14, [nodes + rax]
    mov eax, [rec_count]
    imul rax, rax, 12
    lea rbx, [rec_order + rax]
    movzx eax, byte [r14 + N_TAG]
    cmp eax, 2
    je .button
    mov dword [rbx], 0
    mov [rbx + 4], r12d
    mov [rbx + 8], r13d
    mov eax, [rec_count]
    inc dword [rec_count]
    mov r13d, eax
    jmp .children
.button:
    mov dword [rbx], 1
    mov [rbx + 4], r12d
    mov [rbx + 8], r13d
    mov eax, [rec_count]
    mov r13d, eax               ; view rec idx (pai dos filhos)
    add rbx, 12
    mov dword [rbx], 2
    mov [rbx + 4], r12d
    mov [rbx + 8], r13d
    add dword [rec_count], 2
.children:
    mov r15d, [r14 + N_FIRST]
.child_loop:
    cmp r15d, -1
    je .done
    mov rdi, r15
    mov rsi, r13
    call visit
    mov rax, r15
    imul rax, rax, NODE_SIZE
    lea rax, [nodes + rax]
    mov r15d, [rax + N_NEXT]
    jmp .child_loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; serialize - builds the ASXUIV1 blob in blob_buf:
;   +0 "ASXUIV1" | +8 count | +12/16/20 theme bg/text/accent
;   +24 records 32B | ... string pool (text_offset relativo ao blob)
; ----------------------------------------------------------------------
serialize:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov dword [blob_buf], 0x584D5341       ; "ASX"
    mov dword [blob_buf + 4], 0x31564955   ; "UIV1"
    mov eax, [rec_count]
    mov [blob_buf + 8], eax
    mov eax, [theme_bg]
    mov [blob_buf + 12], eax
    mov eax, [theme_text]
    mov [blob_buf + 16], eax
    mov eax, [theme_accent]
    mov [blob_buf + 20], eax
    mov eax, [rec_count]
    imul eax, 32
    add eax, 24
    mov [blob_len], rax
    xor r12, r12                ; i
.loop:
    cmp r12, [rec_count]
    jge .done
    mov rax, r12
    imul rax, rax, 12
    lea r13, [rec_order + rax]
    mov eax, [r13]              ; kind
    mov ebx, [r13 + 4]          ; node idx
    mov r14d, [r13 + 8]         ; parent rec idx
    imul r10, rbx, NODE_SIZE
    lea r15, [nodes + r10]
    mov rax, r12
    imul rax, rax, 32
    lea rdi, [blob_buf + rax + 24]
    ; zero o record
    mov ecx, 32
    xor eax, eax
    rep stosb
    mov rax, r12
    imul rax, rax, 32
    lea rdi, [blob_buf + rax + 24]
    ; type
    mov eax, [r13]
    cmp eax, 2
    je .t_label
    cmp eax, 1
    je .t_view
    movzx eax, byte [r15 + N_TAG]
    jmp .have_type
.t_view:
    xor eax, eax
    jmp .have_type
.t_label:
    mov eax, 1
.have_type:
    mov [rdi], al
    ; x/y/w/h
    mov eax, [r15 + N_AX]
    mov [rdi + 2], ax
    mov eax, [r15 + N_AY]
    mov [rdi + 4], ax
    ; w/h: for views (type 0) store the CLASS width/height (N_W/N_H, 0 =
    ; auto/flex) - the glue does flexbox; for canvas keep the laid-out
    ; size. labels don't use w/h.
    mov eax, [r13]
    cmp eax, 2
    je .size_canvas
    mov eax, [r15 + N_W]
    mov [rdi + 6], ax
    mov eax, [r15 + N_H]
    mov [rdi + 8], ax
    jmp .size_done
.size_canvas:
    mov eax, [r15 + N_AW]
    mov [rdi + 6], ax
    mov eax, [r15 + N_AH]
    mov [rdi + 8], ax
.size_done:
    ; cor
    mov eax, [r13]
    cmp eax, 2
    je .col_dark
    cmp eax, 1
    je .col_btn
    movzx ecx, byte [r15 + N_TAG]
    test ecx, ecx
    jnz .col_label
    cmp dword [r15 + N_BG], -1
    je .col_view_def
    mov eax, [r15 + N_BG]
    jmp .have_col
.col_view_def:
    ; NO background: transparent (alpha 0) - only explicit bg-* or the
    ; theme root paints a view
    xor eax, eax
    jmp .have_col_t
.col_label:
    cmp dword [r15 + N_COLOR], -1
    je .col_label_def
    mov eax, [r15 + N_COLOR]
    jmp .have_col
.col_label_def:
    mov eax, [theme_text]
    jmp .have_col
.col_btn:
    cmp dword [r15 + N_BG], -1
    je .col_btn_def
    mov eax, [r15 + N_BG]
    jmp .have_col
.col_btn_def:
    mov eax, [theme_accent]
    jmp .have_col
.col_dark:
    mov eax, 0x0F1117
.have_col:
    mov ecx, eax
    shr eax, 16
    mov [rdi + 12], al
    mov eax, ecx
    shr eax, 8
    mov [rdi + 13], al
    mov eax, ecx
    mov [rdi + 14], al
    mov byte [rdi + 15], 255
    jmp .col_alpha_done
.have_col_t:
    ; transparent: r=g=b=0, alpha=0
    mov byte [rdi + 12], 0
    mov byte [rdi + 13], 0
    mov byte [rdi + 14], 0
    mov byte [rdi + 15], 0
.col_alpha_done:
    ; parent
    mov [rdi + 20], r14d
    ; font size
    mov eax, [r13]
    cmp eax, 2
    je .fs_label
    test eax, eax
    jnz .fs_zero
    movzx ecx, byte [r15 + N_TAG]
    test ecx, ecx
    jz .fs_zero
.fs_label:
    movzx eax, byte [r15 + N_FS]
    mov [rdi + 24], al
    jmp .fs_done
.fs_zero:
    mov byte [rdi + 24], 0
.fs_done:
    ; text
    mov eax, [r13]
    cmp eax, 1
    je .no_text
    mov eax, [r15 + N_TEXT_PTR]
    test eax, eax
    jz .no_text
    mov ecx, [r15 + N_TEXT_LEN]
    ; dyn text (declarative state interpolation)? resolve to the INITIAL
    ; value so the SSR HTML and the first render match
    push rdi
    mov rdi, rbx                ; node idx
    call dyn_find
    pop rdi
    cmp rax, -1
    je .tx_plain
    ; ---- dyn: prefix + initial value + suffix into the blob ----
    imul rdx, rax, DYN_ENTRY
    lea rdx, [dyn_tab + rdx]
    ; cap check (template + margin for the value)
    mov eax, [blob_len]
    lea eax, [rax + rcx + 17]
    cmp eax, BLOB_CAP
    jg .err_blob
    mov eax, [blob_len]
    mov [rdi + 16], eax         ; text_offset
    push rax                    ; original blob_len (for the padding)
    lea r10, [blob_buf + rax]
    mov r11, r10                ; write pos
    ; prefix: template[0..D_PREFIX_LEN)
    mov esi, [r15 + N_TEXT_PTR]
    xor r8, r8
.tx_dp:
    cmp r8d, [rdx + D_PREFIX_LEN]   ; u32 compare! (r8 is 64-bit, the
    jge .tx_dv                      ; field is u32 - a qword read would
    mov al, [in_buf + rsi + r8]     ; swallow D_SUFFIX_OFF and loop forever)
    mov [r11], al
    inc r11
    inc r8
    jmp .tx_dp
.tx_dv:
    ; value
    push rdx
    mov edi, [rdx + D_STATE]    ; u32 fields!
    mov esi, [rdx + D_FIELD]
    mov rdx, r11
    call state_value_copy       ; rax = len
    add r11, rax
    pop rdx
    ; suffix: template[D_SUFFIX_OFF .. +D_SUFFIX_LEN)
    mov esi, [r15 + N_TEXT_PTR]
    add esi, [rdx + D_SUFFIX_OFF]
    xor r8, r8
.tx_ds:
    cmp r8d, [rdx + D_SUFFIX_LEN]   ; u32 compare (same trap as .tx_dp)
    jge .tx_dd
    mov al, [in_buf + rsi + r8]
    mov [r11], al
    inc r11
    inc r8
    jmp .tx_ds
.tx_dd:
    mov byte [r11], 0
    inc r11
    ; pad with zeros up to template_len + 16: the runtime montage
    ; rebuilds this text from the CURRENT value and may grow (multi-digit
    ; ints, longer strings), so the pool reserves slack here
    pop rcx                     ; original blob_len
    mov eax, [r15 + N_TEXT_LEN]
    add eax, 16
    add ecx, eax                ; target = orig + template_len + 16
    lea rax, [blob_buf]
    mov edx, r11d
    sub edx, eax                ; current blob len
.tx_pad:
    cmp edx, ecx
    jge .tx_pad_done
    mov byte [blob_buf + rdx], 0
    inc edx
    jmp .tx_pad
.tx_pad_done:
    mov [blob_len], edx
    jmp .next
.tx_plain:
    ; cap check
    mov eax, [blob_len]
    lea eax, [rax + rcx + 1]
    cmp eax, BLOB_CAP
    jg .err_blob
    mov eax, [blob_len]
    mov [rdi + 16], eax
    lea r10, [blob_buf + rax]
    mov esi, [r15 + N_TEXT_PTR]
    xor r8, r8
.copy_tx:
    cmp r8, rcx
    jge .copy_done
    mov al, [in_buf + rsi + r8]
    mov [r10 + r8], al
    inc r8
    jmp .copy_tx
.copy_done:
    mov byte [r10 + rcx], 0
    lea rax, [rcx + 1]
    add [blob_len], rax
    jmp .next
.no_text:
    mov dword [rdi + 16], 0
.next:
    inc r12
    jmp .loop
.err_blob:
    lea rdi, [msg_blob]
    mov rsi, msg_blob_len
    call die
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; emit_shell - <label>_shell: db '<div id="ui" data-modules="/<ui_name>.wasm"></div>', 10
    ;           db '<script type="module" src="/_asx/glue.js"></script>', 0
