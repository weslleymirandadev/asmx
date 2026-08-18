; src/json/parse.asm
; JSON parser - full-document validation, RFC 8259 subset (no duplicate-key
; check). Also exports the internal walkers used by find.asm.
;
;   json_parse(rdi = buf, rsi = len) -> rax = 0 ok, -1 invalid
;   json_skip_ws(rdi = pos, rsi = end) -> rax = pos after whitespace
;   json_parse_string(rdi = pos, rsi = end) -> rax = pos after closing
;       quote, -1 invalid (pos must point AT the opening quote)
;   json_skip_value(rdi = pos, rsi = end) -> rax = pos after value, -1
;       (lenient: skips a value without validating its content; assumes
;       the document was validated by json_parse first)
;
; Internal convention: walkers take pos in r12 and end in r13 (caller
; saves/restores them); parse_value uses r14 as nesting depth. All return
; the new pos in rax, or -1 on error. Errors never die - library code.

%include "json/json.inc"

extern strncmp

%define JSON_MAX_DEPTH 32

section .data
    lit_true  db "true", 0
    lit_false db "false", 0
    lit_null  db "null", 0

section .text

; ----------------------------------------------------------------------
; json_skip_ws(rdi = pos, rsi = end) -> rax = pos
; ----------------------------------------------------------------------
global json_skip_ws
json_skip_ws:
    mov rax, rdi
.loop:
    cmp rax, rsi
    jge .done
    mov dl, [rax]
    cmp dl, ' '
    je .next
    cmp dl, 9
    je .next
    cmp dl, 10
    je .next
    cmp dl, 13
    je .next
    jmp .done
.next:
    inc rax
    jmp .loop
.done:
    ret

; ----------------------------------------------------------------------
; json_parse_string(rdi = pos, rsi = end) -> rax = pos after quote, -1
; Validates escapes: \" \\ \/ \b \f \n \r \t \uXXXX. Raw control chars
; (< 0x20) are invalid.
; ----------------------------------------------------------------------
global json_parse_string
json_parse_string:
    push rbx
    mov rbx, rdi
    cmp rbx, rsi
    jge .err
    cmp byte [rbx], '"'
    jne .err
    inc rbx               ; skip opening quote
.loop:
    cmp rbx, rsi
    jge .err
    mov al, [rbx]
    cmp al, '"'
    je .done
    cmp al, '\'
    je .escape
    cmp al, 0x20
    jl .err               ; raw control char
    inc rbx
    jmp .loop
.escape:
    inc rbx
    cmp rbx, rsi
    jge .err
    mov al, [rbx]
    cmp al, '"'
    je .esc_ok
    cmp al, '\'
    je .esc_ok
    cmp al, '/'
    je .esc_ok
    cmp al, 'b'
    je .esc_ok
    cmp al, 'f'
    je .esc_ok
    cmp al, 'n'
    je .esc_ok
    cmp al, 'r'
    je .esc_ok
    cmp al, 't'
    je .esc_ok
    cmp al, 'u'
    jne .err
    ; \uXXXX: 4 hex digits
    inc rbx
    mov rcx, 4
.hex_loop:
    cmp rbx, rsi
    jge .err
    mov al, [rbx]
    cmp al, '0'
    jb .err
    cmp al, '9'
    jbe .hex_ok
    cmp al, 'a'
    jb .err
    cmp al, 'f'
    jbe .hex_ok
    cmp al, 'A'
    jb .err
    cmp al, 'F'
    ja .err
.hex_ok:
    inc rbx
    dec rcx
    jnz .hex_loop
    jmp .loop
.esc_ok:
    inc rbx
    jmp .loop
.done:
    inc rbx               ; past closing quote
    mov rax, rbx
    pop rbx
    ret
.err:
    mov rax, -1
    pop rbx
    ret

; ----------------------------------------------------------------------
; parse_number(r12 = pos, r13 = end) -> rax = pos, -1
; -? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?
; ----------------------------------------------------------------------
parse_number:
    push rbx
    mov rbx, r12
    cmp rbx, r13
    jge .err
    cmp byte [rbx], '-'
    jne .int_part
    inc rbx
    cmp rbx, r13
    jge .err
.int_part:
    mov al, [rbx]
    cmp al, '0'
    je .int_zero
    cmp al, '1'
    jb .err
    cmp al, '9'
    ja .err
    inc rbx
.int_digits:
    cmp rbx, r13
    jge .frac
    mov al, [rbx]
    cmp al, '0'
    jb .frac
    cmp al, '9'
    ja .frac
    inc rbx
    jmp .int_digits
.int_zero:
    inc rbx
    cmp rbx, r13
    jge .frac
    mov al, [rbx]
    cmp al, '0'
    jb .frac
    cmp al, '9'
    jbe .err              ; leading zeros (01) invalid
.frac:
    cmp rbx, r13
    jge .exp
    cmp byte [rbx], '.'
    jne .exp
    inc rbx
    cmp rbx, r13
    jge .err
    mov al, [rbx]
    cmp al, '0'
    jb .err
    cmp al, '9'
    ja .err
.frac_digits:
    inc rbx
    cmp rbx, r13
    jge .exp
    mov al, [rbx]
    cmp al, '0'
    jb .exp
    cmp al, '9'
    ja .exp
    jmp .frac_digits
.exp:
    cmp rbx, r13
    jge .done
    mov al, [rbx]
    cmp al, 'e'
    je .exp_go
    cmp al, 'E'
    jne .done
.exp_go:
    inc rbx
    cmp rbx, r13
    jge .err
    mov al, [rbx]
    cmp al, '+'
    je .exp_sign
    cmp al, '-'
    je .exp_sign
    cmp al, '0'
    jb .err
    cmp al, '9'
    ja .err
    jmp .exp_digits
.exp_sign:
    inc rbx
    cmp rbx, r13
    jge .err
    mov al, [rbx]
    cmp al, '0'
    jb .err
    cmp al, '9'
    ja .err
.exp_digits:
    inc rbx
    cmp rbx, r13
    jge .done
    mov al, [rbx]
    cmp al, '0'
    jb .done
    cmp al, '9'
    ja .done
    jmp .exp_digits
.done:
    mov rax, rbx
    pop rbx
    ret
.err:
    mov rax, -1
    pop rbx
    ret

; ----------------------------------------------------------------------
; parse_literal(r12 = pos, r13 = end) -> rax = pos, -1
; Matches true/false/null (exact, bounds-checked).
; ----------------------------------------------------------------------
parse_literal:
    push rbx
    push r12
    push r13
    mov rbx, r12
    lea rsi, [lit_true]
    mov rdx, 4
    call lit_try
    test rax, rax
    jz .true
    lea rsi, [lit_false]
    mov rdx, 5
    call lit_try
    test rax, rax
    jz .false
    lea rsi, [lit_null]
    mov rdx, 4
    call lit_try
    test rax, rax
    jz .null
    jmp .err
.true:
    add rbx, 4
    jmp .done
.false:
    add rbx, 5
    jmp .done
.null:
    add rbx, 4
.done:
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret
.err:
    mov rax, -1
    pop r13
    pop r12
    pop rbx
    ret

; lit_try(rbx = pos, r13 = end, rsi = literal, rdx = len) -> rax = 0 match
; Bounds-checked strncmp: returns non-zero if out of bounds or different.
lit_try:
    ; if rbx + rdx > r13 -> no match
    lea rax, [rbx + rdx]
    cmp rax, r13
    jg .no
    mov rdi, rbx
    call strncmp          ; clobbers rdi/rsi/rcx/rdx - rbx/r13 safe
    ret
.no:
    mov rax, 1
    ret

; ----------------------------------------------------------------------
; parse_value(r12 = pos, r13 = end, r14 = depth) -> rax = pos, -1
; Dispatches on the first char. Objects/arrays recurse via parse_value.
; ----------------------------------------------------------------------
parse_value:
    push r14
    cmp r14, JSON_MAX_DEPTH
    jge .err
    cmp r12, r13
    jge .err
    mov al, [r12]
    cmp al, '{'
    je .object
    cmp al, '['
    je .array
    cmp al, '"'
    je .string
    cmp al, '-'
    je .number
    cmp al, '0'
    jb .literal
    cmp al, '9'
    jbe .number
.literal:
    call parse_literal
    jmp .done
.string:
    call str_in
    jmp .done
.number:
    call parse_number
    jmp .done
.object:
    inc r14
    inc r12               ; past '{'
    call skip_ws_in
    mov r12, rax
    cmp r12, r13
    jge .err
    cmp byte [r12], '}'
    je .obj_close
.obj_loop:
    ; key string
    call str_in
    test rax, rax
    js .err
    mov r12, rax
    call skip_ws_in
    mov r12, rax
    cmp r12, r13
    jge .err
    cmp byte [r12], ':'
    jne .err
    inc r12
    call skip_ws_in
    mov r12, rax
    ; value (recurse, depth+1)
    inc r14
    call parse_value
    test rax, rax
    js .err
    mov r12, rax
    dec r14
    call skip_ws_in
    mov r12, rax
    cmp r12, r13
    jge .err
    mov al, [r12]
    cmp al, ','
    je .obj_next
    cmp al, '}'
    jne .err
.obj_close:
    inc r12
    mov rax, r12
    jmp .done
.obj_next:
    inc r12
    call skip_ws_in
    mov r12, rax
    cmp r12, r13
    jge .err
    jmp .obj_loop
.array:
    inc r14
    inc r12               ; past '['
    call skip_ws_in
    mov r12, rax
    cmp r12, r13
    jge .err
    cmp byte [r12], ']'
    je .arr_close
.arr_loop:
    inc r14
    call parse_value
    test rax, rax
    js .err
    mov r12, rax
    dec r14
    call skip_ws_in
    mov r12, rax
    cmp r12, r13
    jge .err
    mov al, [r12]
    cmp al, ','
    je .arr_next
    cmp al, ']'
    jne .err
.arr_close:
    inc r12
    mov rax, r12
    jmp .done
.arr_next:
    inc r12
    call skip_ws_in
    mov r12, rax
    cmp r12, r13
    jge .err
    jmp .arr_loop
.done:
    pop r14
    ret
.err:
    mov rax, -1
    pop r14
    ret

; skip_ws_in - json_skip_ws with args from r12/r13 (internal call site)
skip_ws_in:
    mov rdi, r12
    mov rsi, r13
    call json_skip_ws
    ret

; str_in - json_parse_string with args from r12/r13 (internal call site)
str_in:
    mov rdi, r12
    mov rsi, r13
    call json_parse_string
    ret

; ----------------------------------------------------------------------
; json_skip_value(rdi = pos, rsi = end) -> rax = pos after value, -1
; Lenient walk: strings via json_parse_string, objects/arrays by bracket
; counting, numbers/literals by token scan. Used by json_find.
; ----------------------------------------------------------------------
global json_skip_value
json_skip_value:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    cmp r12, r13
    jge .err
    mov al, [r12]
    cmp al, '"'
    je .string
    cmp al, '{'
    je .open
    cmp al, '['
    je .open
    jmp .token
.string:
    call str_in
    test rax, rax
    js .err
    mov r12, rax
    jmp .done
.open:
    mov rbx, 1            ; nesting depth
    inc r12
.bracket_loop:
    cmp r12, r13
    jge .err
    mov al, [r12]
    cmp al, '"'
    je .bracket_string
    cmp al, '{'
    je .bracket_open
    cmp al, '['
    je .bracket_open
    cmp al, '}'
    je .bracket_close
    cmp al, ']'
    je .bracket_close
    inc r12
    jmp .bracket_loop
.bracket_string:
    call str_in
    test rax, rax
    js .err
    mov r12, rax
    jmp .bracket_loop
.bracket_open:
    inc rbx
    inc r12
    jmp .bracket_loop
.bracket_close:
    dec rbx
    inc r12
    test rbx, rbx
    jnz .bracket_loop
    jmp .done
.token:
    ; number or literal: advance until ws or , } ] :
    cmp r12, r13
    jge .done
    mov al, [r12]
    cmp al, ' '
    je .done
    cmp al, 9
    je .done
    cmp al, 10
    je .done
    cmp al, 13
    je .done
    cmp al, ','
    je .done
    cmp al, '}'
    je .done
    cmp al, ']'
    je .done
    inc r12
    jmp .token
.done:
    mov rax, r12
    pop r13
    pop r12
    pop rbx
    ret
.err:
    mov rax, -1
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; json_parse(rdi = buf, rsi = len) -> rax = 0 ok, -1 invalid
; Validates exactly one JSON value (with surrounding whitespace) spanning
; the whole buffer - no trailing garbage allowed.
; ----------------------------------------------------------------------
global json_parse
json_parse:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rdi
    add r13, rsi          ; end = buf + len
    xor r14, r14          ; depth
    call skip_ws_in
    mov r12, rax
    call parse_value
    test rax, rax
    js .err
    mov r12, rax
    call skip_ws_in
    mov r12, rax
    cmp r12, r13
    jne .err              ; trailing garbage
    xor rax, rax
    jmp .done
.err:
    mov rax, -1
.done:
    pop r14
    pop r13
    pop r12
    ret
