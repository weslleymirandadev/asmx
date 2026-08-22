; =============================================================================
; expand.asm - @@ component expansion (src/components/*.asx, {param} args)
; =============================================================================
;
; A line like  @@ <name> key="value" ...  inside an @ DSL block is
; replaced at compile time by the <name>: block of src/components/<name>.asx:
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
    ; children on the next line? (rax > 0 = extra bytes beyond the @@ line)
    test rax, rax
    jz .no_chl_ext
    add r15, rax
.no_chl_ext:
    ; the component MUST have been @import'ed first: @@Name looks the
    ; name up in the import registry (no implicit src/components/
    ; lookup). On a hit, import_path/import_path_len are filled with the
    ; registered path and the file is loaded into comp_buf.
    call lookup_import         ; rax = index or -1
    cmp rax, -1
    je .not_imported
    ; copy the registered path into import_path and load the file
    mov rdi, rax
    call load_imported
    jmp .imp_loaded
.not_imported:
    lea rdi, [msg_import_req]
    mov rsi, msg_import_req_len
    call die
.imp_loaded:
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
    ; ':' (children) also ends the name: "@@Card:" -> name "Card",
    ; the ':' belongs to the children syntax, not the component name.
    mov r14, r12
.sn:
    cmp r14, r13
    jge .sn_done
    mov al, [r14]
    cmp al, ' '
    je .sn_done
    cmp al, 9
    je .sn_done
    cmp al, ':'
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
    ; ":" -> {children} content ("conteúdo" after the colon)
    cmp byte [r15], ':'
    je .children
    ; key = [r15, r8) until '=' (or ':' for a TYPED prop: name: type)
    mov r8, r15
.ks:
    cmp r8, r13
    jge .err
    cmp byte [r8], '='
    je .ks_done
    cmp byte [r8], ':'
    je .ks_typed
    inc r8
    jmp .ks
.ks_typed:
    ; typed prop: <state>: <type_name> - the expand pass runs BEFORE the
    ; states are registered, so we only record {state_ptr, state_len,
    ; type_ptr, type_len} here; validate_typed_props() checks it after
    ; compile_block (when state_lookup works).
    mov r10, r15                ; state name ptr (in_buf offset)
    mov r11, r8
    sub r11, r15                ; state name len
    ; type name: [r8+1, space)
    lea r12, [r8 + 1]
.kt_ws:
    cmp r12, r13
    jge .err
    mov al, [r12]
    cmp al, ' '
    je .kt_ws_inc
    cmp al, 9
    jne .kt_type
.kt_ws_inc:
    inc r12
    jmp .kt_ws
.kt_type:
    mov r14, r12
.kt_scan:
    cmp r14, r13
    jge .kt_have
    mov al, [r14]
    cmp al, ' '
    je .kt_have
    cmp al, 9
    je .kt_have
    inc r14
    jmp .kt_scan
.kt_have:
    cmp qword [tp_prop_count], MAX_TYPED_PROPS
    jge .err
    mov r9d, r14d
    sub r9d, r12d               ; type name len (r9 survives the loads below)
    mov rax, [tp_prop_count]
    imul rax, rax, 136
    lea rdx, [tp_props + rax]
    ; copy the state name (r10 ptr, r11 len) - the @@ splice will
    ; overwrite the line these pointers reference
    mov r15, r11
    xor r8, r8
.tc1:
    cmp r8, r15
    jge .tc1_done
    mov cl, [r10 + r8]
    mov [rdx + r8], cl
    inc r8
    jmp .tc1
.tc1_done:
    mov [rdx + 64], r15d        ; state name len
    ; copy the type name (r12 ptr, r9 len)
    xor r8, r8
.tc2:
    cmp r8, r9
    jge .tc2_done
    mov cl, [r12 + r8]
    mov [rdx + 68 + r8], cl
    inc r8
    jmp .tc2
.tc2_done:
    mov [rdx + 132], r9d        ; type name len
    inc qword [tp_prop_count]
    ; continue after the type name
    mov r15, r14
    jmp .arg_loop
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
    xor rax, rax                ; 0 = no next-line children consumed
    pop r15
    pop r14
    pop r13
    pop r12
    ret
.children:
    ; "{children}" content: ':' then "text" - stored as a regular
    ; arg_list entry with key "children" (the copy_subst placeholder
    ; lookup finds it like any other {param})
    inc r15                     ; skip ':'
.ch_skip:
    cmp r15, r13
    jge .ch_next_line           ; ':' at line end -> children on the next line
    mov al, [r15]
    cmp al, ' '
    je .ch_inc
    cmp al, 9
    jne .ch_q
.ch_inc:
    inc r15
    jmp .ch_skip
.ch_q:
    cmp byte [r15], '"'
    jne .err
    inc r15
    mov r8, r15                 ; value start
.ch_vs:
    cmp r8, r13
    jge .err
    cmp byte [r8], '"'
    je .ch_done
    inc r8
    jmp .ch_vs
.ch_done:
    mov rax, [arg_count]
    cmp rax, MAX_ARGS
    jge .err
    imul rcx, rax, ARG_ENTRY_SIZE
    lea r10, [arg_list + rcx]
    lea r11, [s_children]
    mov [r10], r11              ; key ptr
    mov qword [r10 + 8], 8      ; key len ("children")
    mov [r10 + 16], r15         ; val ptr
    mov r11, r8
    sub r11, r15
    mov [r10 + 24], r11         ; val len
    inc qword [arg_count]
    jmp .args_done
.ch_next_line:
    ; ':' at the END of the @@ line, no inline text:
    ;   @@card ...:
    ;       "children text"
    ; The next line (if it is a "..." text line) becomes {children}.
    ; Returns rax = offset of the end of that line (0 = nothing consumed),
    ; so expand_block's splice covers both lines.
    cmp byte [r13], 10
    jne .chl_none               ; no newline after ':' -> nothing to grab
    lea r14, [r13 + 1]          ; next line start
    mov rax, [in_len]
    lea rdx, [in_buf + rax]     ; file end ptr
    cmp r14, rdx
    jge .chl_none
.chl_skip:
    cmp r14, rdx
    jge .chl_none
    mov al, [r14]
    cmp al, ' '
    je .chl_inc
    cmp al, 9
    jne .chl_q
.chl_inc:
    inc r14
    jmp .chl_skip
.chl_q:
    cmp byte [r14], '"'
    jne .chl_none               ; next line is not a text line
    inc r14
    mov r15, r14                ; value start (reuse the args cursor)
.chl_vs:
    cmp r14, rdx
    jge .err
    cmp byte [r14], '"'
    je .chl_done
    inc r14
    jmp .chl_vs
.chl_done:
    ; entry: key "children", val [r15, r14)
    mov rax, [arg_count]
    cmp rax, MAX_ARGS
    jge .err
    imul rcx, rax, ARG_ENTRY_SIZE
    lea r10, [arg_list + rcx]
    lea r11, [s_children]
    mov [r10], r11              ; key ptr
    mov qword [r10 + 8], 8      ; key len ("children")
    mov [r10 + 16], r15         ; val ptr
    mov r11, r14
    sub r11, r15
    mov [r10 + 24], r11         ; val len
    inc qword [arg_count]
    ; end of the children line = the new splice end
    inc r14                     ; skip the closing quote
.chl_end:
    cmp r14, rdx
    jge .chl_line_end
    cmp byte [r14], 10
    je .chl_line_end
    inc r14
    jmp .chl_end
.chl_line_end:
    mov rax, r14
    sub rax, r13                ; offset relative to the '@@' line end
    pop r15
    pop r14
    pop r13
    pop r12
    ret
.chl_none:
    xor rax, rax
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
; check_import_prefix(rdi = line start, rsi = line end ptr)
; -> rax = 1 if the line starts with the "@import " keyword (7 chars +
; a space/tab), else 0. The line must NOT be "@@" (handled separately).
; ----------------------------------------------------------------------
check_import_prefix:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    ; need at least 8 chars ("@import" + separator)
    lea r8, [r12 + 7]
    cmp r8, r13
    jae .no
    lea rdi, [r12]
    lea rsi, [s_import]
    mov rdx, 7
    call strncmp
    test rax, rax
    jnz .no
    ; separator must be space or tab (so "@imported" does not match)
    mov al, [r12 + 7]
    cmp al, ' '
    je .yes
    cmp al, 9
    je .yes
    jmp .no
.yes:
    mov rax, 1
    jmp .done
.no:
    xor rax, rax
.done:
    pop r13
    pop r12
    ret

; ----------------------------------------------------------------------
; parse_import(rdi = ptr after "@import ", rsi = line end ptr)
; Parses "<Name> from "path"" into comp_name/comp_name_len and
; import_path/import_path_len. The path may use the "@/" alias (= src/);
; it is kept verbatim (the alias is resolved in load_component_import).
; ----------------------------------------------------------------------
parse_import:
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; cur (after "@import ")
    mov r13, rsi                ; line end
    ; --- skip leading spaces/tabs (the separator after "@import") ---
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
    jge .err
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
    ; --- expect "from" ---
    mov r15, r14
.fs:
    cmp r15, r13
    jge .err
    mov al, [r15]
    cmp al, ' '
    je .f_inc
    cmp al, 9
    jne .f_have
.f_inc:
    inc r15
    jmp .fs
.f_have:
    lea rdi, [r15]
    lea rsi, [s_from]
    mov rdx, 4
    call strncmp
    test rax, rax
    jnz .err
    add r15, 4
    ; --- expect '"' ---
.qt:
    cmp r15, r13
    jge .err
    mov al, [r15]
    cmp al, ' '
    je .q_inc
    cmp al, 9
    jne .q_have
.q_inc:
    inc r15
    jmp .qt
.q_have:
    cmp byte [r15], '"'
    jne .err
    inc r15                     ; skip the opening quote
    ; --- path: [r15, r16) until the closing quote ---
    mov r14, r15
.ps:
    cmp r14, r13
    jge .err
    cmp byte [r14], '"'
    je .ps_done
    inc r14
    jmp .ps
.ps_done:
    mov rax, r14
    sub rax, r15
    mov [import_path_len], rax
    cmp rax, 512
    jge .err
    xor r8, r8
.ip:
    cmp r8, rax
    jge .ip_done
    mov cl, [r15 + r8]
    mov [import_path + r8], cl
    inc r8
    jmp .ip
.ip_done:
    xor rax, rax
    jmp .done
.err:
    lea rdi, [msg_import_bad]
    mov rsi, msg_import_bad_len
    call die
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; ----------------------------------------------------------------------
; load_component_import - resolves import_path (the "@/" alias becomes
; "src/") into comp_path and reads the file into comp_buf. Appends
; ".asx" unless the path already ends with it.
; ----------------------------------------------------------------------
load_component_import:
    push r12
    push r13
    push r14
    push r15
    ; comp_path = "" (reset)
    lea rdi, [comp_path]
    mov byte [rdi], 0
    ; path ptr/len: skip the "@/" alias if present
    lea r12, [import_path]
    mov r13, [import_path_len]
    cmp r13, 2
    jb .no_alias
    cmp byte [r12], '@'
    jne .no_alias
    cmp byte [r12 + 1], '/'
    jne .no_alias
    add r12, 2
    sub r13, 2
.no_alias:
    ; if the path starts with "/", it is relative to src/ as well
    ; (e.g. "@/components/Header" -> "src/components/Header.asx")
    lea rdi, [comp_path]
    lea rsi, [s_src_prefix]
    call strcpy_l               ; comp_path = "src/"
    ; append the path
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call memcpy
    ; append ".asx" unless the path already ends with it
    lea r15, [comp_path + 4 + r13]  ; end of "src/" + path
    cmp r13, 4
    jb .add_ext
    lea rdi, [r15 - 4]
    lea rsi, [s_dot_asx]
    mov rdx, 4
    call strncmp
    test rax, rax
    jz .have_ext
.add_ext:
    mov byte [r15], '.'
    mov byte [r15 + 1], 'a'
    mov byte [r15 + 2], 's'
    mov byte [r15 + 3], 'x'
    mov byte [r15 + 4], 0
    jmp .read
.have_ext:
    mov byte [r15], 0
.read:
    lea rdi, [comp_path]
    lea rsi, [comp_buf]
    mov rdx, IN_CAP
    call read_file_to
    test rax, rax
    js .err
    mov [comp_len], rax
    pop r15
    pop r14
    pop r13
    pop r12
    ret
.err:
    lea rdi, [msg_import_missing]
    mov rsi, msg_import_missing_len
    call die

; ----------------------------------------------------------------------
; register_import - appends the current import (comp_name/comp_name_len +
; import_path/import_path_len) to the import registry. Called after
; parse_import, BEFORE load_component_import. Dies if MAX_IMPORTS is hit.
; ----------------------------------------------------------------------
register_import:
    push rbx
    push r12
    push r13
    push r14
    mov rax, [import_count]
    cmp rax, MAX_IMPORTS
    jge .full
    imul r12, rax, 64           ; offset into import_keys
    imul r13, rax, 512          ; offset into import_paths
    ; copy the name (comp_name, comp_name_len) into import_keys + r12
    mov r14, [comp_name_len]
    cmp r14, 63
    jae .name_long
    xor rbx, rbx
.cp1:
    cmp rbx, r14
    jge .cp1_done
    mov cl, [comp_name + rbx]
    mov [import_keys + r12 + rbx], cl
    inc rbx
    jmp .cp1
.cp1_done:
    mov byte [import_keys + r12 + rbx], 0
    ; copy the path (import_path, import_path_len) into import_paths + r13
    mov r14, [import_path_len]
    cmp r14, 511
    jae .path_long
    xor rbx, rbx
.cp2:
    cmp rbx, r14
    jge .cp2_done
    mov cl, [import_path + rbx]
    mov [import_paths + r13 + rbx], cl
    inc rbx
    jmp .cp2
.cp2_done:
    mov byte [import_paths + r13 + rbx], 0
    inc qword [import_count]
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.full:
    lea rdi, [msg_import_max]
    mov rsi, msg_import_max_len
    call die
.name_long:
    lea rdi, [msg_import_name]
    mov rsi, msg_import_name_len
    call die
.path_long:
    lea rdi, [msg_import_path]
    mov rsi, msg_import_path_len
    call die

; ----------------------------------------------------------------------
; lookup_import -> rax = index of the import whose key matches
; comp_name/comp_name_len, or -1. Keys are null-terminated; the caller's
; comp_name is a length-delimited buffer (no null needed).
; ----------------------------------------------------------------------
lookup_import:
    push rbx
    push r12
    push r13
    push r14
    xor r12, r12                ; idx
.loop:
    cmp r12, [import_count]
    jge .none
    ; compare import_keys[idx] against comp_name
    mov r14, [comp_name_len]
    xor r13, r13
.cmp:
    cmp r13, r14
    jge .len_done
    mov al, [comp_name + r13]
    imul r10, r12, 64
    add r10, r13
    mov bl, [import_keys + r10]
    cmp al, bl
    jne .next
    inc r13
    jmp .cmp
.len_done:
    ; all comp_name chars matched: key must end here (null)
    imul r10, r12, 64
    add r10, r13
    cmp byte [import_keys + r10], 0
    jne .next
    mov rax, r12
    jmp .done
.next:
    inc r12
    jmp .loop
.none:
    mov rax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; load_imported(rdi = index) - copies import_paths[index] into
; import_path/import_path_len and loads the file into comp_buf (same as
; load_component_import, but the path comes from the registry).
; ----------------------------------------------------------------------
load_imported:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; index
    ; copy import_paths[index] -> import_path (strcpy_l semantics)
    lea rdi, [import_path]
    imul r10, r12, 512
    lea rsi, [import_paths + r10]
    call strcpy_l               ; rax = end (null copied)
    ; import_path_len = len (strcpy_l returns dst + len where the len
    ; includes the null - recompute as strlen)
    lea rdi, [import_path]
    call strlen
    mov [import_path_len], rax
    ; delegate to load_component_import: it resolves the "@/" alias,
    ; appends ".asx" if needed and reads the file into comp_buf.
    ; (The registered path may still carry the "@/" alias verbatim.)
    call load_component_import
    ; the component file may itself start with top-of-file @import lines
    ; (nested components, %include-style): register them so inner @@Name
    ; resolves during the build_expand below.
    ; NOTE: scan_component_imports clobbers comp_name/comp_name_len via
    ; parse_import - save/restore them (find_comp_block compares the
    ; component label against comp_name right after this returns).
    push qword [comp_name_len]
    push qword [comp_name]
    push qword [comp_name + 8]
    push qword [comp_name + 16]
    push qword [comp_name + 24]
    push qword [comp_name + 32]
    push qword [comp_name + 40]
    push qword [comp_name + 48]
    push qword [comp_name + 56]
    call scan_component_imports
    pop qword [comp_name + 56]
    pop qword [comp_name + 48]
    pop qword [comp_name + 40]
    pop qword [comp_name + 32]
    pop qword [comp_name + 24]
    pop qword [comp_name + 16]
    pop qword [comp_name + 8]
    pop qword [comp_name]
    pop qword [comp_name_len]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; scan_component_imports - walks comp_buf line by line at column 0 and
; registers every "@import Name from "@/path"" it finds, stopping at
; the first non-import line (the component's own label). The registered
; paths stay in the global registry for the whole compile (nested
; components, %include-style).
; ----------------------------------------------------------------------
scan_component_imports:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r12, r12
.loop:
    mov r13, [comp_len]
    cmp r12, r13
    jge .done
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
    ; column-0 "@import "?
    cmp byte [comp_buf + r12], '@'
    jne .done
    lea rdi, [comp_buf + r12]
    lea rsi, [comp_buf + r14]
    call check_import_prefix
    test rax, rax
    jz .done
    lea rdi, [comp_buf + r12 + 7]
    lea rsi, [comp_buf + r14]
    call parse_import
    call register_import
    ; next line
    mov r12, r14
    cmp r12, r13
    jge .done
    cmp byte [comp_buf + r12], 10
    jne .done
    inc r12
    jmp .loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

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
    cmp al, '{'                 ; {children} placeholder line
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
    ; {children}? -> inline (inside quotes) substitutes the raw value;
    ; on its own line it becomes a @p: "value" label line
    cmp rsi, 8
    jne .not_ch
    push rdi
    lea rsi, [s_children]
    mov rdx, 8
    call strncmp
    pop rdi
    test rax, rax
    jnz .not_ch
    ; is there anything but whitespace before the { on this line?
    ; (line start = r13's saved value is gone, re-scan from the line
    ; start: walk back from r12 to the previous newline)
    mov r10, r12
.bk:
    cmp r10, 0
    je .pure_line
    mov al, [comp_buf + r10 - 1]
    cmp al, 10
    je .have_line_start
    cmp al, 13
    je .have_line_start
    dec r10
    jmp .bk
.have_line_start:
    mov r11, r10
    jmp .scan_ws
.pure_line:
    xor r11, r11
.scan_ws:
    cmp r11, r12
    jge .label_line            ; only whitespace before { -> label line
    mov al, [comp_buf + r11]
    cmp al, ' '
    je .ws
    cmp al, 9
    je .ws
    jmp .inline_ch
.ws:
    inc r11
    jmp .scan_ws
.label_line:
    mov rsi, 8                  ; rsi died in the strncmp - it is "children"
    call arg_lookup             ; rax = val ptr, rdx = val len
    cmp rax, -1
    je .vcc_none                ; no children given - the line vanishes
    mov r11, rax                ; val ptr (rax dies in the writes below)
    mov rbx, rdx
    mov r9, [expand_len]
    ; expand to a label line:  @p: "value"
    mov dword [expand_buf + r9], 0x203A7040   ; '@' 'p' ':' ' '
    add qword [expand_len], 4
    mov rax, [expand_len]
    mov byte [expand_buf + rax], '"'
    inc qword [expand_len]
    xor r8, r8
.vcc:
    cmp r8, rbx
    jge .vcc_done
    mov cl, [r11 + r8]
    mov r10, [expand_len]
    mov [expand_buf + r10], cl
    inc qword [expand_len]
    inc r8
    jmp .vcc
.vcc_done:
    mov rax, [expand_len]
    mov byte [expand_buf + rax], '"'
    inc qword [expand_len]
    mov r12, r14
    inc r12                     ; skip '}'
    jmp .loop
.inline_ch:
    ; inline {children}: substitute the raw value (the surrounding
    ; quotes are already in the template line)
    mov rsi, 8
    call arg_lookup
    cmp rax, -1
    je .vcc_none
    mov r11, rax
    mov rbx, rdx
    xor r8, r8
.inl:
    cmp r8, rbx
    jge .inl_done
    mov cl, [r11 + r8]
    mov r10, [expand_len]
    mov [expand_buf + r10], cl
    inc qword [expand_len]
    inc r8
    jmp .inl
.inl_done:
    mov r12, r14
    inc r12                     ; skip '}'
    jmp .loop
.vcc_none:
    mov r12, r14                ; {children} without a value: the line
    inc r12                     ; vanishes (skip past '}')
    jmp .loop
.not_ch:
    mov rsi, r14                ; name len (rsi died in the strncmp above)
    sub rsi, r12
    dec rsi
    call arg_lookup             ; rax = val ptr, rdx = val len
    cmp rax, -1
    je .state_ph
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
.state_ph:
    ; {state} / {state.field} / any unknown placeholder: preserve it
    ; literally - the expand pass runs BEFORE the states are registered,
    ; so we can't look them up here; check_interp validates the expanded
    ; text later (with the states available)
    mov r8, r14
    inc r8                       ; end (after '}')
    mov r9, [expand_len]
.st_cp:
    cmp r12, r8
    jge .st_cp_done
    mov cl, [comp_buf + r12]
    mov [expand_buf + r9], cl
    inc r9
    inc r12
    jmp .st_cp
.st_cp_done:
    mov [expand_len], r9
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
    ; move [src, in_len) to [line_start + expand_len, ...)
    mov rax, [in_len]
    sub rax, rbx                ; n
    mov rdx, [expand_len]
    lea rdi, [in_buf + r12]
    add rdi, rdx                ; dst
    lea rsi, [in_buf + rbx]     ; src
    mov rdx, rax                ; n
    ; direction: dst > src (growing, the usual @@ case) -> copy from the
    ; end backwards; dst < src (collapsing, e.g. expand_len=0 removing an
    ; @import line) -> copy from the start forwards. Picking the wrong
    ; direction with overlapping regions corrupts the block.
    cmp rdi, rsi
    jae .grow
    call memmove_front
    jmp .after_move
.grow:
    call memmove_back
.after_move:
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
; memmove_front(rdi = dst, rsi = src, rdx = n) - copies [src, src+n) to
; [dst, dst+n) from the start forwards (required when dst < src overlaps:
; the tail of the source is still untouched while we copy the head).
; ----------------------------------------------------------------------
memmove_front:
    test rdx, rdx
    jz .done
    mov rcx, rdx
    rep movsb
.done:
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

; ----------------------------------------------------------------------
; validate_typed_props() - checks every recorded typed @@ prop against
; the registered states (the expand pass runs before compile_block, so
; the lookup only works here). Dies on: unknown state, scalar state, or
; a type name mismatch.
; ----------------------------------------------------------------------
validate_typed_props:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r12, r12
.vt_loop:
    cmp r12, [tp_prop_count]
    jge .done
    imul rax, r12, 136
    lea rbx, [tp_props + rax]
    ; find the state by its COPIED name (the @@ splice overwrote the
    ; original line, so offsets into it are dead)
    xor r13, r13
.vt_sloop:
    cmp r13, [state_count]
    jge .err
    imul rax, r13, STATE_ENTRY
    lea r14, [state_tab + rax]
    mov eax, [rbx + 64]
    cmp [r14 + S_NAME_LEN], eax
    jne .vt_snext
    mov edx, [r14 + S_NAME_PTR]
    lea rdi, [in_buf + rdx]
    lea rsi, [rbx]
    mov edx, [rbx + 64]         ; u32 state name len!
    call strncmp
    test rax, rax
    jz .vt_sfound
.vt_snext:
    inc r13
    jmp .vt_sloop
.vt_sfound:
    ; the state must be an object of the annotated type
    imul rax, r13, STATE_ENTRY
    mov edx, [state_tab + rax + S_TYPE_IDX]
    cmp edx, -1
    je .err                     ; scalar state can't take a named type
    imul rdx, rdx, TYPE_ENTRY
    mov ecx, [type_tab + rdx + T_NAME_PTR]
    mov r8d, [type_tab + rdx + T_NAME_LEN]
    mov eax, [rbx + 132]
    cmp r8d, eax
    jne .err                    ; type name length mismatch
    lea rdi, [in_buf + rcx]
    lea rsi, [rbx + 68]
    mov rdx, r8
    call strncmp
    test rax, rax
    jnz .err                    ; type name mismatch
    inc r12
    jmp .vt_loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.err:
    lea rdi, [msg_comp_param]
    mov rsi, msg_comp_param_len
    call die
