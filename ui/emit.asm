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
    ; --- responsive/hover variants: <style data-asx-variants> ---
    ; one rule per variant entry: hover (no media query) or
    ; @media(min-width:<bp>px). !important wins over the inline cssText
    ; the glue writes during hydration (specificity of the attribute
    ; selector is the same, importance is what breaks the tie).
    call emit_variants
    call emit_animations
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
    ; real HTML tag id: i32.store8 tag_id at widget_base + rec*32 + 1
    lea rdi, [s_dyn_f1]
    call out_wat_str
    mov rdi, r12
    imul rdi, rdi, 32
    add rdi, 1
    call itoa_wat
    lea rdi, [s_tag_f2]
    call out_wat_str
    movzx edi, byte [r15 + 1]   ; tag id from the blob record
    call itoa_wat
    lea rdi, [s_tag_f3]
    call out_wat_str
    ; html attributes: i32.store ABSOLUTE address at widget_base +
    ; rec*32 + 26 (bytes 26..29). The blob carried the relative offset;
    ; the checksum skips 26..30 on both sides.
    mov eax, [r15 + 26]
    test eax, eax
    jz .l2n_noattr
    lea rdi, [s_dyn_f1]
    call out_wat_str
    mov rdi, r12
    imul rdi, rdi, 32
    add rdi, 26
    call itoa_wat
    lea rdi, [s_attr_f2]
    call out_wat_str
    mov edi, [r15 + 26]
    call wat_text_addr          ; rax = endereco wasm do attr string
    mov rdi, rax
    call itoa_wat
    lea rdi, [s_attr_f3]
    call out_wat_str
.l2n_noattr:
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
    ; html attributes: emit the attr string data segment (record byte
    ; 26..29 carries the blob-relative offset; the store in the body
    ; already wrote the absolute address into the wasm record)
    mov eax, [r15 + 26]
    test eax, eax
    jz .dn_noattr
    push r12
    push r15
    push rax                    ; attr offset (blob-relative)
    mov rdi, rax
    call wat_text_addr          ; rax = endereco wasm
    mov rbx, rax
    lea rdi, [s_wat_d1]
    call out_wat_str
    mov rdi, rbx
    call itoa_wat
    lea rdi, [s_wat_d2]
    call out_wat_str
    ; attr text: [blob_buf + attr_offset] up to the 0 (pool null)
    pop rax
    lea rdi, [blob_buf + rax]
    mov rsi, rdi
.atx_scan:
    cmp byte [rsi], 0
    je .atx_found
    inc rsi
    jmp .atx_scan
.atx_found:
    sub rsi, rdi                ; attr length
    call out_wat_text
    lea rdi, [s_wat_d3]
    call out_wat_str
    pop r15
    pop r12
.dn_noattr:
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
    ; ---- style records (STYLE_REC bytes each, after the string pool) ----
    ; build style_buf: one STYLE_REC-byte style record per widget record
    ; (same order as the 32B blob records): flags u32, weight u16,
    ; align, gap, radius, px, py, border, opacity, shadow, role, pad,
    ; mt, mb, h, grid_cols, ml, mr, pl, pr, pt, pb
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
    cmp r14, STYLE_REC
    jge .sbyte_next
    movzx eax, byte [rbx + r14]
    call out_wat_byte_hex
    inc r14
    jmp .sbyte_inner
.sbyte_next:
    add r13, STYLE_REC
    jmp .sbytes
.sbytes_done:
    lea rdi, [s_wat_d3]
    call out_wat_str
    ; str_cursor += state_data + STYLE_REC * rec_count (dyn_parts already added)
    mov eax, [state_data_len]
    add [str_cursor], rax
    mov eax, [rec_count]
    imul eax, eax, STYLE_REC
    add [str_cursor], rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; build_style_records - fills style_buf with one STYLE_REC-byte style
; record per widget record (same order as the 32B blob records): flags
; u32, weight u16, align, gap, radius, px, py, border, opacity, shadow,
; role, pad, mt, mb, h, grid_cols, ml, mr, pl, pr, pt, pb. Sets
; style_len = rec_count * STYLE_REC. Called by emit_wat_componente AND by
; the SSR pass (emit_shell) - the SSR HTML needs the same style data.
build_style_records:
    push rbx
    push r12
    push r13
    mov rax, [rec_count]
    imul rax, rax, STYLE_REC
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
    imul rax, r13, STYLE_REC
    lea rdi, [style_buf + rax]
    ; zero the record
    mov ecx, STYLE_REC
    xor eax, eax
    rep stosb
    imul rax, r13, STYLE_REC
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
    ; x-axis margins/paddings + pt/pb (2026-08-20): +20 ml +21 mr
    ; +22 pl +23 pr +24 pt +25 pb
    movzx eax, byte [rbx + N_ML]
    mov [rdi + 20], al
    movzx eax, byte [rbx + N_MR]
    mov [rdi + 21], al
    movzx eax, byte [rbx + N_PL]
    mov [rdi + 22], al
    movzx eax, byte [rbx + N_PR]
    mov [rdi + 23], al
    movzx eax, byte [rbx + N_PT]
    mov [rdi + 24], al
    movzx eax, byte [rbx + N_PB]
    mov [rdi + 25], al
    ; transitions (2026-08-20): +26 trans +27 ease +28 duration u16 +30 delay u16
    movzx eax, byte [rbx + N_TRANS]
    mov [rdi + 26], al
    movzx eax, byte [rbx + N_EASE]
    mov [rdi + 27], al
    movzx eax, word [rbx + N_DUR]
    mov [rdi + 28], ax
    movzx eax, word [rbx + N_DELAY]
    mov [rdi + 30], ax
    ; typography + animation (2026-08-20): +32 anim +33 tbehav +34 family
    ; +35 stretch +36 varnum +37 tracking +38 leading +39 whitespace
    ; +40 wordbreak +41 overflow +42 valign +43 indent +44 deco_style
    ; +45 deco_thick +46 deco_color u32 +50 uo +51 clamp +52 list_pos
    ; +53 list_type +54 hyphens +55 tab_size +56 content +57 textwrap
    ; +58 smoothing
    movzx eax, byte [rbx + N_ANIM]
    mov [rdi + 32], al
    movzx eax, byte [rbx + N_TBEHAV]
    mov [rdi + 33], al
    movzx eax, byte [rbx + N_FAMILY]
    mov [rdi + 34], al
    movzx eax, byte [rbx + N_STRETCH]
    mov [rdi + 35], al
    movzx eax, byte [rbx + N_VARNUM]
    mov [rdi + 36], al
    movzx eax, byte [rbx + N_TRACK]
    mov [rdi + 37], al
    movzx eax, byte [rbx + N_LEAD]
    mov [rdi + 38], al
    movzx eax, byte [rbx + N_WS]
    mov [rdi + 39], al
    movzx eax, byte [rbx + N_WBREAK]
    mov [rdi + 40], al
    movzx eax, byte [rbx + N_OVERFLOW]
    mov [rdi + 41], al
    movzx eax, byte [rbx + N_VALIGN]
    mov [rdi + 42], al
    movzx eax, byte [rbx + N_INDENT]
    mov [rdi + 43], al
    movzx eax, byte [rbx + N_DSTYLE]
    mov [rdi + 44], al
    movzx eax, byte [rbx + N_DTHICK]
    mov [rdi + 45], al
    mov eax, [rbx + N_DCOLOR]
    test eax, eax
    jnz .have_dcol
    mov eax, -1              ; 0 = unset -> 0xFFFFFFFF sentinel (none)
.have_dcol:
    mov [rdi + 46], eax
    movzx eax, byte [rbx + N_UO]
    mov [rdi + 50], al
    movzx eax, byte [rbx + N_CLAMP]
    mov [rdi + 51], al
    movzx eax, byte [rbx + N_LISTPOS]
    mov [rdi + 52], al
    movzx eax, byte [rbx + N_LISTTYPE]
    mov [rdi + 53], al
    movzx eax, byte [rbx + N_HYPHENS]
    mov [rdi + 54], al
    movzx eax, byte [rbx + N_TABSIZE]
    mov [rdi + 55], al
    movzx eax, byte [rbx + N_CONTENT]
    mov [rdi + 56], al
    movzx eax, byte [rbx + N_TWRAP]
    mov [rdi + 57], al
    movzx eax, byte [rbx + N_SMOOTH]
    mov [rdi + 58], al
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
    ; a button emits TWO records with the same node (view + label);
    ; the dyn text lives on the LABEL (kind 2) - skip records whose
    ; text_offset is 0 (views), otherwise the montage would write at
    ; the pool start (wat_text_addr(0)) and corrupt the first string.
    imul rax, r8, 32
    lea r9, [blob_buf + rax + 24]
    cmp dword [r9 + 16], 0
    je .pd_rec_next
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

; ----------------------------------------------------------------------
; emit_variants - <style data-asx-variants>...</style> with one rule per
; variant entry. The rule targets the widget by data-asx-id and uses
; !important so it beats the inline cssText the glue writes during
; hydration. Field -> CSS mapping mirrors ssr_css_view/ssr_css_label.
; ----------------------------------------------------------------------
emit_variants:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp qword [variant_count], 0
    je .done
    lea rdi, [s_var_open]
    call out_str
    xor r13, r13
.loop:
    cmp r13, [variant_count]
    jge .close
    imul rax, r13, VAR_ENTRY
    lea r15, [variant_tab + rax]
    mov r12d, [r15 + V_BP]
    mov ebx, [r15 + V_NODE]
    ; selector: hover -> [data-asx-id="N"]:hover ; else @media(min-width:P)
    test r12d, r12d
    jnz .media
    lea rdi, [s_var_hov1]
    call out_str
    mov rdi, rbx
    call ssr_dec
    lea rdi, [s_var_hov2]
    call out_str
    jmp .have_sel
.media:
    lea rdi, [s_var_mq1]
    call out_str
    mov rdi, r12
    call variant_bp_width
    mov rdi, rax
    call ssr_dec
    lea rdi, [s_var_mq2]
    call out_str
    mov rdi, rbx
    call ssr_dec
    lea rdi, [s_var_mq3]
    call out_str
.have_sel:
    ; property for the changed field (u32 loads: the table stores
    ; dwords; loading 8 bytes would mix in the next entry's bytes)
    mov edi, [r15 + V_FIELD]
    mov esi, [r15 + V_VALUE]
    mov r14d, [out_len]          ; rule start (selector already emitted)
    call emit_var_prop
    ; !important pass: every ';' that is NOT the last byte of the rule
    ; becomes "!important;" so multi-declaration rules (padding-left/right,
    ; flex+direction, clamp+overflow) carry the importance on EACH
    ; declaration. A trailing ';' (last byte) is left for the strip+append.
    xor ecx, ecx                 ; count eligible ';' in the rule
    mov rsi, r14
.count_semi:
    cmp rsi, [out_len]
    jge .count_done
    cmp byte [out_buf + rsi], ';'
    jne .count_next
    lea rax, [rsi + 1]
    cmp rax, [out_len]
    jge .count_next              ; trailing ';' (last byte) -> strip handles it
    inc ecx
.count_next:
    inc rsi
    jmp .count_semi
.count_done:
    test ecx, ecx
    jz .imp_done
    mov rsi, r14
    xor edi, edi                 ; dst index into var_rule_buf
.cp_loop:
    cmp rsi, [out_len]
    jge .cp_done
    mov al, [out_buf + rsi]
    mov [var_rule_buf + rdi], al
    inc rdi
    inc rsi
    cmp al, ';'
    jne .cp_loop
    cmp rsi, [out_len]
    jge .cp_loop                 ; trailing ';' (last byte) stays
    ; not trailing: "!important" goes BEFORE the ';' - the ';' was just
    ; written at var_rule_buf[rdi-1]; back up, write the bang, then the ';'
    dec rdi
    lea r9, [s_bang]
    mov ecx, 10
.cp_bang:
    mov al, [r9]
    mov [var_rule_buf + rdi], al
    inc rdi
    inc r9
    dec ecx
    jnz .cp_bang
    mov al, ';'
    mov [var_rule_buf + rdi], al
    inc rdi
    jmp .cp_loop
.cp_done:
    mov rcx, rdi
    mov rsi, var_rule_buf
    lea rdi, [out_buf + r14]
    push rcx                 ; rep movsb clobbers rcx - save the length
    rep movsb
    pop rcx
    add r14, rcx
    mov [out_len], r14
.imp_done:
    ; strip the trailing ';' so the !important lands inside the
    ; declaration (a ';' before it would make the rule invalid and the
    ; browser would drop it).
    mov rcx, [out_len]
    test rcx, rcx
    jz .have_end
    cmp byte [out_buf + rcx - 1], ';'
    jne .have_end
    dec rcx
    mov [out_len], rcx
.have_end:
    lea rdi, [s_var_end]
    call out_str
    inc r13
    jmp .loop
.close:
    lea rdi, [s_var_close]
    call out_str
    call ssr_nl
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; emit_animations - <style data-asx-anim> with ONLY the @keyframes actually
; used (nodes with N_ANIM set + variant entries changing N_ANIM). SSR-only
; like the variants block; the glue never touches it.
emit_animations:
    push rbx
    push r12
    push r13
    xor r12d, r12d           ; used bits (spin=1 ping=2 pulse=4 bounce=8)
    xor r13, r13
.aloop:
    cmp r13, [rec_count]
    jge .avars
    imul rax, r13, 12
    mov eax, [rec_order + rax + 4]   ; node idx
    imul rax, rax, NODE_SIZE
    mov eax, [nodes + rax + N_ANIM]
    test eax, eax
    jz .anext
    dec eax
    mov cl, al
    mov edx, 1
    shl edx, cl
    or r12d, edx
.anext:
    inc r13
    jmp .aloop
.avars:
    ; variant entries may animate too (e.g. hover:animate-spin)
    xor r13, r13
.aloop2:
    cmp r13, [variant_count]
    jge .have_used
    imul rax, r13, VAR_ENTRY
    cmp dword [variant_tab + rax + V_FIELD], N_ANIM
    jne .anext2
    mov eax, [variant_tab + rax + V_VALUE]
    dec eax
    mov cl, al
    mov edx, 1
    shl edx, cl
    or r12d, edx
.anext2:
    inc r13
    jmp .aloop2
.have_used:
    test r12d, r12d
    jz .done
    lea rdi, [s_anim_open]
    call out_str
    test r12d, 1
    jz .nospin
    lea rdi, [s_kf_spin]
    call out_str
.nospin:
    test r12d, 2
    jz .noping
    lea rdi, [s_kf_ping]
    call out_str
.noping:
    test r12d, 4
    jz .nopulse
    lea rdi, [s_kf_pulse]
    call out_str
.nopulse:
    test r12d, 8
    jz .nobounce
    lea rdi, [s_kf_bounce]
    call out_str
.nobounce:
    lea rdi, [s_anim_close]
    call out_str
    call ssr_nl
.done:
    pop r13
    pop r12
    pop rbx
    ret

; variant_bp_width(bp id) -> min-width px
variant_bp_width:
    cmp rdi, 1
    jne .b2
    mov rax, BP_XS
    ret
.b2:
    cmp rdi, 2
    jne .b3
    mov rax, BP_SM
    ret
.b3:
    cmp rdi, 3
    jne .b4
    mov rax, BP_MD
    ret
.b4:
    cmp rdi, 4
    jne .b5
    mov rax, BP_LG
    ret
.b5:
    cmp rdi, 5
    jne .b6
    mov rax, BP_XL
    ret
.b6:
    mov rax, BP_2XL
    ret

; emit_var_prop(rdi = field offset, rsi = value) - writes "prop:val;" 
emit_var_prop:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    ; dispatch by field offset (mirrors the node struct + ssr emitters)
    cmp r12d, N_BG
    jne .not_bg
    lea rdi, [s_var_bg]
    call out_str
    mov rdi, r13
    call ssr_hex6
    jmp .done
.not_bg:
    cmp r12d, N_COLOR
    jne .not_color
    lea rdi, [s_var_tcol]
    call out_str
    mov rdi, r13
    call ssr_hex6
    jmp .done
.not_color:
    cmp r12d, N_FS
    jne .not_fs
    lea rdi, [s_var_fs]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_fs:
    cmp r12d, N_PAD
    jne .not_pad
    lea rdi, [s_var_pad]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_pad:
    cmp r12d, N_MT
    jne .not_mt
    lea rdi, [s_var_mt]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_mt:
    cmp r12d, N_MB
    jne .not_mb
    lea rdi, [s_var_mb]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_mb:
    cmp r12d, N_ML
    jne .not_ml
    lea rdi, [s_var_ml]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_ml:
    cmp r12d, N_MR
    jne .not_mr
    lea rdi, [s_var_mr]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_mr:
    cmp r12d, N_PL
    jne .not_pl
    lea rdi, [s_var_pl]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_pl:
    cmp r12d, N_PR
    jne .not_pr
    lea rdi, [s_var_pr]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_pr:
    cmp r12d, N_PT
    jne .not_pt
    lea rdi, [s_var_pt]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_pt:
    cmp r12d, N_PB
    jne .not_pb
    lea rdi, [s_var_pb]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_pb:
    cmp r12d, N_PX
    jne .not_pxv
    lea rdi, [s_var_plx]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    lea rdi, [s_var_prx]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_pxv:
    cmp r12d, N_PY
    jne .not_pyv
    lea rdi, [s_var_pt]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    lea rdi, [s_var_pb]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_pyv:
    cmp r12d, N_H
    jne .not_hv
    lea rdi, [s_css_mh]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_hv:
    cmp r12d, N_BORDER
    jne .not_bdv
    lea rdi, [s_css_bd1]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_css_bd2]
    call out_str
    jmp .done
.not_bdv:
    cmp r12d, N_TRANS
    jne .not_trans
    lea rdi, [s_var_tprop]
    call out_str
    cmp r13d, 2
    jne .vt3
    lea rdi, [s_tp_none]
    jmp .vt_done
.vt3:
    cmp r13d, 3
    jne .vt4
    lea rdi, [s_tp_all]
    jmp .vt_done
.vt4:
    cmp r13d, 4
    jne .vt5
    lea rdi, [s_tp_colors]
    jmp .vt_done
.vt5:
    cmp r13d, 5
    jne .vt6
    lea rdi, [s_tp_opacity]
    jmp .vt_done
.vt6:
    cmp r13d, 6
    jne .vt7
    lea rdi, [s_tp_shadow]
    jmp .vt_done
.vt7:
    cmp r13d, 7
    jne .vt_def
    lea rdi, [s_tp_transform]
    jmp .vt_done
.vt_def:
    lea rdi, [s_tp_default]
.vt_done:
    call out_str
    jmp .done
.not_trans:
    cmp r12d, N_EASE
    jne .not_ease
    lea rdi, [s_var_tfn]
    call out_str
    cmp r13d, 1
    jne .ve2
    lea rdi, [s_ease_linear]
    jmp .ve_done
.ve2:
    cmp r13d, 2
    jne .ve3
    lea rdi, [s_ease_in]
    jmp .ve_done
.ve3:
    cmp r13d, 3
    jne .ve4
    lea rdi, [s_ease_out]
    jmp .ve_done
.ve4:
    lea rdi, [s_ease_inout]
.ve_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_ease:
    cmp r12d, N_DUR
    jne .not_dur
    lea rdi, [s_var_tdur]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_ms]
    call out_str
    jmp .done
.not_dur:
    cmp r12d, N_DELAY
    jne .not_delay
    lea rdi, [s_var_tdelay]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_ms]
    call out_str
    jmp .done
.not_delay:
    cmp r12d, N_ANIM
    jne .not_animv
    lea rdi, [s_css_anim]
    call out_str
    lea r11, [anim_vals]
    mov rdi, [r11 + r13*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_animv:
    cmp r12d, N_TBEHAV
    jne .not_tbhv
    lea rdi, [s_css_tbehav]
    call out_str
    cmp r13d, 2
    jne .tbv_norm
    lea rdi, [s_v_allow_discrete]
    jmp .tbv_done
.tbv_norm:
    lea rdi, [s_v_normal]
.tbv_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_tbhv:
    cmp r12d, N_FAMILY
    jne .not_famv
    lea rdi, [s_css_family]
    call out_str
    lea r11, [fam_vals]
    mov rdi, [r11 + r13*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_famv:
    cmp r12d, N_STRETCH
    jne .not_strv
    lea rdi, [s_css_fstr]
    call out_str
    lea r11, [stretch_vals]
    mov rdi, [r11 + r13*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_strv:
    cmp r12d, N_VARNUM
    jne .not_vnv
    lea rdi, [s_css_varnum]
    call out_str
    lea r11, [varnum_vals]
    mov rdi, [r11 + r13*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_vnv:
    cmp r12d, N_SMOOTH
    jne .not_smv
    lea rdi, [s_css_smooth]
    call out_str
    cmp r13d, 2
    jne .smv_anti
    lea rdi, [s_v_subpixel]
    jmp .smv_done
.smv_anti:
    lea rdi, [s_v_antialiased]
.smv_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_smv:
    cmp r12d, N_TRACK
    jne .not_trkv
    lea rdi, [s_css_track]
    call out_str
    lea r11, [track_vals]
    mov rdi, [r11 + r13*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_trkv:
    cmp r12d, N_LEAD
    jne .not_ldv
    lea rdi, [s_css_lhp]
    call out_str
    lea r11, [lead_vals]
    mov rdi, [r11 + r13*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_ldv:
    cmp r12d, N_WS
    jne .not_wsv
    lea rdi, [s_css_ws]
    call out_str
    lea r11, [ws_vals]
    mov rdi, [r11 + r13*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_wsv:
    cmp r12d, N_WBREAK
    jne .not_wbv
    cmp r13d, 2
    je .wbv_ow
    cmp r13d, 5
    je .wbv_ow
    cmp r13d, 6
    je .wbv_ow
    cmp r13d, 7
    je .wbv_ow
    lea rdi, [s_css_wb]
    call out_str
    cmp r13d, 3
    je .wbv_all
    cmp r13d, 4
    je .wbv_keep
    lea rdi, [s_v_normal]
    jmp .wbv_done
.wbv_all:
    lea rdi, [s_v_break_all]
    jmp .wbv_done
.wbv_keep:
    lea rdi, [s_v_keep_all]
    jmp .wbv_done
.wbv_ow:
    lea rdi, [s_css_ow]
    call out_str
    cmp r13d, 7
    je .wbv_any
    cmp r13d, 5
    jne .wbv_bw
    lea rdi, [s_v_normal]
    jmp .wbv_done
.wbv_bw:
    lea rdi, [s_v_break_word]
    jmp .wbv_done
.wbv_any:
    lea rdi, [s_v_anywhere]
.wbv_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_wbv:
    cmp r12d, N_OVERFLOW
    jne .not_ovv
    cmp r13d, 3
    jne .ovv_notr
    lea rdi, [s_css_trunc]
    call out_str
    jmp .done
.ovv_notr:
    lea rdi, [s_css_ov]
    call out_str
    cmp r13d, 2
    jne .ovv_ell
    lea rdi, [s_v_clip]
    jmp .ovv_done
.ovv_ell:
    lea rdi, [s_v_ellipsis]
.ovv_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_ovv:
    cmp r12d, N_VALIGN
    jne .not_vav
    lea rdi, [s_css_valign]
    call out_str
    lea r11, [valign_vals]
    mov rdi, [r11 + r13*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_vav:
    cmp r12d, N_INDENT
    jne .not_indv
    lea rdi, [s_css_indent]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_css_px_semi]
    call out_str
    jmp .done
.not_indv:
    cmp r12d, N_DSTYLE
    jne .not_dstv
    lea rdi, [s_css_dstyle]
    call out_str
    lea r11, [dstyle_vals]
    mov rdi, [r11 + r13*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_dstv:
    cmp r12d, N_DTHICK
    jne .not_dthv
    lea rdi, [s_css_dthick]
    call out_str
    cmp r13d, 1
    je .dthv_auto
    cmp r13d, 2
    je .dthv_ff
    lea edi, [r13d - 2]
    call ssr_dec
    lea rdi, [s_css_px_semi]
    call out_str
    jmp .done
.dthv_auto:
    lea rdi, [s_v_auto]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.dthv_ff:
    lea rdi, [s_v_from_font]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_dthv:
    cmp r12d, N_DCOLOR
    jne .not_dclv
    lea rdi, [s_css_dcolor]
    call out_str
    mov rdi, r13
    call ssr_hex6
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_dclv:
    cmp r12d, N_UO
    jne .not_uov
    lea rdi, [s_css_uo]
    call out_str
    cmp r13d, 1
    je .uov_auto
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_css_px_semi]
    call out_str
    jmp .done
.uov_auto:
    lea rdi, [s_v_auto]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_uov:
    cmp r12d, N_CLAMP
    jne .not_clv
    lea rdi, [s_css_clamp1]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_css_clamp2]
    call out_str
    jmp .done
.not_clv:
    cmp r12d, N_LISTPOS
    jne .not_lspv
    lea rdi, [s_css_listpos]
    call out_str
    cmp r13d, 2
    jne .lspv_in
    lea rdi, [s_v_outside]
    jmp .lspv_done
.lspv_in:
    lea rdi, [s_v_inside]
.lspv_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_lspv:
    cmp r12d, N_LISTTYPE
    jne .not_lstv
    lea rdi, [s_css_listtype]
    call out_str
    cmp r13d, 2
    je .lstv_disc
    cmp r13d, 3
    je .lstv_dec
    lea rdi, [s_v_none]
    jmp .lstv_done
.lstv_disc:
    lea rdi, [s_v_disc]
    jmp .lstv_done
.lstv_dec:
    lea rdi, [s_v_decimal]
.lstv_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_lstv:
    cmp r12d, N_HYPHENS
    jne .not_hyv
    lea rdi, [s_css_hyphens]
    call out_str
    lea r11, [hyphens_vals]
    mov rdi, [r11 + r13*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_hyv:
    cmp r12d, N_TABSIZE
    jne .not_tbv2
    lea rdi, [s_css_tab]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_tbv2:
    cmp r12d, N_CONTENT
    jne .not_ctv
    lea rdi, [s_css_contn]
    call out_str
    jmp .done
.not_ctv:
    cmp r12d, N_TWRAP
    jne .not_twv
    lea rdi, [s_css_tw]
    call out_str
    lea r11, [tw_vals]
    mov rdi, [r11 + r13*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .done
.not_twv:
    cmp r12d, N_W
    jne .not_w
    lea rdi, [s_var_w]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_w:
    cmp r12d, N_GAP
    jne .not_gap
    lea rdi, [s_var_gap]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_gap:
    cmp r12d, N_RADIUS
    jne .not_rad
    cmp r13d, 255
    jne .rad_n
    lea rdi, [s_var_rad_full]
    call out_str
    jmp .done
.rad_n:
    lea rdi, [s_var_rad]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_px]
    call out_str
    jmp .done
.not_rad:
    cmp r12d, N_WEIGHT
    jne .not_fw
    lea rdi, [s_var_fw]
    call out_str
    mov rdi, r13
    call ssr_dec
    jmp .done
.not_fw:
    cmp r12d, N_ALIGN
    jne .not_align
    cmp r13d, 1
    je .al_c
    cmp r13d, 2
    je .al_r
    lea rdi, [s_var_ta_j]
    call out_str
    jmp .done
.al_c:
    lea rdi, [s_var_ta_c]
    call out_str
    jmp .done
.al_r:
    lea rdi, [s_var_ta_r]
    call out_str
    jmp .done
.not_align:
    cmp r12d, N_OPACITY
    jne .not_op
    lea rdi, [s_var_op]
    call out_str
    mov rdi, r13
    call ssr_dec
    jmp .done
.not_op:
    cmp r12d, N_GRID_COLS
    jne .not_gc
    lea rdi, [s_var_gcols]
    call out_str
    mov rdi, r13
    call ssr_dec
    lea rdi, [s_var_gcols2]
    call out_str
    jmp .done
.not_gc:
    cmp r12d, N_FLAGS
    jne .done
    ; flags: emit display:none / display:grid / display:flex + direction
    test r13d, F_HIDDEN
    jz .not_hid
    lea rdi, [s_var_hidden]
    call out_str
    jmp .done
.not_hid:
    test r13d, F_GRID
    jz .not_grd
    lea rdi, [s_var_grid]
    call out_str
    jmp .done
.not_grd:
    ; display (mutually exclusive): hidden/grid jump out, flex falls
    ; through so wrap/grow/items/justify still emit on the same rule
    test r13d, F_FLEX
    jz .not_flex
    lea rdi, [s_var_flex]
    call out_str
    test r13d, F_FLEXCOL
    jz .row
    lea rdi, [s_var_col]
    jmp .dir_call
.row:
    lea rdi, [s_var_row]
.dir_call:
    call out_str
    lea rdi, [s_css_semi]        ; flex falls through to wrap/grow/items
    call out_str
.not_flex:
    test r13d, F_WRAP
    jz .not_wrap
    lea rdi, [s_css_wrap]
    call out_str
.not_wrap:
    test r13d, F_GROW
    jz .not_grow
    lea rdi, [s_css_grow]
    call out_str
.not_grow:
    ; align-items (mutual - first match wins, then jump past the rest)
    test r13d, F_ITEMSC
    jz .not_items_c
    lea rdi, [s_css_items]
    call out_str
    lea rdi, [s_css_center]
    call out_str
    jmp .not_items
.not_items_c:
    test r13d, F_ITEMSE
    jz .not_items_e
    lea rdi, [s_css_items]
    call out_str
    lea rdi, [s_css_fe]
    call out_str
    jmp .not_items
.not_items_e:
    test r13d, F_ITEMSS
    jz .not_items_s
    lea rdi, [s_css_items]
    call out_str
    lea rdi, [s_css_fs]
    call out_str
    jmp .not_items
.not_items_s:
    test r13d, F_ITEMST
    jz .not_items
    lea rdi, [s_css_items]
    call out_str
    lea rdi, [s_css_stretch]
    call out_str
.not_items:
    ; justify-content (mutual)
    test r13d, F_JUSTC
    jz .not_just_c
    lea rdi, [s_var_just]
    call out_str
    lea rdi, [s_css_center]
    call out_str
    jmp .not_just
.not_just_c:
    test r13d, F_JUSTE
    jz .not_just_e
    lea rdi, [s_var_just]
    call out_str
    lea rdi, [s_css_fe]
    call out_str
    jmp .not_just
.not_just_e:
    test r13d, F_JUSTB
    jz .not_just_b
    lea rdi, [s_var_just]
    call out_str
    lea rdi, [s_css_sb]
    call out_str
    jmp .not_just
.not_just_b:
    test r13d, F_JUSTA
    jz .not_just_a
    lea rdi, [s_var_just]
    call out_str
    lea rdi, [s_css_sa]
    call out_str
    jmp .not_just
.not_just_a:
    test r13d, F_JUSTV
    jz .not_just
    lea rdi, [s_var_just]
    call out_str
    lea rdi, [s_css_sv]
    call out_str
.not_just:
    test r13d, F_BOLD
    jz .not_bold
    lea rdi, [s_css_fw]
    call out_str
    lea rdi, [s_css_700]
    call out_str
.not_bold:
    ; text-transform (mutual)
    test r13d, F_UPPER
    jz .not_upper
    lea rdi, [s_css_tt]
    call out_str
    jmp .not_tran
.not_upper:
    test r13d, F_LOWER
    jz .not_lower
    lea rdi, [s_css_lo]
    call out_str
    jmp .not_tran
.not_lower:
    test r13d, F_CAPITALIZE
    jz .not_cap
    lea rdi, [s_css_tcap]
    call out_str
    jmp .not_tran
.not_cap:
    test r13d, F_NORMALCASE
    jz .not_tran
    lea rdi, [s_css_tnc]
    call out_str
.not_tran:
    ; font-style (mutual)
    test r13d, F_ITALIC
    jz .not_ital
    lea rdi, [s_css_it]
    call out_str
    jmp .not_fstyle
.not_ital:
    test r13d, F_NOTITALIC
    jz .not_fstyle
    lea rdi, [s_css_ni]
    call out_str
.not_fstyle:
    ; text-decoration-line (mutual)
    test r13d, F_UNDER
    jz .not_und
    lea rdi, [s_css_un]
    call out_str
    jmp .done
.not_und:
    test r13d, F_LINE
    jz .not_line
    lea rdi, [s_css_ln]
    call out_str
    jmp .done
.not_line:
    test r13d, F_OVERLINE
    jz .not_ovl
    lea rdi, [s_css_ovl]
    call out_str
    jmp .done
.not_ovl:
    test r13d, F_NOUNDERLINE
    jz .done
    lea rdi, [s_css_nun]
    call out_str
.done:
    pop r13
    pop r12
    pop rbx
    ret
