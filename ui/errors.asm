; =============================================================================
; errors.asm - GCC/rustc-style formatted errors for the @ DSL compiler.
; Prints:
;   src/app/about/page.asx:1:1: error: cannot read imported component file
;     |
;   1 | @import Header from "@/components/Header"
;     | ^^^^^^^
;
; with ANSI colors (always on - the make pipeline passes stderr through to
; the terminal). The compiler runs without libc: raw SYS_write to fd 2.
; =============================================================================

; ----------------------------------------------------------------------
; write_str(rdi = null-terminated string) - writes to fd 2.
; ----------------------------------------------------------------------
write_str:
    push r12
    mov r12, rdi
    xor rdx, rdx
.slen:
    cmp byte [r12 + rdx], 0
    je .have
    inc rdx
    jmp .slen
.have:
    mov rax, SYS_write
    mov rdi, 2
    mov rsi, r12
    syscall
    pop r12
    ret

; ----------------------------------------------------------------------
; write_raw(rdi = buf, rsi = len) - writes to fd 2.
; ----------------------------------------------------------------------
write_raw:
    mov rax, SYS_write
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, 2
    syscall
    ret

; ----------------------------------------------------------------------
; fmt_u64(rdi = value, rsi = buf) - decimal digits written into buf
; (no terminator), returns rax = length.
; ----------------------------------------------------------------------
fmt_u64:
    push rbx
    push r12
    push r13
    mov r12, rdi                ; value
    mov r13, rsi                ; buf
    lea rdi, [r13 + 20]
    mov byte [rdi], 0
    mov rax, r12
    xor rdx, rdx
.digit:
    mov rcx, 10
    div rcx                     ; rax = q, rdx = rem
    add dl, '0'
    dec rdi
    mov [rdi], dl
    xor rdx, rdx
    test rax, rax
    jnz .digit
    ; memmove [rdi..end] -> r13
    mov rsi, rdi
    lea rdx, [r13 + 20]
    sub rdx, rdi                ; len
    mov rcx, rdx
    mov rdi, r13
    rep movsb
    mov rsi, r13                ; buf back in rsi (rep movsb clobbered it)
    mov rax, rdx                ; len
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; err_location(rdi = buf, rsi = offset) - 1-based line/col of offset.
; Returns rax = line, rdx = col.
; ----------------------------------------------------------------------
err_location:
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; buf
    mov r13, rsi                ; offset
    xor r14, r14                ; line = 1 (0-based counter)
    xor r15, r15                ; last line start
    xor rcx, rcx
.loop:
    cmp rcx, r13
    jge .done
    cmp byte [r12 + rcx], 10
    jne .next
    inc r14
    lea r15, [rcx + 1]
.next:
    inc rcx
    jmp .loop
.done:
    lea rax, [r14 + 1]          ; line (1-based)
    mov rdx, r13
    sub rdx, r15
    add rdx, 1                  ; col (1-based)
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; ----------------------------------------------------------------------
; err_die(rdi = path, rsi = path_len, rdx = line, rcx = col,
;         r8 = msg, r9 = msg_len) - prints the header line with colors
; and exits 1. Used when no source snippet is available.
; ----------------------------------------------------------------------
err_die:
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; path
    mov r13, rsi                ; path_len
    mov r14, rdx                ; line
    mov r15, rcx                ; col
    ; bold cyan path
    lea rdi, [c_bold_cyan]
    call write_str
    mov rdi, r12
    mov rsi, r13
    call write_raw
    lea rdi, [c_reset]
    call write_str
    ; :line:col  (bold)
    lea rdi, [c_bold]
    call write_str
    lea rdi, [c_colon]
    call write_str
    mov rdi, r14
    lea rsi, [num_buf]
    call fmt_u64
    mov rdi, rsi
    mov rsi, rax
    call write_raw
    lea rdi, [c_colon]
    call write_str
    mov rdi, r15
    lea rsi, [num_buf]
    call fmt_u64
    mov rdi, rsi
    mov rsi, rax
    call write_raw
    lea rdi, [c_reset]
    call write_str
    ; ": error: "
    lea rdi, [c_colon_space]
    call write_str
    lea rdi, [c_bold_red]
    call write_str
    lea rdi, [s_error]
    call write_str
    lea rdi, [c_reset]
    call write_str
    lea rdi, [c_colon_space]
    call write_str
    ; msg
    mov rdi, r8
    mov rsi, r9
    call write_raw
    ; newline
    lea rdi, [c_nl]
    call write_str
    pop r15
    pop r14
    pop r13
    pop r12
    mov rax, SYS_exit
    mov rdi, 1
    syscall

; ----------------------------------------------------------------------
; err_at(rdi = buf, rsi = offset, rdx = path, rcx = path_len,
;        r8 = msg, r9 = msg_len) - computes the location, prints the
; header AND the source snippet with a caret, then exits 1.
; ----------------------------------------------------------------------
err_at:
    push r12
    push r13
    push r14
    push r15
    push rbx
    mov r12, rdi                ; buf
    mov r13, rsi                ; offset
    mov r14, rdx                ; path
    mov r15, rcx                ; path_len
    mov rbx, r8                 ; msg
    ; --- location ---
    mov rdi, r12
    mov rsi, r13
    call err_location
    push rax                    ; line
    push rdx                    ; col
    ; --- header (reuse err_die's body but don't exit) ---
    mov rdi, r14
    mov rsi, r15
    mov rdx, rax
    mov rcx, [rsp]              ; col
    mov r8, rbx
    mov r9, r9
    call err_header
    ; --- snippet: find line start/end ---
    ; line start: scan back from offset to \n
    mov rdi, r12
    mov rsi, r13
    call line_bounds            ; rax = start_off, rdx = end_off, rcx = col
    ; convert offsets to pointers: r12 = buf base
    add rax, r12
    add rdx, r12
    mov r12, rax                ; line start ptr
    mov r13, rdx                ; line end ptr
    mov rbx, rcx                ; col within the line (0-based)
    ; "  |" gutter line
    lea rdi, [g_gutter]
    call write_str
    ; "<line> | " with the line number right-aligned (width 3)
    lea rdi, [g_pad]
    call write_str
    pop rcx                     ; col (1-based)
    pop rdx                     ; line
    push rdx
    push rcx
    mov rdi, rdx
    lea rsi, [num_buf]
    call fmt_u64
    mov rdi, rsi
    mov rsi, rax
    call write_raw
    lea rdi, [g_bar]
    call write_str
    ; the source line
    mov rdi, r12
    mov rsi, r13
    sub rsi, r12
    call write_raw
    lea rdi, [c_nl]
    call write_str
    ; caret line: "  | " + spaces + ^... (underline the rest of the token)
    lea rdi, [g_caret_pad]
    call write_str
    ; spaces = col-1
    pop rcx                     ; col
    pop rdx                     ; line (unused now)
    mov r8, rcx
    dec r8
    xor r9, r9
.spc:
    cmp r9, r8
    jge .spc_done
    lea rdi, [c_space]
    call write_str
    inc r9
    jmp .spc
.spc_done:
    lea rdi, [c_bold_red]
    call write_str
    ; carets: from col to end of token (non-space chars)
    lea rdi, [r12 + r8]         ; point at the error char
    xor r9, r9
.caret:
    cmp r9, 60
    jge .caret_done
    lea rsi, [rdi + r9]
    cmp rsi, r13
    jge .caret_done
    cmp byte [rsi], ' '
    je .caret_done
    cmp byte [rsi], 9
    je .caret_done
    push rdi
    push rsi
    lea rdi, [c_caret]
    call write_str
    pop rsi
    pop rdi
    inc r9
    jmp .caret
.caret_done:
    lea rdi, [c_reset]
    call write_str
    lea rdi, [c_nl]
    call write_str
    pop rbx
    pop r15
    pop r14
    pop r13
    pop r12
    mov rax, SYS_exit
    mov rdi, 1
    syscall

; ----------------------------------------------------------------------
; err_header(rdi = path, rsi = path_len, rdx = line, rcx = col,
;            r8 = msg, r9 = msg_len) - prints the "path:line:col: error:
; msg" line (no exit, no snippet).
; ----------------------------------------------------------------------
err_header:
    push r12
    push r13
    push r14
    push r15
    push rbx
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8
    lea rdi, [c_bold_cyan]
    call write_str
    mov rdi, r12
    mov rsi, r13
    call write_raw
    lea rdi, [c_reset]
    call write_str
    lea rdi, [c_bold]
    call write_str
    lea rdi, [c_colon]
    call write_str
    mov rdi, r14
    lea rsi, [num_buf]
    call fmt_u64
    mov rdi, rsi
    mov rsi, rax
    call write_raw
    lea rdi, [c_colon]
    call write_str
    mov rdi, r15
    lea rsi, [num_buf]
    call fmt_u64
    mov rdi, rsi
    mov rsi, rax
    call write_raw
    lea rdi, [c_reset]
    call write_str
    lea rdi, [c_colon_space]
    call write_str
    lea rdi, [c_bold_red]
    call write_str
    lea rdi, [s_error]
    call write_str
    lea rdi, [c_reset]
    call write_str
    lea rdi, [c_colon_space]
    call write_str
    mov rdi, rbx
    mov rsi, r9
    call write_raw
    lea rdi, [c_nl]
    call write_str
    pop rbx
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; ----------------------------------------------------------------------
; line_bounds(rdi = buf, rsi = offset) - finds the line containing
; offset. Returns rax = line start, rdx = line end (exclusive),
; rcx = column of offset within the line (0-based).
; ----------------------------------------------------------------------
line_bounds:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    ; scan back for the line start
    mov rax, r13
.back:
    cmp rax, 0
    jle .have_start
    cmp byte [r12 + rax - 1], 10
    je .have_start
    dec rax
    jmp .back
.have_start:
    ; rax = line start
    mov rcx, r13
    sub rcx, rax                ; col in line
    ; scan forward for the line end
    mov rdx, r13
.fwd:
    cmp rdx, 4096
    jge .have_end
    cmp byte [r12 + rdx], 10
    je .have_end
    cmp byte [r12 + rdx], 0
    je .have_end
    inc rdx
    jmp .fwd
.have_end:
    pop r13
    pop r12
    ret
