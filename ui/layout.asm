; =============================================================================
; layout.asm - auto layout (visit, layout_node)
; =============================================================================

memcpy:
    xor rcx, rcx
.loop:
    cmp rcx, rdx
    jge .done
    mov al, [rsi + rcx]
    mov [rdi + rcx], al
    inc rcx
    jmp .loop
.done:
    ret

; ----------------------------------------------------------------------
; layout_all - layout vertical automatico dos roots (post-order)
; ----------------------------------------------------------------------
layout_all:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r12, r12
.loop:
    cmp r12, [node_count]
    jge .done
    imul rax, r12, NODE_SIZE
    lea rcx, [nodes + rax]
    cmp dword [rcx + N_PARENT], -1
    jne .next
    mov rdi, r12
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, 720
    call layout_node
.next:
    inc r12
    jmp .loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; layout_node(rdi = idx, rsi = x, rdx = y, rcx = w) -> rax = bottom y
; ----------------------------------------------------------------------
layout_node:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    imul rax, r12, NODE_SIZE
    lea rbx, [nodes + rax]
    mov eax, [rbx + N_MT]
    add r14, rax                ; y' = y + mt
    movzx eax, byte [rbx + N_TAG]
    cmp eax, 1
    je .label
    cmp eax, 2
    je .button
    ; ---- view ----
    mov [rbx + N_AX], r13d
    mov [rbx + N_AY], r14d
    mov eax, [rbx + N_W]
    test eax, eax
    jnz .view_w
    mov eax, r15d
.view_w:
    mov [rbx + N_AW], eax
    ; xin = x + pad, win = w - 2*pad, cy = y' + pad
    mov eax, [rbx + N_PAD]
    mov r9d, r13d
    add r9d, eax
    mov r10d, r15d
    sub r10d, eax
    sub r10d, eax
    lea r11d, [r14 + rax]
    mov r8d, [rbx + N_FIRST]
.child_loop:
    cmp r8d, -1
    je .children_done
    push r8
    push r9
    push r10
    push r11
    mov rdi, r8
    mov rsi, r9
    mov rdx, r11
    mov rcx, r10
    call layout_node
    pop r11
    pop r10
    pop r9
    pop r8
    mov r11, rax                ; cy = bottom do filho
    mov rax, r8
    imul rax, rax, NODE_SIZE
    lea rax, [nodes + rax]
    mov r8d, [rax + N_NEXT]
    jmp .child_loop
.children_done:
    ; ah = max(0, cy - ay - mb) + pad
    mov eax, r11d
    sub eax, [rbx + N_AY]
    sub eax, [rbx + N_MB]
    test eax, eax
    jns .ah_ok
    xor eax, eax
.ah_ok:
    add eax, [rbx + N_PAD]
    mov [rbx + N_AH], eax
    mov eax, [rbx + N_AY]
    add eax, [rbx + N_AH]
    add eax, [rbx + N_MB]
    jmp .done
.label:
    ; tw = len*fs*62/100 ; ax = xin, ay = y' ; ah = fs*1.5
    mov eax, [rbx + N_TEXT_LEN]
    imul eax, [rbx + N_FS]
    imul eax, 62
    xor edx, edx
    mov ecx, 100
    div ecx
    mov ecx, [rbx + N_PAD]
    lea ecx, [r13 + rcx]
    mov [rbx + N_AX], ecx
    mov [rbx + N_AY], r14d
    mov [rbx + N_AW], eax
    mov eax, [rbx + N_FS]
    imul eax, 3
    xor edx, edx
    mov ecx, 2
    div ecx
    mov [rbx + N_AH], eax
    mov eax, [rbx + N_AY]
    add eax, [rbx + N_AH]
    add eax, [rbx + N_MB]
    jmp .done
.button:
    ; tw = text_width(len ou 1, fs); aw = tw + 2*pad; ah = fs*1.5 + 2*pad
    mov eax, [rbx + N_TEXT_LEN]
    test eax, eax
    jnz .btn_len
    mov eax, 1
.btn_len:
    imul eax, [rbx + N_FS]
    imul eax, 62
    xor edx, edx
    mov ecx, 100
    div ecx
    mov ecx, [rbx + N_PAD]
    lea ecx, [r13 + rcx]
    mov [rbx + N_AX], ecx
    mov [rbx + N_AY], r14d
    mov ecx, [rbx + N_PAD]
    lea ecx, [rcx + rcx]
    add eax, ecx
    mov [rbx + N_AW], eax
    mov eax, [rbx + N_FS]
    imul eax, 3
    xor edx, edx
    mov ecx, 2
    div ecx
    mov edx, [rbx + N_PAD]
    lea edx, [rdx + rdx]
    add eax, edx
    mov [rbx + N_AH], eax
    mov eax, [rbx + N_AY]
    add eax, [rbx + N_AH]
    add eax, [rbx + N_MB]
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; build_records - pre-order (parent before child) -> rec_order/rec_count.
; a button becomes 2 records: view (kind 1) + label (kind 2).
; ----------------------------------------------------------------------
build_records:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov qword [rec_count], 0
    xor r12, r12
.loop:
    cmp r12, [node_count]
    jge .done
    imul rax, r12, NODE_SIZE
    lea rcx, [nodes + rax]
    cmp dword [rcx + N_PARENT], -1
    jne .next
    mov rdi, r12
    mov rsi, -1
    call visit
.next:
    inc r12
    jmp .loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; visit(rdi = node idx, rsi = parent record idx)
