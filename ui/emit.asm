; =============================================================================
; emit.asm - page.s shell + component .wat
; =============================================================================

emit_shell:
    push rbx
    push r12
    push r13
    push r14
    push r15
    ; <label>_shell: db '
    lea rdi, [s_sh1]
    call out_label
    mov al, 39
    call out_byte
    ; <div id="ui" data-asx-root="<ui_name>"
    lea rdi, [s_ssr_div1]
    call out_str
    lea rdi, [ui_name_buf]
    mov rsi, [ui_name_len]
    call out_bytes
    ; " data-asx-checksum="<fnv1a over the canonical IR>"
    lea rdi, [s_ssr_ck1]
    call out_str
    call ssr_hash
    mov rdi, rax
    call ssr_hex8
    ; " data-modules="/<ui_name>
    lea rdi, [s_ssr_mod1]
    call out_str
    lea rdi, [ui_name_buf]
    mov rsi, [ui_name_len]
    call out_bytes
    ; suffix: index (root) -> ".wasm>"; other routes -> "/page.wasm>"
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
    lea rdi, [s_ssr_sufi]       ; '.wasm">'
    jmp .emit_suf
.use_page:
    lea rdi, [s_ssr_sufp]       ; '/page.wasm">'
.emit_suf:
    call out_str
    ; close the line and open the next one: ' + ', 10 + newline + db '
    call ssr_nl
    ; --- SSR widget tree (stable data-asx-id + inline CSS) ---
    call ssr_emit_children
    ; --- close the root #ui ---
    lea rdi, [s_ssr_close]
    call out_str
    call ssr_nl
    ; --- hydration snapshot (minimal render state) ---
    lea rdi, [s_ssr_snap1]
    call out_str
    lea rdi, [ui_name_buf]
    mov rsi, [ui_name_len]
    call out_bytes
    lea rdi, [s_ssr_snap2]
    call out_str
    call ssr_nl
    ; --- global base css (reset + theme) served with the SSR shell:
    ; the first paint is already the final layout, the glue skips its
    ; own copy when this tag is present (no flicker on reload) ---
    lea rdi, [s_ssr_sty1]
    call out_str
    mov rdi, [theme_bg]
    call ssr_hex6
    lea rdi, [s_ssr_sty2]
    call out_str
    mov rdi, [theme_text]
    call ssr_hex6
    lea rdi, [s_ssr_sty3]
    call out_str
    call ssr_nl
    ; --- the glue script (hydration happens in the browser) ---
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
    ; precompute the dyn text addresses (dst/prefix/suffix) before any
    ; emission: the montage in the body needs them, the data segments
    ; come later
    call precalc_dyn
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
    movzx edi, byte [r15 + 15]  ; alpha (0 = transparent view)
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
    ; dyn flag in the wasm record byte 25 (1 = interpolated text): the
    ; ssr_checksum skips its string on BOTH sides (the blob carries the
    ; same flag, set by serialize). The widget index equals the record
    ; index (widgets are created in rec_order).
    imul rax, r12, 12
    lea rcx, [rec_order + rax]
    mov edi, [rcx + 4]          ; node idx
    call dyn_find
    cmp rax, -1
    je .l2n
    lea rdi, [s_dyn_f1]
    call out_wat_str
    mov rdi, r12
    imul rdi, rdi, 32
    add rdi, 25
    call itoa_wat
    lea rdi, [s_dyn_f2]
    call out_wat_str
.l2n:
    inc r12
    jmp .l2
.l2d:
    ; rebuild the interpolated texts from the CURRENT state values
    ; (the records already point at the reserved addresses)
    call emit_dyn_montage
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
    ; dyn text? no data segment (the text is mounted at render time; the
    ; space is already reserved in the pool with padding by serialize)
    push r12
    push r15
    push rax                    ; text_offset
    imul rax, r12, 12
    lea rcx, [rec_order + rax]
    mov edi, [rcx + 4]          ; node idx
    call dyn_find
    cmp rax, -1
    pop rax                     ; restore text_offset (flags kept)
    pop r15
    pop r12
    jne .dn
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
    ; ---- dyn text prefix/suffix data segments ----
    call emit_dyn_parts
    ; advance the cursor over the dyn parts BEFORE the states (their
    ; data segment must not collide with the prefix/suffix segments)
    mov eax, [dyn_parts_len]
    add [str_cursor], rax
    ; ---- declarative states: strings + state_data ----
    call emit_states
    ; ---- style records (20B each, after the string pool) ----
    ; build style_buf: one 20-byte style record per widget record
    ; (same order as the 32B blob records): flags u32, weight u16,
    ; align, gap, radius, px, py, border, opacity, shadow, role, pad,
    ; mt, mb, h, grid_cols
    call build_style_records
    ; styles data segment at STR_BASE + str_cursor
    mov rax, [str_cursor]
    add rax, STR_BASE
    mov [style_addr], rax
    lea rdi, [s_wat_d1]
    call out_wat_str
    mov rdi, [style_addr]
    call itoa_wat
    lea rdi, [s_wat_d2]
    call out_wat_str
    xor r13, r13
.sbytes:
    cmp r13, [style_len]
    jge .sbytes_done
    lea rbx, [style_buf + r13]
    xor r14, r14
.sbyte_inner:
    cmp r14, 20
    jge .sbyte_next
    movzx eax, byte [rbx + r14]
    call out_wat_byte_hex
    inc r14
    jmp .sbyte_inner
.sbyte_next:
    add r13, 20
    jmp .sbytes
.sbytes_done:
    lea rdi, [s_wat_d3]
    call out_wat_str
    ; str_cursor += state_data + 20 * rec_count (dyn_parts already added)
    mov eax, [state_data_len]
    add [str_cursor], rax
    mov eax, [rec_count]
    imul eax, eax, 20
    add [str_cursor], rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; build_style_records - fills style_buf with one 20-byte style record per
; widget record (same order as the 32B blob records): flags u32, weight
; u16, align, gap, radius, px, py, border, opacity, shadow, role, pad,
; mt, mb, h, grid_cols. Sets style_len = rec_count * 20. Called by
; emit_wat_componente AND by the SSR pass (emit_shell) - the SSR HTML
; needs the same style data.
build_style_records:
    push rbx
    push r12
    push r13
    mov rax, [rec_count]
    imul rax, rax, 20
    mov [style_len], rax
    xor r13, r13
.sloop:
    cmp r13, [rec_count]
    jge .sloop_done
    imul rax, r13, 12
    lea rcx, [rec_order + rax]
    mov eax, [rcx]               ; kind
    mov ebx, [rcx + 4]           ; node idx
    imul rbx, rbx, NODE_SIZE
    lea rbx, [nodes + rbx]       ; node ptr
    imul rax, r13, 20
    lea rdi, [style_buf + rax]
    ; zero the 20 bytes
    mov ecx, 20
    xor eax, eax
    rep stosb
    imul rax, r13, 20
    lea rdi, [style_buf + rax]
    ; flags u32
    mov eax, [rbx + N_FLAGS]
    mov [rdi], eax
    ; weight u16
    movzx eax, word [rbx + N_WEIGHT]
    mov [rdi + 4], ax
    ; align/gap/radius/px/py/border/opacity/shadow
    movzx eax, byte [rbx + N_ALIGN]
    mov [rdi + 6], al
    movzx eax, byte [rbx + N_GAP]
    mov [rdi + 7], al
    movzx eax, byte [rbx + N_RADIUS]
    mov [rdi + 8], al
    movzx eax, byte [rbx + N_PX]
    mov [rdi + 9], al
    movzx eax, byte [rbx + N_PY]
    mov [rdi + 10], al
    movzx eax, byte [rbx + N_BORDER]
    mov [rdi + 11], al
    movzx eax, byte [rbx + N_OPACITY]
    mov [rdi + 12], al
    movzx eax, byte [rbx + N_SHADOW]
    mov [rdi + 13], al
    ; role: kind 1 (button view) = 1 (recompute rec_order ptr - rep
    ; stosb clobbered rcx)
    imul rax, r13, 12
    lea rcx, [rec_order + rax]
    mov eax, [rcx]               ; kind
    cmp eax, 1
    jne .role0
    mov byte [rdi + 14], 1
.role0:
    ; pad (p-*), mt, mb, explicit height (h-*), grid cols
    movzx eax, byte [rbx + N_PAD]
    mov [rdi + 15], al
    movzx eax, byte [rbx + N_MT]
    mov [rdi + 16], al
    movzx eax, byte [rbx + N_MB]
    mov [rdi + 17], al
    movzx eax, byte [rbx + N_H]
    mov [rdi + 18], al
    movzx eax, byte [rbx + N_GRID_COLS]
    mov [rdi + 19], al
    inc r13
    jmp .sloop
.sloop_done:
    pop r13
    pop r12
    pop rbx
    ret

; out_wat_byte_hex(al = byte) - writes \hh
out_wat_byte_hex:
    push rax
    lea rdi, [s_wat_bs]
    call out_wat_str
    pop rax
    push rax
    shr al, 4
    call out_wat_nibble
    pop rax
    and al, 0x0f
    call out_wat_nibble
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

; ----------------------------------------------------------------------
; precalc_dyn - computes, for every dyn text, the wasm addresses of the
; mounted text (dst), the prefix and the suffix. The addresses depend on
; the pool size, so they are computed BEFORE the body is emitted.
; ----------------------------------------------------------------------
precalc_dyn:
    push rbx
    push r12
    push r13
    push r14
    push r15
    ; pool_size
    mov eax, [blob_len]
    sub eax, 24
    mov ecx, [rec_count]
    imul ecx, ecx, 32
    sub eax, ecx
    mov r12d, eax               ; pool_size
    ; post-pool cursor (base of the prefix/suffix segments)
    mov eax, [str_cursor]
    add eax, r12d
    mov r13d, eax
    xor r14d, r14d              ; acc
    xor r15, r15                ; dyn idx
.pd_loop:
    cmp r15, [dyn_count]
    jge .pd_done
    imul rax, r15, DYN_ENTRY
    lea rbx, [dyn_tab + rax]
    ; node -> record -> text_offset
    mov r12d, [rbx + D_NODE]
    xor r8, r8
.pd_rec:
    cmp r8, [rec_count]
    jge .pd_next
    imul rax, r8, 12
    lea r9, [rec_order + rax]
    cmp dword [r9 + 4], r12d
    jne .pd_rec_next
    imul rax, r8, 32
    lea r9, [blob_buf + rax + 24]
    mov r12d, [r9 + 16]         ; text_offset
    ; dst
    mov rdi, r12
    call wat_text_addr          ; uses the CURRENT str_cursor (pre-pool)
    mov [dyn_dst + r15*4], eax
    ; prefix_addr = STR_BASE + post_pool + acc
    lea eax, [r13 + r14]
    add eax, STR_BASE
    mov [dyn_prefix + r15*4], eax
    mov eax, [rbx + D_PREFIX_LEN]
    inc eax
    add r14d, eax
    ; suffix_addr
    lea eax, [r13 + r14]
    add eax, STR_BASE
    mov [dyn_suffix + r15*4], eax
    mov eax, [rbx + D_SUFFIX_LEN]
    inc eax
    add r14d, eax
    jmp .pd_next
.pd_rec_next:
    inc r8
    jmp .pd_rec
.pd_next:
    inc r15
    jmp .pd_loop
.pd_done:
    mov [dyn_parts_len], r14
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; emit_dyn_montage - inside render, after the calls: rebuild the
; interpolated texts from the current state values.
; ----------------------------------------------------------------------
emit_dyn_montage:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp qword [dyn_count], 0
    je .done
    xor r12, r12
.dm_loop:
    cmp r12, [dyn_count]
    jge .done
    imul rax, r12, DYN_ENTRY
    lea r13, [dyn_tab + rax]
    ; dst
    lea rdi, [s_fmt_d1]
    call out_wat_str
    mov edi, [dyn_dst + r12*4]
    call itoa_wat
    lea rdi, [s_fmt_d2]
    call out_wat_str
    mov edi, [dyn_prefix + r12*4]
    call itoa_wat
    lea rdi, [s_fmt_d3]
    call out_wat_str
    mov edi, [r13 + D_PREFIX_LEN]
    call itoa_wat
    ; value: field kind + address
    mov r14d, [r13 + D_STATE]
    mov r15d, [r13 + D_FIELD]
    mov eax, [r13 + D_FIELD]
    cmp eax, -1
    jne .dm_obj
    imul rax, r14, STATE_ENTRY
    mov ebx, [state_tab + rax + S_KIND]
    jmp .dm_have_kind
.dm_obj:
    imul rax, r14, STATE_ENTRY
    mov edx, [state_tab + rax + S_TYPE_IDX]
    imul rax, rdx, TYPE_ENTRY
    mov ecx, [type_tab + rax + T_FIELDS_IDX]
    imul rax, r15, FIELD_ENTRY
    mov ebx, [field_tab + rcx + rax + F_KIND]
.dm_have_kind:
    mov rdi, r14
    mov rsi, r15
    call state_field_addr       ; rax = offset into state_data
    mov r14d, eax
    lea rdi, [s_fmt_d4]
    call out_wat_str
    mov rdi, r14
    call itoa_wat
    lea rdi, [s_fmt_d5]
    call out_wat_str
    mov edi, [dyn_suffix + r12*4]
    call itoa_wat
    cmp ebx, K_STR
    je .dm_str
    lea rdi, [s_fmt_call]
    call out_wat_str
    jmp .dm_next
.dm_str:
    lea rdi, [s_fmt_callstr]
    call out_wat_str
.dm_next:
    inc r12
    jmp .dm_loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; emit_dyn_parts - emits the prefix/suffix data segments of the dyn
; texts (after the string pool).
; ----------------------------------------------------------------------
emit_dyn_parts:
    push rbx
    push r12
    push r13
    push r14
    xor r12, r12
.edp_loop:
    cmp r12, [dyn_count]
    jge .done
    imul rax, r12, DYN_ENTRY
    lea rbx, [dyn_tab + rax]
    ; prefix segment
    lea rdi, [s_wat_d1]
    call out_wat_str
    mov edi, [dyn_prefix + r12*4]
    call itoa_wat
    lea rdi, [s_wat_d2]
    call out_wat_str
    mov r13d, [rbx + D_NODE]
    imul rax, r13, NODE_SIZE
    mov r14d, [nodes + rax + N_TEXT_PTR]
    lea rdi, [in_buf + r14]
    mov esi, [rbx + D_PREFIX_LEN]   ; u32 field!
    call out_wat_text
    lea rdi, [s_wat_d3]
    call out_wat_str
    ; suffix segment
    lea rdi, [s_wat_d1]
    call out_wat_str
    mov edi, [dyn_suffix + r12*4]
    call itoa_wat
    lea rdi, [s_wat_d2]
    call out_wat_str
    mov r13d, [rbx + D_NODE]
    imul rax, r13, NODE_SIZE
    mov r14d, [nodes + rax + N_TEXT_PTR]
    add r14d, [rbx + D_SUFFIX_OFF]
    lea rdi, [in_buf + r14]
    mov esi, [rbx + D_SUFFIX_LEN]   ; u32 field!
    call out_wat_text
    lea rdi, [s_wat_d3]
    call out_wat_str
    inc r12
    jmp .edp_loop
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; emit_states - emits the state data: the string bytes first (as data
; segments, in field order), then the resolved state_data record (string
; fields rewritten with the wasm addresses). Sets state_base_addr.
; ----------------------------------------------------------------------
emit_states:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp qword [state_count], 0
    je .done
    ; ---- pass 1: string data segments + their wasm addrs ----
    xor r12, r12                ; string counter (order)
    xor r13, r13                ; state idx
.es_state:
    cmp r13, [state_count]
    jge .es_resolve
    imul rax, r13, STATE_ENTRY
    lea r14, [state_tab + rax]
    cmp dword [r14 + S_IS_OBJ], 1
    je .es_obj
    ; scalar string?
    cmp dword [r14 + S_KIND], K_STR
    jne .es_next_state
    mov eax, [r14 + S_DATA_OFF]
    mov ecx, [state_data + rax]     ; offset in state_str_buf
    push r14
    call emit_state_str
    pop r14
    inc r12
    jmp .es_next_state
.es_obj:
    mov eax, [r14 + S_TYPE_IDX]
    imul rax, rax, TYPE_ENTRY
    lea r15, [type_tab + rax]
    mov ebx, [r15 + T_FIELDS_IDX]
    mov r8d, [r15 + T_N_FIELDS]
    xor r9, r9
.es_field:
    cmp r9, r8
    jge .es_next_state
    imul rax, r9, FIELD_ENTRY
    lea rax, [field_tab + rbx + rax]
    cmp dword [rax + F_KIND], K_STR
    jne .es_next_field
    mov edx, [r14 + S_DATA_OFF]
    add edx, [rax + F_OFFSET]
    mov ecx, [state_data + rdx]     ; offset in state_str_buf
    push r14
    push r15
    push rbx
    push r8
    push r9
    call emit_state_str
    pop r9
    pop r8
    pop rbx
    pop r15
    pop r14
    inc r12
.es_next_field:
    inc r9
    jmp .es_field
.es_next_state:
    inc r13
    jmp .es_state
.es_resolve:
    ; ---- pass 2: build state_data_out with the resolved ptrs ----
    xor r12, r12                ; string counter (same order)
    xor r13, r13                ; state idx
    xor r14, r14                ; out pos
.er_state:
    cmp r13, [state_count]
    jge .er_emit
    imul rax, r13, STATE_ENTRY
    lea rbx, [state_tab + rax]
    cmp dword [rbx + S_IS_OBJ], 1
    je .er_obj
    mov eax, [rbx + S_DATA_OFF]
    cmp dword [rbx + S_KIND], K_STR
    jne .er_int
    mov edx, [str_addr_buf + r12*4]
    mov [state_data_out + r14], edx
    inc r12
    add r14, 4
    jmp .er_next_state
.er_int:
    mov edx, [state_data + rax]
    mov [state_data_out + r14], edx
    add r14, 4
    jmp .er_next_state
.er_obj:
    mov eax, [rbx + S_TYPE_IDX]
    imul rax, rax, TYPE_ENTRY
    lea r15, [type_tab + rax]
    mov r10d, [r15 + T_FIELDS_IDX]
    mov r8d, [r15 + T_N_FIELDS]
    xor r9, r9
.er_field:
    cmp r9, r8
    jge .er_next_state
    imul rax, r9, FIELD_ENTRY
    lea rax, [field_tab + r10 + rax]
    mov ecx, [rbx + S_DATA_OFF]
    add ecx, [rax + F_OFFSET]
    cmp dword [rax + F_KIND], K_STR
    jne .er_field_int
    mov edx, [str_addr_buf + r12*4]
    mov [state_data_out + r14], edx
    inc r12
    jmp .er_field_next
.er_field_int:
    mov edx, [state_data + rcx]
    mov [state_data_out + r14], edx
.er_field_next:
    add r14, 4
    inc r9
    jmp .er_field
.er_next_state:
    inc r13
    jmp .er_state
.er_emit:
    ; state_base = STR_BASE + str_cursor
    mov eax, [str_cursor]
    add eax, STR_BASE
    mov [state_base_addr], eax
    lea rdi, [s_wat_d1]
    call out_wat_str
    mov rdi, [state_base_addr]
    call itoa_wat
    lea rdi, [s_wat_d2]
    call out_wat_str
    xor r13, r13
.er_bytes:
    cmp r13, [state_data_len]
    jge .er_bytes_done
    movzx eax, byte [state_data_out + r13]
    call out_wat_byte_hex
    inc r13
    jmp .er_bytes
.er_bytes_done:
    lea rdi, [s_wat_d3]
    call out_wat_str
    mov eax, [state_data_len]
    add [str_cursor], rax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; emit_state_str(rcx = state_str_buf offset, r12 = string counter)
; - emits a data segment for the string and stores its wasm address in
;   str_addr_buf[r12*4]; advances str_cursor.
; ----------------------------------------------------------------------
emit_state_str:
    push rbx
    push r12
    push r13
    push r14
    mov r14d, ecx               ; string offset (strlen clobbers rcx!)
    mov edx, [str_cursor]
    add edx, STR_BASE
    mov [str_addr_buf + r12*4], edx
    lea rdi, [s_wat_d1]
    call out_wat_str
    mov rdi, rdx
    call itoa_wat
    lea rdi, [s_wat_d2]
    call out_wat_str
    lea rdi, [state_str_buf + r14]
    call strlen
    mov r13, rax
    lea rdi, [state_str_buf + r14]
    mov rsi, r13
    call out_wat_text
    lea rdi, [s_wat_d3]
    call out_wat_str
    lea rax, [r13 + 1]
    add [str_cursor], rax
    pop r14
    pop r13
    pop r12
    pop rbx
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
