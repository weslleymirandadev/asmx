; =============================================================================
; state.asm - declarative state: types, states, interpolations, onclick
; =============================================================================
; DSL additions (no '@' - keyword directives + name="value" attributes):
;   type <name>                  ; object type, fields on the indented lines
;       field: int|bool|string[<N>]
;   state <name>: <type>         ; object state, values on indented lines
;       field: <value>
;   state <name>: int = <n>      ; scalar int
;   state <name>: bool = true    ; scalar bool
;   <tag> onclick="<expr>"       ; action on a button (expr: count++ / x = 5 / u.a = true)
;   "text {state}" / "text {state.field}"   ; interpolation (1 per text)
;
; Runtime model: every state lives in a memory area (state_data) as a flat
; record; strings are bytes in state_str_buf and their field stores an
; offset that the emit pass resolves to a wasm address. The render()
; rebuilds texts from the CURRENT values (fmt in widgets.wat); the SSR
; blob carries the INITIAL values (serialize resolves interpolations).

; ----------------------------------------------------------------------
; is_directive(rdi = line ptr, rsi = line end) -> rax = 1 if the line
; starts with the "state" or "type" keyword (no '@'). Used by
; find_block_end to keep directive lines inside a @ block.
; ----------------------------------------------------------------------
is_directive:
    push rbx
    push r12
    mov r12, rdi                ; line start
    mov rbx, rdi
.id_tk:
    cmp rbx, rsi
    jge .no
    mov al, [in_buf + rbx]
    cmp al, ' '
    je .id_have
    cmp al, 9
    je .id_have
    inc rbx
    jmp .id_tk
.id_have:
    mov rdx, rbx
    sub rdx, r12                ; token len
    cmp rdx, 5
    jne .not_state
    lea rdi, [in_buf + r12]
    lea rsi, [s_state]
    mov rdx, 5
    call strncmp
    test rax, rax
    jz .yes
.not_state:
    mov rdx, rbx
    sub rdx, r12
    cmp rdx, 4
    jne .no
    lea rdi, [in_buf + r12]
    lea rsi, [s_type]
    mov rdx, 4
    call strncmp
    test rax, rax
    jz .yes
    jmp .no
.yes:
    mov rax, 1
    jmp .done
.no:
    xor eax, eax
.done:
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; line_has_colon(rdi = line ptr, rsi = end) -> rax = 1 se a linha tem
; ':' antes do primeiro espaço (um "campo: valor" de type/state)
; ----------------------------------------------------------------------
line_has_colon:
    push rbx
    mov rbx, rdi
.lhc_loop:
    cmp rbx, rsi
    jge .no
    mov al, [in_buf + rbx]
    cmp al, ':'
    je .yes
    cmp al, ' '
    je .no
    cmp al, 9
    je .no
    inc rbx
    jmp .lhc_loop
.yes:
    mov rax, 1
    jmp .done
.no:
    xor eax, eax
.done:
    pop rbx
    ret

; ----------------------------------------------------------------------
; parse_directive(rdi = cur, rsi = end) -> rax = new cur, or -1 if the
; line is not a keyword directive. Dispatches state/type (no '@').
; ----------------------------------------------------------------------
parse_directive:
    push rbx
    push r12
    push r13
    mov r12, rdi                ; cur
    mov r13, rsi                ; end
    ; skip leading whitespace (indented lines inside the block)
    mov rbx, r12
.pd_ws:
    cmp rbx, r13
    jge .none
    mov al, [in_buf + rbx]
    cmp al, ' '
    je .pd_ws_inc
    cmp al, 9
    jne .pd_tk
.pd_ws_inc:
    inc rbx
    jmp .pd_ws
.pd_tk:
    mov r12, rbx
    ; first token of the line: [r12, space)
    mov rbx, r12
.tk:
    cmp rbx, r13
    jge .none
    mov al, [in_buf + rbx]
    cmp al, ' '
    je .have
    cmp al, 9
    je .have
    cmp al, ':'
    je .have
    inc rbx
    jmp .tk
.have:
    mov rdx, rbx
    sub rdx, r12                ; token len
    ; "state"?
    cmp rdx, 5
    jne .not_state
    lea rdi, [in_buf + r12]
    lea rsi, [s_state]
    mov rdx, 5
    call strncmp
    test rax, rax
    jnz .not_state
    mov rdi, r12
    mov rsi, r13
    call parse_state_directive
    jmp .done
.not_state:
    ; "type"?
    mov rdx, rbx
    sub rdx, r12
    cmp rdx, 4
    jne .not_type
    lea rdi, [in_buf + r12]
    lea rsi, [s_type]
    mov rdx, 4
    call strncmp
    test rax, rax
    jnz .not_type
    mov rdi, r12
    mov rsi, r13
    call parse_type_directive
    jmp .done
.not_type:
    mov rax, -1
.done:
    pop r13
    pop r12
    pop rbx
    ret
.none:
    mov rax, -1
    jmp .done

; ----------------------------------------------------------------------
; parse_type_directive(rdi = cur, rsi = end) -> rax = new cur
;   type <name>
;       field: int|bool|string[<N>]   (indented lines)
; ----------------------------------------------------------------------
parse_type_directive:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; cur
    mov r13, rsi                ; end
    ; skip "type" token
    mov rbx, r12
.pt_skip:
    cmp rbx, r13
    jge .err
    mov al, [in_buf + rbx]
    cmp al, ' '
    je .pt_have
    cmp al, 9
    je .pt_have
    inc rbx
    jmp .pt_skip
.pt_have:
    ; skip ws
.pt_ws:
    cmp rbx, r13
    jge .err
    mov al, [in_buf + rbx]
    cmp al, ' '
    je .pt_ws_inc
    cmp al, 9
    jne .pt_name
.pt_ws_inc:
    inc rbx
    jmp .pt_ws
.pt_name:
    ; name: [rbx, space)
    mov r14, rbx
.pt_name_scan:
    cmp r14, r13
    jge .pt_name_end
    mov al, [in_buf + r14]
    cmp al, ' '
    je .pt_name_end
    cmp al, 9
    je .pt_name_end
    cmp al, 10
    je .pt_name_end
    inc r14
    jmp .pt_name_scan
.pt_name_end:
    ; register the type
    cmp qword [type_count], MAX_TYPES
    jge .err
    mov rax, [type_count]
    imul rax, rax, TYPE_ENTRY
    lea r15, [type_tab + rax]   ; r15 = type entry
    mov [r15 + T_NAME_PTR], ebx
    mov eax, r14d
    sub eax, ebx
    mov [r15 + T_NAME_LEN], eax
    mov dword [r15 + T_N_FIELDS], 0
    mov dword [r15 + T_SIZE], 0
    mov edx, [field_count]      ; this type's fields start here
    mov [r15 + T_FIELDS_IDX], edx
    ; directive indent = r12 - line start (the token's offset)
    mov r9, r12
.pt_ib:
    cmp r9, 0
    jle .pt_ib_done
    cmp byte [in_buf + r9 - 1], 10
    je .pt_ib_done
    dec r9
    jmp .pt_ib
.pt_ib_done:
    sub r12d, r9d               ; r12 = directive indent
    push r12                    ; saved on the stack (survives calls)
    ; fields: indented lines until dedent
    mov r12, r14
    ; skip to the end of the "type <name>" line first
.pt_eol:
    cmp r12, r13
    jge .pt_done
    cmp byte [in_buf + r12], 10
    je .pt_eol_done
    inc r12
    jmp .pt_eol
.pt_eol_done:
    inc r12                     ; next line
.pt_line:
    ; end of current line
    cmp r12, r13
    jge .pt_done
    mov r14, r12
.pt_scan:
    cmp r14, r13
    jge .pt_line_end
    cmp byte [in_buf + r14], 10
    je .pt_line_end
    inc r14
    jmp .pt_scan
.pt_line_end:
    ; indent?
    mov rbx, r12
.pt_ind:
    cmp rbx, r14
    jge .pt_done
    mov al, [in_buf + rbx]
    cmp al, ' '
    je .pt_ind_inc
    cmp al, 9
    jne .pt_ind_done
.pt_ind_inc:
    inc rbx
    jmp .pt_ind
.pt_ind_done:
    cmp rbx, r12
    jle .pt_done
    ; line indent <= directive indent -> end of the type body
    mov rax, rbx
    sub rax, r12                ; this line's indent
    cmp eax, [rsp]              ; saved directive indent
    jle .pt_done
    ; field: name ':' kind
    mov rdi, rbx                ; name ptr
    mov rsi, r14
    call parse_field_line       ; rax = kind, rbx = new pos (after kind)
    cmp rax, -1
    je .err
    ; append field to the type
    mov ecx, [r15 + T_N_FIELDS]
    cmp ecx, MAX_FIELDS
    jge .err
    mov r8, [field_count]
    imul r8, r8, FIELD_ENTRY
    lea r9, [field_tab + r8]
    mov [r9 + F_NAME_PTR], edi  ; edi = name ptr (parse_field_line returned it)
    mov [r9 + F_NAME_LEN], esi  ; esi = name len
    mov [r9 + F_OFFSET], ecx
    imul ecx, ecx, 4            ; offset = n_fields * 4
    mov [r9 + F_OFFSET], ecx
    mov [r9 + F_KIND], eax
    ; str cap
    cmp eax, K_STR
    jne .pt_nostrcap
    mov [r9 + F_STR_CAP], r10d
.pt_nostrcap:
    inc qword [field_count]
    ; size += 4
    mov eax, [r15 + T_SIZE]
    add eax, 4
    mov [r15 + T_SIZE], eax
    mov eax, [r15 + T_N_FIELDS]
    inc eax
    mov [r15 + T_N_FIELDS], eax
    ; next line
    mov r12, r14
    cmp r12, r13
    jge .pt_done
    cmp byte [in_buf + r12], 10
    jne .pt_done
    inc r12
    jmp .pt_line
.pt_done:
    pop r9                      ; discard the saved indent
    inc qword [type_count]
    mov rax, r12
    jmp .out
.err:
    lea rdi, [msg_type]
    mov rsi, msg_type_len
    call die
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; parse_field_line(rdi = line ptr, rsi = line end) -> rax = kind,
; rbx = pos after the kind, rdi = name ptr, rsi = name len, r10d = str cap
; Parses "name: kind" where kind is int|bool|string|string<N>.
; ----------------------------------------------------------------------
parse_field_line:
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    ; name until ':'
    mov rdi, r12
.pf_scan:
    cmp rdi, r13
    jge .err
    mov al, [in_buf + rdi]
    cmp al, ':'
    je .pf_colon
    cmp al, ' '
    je .err
    inc rdi
    jmp .pf_scan
.pf_colon:
    mov r15, rdi
    sub r15, r12                ; name len (r15 callee-saved)
    ; skip ':' and ws
    lea rbx, [rdi + 1]
.pf_ws:
    cmp rbx, r13
    jge .err
    mov al, [in_buf + rbx]
    cmp al, ' '
    je .pf_ws_inc
    cmp al, 9
    jne .pf_kind
.pf_ws_inc:
    inc rbx
    jmp .pf_ws
.pf_kind:
    ; kind: [rbx, end or space)
    mov rcx, rbx
.pf_kscan:
    cmp rcx, r13
    jge .pf_kend
    mov al, [in_buf + rcx]
    cmp al, ' '
    je .pf_kend
    cmp al, 9
    je .pf_kend
    inc rcx
    jmp .pf_kscan
.pf_kend:
    mov rdx, rcx
    sub rdx, rbx                ; kind token len
    mov r14, rbx                ; kind ptr (r14 callee-saved - strncmp
                                ; clobbers r8!)
    mov r13, rcx                ; kind end (rcx is clobbered by strncmp!)
    ; int?
    cmp rdx, 3
    jne .pf_not_int
    lea rdi, [in_buf + r14]
    lea rsi, [s_key_int]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .pf_not_int
    mov rax, K_INT
    xor r10d, r10d
    mov rbx, r13
    jmp .ok
.pf_not_int:
    ; bool?
    mov rdx, r13
    sub rdx, r14
    cmp rdx, 4
    jne .pf_not_bool
    lea rdi, [in_buf + r14]
    lea rsi, [s_key_bool]
    mov rdx, 4
    call strncmp
    test rax, rax
    jnz .pf_not_bool
    mov rax, K_BOOL
    xor r10d, r10d
    mov rbx, r13
    jmp .ok
.pf_not_bool:
    ; string? (with optional <N>)
    mov rdx, r13
    sub rdx, r14
    cmp rdx, 6
    jl .err
    lea rdi, [in_buf + r14]
    lea rsi, [s_key_string]
    mov rdx, 6
    call strncmp
    test rax, rax
    jnz .err
    mov rax, K_STR
    mov r10d, STR_DEFAULT_CAP
    ; <N>?
    lea rdi, [in_buf + r14 + 6]
    mov rsi, r13
    sub rsi, r14
    sub rsi, 6
    test rsi, rsi
    jz .pf_str_done
    cmp byte [in_buf + r14 + 6], '<'
    jne .err
    dec rsi
    cmp byte [in_buf + r13 - 1], '>'
    jne .err
    dec rsi
    lea rdi, [in_buf + r14 + 7]
    call atoi_n
    test rax, rax
    jz .err
    mov r10d, eax
.pf_str_done:
    mov rbx, rcx
    jmp .ok
.err:
    mov rax, -1
.ok:
    ; return name ptr in rdi, name len in rsi (the caller stores them
    ; into the field table)
    mov rdi, r12                ; name ptr (line start = name start)
    mov rsi, r15                ; name len
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; ----------------------------------------------------------------------
; parse_state_directive(rdi = cur, rsi = end) -> rax = new cur
;   state <name>: int = <n> | bool = true|false
;   state <name>: <type>        ; object, values on indented lines
;       field: <value>
; ----------------------------------------------------------------------
parse_state_directive:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    ; skip "state"
    mov rbx, r12
.ps_skip:
    cmp rbx, r13
    jge .err
    mov al, [in_buf + rbx]
    cmp al, ' '
    je .ps_have
    cmp al, 9
    je .ps_have
    inc rbx
    jmp .ps_skip
.ps_have:
.ps_ws:
    cmp rbx, r13
    jge .err
    mov al, [in_buf + rbx]
    cmp al, ' '
    je .ps_ws_inc
    cmp al, 9
    jne .ps_name
.ps_ws_inc:
    inc rbx
    jmp .ps_ws
.ps_name:
    ; name: [rbx, ':' or space)
    mov r14, rbx
.ps_nscan:
    cmp r14, r13
    jge .err
    mov al, [in_buf + r14]
    cmp al, ':'
    je .ps_colon
    cmp al, ' '
    je .ps_colon
    cmp al, 10
    je .err
    inc r14
    jmp .ps_nscan
.ps_colon:
    mov r11d, r14d
    sub r11d, ebx               ; name len (r11 callee-saved)
    inc r14                     ; skip ':'
    ; skip ws -> type token
.ps_ws2:
    cmp r14, r13
    jge .err
    mov al, [in_buf + r14]
    cmp al, ' '
    je .ps_ws2_inc
    cmp al, 9
    jne .ps_type
.ps_ws2_inc:
    inc r14
    jmp .ps_ws2
.ps_type:
    ; type: [r14, space or '=')
    mov r15, r14
.ps_tscan:
    cmp r15, r13
    jge .ps_tend
    mov al, [in_buf + r15]
    cmp al, ' '
    je .ps_tend
    cmp al, 9
    je .ps_tend
    cmp al, '='
    je .ps_tend
    cmp al, 10
    je .ps_tend
    inc r15
    jmp .ps_tscan
.ps_tend:
    mov r9d, r15d
    sub r9d, r14d               ; type token len
    ; check int/bool (scalar)
    mov rdi, r14
    mov rsi, r9
    call type_kind_of           ; rax = K_INT/K_BOOL for scalars, -1 for named
    cmp rax, -1
    je .ps_obj
    ; ---- scalar: expect '= value' ----
    mov r10d, eax               ; kind (r10 callee-saved)
    ; register the state BEFORE the value parse reuses r11 (val ptr)
    mov rdi, rbx                ; name ptr
    mov rsi, r11                ; name len
    mov rdx, r10                ; kind
    call state_register_scalar  ; rax = state idx
    push rax                    ; state idx
    ; skip ws to '='
    mov rcx, r15
.ps_eq_ws:
    cmp rcx, r13
    jge .err
    mov al, [in_buf + rcx]
    cmp al, ' '
    je .ps_eq_inc
    cmp al, 9
    je .ps_eq_inc
    cmp al, '='
    je .ps_eq
    jmp .err
.ps_eq_inc:
    inc rcx
    jmp .ps_eq_ws
.ps_eq:
    inc rcx
.ps_val_ws:
    cmp rcx, r13
    jge .err
    mov al, [in_buf + rcx]
    cmp al, ' '
    je .ps_val_inc
    cmp al, 9
    jne .ps_val
.ps_val_inc:
    inc rcx
    jmp .ps_val_ws
.ps_val:
    ; value: [rcx, line end)
    mov rdi, rcx
    mov rsi, rcx
.ps_line_scan:
    cmp rsi, r13
    jge .ps_line_done
    cmp byte [in_buf + rsi], 10
    je .ps_line_done
    inc rsi
    jmp .ps_line_scan
.ps_line_done:
    ; trim trailing \r
.ps_val_trim:
    cmp rsi, rdi
    jle .ps_val_ok
    cmp byte [in_buf + rsi - 1], 13
    jne .ps_val_ok
    dec rsi
    jmp .ps_val_trim
.ps_val_ok:
    mov r11, rdi                ; val ptr (r11 callee-saved)
    mov r15, rsi                ; val end (r15 callee-saved)
.ps_register:
    ; store the initial value into the state slot
    cmp r10d, K_STR
    je .ps_scalar_str
    mov rdi, r11
    mov rsi, r15
    call parse_scalar_value     ; rax = value
    pop rcx                     ; state idx
    imul rcx, rcx, STATE_ENTRY
    lea rcx, [state_tab + rcx]
    mov edx, [rcx + S_DATA_OFF]
    mov [state_data + rdx], eax
    jmp .ps_after_val
.ps_scalar_str:
    ; string scalar: copy "..." into state_str_buf, field stores the offset
    mov rdi, r11
    mov rsi, r15
    call state_str_store        ; rax = offset or -1
    pop rcx                     ; state idx
    imul rcx, rcx, STATE_ENTRY
    lea rcx, [state_tab + rcx]
    mov edx, [rcx + S_DATA_OFF]
    mov [state_data + rdx], eax
.ps_after_val:
    ; consume the rest of the line
    mov r12, r15
    jmp .done
.ps_obj:
    ; ---- object: resolve type, register, consume indented value lines ----
    mov rdi, r14
    mov rsi, r9
    call type_lookup            ; rax = type idx
    cmp rax, -1
    je .err_type
    mov r10d, eax               ; type idx
    mov rdi, rbx                ; name ptr
    mov rsi, r11                ; name len
    mov rdx, r10
    call state_register_object  ; rax = state idx
    ; directive indent = r12 - line start (the token's offset)
    mov r9, r12
.ps_ib:
    cmp r9, 0
    jle .ps_ib_done
    cmp byte [in_buf + r9 - 1], 10
    je .ps_ib_done
    dec r9
    jmp .ps_ib
.ps_ib_done:
    sub r12d, r9d               ; r12 = directive indent
    push r12                    ; saved on the stack (survives calls)
    push r10                    ; type idx (r10 is clobbered by calls!)
    ; end of the "state <name>: <type>" line -> next line
    mov r14, r15
.ps_eol:
    cmp r14, r13
    jge .ps_odone
    cmp byte [in_buf + r14], 10
    je .ps_eol_done
    inc r14
    jmp .ps_eol
.ps_eol_done:
    inc r14
.ps_ol:
    cmp r14, r13
    jge .ps_odone
    mov r15, r14
.ps_oscan:
    cmp r15, r13
    jge .ps_oend
    cmp byte [in_buf + r15], 10
    je .ps_oend
    inc r15
    jmp .ps_oscan
.ps_oend:
    ; indent?
    mov rbx, r14
.ps_oind:
    cmp rbx, r15
    jge .ps_odone
    mov al, [in_buf + rbx]
    cmp al, ' '
    je .ps_oind_inc
    cmp al, 9
    jne .ps_oind_done
.ps_oind_inc:
    inc rbx
    jmp .ps_oind
.ps_oind_done:
    cmp rbx, r14
    jle .ps_odone
    ; line indent <= directive indent -> end of the object body
    mov rax, rbx
    sub rax, r14                ; this line's indent
    cmp eax, [rsp + 8]          ; saved directive indent
    jle .ps_odone
    ; field line: name ':' value
    mov rdi, rbx                ; line ptr
    mov rsi, r15                ; line end
    mov rdx, [rsp]              ; type idx (pushed, survives calls)
    call parse_state_field_value
    cmp rax, -1
    je .err
    mov r14, r15
    cmp r14, r13
    jge .ps_odone
    cmp byte [in_buf + r14], 10
    jne .ps_odone
    inc r14
    jmp .ps_ol
.ps_odone:
    pop r9                      ; discard the type idx
    pop r9                      ; discard the saved indent
    mov r12, r14
    jmp .done
.err:
    lea rdi, [msg_state]
    mov rsi, msg_state_len
    call die
.err_type:
    lea rdi, [msg_typemiss]
    mov rsi, msg_typemiss_len
    call err_msg_token
.done:
    mov rax, r12
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; type_kind_of(rdi = ptr, rsi = len) -> rax = K_INT/K_BOOL for the scalar
; keyword types, -1 otherwise (a named type)
; ----------------------------------------------------------------------
type_kind_of:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    cmp r13, 3
    jne .not_int
    lea rdi, [in_buf + r12]
    lea rsi, [s_key_int]
    mov rdx, 3
    call strncmp
    test rax, rax
    jnz .not_int
    mov rax, K_INT
    jmp .done
.not_int:
    cmp r13, 4
    jne .not_bool
    lea rdi, [in_buf + r12]
    lea rsi, [s_key_bool]
    mov rdx, 4
    call strncmp
    test rax, rax
    jnz .not_bool
    mov rax, K_BOOL
    jmp .done
.not_bool:
    ; string? (also matches string<N>)
    cmp r13, 6
    jl .none
    lea rdi, [in_buf + r12]
    lea rsi, [s_key_string]
    mov rdx, 6
    call strncmp
    test rax, rax
    jnz .none
    mov rax, K_STR
    jmp .done
.none:
    mov rax, -1
.done:
    pop r13
    pop r12
    ret

; ----------------------------------------------------------------------
; state_register_scalar(rdi = name ptr, rsi = name len, rdx = kind)
; -> rax = state idx. Allocates 4 bytes in state_data.
; ----------------------------------------------------------------------
state_register_scalar:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    cmp qword [state_count], MAX_STATES
    jge .err
    mov rax, [state_count]
    imul rax, rax, STATE_ENTRY
    lea rbx, [state_tab + rax]
    mov [rbx + S_NAME_PTR], r12d
    mov [rbx + S_NAME_LEN], r13d
    mov dword [rbx + S_TYPE_IDX], -1
    mov eax, [state_data_len]
    mov [rbx + S_DATA_OFF], eax
    add dword [state_data_len], 4
    mov dword [rbx + S_IS_OBJ], 0
    mov [rbx + S_KIND], edx
    mov rax, [state_count]
    inc qword [state_count]
    jmp .done
.err:
    lea rdi, [msg_state]
    mov rsi, msg_state_len
    call die
.done:
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; state_register_object(rdi = name ptr, rsi = name len, rdx = type idx)
; -> rax = state idx. Allocates type size bytes in state_data.
; ----------------------------------------------------------------------
state_register_object:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    cmp qword [state_count], MAX_STATES
    jge .err
    mov rax, [state_count]
    imul rax, rax, STATE_ENTRY
    lea rbx, [state_tab + rax]
    mov [rbx + S_NAME_PTR], r12d
    mov [rbx + S_NAME_LEN], r13d
    mov [rbx + S_TYPE_IDX], edx
    mov eax, [state_data_len]
    mov [rbx + S_DATA_OFF], eax
    ; size = type_tab[type].T_SIZE
    imul rcx, rdx, TYPE_ENTRY
    mov ecx, [type_tab + rcx + T_SIZE]
    add [state_data_len], ecx
    mov dword [rbx + S_IS_OBJ], 1
    mov dword [rbx + S_KIND], -1
    mov rax, [state_count]
    inc qword [state_count]
    jmp .done
.err:
    lea rdi, [msg_state]
    mov rsi, msg_state_len
    call die
.done:
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; parse_scalar_value(rdi = ptr, rsi = len) -> rax = value or -1
; int -> atoi; bool -> 1/0
; ----------------------------------------------------------------------
parse_scalar_value:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    ; true?
    cmp r13, 4
    jne .not_true
    lea rdi, [in_buf + r12]
    lea rsi, [s_true]
    mov rdx, 4
    call strncmp
    test rax, rax
    jnz .not_true
    mov rax, 1
    jmp .done
.not_true:
    ; false?
    cmp r13, 5
    jne .not_false
    lea rdi, [in_buf + r12]
    lea rsi, [s_false]
    mov rdx, 5
    call strncmp
    test rax, rax
    jnz .not_false
    xor eax, eax
    jmp .done
.not_false:
    ; int
    lea rdi, [in_buf + r12]
    mov rsi, r13
    call atoi_n
    cmp rax, -1
    jne .done
    mov rax, -1
.done:
    pop r13
    pop r12
    ret

; ----------------------------------------------------------------------
; state_str_store(rdi = ptr, rsi = end) -> rax = state_str_buf offset or -1
; Copies a quoted "string" (without the quotes) into state_str_buf,
; null-terminated. Enforces STR_DEFAULT_CAP.
; ----------------------------------------------------------------------
state_str_store:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    cmp byte [in_buf + r12], '"'
    jne .err
    inc r12
    cmp byte [in_buf + r13 - 1], '"'
    jne .err
    dec r13
    mov rbx, r13
    sub rbx, r12                ; string len
    cmp rbx, STR_DEFAULT_CAP
    jg .err
    mov r8, [state_str_len]
    lea r9, [state_str_buf + r8]
    xor r10, r10
.ss_cp:
    cmp r10, rbx
    jge .done
    mov cl, [in_buf + r12 + r10]
    mov [r9 + r10], cl
    inc r10
    jmp .ss_cp
.done:
    mov byte [r9 + rbx], 0
    mov rax, r8
    add [state_str_len], rbx
    inc qword [state_str_len]
    jmp .out
.err:
    mov rax, -1
.out:
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; parse_state_field_value(rdi = line ptr, rsi = line end, rdx = type idx)
; -> rax = 0 ok, -1 err. Parses "field: value" and stores the value into
; state_data at the state's S_DATA_OFF + field offset. Strings go to
; state_str_buf, the field stores the offset.
; ----------------------------------------------------------------------
parse_state_field_value:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; line ptr
    mov r13, rsi                ; line end
    mov r14, rdx                ; type idx
    ; field name until ':'
    mov rbx, r12
.psf_scan:
    cmp rbx, r13
    jge .err
    mov al, [in_buf + rbx]
    cmp al, ':'
    je .psf_colon
    cmp al, ' '
    je .err
    inc rbx
    jmp .psf_scan
.psf_colon:
    ; field lookup in the type
    mov rdi, r12
    mov rsi, rbx
    sub rsi, r12                ; name len
    mov rdx, r14
    call field_lookup           ; rax = field idx
    cmp rax, -1
    je .err
    mov r15d, eax               ; field idx
    ; skip ':' ws
    lea rbx, [rbx + 1]
.psf_ws:
    cmp rbx, r13
    jge .err
    mov al, [in_buf + rbx]
    cmp al, ' '
    je .psf_ws_inc
    cmp al, 9
    jne .psf_val
.psf_ws_inc:
    inc rbx
    jmp .psf_ws
.psf_val:
    ; value: [rbx, r13) trimmed
    mov rdi, rbx
    mov rsi, r13
.psf_trim:
    cmp rsi, rdi
    jle .psf_vok
    cmp byte [in_buf + rsi - 1], 13
    jne .psf_vok
    dec rsi
    jmp .psf_trim
.psf_vok:
    ; field entry
    imul rax, r15, FIELD_ENTRY
    lea rcx, [field_tab + rax]
    mov eax, [rcx + F_KIND]
    ; state data address of this field
    mov rdx, [state_count]
    dec rdx
    imul rdx, rdx, STATE_ENTRY
    mov edx, [state_tab + rdx + S_DATA_OFF]
    add edx, [rcx + F_OFFSET]
    mov r14d, edx               ; field data addr (r14 survives calls)
    ; store by kind
    cmp eax, K_STR
    je .psf_str
    ; int/bool (rdi/rsi = value ptr/end from .psf_trim)
    call parse_scalar_value
    cmp rax, -1
    je .err
    mov [state_data + r14], eax
    jmp .ok
.psf_str:
    ; copy the string (between quotes) into state_str_buf
    mov rdi, rdi
    cmp byte [in_buf + rdi], '"'
    jne .err
    inc rdi
    dec rsi
    cmp byte [in_buf + rsi], '"'
    jne .err
    ; len check vs cap
    mov ecx, [rcx + F_STR_CAP]
    mov eax, esi
    sub eax, edi
    cmp eax, ecx
    jg .err
    ; copy to state_str_buf
    mov r8, [state_str_len]     ; off
    lea r9, [state_str_buf + r8]
    xor r10, r10
.psf_cp:
    cmp r10, rax
    jge .psf_cp_done
    mov cl, [in_buf + rdi + r10]
    mov [r9 + r10], cl
    inc r10
    jmp .psf_cp
.psf_cp_done:
    mov byte [r9 + rax], 0
    add [state_str_len], rax
    inc qword [state_str_len]
    ; field stores the state_str_buf offset
    mov [state_data + r14], r8d
    jmp .ok
.err:
    mov rax, -1
    jmp .out
.ok:
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; type_lookup(rdi = ptr, rsi = len) -> rax = type idx or -1
; field_lookup(rdi = ptr, rsi = len, rdx = type idx) -> rax = field idx or -1
; state_lookup(rdi = ptr, rsi = len) -> rax = state idx or -1
; ----------------------------------------------------------------------
type_lookup:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    xor rbx, rbx
.tl_loop:
    cmp rbx, [type_count]
    jge .none
    imul rax, rbx, TYPE_ENTRY
    lea rcx, [type_tab + rax]
    mov edi, [rcx + T_NAME_PTR]
    mov esi, [rcx + T_NAME_LEN]
    cmp rsi, r13
    jne .tl_next
    lea rdi, [in_buf + rdi]
    lea rsi, [in_buf + r12]
    mov rdx, r13
    call strncmp
    test rax, rax
    jz .found
.tl_next:
    inc rbx
    jmp .tl_loop
.found:
    mov rax, rbx
    jmp .done
.none:
    mov rax, -1
.done:
    pop r13
    pop r12
    pop rbx
    ret

field_lookup:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx                ; type idx
    imul rax, r14, TYPE_ENTRY
    lea rcx, [type_tab + rax]
    mov ebx, [rcx + T_FIELDS_IDX]
    mov r15d, [rcx + T_N_FIELDS] ; r15 survives strncmp (r8 doesn't!)
    xor r9, r9
.fl_loop:
    cmp r9, r15
    jge .none
    imul rax, r9, FIELD_ENTRY
    lea rcx, [field_tab + rbx + rax]
    mov edi, [rcx + F_NAME_PTR]
    mov esi, [rcx + F_NAME_LEN]
    cmp rsi, r13
    jne .fl_next
    lea rdi, [in_buf + rdi]
    lea rsi, [in_buf + r12]
    mov rdx, r13
    call strncmp
    test rax, rax
    jz .found
.fl_next:
    inc r9
    jmp .fl_loop
.found:
    mov rax, r9
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

state_lookup:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    xor rbx, rbx
.sl_loop:
    cmp rbx, [state_count]
    jge .none
    imul rax, rbx, STATE_ENTRY
    lea rcx, [state_tab + rax]
    mov edi, [rcx + S_NAME_PTR]
    mov esi, [rcx + S_NAME_LEN]
    cmp rsi, r13
    jne .sl_next
    lea rdi, [in_buf + rdi]
    lea rsi, [in_buf + r12]
    mov rdx, r13
    call strncmp
    test rax, rax
    jz .found
.sl_next:
    inc rbx
    jmp .sl_loop
.found:
    mov rax, rbx
    jmp .done
.none:
    mov rax, -1
.done:
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; parse_attr(rdi = name ptr, rsi = name len, rdx = val ptr, rcx = val len)
; Handles onclick="expr" attributes: registers an action on the LAST
; button node pushed (the current open node).
; ----------------------------------------------------------------------
parse_attr:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    push rcx                    ; value len (strncmp clobbers rcx!)
    ; name == "onclick"?
    cmp r13, 7
    jne .unknown
    lea rdi, [in_buf + r12]
    lea rsi, [s_key_onclick]
    mov rdx, 7
    call strncmp
    test rax, rax
    jnz .unknown
    ; the current open node (top of istack) is the button
    cmp qword [stack_top], 0
    je .unknown
    mov rax, [stack_top]
    dec rax
    shl rax, 3
    lea rbx, [istack + rax]
    mov ebx, [rbx + 4]          ; node idx
    ; record idx of this node (search rec_order later - emit does the
    ; same correlation; store the NODE idx and resolve in the emit pass)
    ; For now the action stores the node idx; the emit pass converts it
    ; to the button view record (kind 1). We mark the node as a button.
    ; -> parse the expression
    mov rdi, r14
    pop rsi                     ; value len (restored)
    mov rdx, rbx
    call parse_expr
    jmp .done
.unknown:
    ; generic html attribute: store 'name="value" ' into the attr_buf of
    ; the CURRENT open node (top of istack, same node onclick targets).
    ; The SSR emits these verbatim after the tag name; the wasm record
    ; carries a pointer (attr_ptr) so the glue re-applies them on CSR.
    ; r12=name ptr r13=name len r14=val ptr - all live.
    pop r9                      ; value len (ALWAYS popped here; the
                                ; onclick path pops it as rsi above)
    cmp qword [stack_top], 0
    je .attr_done
    mov rax, [stack_top]
    dec rax
    shl rax, 3
    lea rbx, [istack + rax]
    mov ebx, [rbx + 4]          ; node idx
    mov rax, [attr_cur]
    cmp rax, 4096 - 64
    jge .attr_done
    lea r15, [attr_buf + rax]   ; write cursor (callee-saved, no calls)
    mov r11, r15                ; start pointer (for the length)
    ; name
    mov rcx, r13
    lea rsi, [in_buf + r12]
    xor r8, r8
.an_copy:
    cmp r8, rcx
    jge .an_done
    mov al, [rsi + r8]
    mov [r15 + r8], al
    inc r8
    jmp .an_copy
.an_done:
    add r15, r8
    ; '="'
    mov byte [r15], '='
    mov byte [r15 + 1], '"'
    add r15, 2
    ; value
    mov rcx, r9                ; value len
    lea rsi, [in_buf + r14]
    xor r8, r8
.av_copy:
    cmp r8, rcx
    jge .av_done
    mov al, [rsi + r8]
    mov [r15 + r8], al
    inc r8
    jmp .av_copy
.av_done:
    add r15, r8
    ; '"' (no trailing space - the SSR adds separators itself)
    mov byte [r15], '"'
    add r15, 1
    ; record the extent in attr_off/attr_len of the node
    mov rax, [attr_cur]
    mov [attr_off + rbx*4], eax
    sub r15, r11                ; length written
    mov [attr_len + rbx*4], r15d
    add [attr_cur], r15
.attr_done:
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; parse_expr(rdi = ptr, rsi = len, rdx = node idx) -> rax = 0 ok, -1 err
; expr := <state>[.<field>]<op>[<operand>]
;   op: ++ | -- | = <int|true|false> | += <int> | -= <int>
; Registers an action (A_WIDGET = node idx; the emit pass resolves it to
; the button view record).
; ----------------------------------------------------------------------
parse_expr:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; expr ptr (in_buf offset)
    mov r13, rsi                ; expr len
    mov r14, rdx                ; node idx
    xor ebx, ebx                ; 0 = no dot yet
    ; ---- state name: relative pos until '.' or an operator ----
    xor r15, r15
.pe_scan_name:
    cmp r15, r13
    jge .err
    mov al, [in_buf + r12 + r15]
    cmp al, '.'
    je .pe_dot
    cmp al, '+'
    je .pe_op
    cmp al, '-'
    je .pe_op
    cmp al, '='
    je .pe_op
    cmp al, ' '
    je .pe_op
    cmp al, 9
    je .pe_op
    inc r15
    jmp .pe_scan_name
.pe_dot:
    mov rbx, r15                ; position of the '.'
    inc r15
    mov r11, r15                ; field start (relative; r11 survives the
                                ; strncmp inside state_lookup - r8 doesn't!)
.pe_scan_field:
    cmp r15, r13
    jge .err
    mov al, [in_buf + r12 + r15]
    cmp al, '+'
    je .pe_op
    cmp al, '-'
    je .pe_op
    cmp al, '='
    je .pe_op
    cmp al, ' '
    je .pe_op
    cmp al, 9
    je .pe_op
    inc r15
    jmp .pe_scan_field
.pe_op:
    ; name = [0, rbx) if dot else [0, r15); field = [r11, r15) if dot.
    mov r10, r15                ; operator position (relative)
    ; state lookup
    mov rdi, r12
    mov rsi, r15
    test rbx, rbx
    jz .pe_no_field
    mov rsi, rbx
.pe_no_field:
    ; rsi = name len (relative)
    call state_lookup
    cmp rax, -1
    je .err
    mov r9d, eax                ; state idx
    ; field idx
    test rbx, rbx
    jz .pe_no_field2
    mov rdi, r11
    add rdi, r12                ; field ptr (absolute in_buf offset)
    mov rsi, r10
    sub rsi, r11                ; field len
    imul rax, r9, STATE_ENTRY
    mov edx, [state_tab + rax + S_TYPE_IDX]
    call field_lookup
    cmp rax, -1
    je .err
    mov r11d, eax               ; field idx (field start no longer needed)
    jmp .pe_have_field
.pe_no_field2:
    mov r11d, -1                ; no field
.pe_have_field:
    ; ---- operator (absolute in_buf offsets) ----
    lea rdi, [r10 + r12]        ; operator position
    lea rsi, [r12 + r13]        ; expr end
    call parse_op               ; rax = op, rbx = operand pos (absolute)
    cmp rax, -1
    je .err
    mov r15d, eax               ; op
    sub rbx, r12                ; operand pos (relative to the expr)
    ; ---- field kind ----
    imul rax, r9, STATE_ENTRY
    lea r8, [state_tab + rax]
    mov ecx, [r8 + S_KIND]
    cmp r11d, -1
    je .pe_have_kind
    mov eax, [r8 + S_TYPE_IDX]
    imul rax, rax, TYPE_ENTRY
    mov edx, [type_tab + rax + T_FIELDS_IDX]
    imul rax, r11, FIELD_ENTRY
    mov ecx, [field_tab + rdx + rax + F_KIND]
.pe_have_kind:
    cmp ecx, K_STR
    je .err_strasg
    cmp ecx, K_BOOL
    jne .pe_kind_int
    ; bool: only '= true/false' -> SET_TRUE/SET_FALSE
    cmp r15d, OP_SET
    jne .err
    lea rdi, [r12 + rbx]        ; operand ptr (absolute)
    lea rsi, [r12 + r13]        ; expr end
    call trim_eol
    call skip_operand_ws
    mov r8, rsi
    sub r8, rdi                 ; operand len
    mov rsi, r8
    call parse_scalar_value
    cmp rax, -1
    je .err
    test rax, rax
    jz .pe_false
    mov r15d, OP_SET_TRUE
    mov ebx, 1
    jmp .pe_store
.pe_false:
    mov r15d, OP_SET_FALSE
    xor ebx, ebx
    jmp .pe_store
.pe_kind_int:
    ; int: INC/DEC take no operand
    cmp r15d, OP_INC
    je .pe_store
    cmp r15d, OP_DEC
    je .pe_store
    ; SET/ADD/SUB: parse the operand as int
    lea rdi, [r12 + rbx]        ; operand ptr (absolute)
    lea rsi, [r12 + r13]        ; expr end
    call trim_eol
    call skip_operand_ws
    mov r8, rsi
    sub r8, rdi                 ; operand len
    lea rdi, [in_buf + rdi]     ; ptr
    mov rsi, r8
    call atoi_n
    mov ebx, eax
    ; fallthrough
.pe_store:
    cmp qword [action_count], MAX_ACTIONS
    jge .err
    mov rax, [action_count]
    imul rax, rax, ACTION_ENTRY
    lea rdi, [action_tab + rax]
    mov [rdi + A_WIDGET], r14d
    mov [rdi + A_STATE], r9d
    mov [rdi + A_FIELD], r11d
    mov [rdi + A_OP], r15d
    mov [rdi + A_OPERAND], ebx
    inc qword [action_count]
    xor eax, eax
    jmp .done
.err:
    lea rdi, [msg_expr]
    mov rsi, msg_expr_len
    call die
.err_strasg:
    lea rdi, [msg_strasg]
    mov rsi, msg_strasg_len
    call die
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; parse_op(rdi = op position, rsi = expr end) -> rax = op, rbx = operand
; position. Ops: ++ -- = += -=
; ----------------------------------------------------------------------
parse_op:
    ; skip ws (the name scan stops at a space; the operator follows)
.pop_ws:
    mov al, [in_buf + rdi]
    cmp al, ' '
    je .pop_ws_inc
    cmp al, 9
    jne .pop_have
.pop_ws_inc:
    inc rdi
    jmp .pop_ws
.pop_have:
    mov al, [in_buf + rdi]
    cmp al, '+'
    je .plus
    cmp al, '-'
    je .minus
    ; '='
    mov rax, OP_SET
    lea rbx, [rdi + 1]
    ret
.plus:
    lea rcx, [rdi + 1]
    cmp rcx, rsi
    jge .err
    mov al, [in_buf + rcx]
    cmp al, '+'
    je .inc
    cmp al, '='
    je .add
    jmp .err
.inc:
    mov rax, OP_INC
    lea rbx, [rdi + 2]
    ret
.add:
    mov rax, OP_ADD
    lea rbx, [rdi + 2]
    ret
.minus:
    lea rcx, [rdi + 1]
    cmp rcx, rsi
    jge .err
    mov al, [in_buf + rcx]
    cmp al, '-'
    je .dec
    cmp al, '='
    je .sub
    jmp .err
.dec:
    mov rax, OP_DEC
    lea rbx, [rdi + 2]
    ret
.sub:
    mov rax, OP_SUB
    lea rbx, [rdi + 2]
    ret
.err:
    mov rax, -1
    ret

; ----------------------------------------------------------------------
; skip_operand_ws(rdi = ptr (absolute in_buf offset), rsi = end) -> rdi
; adjusted past leading spaces/tabs (absolute). Errors on empty.
; ----------------------------------------------------------------------
skip_operand_ws:
.sow_ws:
    cmp rdi, rsi
    jge .err
    mov al, [in_buf + rdi]
    cmp al, ' '
    je .sow_inc
    cmp al, 9
    jne .done
.sow_inc:
    inc rdi
    jmp .sow_ws
.err:
    mov rdi, rsi
.done:
    ret

; ----------------------------------------------------------------------
; trim_eol(rdi = ptr, rsi = end) -> rsi adjusted (trailing \r removed)
; ----------------------------------------------------------------------
trim_eol:
    cmp rsi, rdi
    jle .done
    mov al, [in_buf + rsi - 1]
    cmp al, 13
    jne .done
    dec rsi
    jmp trim_eol
.done:
    ret

; ----------------------------------------------------------------------
; state_value_copy(state_idx, field_idx, dst) -> rax = len
; Writes the INITIAL value of a state field, formatted, to dst:
; int -> decimal digits, bool -> "true"/"false", string -> raw bytes.
; Used by serialize to resolve interpolations for the SSR blob.
; ----------------------------------------------------------------------
state_value_copy:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; state idx
    mov r13, rsi                ; field idx (-1 = scalar)
    mov r14, rdx                ; dst
    imul rax, r12, STATE_ENTRY
    lea rbx, [state_tab + rax]
    mov r15d, [rbx + S_DATA_OFF]
    mov ecx, [rbx + S_KIND]
    cmp r13d, -1
    je .have_kind
    ; object field: kind from the field table
    mov eax, [rbx + S_TYPE_IDX]
    imul rax, rax, TYPE_ENTRY
    mov edx, [type_tab + rax + T_FIELDS_IDX]
    imul rax, r13, FIELD_ENTRY
    lea rax, [field_tab + rdx + rax]
    mov ecx, [rax + F_KIND]
    add r15d, [rax + F_OFFSET]
.have_kind:
    mov r13, r14                ; dst original (r13 is free now; field idx
                                ; was consumed above) - itoa clobbers rdx
    cmp ecx, K_STR
    je .str
    ; int/bool
    cmp ecx, K_BOOL
    jne .int
    mov eax, [state_data + r15]
    test eax, eax
    jz .false
    lea rdi, [s_true]
    jmp .copy_str_lit
.false:
    lea rdi, [s_false]
.copy_str_lit:
    ; copy literal (rdi) to dst
    mov r15, rdi
.csl:
    mov al, [r15]
    test al, al
    jz .csl_done
    mov [r14], al
    inc r14
    inc r15
    jmp .csl
.csl_done:
    mov rax, r14
    sub rax, r13                ; len
    jmp .done
.int:
    mov eax, [state_data + r15]
    mov rdi, rax
    lea rsi, [itoa_buf]
    call itoa
    ; copy digits
    mov r15, rax
.cp_digits:
    mov al, [r15]
    test al, al
    jz .cp_done
    mov [r14], al
    inc r14
    inc r15
    jmp .cp_digits
.cp_done:
    mov rax, r14
    sub rax, r13
    jmp .done
.str:
    ; string: field holds a state_str_buf offset
    mov eax, [state_data + r15]
    lea r15, [state_str_buf + rax]
.cp_str:
    mov al, [r15]
    test al, al
    jz .cp_str_done
    mov [r14], al
    inc r14
    inc r15
    jmp .cp_str
.cp_str_done:
    mov rax, r14
    sub rax, r13
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; state_field_addr(state_idx, field_idx) -> rax = offset into state_data
; ----------------------------------------------------------------------
state_field_addr:
    imul rcx, rdi, STATE_ENTRY
    lea rax, [state_tab + rcx]
    mov eax, [rax + S_DATA_OFF]
    cmp esi, -1                 ; 32-bit compare (mov esi zero-extends)
    je .done
    imul rcx, rdi, STATE_ENTRY
    mov edx, [state_tab + rcx + S_TYPE_IDX]
    imul rcx, rdx, TYPE_ENTRY
    mov edx, [type_tab + rcx + T_FIELDS_IDX]
    imul rcx, rsi, FIELD_ENTRY
    add eax, [field_tab + rdx + rcx + F_OFFSET]
.done:
    ret

; ----------------------------------------------------------------------
; dyn_register(node_idx, state_idx, field_idx, prefix_len, suffix_off,
;              suffix_len) -> rax = 0 ok, -1 limit
; ----------------------------------------------------------------------
dyn_register:
    push rbx
    cmp qword [dyn_count], MAX_DYN_TEXTS
    jge .full
    mov rax, [dyn_count]
    imul rax, rax, DYN_ENTRY
    lea rbx, [dyn_tab + rax]
    mov [rbx + D_NODE], edi
    mov [rbx + D_STATE], esi
    mov [rbx + D_FIELD], edx
    mov [rbx + D_PREFIX_LEN], ecx
    mov [rbx + D_SUFFIX_OFF], r8d
    mov [rbx + D_SUFFIX_LEN], r9d
    inc qword [dyn_count]
    xor eax, eax
    jmp .done
.full:
    mov rax, -1
.done:
    pop rbx
    ret

; ----------------------------------------------------------------------
; check_interp(rdi = node idx, rsi = text ptr (in_buf offset), rdx = len)
; Detects {state} / {state.field} in a text widget and registers the dyn
; text. Ignores {slug} (the glue substitutes it). Max 1 interpolation
; per text (msg_dyn otherwise).
; ----------------------------------------------------------------------
check_interp:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; node idx
    mov r13, rsi                ; text ptr
    mov r14, rdx                ; text len
    xor r15, r15
.ci_scan:
    cmp r15, r14
    jge .done
    mov al, [in_buf + r13 + r15]
    cmp al, '{'
    je .ci_open
    inc r15
    jmp .ci_scan
.ci_open:
    mov rbx, r15                ; prefix_len
    inc r15
    lea r9, [r13 + r15]         ; name ptr (in_buf offset) - r9 survives
                                ; strncmp (r8b is clobbered by it!)
    mov r10, r15                ; name end pos
.ci_name:
    cmp r10, r14
    jge .err
    mov al, [in_buf + r13 + r10]
    cmp al, '}'
    je .ci_nodot
    cmp al, '.'
    je .ci_dot
    inc r10
    jmp .ci_name
.ci_nodot:
    ; {slug}? -> ignore (glue substitutes it at render time)
    mov rdi, r10
    sub rdi, r15
    cmp rdi, 4
    jne .ci_lookup
    lea rdi, [in_buf + r9]
    lea rsi, [s_slug]
    mov rdx, 4
    call strncmp
    test rax, rax
    jz .done
.ci_lookup:
    mov rdi, r9                 ; name ptr (in_buf offset)
    mov rsi, r10
    sub rsi, r15
    call state_lookup
    cmp rax, -1
    je .err
    mov r8d, eax                ; state idx
    mov r9d, -1                 ; field idx
    mov r15d, r10d              ; close_pos
    jmp .ci_register
.ci_dot:
    inc r10
    mov r11, r10                ; field start pos
.ci_field:
    cmp r10, r14
    jge .err
    mov al, [in_buf + r13 + r10]
    cmp al, '}'
    je .ci_fclose
    inc r10
    jmp .ci_field
.ci_fclose:
    ; {slug.field}? ignore
    mov rdi, r11
    dec rdi
    sub rdi, r15                ; name len
    cmp rdi, 4
    jne .ci_flookup
    lea rdi, [in_buf + r9]
    lea rsi, [s_slug]
    mov rdx, 4
    call strncmp
    test rax, rax
    jz .done
.ci_flookup:
    mov rdi, r9                 ; name ptr (in_buf offset)
    mov rsi, r11
    dec rsi
    sub rsi, r15                ; name len
    call state_lookup
    cmp rax, -1
    je .err
    mov r8d, eax                ; state idx
    push r8                     ; field_lookup clobbers r8 (strncmp uses
                                ; r8b) - save the state idx on the stack
    ; field lookup
    lea rdi, [r13 + r11]        ; field ptr (in_buf offset)
    mov rsi, r10
    sub rsi, r11                ; field len
    imul rax, r8, STATE_ENTRY
    mov edx, [state_tab + rax + S_TYPE_IDX]
    call field_lookup
    cmp rax, -1
    je .err
    mov r9d, eax                ; field idx
    mov r15d, r10d              ; close_pos
    pop r8                      ; restore the state idx
.ci_register:
    ; 2nd interpolation in the suffix?
    lea rax, [r13 + r15 + 1]    ; suffix start
    mov ecx, r14d
    sub ecx, r15d
    dec ecx                     ; suffix len
    xor r11d, r11d
.ci_suf:
    cmp r11, rcx
    jge .ci_suf_ok
    cmp byte [in_buf + rax + r11], '{'
    je .err_dyn
    inc r11
    jmp .ci_suf
.ci_suf_ok:
    ; dyn_register(node, state, field, prefix_len, suffix_off, suffix_len)
    mov rdi, r12
    mov rsi, r8
    mov rdx, r9
    mov rcx, rbx
    lea r8, [r15 + 1]           ; suffix_off RELATIVE to the text start
                                ; (emit adds N_TEXT_PTR to it!)
    mov r9, r14
    sub r9, r15
    dec r9                      ; suffix_len
    call dyn_register
    cmp rax, -1
    je .err_dyn
    jmp .done
.err:
    lea rdi, [msg_fieldmiss]
    mov rsi, msg_fieldmiss_len
    call err_msg_token
.err_dyn:
    lea rdi, [msg_dyn]
    mov rsi, msg_dyn_len
    call die
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; dyn_find(rdi = node idx) -> rax = dyn idx or -1
; ----------------------------------------------------------------------
dyn_find:
    push rbx
    xor rbx, rbx
.df_loop:
    cmp rbx, [dyn_count]
    jge .none
    imul rax, rbx, DYN_ENTRY
    cmp [dyn_tab + rax + D_NODE], edi
    je .found
    inc rbx
    jmp .df_loop
.found:
    mov rax, rbx
    jmp .done
.none:
    mov rax, -1
.done:
    pop rbx
    ret

; ----------------------------------------------------------------------
; err_msg_token(rdi = msg prefix ptr, rsi = prefix len) - prints the
; prefix + newline to stderr (the token itself is in the message).
; ----------------------------------------------------------------------
err_msg_token:
    push r12
    mov r12, rdi
    mov rax, SYS_write
    mov rdx, rsi
    mov rsi, r12
    mov rdi, 2
    syscall
    mov rax, SYS_write
    mov rdi, 2
    lea rsi, [msg_nl]
    mov rdx, 1
    syscall
    pop r12
    ret
