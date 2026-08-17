; src/common/strings.asm
; String manipulation functions for x86-64 Linux
;
; NOTE: does NOT include common.inc (which pulls strings.inc with externs
; of the very symbols defined here). Rule: the file that DEFINES a symbol
; must not include the header that declares it. Includes only leaf .inc.

%include "common/syscalls.inc"
%include "common/macros.inc"

section .text

; ----------------------------------------------------------------------
; int strcmp(const char *s1, const char *s2)
; Returns: 0 if equal, <0 if s1 < s2, >0 if s1 > s2
; ----------------------------------------------------------------------
global strcmp
strcmp:
    push rbp
    mov rbp, rsp
    xor ecx, ecx
.compare_loop:
    mov al, [rdi + rcx]
    mov dl, [rsi + rcx]
    cmp al, 0
    je .s1_ended
    cmp dl, 0
    je .s2_ended
    cmp al, dl
    jne .diff_found
    inc rcx
    jmp .compare_loop
.s1_ended:
    cmp dl, 0
    je .equal
    mov eax, -1
    jmp .done
.s2_ended:
    cmp al, 0
    je .equal
    mov eax, 1
    jmp .done
.diff_found:
    movzx eax, al
    movzx edx, dl
    sub eax, edx
.done:
    pop rbp
    ret
.equal:
    xor eax, eax
    pop rbp
    ret

; ----------------------------------------------------------------------
; int strncmp(const char *s1, const char *s2, size_t n)
; ----------------------------------------------------------------------
global strncmp
strncmp:
    push rbp
    mov rbp, rsp
    test rdx, rdx
    je .done_zero
    xor ecx, ecx
.compare_loop:
    cmp rcx, rdx
    jge .done_zero
    mov al, [rdi + rcx]
    mov r8b, [rsi + rcx]   ; use r8b, NOT dl (rdx holds n)
    cmp al, 0
    je .s1_ended
    cmp r8b, 0
    je .s2_ended
    cmp al, r8b
    jne .diff_found
    inc rcx
    jmp .compare_loop
.s1_ended:
    cmp r8b, 0
    je .equal
    mov eax, -1
    jmp .done
.s2_ended:
    cmp al, 0
    je .equal
    mov eax, 1
    jmp .done
.diff_found:
    movzx eax, al
    movzx edx, r8b
    sub eax, edx
.done:
    pop rbp
    ret
.done_zero:
    xor eax, eax
    pop rbp
    ret
.equal:
    xor eax, eax
    pop rbp
    ret

; ----------------------------------------------------------------------
; size_t strlen(const char *s)
; ----------------------------------------------------------------------
global strlen
strlen:
    push rbp
    mov rbp, rsp
    xor rax, rax
.count_loop:
    cmp byte [rdi + rax], 0
    je .done
    inc rax
    jmp .count_loop
.done:
    pop rbp
    ret

; ----------------------------------------------------------------------
; char *strncpy(char *dest, const char *src, size_t n)
; Copies up to n chars, stopping at source null (libc semantics).
; Callers that need a terminator must pass len+1 (or null-terminate manually).
; ----------------------------------------------------------------------
global strncpy
strncpy:
    push rbp
    mov rbp, rsp
    push rdi
    xor ecx, ecx
.copy_loop:
    cmp rcx, rdx
    jge .done
    mov al, [rsi + rcx]
    mov [rdi + rcx], al
    test al, al
    je .done
    inc rcx
    jmp .copy_loop
.done:
    pop rdi
    mov rax, rdi
    pop rbp
    ret

; ----------------------------------------------------------------------
; int atoi(const char *s)
; Parses decimal ASCII digits until non-digit or null.
; Returns: rax = value
; Arguments: rdi = s
; Clobbers: rax, rcx, rdx
global atoi
atoi:
    push rbp
    mov rbp, rsp
    xor eax, eax          ; result
    xor ecx, ecx          ; index
.next_digit:
    mov dl, [rdi + rcx]
    cmp dl, '0'
    jb .done
    cmp dl, '9'
    ja .done
    imul rax, rax, 10
    movzx edx, dl
    sub edx, '0'
    add rax, rdx
    inc rcx
    jmp .next_digit
.done:
    pop rbp
    ret

; char *itoa(int value, char *buf)
; Converts integer to decimal ASCII (null-terminated), right-aligned in buf.
; Returns: rax = pointer to first digit (use as string start)
; Arguments: rdi = value, rsi = buf (must hold at least 12 bytes)
; Clobbers: rax, rcx, rdx, rsi
global itoa
itoa:
    push rbp
    mov rbp, rsp
    push rbx
    mov rbx, rsi          ; buf
    add rsi, 11
    mov byte [rsi], 0     ; null terminator
    mov rax, rdi          ; value
.digit_loop:
    mov rcx, 10
    xor rdx, rdx
    div rcx               ; rdx = digit
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .digit_loop
    mov rax, rsi          ; pointer to first digit
    pop rbx
    pop rbp
    ret

; char *strstr(const char *haystack, const char *needle)
; ----------------------------------------------------------------------
global strstr
strstr:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi          ; haystack pointer (advances)
    mov r13, rsi          ; needle pointer (reset each attempt)
    mov r14, rdi          ; haystack start (for return calc)

    ; Empty needle matches at start
    cmp byte [r13], 0
    je .found

.outer_loop:
    ; If haystack char is 0, no match
    cmp byte [r12], 0
    je .not_found

    ; Try to match needle starting at r12
    mov rbx, r12          ; attempt pointer
    mov rcx, r13          ; needle pointer

.inner_loop:
    mov al, [rcx]
    test al, al
    jz .found             ; reached end of needle = full match

    mov dl, [rbx]
    cmp al, dl
    jne .advance_haystack

    inc rbx
    inc rcx
    jmp .inner_loop

.advance_haystack:
    inc r12
    jmp .outer_loop

.found:
    mov rax, r12
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.not_found:
    xor rax, rax          ; return NULL
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
