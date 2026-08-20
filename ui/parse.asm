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
    shr rdi, 7                  ; node idx (NODE_SIZE = 128)
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
    mov r8d, eax                ; tag id
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
    mov [rdi + N_TAG], r8b
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
    ; find a ':' in [r9, r14) - the inline text separator
    mov r8, r9
.cls_scan:
    cmp r8, r14
    jge .cls_done
    cmp byte [in_buf + r8], ':'
    je .cls_colon
    inc r8
    jmp .cls_scan
.cls_colon:
    mov rdx, r8                 ; classes end at the colon
.cls_done:
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
class_apply:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    ; ---- exact-name tables (flags / rounded / font-weight / shadow) ----
    lea rdx, [tw_flags]
    lea rcx, [tw_flags_end]
    call tw_lookup
    cmp rax, -1
    je .not_flags
    or [r12 + N_FLAGS], eax
    jmp .done
.not_flags:
    lea rdx, [tw_round]
    lea rcx, [tw_round_end]
    call tw_lookup
    cmp rax, -1
    je .not_round
    mov [r12 + N_RADIUS], eax
    jmp .done
.not_round:
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
    lea rdx, [tw_shadow]
    lea rcx, [tw_shadow_end]
    call tw_lookup
    cmp rax, -1
    je .not_shadow
    mov [r12 + N_SHADOW], eax
    jmp .done
.not_shadow:
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
    ; m-<n> (after mt-/mb-)
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
    mov [r12 + N_MT], eax
    mov [r12 + N_MB], eax
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
