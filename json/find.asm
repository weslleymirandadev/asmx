; src/json/find.asm
; JSON field extraction - find a key in the ROOT OBJECT and return its
; value, without parsing the whole document (the caller should have run
; json_parse first to validate it).
;
;   json_find(rdi = buf, rsi = len, rdx = key) ->
;       rax = value ptr, rdx = value len, rcx = type
;       rax = -1 if key missing or document is not an object
;
; Strings: rax points at the CONTENT (after the opening quote), rdx is the
; content length (escapes still raw). Other types: ptr/len of the raw
; token (object/array = balanced span). Keys are compared with escape
; resolution (\n, \t, \", \\, \u00XX... - \u above 0x7F never matches).

%include "json/json.inc"

extern json_skip_ws
extern json_parse_string
extern json_skip_value

section .text

; ----------------------------------------------------------------------
; json_find(rdi = buf, rsi = len, rdx = key)
; ----------------------------------------------------------------------
global json_find
json_find:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi          ; buf
    mov r13, rdi
    add r13, rsi          ; end
    mov r14, rdx          ; key (null-terminated)

    ; skip ws, expect '{'
    mov rdi, r12
    mov rsi, r13
    call json_skip_ws
    mov r12, rax
    cmp r12, r13
    jge .nf
    cmp byte [r12], '{'
    jne .nf
    inc r12

.pair_loop:
    ; skip ws; '}' -> key missing
    mov rdi, r12
    mov rsi, r13
    call json_skip_ws
    mov r12, rax
    cmp r12, r13
    jge .nf
    cmp byte [r12], '}'
    je .nf

    ; key string: content = [r12+1, ret-1)
    mov rdi, r12
    mov rsi, r13
    call json_parse_string
    test rax, rax
    js .nf
    mov r15, rax          ; pos after closing quote
    lea rbx, [r12 + 1]    ; key content ptr
    mov rdx, r15
    sub rdx, rbx
    dec rdx               ; content len (exclude closing quote)

    ; compare with the requested key
    mov rdi, r14
    mov rsi, rbx
    call cmp_key
    test rax, rax
    jz .found_key

    ; not this key: skip ':' + value, continue
    mov r12, r15
    mov rdi, r12
    mov rsi, r13
    call json_skip_ws
    mov r12, rax
    cmp r12, r13
    jge .nf
    cmp byte [r12], ':'
    jne .nf
    inc r12
    mov rdi, r12
    mov rsi, r13
    call json_skip_ws
    mov r12, rax
    ; skip the value
    mov rdi, r12
    mov rsi, r13
    call json_skip_value
    test rax, rax
    js .nf
    mov r12, rax
    ; expect ',' to continue
    mov rdi, r12
    mov rsi, r13
    call json_skip_ws
    mov r12, rax
    cmp r12, r13
    jge .nf
    cmp byte [r12], ','
    jne .nf
    inc r12
    jmp .pair_loop

.found_key:
    ; r12 = pos after key string; skip ':' + ws -> value start
    mov r12, r15
    mov rdi, r12
    mov rsi, r13
    call json_skip_ws
    mov r12, rax
    cmp r12, r13
    jge .nf
    cmp byte [r12], ':'
    jne .nf
    inc r12
    mov rdi, r12
    mov rsi, r13
    call json_skip_ws
    mov r12, rax

    ; value span
    mov rbx, r12          ; value start
    mov rdi, r12
    mov rsi, r13
    call json_skip_value
    test rax, rax
    js .nf
    mov r15, rax          ; value end

    ; type from first char
    xor r9d, r9d
    mov al, [rbx]
    cmp al, '"'
    jne .not_str
    mov r9, JSON_T_STRING
    ; string: return content without the quotes
    inc rbx
    mov rax, rbx
    mov rdx, r15
    sub rdx, rbx
    dec rdx
    jmp .type_done
.not_str:
    cmp al, '{'
    jne .not_obj
    mov r9, JSON_T_OBJECT
    jmp .raw
.not_obj:
    cmp al, '['
    jne .not_arr
    mov r9, JSON_T_ARRAY
    jmp .raw
.not_arr:
    cmp al, 't'
    je .bool_t
    cmp al, 'f'
    je .bool_t
    cmp al, 'n'
    je .null_t
    mov r9, JSON_T_NUMBER
    jmp .raw
.bool_t:
    mov r9, JSON_T_BOOL
    jmp .raw
.null_t:
    mov r9, JSON_T_NULL
.raw:
    mov rax, rbx
    mov rdx, r15
    sub rdx, rbx
.type_done:
    mov rcx, r9
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.nf:
    mov rax, -1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; cmp_key(rdi = key, rsi = content, rdx = content_len) -> rax = 0 equal
; Compares a null-terminated key against a JSON key string, resolving
; escapes on the JSON side ("a\u0041" matches "aA"; \u > 0x7F never
; matches). Clobbers rcx, r8, r9, r10, r11, dl.
; ----------------------------------------------------------------------
cmp_key:
    push rbx
    push r12
    push r13
    mov r12, rdi          ; key ptr
    mov r13, rsi          ; content ptr
    xor rbx, rbx          ; content index
.loop:
    cmp rbx, rdx
    jge .end_content
    mov al, [r12]
    test al, al
    jz .mismatch          ; key exhausted but content remains
    mov cl, [r13 + rbx]
    cmp cl, '\'
    je .escape
    cmp al, cl
    jne .mismatch
    inc rbx
    inc r12
    jmp .loop
.escape:
    inc rbx
    cmp rbx, rdx
    jge .mismatch
    mov cl, [r13 + rbx]
    cmp cl, '"'
    je .esc_dquote
    cmp cl, '\'
    je .esc_bslash
    cmp cl, '/'
    je .esc_slash
    cmp cl, 'b'
    je .esc_b
    cmp cl, 'f'
    je .esc_f
    cmp cl, 'n'
    je .esc_n
    cmp cl, 'r'
    je .esc_r
    cmp cl, 't'
    je .esc_t
    cmp cl, 'u'
    je .esc_u
    jmp .mismatch
.esc_dquote:
    mov cl, '"'
    jmp .esc_compare
.esc_bslash:
    mov cl, '\'
    jmp .esc_compare
.esc_slash:
    mov cl, '/'
    jmp .esc_compare
.esc_b:
    mov cl, 8
    jmp .esc_compare
.esc_f:
    mov cl, 12
    jmp .esc_compare
.esc_n:
    mov cl, 10
    jmp .esc_compare
.esc_r:
    mov cl, 13
    jmp .esc_compare
.esc_t:
    mov cl, 9
    jmp .esc_compare
.esc_compare:
    cmp al, cl
    jne .mismatch
    inc rbx               ; consumed the escape char
    inc r12
    jmp .loop
.esc_u:
    ; \uXXXX -> codepoint; match only if <= 0x7F
    inc rbx
    xor r9d, r9d          ; codepoint
    mov r8, 4
.hex_loop:
    cmp rbx, rdx
    jge .mismatch
    mov cl, [r13 + rbx]
    cmp cl, '0'
    jb .mismatch
    cmp cl, '9'
    jbe .hex_num
    cmp cl, 'a'
    jb .mismatch
    cmp cl, 'f'
    jbe .hex_low
    cmp cl, 'A'
    jb .mismatch
    cmp cl, 'F'
    ja .mismatch
    sub cl, 'A' - 10
    jmp .hex_apply
.hex_low:
    sub cl, 'a' - 10
    jmp .hex_apply
.hex_num:
    sub cl, '0'
.hex_apply:
    imul r9, r9, 16
    movzx r10d, cl
    add r9, r10
    inc rbx
    dec r8
    jnz .hex_loop
    cmp r9, 0x7F
    ja .mismatch
    mov cl, r9b
    jmp .esc_compare
.end_content:
    cmp byte [r12], 0
    jne .mismatch
    xor rax, rax
    jmp .done
.mismatch:
    mov rax, 1
.done:
    pop r13
    pop r12
    pop rbx
    ret
