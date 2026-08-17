; src/http/method_check.asm
; HTTP method checker
; Uses http.inc (interface)

%include "http/http.inc"

; Check if a buffer starts with a given HTTP method
; Arguments: rdi = buffer, rsi = method string to check
; Returns: rax = 1 if buffer starts with method, 0 otherwise
global http_method_includes
http_method_includes:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14

    mov r12, rdi              ; buffer pointer
    mov r13, rsi              ; method string pointer

    ; Get buffer length via strlen
    mov rdi, r12
    call strlen
    mov r14, rax              ; buffer length

    ; Get method length via strlen
    mov rdi, r13
    call strlen
    mov rcx, rax              ; method length

    ; If method is longer than buffer, can't match
    cmp rcx, r14
    ja .not_found

    ; Use strncmp to compare limited length
    mov rdi, r12              ; buffer
    mov rsi, r13              ; method
    mov rdx, rcx              ; limit = method length
    call strncmp
    test rax, rax
    jz .found

.not_found:
    xor rax, rax              ; return 0
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

.found:
    mov rax, 1                ; return 1
    pop r14
    pop r13
    pop r12
    pop rbp
    ret
