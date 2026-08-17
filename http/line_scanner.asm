; src/http/line_scanner.asm
; Line scanner - splits buffer on \n for iteration
; Uses http.inc (interface)

%include "http/http.inc"

extern http_newline_char
extern http_line_start
extern http_line_end
extern http_line_count

; Scan buffer line by line, splitting on \n
; Arguments: rdi = buffer, rsi = buffer length
; Returns: line_count in memory, line_start/line_end updated for iteration
global http_scan_lines
http_scan_lines:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov r12, rdi              ; buffer
    mov r13, rsi              ; length
    xor rax, rax              ; line count

    mov rbx, r12              ; current position

.scan_loop:
    cmp rbx, r13
    jge .scan_done

    ; Find next newline
    mov rdi, rbx
    mov rsi, http_newline_char
    mov rdx, 1
    call strstr
    test rax, rax
    jz .no_newline_in_loop

    ; Found \n
    mov qword [http_line_end], rax
    mov qword [http_line_start], rbx
    inc rax
    mov rbx, rax
    inc qword [http_line_count]
    jmp .scan_loop

.no_newline_in_loop:
    ; Last line (no trailing newline)
    mov qword [http_line_end], r13
    mov qword [http_line_start], rbx
    inc qword [http_line_count]

.scan_done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
