; =============================================================================
; expand.asm - @@ component expansion (src/components/*.s, {param} args)
; =============================================================================
;
; A line like  @@ <name> key="value" ...  inside an @ DSL block is
; replaced at compile time by the <name>: block of src/components/<name>.s:
;   - every line is re-indented to the @@ line level (nesting works);
;   - {key} placeholders are substituted by the given values.
; Nested @@ lines inside a component expand recursively (depth-limited).
; The in_buf is rewritten in place (in_len grows/shrinks).

; ----------------------------------------------------------------------
; expand_block(rdi = start_off, rsi = end_off) -> rax = new block end.
; Scans the in_buf block [start, end) line by line; every @@ line is
; spliced. Arg pointers into the in_buf stay valid until the splice.
; ----------------------------------------------------------------------
expand_block:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; cur
    mov r13, rsi                ; block end
    mov qword [comp_depth], 0
    ; preserve the caller's label_buf (find_comp_block's is_label clobbers it)
    mov rax, [label_len]
    mov [save_label_len], rax
    xor rcx, rcx
.sl:
    cmp rcx, 64
    jge .sl_done
    mov al, [label_buf + rcx]
    mov [save_label_buf + rcx], al
    inc rcx
    jmp .sl
.sl_done:
.loop:
    cmp r12, r13
    jge .done
    ; line [r12, r15)
    mov r15, r12
.scan:
    cmp r15, r13
    jge .have
    cmp byte [in_buf + r15], 10
    je .have
    inc r15
    jmp .scan
.have:
    ; indent: rbx = first non-space char
    mov rbx, r12
.indent:
    cmp rbx, r15
    jge .next_line
    mov al, [in_buf + rbx]
    cmp al, ' '
    je .in_ind
    cmp al, 9
    jne .ind_done
.in_ind:
    inc rbx
    jmp .indent
.ind_done:
    ; depth pop: line indent < open @@ indent -> left the component
.pop:
    cmp qword [comp_depth], 0
    je .no_pop
    mov rax, [comp_depth]
    dec rax
    mov rcx, rbx
    sub rcx, r12                ; line indent
    cmp rcx, [comp_stack + rax * 8]
    jge .no_pop
    dec qword [comp_depth]
    jmp .pop
.no_pop:
    ; "@@"? (custom component instantiation: @@card key="value")
    cmp rbx, r15
    jge .next_line
    cmp byte [in_buf + rbx], '@'
    jne .next_line
    lea r8, [rbx + 1]
    cmp r8, r15
    jge .next_line
    cmp byte [in_buf + r8], '@'
    jne .next_line
    lea r8, [rbx + 2]           ; the component name starts here
.is_comp:
    cmp qword [comp_depth], MAX_COMP_DEPTH
    jge .too_deep
    ; parse the name + args (ptrs into in_buf; valid until the splice)
    lea rdi, [in_buf + r8]
    lea rsi, [in_buf + r15]     ; line end POINTER (r15 is an offset)
    call parse_comp_args
    ; load src/components/<name>.s into comp_buf
    call load_component
    ; find the <name>: block inside comp_buf
    call find_comp_block        ; rax = content start, rdx = content end
    mov r14, rax
    mov rbx, rdx                ; comp block end (callee-saved)
    ; build the expanded block: re-indent + {param} substitution
    mov rdi, r12                ; @@ line start
    mov rsi, r14                ; comp content start
    mov rdx, rbx                ; comp content end
    call build_expand
    ; splice the expanded block over the @@ line [r12, r15)
    mov rdi, r12
    mov rsi, r15
    call splice_in              ; rax = delta
    add r13, rax                ; block end moved
    ; push the @@ indent (depth tracking), then re-scan the inserted lines
    mov rcx, r12
.ind2:
    cmp byte [in_buf + rcx], '@'
    je .ind2_done
    inc rcx
    jmp .ind2
.ind2_done:
    sub rcx, r12                ; indent
    mov rax, [comp_depth]
    mov [comp_stack + rax * 8], rcx
    inc qword [comp_depth]
    jmp .loop                   ; cur stays at r12: scan the inserted block
.next_line:
    mov r12, r15
    cmp r12, r13
    jge .done
    cmp byte [in_buf + r12], 10
    jne .done
    inc r12
    jmp .loop
.done:
    ; restore the caller's label_buf
    mov rax, [save_label_len]
    mov [label_len], rax
    xor rcx, rcx
.rl:
    cmp rcx, 64
    jge .rl_done
    mov al, [save_label_buf + rcx]
    mov [label_buf + rcx], al
    inc rcx
    jmp .rl
.rl_done:
    mov rax, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.too_deep:
    lea rdi, [msg_comp_depth]
    mov rsi, msg_comp_depth_len
    call die

; ----------------------------------------------------------------------
; parse_comp_args(rdi = name token ptr, rsi = line end)
; Parses "<name> key=\"value\" ..." into comp_name/comp_name_len and
; arg_list/arg_count. Args point INTO the in_buf (valid until the splice).
; ----------------------------------------------------------------------
parse_comp_args:
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; cur
    mov r13, rsi                ; line end
    mov qword [arg_count], 0
    ; skip leading spaces (the caller points right after "comp")
.lead:
    cmp r12, r13
    jge .err
    mov al, [r12]
    cmp al, ' '
    je .lead_inc
    cmp al, 9
    jne .lead_done
.lead_inc:
    inc r12
    jmp .lead
.lead_done:
    ; --- name: [r12, r14) ---
    mov r14, r12
.sn:
    cmp r14, r13
    jge .sn_done
    mov al, [r14]
    cmp al, ' '
    je .sn_done
    cmp al, 9
    je .sn_done
    inc r14
    jmp .sn
.sn_done:
    mov rax, r14
    sub rax, r12
    mov [comp_name_len], rax
    cmp rax, 64
    jge .err
    xor r8, r8
.cp:
    cmp r8, rax
    jge .cp_done
    mov cl, [r12 + r8]
    mov [comp_name + r8], cl
    inc r8
    jmp .cp
.cp_done:
    ; --- args: key="value" pairs ---
    mov r15, r14
.arg_loop:
    ; skip spaces
.as:
    cmp r15, r13
    jge .args_done
    mov al, [r15]
    cmp al, ' '
    je .as_inc
    cmp al, 9
    jne .as_done
.as_inc:
    inc r15
    jmp .as
.as_done:
    cmp r15, r13
    jge .args_done
    ; key = [r15, r8) until '='
    mov r8, r15
.ks:
    cmp r8, r13
    jge .err
    cmp byte [r8], '='
    je .ks_done
    inc r8
    jmp .ks
.ks_done:
    ; value = "..." (quoted)
    inc r8                      ; skip '='
    cmp r8, r13
    jge .err
    cmp byte [r8], '"'
    jne .err
    inc r8                      ; skip '"'
    mov r9, r8                  ; value start
.vs:
    cmp r9, r13
    jge .err
    cmp byte [r9], '"'
    je .vs_done
    inc r9
    jmp .vs
.vs_done:
    ; entry: {key_ptr, key_len, val_ptr, val_len} (dq each)
    mov rax, [arg_count]
    cmp rax, MAX_ARGS
    jge .err
    imul rcx, rax, ARG_ENTRY_SIZE
    lea r10, [arg_list + rcx]
    mov [r10], r15              ; key ptr
    mov r11, r8
    sub r11, r15
    sub r11, 2                  ; key len (without '=' and the opening quote)
    mov [r10 + 8], r11
    mov [r10 + 16], r8          ; val ptr (after the quote)
    mov r11, r9
    sub r11, r8
    mov [r10 + 24], r11         ; val len
    inc qword [arg_count]
    mov r15, r9
    inc r15                     ; skip the closing quote
    jmp .arg_loop
.args_done:
    pop r15
    pop r14
    pop r13
    pop r12
    ret
.err:
    lea rdi, [msg_comp_args]
    mov rsi, msg_comp_args_len
    call die

; ----------------------------------------------------------------------
; load_component - builds comp_path = "src/components/<name>.s" and reads
; it into comp_buf/comp_len. Dies on a missing file.
; ----------------------------------------------------------------------
load_component:
    push r12
    push r13
    lea rdi, [comp_path]
    lea rsi, [s_components]
    call strcpy_l               ; rax = dst end (null included)
    mov r12, rax
    mov r13, [comp_name_len]
    mov rdi, r12
    lea rsi, [comp_name]
    mov rdx, r13
    call memcpy
    mov rdi, r12
    add rdi, r13
    mov byte [rdi], '.'
    mov byte [rdi + 1], 's'
    mov byte [rdi + 2], 0
    lea rdi, [comp_path]
    lea rsi, [comp_buf]
    mov rdx, IN_CAP
    call read_file_to
    test rax, rax
    js .err
    mov [comp_len], rax
    pop r13
    pop r12
    ret
.err:
    lea rdi, [msg_comp_missing]
    mov rsi, msg_comp_missing_len
    call die

; ----------------------------------------------------------------------
; find_comp_block - scans comp_buf for the "<name>:" label and returns its
; @ block: rax = content start, rdx = content end (offsets into comp_buf).
; The same block rules as find_block_end (empty/comment lines continue;
; @ and " with indent > 0 continue; anything else ends the block).
; ----------------------------------------------------------------------
find_comp_block:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r12, r12                ; cur
.loop:
    mov r13, [comp_len]
    cmp r12, r13
    jge .err
    ; line [r12, r14)
    mov r14, r12
.scan:
    cmp r14, r13
    jge .have
    cmp byte [comp_buf + r14], 10
    je .have
    inc r14
    jmp .scan
.have:
    lea rdi, [comp_buf + r12]
    mov rsi, r14
    sub rsi, r12
    call is_label               ; fills label_buf/label_len
    test rax, rax
    jz .next
    ; label == comp_name?
    lea rdi, [label_buf]
    lea rsi, [comp_name]
    mov rdx, [comp_name_len]
    call strncmp
    test rax, rax
    jnz .next
    ; found: content = the next line, must be '@' with indent > 0
    mov rdi, r14
    cmp rdi, r13
    jge .err
    cmp byte [comp_buf + rdi], 10
    jne .err
    inc rdi
.cl:
    cmp rdi, r13
    jge .err
    mov r15, rdi
.cscan:
    cmp r15, r13
    jge .chave
    cmp byte [comp_buf + r15], 10
    je .chave
    inc r15
    jmp .cscan
.chave:
    mov r8, rdi
.cs_ind:
    cmp r8, r15
    jge .c_next
    mov al, [comp_buf + r8]
    cmp al, ' '
    je .cs_i
    cmp al, 9
    jne .cs_done
.cs_i:
    inc r8
    jmp .cs_ind
.cs_done:
    cmp r8, r15
    jge .c_next
    mov al, [comp_buf + r8]
    cmp al, ';'
    je .c_next
    cmp al, '@'
    jne .err
    cmp r8, rdi
    jle .err                    ; indent == 0
    ; content start = rdi; find the block end (comp_buf-based)
    mov r15, rdi                ; -> return value (rax dies in the scan: mov al)
    mov r12, rdi                ; line start for the end scan
.be_loop:
    mov r8, r12
.be_scan:
    cmp r8, r13
    jge .be_done
    cmp byte [comp_buf + r8], 10
    je .be_have
    inc r8
    jmp .be_scan
.be_have:
    mov r9, r12
.be_ind:
    cmp r9, r8
    jge .be_next
    mov al, [comp_buf + r9]
    cmp al, ' '
    je .be_i
    cmp al, 9
    jne .be_stripped
.be_i:
    inc r9
    jmp .be_ind
.be_stripped:
    cmp r9, r8
    jge .be_next
    mov al, [comp_buf + r9]
    cmp al, ';'
    je .be_next
    cmp al, '@'
    je .be_q
    cmp al, '"'
    je .be_q
    jmp .be_done
.be_q:
    cmp r9, r12
    jle .be_done                ; indent == 0 -> ends the block
    jmp .be_next
.be_next:
    mov r12, r8
    cmp r12, r13
    jge .be_done
    cmp byte [comp_buf + r12], 10
    jne .be_done
    inc r12
    jmp .be_loop
.be_done:
    mov rdx, r12                ; block end (-> return value)
    mov rax, r15                ; content start (restore: al was clobbered by the scan)
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.c_next:
    mov rdi, r15
    cmp rdi, r13
    jge .err
    cmp byte [comp_buf + rdi], 10
    jne .err
    inc rdi
    jmp .cl
.next:
    mov r12, r14
    cmp r12, r13
    jge .err
    cmp byte [comp_buf + r12], 10
    jne .err
    inc r12
    jmp .loop
.err:
    lea rdi, [msg_comp_label]
    mov rsi, msg_comp_label_len
    call die

; ----------------------------------------------------------------------
; build_expand(rdi = @@ line start, rsi = comp content start,
;              rdx = comp content end) - builds expand_buf/expand_len:
;   delta = @@ line indent - comp base indent (clamped to 0)
;   each comp line: (delta) spaces + the line with {key} substituted
; ----------------------------------------------------------------------
build_expand:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; @@ line start
    mov r13, rsi                ; comp content start
    mov r14, rdx                ; comp content end
    mov qword [expand_len], 0
    ; @@ line indent
    mov r15, r12
.ic:
    cmp byte [in_buf + r15], '@'
    je .ic_done
    inc r15
    jmp .ic
.ic_done:
    mov rax, r15
    sub rax, r12                ; @@ indent
    ; comp base indent (the first content line)
    mov r15, r13
.cb:
    cmp byte [comp_buf + r15], '@'
    je .cb_done
    inc r15
    jmp .cb
.cb_done:
    sub r15, r13
    sub rax, r15                ; delta indent
    test rax, rax
    jns .ok_d
    xor rax, rax
.ok_d:
    mov r15, rax                ; delta indent
    ; per line
    mov r12, r13
.line_loop:
    cmp r12, r14
    jge .done
    mov r13, r12
.ls:
    cmp r13, r14
    jge .lh
    cmp byte [comp_buf + r13], 10
    je .lh
    inc r13
    jmp .ls
.lh:
    ; emit the indent (delta spaces)
    mov rax, [expand_len]
    lea rdi, [expand_buf + rax]
    xor rcx, rcx
.ind_loop:
    cmp rcx, r15
    jge .no_ind
    mov byte [rdi + rcx], ' '
    inc rcx
    jmp .ind_loop
.no_ind:
    add [expand_len], r15
    ; copy the line with {param} substitution
    mov rdi, r12
    mov rsi, r13
    call copy_subst
    ; newline
    mov rax, [expand_len]
    mov byte [expand_buf + rax], 10
    inc qword [expand_len]
    mov r12, r13
    cmp r12, r14
    jge .done
    cmp byte [comp_buf + r12], 10
    jne .done
    inc r12
    jmp .line_loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; copy_subst(rdi = line start, rsi = line end) - copies [start, end) from
; comp_buf to expand_buf, replacing {key} with the arg value (dies on an
; unknown placeholder).
; ----------------------------------------------------------------------
copy_subst:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi                ; cur
    mov r13, rsi                ; line end
.loop:
    cmp r12, r13
    jge .done
    mov bl, [comp_buf + r12]    ; byte (bl survives the expand_len load below)
    cmp bl, '{'
    je .ph
    mov rax, [expand_len]
    mov [expand_buf + rax], bl
    inc qword [expand_len]
    inc r12
    jmp .loop
.ph:
    ; name = [r12+1, r14)
    mov r14, r12
    inc r14
.pn:
    cmp r14, r13
    jge .err
    cmp byte [comp_buf + r14], '}'
    je .pn_done
    inc r14
    jmp .pn
.pn_done:
    lea rdi, [comp_buf + r12 + 1]
    mov rsi, r14
    sub rsi, r12
    dec rsi                     ; name len
    call arg_lookup             ; rax = val ptr, rdx = val len
    cmp rax, -1
    je .err
    mov rbx, rdx                ; val len (rdx dies in the copy loop)
    mov r9, [expand_len]
    xor r8, r8
.vc:
    cmp r8, rbx
    jge .vc_done
    mov cl, [rax + r8]
    mov [expand_buf + r9 + r8], cl
    inc r8
    jmp .vc
.vc_done:
    add [expand_len], rbx
    mov r12, r14
    inc r12                     ; skip '}'
    jmp .loop
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.err:
    lea rdi, [msg_comp_param]
    mov rsi, msg_comp_param_len
    call die

; ----------------------------------------------------------------------
; arg_lookup(rdi = key ptr, rsi = key len) -> rax = val ptr, rdx = val len
; (or -1 if the key is not among the @@ args)
; ----------------------------------------------------------------------
arg_lookup:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    xor rbx, rbx                ; i (rbx survives the strncmp below)
.loop:
    cmp rbx, [arg_count]
    jge .none
    imul rax, rbx, ARG_ENTRY_SIZE
    lea rdx, [arg_list + rax]
    cmp [rdx + 8], r13          ; key len matches?
    jne .next
    mov rdi, r12
    mov rsi, [rdx]              ; key ptr
    mov rdx, r13
    call strncmp                ; clobbers rcx and rdx (r12/r13/rbx saved)
    test rax, rax
    jnz .next
    imul rax, rbx, ARG_ENTRY_SIZE
    lea rdx, [arg_list + rax]
    mov rax, [rdx + 16]         ; val ptr
    mov rdx, [rdx + 24]         ; val len
    pop r13
    pop r12
    pop rbx
    ret
.next:
    inc rbx
    jmp .loop
.none:
    mov rax, -1
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; splice_in(rdi = line start, rsi = line end) - replaces [start, end) plus
; its newline with expand_buf/expand_len. Returns rax = delta (may be
; negative when the component is smaller than the @@ line).
; ----------------------------------------------------------------------
splice_in:
    push rbx
    push r12
    push r13
    mov r12, rdi                ; line start
    mov r13, rsi                ; line end
    ; src = line end + 1 (skip the \n if present)
    mov rbx, r13
    cmp rbx, [in_len]
    jge .no_nl
    cmp byte [in_buf + rbx], 10
    jne .no_nl
    inc rbx
.no_nl:
    ; move [src, in_len) to [line_start + expand_len, ...) backwards
    mov rax, [in_len]
    sub rax, rbx                ; n
    mov rdx, [expand_len]
    lea rdi, [in_buf + r12]
    add rdi, rdx                ; dst
    lea rsi, [in_buf + rbx]     ; src
    mov rdx, rax                ; n
    call memmove_back
    ; copy the expanded block over the @@ line
    lea rdi, [in_buf + r12]     ; r12 is an offset, not a pointer
    lea rsi, [expand_buf]
    mov rdx, [expand_len]
    call memcpy
    ; delta = expand_len - (src - line_start); in_len += delta
    mov rax, [expand_len]
    mov rcx, rbx
    sub rcx, r12
    sub rax, rcx
    add [in_len], rax
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; memmove_back(rdi = dst, rsi = src, rdx = n) - copies [src, src+n) to
; [dst, dst+n) from the end backwards (required when dst > src overlaps).
; ----------------------------------------------------------------------
memmove_back:
    test rdx, rdx
    jz .done
    lea rdi, [rdi + rdx - 1]
    lea rsi, [rsi + rdx - 1]
    mov rcx, rdx
    std
    rep movsb
    cld
.done:
    ret
