; src/asmx/ssr.asm
; Server-side rendering helper: copies an HTML template to a buffer and
; replaces the "@client@" placeholder with <script src="PATH"></script>
; tags for every asset registered via the `client` macro (client linker
; section, __start_client/__stop_client).
;
;   ssr_render(rdi = template, rsi = dst, rdx = cap) -> rax = total len
;     Writes what fits in cap + a null terminator; returns the FULL length
;     needed (snprintf style). No placeholder -> template copied as-is.
;     Internal state: r13 = dst pos, r14 = cap left, r15 = total len.

%include "common/common.inc"

extern __start_client
extern __stop_client
extern strncmp

section .data
    ph       db "@client@", 0
    tag_pre  db '<script src="', 0
    tag_post db '"></script>', 0

section .text

global ssr_render
ssr_render:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi          ; template
    mov r13, rsi          ; dst
    mov r14, rdx          ; cap
    xor r15, r15          ; total len
    xor rbx, rbx          ; template pos
.loop:
    mov al, [r12 + rbx]
    test al, al
    jz .done
    cmp al, '@'
    jne .plain
    ; check the full placeholder (8 bytes)
    lea rsi, [ph]
    lea rdi, [r12 + rbx]
    mov rdx, 8
    call strncmp          ; clobbers rdi/rsi/rcx/rdx/r8 - rbx/r12-r15 safe
    test rax, rax
    jz .inject
.plain:
    mov al, [r12 + rbx]
    call putc_byte
    inc rbx
    jmp .loop
.inject:
    ; one <script src="PATH"></script> tag per client asset
    mov rcx, __start_client
    mov rdx, __stop_client
.tag_loop:
    cmp rcx, rdx
    jge .inject_done
    lea rdi, [tag_pre]
    call puts_str
    mov rdi, [rcx]
    call puts_str
    lea rdi, [tag_post]
    call puts_str
    add rcx, 8
    jmp .tag_loop
.inject_done:
    add rbx, 8
    jmp .loop
.done:
    test r14, r14
    jz .fin
    mov byte [r13], 0
.fin:
    mov rax, r15
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; putc_byte(al = char) - write one char at [r13], advance, count in r15
putc_byte:
    inc r15
    test r14, r14
    jz .done
    mov [r13], al
    inc r13
    dec r14
.done:
    ret

; puts_str(rdi = src) - write a null-terminated string via putc_byte
puts_str:
    push r12
    mov r12, rdi
.loop:
    mov al, [r12]
    test al, al
    jz .done
    call putc_byte
    inc r12
    jmp .loop
.done:
    pop r12
    ret

; ensure the `client` linker section exists even with no client assets,
; so __start_client/__stop_client are always defined
section client
