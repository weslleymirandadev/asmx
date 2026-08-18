; =============================================================================
; emit.asm - page.s shell + component .wat
; =============================================================================

emit_shell:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea rdi, [s_sh1]
    call out_label
    mov al, 39
    call out_byte
    lea rdi, [s_sh2]
    call out_str
    lea rdi, [ui_name_buf]
    mov rsi, [ui_name_len]
    call out_bytes
    ; suffix: index (root) -> ".wasm"; other routes -> "/page.wasm"
    cmp qword [ui_name_len], 5
    jne .use_page
    cmp byte [ui_name_buf], 'i'
    jne .use_page
    cmp byte [ui_name_buf + 1], 'n'
    jne .use_page
    cmp byte [ui_name_buf + 2], 'd'
    jne .use_page
    cmp byte [ui_name_buf + 3], 'e'
    jne .use_page
    cmp byte [ui_name_buf + 4], 'x'
    jne .use_page
    lea rdi, [s_sh3i]           ; '.wasm"></div>'
    jmp .emit_suf
.use_page:
    lea rdi, [s_sh3]            ; '/page.wasm"></div>'
.emit_suf:
    call out_str
    mov al, 39
    call out_byte
    lea rdi, [s_sh4]
    call out_str
    lea rdi, [s_sh5]
    call out_str
    mov al, 39
    call out_byte
    lea rdi, [s_sh6]
    call out_str
    mov al, 39
    call out_byte
    lea rdi, [s_sh7]
    call out_str
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; emit_wat_componente - writes the $c_<label> function (the scene) to wat_buf
; + string data segments. str_cursor advances over the pool.
; ----------------------------------------------------------------------
emit_wat_componente:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov qword [wat_len], 0
    lea rdi, [s_wat_h1]
    call out_wat_str
    lea rdi, [label_buf]
    mov rsi, [label_len]
    call out_wat_bytes
    lea rdi, [s_wat_h2]
    call out_wat_str
    lea rdi, [s_wat_fn1]
    call out_wat_str
    lea rdi, [label_buf]
    mov rsi, [label_len]
    call out_wat_bytes
    lea rdi, [s_wat_fn2]
    call out_wat_str
    ; pass 1: count views (type 0) -> local_of[record] and n_locals
    xor r12, r12                ; i
    xor r13, r13                ; n_locals
.l1:
    cmp r12, [rec_count]
    jge .l1d
    mov rax, r12
    imul rax, rax, 32
    lea rcx, [blob_buf + rax + 24]
    cmp byte [rcx], 0
    jne .l1n
    mov [local_of + r12*4], r13d
    inc r13
.l1n:
    inc r12
    jmp .l1
.l1d:
    ; (local $vN i32) por view
    xor r14, r14
.locals:
    cmp r14, r13
    jge .locals_done
    lea rdi, [s_wat_loc1]
    call out_wat_str
    mov rdi, r14
    call itoa_wat
    lea rdi, [s_wat_loc2]
    call out_wat_str
    inc r14
    jmp .locals
.locals_done:
    ; pass 2: the calls
    xor r12, r12
.l2:
    cmp r12, [rec_count]
    jge .l2d
    mov rax, r12
    imul rax, rax, 32
    lea r15, [blob_buf + rax + 24]
    movzx eax, byte [r15]
    test eax, eax
    jnz .l2_label
    ; ---- view ----
    movzx edi, word [r15 + 2]
    call emit_wat_i32
    movzx edi, word [r15 + 4]
    call emit_wat_i32
    movzx edi, word [r15 + 6]
    call emit_wat_i32
    movzx edi, word [r15 + 8]
    call emit_wat_i32
    movzx edi, byte [r15 + 12]
    call emit_wat_i32
    movzx edi, byte [r15 + 13]
    call emit_wat_i32
    movzx edi, byte [r15 + 14]
    call emit_wat_i32
    mov edi, [r15 + 20]         ; parent
    call emit_wat_parent
    lea rdi, [s_wat_view]
    call out_wat_str
    ; local.set $v<local_of[i]>
    mov edi, [local_of + r12*4]
    call itoa_wat
    lea rdi, [s_wat_fn2]        ; "\n"
    call out_wat_str
    jmp .l2n
.l2_label:
    movzx edi, word [r15 + 2]
    call emit_wat_i32
    movzx edi, word [r15 + 4]
    call emit_wat_i32
    movzx edi, word [r15 + 6]
    call emit_wat_i32
    movzx edi, word [r15 + 8]
    call emit_wat_i32
    mov edi, [r15 + 16]         ; text_offset
    call emit_wat_textptr
    mov edi, [r15 + 20]         ; parent
    call emit_wat_parent
    movzx edi, byte [r15 + 24]  ; fs
    call emit_wat_i32
    movzx edi, byte [r15 + 12]
    call emit_wat_i32
    movzx edi, byte [r15 + 13]
    call emit_wat_i32
    movzx edi, byte [r15 + 14]
    call emit_wat_i32
    lea rdi, [s_wat_lbl]
    call out_wat_str
.l2n:
    inc r12
    jmp .l2
.l2d:
    lea rdi, [s_wat_close]
    call out_wat_str
    ; string data segments (text_offset relative to the blob)
    xor r12, r12
.dl:
    cmp r12, [rec_count]
    jge .dd
    mov rax, r12
    imul rax, rax, 32
    lea r15, [blob_buf + rax + 24]
    mov eax, [r15 + 16]
    test eax, eax
    jz .dn
    mov rdi, rax
    call wat_text_addr          ; rax = endereco wasm da string
    mov rbx, rax
    lea rdi, [s_wat_d1]
    call out_wat_str
    mov rdi, rbx
    call itoa_wat
    lea rdi, [s_wat_d2]
    call out_wat_str
    ; text: [blob_buf + text_offset] up to the 0 (pool null)
    mov esi, [r15 + 16]
    lea rdi, [blob_buf + rsi]
    mov rsi, rdi
.tx_scan:
    cmp byte [rsi], 0
    je .tx_found
    inc rsi
    jmp .tx_scan
.tx_found:
    sub rsi, rdi                ; text length
    call out_wat_text
    lea rdi, [s_wat_d3]
    call out_wat_str
.dn:
    inc r12
    jmp .dl
.dd:
    ; str_cursor += tamanho do pool (blob_len - 24 - count*32)
    mov eax, [blob_len]
    sub eax, 24
    mov ecx, [rec_count]
    imul ecx, ecx, 32
    sub eax, ecx
    add [str_cursor], rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; emit_wat_i32(rdi = val) - "  i32.const <val>\n"
emit_wat_i32:
    push r12
    mov r12, rdi
    lea rdi, [s_wat_i32]
    call out_wat_str
    mov rdi, r12
    call itoa_wat
    lea rdi, [s_wat_fn2]
    call out_wat_str
    pop r12
    ret

; emit_wat_parent(rdi = parent record idx) - local.get $vN or i32.const -1
emit_wat_parent:
    push r12
    mov r12d, edi               ; parent (u32; -1 = 0xFFFFFFFF)
    cmp r12d, -1
    je .root
    lea rdi, [s_wat_lget]
    call out_wat_str
    mov eax, [local_of + r12*4]
    mov rdi, rax
    call itoa_wat
    lea rdi, [s_wat_fn2]
    call out_wat_str
    jmp .done
.root:
    lea rdi, [s_wat_m1]
    call out_wat_str
.done:
    pop r12
    ret

; emit_wat_textptr(rdi = text_offset relative to the blob) - i32.const <addr>
emit_wat_textptr:
    push r12
    push r13
    mov r12, rdi
    lea rdi, [s_wat_i32]
    call out_wat_str
    test r12, r12
    jz .zero
    mov rdi, r12
    call wat_text_addr          ; rax = endereco
    mov rdi, rax
    call itoa_wat
    jmp .done
.zero:
    ; no text: i32.const 0 (don't leak a garbage address)
    mov rdi, 0
    call itoa_wat
.done:
    lea rdi, [s_wat_fn2]
    call out_wat_str
    pop r13
    pop r12
    ret

; wat_text_addr(rdi = text_offset) -> rax = STR_BASE + str_cursor + pool_pos
wat_text_addr:
    mov rax, [str_cursor]
    add rax, STR_BASE
    add rax, rdi                ; + text_offset
    sub rax, 24                 ; - header
    mov rcx, [rec_count]
    imul rcx, rcx, 32
    sub rax, rcx                ; - records = pool_pos
    ret

; out_wat_text(rdi = ptr, rsi = len) - text with escapes (", \, <0x20)
out_wat_text:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov rbx, rsi
    xor r13, r13
.loop:
    cmp r13, rbx
    jge .done
    mov al, [r12 + r13]
    cmp al, '"'
    je .esc_quote
    cmp al, 0x5C                ; '\\'
    je .esc_bs
    cmp al, 0x20
    jb .esc_hex
    call out_wat_byte
    jmp .next
.esc_quote:
    lea rdi, [s_wat_q]
    call out_wat_str
    jmp .next
.esc_bs:
    lea rdi, [s_wat_bs]
    call out_wat_str
    jmp .next
.esc_hex:
    ; \hh
    lea rdi, [s_wat_bs]
    call out_wat_str
    push rax
    shr al, 4
    call out_wat_nibble
    pop rax
    and al, 0x0f
    call out_wat_nibble
.next:
    inc r13
    jmp .loop
.done:
    pop r13
    pop r12
    pop rbx
    ret

; out_wat_nibble(al = 0..15)
out_wat_nibble:
    cmp al, 10
    jl .digit
    add al, 'a' - 10
    jmp out_wat_byte
.digit:
    add al, '0'
    jmp out_wat_byte

; ----------------------------------------------------------------------
; append_wat_call - appends "  call $c_<label>\n" to the final module.
; On the first component it also writes the render header.
