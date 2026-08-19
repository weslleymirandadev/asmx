; =============================================================================
; mainwat.asm - final module (append_wat_call, emit_wat_main)
; =============================================================================

append_wat_call:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp qword [main_started], 0
    jne .have_hdr
    mov qword [main_len], 0
    lea rdi, [s_main_h1]
    call out_main_str
    lea rdi, [ui_name_buf]
    mov rsi, [ui_name_len]
    call out_main_bytes
    lea rdi, [s_main_h2]
    call out_main_str
    mov qword [main_started], 1
.have_hdr:
    lea rdi, [s_main_call]
    call out_main_str
    lea rdi, [label_buf]
    mov rsi, [label_len]
    call out_main_bytes
    lea rdi, [s_nl2]
    call out_main_str
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; emit_wat_main - finishes the final module: close + theme + exports
; ----------------------------------------------------------------------
emit_wat_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea rdi, [s_main_t1]
    call out_main_str
    mov rdi, [theme_bg]
    call hex6_main
    lea rdi, [s_main_t2]
    call out_main_str
    mov rdi, [theme_text]
    call hex6_main
    lea rdi, [s_main_t3]
    call out_main_str
    mov rdi, [theme_accent]
    call hex6_main
    lea rdi, [s_main_t4]
    call out_main_str
    ; $style_base global (styles data segment addr) - emitted after the
    ; exports (wat2wasm resolves globals in any order; the styles()
    ; export above reads it)
    call emit_style_global
    ; state: button + "count: N" text -> emit the handle_event func
    ; at the end of the module (after every other export)
    call emit_handle_event
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; emit_style_global - "(global $style_base i32 (i32.const <addr>))"
; The styles() export (s_main_t4) reads $style_base; the data segment
; address is only known after the component wat is emitted, so it is
; written here, right after the header.
; ----------------------------------------------------------------------
emit_style_global:
    push r12
    lea rdi, [s_style_g1]
    call out_main_str
    mov rdi, [style_addr]
    call itoa_main
    lea rdi, [s_style_g2]
    call out_main_str
    pop r12
    ret

; hex6_main(rdi = 0xRRGGBB) - writes 6 hex digits to main_buf
hex6_main:
    push r12
    push r13
    mov r12, rdi
    mov r13, 20
.loop:
    cmp r13, 0
    jl .done
    mov eax, r12d
    mov ecx, r13d
    shr eax, cl
    and eax, 0x0f
    cmp eax, 10
    jl .digit
    add eax, 'a' - 10
    jmp .emit
.digit:
    add eax, '0'
.emit:
    call out_main_byte
    sub r13, 4
    jmp .loop
.done:
    pop r13
    pop r12
    ret

; ----------------------------------------------------------------------
; emit_handle_event - if the layout has a button (rec kind 1) AND a text
; node starting with "count: ", emits the $count global + the exported
; handle_event into main_buf: a click (t==1) inside the button rect
; increments $count and rewrites the digit at text_ptr+7 ("count: N").
; ----------------------------------------------------------------------
emit_handle_event:
    push rbx
    push r12
    push r13
    push r14
    push r15
    ; --- find the button view record (rec_order kind 1) ---
    xor r12, r12
.find_btn:
    cmp r12, [rec_count]
    jge .done
    imul rax, r12, 12
    lea rbx, [rec_order + rax]
    cmp dword [rbx], 1          ; kind 1 = button view
    je .have_btn
    inc r12
    jmp .find_btn
.have_btn:
    ; The glue filters clicks by the button's REAL DOM rect
    ; (getBoundingClientRect) and only calls handle_event(1, ...) for
    ; clicks inside a button, with coords relative to it. So the wasm
    ; hit test accepts anything: 0 <= x/y < 32767.
    mov r13d, 0                 ; bx = 0
    mov r14d, 0                 ; by = 0
    mov r15d, 32767             ; bw = 32767
    mov ebx, 32767              ; bh = 32767
    ; --- find the "count: " text node ---
    xor r12, r12
.find_cnt:
    cmp r12, [node_count]
    jge .done
    imul rax, r12, NODE_SIZE
    lea rcx, [nodes + rax]
    mov eax, [rcx + N_TEXT_PTR]
    test eax, eax
    jz .next_cnt
    lea rdi, [in_buf + rax]
    lea rsi, [s_count_prefix]
    mov rdx, 7
    call strncmp
    test rax, rax
    jz .have_cnt
.next_cnt:
    inc r12
    jmp .find_cnt
.have_cnt:
    ; the node's N_TEXT_PTR is an in_buf offset - the wasm text address
    ; must come from the RECORD's text_offset (blob-relative), like the
    ; emit pass does: find the rec_order entry whose node == r12
    xor rdx, rdx                ; rec idx (r15 keeps bw - no r15 here!)
.rec_loop:
    cmp rdx, [rec_count]
    jge .done
    imul rax, rdx, 12
    lea r8, [rec_order + rax]
    cmp dword [r8 + 4], r12d     ; rec node == the count node?
    jne .rec_next
    mov rax, rdx
    imul rax, rax, 32
    lea r8, [blob_buf + rax + 24]
    mov eax, [r8 + 16]           ; text_offset (blob-relative)
    mov rdi, rax
    call wat_text_addr           ; rax = wasm addr, but str_cursor already
                                 ; advanced by pool_len (.dd) and the styles
                                 ; data segment (16*rec_count) - undo both:
    mov ecx, [blob_len]
    sub ecx, 24
    mov edx, [rec_count]
    imul edx, edx, 32
    sub ecx, edx                 ; pool_len
    sub rax, rcx
    mov edx, [rec_count]
    imul edx, edx, 16            ; styles_len
    sub rax, rdx
    jmp .have_off
.rec_next:
    inc rdx
    jmp .rec_loop
.have_off:
    mov r12, rax                ; tp
    ; --- emit (the $count global lives in the module header) ---
    ; state accessors for hydration: the glue restores the snapshot
    ; count BEFORE the first render (set_count) so the first paint is
    ; exactly what the SSR produced
    lea rdi, [s_ev_cnt_get]
    call out_main_str
    lea rdi, [s_ev_cnt_set]
    call out_main_str
    lea rdi, [s_ev_head]
    call out_main_str
    mov rdi, r13                ; bx
    call itoa_main
    lea rdi, [s_ev_x_ge]
    call out_main_str
    lea rax, [r13 + r15]        ; bx + bw
    mov rdi, rax
    call itoa_main
    lea rdi, [s_ev_x_lt]
    call out_main_str
    mov rdi, r14                ; by
    call itoa_main
    lea rdi, [s_ev_y_ge]
    call out_main_str
    lea rax, [r14 + rbx]        ; by + bh
    mov rdi, rax
    call itoa_main
    lea rdi, [s_ev_y_lt]
    call out_main_str
    mov rdi, r12                ; tp
    call itoa_main
    lea rdi, [s_ev_dig]
    call out_main_str
    ; SPACE key handler (same increment, duplicated in the template)
    lea rdi, [s_ev_ksp]
    call out_main_str
    mov rdi, r12                ; tp
    call itoa_main
    lea rdi, [s_ev_ksp2]
    call out_main_str
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; write_wat_file - writes <out_path>.d/<label>.wat (mkdir of .d once)
