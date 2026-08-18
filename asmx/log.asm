; src/asmx/log.asm
; Terminal logging: colored startup banner + per-request log lines in
; Next.js dev-server style, e.g.:
;
;   [ASMX] : listening on http://localhost:8080
;   GET /api/hello 200 (2ms)
;   GET / 200 (0ms)
;
; Colors (ANSI): method+path bold, status green 2xx / yellow 3xx /
; red 4xx+, duration gray. No-op for the first request (nothing to log).
;
; Exported:
;   log_banner(rdi = port)   - startup banner (colored)
;   log_request()            - log the request that just finished
;   clock_start()            - capture ts_start (called by the core right
;                              after reading the request bytes)

%include "common/common.inc"

extern strlen
extern itoa
extern itoa_buf
extern route
extern resp_status
extern http_req_method

%define SYS_clock_gettime 228
%define CLOCK_MONOTONIC 1

section .data
    ; ANSI escape sequences (null-terminated)
    ansi_cyan   db 27, '[1;36m', 0
    ansi_bold   db 27, '[1m', 0
    ansi_green  db 27, '[32m', 0
    ansi_yellow db 27, '[33m', 0
    ansi_red    db 27, '[31m', 0
    ansi_gray   db 27, '[90m', 0
    ansi_reset  db 27, '[0m', 0

    space       db ' ', 0
    ms_open     db ' (', 0
    ms_close    db 'ms)', 10, 0

    banner_pre  db 10, 10, 0
    banner_name db '[ASMX]', 0
    banner_mid  db ': listening on ', 0
    banner_url  db 'http://localhost:', 0
    banner_post db 10, 0

section .bss
    ts_start   resq 2      ; clock_gettime timespec: sec, nsec
    ts_end     resq 2
    req_count  resq 1

section .text

; ----------------------------------------------------------------------
; log_banner(rdi = port) - colored startup banner
; ----------------------------------------------------------------------
global log_banner
log_banner:
    push r12
    mov r12, rdi              ; port
    lea rdi, [banner_pre]
    call print_str
    lea rsi, [ansi_cyan]
    call write_ansi
    lea rdi, [banner_name]
    call print_str
    lea rsi, [ansi_reset]
    call write_ansi
    lea rdi, [banner_mid]
    call print_str
    lea rsi, [ansi_bold]
    call write_ansi
    lea rdi, [banner_url]
    call print_str
    mov rdi, r12
    lea rsi, [itoa_buf]
    call itoa                  ; rax = ptr to first digit
    mov rsi, rax
    lea rdx, [itoa_buf + 11]
    sub rdx, rsi               ; digit count
    mov rax, SYS_write
    mov rdi, 1
    syscall
    lea rsi, [ansi_reset]
    call write_ansi
    lea rdi, [banner_post]
    call print_str
    pop r12
    ret

; ----------------------------------------------------------------------
; log_request() - log the request that just finished (ts_end - ts_start).
; The start timestamp is captured by clock_start() right after the core
; reads the request bytes, so the duration measures the actual request
; processing time (no idle/accept wait). First call: nothing to log.
; ----------------------------------------------------------------------
global log_request
log_request:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp qword [req_count], 0
    je .first
    ; --- log the request that just finished ---
    lea rdi, [ts_end]
    call clock_now
    ; elapsed ms = (sec_delta * 1000) + (nsec_delta / 1e6), handling the
    ; nsec borrow (nsec_end < nsec_start while sec_delta >= 1)
    mov r12, [ts_end]
    sub r12, [ts_start]        ; sec delta
    mov rax, [ts_end + 8]
    sub rax, [ts_start + 8]    ; nsec delta (signed)
    test rax, rax
    jns .nsec_ok
    add rax, 1000000000
    dec r12
.nsec_ok:
    mov r13, rax               ; nsec delta
    mov rax, r12
    mov rbx, 1000
    mul rbx                    ; rdx:rax = sec delta * 1000
    mov r14, rax               ; ms base
    mov rax, r13
    xor rdx, rdx
    mov rbx, 1000000
    div rbx                    ; rax = nsec delta / 1e6
    add rax, r14
    mov r15, rax               ; total ms

    ; BOLD method path SPACE [status color] STATUS RESET GRAY (ms) RESET NL
    lea rsi, [ansi_bold]
    call write_ansi
    mov rdi, http_req_method
    call print_str
    lea rdi, [space]
    call print_str
    mov rdi, route
    call print_str
    lea rdi, [space]
    call print_str

    ; status color: 2xx green, 3xx yellow, 4xx+ red
    mov rax, [resp_status]
    cmp rax, 300
    jl .green
    cmp rax, 400
    jl .yellow
    lea rsi, [ansi_red]
    jmp .color_done
.green:
    lea rsi, [ansi_green]
    jmp .color_done
.yellow:
    lea rsi, [ansi_yellow]
.color_done:
    call write_ansi

    ; status digits - itoa(rdi = value, rsi = buf) -> rax = first digit ptr
    mov rdi, [resp_status]
    lea rsi, [itoa_buf]
    call itoa
    mov rsi, rax
    lea rdx, [itoa_buf + 11]
    sub rdx, rsi
    mov rax, SYS_write
    mov rdi, 1
    syscall

    lea rsi, [ansi_reset]
    call write_ansi
    lea rsi, [ansi_gray]
    call write_ansi
    lea rdi, [ms_open]
    call print_str

    ; duration digits - itoa(rdi = value, rsi = buf) -> rax = first digit ptr
    mov rdi, r15
    lea rsi, [itoa_buf]
    call itoa
    mov rsi, rax
    lea rdx, [itoa_buf + 11]
    sub rdx, rsi
    mov rax, SYS_write
    mov rdi, 1
    syscall

    lea rdi, [ms_close]
    call print_str
    lea rsi, [ansi_reset]
    call write_ansi
.first:
    inc qword [req_count]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; clock_start() - capture ts_start for the CURRENT request. Called by the
; core right after reading the request bytes (measurement starts when the
; request arrives, not when the accept loop wakes up).
; ----------------------------------------------------------------------
global clock_start
clock_start:
    lea rdi, [ts_start]
    jmp clock_now

; ----------------------------------------------------------------------
; clock_now(rdi = dst timespec) - CLOCK_MONOTONIC, 16 bytes at dst
; ----------------------------------------------------------------------
clock_now:
    mov rsi, rdi              ; ts ptr
    mov rdi, CLOCK_MONOTONIC
    mov rax, SYS_clock_gettime
    syscall                   ; clobbers rcx/r11 only
    ret

; write_ansi(rsi = null-terminated ANSI sequence) - write(1, rsi, strlen)
write_ansi:
    push rdi
    mov rdi, rsi
    call strlen
    mov rdx, rax
    mov rax, SYS_write
    mov rdi, 1
    syscall
    pop rdi
    ret

; print_str(rdi = null-terminated string) - write(1, rdi, strlen)
print_str:
    push rdi
    call strlen
    mov rsi, rdi
    pop rdi
    mov rdx, rax
    mov rax, SYS_write
    mov rdi, 1
    syscall
    ret
