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
    cmp r14, 26
    jb .rb_hash
    cmp r14, 30
    jb .rb_skip                ; skip attr_ptr (offset vs wasm address)
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
    mov rdi, r14
    call ssr_tag_close          ; '</tag>' (real html tag)
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
    mov rax, [ssr_top]
    dec rax
    mov rdi, [ssr_stack + rax*8]
    call ssr_tag_close
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
    mov rax, [ssr_top]
    dec rax
    mov rdi, [ssr_stack + rax*8]
    call ssr_tag_close
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
; 0 if self-contained (label/canvas). Emits the opening tag line with the
; REAL html tag (record byte 1 -> tag_names) + its attributes.
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
    ; ---- view ----
    call ssr_tag_open           ; '<tag data-asx-id="N"[role][attrs]'
    lea rdi, [s_ssr_sty]       ; ' style="'
    call out_str
    mov rdi, r12
    call ssr_css_view
    lea rdi, [s_ssr_gt]        ; '">'
    call out_str
    call ssr_nl
    mov rax, 1
    jmp .done
.label:
    ; ---- label ----
    call ssr_tag_open
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
    mov rdi, r12
    call ssr_tag_close          ; '</tag>'
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
; ssr_tag_open - emits the dynamic tag open prefix for the record in
; rbx: '<tag data-asx-id="N"' + [role] + [attrs] (no style yet; the
; caller emits ' style="' + css + '">'). r12 = rec idx, rbx = 32B record.
; void elements (img/br/hr/input/...) are emitted by the CALLER with no
; closing tag - ssr_open_node returns 0 for them (no stack push).
; ----------------------------------------------------------------------
ssr_tag_open:
    push rbx
    push r12
    push r13
    push r14
    ; '<'
    lea rdi, [s_ssr_lt]
    call out_str
    ; tag name from tag_names[id]
    movzx eax, byte [rbx + 1]   ; tag id (record byte 1)
    mov rax, [tag_names + rax*8]
    mov rdi, rax
    call out_str
    ; ' data-asx-id="'
    lea rdi, [s_ssr_ida]
    call out_str
    mov rdi, r12
    call ssr_dec
    ; '"'
    lea rdi, [s_ssr_idc]
    call out_str
    ; role (button view)? style record +14 == 1
    imul rax, r12, STYLE_REC
    lea r13, [style_buf + rax]
    cmp byte [r13 + 14], 1
    jne .to_no_role
    lea rdi, [s_ssr_role]
    call out_str
.to_no_role:
    ; attributes: 'name="value"' string in the pool (record bytes
    ; 26..29 = blob-relative offset; 0 = none). A leading space
    ; separates them from the id/role attributes.
    mov eax, [rbx + 26]
    test eax, eax
    jz .to_no_attr
    mov r14d, eax               ; attr offset (out_byte clobbers rax)
    mov al, ' '
    call out_byte
    lea rdi, [blob_buf + r14]
    call out_str
.to_no_attr:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; ssr_tag_close(rdi = rec idx) - emits '</tag>' with the record's real
; html tag name (record byte 1 -> tag_names).
; ----------------------------------------------------------------------
ssr_tag_close:
    push rbx
    push r12
    mov r12, rdi
    imul rax, r12, 32
    lea rbx, [blob_buf + rax + 24]
    lea rdi, [s_ssr_close2]     ; '</'
    call out_str
    movzx eax, byte [rbx + 1]   ; tag id
    mov rax, [tag_names + rax*8]
    mov rdi, rax
    call out_str
    lea rdi, [s_ssr_close3]     ; '>'
    call out_str
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
    imul rax, r12, STYLE_REC
    lea r13, [style_buf + rax]       ; style record
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
    ; padding: if any axis-specific field (pl/pr/pt/pb) is set, emit the
    ; full 4-value form (each axis: specific > px/py > pad); otherwise
    ; the legacy 2-value form (py||pad, px||pad)
    movzx eax, byte [r13 + 22]   ; pl
    movzx ecx, byte [r13 + 23]   ; pr
    or eax, ecx
    movzx ecx, byte [r13 + 24]   ; pt
    or eax, ecx
    movzx ecx, byte [r13 + 25]   ; pb
    or eax, ecx
    jnz .pad4
    ; px-*/p-* 2-value form
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
    jmp .no_pad
.pad4:
    ; top = pt || py || pad (r10), right = pr || px || pad (r11);
    ; bottom and left computed at emit time (edi). rbx is the blob
    ; record ptr here - NEVER clobber it.
    movzx r10d, byte [r13 + 24]
    test r10d, r10d
    jnz .pad_top
    movzx r10d, byte [r13 + 10]
    test r10d, r10d
    jnz .pad_top
    movzx r10d, byte [r13 + 15]
.pad_top:
    movzx r11d, byte [r13 + 23]
    test r11d, r11d
    jnz .pad_right
    movzx r11d, byte [r13 + 9]
    test r11d, r11d
    jnz .pad_right
    movzx r11d, byte [r13 + 15]
.pad_right:
    lea rdi, [s_css_pad]
    call out_str
    mov edi, r10d
    call ssr_dec
    lea rdi, [s_css_px_sp]
    call out_str
    mov edi, r11d
    call ssr_dec
    lea rdi, [s_css_px_sp]
    call out_str
    ; bottom = pb || py || pad
    movzx edi, byte [r13 + 25]
    test edi, edi
    jnz .pad_bottom
    movzx edi, byte [r13 + 10]
    test edi, edi
    jnz .pad_bottom
    movzx edi, byte [r13 + 15]
.pad_bottom:
    call ssr_dec
    lea rdi, [s_css_px_sp]
    call out_str
    ; left = pl || px || pad
    movzx edi, byte [r13 + 22]
    test edi, edi
    jnz .pad_left
    movzx edi, byte [r13 + 9]
    test edi, edi
    jnz .pad_left
    movzx edi, byte [r13 + 15]
.pad_left:
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
    ; margin: ml||mr forces the 4-value form (mt mr mb ml), else the
    ; legacy (mt||mb) ? "margin:mt 0 mb;"
    movzx eax, byte [r13 + 20]   ; ml
    movzx ecx, byte [r13 + 21]   ; mr
    or eax, ecx
    jnz .mg4
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
    jmp .no_mg
.mg4:
    lea rdi, [s_css_mg]
    call out_str
    movzx edi, byte [r13 + 16]
    call ssr_dec
    lea rdi, [s_css_px_sp]
    call out_str
    movzx edi, byte [r13 + 21]
    call ssr_dec
    lea rdi, [s_css_px_sp]
    call out_str
    movzx edi, byte [r13 + 17]
    call ssr_dec
    lea rdi, [s_css_px_sp]
    call out_str
    movzx edi, byte [r13 + 20]
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
    ; transitions: property + duration (explicit or 150 default) + timing
    ; (explicit or default bezier) + optional delay
    movzx r10d, byte [r13 + 26]  ; trans (out_str zeroes al - keep in r10)
    test r10d, r10d
    jz .no_trans
    lea rdi, [s_css_tprop]
    call out_str
    cmp r10d, 2
    je .tp_none
    cmp r10d, 3
    je .tp_all
    cmp r10d, 4
    je .tp_colors
    cmp r10d, 5
    je .tp_opacity
    cmp r10d, 6
    je .tp_shadow
    cmp r10d, 7
    je .tp_transform
    lea rdi, [s_tp_default]
    jmp .tp_done
.tp_none:
    lea rdi, [s_tp_none]
    jmp .tp_done
.tp_all:
    lea rdi, [s_tp_all]
    jmp .tp_done
.tp_colors:
    lea rdi, [s_tp_colors]
    jmp .tp_done
.tp_opacity:
    lea rdi, [s_tp_opacity]
    jmp .tp_done
.tp_shadow:
    lea rdi, [s_tp_shadow]
    jmp .tp_done
.tp_transform:
    lea rdi, [s_tp_transform]
.tp_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    ; transition-none emits ONLY the property (v4 semantics)
    cmp r10d, 2
    je .no_trans
    lea rdi, [s_css_tdur]
    call out_str
    movzx edi, word [r13 + 28]
    test edi, edi
    jnz .have_dur
    mov edi, 150
.have_dur:
    call ssr_dec
    lea rdi, [s_css_ms]
    call out_str
    lea rdi, [s_css_tfn]
    call out_str
    movzx eax, byte [r13 + 27]   ; ease
    cmp eax, 1
    je .ease_lin
    cmp eax, 2
    je .ease_in
    cmp eax, 3
    je .ease_out
    cmp eax, 4
    je .ease_io
    lea rdi, [s_ease_inout]
    jmp .ease_done
.ease_lin:
    lea rdi, [s_ease_linear]
    jmp .ease_done
.ease_in:
    lea rdi, [s_ease_in]
    jmp .ease_done
.ease_out:
    lea rdi, [s_ease_out]
    jmp .ease_done
.ease_io:
    lea rdi, [s_ease_inout]
.ease_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    movzx eax, word [r13 + 30]   ; delay
    test eax, eax
    jz .no_trans
    lea rdi, [s_css_tdelay]
    call out_str
    movzx edi, word [r13 + 30]
    call ssr_dec
    lea rdi, [s_css_ms]
    call out_str
.no_trans:
    ; transition-behavior (r13+33: 1 normal 2 allow-discrete)
    movzx r10d, byte [r13 + 33]
    test r10d, r10d
    jz .no_tbh
    lea rdi, [s_css_tbehav]
    call out_str
    cmp r10d, 2
    jne .tbh_norm
    lea rdi, [s_v_allow_discrete]
    jmp .tbh_done
.tbh_norm:
    lea rdi, [s_v_normal]
.tbh_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_tbh:
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
    ; list-style-position (r13+52) / list-style-type (r13+53) - inherit
    ; to the li children
    movzx r10d, byte [r13 + 52]
    test r10d, r10d
    jz .no_lsp
    lea rdi, [s_css_listpos]
    call out_str
    cmp r10d, 2
    jne .lsp_in
    lea rdi, [s_v_outside]
    jmp .lsp_done
.lsp_in:
    lea rdi, [s_v_inside]
.lsp_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_lsp:
    movzx r10d, byte [r13 + 53]
    test r10d, r10d
    jz .no_lst
    lea rdi, [s_css_listtype]
    call out_str
    cmp r10d, 2
    je .lst_disc
    cmp r10d, 3
    je .lst_dec
    lea rdi, [s_v_none]
    jmp .lst_done
.lst_disc:
    lea rdi, [s_v_disc]
    jmp .lst_done
.lst_dec:
    lea rdi, [s_v_decimal]
.lst_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_lst:
    ; animation (r13+32, table anim_vals)
    movzx r10d, byte [r13 + 32]
    test r10d, r10d
    jz .no_animv
    lea rdi, [s_css_anim]
    call out_str
    lea r11, [anim_vals]
    mov rdi, [r11 + r10*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_animv:
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
    imul rax, r12, STYLE_REC
    lea r13, [style_buf + rax]
    ; display: line-clamp needs the -webkit-box box model, otherwise block
    movzx r10d, byte [r13 + 51]  ; clamp
    test r10d, r10d
    jz .lbl_block
    lea rdi, [s_css_boxv]        ; "display:-webkit-box;-webkit-box-orient:vertical;"
    call out_str
    lea rdi, [s_css_fs2]         ; "font-size:"
    call out_str
    jmp .lbl_fs
.lbl_block:
    lea rdi, [s_css_l_base]      ; "display:block;font-size:"
    call out_str
.lbl_fs:
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
    ; font-family (r13+34: 1 sans 2 serif 3 mono)
    movzx r10d, byte [r13 + 34]
    test r10d, r10d
    jz .no_fam
    lea rdi, [s_css_family]
    call out_str
    cmp r10d, 2
    je .fam_serif
    cmp r10d, 3
    je .fam_mono
    lea rdi, [s_fam_sans]
    jmp .fam_done
.fam_serif:
    lea rdi, [s_fam_serif]
    jmp .fam_done
.fam_mono:
    lea rdi, [s_fam_mono]
.fam_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_fam:
    ; font-stretch (r13+35, table stretch_vals)
    movzx r10d, byte [r13 + 35]
    test r10d, r10d
    jz .no_str
    lea rdi, [s_css_fstr]
    call out_str
    lea r11, [stretch_vals]
    mov rdi, [r11 + r10*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_str:
    ; font-variant-numeric (r13+36, table varnum_vals)
    movzx r10d, byte [r13 + 36]
    test r10d, r10d
    jz .no_vn
    lea rdi, [s_css_varnum]
    call out_str
    lea r11, [varnum_vals]
    mov rdi, [r11 + r10*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_vn:
    ; font-smoothing (r13+58: 1 antialiased 2 subpixel)
    movzx r10d, byte [r13 + 58]
    test r10d, r10d
    jz .no_sm
    lea rdi, [s_css_smooth]
    call out_str
    cmp r10d, 2
    jne .sm_anti
    lea rdi, [s_v_subpixel]      ; "auto"
    jmp .sm_done
.sm_anti:
    lea rdi, [s_v_antialiased]
.sm_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_sm:
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
    ; letter-spacing (r13+37, table track_vals)
    movzx r10d, byte [r13 + 37]
    test r10d, r10d
    jz .no_tr
    lea rdi, [s_css_track]
    call out_str
    lea r11, [track_vals]
    mov rdi, [r11 + r10*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_tr:
    ; text-align (1 center 2 right 3 justify 4 start 5 end)
    movzx eax, byte [r13 + 6]
    cmp eax, 1
    je .ta_c
    cmp eax, 2
    je .ta_r
    cmp eax, 3
    je .ta_j
    cmp eax, 4
    je .ta_s
    cmp eax, 5
    je .ta_e
    jmp .no_ta
.ta_c:
    lea rdi, [s_css_ta_c]
    jmp .ta_done
.ta_r:
    lea rdi, [s_css_ta_r]
    jmp .ta_done
.ta_j:
    lea rdi, [s_css_ta_j]
    jmp .ta_done
.ta_s:
    lea rdi, [s_css_ta_s]
    jmp .ta_done
.ta_e:
    lea rdi, [s_css_ta_e]
.ta_done:
    call out_str
.no_ta:
    ; text-transform: uppercase > lowercase > capitalize > normal-case
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
    test eax, F_CAPITALIZE
    jz .no_cap
    lea rdi, [s_css_tcap]
    call out_str
.no_cap:
    mov eax, [r13]
    test eax, F_NORMALCASE
    jz .no_ncase
    lea rdi, [s_css_tnc]
    call out_str
.no_ncase:
    ; font-style: italic > not-italic
    mov eax, [r13]
    test eax, F_ITALIC
    jz .no_it
    lea rdi, [s_css_it]
    call out_str
    jmp .no_notit
.no_it:
    mov eax, [r13]
    test eax, F_NOTITALIC
    jz .no_notit
    lea rdi, [s_css_ni]
    call out_str
.no_notit:
    ; text-decoration-line: underline > line-through > overline > none
    mov eax, [r13]
    test eax, F_UNDER
    jz .no_un
    lea rdi, [s_css_un]
    call out_str
    jmp .no_nund
.no_un:
    mov eax, [r13]
    test eax, F_LINE
    jz .no_ln
    lea rdi, [s_css_ln]
    call out_str
    jmp .no_nund
.no_ln:
    mov eax, [r13]
    test eax, F_OVERLINE
    jz .no_ovl
    lea rdi, [s_css_ovl]
    call out_str
    jmp .no_nund
.no_ovl:
    mov eax, [r13]
    test eax, F_NOUNDERLINE
    jz .no_nund
    lea rdi, [s_css_nun]
    call out_str
.no_nund:
    ; text-decoration-color (r13+46 u32, 0xFFFFFFFF = none)
    mov r10d, [r13 + 46]
    cmp r10d, -1
    je .no_dcol
    lea rdi, [s_css_dcolor]
    call out_str
    mov edi, r10d
    call ssr_hex6
    lea rdi, [s_css_semi]
    call out_str
.no_dcol:
    ; text-decoration-style (r13+44, table dstyle_vals)
    movzx r10d, byte [r13 + 44]
    test r10d, r10d
    jz .no_dst
    lea rdi, [s_css_dstyle]
    call out_str
    lea r11, [dstyle_vals]
    mov rdi, [r11 + r10*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_dst:
    ; text-decoration-thickness (r13+45: 1 auto 2 from-font 3+ = px-2)
    movzx r10d, byte [r13 + 45]
    test r10d, r10d
    jz .no_dth
    lea rdi, [s_css_dthick]
    call out_str
    cmp r10d, 1
    je .dth_auto
    cmp r10d, 2
    je .dth_ff
    lea edi, [r10d - 2]
    call ssr_dec
    lea rdi, [s_css_px_semi]
    call out_str
    jmp .no_dth
.dth_auto:
    lea rdi, [s_v_auto]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .no_dth
.dth_ff:
    lea rdi, [s_v_from_font]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_dth:
    ; text-underline-offset (r13+50: 1 auto 2+ px)
    movzx r10d, byte [r13 + 50]
    test r10d, r10d
    jz .no_uo
    lea rdi, [s_css_uo]
    call out_str
    cmp r10d, 1
    je .uo_auto
    mov edi, r10d
    call ssr_dec
    lea rdi, [s_css_px_semi]
    call out_str
    jmp .no_uo
.uo_auto:
    lea rdi, [s_v_auto]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_uo:
    ; margin: (mt||mb) - labels honor mt-*/mb-* like views do; ml||mr
    ; forces the 4-value form (same rule as ssr_css_view)
    movzx eax, byte [r13 + 20]   ; ml
    movzx ecx, byte [r13 + 21]   ; mr
    or eax, ecx
    jnz .mgl4
    movzx eax, byte [r13 + 16]   ; mt
    movzx ecx, byte [r13 + 17]   ; mb
    test eax, eax
    jnz .have_mgl
    test ecx, ecx
    jz .no_mgl
.have_mgl:
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
    jmp .no_mgl
.mgl4:
    lea rdi, [s_css_mg]
    call out_str
    movzx edi, byte [r13 + 16]
    call ssr_dec
    lea rdi, [s_css_px_sp]
    call out_str
    movzx edi, byte [r13 + 21]
    call ssr_dec
    lea rdi, [s_css_px_sp]
    call out_str
    movzx edi, byte [r13 + 17]
    call ssr_dec
    lea rdi, [s_css_px_sp]
    call out_str
    movzx edi, byte [r13 + 20]
    call ssr_dec
    lea rdi, [s_css_px_semi]
    call out_str
.no_mgl:
    ; white-space (r13+39, table ws_vals)
    movzx r10d, byte [r13 + 39]
    test r10d, r10d
    jz .no_ws
    lea rdi, [s_css_ws]
    call out_str
    lea r11, [ws_vals]
    mov rdi, [r11 + r10*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_ws:
    ; word-break / overflow-wrap (r13+40: 1..4 word-break, 5..7 overflow-wrap)
    movzx r10d, byte [r13 + 40]
    test r10d, r10d
    jz .no_wb
    cmp r10d, 2
    je .wb_ow
    cmp r10d, 5
    je .wb_ow
    cmp r10d, 6
    je .wb_ow
    cmp r10d, 7
    je .wb_ow
    lea rdi, [s_css_wb]
    call out_str
    cmp r10d, 3
    je .wb_all
    cmp r10d, 4
    je .wb_keep
    lea rdi, [s_v_normal]
    jmp .wb_done
.wb_all:
    lea rdi, [s_v_break_all]
    jmp .wb_done
.wb_keep:
    lea rdi, [s_v_keep_all]
    jmp .wb_done
.wb_ow:
    lea rdi, [s_css_ow]
    call out_str
    cmp r10d, 7
    je .wb_any
    cmp r10d, 5
    jne .wb_bw
    lea rdi, [s_v_normal]
    jmp .wb_done
.wb_bw:
    lea rdi, [s_v_break_word]
    jmp .wb_done
.wb_any:
    lea rdi, [s_v_anywhere]
.wb_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_wb:
    ; text-overflow (r13+41: 1 ellipsis 2 clip 3 truncate combo)
    movzx r10d, byte [r13 + 41]
    test r10d, r10d
    jz .no_ov
    cmp r10d, 3
    jne .ov_notr
    lea rdi, [s_css_trunc]
    call out_str
    jmp .no_ov
.ov_notr:
    lea rdi, [s_css_ov]
    call out_str
    cmp r10d, 2
    jne .ov_ell
    lea rdi, [s_v_clip]
    jmp .ov_done
.ov_ell:
    lea rdi, [s_v_ellipsis]
.ov_done:
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_ov:
    ; text-wrap (r13+57, table tw_vals)
    movzx r10d, byte [r13 + 57]
    test r10d, r10d
    jz .no_tw
    lea rdi, [s_css_tw]
    call out_str
    lea r11, [tw_vals]
    mov rdi, [r11 + r10*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_tw:
    ; vertical-align (r13+42, table valign_vals)
    movzx r10d, byte [r13 + 42]
    test r10d, r10d
    jz .no_va
    lea rdi, [s_css_valign]
    call out_str
    lea r11, [valign_vals]
    mov rdi, [r11 + r10*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_va:
    ; text-indent (r13+43 px)
    movzx r10d, byte [r13 + 43]
    test r10d, r10d
    jz .no_ind
    lea rdi, [s_css_indent]
    call out_str
    mov edi, r10d
    call ssr_dec
    lea rdi, [s_css_px_semi]
    call out_str
.no_ind:
    ; hyphens (r13+54, table hyphens_vals)
    movzx r10d, byte [r13 + 54]
    test r10d, r10d
    jz .no_hyp
    lea rdi, [s_css_hyphens]
    call out_str
    lea r11, [hyphens_vals]
    mov rdi, [r11 + r10*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_hyp:
    ; tab-size (r13+55, plain number)
    movzx r10d, byte [r13 + 55]
    test r10d, r10d
    jz .no_tab
    lea rdi, [s_css_tab]
    call out_str
    mov edi, r10d
    call ssr_dec
    lea rdi, [s_css_semi]
    call out_str
.no_tab:
    ; line-clamp (r13+51): -webkit-line-clamp:N;overflow:hidden;
    movzx r10d, byte [r13 + 51]
    test r10d, r10d
    jz .no_cl
    lea rdi, [s_css_clamp1]
    call out_str
    mov edi, r10d
    call ssr_dec
    lea rdi, [s_css_clamp2]
    call out_str
.no_cl:
    ; content:none
    movzx eax, byte [r13 + 56]
    test eax, eax
    jz .no_cont
    lea rdi, [s_css_contn]
    call out_str
.no_cont:
    ; animation (r13+32, table anim_vals)
    movzx r10d, byte [r13 + 32]
    test r10d, r10d
    jz .no_anim
    lea rdi, [s_css_anim]
    call out_str
    lea r11, [anim_vals]
    mov rdi, [r11 + r10*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
.no_anim:
    ; line-height: leading value or the default 1.4
    movzx r10d, byte [r13 + 38]
    test r10d, r10d
    jz .no_lead
    lea rdi, [s_css_lhp]
    call out_str
    lea r11, [lead_vals]
    mov rdi, [r11 + r10*8 - 8]
    call out_str
    lea rdi, [s_css_semi]
    call out_str
    jmp .lh_done
.no_lead:
    lea rdi, [s_css_lh]          ; "line-height:1.4;"
    call out_str
.lh_done:
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
