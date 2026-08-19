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
    ; $state_base global (declarative state data addr)
    call emit_state_global
    ; declarative actions on buttons -> the handle_event func at the end
    ; of the module (after every other export)
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
; emit_state_global - "(global $state_base i32 (i32.const <addr>))"
; ----------------------------------------------------------------------
emit_state_global:
    push r12
    lea rdi, [s_state_g1]
    call out_main_str
    mov rdi, [state_base_addr]
    call itoa_main
    lea rdi, [s_state_g2]
    call out_main_str
    pop r12
    ret

; ----------------------------------------------------------------------
; emit_handle_event - if there are declarative actions (onclick=...),
; emits the exported handle_event into main_buf: t==1 (click) dispatches
; by widget id (the glue passes the data-asx-id of the clicked button).
; Each action mutates the state slot and sets $ui_dirty.
; ----------------------------------------------------------------------
emit_handle_event:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp qword [action_count], 0
    je .done
    lea rdi, [s_ev_h1]
    call out_main_str
    xor r12, r12                ; action idx
.act_loop:
    cmp r12, [action_count]
    jge .close
    imul rax, r12, ACTION_ENTRY
    lea r13, [action_tab + rax]
    ; resolve the button record idx (rec_order kind 1, node == A_WIDGET)
    mov r14d, [r13 + A_WIDGET]
    xor rbx, rbx
.btn_loop:
    cmp rbx, [rec_count]
    jge .act_next
    imul rax, rbx, 12
    lea r8, [rec_order + rax]
    cmp dword [r8], 1
    jne .btn_next
    cmp dword [r8 + 4], r14d
    je .btn_found
.btn_next:
    inc rbx
    jmp .btn_loop
.btn_found:
    ; id compare: local.get $id; i32.const <record>; i32.eq; if
    lea rdi, [s_ev_id]
    call out_main_str
    mov rdi, rbx
    call itoa_main
    lea rdi, [s_ev_h2]
    call out_main_str
    ; field offset into state_data
    mov edi, [r13 + A_STATE]
    mov esi, [r13 + A_FIELD]
    call state_field_addr
    mov r14d, eax
    ; op dispatch
    mov eax, [r13 + A_OP]
    cmp eax, OP_INC
    je .op_inc
    cmp eax, OP_DEC
    je .op_dec
    cmp eax, OP_SET
    je .op_set
    cmp eax, OP_ADD
    je .op_add
    cmp eax, OP_SUB
    je .op_sub
    cmp eax, OP_SET_TRUE
    je .op_set_true
    cmp eax, OP_SET_FALSE
    je .op_set_false
    jmp .act_dirty
.op_inc:
    lea rdi, [s_ev_ld]
    call out_main_str
    mov rdi, r14
    call itoa_main
    lea rdi, [s_ev_ld2]
    call out_main_str
    lea rdi, [s_ev_c1]
    call out_main_str
    jmp .act_dirty
.op_dec:
    lea rdi, [s_ev_ld]
    call out_main_str
    mov rdi, r14
    call itoa_main
    lea rdi, [s_ev_ld2]
    call out_main_str
    lea rdi, [s_ev_c1sub]
    call out_main_str
    jmp .act_dirty
.op_set:
    lea rdi, [s_ev_ld]
    call out_main_str
    mov rdi, r14
    call itoa_main
    lea rdi, [s_ev_add]
    call out_main_str
    lea rdi, [s_ev_cop]
    call out_main_str
    mov rdi, [r13 + A_OPERAND]
    call itoa_main
    lea rdi, [s_ev_st]
    call out_main_str
    jmp .act_dirty
.op_add:
    lea rdi, [s_ev_ld]
    call out_main_str
    mov rdi, r14
    call itoa_main
    lea rdi, [s_ev_ld2]
    call out_main_str
    lea rdi, [s_ev_cop]
    call out_main_str
    mov rdi, [r13 + A_OPERAND]
    call itoa_main
    lea rdi, [s_ev_addst]
    call out_main_str
    jmp .act_dirty
.op_sub:
    lea rdi, [s_ev_ld]
    call out_main_str
    mov rdi, r14
    call itoa_main
    lea rdi, [s_ev_ld2]
    call out_main_str
    lea rdi, [s_ev_copsub]
    call out_main_str
    mov rdi, [r13 + A_OPERAND]
    call itoa_main
    lea rdi, [s_ev_subst]
    call out_main_str
    jmp .act_dirty
.op_set_true:
    lea rdi, [s_ev_ld]
    call out_main_str
    mov rdi, r14
    call itoa_main
    lea rdi, [s_ev_add]
    call out_main_str
    lea rdi, [s_ev_st1]
    call out_main_str
    jmp .act_dirty
.op_set_false:
    lea rdi, [s_ev_ld]
    call out_main_str
    mov rdi, r14
    call itoa_main
    lea rdi, [s_ev_add]
    call out_main_str
    lea rdi, [s_ev_st0]
    call out_main_str
.act_dirty:
    lea rdi, [s_ev_dirty]
    call out_main_str
    lea rdi, [s_ev_endif]
    call out_main_str
.act_next:
    inc r12
    jmp .act_loop
.close:
    lea rdi, [s_ev_close]
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
