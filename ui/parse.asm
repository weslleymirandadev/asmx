; =============================================================================
; parse.asm - is_label, compile_block, class_apply, tailwind lookups
; =============================================================================

is_label:
    xor r8, r8                  ; pos
    xor r9, r9                  ; name len
.skip1:
    cmp r8, rsi
    jge .no
    mov al, [rdi + r8]
    cmp al, ' '
    je .s1_inc
    cmp al, 9
    jne .first
.s1_inc:
    inc r8
    jmp .skip1
.first:
    mov al, [rdi + r8]
    call is_alpha_underscore
    test al, al
    jz .no
    mov r10, r8                 ; name start (for the copy)
.name:
    cmp r8, rsi
    jge .after_name
    mov al, [rdi + r8]
    call is_alnum_underscore
    test al, al
    jz .after_name
    inc r9
    inc r8
    jmp .name
.after_name:
    test r9, r9
    jz .no
.skip2:
    cmp r8, rsi
    jge .no
    mov al, [rdi + r8]
    cmp al, ' '
    je .s2_inc
    cmp al, 9
    jne .colon
.s2_inc:
    inc r8
    jmp .skip2
.colon:
    cmp byte [rdi + r8], ':'
    jne .no
    inc r8
.skip3:
    cmp r8, rsi
    jge .yes
    mov al, [rdi + r8]
    cmp al, ' '
    je .s3_inc
    cmp al, 9
    jne .tail
.s3_inc:
    inc r8
    jmp .skip3
.tail:
    cmp byte [rdi + r8], ';'
    jne .no
.yes:
    xor rcx, rcx
.copy:
    cmp rcx, r9
    jge .copy_done
    mov al, [rdi + r10]
    mov [label_buf + rcx], al
    inc r10
    inc rcx
    jmp .copy
.copy_done:
    mov [label_len], r9
    mov rax, 1
    ret
.no:
    xor rax, rax
    ret

; is_alpha_underscore(al) -> al = 1 se [A-Za-z_]
is_alpha_underscore:
    cmp al, '_'
    je .yes
    cmp al, 'A'
    jb .no
    cmp al, 'Z'
    jbe .yes
    cmp al, 'a'
    jb .no
    cmp al, 'z'
    ja .no
.yes:
    mov al, 1
    ret
.no:
    xor al, al
    ret

; is_alnum_underscore(al) -> al = 1 se [A-Za-z0-9_]
is_alnum_underscore:
    cmp al, '0'
    jb is_alpha_underscore
    cmp al, '9'
    jbe .yes
    jmp is_alpha_underscore
.yes:
    mov al, 1
    ret

; ----------------------------------------------------------------------
; find_content(rdi = offset) -> rax = offset of the next line with
; content (not empty, not a comment) or -1
; ----------------------------------------------------------------------
find_content:
    push rbx
    push r12
    push r13
    mov r12, rdi
.loop:
    mov r13, r12
.scan:
    cmp r13, [in_len]
    jge .none
    cmp byte [in_buf + r13], 10
    je .line_end
    inc r13
    jmp .scan
.line_end:
    mov rbx, r12
.skip:
    cmp rbx, r13
    jge .next
    mov al, [in_buf + rbx]
    cmp al, ' '
    je .sk_inc
    cmp al, 9
    jne .check
.sk_inc:
    inc rbx
    jmp .skip
.check:
    cmp byte [in_buf + rbx], ';'
    je .next
    mov rax, r12
    jmp .done
.next:
    mov r12, r13
    inc r12
    cmp r12, [in_len]
    jl .loop
.none:
    mov rax, -1
.done:
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; find_block_end(rdi = start) -> rax = offset of the first line outside the block.
; Empty/comment lines continue the block; @ and " with indent > 0
; continue; any other line ends it.
; ----------------------------------------------------------------------
find_block_end:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
.loop:
    cmp r12, [in_len]
    jge .done
    mov r13, r12
.scan:
    cmp r13, [in_len]
    jge .have_line
    cmp byte [in_buf + r13], 10
    je .have_line
    inc r13
    jmp .scan
.have_line:
    mov r14, r12
.indent:
    cmp r14, r13
    jge .next                  ; empty line -> continue
    mov al, [in_buf + r14]
    cmp al, ' '
    je .in_inc
    cmp al, 9
    jne .stripped
.in_inc:
    inc r14
    jmp .indent
.stripped:
    cmp r14, r13
    jge .next
    mov al, [in_buf + r14]
    cmp al, ';'
    je .next                   ; comentario -> continua
    cmp al, '@'
    je .at_q
    cmp al, '"'
    je .at_q
    ; keyword directive without '@' (state/type)? continues the block
    mov rdi, r14
    mov rsi, r13
    push r12
    push r13
    call is_directive
    pop r13
    pop r12
    test rax, rax
    jnz .next
    ; "field: value" body line of a type/state directive? (indented)
    mov rdi, r14
    mov rsi, r13
    push r12
    push r13
    call line_has_colon
    pop r13
    pop r12
    test rax, rax
    jz .not_block
    cmp r14, r12
    jle .not_block             ; a bare "name:" at column 0 ends it
    jmp .next
.not_block:
    mov rax, r12
    jmp .done
.at_q:
    cmp r14, r12
    jle .not_block             ; indent == 0
    jmp .next
.next:
    mov r12, r13
    cmp r12, [in_len]
    jge .done
    cmp byte [in_buf + r12], 10
    jne .done
    inc r12
    jmp .loop
.done:
    mov rax, r12                ; ALWAYS set the return (block reaches end of file)
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; compile_block(rdi = start, rsi = end) - parses the block -> nodes + layout
; + records + blob (blob_buf/blob_len ready for the emit)
; ----------------------------------------------------------------------
compile_block:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; cur
    mov r13, rsi                ; end
    ; reset estado
    mov qword [node_count], 0
    mov qword [stack_top], 0
    mov qword [theme_given], 0
    mov qword [theme_bg], 0x0f1117
    mov qword [theme_text], 0xf5f5f5
    mov qword [theme_accent], 0xf97316
.loop:
    cmp r12, r13
    jge .done
    ; line [r12, r14)
    mov r14, r12
.scan:
    cmp r14, r13
    jge .have_line
    cmp byte [in_buf + r14], 10
    je .have_line
    inc r14
    jmp .scan
.have_line:
    ; stripped
    mov r15, r12
.indent:
    cmp r15, r14
    jge .stripped
    mov al, [in_buf + r15]
    cmp al, ' '
    je .in_inc
    cmp al, 9
    jne .stripped
.in_inc:
    inc r15
    jmp .indent
.stripped:
    cmp r15, r14
    jge .next_line
    mov al, [in_buf + r15]
    cmp al, ';'
    je .next_line
    cmp al, '"'
    je .text_line
    cmp al, '@'
    je .at_line
    ; keyword directive without '@' (state/type)? consumes its lines
    mov rdi, r12
    mov rsi, r13
    call parse_directive
    cmp rax, -1
    je .err_line
    mov r12, rax
    jmp .loop
; --- text line: "..." -> text of the open node ---
.text_line:
    lea rbx, [r15 + 1]
.tx_scan:
    cmp rbx, r14
    jge .err_text
    cmp byte [in_buf + rbx], '"'
    je .tx_found
    inc rbx
    jmp .tx_scan
.tx_found:
    cmp qword [stack_top], 0
    je .err_text
    mov rax, [stack_top]
    dec rax
    shl rax, 3
    lea rcx, [istack + rax]
    mov edx, [rcx + 4]          ; open node idx
    imul rdx, rdx, NODE_SIZE
    lea rcx, [nodes + rdx]
    movzx eax, byte [rcx + N_TAG]
    cmp eax, 1
    je .tx_ok
    cmp eax, 2
    je .tx_ok
    ; view (tag 0) with a bare string line under it: create an implicit
    ; label child, exactly like inline text after ':' (.inl_found) -
    ; "string on its own line = text of the open node" applies to views
    ; too, not just label/button
    mov rax, [stack_top]
    dec rax
    shl rax, 3
    lea rcx, [istack + rax]
    mov r9d, [rcx + 4]          ; open node idx (parent)
    mov eax, [node_count]
    cmp eax, MAX_NODES
    jge .err_nodes
    mov r10d, eax               ; new child idx
    imul rdx, rax, NODE_SIZE
    lea rdi, [nodes + rdx]
    mov ecx, NODE_SIZE
    xor eax, eax
    rep stosb
    mov eax, r10d
    imul rdx, rax, NODE_SIZE
    lea rdi, [nodes + rdx]
    mov byte [rdi + N_TAG], 1
    mov byte [rdi + N_TAG_ID], TAG_SPAN
    mov dword [rdi + N_FS], 13
    mov dword [rdi + N_PARENT], r9d
    mov dword [rdi + N_FIRST], -1
    mov dword [rdi + N_LAST], -1
    mov dword [rdi + N_NEXT], -1
    mov dword [rdi + N_BG], -1
    mov dword [rdi + N_COLOR], -1
    ; text = line [r15+1, rbx) (r15 = line start, rbx = closing quote)
    lea eax, [r15 + 1]
    mov [rdi + N_TEXT_PTR], eax
    mov eax, ebx
    sub eax, r15d
    dec eax
    mov [rdi + N_TEXT_LEN], eax
    ; declarative state interpolation ({x} / {x.field})?
    ; (r15d = child idx survives the call; the line start goes to the
    ; stack since check_interp clobbers caller-saved regs)
    push r15                    ; stack: line start
    mov r15d, r10d              ; child node idx (callee-saved)
    push rdi                    ; stack: line start, child node ptr
    mov edx, [rdi + N_TEXT_LEN] ; u32 field!
    mov rdi, r15
    mov rax, [rsp + 8]          ; saved line start
    lea rsi, [rax + 1]          ; text ptr (in_buf offset)
    call check_interp
    pop rdi
    add rsp, 8                  ; drop the saved line start
    ; parent first/last point at the new child
    imul r8, r9, NODE_SIZE
    lea r8, [nodes + r8]
    cmp dword [r8 + N_FIRST], -1
    jne .tx_v_has_first
    mov [r8 + N_FIRST], r15d
    jmp .tx_v_last
.tx_v_has_first:
    mov [r8 + N_LAST], r15d
.tx_v_last:
    mov [r8 + N_LAST], r15d
    inc qword [node_count]
    jmp .next_line
.tx_ok:
    cmp dword [rcx + N_TEXT_PTR], 0
    jne .err_text
    lea eax, [r15 + 1]
    mov [rcx + N_TEXT_PTR], eax
    mov eax, ebx
    sub eax, r15d
    dec eax
    mov [rcx + N_TEXT_LEN], eax
    ; declarative state interpolation ({x} / {x.field})?
    push rcx
    push rdx
    mov rdi, rdx
    shr rdi, 8                  ; node idx (NODE_SIZE = 256)
    lea rsi, [r15 + 1]          ; text ptr (in_buf offset)
    mov edx, [rcx + N_TEXT_LEN] ; u32 field!
    call check_interp
    pop rdx
    pop rcx
    jmp .next_line
; --- @ line ---
.at_line:
    lea rbx, [r15 + 1]          ; token start (rbx is callee-saved)
    mov r9, rbx                 ; token end (r9 is not clobbered by strncmp)
.tk_scan:
    cmp r9, r14
    jge .tk_done
    mov al, [in_buf + r9]
    cmp al, ' '
    je .tk_done
    cmp al, 9
    je .tk_done
    cmp al, ':'                ; inline text separator (@p: "...")
    je .tk_done
    inc r9
    jmp .tk_scan
.tk_done:
    mov rdx, r9
    sub rdx, rbx                ; token len
    test rdx, rdx
    jz .err_line
    ; @end
    cmp rdx, 3
    jne .not_end
    lea rdi, [in_buf + rbx]
    lea rsi, [s_end]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_end
    cmp qword [stack_top], 0
    je .next_line
    dec qword [stack_top]
    jmp .next_line
.not_end:
    ; @theme (NOTE: strncmp clobbers rdx - recompute the token len)
    mov rdx, r9
    sub rdx, rbx
    cmp rdx, 5
    jne .not_theme
    lea rdi, [in_buf + rbx]
    lea rsi, [s_theme]
    mov rdx, 5
    call strncmp
    test rax, rax
    jnz .not_theme
    mov rdi, r9
    mov rsi, r14
    call parse_theme
    jmp .next_line
.not_theme:
    ; tag
    lea rdi, [in_buf + rbx]
    mov rsi, r9
    sub rsi, rbx                ; token len (recomputed, don't trust rdx)
    call tag_lookup
    cmp rax, -1
    je .err_tag
    mov r8d, eax                ; real tag id (1..N)
    mov ebx, [node_count]
    cmp ebx, MAX_NODES
    jge .err_nodes
    ; cria no: zero struct
    imul rcx, rbx, NODE_SIZE
    lea rdi, [nodes + rcx]
    mov ecx, NODE_SIZE
    xor eax, eax
    rep stosb
    imul rcx, rbx, NODE_SIZE
    lea rdi, [nodes + rcx]
    mov [rdi + N_TAG_ID], r8b   ; real HTML tag id
    movzx eax, byte [tag_kind + r8]
    mov [rdi + N_TAG], al       ; kind: 0=view 1=label 2=button
    mov dword [rdi + N_FS], 13
    mov dword [rdi + N_PARENT], -1
    mov dword [rdi + N_FIRST], -1
    mov dword [rdi + N_LAST], -1
    mov dword [rdi + N_NEXT], -1
    mov dword [rdi + N_BG], -1       ; -1 = sem bg (0 = preto, valido!)
    mov dword [rdi + N_COLOR], -1    ; -1 = sem cor
    inc qword [node_count]
    ; dedent por indentacao
    mov eax, r15d
    sub eax, r12d               ; indent
.dedent:
    cmp qword [stack_top], 0
    je .parent
    mov rdx, [stack_top]
    dec rdx
    shl rdx, 3
    lea rcx, [istack + rdx]
    cmp [rcx], eax              ; top.indent >= indent?
    jl .parent
    dec qword [stack_top]
    jmp .dedent
.parent:
    mov edx, -1
    cmp qword [stack_top], 0
    je .have_parent
    mov rax, [stack_top]
    dec rax
    shl rax, 3
    lea rcx, [istack + rax]
    mov edx, [rcx + 4]
.have_parent:
    imul rax, rbx, NODE_SIZE
    lea rcx, [nodes + rax]
    mov [rcx + N_PARENT], edx
    cmp edx, -1
    je .push
    imul rdx, rdx, NODE_SIZE
    lea rdx, [nodes + rdx]      ; pbase
    cmp dword [rdx + N_FIRST], -1
    jne .has_first
    mov [rdx + N_FIRST], ebx
    jmp .set_last
.has_first:
    mov eax, [rdx + N_LAST]
    imul rax, rax, NODE_SIZE
    lea rax, [nodes + rax]
    mov [rax + N_NEXT], ebx
.set_last:
    mov [rdx + N_LAST], ebx
.push:
    mov rdx, [stack_top]
    cmp rdx, MAX_STACK
    jge .err_depth
    shl rdx, 3
    lea rcx, [istack + rdx]
    mov eax, r15d
    sub eax, r12d
    mov [rcx], eax
    mov [rcx + 4], ebx
    inc qword [stack_top]
    ; classes: tokens de r9 (pos-token) ate r14, mas para no ':' (inline text)
    imul rcx, rbx, NODE_SIZE
    lea rdi, [nodes + rcx]
    mov rsi, r9
    mov rdx, r14
    ; find a ':' in [r9, r14) - the inline text separator, UNLESS it is
    ; a variant prefix separator (hover:/sm:/md:/... - then keep looking)
    mov r8, r9
.cls_scan:
    cmp r8, r14
    jge .cls_done
    cmp byte [in_buf + r8], ':'
    je .cls_colon
    inc r8
    jmp .cls_scan
.cls_colon:
    ; token before the ':' = [last space, r8). If it is a variant
    ; prefix, this ':' belongs to the class (hover:bg-x), skip it.
    ; LOCAL byte check only - no calls: variant_bp clobbers caller-
    ; saved regs that are live here (r8 cursor, r9 classes start,
    ; rbx node idx, r14 line end). rdi/rsi are recomputed at .cls_done.
    mov rax, r8
.cls_ws_back:
    cmp rax, r9
    jbe .cls_tok_done
    mov cl, [in_buf + rax - 1]
    cmp cl, ' '
    je .cls_tok_done
    cmp cl, 9
    je .cls_tok_done
    dec rax
    jmp .cls_ws_back
.cls_tok_done:
    ; token = [rax, r8); len = rcx = r8 - rax
    mov rcx, r8
    sub rcx, rax
    cmp rcx, 5
    jne .t_len3
    cmp byte [in_buf + rax], 'h'      ; hover:
    jne .real_colon
    cmp byte [in_buf + rax + 1], 'o'
    jne .real_colon
    cmp byte [in_buf + rax + 2], 'v'
    jne .real_colon
    cmp byte [in_buf + rax + 3], 'e'
    jne .real_colon
    cmp byte [in_buf + rax + 4], 'r'
    jne .real_colon
    jmp .cls_variant
.t_len3:
    cmp rcx, 3
    jne .t_len2
    cmp byte [in_buf + rax], '2'      ; 2xl:
    jne .real_colon
    cmp byte [in_buf + rax + 1], 'x'
    jne .real_colon
    cmp byte [in_buf + rax + 2], 'l'
    jne .real_colon
    jmp .cls_variant
.t_len2:
    cmp rcx, 2
    jne .real_colon
    movzx edx, byte [in_buf + rax]
    movzx ecx, byte [in_buf + rax + 1]
    cmp edx, 'x'                      ; xs: / xl:
    jne .t_sm
    cmp ecx, 's'
    je .cls_variant
    cmp ecx, 'l'
    je .cls_variant
    jmp .real_colon
.t_sm:
    cmp edx, 's'                      ; sm:
    jne .t_md
    cmp ecx, 'm'
    je .cls_variant
    jmp .real_colon
.t_md:
    cmp edx, 'm'                      ; md:
    jne .t_lg
    cmp ecx, 'd'
    je .cls_variant
    jmp .real_colon
.t_lg:
    cmp edx, 'l'                      ; lg:
    jne .real_colon
    cmp ecx, 'g'
    je .cls_variant
    jmp .real_colon
.real_colon:
    mov rdx, r8                 ; real inline-text colon
    jmp .cls_done
.cls_variant:
    inc r8
    jmp .cls_scan
.cls_done:
    ; node base (rdi) + classes start (rsi) were clobbered by the
    ; byte checks above - recompute both for parse_classes
    imul rcx, rbx, NODE_SIZE
    lea rdi, [nodes + rcx]
    mov rsi, r9
    push r14                    ; parse_classes clobbers r14 (line end)
    push rdx                    ; ... and rdx (the colon offset)
    call parse_classes
    pop rdx
    pop r14
    ; inline text after ':'?  ": \"content\"" -> the node's text
    cmp rdx, r14
    jge .no_inline
    lea r8, [rdx + 1]           ; skip ':'
.inl_skip:
    cmp r8, r14
    jge .no_inline
    mov al, [in_buf + r8]
    cmp al, ' '
    je .inl_si
    cmp al, 9
    jne .inl_q
.inl_si:
    inc r8
    jmp .inl_skip
.inl_q:
    cmp byte [in_buf + r8], '"'
    jne .no_inline
    lea r9, [r8 + 1]            ; text start
    mov r10, r9
.inl_scan:
    cmp r10, r14
    jge .no_inline
    cmp byte [in_buf + r10], '"'
    je .inl_found
    inc r10
    jmp .inl_scan
.inl_found:
    ; the node (rbx) gets the text if it is a label/button; a view gets
    ; an implicit label child
    imul rcx, rbx, NODE_SIZE
    lea rcx, [nodes + rcx]
    movzx eax, byte [rcx + N_TAG]
    cmp eax, 1
    je .inl_ok
    cmp eax, 2
    je .inl_ok
    ; view: create a label child (tag 1) under it
    mov eax, [node_count]
    cmp eax, MAX_NODES
    jge .err_nodes
    mov r15d, eax               ; new child idx
    imul rdx, rax, NODE_SIZE
    lea rdi, [nodes + rdx]
    mov ecx, NODE_SIZE
    xor eax, eax
    rep stosb
    mov eax, r15d               ; recompute (rep stosb clobbered rax/rcx/rdi)
    imul rdx, rax, NODE_SIZE
    lea rdi, [nodes + rdx]
    mov byte [rdi + N_TAG], 1
    mov byte [rdi + N_TAG_ID], TAG_SPAN
    mov dword [rdi + N_FS], 13
    mov dword [rdi + N_PARENT], ebx
    mov dword [rdi + N_FIRST], -1
    mov dword [rdi + N_LAST], -1
    mov dword [rdi + N_NEXT], -1
    mov dword [rdi + N_BG], -1
    mov dword [rdi + N_COLOR], -1
    mov [rdi + N_TEXT_PTR], r9d
    mov eax, r10d
    sub eax, r9d               ; r9 is past the quote already - no -1
    mov [rdi + N_TEXT_LEN], eax
    ; declarative state interpolation (view inline text)
    push rdi
    mov edx, [rdi + N_TEXT_LEN]  ; u32 field! (node ptr still in rdi)
    mov rdi, r15                 ; child node idx
    mov rsi, r9                  ; text ptr
    call check_interp
    pop rdi
    ; parent first/last point at the new child
    imul r8, rbx, NODE_SIZE
    lea r8, [nodes + r8]
    cmp dword [r8 + N_FIRST], -1
    jne .v_has_first
    mov [r8 + N_FIRST], r15d
    jmp .v_last
.v_has_first:
    mov [r8 + N_LAST], r15d
.v_last:
    mov [r8 + N_LAST], r15d
    inc qword [node_count]
    jmp .no_inline
.inl_ok:
    mov [rcx + N_TEXT_PTR], r9d
    mov eax, r10d
    sub eax, r9d               ; r9 is past the quote already - no -1
    mov [rcx + N_TEXT_LEN], eax
    ; declarative state interpolation
    push rcx
    mov rdi, rbx               ; node idx of the tag
    mov rsi, r9
    mov edx, [rcx + N_TEXT_LEN] ; u32 field!
    call check_interp
    pop rcx
.no_inline:
    jmp .next_line
.next_line:
    mov r12, r14
    cmp r12, r13
    jge .done
    cmp byte [in_buf + r12], 10
    jne .done
    inc r12
    jmp .loop
; --- erros ---
.err_line:
    lea rdi, [msg_block]
    mov rsi, msg_block_len
    call die
.err_text:
    lea rdi, [msg_text]
    mov rsi, msg_text_len
    call die
.err_nodes:
    lea rdi, [msg_nodes]
    mov rsi, msg_nodes_len
    call die
.err_depth:
    lea rdi, [msg_depth]
    mov rsi, msg_depth_len
    call die
.err_tag:
    lea rdi, [in_buf + rbx]
    mov rsi, r9
    sub rsi, rbx
    jmp err_tag
.done:
    ; layout dos roots
    call layout_all
    ; theme: without @theme the bg of the 1st root becomes the page background
    cmp qword [theme_given], 0
    jne .theme_done
    xor r12, r12
.t_loop:
    cmp r12, [node_count]
    jge .theme_done
    imul rax, r12, NODE_SIZE
    lea rcx, [nodes + rax]
    cmp dword [rcx + N_PARENT], -1
    jne .t_next
    cmp dword [rcx + N_BG], -1
    je .t_next
    mov eax, [rcx + N_BG]
    mov [theme_bg], eax
    jmp .theme_done
.t_next:
    inc r12
    jmp .t_loop
.theme_done:
    call build_records
    call serialize
    ; style records must exist before emit_shell (the SSR HTML reads
    ; role/padding/etc. from style_buf) AND before emit_wat_componente
    call build_style_records
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; err_tag(rdi = token ptr, rsi = token len) - message + exit 1
err_tag:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov rax, SYS_write
    mov rdi, 2
    lea rsi, [msg_tag]
    mov rdx, msg_tag_len
    syscall
    mov rax, SYS_write
    mov rdi, 2
    mov rsi, r12
    mov rdx, r13
    syscall
    mov rax, SYS_write
    mov rdi, 2
    lea rsi, [msg_nl]
    mov rdx, 1
    syscall
    mov rax, SYS_exit
    mov rdi, 1
    syscall

; ----------------------------------------------------------------------
; parse_theme(rdi = pos, rsi = end) - "@theme bg #hex text #hex accent #hex"
; ----------------------------------------------------------------------
parse_theme:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
.loop:
    ; skip espacos
    mov r14, r12
.skip:
    cmp r14, r13
    jge .done
    mov al, [in_buf + r14]
    cmp al, ' '
    je .sk_inc
    cmp al, 9
    jne .have_key
.sk_inc:
    inc r14
    jmp .skip
.have_key:
    mov rbx, r14                ; key start
.k_scan:
    cmp r14, r13
    jge .done
    mov al, [in_buf + r14]
    cmp al, ' '
    je .key_done
    cmp al, 9
    je .key_done
    inc r14
    jmp .k_scan
.key_done:
    ; skip espacos -> value
    mov r15, r14
.skip2:
    cmp r15, r13
    jge .done
    mov al, [in_buf + r15]
    cmp al, ' '
    je .sk2_inc
    cmp al, 9
    jne .have_val
.sk2_inc:
    inc r15
    jmp .skip2
.have_val:
    mov rcx, r15                ; value start
.v_scan:
    cmp rcx, r13
    jge .val_done
    mov al, [in_buf + rcx]
    cmp al, ' '
    je .val_done
    cmp al, 9
    je .val_done
    inc rcx
    jmp .v_scan
.val_done:
    mov r12, rcx                ; value end = nova pos do loop (callee-saved,
                                ; survives the strncmp/hex_to_int calls below)
    mov rdx, r14
    sub rdx, rbx                ; key len
    cmp rdx, 2
    jne .k_text
    lea rdi, [in_buf + rbx]
    lea rsi, [s_key_bg]
    mov rdx, 2
    call strncmp
    test rax, rax
    jnz .k_text
    mov esi, r12d
    sub esi, r15d
    dec esi
    lea rdi, [in_buf + r15 + 1]
    call hex_to_int
    mov [theme_bg], rax
    jmp .cont
.k_text:
    mov rdx, r14
    sub rdx, rbx
    cmp rdx, 4
    jne .k_accent
    lea rdi, [in_buf + rbx]
    lea rsi, [s_key_text]
    mov rdx, 4
    call strncmp
    test rax, rax
    jnz .k_accent
    mov esi, r12d
    sub esi, r15d
    dec esi
    lea rdi, [in_buf + r15 + 1]
    call hex_to_int
    mov [theme_text], rax
    jmp .cont
.k_accent:
    mov esi, r12d
    sub esi, r15d
    dec esi
    lea rdi, [in_buf + r15 + 1]
    call hex_to_int
    mov [theme_accent], rax
.cont:
    mov qword [theme_given], 1
    jmp .loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; parse_classes(rdi = base, rsi = pos, rdx = end) - aplica tokens de classe
; ----------------------------------------------------------------------
parse_classes:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
.loop:
    cmp r13, r14
    jge .done
    mov al, [in_buf + r13]
    cmp al, ' '
    je .sk_inc
    cmp al, 9
    jne .have_tok
.sk_inc:
    inc r13
    jmp .loop
.have_tok:
    mov rbx, r13
    ; attribute (name="value")? scan for '=' before any space
    mov r9, rbx
.attr_scan:
    cmp r9, r14
    jge .plain_tok
    mov al, [in_buf + r9]
    cmp al, '='
    je .is_attr
    cmp al, ' '
    je .plain_tok
    cmp al, 9
    je .plain_tok
    inc r9
    jmp .attr_scan
.plain_tok:
    ; normal class token: [rbx, r9)
    mov rdi, r12
    lea rsi, [in_buf + rbx]
    mov rdx, r9
    sub rdx, rbx
    call class_apply
    mov r13, r9
    jmp .loop
.is_attr:
    ; name = [rbx, r9); find the opening quote
    lea r10, [r9 + 1]
.attr_q:
    cmp r10, r14
    jge .plain_tok
    mov al, [in_buf + r10]
    cmp al, '"'
    je .attr_val
    inc r10
    jmp .attr_q
.attr_val:
    inc r10                     ; value start
    mov r11, r10
.attr_vscan:
    cmp r11, r14
    jge .plain_tok
    cmp byte [in_buf + r11], '"'
    je .attr_vend
    inc r11
    jmp .attr_vscan
.attr_vend:
    ; value = [r10, r11)
    mov rdi, rbx                ; name ptr
    mov rsi, r9
    sub rsi, rbx                ; name len
    mov rdx, r10                ; value ptr
    mov rcx, r11
    sub rcx, r10                ; value len
    push r14
    push r11
    call parse_attr
    pop r11
    pop r14
    ; continue after the closing quote
    mov r13, r11
    inc r13
    jmp .loop
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; tw_lookup(rdi = ptr, rsi = len, rdx = table, rcx = table_end) -> value or -1
; Generic table lookup: entries are (dq name_ptr, dq value).
; ----------------------------------------------------------------------
tw_lookup:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi              ; token ptr
    mov r13, rsi              ; token len
    mov r14, rdx              ; table
    mov r15, rcx              ; table end
.loop:
    cmp r14, r15
    jge .none
    mov rdi, [r14]
    call strlen
    cmp rax, r13
    jne .next
    mov rdi, [r14]
    mov rsi, r12
    mov rdx, r13
    call strncmp
    test rax, rax
    jz .found
.next:
    add r14, 16
    jmp .loop
.found:
    mov rax, [r14 + 8]
    jmp .done
.none:
    mov rax, -1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; class_apply(rdi = base, rsi = token, rdx = token len)
; ----------------------------------------------------------------------
; Variant wrapper: if the token starts with a responsive/hover prefix
; (hover: xs: sm: md: lg: xl: 2xl:), the class is applied to a scratch
; copy of the node and the CHANGED style fields are recorded in
; variant_tab (node, breakpoint, field, value) - the base node itself is
; untouched, so the SSR/wasm render the base layout and the emitted
; <style data-asx-variants> block overrides it at the breakpoint/hover.
class_apply:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; node base
    mov r13, rsi                ; token ptr
    mov r14, rdx                ; token len
    ; scan for ':' (variant separator)
    xor rbx, rbx
.scan:
    cmp rbx, r14
    jge .no_var
    cmp byte [r13 + rbx], ':'
    je .have_var
    inc rbx
    jmp .scan
.have_var:
    ; prefix len = rbx, class token = [r13+rbx+1, r13+r14)
    ; match the prefix -> breakpoint id
    mov rdi, r13
    mov rsi, rbx
    call variant_bp            ; rax = bp (0=hover 1=xs 2=sm 3=md 4=lg 5=xl 6=2xl) or -1
    cmp rax, -1
    je .no_var
    push rax                    ; bp (callee-saved r12-r15 are busy)
    ; copy the node to node_tmp (scratch)
    mov rdi, node_tmp
    mov rsi, r12
    mov rcx, NODE_SIZE
    rep movsb
    ; apply the class to node_tmp (base = node_tmp, token = rest)
    lea rdi, [node_tmp]
    lea rsi, [r13 + rbx + 1]
    mov rdx, r14
    sub rdx, rbx
    dec rdx
    call class_apply_core
    ; diff the style fields between the real node and node_tmp; every
    ; change becomes a variant entry. NOTE: r9 is caller-saved and the
    ; parse_classes loop relies on it right after class_apply returns -
    ; keep the bp in r15 instead (r15 is callee-saved and unused here).
    pop r15                     ; bp
    mov r8, r12
    sub r8, nodes
    shr r8, 8                   ; node idx (NODE_SIZE = 256)
    ; field table: (offset u32, size u32) - compare + record
    lea r10, [var_fields]
.var_loop:
    cmp r10, var_fields_end
    jge .done
    mov eax, [r10]              ; field offset
    mov ecx, [r10 + 4]          ; size (4 or 1)
    ; read both values
    mov r11d, eax
    mov edx, 0
    cmp ecx, 1
    jne .rd4
    movzx edx, byte [node_tmp + r11]
    movzx ebx, byte [r12 + r11]
    jmp .have_vals
.rd4:
    mov edx, [node_tmp + r11]
    mov ebx, [r12 + r11]
.have_vals:
    cmp edx, ebx
    je .var_next
    ; changed: record (node, bp, field, value)
    cmp qword [variant_count], MAX_VARIANTS
    jge .var_next
    mov rdi, [variant_count]
    imul rdi, rdi, VAR_ENTRY
    lea rdi, [variant_tab + rdi]
    mov [rdi + V_NODE], r8d
    mov [rdi + V_BP], r15d
    mov [rdi + V_FIELD], eax
    mov [rdi + V_VALUE], edx
    inc qword [variant_count]
.var_next:
    add r10, 8
    jmp .var_loop
.no_var:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call class_apply_core
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; variant_bp(rdi = prefix ptr, rsi = prefix len) -> bp id or -1
variant_bp:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    lea r14, [var_prefixes]
.bp_loop:
    cmp r14, var_prefixes_end
    jge .none
    mov rdi, [r14]              ; literal ptr
    mov rsi, [r14 + 8]          ; literal len
    cmp rsi, r13
    jne .bp_next
    mov rdi, [r14]
    mov rsi, r12
    mov rdx, r13
    call strncmp
    test rax, rax
    jz .found
.bp_next:
    add r14, 24
    jmp .bp_loop
.found:
    mov rax, [r14 + 16]         ; bp id
    jmp .done
.none:
    mov rax, -1
.done:
    pop r14
    pop r13
    pop r12
    ret

; ----------------------------------------------------------------------
; class_apply_core(rdi = base, rsi = token, rdx = token len) - the
; actual class application (no variant handling).
; ----------------------------------------------------------------------
class_apply_core:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    ; ---- exact-name tables (flags / rounded / font-weight / shadow) ----
    ; tw_lookup(rdi = token ptr, rsi = token LEN, rdx = table, rcx = end).
    ; BOTH must be re-set before every call: on entry rdi = node base and
    ; rsi = token ptr (caller-saved, clobbered by strncmp inside the
    ; lookup). Bug: with rsi = token ptr, cmp rax, r13 compared strlen
    ; against an ADDRESS -> every exact-name class returned -1 and
    ; flex/rounded/font/shadow silently never applied.
    mov rdi, r13
    mov rsi, r14
    lea rdx, [tw_flags]
    lea rcx, [tw_flags_end]
    call tw_lookup
    cmp rax, -1
    je .not_flags
    or [r12 + N_FLAGS], eax
    jmp .done
.not_flags:
    mov rdi, r13
    mov rsi, r14
    lea rdx, [tw_round]
    lea rcx, [tw_round_end]
    call tw_lookup
    cmp rax, -1
    je .not_round
    mov [r12 + N_RADIUS], eax
    jmp .done
.not_round:
    mov rdi, r13
    mov rsi, r14
    lea rdx, [tw_fontw]
    lea rcx, [tw_fontw_end]
    call tw_lookup
    cmp rax, -1
    je .not_fontw
    mov [r12 + N_WEIGHT], eax
    cmp eax, 600
    jl .done
    or dword [r12 + N_FLAGS], F_BOLD
    jmp .done
.not_fontw:
    mov rdi, r13
    mov rsi, r14
    lea rdx, [tw_shadow]
    lea rcx, [tw_shadow_end]
    call tw_lookup
    cmp rax, -1
    je .not_shadow
    mov [r12 + N_SHADOW], eax
    jmp .done
.not_shadow:
    ; text-center / text-right / text-justify -> N_ALIGN (the label CSS
    ; reads the align byte; MUST run before the text-<color>/text-<size>
    ; prefix below, which would otherwise swallow the whole token)
    ; strncmp(rdi = token, rsi = literal, rdx = len)
    mov rdi, r13
    lea rsi, [s_text_center]
    mov rdx, 11
    call strncmp
    test rax, rax
    jnz .not_tc
    mov byte [r12 + N_ALIGN], 1
    jmp .done
.not_tc:
    mov rdi, r13
    lea rsi, [s_text_right]
    mov rdx, 10
    call strncmp
    test rax, rax
    jnz .not_tr
    mov byte [r12 + N_ALIGN], 2
    jmp .done
.not_tr:
    mov rdi, r13
    lea rsi, [s_text_justify]
    mov rdx, 12
    call strncmp
    test rax, rax
    jnz .not_tj
    mov byte [r12 + N_ALIGN], 3
    jmp .done
.not_tj:
    ; grid-cols-<n> (requires the grid flag to take effect)
    cmp r14d, 10
    jb .not_gc
    lea rdi, [r13]
    lea rsi, [s_grid_cols]
    mov rdx, 10
    call strncmp
    test rax, rax
    jnz .not_gc
    mov rdi, r13
    add rdi, 10
    mov rsi, r14
    sub rsi, 10
    lea rdx, [tw_gridcols]
    lea rcx, [tw_gridcols_end]
    call tw_lookup
    cmp rax, -1
    je .not_gc
    or dword [r12 + N_FLAGS], F_GRID
    mov [r12 + N_GRID_COLS], al
    jmp .done
.not_gc:
    ; ---- transitions (2026-08-20) ----
    ; transition-behavior-<suffix> MUST run before transition-<suffix>
    ; ("transition-behavior-normal" starts with "transition-")
    cmp r14d, 20
    jb .not_tbehav
    lea rdi, [r13]
    lea rsi, [s_tbehav_prefix]
    mov rdx, 20
    call strncmp
    test rax, rax
    jnz .not_tbehav
    lea rdi, [r13 + 20]
    mov rsi, r14
    sub rsi, 20
    lea rdx, [tw_tbehav]
    lea rcx, [tw_tbehav_end]
    call tw_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_TBEHAV], eax
    jmp .done
.not_tbehav:
    ; transition-<suffix>: none/all/colors/opacity/shadow/transform
    cmp r14d, 11
    jb .not_transp
    lea rdi, [r13]
    lea rsi, [s_transition_prefix]
    mov rdx, 11
    call strncmp
    test rax, rax
    jnz .not_transp
    lea rdi, [r13 + 11]
    mov rsi, r14
    sub rsi, 11
    lea rdx, [tw_trans]
    lea rcx, [tw_trans_end]
    call tw_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_TRANS], eax
    jmp .done
.not_transp:
    ; transition (bare - Tailwind default property set)
    cmp r14d, 10
    jne .not_trans
    lea rdi, [r13]
    lea rsi, [s_transition]
    mov rdx, 10
    call strncmp
    test rax, rax
    jnz .not_trans
    mov dword [r12 + N_TRANS], 1
    jmp .done
.not_trans:
    ; duration-<n> (transition-duration ms)
    cmp r14d, 9
    jb .not_dur
    lea rdi, [r13]
    lea rsi, [s_duration]
    mov rdx, 9
    call strncmp
    test rax, rax
    jnz .not_dur
    lea rdi, [r13 + 9]
    mov rsi, r14
    sub rsi, 9
    call atoi_n
    mov [r12 + N_DUR], eax
    jmp .done
.not_dur:
    ; ease-<suffix>: linear/in/out/in-out
    cmp r14d, 5
    jb .not_ease
    lea rdi, [r13]
    lea rsi, [s_ease]
    mov rdx, 5
    call strncmp
    test rax, rax
    jnz .not_ease
    lea rdi, [r13 + 5]
    mov rsi, r14
    sub rsi, 5
    lea rdx, [tw_ease]
    lea rcx, [tw_ease_end]
    call tw_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_EASE], eax
    jmp .done
.not_ease:
    ; delay-<n> (transition-delay ms)
    cmp r14d, 6
    jb .not_delay
    lea rdi, [r13]
    lea rsi, [s_delay]
    mov rdx, 6
    call strncmp
    test rax, rax
    jnz .not_delay
    lea rdi, [r13 + 6]
    mov rsi, r14
    sub rsi, 6
    call atoi_n
    mov [r12 + N_DELAY], eax
    jmp .done
.not_delay:
    ; ---- typography + animation (2026-08-20) ----
    ; font-<family>: sans/serif/mono (prefix "font-"; the font-<weight>
    ; names were consumed by tw_fontw above, so only families/stretch
    ; reach here)
    cmp r14d, 5
    jb .not_fontp
    lea rdi, [r13]
    lea rsi, [s_font_prefix]
    mov rdx, 5
    call strncmp
    test rax, rax
    jnz .not_fontp
    lea rdi, [r13 + 5]
    mov rsi, r14
    sub rsi, 5
    lea rdx, [tw_family]
    lea rcx, [tw_family_end]
    call tw_lookup
    cmp rax, -1
    je .not_fontp
    mov [r12 + N_FAMILY], eax
    jmp .done
.not_fontp:
    ; font-stretch-<keyword>
    cmp r14d, 13
    jb .not_fstretch
    lea rdi, [r13]
    lea rsi, [s_font_stretch]
    mov rdx, 13
    call strncmp
    test rax, rax
    jnz .not_fstretch
    lea rdi, [r13 + 13]
    mov rsi, r14
    sub rsi, 13
    lea rdx, [tw_stretch]
    lea rcx, [tw_stretch_end]
    call tw_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_STRETCH], eax
    jmp .done
.not_fstretch:
    ; font-variant-numeric (exact names, no common prefix)
    mov rdi, r13
    mov rsi, r14
    lea rdx, [tw_varnum]
    lea rcx, [tw_varnum_end]
    call tw_lookup
    cmp rax, -1
    je .not_varnum
    mov [r12 + N_VARNUM], eax
    jmp .done
.not_varnum:
    ; tracking-<suffix>
    cmp r14d, 9
    jb .not_track
    lea rdi, [r13]
    lea rsi, [s_tracking]
    mov rdx, 9
    call strncmp
    test rax, rax
    jnz .not_track
    lea rdi, [r13 + 9]
    mov rsi, r14
    sub rsi, 9
    lea rdx, [tw_tracking]
    lea rcx, [tw_tracking_end]
    call tw_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_TRACK], eax
    jmp .done
.not_track:
    ; leading-<suffix>: named (tw_leading) or numeric 3..10
    cmp r14d, 8
    jb .not_lead
    lea rdi, [r13]
    lea rsi, [s_leading]
    mov rdx, 8
    call strncmp
    test rax, rax
    jnz .not_lead
    lea rdi, [r13 + 8]
    mov rsi, r14
    sub rsi, 8
    lea rdx, [tw_leading]
    lea rcx, [tw_leading_end]
    call tw_lookup
    cmp rax, -1
    je .lead_num
    mov [r12 + N_LEAD], eax
    jmp .done
.lead_num:
    lea rdi, [r13 + 8]
    mov rsi, r14
    sub rsi, 8
    call atoi_n
    cmp rax, 3
    jb .done
    cmp rax, 10
    ja .done
    add rax, 4               ; leading-3 -> 7 .. leading-10 -> 14
    mov [r12 + N_LEAD], eax
    jmp .done
.not_lead:
    ; line-clamp-<n> (1..6) / line-clamp-none
    cmp r14d, 11
    jb .not_clamp
    lea rdi, [r13]
    lea rsi, [s_line_clamp]
    mov rdx, 11
    call strncmp
    test rax, rax
    jnz .not_clamp
    lea rdi, [r13 + 11]
    mov rsi, r14
    sub rsi, 11
    call atoi_n
    cmp rax, 1
    jb .done
    cmp rax, 6
    ja .done
    mov [r12 + N_CLAMP], eax
    jmp .done
.not_clamp:
    ; list-style-position: list-inside / list-outside
    cmp r14d, 11
    jne .not_lin
    lea rdi, [r13]
    lea rsi, [s_list_inside]
    mov rdx, 11
    call strncmp
    test rax, rax
    jnz .not_lin
    mov dword [r12 + N_LISTPOS], 1
    jmp .done
.not_lin:
    cmp r14d, 12
    jne .not_lout
    lea rdi, [r13]
    lea rsi, [s_list_outside]
    mov rdx, 12
    call strncmp
    test rax, rax
    jnz .not_lout
    mov dword [r12 + N_LISTPOS], 2
    jmp .done
.not_lout:
    ; list-style-type: list-none / list-disc / list-decimal
    cmp r14d, 9
    jne .not_lt
    lea rdi, [r13]
    lea rsi, [s_list_none]
    mov rdx, 9
    call strncmp
    test rax, rax
    jnz .not_lt
    mov dword [r12 + N_LISTTYPE], 1
    jmp .done
.not_lt:
    cmp r14d, 9
    jne .not_ld
    lea rdi, [r13]
    lea rsi, [s_list_disc]
    mov rdx, 9
    call strncmp
    test rax, rax
    jnz .not_ld
    mov dword [r12 + N_LISTTYPE], 2
    jmp .done
.not_ld:
    cmp r14d, 12
    jne .not_ldec
    lea rdi, [r13]
    lea rsi, [s_list_decimal]
    mov rdx, 12
    call strncmp
    test rax, rax
    jnz .not_ldec
    mov dword [r12 + N_LISTTYPE], 3
    jmp .done
.not_ldec:
    ; text-align: text-start / text-end (before the text-<color> block)
    cmp r14d, 10
    jne .not_tstart
    lea rdi, [r13]
    lea rsi, [s_text_start]
    mov rdx, 10
    call strncmp
    test rax, rax
    jnz .not_tstart
    mov byte [r12 + N_ALIGN], 4
    jmp .done
.not_tstart:
    cmp r14d, 8
    jne .not_tend
    lea rdi, [r13]
    lea rsi, [s_text_end]
    mov rdx, 8
    call strncmp
    test rax, rax
    jnz .not_tend
    mov byte [r12 + N_ALIGN], 5
    jmp .done
.not_tend:
    ; text-overflow: truncate / text-ellipsis / text-clip
    cmp r14d, 8
    jne .not_trunc
    lea rdi, [r13]
    lea rsi, [s_truncate]
    mov rdx, 8
    call strncmp
    test rax, rax
    jnz .not_trunc
    mov dword [r12 + N_OVERFLOW], 3
    jmp .done
.not_trunc:
    cmp r14d, 13
    jne .not_tell
    lea rdi, [r13]
    lea rsi, [s_text_ellipsis]
    mov rdx, 13
    call strncmp
    test rax, rax
    jnz .not_tell
    mov dword [r12 + N_OVERFLOW], 1
    jmp .done
.not_tell:
    cmp r14d, 9
    jne .not_tclip
    lea rdi, [r13]
    lea rsi, [s_text_clip]
    mov rdx, 9
    call strncmp
    test rax, rax
    jnz .not_tclip
    mov dword [r12 + N_OVERFLOW], 2
    jmp .done
.not_tclip:
    ; text-wrap / text-nowrap / text-balance / text-pretty (exact)
    cmp r14d, 9
    jne .not_twrap
    lea rdi, [r13]
    lea rsi, [s_text_wrap]
    mov rdx, 9
    call strncmp
    test rax, rax
    jnz .not_twrap
    mov dword [r12 + N_TWRAP], 1
    jmp .done
.not_twrap:
    cmp r14d, 11
    jne .not_twn
    lea rdi, [r13]
    lea rsi, [s_text_nowrap]
    mov rdx, 11
    call strncmp
    test rax, rax
    jnz .not_twn
    mov dword [r12 + N_TWRAP], 2
    jmp .done
.not_twn:
    cmp r14d, 12
    jne .not_twb
    lea rdi, [r13]
    lea rsi, [s_text_balance]
    mov rdx, 12
    call strncmp
    test rax, rax
    jnz .not_twb
    mov dword [r12 + N_TWRAP], 3
    jmp .done
.not_twb:
    cmp r14d, 11
    jne .not_twp
    lea rdi, [r13]
    lea rsi, [s_text_pretty]
    mov rdx, 11
    call strncmp
    test rax, rax
    jnz .not_twp
    mov dword [r12 + N_TWRAP], 4
    jmp .done
.not_twp:
    ; decoration-<suffix>: color | style | auto/from-font | thickness px
    cmp r14d, 11
    jb .not_deco
    lea rdi, [r13]
    lea rsi, [s_decoration]
    mov rdx, 11
    call strncmp
    test rax, rax
    jnz .not_deco
    lea rdi, [r13 + 11]
    mov rsi, r14
    sub rsi, 11
    call palette_lookup
    cmp rax, -1
    je .deco_style
    mov [r12 + N_DCOLOR], eax
    jmp .done
.deco_style:
    lea rdi, [r13 + 11]
    mov rsi, r14
    sub rsi, 11
    lea rdx, [tw_decostyle]
    lea rcx, [tw_decostyle_end]
    call tw_lookup
    cmp rax, -1
    je .deco_thick
    mov [r12 + N_DSTYLE], eax
    jmp .done
.deco_thick:
    lea rdi, [r13 + 11]
    mov rsi, r14
    sub rsi, 11
    lea rdx, [tw_dthick]
    lea rcx, [tw_dthick_end]
    call tw_lookup
    cmp rax, -1
    je .deco_px
    mov [r12 + N_DTHICK], eax
    jmp .done
.deco_px:
    lea rdi, [r13 + 11]
    mov rsi, r14
    sub rsi, 11
    call atoi_n
    cmp rax, 9
    jae .done
    add rax, 2               ; decoration-<n> -> thickness px (n + 2)
    mov [r12 + N_DTHICK], eax
    jmp .done
.not_deco:
    ; underline-offset-<suffix>: auto | px
    cmp r14d, 17
    jb .not_uo
    lea rdi, [r13]
    lea rsi, [s_uo_prefix]
    mov rdx, 17
    call strncmp
    test rax, rax
    jnz .not_uo
    lea rdi, [r13 + 17]
    mov rsi, r14
    sub rsi, 17
    call atoi_n
    test rax, rax
    jnz .uo_px
    ; "auto" (atoi gave 0)
    mov dword [r12 + N_UO], 1
    jmp .done
.uo_px:
    mov [r12 + N_UO], eax
    jmp .done
.not_uo:
    ; text-transform/decoration/font-style flags
    cmp r14d, 10
    jne .not_cap
    lea rdi, [r13]
    lea rsi, [s_capitalize]
    mov rdx, 10
    call strncmp
    test rax, rax
    jnz .not_cap
    or dword [r12 + N_FLAGS], F_CAPITALIZE
    jmp .done
.not_cap:
    cmp r14d, 11
    jne .not_ncase
    lea rdi, [r13]
    lea rsi, [s_normal_case]
    mov rdx, 11
    call strncmp
    test rax, rax
    jnz .not_ncase
    or dword [r12 + N_FLAGS], F_NORMALCASE
    jmp .done
.not_ncase:
    cmp r14d, 10
    jne .not_nit
    lea rdi, [r13]
    lea rsi, [s_not_italic]
    mov rdx, 10
    call strncmp
    test rax, rax
    jnz .not_nit
    or dword [r12 + N_FLAGS], F_NOTITALIC
    jmp .done
.not_nit:
    cmp r14d, 8
    jne .not_ovl
    lea rdi, [r13]
    lea rsi, [s_overline]
    mov rdx, 8
    call strncmp
    test rax, rax
    jnz .not_ovl
    or dword [r12 + N_FLAGS], F_OVERLINE
    jmp .done
.not_ovl:
    ; (no-underline is consumed by tw_flags -> F_NOUNDERLINE)
.not_nund:
    ; font-smoothing: antialiased / subpixel-antialiased
    cmp r14d, 11
    jne .not_anti
    lea rdi, [r13]
    lea rsi, [s_antialiased]
    mov rdx, 11
    call strncmp
    test rax, rax
    jnz .not_anti
    mov dword [r12 + N_SMOOTH], 1
    jmp .done
.not_anti:
    cmp r14d, 21
    jne .not_subp
    lea rdi, [r13]
    lea rsi, [s_subpixel]
    mov rdx, 21
    call strncmp
    test rax, rax
    jnz .not_subp
    mov dword [r12 + N_SMOOTH], 2
    jmp .done
.not_subp:
    ; indent-<n> (spacing scale)
    cmp r14d, 7
    jb .not_indent
    lea rdi, [r13]
    lea rsi, [s_indent]
    mov rdx, 7
    call strncmp
    test rax, rax
    jnz .not_indent
    lea rdi, [r13 + 7]
    mov rsi, r14
    sub rsi, 7
    call scale_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_INDENT], eax
    jmp .done
.not_indent:
    ; tab-<n> (literal number)
    cmp r14d, 4
    jb .not_tabsz
    lea rdi, [r13]
    lea rsi, [s_tab]
    mov rdx, 4
    call strncmp
    test rax, rax
    jnz .not_tabsz
    lea rdi, [r13 + 4]
    mov rsi, r14
    sub rsi, 4
    call atoi_n
    test rax, rax
    jz .done
    mov [r12 + N_TABSIZE], eax
    jmp .done
.not_tabsz:
    ; align-<suffix>: vertical-align
    cmp r14d, 6
    jb .not_valign
    lea rdi, [r13]
    lea rsi, [s_align]
    mov rdx, 6
    call strncmp
    test rax, rax
    jnz .not_valign
    lea rdi, [r13 + 6]
    mov rsi, r14
    sub rsi, 6
    lea rdx, [tw_valign]
    lea rcx, [tw_valign_end]
    call tw_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_VALIGN], eax
    jmp .done
.not_valign:
    ; whitespace-<suffix>
    cmp r14d, 11
    jb .not_ws
    lea rdi, [r13]
    lea rsi, [s_whitespace]
    mov rdx, 11
    call strncmp
    test rax, rax
    jnz .not_ws
    lea rdi, [r13 + 11]
    mov rsi, r14
    sub rsi, 11
    lea rdx, [tw_ws]
    lea rcx, [tw_ws_end]
    call tw_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_WS], eax
    jmp .done
.not_ws:
    ; break-<suffix>: word-break
    cmp r14d, 6
    jb .not_wb
    lea rdi, [r13]
    lea rsi, [s_break]
    mov rdx, 6
    call strncmp
    test rax, rax
    jnz .not_wb
    lea rdi, [r13 + 6]
    mov rsi, r14
    sub rsi, 6
    lea rdx, [tw_wbreak]
    lea rcx, [tw_wbreak_end]
    call tw_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_WBREAK], eax
    jmp .done
.not_wb:
    ; wrap-<suffix>: overflow-wrap
    cmp r14d, 5
    jb .not_wrp
    lea rdi, [r13]
    lea rsi, [s_wrap]
    mov rdx, 5
    call strncmp
    test rax, rax
    jnz .not_wrp
    lea rdi, [r13 + 5]
    mov rsi, r14
    sub rsi, 5
    lea rdx, [tw_wrap]
    lea rcx, [tw_wrap_end]
    call tw_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_WBREAK], eax
    jmp .done
.not_wrp:
    ; hyphens-<suffix>
    cmp r14d, 8
    jb .not_hyp
    lea rdi, [r13]
    lea rsi, [s_hyphens]
    mov rdx, 8
    call strncmp
    test rax, rax
    jnz .not_hyp
    lea rdi, [r13 + 8]
    mov rsi, r14
    sub rsi, 8
    lea rdx, [tw_hyphens]
    lea rcx, [tw_hyphens_end]
    call tw_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_HYPHENS], eax
    jmp .done
.not_hyp:
    ; content-none
    cmp r14d, 12
    jne .not_cont
    lea rdi, [r13]
    lea rsi, [s_content_none]
    mov rdx, 12
    call strncmp
    test rax, rax
    jnz .not_cont
    mov dword [r12 + N_CONTENT], 1
    jmp .done
.not_cont:
    ; animate-<suffix>: spin/ping/pulse/bounce (none = default, no-op)
    cmp r14d, 8
    jb .not_anim
    lea rdi, [r13]
    lea rsi, [s_animate]
    mov rdx, 8
    call strncmp
    test rax, rax
    jnz .not_anim
    lea rdi, [r13 + 8]
    mov rsi, r14
    sub rsi, 8
    lea rdx, [tw_anim]
    lea rcx, [tw_anim_end]
    call tw_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_ANIM], eax
    jmp .done
.not_anim:
    ; ---- numeric prefixes ----
    ; gap-<n>
    cmp r14d, 4
    jb .not_gap
    lea rdi, [r13]
    lea rsi, [s_gap_prefix]
    mov rdx, 4
    call strncmp
    test rax, rax
    jnz .not_gap
    lea rdi, [r13 + 4]
    mov rsi, r14
    sub rsi, 4
    call scale_lookup
    mov [r12 + N_GAP], eax
    jmp .done
.not_gap:
    ; px-<n>
    cmp r14d, 3
    jb .not_px
    lea rdi, [r13]
    lea rsi, [s_px_prefix]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_px
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    mov [r12 + N_PX], eax
    jmp .done
.not_px:
    ; py-<n>
    cmp r14d, 3
    jb .not_py
    lea rdi, [r13]
    lea rsi, [s_py_prefix]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_py
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    mov [r12 + N_PY], eax
    jmp .done
.not_py:
    ; pt-<n>
    cmp r14d, 3
    jb .not_pt
    lea rdi, [r13]
    lea rsi, [s_pt_prefix]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_pt
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    mov [r12 + N_PT], eax
    jmp .done
.not_pt:
    ; pb-<n>
    cmp r14d, 3
    jb .not_pb
    lea rdi, [r13]
    lea rsi, [s_pb_prefix]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_pb
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    mov [r12 + N_PB], eax
    jmp .done
.not_pb:
    ; h-<n> (height; "h-screen" -> 720 via scale screen)
    cmp r14d, 2
    jb .not_h
    lea rdi, [r13]
    lea rsi, [s_h_prefix]
    mov rdx, 2
    call strncmp
    test rax, rax
    jnz .not_h
    lea rdi, [r13 + 2]
    mov rsi, r14
    sub rsi, 2
    call scale_lookup
    mov [r12 + N_H], eax
    jmp .done
.not_h:
    ; border-<n> or border-<color> (width via scale; color via palette)
    cmp r14d, 7
    jb .not_borderp
    lea rdi, [r13]
    lea rsi, [s_border_prefix]
    mov rdx, 7
    call strncmp
    test rax, rax
    jnz .not_borderp
    lea rdi, [r13 + 7]
    mov rsi, r14
    sub rsi, 7
    call palette_lookup
    cmp rax, -1
    je .border_scale
    mov [r12 + N_BORDER_COLOR], eax
    jmp .done
.border_scale:
    lea rdi, [r13 + 7]
    mov rsi, r14
    sub rsi, 7
    call scale_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_BORDER], eax
    jmp .done
.not_borderp:
    ; border (width 1)
    cmp r14d, 6
    jne .not_border
    lea rdi, [r13]
    lea rsi, [s_border]
    mov rdx, 6
    call strncmp
    test rax, rax
    jnz .not_border
    mov dword [r12 + N_BORDER], 1
    jmp .done
.not_border:
    ; opacity-<n>
    cmp r14d, 8
    jb .not_opacity
    lea rdi, [r13]
    lea rsi, [s_opacity_prefix]
    mov rdx, 8
    call strncmp
    test rax, rax
    jnz .not_opacity
    lea rdi, [r13 + 8]
    mov rsi, r14
    sub rsi, 8
    call atoi_n
    cmp rax, 100
    jg .done
    mov [r12 + N_OPACITY], eax
    jmp .done
.not_opacity:
    ; bg-<color>
    cmp r14d, 3
    jb .not_bg
    lea rdi, [r13]
    lea rsi, [s_bg]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_bg
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call palette_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_BG], eax
    jmp .done
.not_bg:
    ; text-<color> | text-<size>
    cmp r14d, 5
    jb .not_text
    lea rdi, [r13]
    lea rsi, [s_text]
    mov rdx, 5
    call strncmp
    test rax, rax
    jnz .not_text
    lea rdi, [r13 + 5]
    mov rsi, r14
    sub rsi, 5
    call palette_lookup
    cmp rax, -1
    jne .text_color
    lea rdi, [r13 + 5]
    mov rsi, r14
    sub rsi, 5
    call size_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_FS], eax
    jmp .done
.text_color:
    mov [r12 + N_COLOR], eax
    jmp .done
.not_text:
    ; mt-<n>
    cmp r14d, 3
    jb .not_mt
    lea rdi, [r13]
    lea rsi, [s_mt]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_mt
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    mov [r12 + N_MT], eax
    jmp .done
.not_mt:
    ; mb-<n>
    cmp r14d, 3
    jb .not_mb
    lea rdi, [r13]
    lea rsi, [s_mb]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_mb
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    mov [r12 + N_MB], eax
    jmp .done
.not_mb:
    ; my-<n> (margin-top + margin-bottom)
    cmp r14d, 3
    jb .not_my
    lea rdi, [r13]
    lea rsi, [s_my]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_my
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_MT], eax
    mov [r12 + N_MB], eax
    jmp .done
.not_my:
    ; mx-<n> (margin-left + margin-right)
    cmp r14d, 3
    jb .not_mx
    lea rdi, [r13]
    lea rsi, [s_mx]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_mx
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_ML], eax
    mov [r12 + N_MR], eax
    jmp .done
.not_mx:
    ; me-<n> (margin-inline-end; LTR = right)
    cmp r14d, 3
    jb .not_me
    lea rdi, [r13]
    lea rsi, [s_me]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_me
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_MR], eax
    jmp .done
.not_me:
    ; ms-<n> (margin-inline-start; LTR = left)
    cmp r14d, 3
    jb .not_ms
    lea rdi, [r13]
    lea rsi, [s_ms]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_ms
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_ML], eax
    jmp .done
.not_ms:
    ; ml-<n> (margin-left)
    cmp r14d, 3
    jb .not_ml
    lea rdi, [r13]
    lea rsi, [s_ml]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_ml
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_ML], eax
    jmp .done
.not_ml:
    ; mr-<n> (margin-right)
    cmp r14d, 3
    jb .not_mr
    lea rdi, [r13]
    lea rsi, [s_mr]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_mr
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_MR], eax
    jmp .done
.not_mr:
    ; p-<n>
    cmp r14d, 2
    jb .not_p
    lea rdi, [r13]
    lea rsi, [s_p]
    mov rdx, 2
    call strncmp
    test rax, rax
    jnz .not_p
    lea rdi, [r13 + 2]
    mov rsi, r14
    sub rsi, 2
    call scale_lookup
    mov [r12 + N_PAD], eax
    jmp .done
.not_p:
    ; pe-<n> (padding-inline-end; LTR = right)
    cmp r14d, 3
    jb .not_pe
    lea rdi, [r13]
    lea rsi, [s_pe]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_pe
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_PR], eax
    jmp .done
.not_pe:
    ; ps-<n> (padding-inline-start; LTR = left)
    cmp r14d, 3
    jb .not_ps
    lea rdi, [r13]
    lea rsi, [s_ps]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_ps
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_PL], eax
    jmp .done
.not_ps:
    ; pl-<n> (padding-left)
    cmp r14d, 3
    jb .not_pl
    lea rdi, [r13]
    lea rsi, [s_pl]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_pl
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_PL], eax
    jmp .done
.not_pl:
    ; pr-<n> (padding-right)
    cmp r14d, 3
    jb .not_pr
    lea rdi, [r13]
    lea rsi, [s_pr]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_pr
    lea rdi, [r13 + 3]
    mov rsi, r14
    sub rsi, 3
    call scale_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_PR], eax
    jmp .done
.not_pr:
    ; w-<n>
    cmp r14d, 2
    jb .not_w
    lea rdi, [r13]
    lea rsi, [s_w]
    mov rdx, 2
    call strncmp
    test rax, rax
    jnz .not_w
    lea rdi, [r13 + 2]
    mov rsi, r14
    sub rsi, 2
    call scale_lookup
    mov [r12 + N_W], eax
    jmp .done
.not_w:
    ; m-<n> (all four sides - mt/mb/ml/mr)
    cmp r14d, 2
    jb .done
    lea rdi, [r13]
    lea rsi, [s_m]
    mov rdx, 2
    call strncmp
    test rax, rax
    jnz .done
    lea rdi, [r13 + 2]
    mov rsi, r14
    sub rsi, 2
    call scale_lookup
    cmp rax, -1
    je .done
    mov [r12 + N_MT], eax
    mov [r12 + N_MB], eax
    mov [r12 + N_ML], eax
    mov [r12 + N_MR], eax
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; lookups: tag_lookup(ptr, len) -> id 0/1/2 or -1
;          palette_lookup(ptr, len) -> 0xRRGGBB or -1
;          size_lookup(ptr, len) -> px or -1
; ----------------------------------------------------------------------
tag_lookup:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    lea r14, [tags]
.loop:
    cmp r14, tags_end
    jge .none
    mov rdi, [r14]
    call strlen
    cmp rax, r13
    jne .next
    mov rdi, [r14]
    mov rsi, r12
    mov rdx, r13
    call strncmp
    test rax, rax
    jz .found
.next:
    add r14, 16
    jmp .loop
.found:
    mov rax, [r14 + 8]
    jmp .done
.none:
    mov rax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

palette_lookup:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    ; direct hex: #rgb or #rrggbb (Tailwind arbitrary colors)
    cmp byte [r12], '#'
    jne .named
    cmp r13, 4
    je .hex3
    cmp r13, 7
    je .hex6
    jmp .none
.hex3:
    ; #rgb -> 0xrrggbb (each nibble doubled): process digits left->right,
    ; shifting the accumulator left each position
    xor eax, eax
    mov ecx, 1
.h3l:
    movzx edx, byte [r12 + rcx]
    call hex_nib
    cmp edx, -1
    je .none
    shl eax, 8
    mov r8d, edx
    shl r8d, 4
    or eax, r8d
    or eax, edx
    inc rcx
    cmp rcx, 4
    jne .h3l
    jmp .done
.hex6:
    xor eax, eax
    mov ecx, 1
.h6l:
    movzx edx, byte [r12 + rcx]
    call hex_nib
    cmp edx, -1
    je .none
    shl eax, 4
    or eax, edx
    inc rcx
    cmp rcx, 7
    jne .h6l
    jmp .done
.named:
    lea r14, [tw_colors]
.loop:
    cmp r14, tw_colors_end
    jge .none
    mov rdi, [r14]
    call strlen
    cmp rax, r13
    jne .next
    mov rdi, [r14]
    mov rsi, r12
    mov rdx, r13
    call strncmp
    test rax, rax
    jz .found
.next:
    add r14, 16
    jmp .loop
.found:
    mov rax, [r14 + 8]
    jmp .done
.none:
    mov rax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; hex_nib(rdx = ascii) -> edx = 0..15 or -1
hex_nib:
    cmp dl, '0'
    jb .bad
    cmp dl, '9'
    ja .hexlet
    sub dl, '0'
    ret
.hexlet:
    or dl, 0x20              ; tolower
    cmp dl, 'a'
    jb .bad
    cmp dl, 'f'
    ja .bad
    sub dl, 'a' - 10
    ret
.bad:
    mov edx, -1
    ret

size_lookup:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    lea r14, [tw_sizes]
.loop:
    cmp r14, tw_sizes_end
    jge .none
    mov rdi, [r14]
    call strlen
    cmp rax, r13
    jne .next
    mov rdi, [r14]
    mov rsi, r12
    mov rdx, r13
    call strncmp
    test rax, rax
    jz .found
.next:
    add r14, 16
    jmp .loop
.found:
    mov rax, [r14 + 8]
    jmp .done
.none:
    mov rax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

scale_lookup:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    lea r14, [tw_scale]
.loop:
    cmp r14, tw_scale_end
    jge .none
    mov rdi, [r14]
    call strlen
    cmp rax, r13
    jne .next
    mov rdi, [r14]
    mov rsi, r12
    mov rdx, r13
    call strncmp
    test rax, rax
    jz .found
.next:
    add r14, 16
    jmp .loop
.found:
    mov rax, [r14 + 8]
    jmp .done
.none:
    mov rax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; atoi_n(rdi = ptr, rsi = len) -> rax (decimal, ate len chars)
; ----------------------------------------------------------------------
atoi_n:
    xor eax, eax
    xor ecx, ecx
.loop:
    cmp rcx, rsi
    jge .done
    mov dl, [rdi + rcx]
    cmp dl, '0'
    jb .done
    cmp dl, '9'
    ja .done
    imul rax, rax, 10
    movzx edx, dl
    sub edx, '0'
    add rax, rdx
    inc rcx
    jmp .loop
.done:
    ret

; hex_to_int(rdi = ptr, rsi = len) -> rax (hex, ate len chars)
hex_to_int:
    xor eax, eax
    xor ecx, ecx
.loop:
    cmp rcx, rsi
    jge .done
    mov dl, [rdi + rcx]
    cmp dl, '0'
    jb .done
    cmp dl, '9'
    jbe .digit
    or dl, 0x20
    cmp dl, 'a'
    jb .done
    cmp dl, 'f'
    ja .done
    sub dl, 'a' - 10
    jmp .apply
.digit:
    sub dl, '0'
.apply:
    shl eax, 4
    movzx edx, dl
    add eax, edx
    inc rcx
    jmp .loop
.done:
    ret

; ----------------------------------------------------------------------
; memcpy(rdi = dst, rsi = src, rdx = n)
