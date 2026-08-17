; src/asmx/helpers.asm
; Internal helpers for asmx - string/memory copy with position advance
; Used by send.asm to build response headers in resp_buf

%include "common/syscalls.inc"

; memcpy_adv(rdi = dest, rsi = src, rdx = len) -> rax = dest + len
global memcpy_adv
memcpy_adv:
    push rcx
    xor rcx, rcx
.loop:
    cmp rcx, rdx
    jge .done
    mov al, [rsi + rcx]
    mov [rdi + rcx], al
    inc rcx
    jmp .loop
.done:
    mov rax, rdi
    add rax, rdx
    pop rcx
    ret

; strcpy_adv(rdi = dest, rsi = src) -> rax = dest + len (src null-terminated)
global strcpy_adv
strcpy_adv:
    push rcx
    xor rcx, rcx
.loop:
    mov al, [rsi + rcx]
    test al, al
    jz .done
    mov [rdi + rcx], al
    inc rcx
    jmp .loop
.done:
    mov rax, rdi
    add rax, rcx
    pop rcx
    ret
