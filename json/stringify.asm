; src/json/stringify.asm
; JSON stringifier primitives - write a JSON fragment AT rsi and return
; the length in rax. Concatenate the fragments into your own buffer.
;
;   json_str_int(rdi = value, rsi = dst) -> rax = len
;   json_str_bool(rdi = 0/1, rsi = dst) -> rax = len
;   json_str_null(rsi = dst) -> rax = len
;   json_str_string(rdi = src, rsi = dst, rdx = cap) -> rax = total len
;     (writes what fits in cap, returns the FULL length needed - snprintf
;     style; escapes " \ \b \f \n \r \t, other <0x20 as \u00XX)

%include "json/json.inc"

section .text

; ----------------------------------------------------------------------
; json_str_int(rdi = value, rsi = dst) -> rax = len (no null terminator)
; ----------------------------------------------------------------------
global json_str_int
json_str_int:
    push rbx
    push r12
    push r13
    mov r13, rsi          ; dst original
    mov r12, rsi          ; write pos
    xor ebx, ebx          ; digit count
    mov rax, rdi
    test rax, rax
    jns .positive
    mov byte [r12], '-'
    inc r12
    neg rax
.positive:
    test rax, rax
    jnz .digits
    mov byte [r12], '0'
    inc r12
    jmp .done
.digits:
    mov rcx, 10
.digit_loop:
    xor rdx, rdx
    div rcx               ; rax = q, rdx = remainder
    add dl, '0'
    push rdx
    inc rbx
    test rax, rax
    jnz .digit_loop
.write_loop:
    test rbx, rbx
    jz .done
    pop rdx
    mov [r12], dl
    inc r12
    dec rbx
    jmp .write_loop
.done:
    mov rax, r12
    sub rax, r13          ; len = end - start (sign included)
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; json_str_bool(rdi = 0/1, rsi = dst) -> rax = len
; ----------------------------------------------------------------------
global json_str_bool
json_str_bool:
    test rdi, rdi
    jz .false
    mov dword [rsi], 'true'
    mov rax, 4
    ret
.false:
    mov dword [rsi], 'fals'
    mov byte [rsi + 4], 'e'
    mov rax, 5
    ret

; ----------------------------------------------------------------------
; json_str_null(rsi = dst) -> rax = len
; ----------------------------------------------------------------------
global json_str_null
json_str_null:
    mov dword [rsi], 'null'
    mov rax, 4
    ret

; ----------------------------------------------------------------------
; json_str_string(rdi = src, rsi = dst, rdx = cap) -> rax = total len
; ----------------------------------------------------------------------
global json_str_string
json_str_string:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi          ; src
    mov r13, rsi          ; dst
    mov r14, rdx          ; cap
    xor r15, r15          ; total len
    ; opening quote
    cmp r14, 1
    jl .loop
    mov byte [r13], '"'
    inc r13
    dec r14
    inc r15
.loop:
    mov al, [r12]
    test al, al
    jz .close
    cmp al, '"'
    je .esc2
    cmp al, '\'
    je .esc2
    cmp al, 8
    je .esc_b
    cmp al, 12
    je .esc_f
    cmp al, 10
    je .esc_n
    cmp al, 13
    je .esc_r
    cmp al, 9
    je .esc_t
    cmp al, 0x20
    jl .esc6
    ; plain char
    cmp r14, 1
    jl .plain_count
    mov [r13], al
    inc r13
    dec r14
.plain_count:
    inc r15
    inc r12
    jmp .loop
.esc_b:
    mov al, 'b'
    jmp .esc2
.esc_f:
    mov al, 'f'
    jmp .esc2
.esc_n:
    mov al, 'n'
    jmp .esc2
.esc_r:
    mov al, 'r'
    jmp .esc2
.esc_t:
    mov al, 't'
    jmp .esc2
.esc2:
    ; \x escape: 2 bytes ('\' + escape letter)
    cmp r14, 2
    jl .esc2_count
    mov byte [r13], '\'
    mov byte [r13 + 1], al
    add r13, 2
    sub r14, 2
.esc2_count:
    add r15, 2
    inc r12
    jmp .loop
.esc6:
    ; \u00XX: 6 bytes
    mov bl, al
    cmp r14, 6
    jl .esc6_count
    mov byte [r13], '\'
    mov byte [r13 + 1], 'u'
    mov byte [r13 + 2], '0'
    mov byte [r13 + 3], '0'
    mov dil, bl
    shr dil, 4
    call hex_char
    mov [r13 + 4], al
    mov dil, bl
    and dil, 0x0F
    call hex_char
    mov [r13 + 5], al
    add r13, 6
    sub r14, 6
.esc6_count:
    add r15, 6
    inc r12
    jmp .loop
.close:
    inc r15               ; closing quote always counts toward total
    cmp r14, 1
    jl .done
    mov byte [r13], '"'
    inc r13
    dec r14
.done:
    mov rax, r15
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; hex_char(dil = nibble) -> al = ascii hex (lowercase)
hex_char:
    cmp dil, 10
    jl .num
    add dil, 'a' - 10
    mov al, dil
    ret
.num:
    add dil, '0'
    mov al, dil
    ret
