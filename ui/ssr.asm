; =============================================================================
; ssr.asm - Server-Side Rendering of the widget tree (hydration support)
; =============================================================================
; The @ DSL block compiles to ONE IR (the serialized blob: 32B records +
; string pool). Two backends consume it:
;   - the WASM module (emit.asm/mainwat.asm + asx/wasm/*.wat) renders it
;     in the browser;
;   - THIS module renders it as static HTML at build time (the <label>_shell
;     the server sends). Same records, same inline CSS -> the browser can
;     HYDRATE the SSR DOM instead of rebuilding it.
;
; Every widget gets a stable data-asx-id (its record index, deterministic
; pre-order). The shell carries data-asx-root + data-asx-checksum (FNV-1a
; over the canonical IR: records with the text_ptr field skipped + strings
; in record order). The glue recomputes the same hash in the module
; (widgets.wat ssr_checksum) and compares: mismatch = divergence between the
; SSR DOM and the module -> diagnostic + client re-render.

; ssr_hash() -> rax = FNV-1a 32 over the canonical first-render IR:
;   for each record (32B): all bytes EXCEPT [16..20) (text_ptr differs
;   between the blob, relative offset, and the wasm, absolute address);
;   then for each record with text: the string bytes up to (not incl.) the 0.
; Must match wasm/widgets.wat ssr_checksum exactly.
ssr_hash:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, 0x811c9dc5       ; h
    ; ---- records ----
    xor r13, r13               ; rec idx
.rec_loop:
    cmp r13, [rec_count]
    jge .rec_done
    imul rax, r13, 32
    lea rbx, [blob_buf + rax + 24]
    xor r14, r14               ; byte idx
.rb_loop:
    cmp r14, 32
    jge .rb_done
    cmp r14, 16
    jb .rb_hash
    cmp r14, 20
    jb .rb_skip                ; skip text_ptr (offset vs wasm address)
.rb_hash:
    movzx edx, byte [rbx + r14]
    mov eax, r12d
    xor eax, edx
    imul eax, eax, 0x01000193
    mov r12d, eax
.rb_skip:
    inc r14
    jmp .rb_loop
.rb_done:
    inc r13
    jmp .rec_loop
.rec_done:
    ; ---- strings (record order) ----
    xor r13, r13
.str_loop:
    cmp r13, [rec_count]
    jge .done
    ; interpolated texts (dyn) are SKIPPED: the value is runtime data
    ; (ssr.state may override it server-side), not part of the canonical
    ; IR. The wasm skips them too (dyn flag in record byte 25).
    imul rax, r13, 12
    lea rcx, [rec_order + rax]
    mov edi, [rcx + 4]          ; node idx
    call dyn_find               ; clobbers rbx/rdi - r13 safe
    cmp rax, -1
    jne .str_next
    imul rax, r13, 32
    lea rbx, [blob_buf + rax + 24]
    mov eax, [rbx + 16]        ; text_offset
    test eax, eax
    jz .str_next
    lea rbx, [blob_buf + rax]
.sb_loop:
    movzx edx, byte [rbx]
    test edx, edx
    jz .str_next
    mov eax, r12d
    xor eax, edx
    imul eax, eax, 0x01000193
    mov r12d, eax
    inc rbx
    jmp .sb_loop
.str_next:
    inc r13
    jmp .str_loop
.done:
    mov eax, r12d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; ssr_emit_children - emits the nested widget HTML (one db line per node)
; into out_buf, using rec_order (pre-order, parent before child) + a stack
; of open views. Stable ids: the record index.
; ----------------------------------------------------------------------
ssr_emit_children:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov qword [ssr_top], 0
    xor r12, r12               ; rec idx
.loop:
    cmp r12, [rec_count]
    jge .done
    imul rax, r12, 12
    lea rcx, [rec_order + rax]
    mov r13d, [rcx + 8]        ; parent rec idx (-1 = root)
    ; close views until the top of the stack is this record's parent
.close_loop:
    cmp qword [ssr_top], 0
    je .closed
    mov rax, [ssr_top]
    dec rax
    mov r14, [ssr_stack + rax*8]
    cmp r14, r13
    je .closed
    lea rdi, [s_ssr_close]
    call out_str
    call ssr_nl
    dec qword [ssr_top]
    jmp .close_loop
.closed:
    ; a new root with a non-empty stack: close everything (multiple roots)
    cmp r13d, -1
    jne .have_parent
    cmp qword [ssr_top], 0
    je .have_parent
.cl_all:
    cmp qword [ssr_top], 0
    je .have_parent
    lea rdi, [s_ssr_close]
    call out_str
    call ssr_nl
    dec qword [ssr_top]
    jmp .cl_all
.have_parent:
    mov rdi, r12
    call ssr_open_node         ; rax = 1 if it opens a container (push)
    test rax, rax
    jz .next
    mov rax, [ssr_top]
    mov [ssr_stack + rax*8], r12
    inc qword [ssr_top]
.next:
    inc r12
    jmp .loop
.done:
.cl_last:
    cmp qword [ssr_top], 0
    je .fin
    lea rdi, [s_ssr_close]
    call out_str
    call ssr_nl
    dec qword [ssr_top]
    jmp .cl_last
.fin:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; ssr_open_node(rdi = rec idx) -> rax = 1 if a container (push to stack),
; 0 if self-contained (label/canvas). Emits the opening tag line.
; ----------------------------------------------------------------------
ssr_open_node:
    push rbx
    push r12
    push r13
    mov r12, rdi
    imul rax, r12, 32
    lea rbx, [blob_buf + rax + 24]
    movzx eax, byte [rbx]      ; type
    cmp eax, 1
    je .label
    cmp eax, 2
    je .canvas
    ; ---- view (div) ----
    lea rdi, [s_ssr_id1]       ; '<div data-asx-id="'
    call out_str
    mov rdi, r12
    call ssr_dec
    ; role (button view)? style record +11 == 1
    imul rax, r12, 16
    lea r13, [style_buf + rax]
    cmp byte [r13 + 11], 1
    jne .no_role
    lea rdi, [s_ssr_role]
    call out_str
.no_role:
    lea rdi, [s_ssr_sty]       ; '" style="'
    call out_str
    mov rdi, r12
    call ssr_css_view
    lea rdi, [s_ssr_gt]        ; '">'
    call out_str
    call ssr_nl
    mov rax, 1
    jmp .done
.label:
    ; ---- label (span) ----
    lea rdi, [s_ssr_span1]     ; '<span data-asx-id="'
    call out_str
    mov rdi, r12
    call ssr_dec
    lea rdi, [s_ssr_sty]
    call out_str
    mov rdi, r12
    call ssr_css_label
    lea rdi, [s_ssr_gt]
    call out_str
    mov eax, [rbx + 16]        ; text_offset
    test eax, eax
    jz .no_txt
    ; dyn text (interpolated state)? emit a SUBSTITUTION SLOT instead of
    ; the raw text: <prefix> 0x01 <state name> 0x02 <default> 0x03 <suffix>
    ; The server (asx_send_content) replaces <default> with the ssr.state
    ; value when set, or strips the markers otherwise.
    push r12
    push r13
    push r14
    imul rax, r12, 12
    lea rcx, [rec_order + rax]
    mov edi, [rcx + 4]          ; node idx
    call dyn_find
    pop r14
    pop r13
    pop r12
    cmp rax, -1
    je .tx_plain
    push r12
    push r13
    push r14
    push r15
    mov r14d, eax               ; dyn idx
    ; text: [blob_buf + off, off + len)
    mov eax, [rbx + 16]
    lea r13, [blob_buf + rax]
    mov rdi, r13
    call strlen
    mov r15, rax                ; total text len
    imul rax, r14, DYN_ENTRY
    lea rcx, [dyn_tab + rax]
    ; prefix
    mov esi, [rcx + D_PREFIX_LEN]
    mov rdi, r13
    call ssr_esc_text
    ; slot open (', 1, ')
    lea rdi, [s_ssr_slot1]
    call out_str
    ; state name (in_buf offset from state_tab)
    imul rax, r14, DYN_ENTRY
    lea rcx, [dyn_tab + rax]
    mov edi, [rcx + D_STATE]
    imul rax, rdi, STATE_ENTRY
    lea rax, [state_tab + rax]
    mov edi, [rax + S_NAME_PTR]
    mov esi, [rax + S_NAME_LEN]
    lea rdi, [in_buf + rdi]
    call out_bytes
    ; object field? the key is "state.field" (matches the set_<state>.<field>
    ; export the glue restores from the snapshot)
    imul rax, r14, DYN_ENTRY
    lea rcx, [dyn_tab + rax]
    mov eax, [rcx + D_FIELD]
    cmp eax, -1
    je .slot_field_done
    push r15
    mov al, '.'
    call out_byte               ; clobbers rcx - recompute the dyn entry
    ; field name: type -> fields -> field entry
    imul rax, r14, DYN_ENTRY
    lea rcx, [dyn_tab + rax]
    mov edi, [rcx + D_STATE]
    imul rax, rdi, STATE_ENTRY
    mov edi, [state_tab + rax + S_TYPE_IDX]
    imul rax, rdi, TYPE_ENTRY
    mov edi, [type_tab + rax + T_FIELDS_IDX]
    mov eax, [rcx + D_FIELD]
    imul rax, rax, FIELD_ENTRY
    lea rax, [field_tab + rdi + rax]
    mov edi, [rax + F_NAME_PTR]
    mov esi, [rax + F_NAME_LEN]
    lea rdi, [in_buf + rdi]
    call out_bytes
    pop r15
.slot_field_done:
    ; slot sep (', 2, ')
    lea rdi, [s_ssr_slot2]
    call out_str
    ; default value: text[D_PREFIX_LEN .. len - D_SUFFIX_LEN)
    imul rax, r14, DYN_ENTRY
    lea rcx, [dyn_tab + rax]
    mov edx, [rcx + D_PREFIX_LEN]
    mov r8d, [rcx + D_SUFFIX_LEN]
    lea rdi, [r13 + rdx]
    mov rsi, r15
    sub rsi, rdx
    sub rsi, r8
    call ssr_esc_text
    ; slot close (', 3, ')
    lea rdi, [s_ssr_slot3]
    call out_str
    ; suffix: text[len - D_SUFFIX_LEN .. len)
    imul rax, r14, DYN_ENTRY
    lea rcx, [dyn_tab + rax]
    mov edx, [rcx + D_SUFFIX_LEN]
    mov rdi, r15
    sub rdi, rdx
    add rdi, r13
    mov rsi, rdx
    call ssr_esc_text
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .no_txt
.tx_plain:
    mov eax, [rbx + 16]        ; text_offset (dyn_find clobbered rax)
    lea rdi, [blob_buf + rax]
    mov rsi, rdi
.tx:
    cmp byte [rsi], 0
    je .txd
    inc rsi
    jmp .tx
.txd:
    sub rsi, rdi
    call ssr_esc_text
.no_txt:
    lea rdi, [s_ssr_span2]     ; '</span>'
    call out_str
    call ssr_nl
    xor rax, rax
    jmp .done
.canvas:
    ; ---- canvas ----
    lea rdi, [s_ssr_cv1]       ; '<canvas data-asx-id="'
    call out_str
    mov rdi, r12
    call ssr_dec
    lea rdi, [s_ssr_cv_w]      ; '" width="'
    call out_str
    movzx edi, word [rbx + 6]
    call ssr_dec
    lea rdi, [s_ssr_cv_h]      ; '" height="'
    call out_str
    movzx edi, word [rbx + 8]
    call ssr_dec
    lea rdi, [s_ssr_sty]
    call out_str
    mov rdi, r12
    call ssr_css_canvas
    lea rdi, [s_ssr_cv2]       ; '"></canvas>'
    call out_str
    call ssr_nl
    xor rax, rax
.done:
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; ssr_css_view(rdi = rec idx) - emits the inline CSS body for a view.
; Mirrors the glue's view cssText builder (wasm/glue.asm).
; ----------------------------------------------------------------------
ssr_css_view:
    push rbx
    push r12
    push r13
    mov r12, rdi
    imul rax, r12, 32
    lea rbx, [blob_buf + rax + 24]   ; 32B record
    imul rax, r12, 20
    lea r13, [style_buf + rax]       ; 20B style record
    ; hidden? display:none wins over everything (no flex/grid emit)
    mov eax, [r13]
    test eax, F_HIDDEN
    jz .not_hidden
    lea rdi, [s_css_hidden]
    call out_str
    jmp .done_css
.not_hidden:
    mov eax, [r13]
    ; grid? display:grid + grid-template-columns:repeat(N,1fr), then the
    ; shared props (bg/pad/gap/...) - no flex-direction/align/justify
    test eax, F_GRID
    jz .not_grid
    lea rdi, [s_css_grid]
    call out_str
    movzx edi, byte [r13 + 19]
    test edi, edi
    jz .no_gridc
    lea rdi, [s_css_grid_cols]
    call out_str
    movzx edi, byte [r13 + 19]
    call ssr_dec
    lea rdi, [s_css_grid_cols2]
    call out_str
.no_gridc:
    jmp .grid_skip
.not_grid:
    ; flex-direction: flags&1 ? (flags&2 ? column : row) : column
    lea rdi, [s_css_v_base]
    call out_str
    mov eax, [r13]
    test eax, F_FLEX
    jz .col
    test eax, F_FLEXCOL
    jz .row
.col:
    lea rdi, [s_css_col]
    jmp .dir_done
.row:
    lea rdi, [s_css_row]
.dir_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    ; flex-wrap
    mov eax, [r13]
    test eax, F_WRAP
    jz .no_wrap
    lea rdi, [s_css_wrap]
    call out_str
.no_wrap:
    ; flex-grow (flex-1)
    mov eax, [r13]
    test eax, F_GROW
    jz .no_grow
    lea rdi, [s_css_grow]
    call out_str
.no_grow:
    ; align-items: default stretch (CSS canonical - equalizes sibling
    ; heights in a row, e.g. cards); items-start is the explicit flex-start
    lea rdi, [s_css_items]
    call out_str
    mov eax, [r13]
    test eax, F_ITEMSC
    jnz .items_c
    test eax, F_ITEMSE
    jnz .items_e
    test eax, F_ITEMST
    jnz .items_s
    test eax, F_ITEMSS
    jnz .items_start
    lea rdi, [s_css_stretch]
    jmp .items_done
.items_c:
    lea rdi, [s_css_center]
    jmp .items_done
.items_e:
    lea rdi, [s_css_fe]
    jmp .items_done
.items_s:
    lea rdi, [s_css_stretch]
    jmp .items_done
.items_start:
    lea rdi, [s_css_fs]
.items_done:
    call out_str
    ; justify-content
    lea rdi, [s_css_just]
    call out_str
    mov eax, [r13]
    test eax, F_JUSTC
    jnz .just_c
    test eax, F_JUSTB
    jnz .just_b
    test eax, F_JUSTE
    jnz .just_e
    test eax, F_JUSTA
    jnz .just_a
    test eax, F_JUSTV
    jnz .just_v
    lea rdi, [s_css_fs]
    jmp .just_done
.just_c:
    lea rdi, [s_css_center]
    jmp .just_done
.just_b:
    lea rdi, [s_css_sb]
    jmp .just_done
.just_e:
    lea rdi, [s_css_fe]
    jmp .just_done
.just_a:
    lea rdi, [s_css_sa]
    jmp .just_done
.just_v:
    lea rdi, [s_css_sv]
.just_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.grid_skip:
    ; background: only when the record is opaque (alpha != 0)
    movzx eax, byte [rbx + 15]
    test eax, eax
    jz .no_bg
    lea rdi, [s_css_bg]
    call out_str
    movzx edi, byte [rbx + 12]
    call ssr_hex2
    movzx edi, byte [rbx + 13]
    call ssr_hex2
    movzx edi, byte [rbx + 14]
    call ssr_hex2
    lea rdi, [s_css_semi]
    call out_str
.no_bg:
    ; padding: (px||pad) ? "padding:" + (py||pad) + "px " + (px||pad) + "px;"
    movzx eax, byte [r13 + 9]    ; px
    test eax, eax
    jnz .have_px
    movzx eax, byte [r13 + 15]   ; pad
.have_px:
    test eax, eax
    jz .no_pad
    lea rdi, [s_css_pad]
    call out_str
    movzx edi, byte [r13 + 10]   ; py
    test edi, edi
    jnz .have_py
    movzx edi, byte [r13 + 15]
.have_py:
    call ssr_dec
    lea rdi, [s_css_px_sp]
    call out_str
    movzx edi, byte [r13 + 9]
    test edi, edi
    jnz .have_px2
    movzx edi, byte [r13 + 15]
.have_px2:
    call ssr_dec
    lea rdi, [s_css_px_semi]
    call out_str
.no_pad:
    ; gap
    movzx eax, byte [r13 + 7]
    test eax, eax
    jz .no_gap
    lea rdi, [s_css_gap]
    call out_str
    movzx edi, byte [r13 + 7]
    call ssr_dec
    lea rdi, [s_css_px_semi]
    call out_str
.no_gap:
    ; margin: (mt||mb)
    movzx eax, byte [r13 + 16]   ; mt
    movzx ecx, byte [r13 + 17]   ; mb
    test eax, eax
    jnz .have_mg
    test ecx, ecx
    jz .no_mg
.have_mg:
    lea rdi, [s_css_mg]
    call out_str
    movzx edi, byte [r13 + 16]
    call ssr_dec
    lea rdi, [s_css_px0]
    call out_str
    movzx edi, byte [r13 + 17]
    call ssr_dec
    lea rdi, [s_css_px_semi]
    call out_str
.no_mg:
    ; radius
    movzx eax, byte [r13 + 8]
    test eax, eax
    jz .no_rad
    cmp eax, 255
    jne .rad_n
    lea rdi, [s_css_rad_full]
    call out_str
    jmp .no_rad
.rad_n:
    lea rdi, [s_css_rad]
    call out_str
    movzx edi, byte [r13 + 8]
    call ssr_dec
    lea rdi, [s_css_px_semi]
    call out_str
.no_rad:
    ; border
    movzx eax, byte [r13 + 11]
    test eax, eax
    jz .no_bd
    lea rdi, [s_css_bd1]
    call out_str
    movzx edi, byte [r13 + 11]
    call ssr_dec
    lea rdi, [s_css_bd2]
    call out_str
.no_bd:
    ; opacity (0-100 -> "0.XX" / "1")
    movzx eax, byte [r13 + 12]
    test eax, eax
    jz .no_op
    lea rdi, [s_css_op]
    call out_str
    cmp eax, 100
    jne .op_frac
    lea rdi, [s_css_one]
    call out_str
    jmp .no_op
.op_frac:
    lea rdi, [s_css_zero_dot]
    call out_str
    cmp eax, 10
    jge .op_2d
    lea rdi, [s_css_zero]
    call out_str
.op_2d:
    movzx edi, al
    call ssr_dec
    lea rdi, [s_css_semi]
    call out_str
.no_op:
    ; shadow
    movzx eax, byte [r13 + 13]
    test eax, eax
    jz .no_sh
    lea rdi, [s_css_sh]
    call out_str
.no_sh:
    ; width: (w && w < 720) ? "width:Npx;" : role ? auto : 100%
    movzx eax, word [rbx + 6]
    test eax, eax
    jz .ww_auto
    cmp eax, 720
    jge .ww_auto
    lea rdi, [s_css_w]
    call out_str
    movzx edi, word [rbx + 6]
    call ssr_dec
    lea rdi, [s_css_px_semi]
    call out_str
    jmp .ww_done
.ww_auto:
    cmp byte [r13 + 14], 1
    jne .ww_stretch
    lea rdi, [s_css_btn]
    call out_str
    jmp .ww_done
.ww_stretch:
    lea rdi, [s_css_100]
    call out_str
.ww_done:
    ; min-height (h-*)
    movzx eax, byte [r13 + 18]
    test eax, eax
    jz .no_hh
    lea rdi, [s_css_mh]
    call out_str
    movzx edi, byte [r13 + 18]
    call ssr_dec
    lea rdi, [s_css_px_semi]
    call out_str
.no_hh:
.done_css:
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; ssr_css_label(rdi = rec idx) - inline CSS for a text widget (span).
; ----------------------------------------------------------------------
ssr_css_label:
    push rbx
    push r12
    push r13
    mov r12, rdi
    imul rax, r12, 32
    lea rbx, [blob_buf + rax + 24]
    imul rax, r12, 20
    lea r13, [style_buf + rax]
    lea rdi, [s_css_l_base]      ; "display:block;font-size:"
    call out_str
    movzx edi, byte [rbx + 24]   ; fs
    test edi, edi
    jnz .have_fs
    mov edi, 13
.have_fs:
    call ssr_dec
    lea rdi, [s_css_l_col]       ; "px;color:#"
    call out_str
    movzx edi, byte [rbx + 12]
    call ssr_hex2
    movzx edi, byte [rbx + 13]
    call ssr_hex2
    movzx edi, byte [rbx + 14]
    call ssr_hex2
    lea rdi, [s_css_semi]
    call out_str
    ; font-weight (u16 - 100..900 fits)
    movzx eax, word [r13 + 4]
    test eax, eax
    jz .no_fw
    lea rdi, [s_css_fw]
    call out_str
    movzx edi, word [r13 + 4]
    call ssr_dec
    lea rdi, [s_css_semi]
    call out_str
.no_fw:
    ; text-align
    movzx eax, byte [r13 + 6]
    cmp eax, 1
    je .ta_c
    cmp eax, 2
    je .ta_r
    cmp eax, 3
    je .ta_j
    jmp .no_ta
.ta_c:
    lea rdi, [s_css_ta_c]
    jmp .ta_done
.ta_r:
    lea rdi, [s_css_ta_r]
    jmp .ta_done
.ta_j:
    lea rdi, [s_css_ta_j]
.ta_done:
    call out_str
.no_ta:
    ; uppercase / lowercase / italic / underline / line-through
    mov eax, [r13]
    test eax, F_UPPER
    jz .no_tt
    lea rdi, [s_css_tt]
    call out_str
.no_tt:
    mov eax, [r13]
    test eax, F_LOWER
    jz .no_lo
    lea rdi, [s_css_lo]
    call out_str
.no_lo:
    mov eax, [r13]
    test eax, F_ITALIC
    jz .no_it
    lea rdi, [s_css_it]
    call out_str
.no_it:
    mov eax, [r13]
    test eax, F_UNDER
    jz .no_un
    lea rdi, [s_css_un]
    call out_str
.no_un:
    mov eax, [r13]
    test eax, F_LINE
    jz .no_ln
    lea rdi, [s_css_ln]
    call out_str
.no_ln:
    lea rdi, [s_css_lh]          ; "line-height:1.4;"
    call out_str
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; ssr_css_canvas(rdi = rec idx) - inline CSS for a canvas widget.
; ----------------------------------------------------------------------
ssr_css_canvas:
    push rbx
    push r12
    mov r12, rdi
    imul rax, r12, 32
    lea rbx, [blob_buf + rax + 24]
    lea rdi, [s_css_cv_base]     ; "display:block;width:"
    call out_str
    movzx edi, word [rbx + 6]
    call ssr_dec
    lea rdi, [s_css_px_semi]
    call out_str
    lea rdi, [s_css_cv_h]        ; "height:"
    call out_str
    movzx edi, word [rbx + 8]
    call ssr_dec
    lea rdi, [s_css_cv_end]
    call out_str
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; ssr_esc_text(rdi = ptr, rsi = len) - text with HTML escapes so it is
; safe inside the db '...' literal AND in the rendered page: & < > " '
; ----------------------------------------------------------------------
ssr_esc_text:
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
    cmp al, '&'
    je .amp
    cmp al, '<'
    je .lt
    cmp al, '>'
    je .gt
    cmp al, '"'
    je .quot
    cmp al, 39
    je .apos
    call out_byte
    jmp .next
.amp:
    lea rdi, [s_esc_amp]
    jmp .esc
.lt:
    lea rdi, [s_esc_lt]
    jmp .esc
.gt:
    lea rdi, [s_esc_gt]
    jmp .esc
.quot:
    lea rdi, [s_esc_quot]
    jmp .esc
.apos:
    lea rdi, [s_esc_apos]
.esc:
    call out_str
.next:
    inc r13
    jmp .loop
.done:
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; ssr_nl - closes the current db line and opens the next one, following
; the existing shell literal style: ' + ', 10 + newline + "          db '"
; ----------------------------------------------------------------------
ssr_nl:
    mov al, 39
    call out_byte
    lea rdi, [s_sh4]
    call out_str
    lea rdi, [s_sh5]
    call out_str
    mov al, 39
    call out_byte
    ret

; ----------------------------------------------------------------------
; ssr_dec(rdi = val) - decimal to out_buf
; ----------------------------------------------------------------------
ssr_dec:
    push r12
    mov r12, rdi
    lea rsi, [itoa_buf]
    call itoa
    mov rdi, rax
    call out_str
    pop r12
    ret

; ----------------------------------------------------------------------
; ssr_hex8(rdi = u32) - 8 lowercase hex digits to out_buf
; ssr_hex6(rdi = u32) - 6 lowercase hex digits (0xRRGGBB theme colors)
; ssr_hex2(rdi = 0..255) - 2 lowercase hex digits
; ----------------------------------------------------------------------
ssr_hex8:
    push r12
    mov r12, rdi
    mov rdi, r12
    shr rdi, 28
    call ssr_hex_nib
    mov rdi, r12
    shr rdi, 24
    call ssr_hex_nib
    mov rdi, r12
    shr rdi, 20
    call ssr_hex_nib
    mov rdi, r12
    shr rdi, 16
    call ssr_hex_nib
    mov rdi, r12
    shr rdi, 12
    call ssr_hex_nib
    mov rdi, r12
    shr rdi, 8
    call ssr_hex_nib
    mov rdi, r12
    shr rdi, 4
    call ssr_hex_nib
    mov rdi, r12
    call ssr_hex_nib
    pop r12
    ret

ssr_hex6:
    push r12
    mov r12, rdi
    mov rdi, r12
    shr rdi, 20
    call ssr_hex_nib
    mov rdi, r12
    shr rdi, 16
    call ssr_hex_nib
    mov rdi, r12
    shr rdi, 12
    call ssr_hex_nib
    mov rdi, r12
    shr rdi, 8
    call ssr_hex_nib
    mov rdi, r12
    shr rdi, 4
    call ssr_hex_nib
    mov rdi, r12
    call ssr_hex_nib
    pop r12
    ret

ssr_hex2:
    push r12
    mov r12, rdi
    mov rdi, r12
    shr rdi, 4
    call ssr_hex_nib
    mov rdi, r12
    call ssr_hex_nib
    pop r12
    ret

; ssr_hex_nib(rdi = 0..15) - one lowercase hex digit
ssr_hex_nib:
    and edi, 0x0f
    cmp edi, 10
    jl .digit
    add edi, 'a' - 10
    jmp .emit
.digit:
    add edi, '0'
.emit:
    mov al, dil
    jmp out_byte
