; src/asmx/log.asm
; Terminal logging: colored startup banner + per-request log lines in
; Next.js dev-server style, e.g.:
;
;   [ASMX] : listening on http://localhost:3000
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
    dot         db '.', 0
    us_suf      db ' μs)', 10, 0
    ms_suf      db ' ms)', 10, 0
    s_suf       db ' s)', 10, 0
    min_m       db 'm', 0
    min_s       db 's)', 10, 0

    banner_pre  db 10, 10, 0
    banner_name db '[ASMX]', 0
    banner_mid  db ': listening on ', 0
    banner_url  db 'http://localhost:', 0
    banner_post db 10, 0
    s_glue      db '/_asmx/glue.js', 0
    br_err      db 'Error', 0
    br_colon    db ': port ', 0
    br_mid      db ' already in use, starting server at ', 0
    bg_err      db 'Error', 0
    bg_colon    db ': no free port found up to ', 0
    br_nl       db 10, 0

section .bss
    ts_start   resq 2      ; clock_gettime timespec: sec, nsec
    ts_end     resq 2
    req_count  resq 1

section .text

; ----------------------------------------------------------------------
; log_bind_retry(rdi = taken port) - colored "Error: port %d already in
; use, starting server at %d" (the core then retries on port+1)
; ----------------------------------------------------------------------
global log_bind_retry
log_bind_retry:
    push r12
    mov r12, rdi
    ; "Error" (red bold), then normal color from the colon on
    lea rsi, [ansi_red]
    call write_ansi
    lea rsi, [ansi_bold]
    call write_ansi
    lea rdi, [br_err]
    call print_str
    lea rsi, [ansi_reset]
    call write_ansi
    lea rdi, [br_colon]
    call print_str
    ; port number (red)
    lea rsi, [ansi_red]
    call write_ansi
    lea rsi, [ansi_bold]
    call write_ansi
    mov rdi, r12
    call print_itoa
    lea rsi, [ansi_reset]
    call write_ansi
    lea rdi, [br_mid]
    call print_str
    ; retry port (red)
    lea rsi, [ansi_red]
    call write_ansi
    lea rsi, [ansi_bold]
    call write_ansi
    lea rdi, [r12 + 1]
    call print_itoa
    lea rsi, [ansi_reset]
    call write_ansi
    lea rdi, [br_nl]
    call print_str
    pop r12
    ret

; ----------------------------------------------------------------------
; log_bind_giveup(rdi = max port) - colored "Error: no free port found
; up to N" (the retry hit MAX_PORT without finding a free one)
; ----------------------------------------------------------------------
global log_bind_giveup
log_bind_giveup:
    push r12
    mov r12, rdi
    ; "Error" (red bold), then normal color from the colon on
    lea rsi, [ansi_red]
    call write_ansi
    lea rsi, [ansi_bold]
    call write_ansi
    lea rdi, [bg_err]
    call print_str
    lea rsi, [ansi_reset]
    call write_ansi
    lea rdi, [bg_colon]
    call print_str
    ; the ceiling port (red)
    lea rsi, [ansi_red]
    call write_ansi
    lea rsi, [ansi_bold]
    call write_ansi
    mov rdi, r12
    call print_itoa
    lea rsi, [ansi_reset]
    call write_ansi
    lea rdi, [br_nl]
    call print_str
    pop r12
    ret

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
    ; --- skip asset requests (glue.js / *.wasm): log routes only ---
    lea rdi, [route]
    call strlen
    cmp rax, 5
    jl .not_wasm
    cmp dword [route + rax - 4], 0x6D736177   ; trailing "wasm"
    je .first
.not_wasm:
    lea rdi, [route]
    lea rsi, [s_glue]
    mov rdx, 14
    call strncmp
    test rax, rax
    jz .first
    ; --- log the request that just finished ---
    lea rdi, [ts_end]
    call clock_now
    ; total_ns = sec_delta * 1e9 + nsec_delta, handling the nsec borrow
    ; (nsec_end < nsec_start while sec_delta >= 1)
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
    mov rbx, 1000000000
    mul rbx                    ; rdx:rax = sec delta * 1e9
    add rax, r13               ; total_ns
    mov r15, rax

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

    ; adaptive duration: minutes (rare) / s / ms / μs, 1 decimal each
    mov rax, r15                ; total_ns
    mov rbx, 60000000000        ; 60e9 > 2^32: via register, never imm32-truncated
    cmp rax, rbx                ; >= 60s -> minutes
    jae .minutes
    cmp rax, 1000000000         ; >= 1s -> seconds
    jae .seconds
    cmp rax, 1000000            ; >= 1ms -> milliseconds
    jae .millis
    ; micros: value*10 = total_ns / 100
    mov rdi, r15
    mov rsi, 100
    call print_dec1
    lea rdi, [us_suf]
    call print_str
    jmp .dur_done
.millis:
    mov rdi, r15
    mov rsi, 100000
    call print_dec1
    lea rdi, [ms_suf]
    call print_str
    jmp .dur_done
.seconds:
    mov rdi, r15
    mov rsi, 100000000
    call print_dec1
    lea rdi, [s_suf]
    call print_str
    jmp .dur_done
.minutes:
    mov rax, r15
    xor rdx, rdx
    mov rbx, 1000000000
    div rbx                     ; rax = total seconds
    mov r12, rax
    xor rdx, rdx
    mov rbx, 60
    div rbx                     ; rax = minutes, rdx = seconds
    mov r13, rax
    mov r14, rdx
    mov rdi, r13
    call print_itoa
    lea rdi, [min_m]
    call print_str
    mov rdi, r14
    call print_itoa
    lea rdi, [min_s]
    call print_str
.dur_done:
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

; ----------------------------------------------------------------------
; print_itoa(rdi = value) - itoa + write(1) of the digits
; ----------------------------------------------------------------------
print_itoa:
    push r12
    mov r12, rdi
    mov rdi, r12
    lea rsi, [itoa_buf]
    call itoa                   ; rax = ptr to first digit
    mov rsi, rax
    lea rdx, [itoa_buf + 11]
    sub rdx, rsi                ; digit count
    mov rax, SYS_write
    mov rdi, 1
    syscall
    pop r12
    ret

; ----------------------------------------------------------------------
; print_dec1(rdi = total_ns, rsi = divisor) - prints "N.N" (1 decimal).
; The value in tenths = total_ns / divisor, so the divisor must make the
; unit*10: 100 for μs, 100000 for ms, 100000000 for s.
; ----------------------------------------------------------------------
print_dec1:
    push rbx
    push r12
    push r13
    mov rax, rdi
    mov rbx, rsi
    xor rdx, rdx
    div rbx                     ; rax = value*10
    mov r12, rax
    xor rdx, rdx
    mov rbx, 10
    div rbx                     ; rax = integer part, rdx = tenths digit
    mov r13, rdx
    mov rdi, rax
    call print_itoa
    lea rdi, [dot]
    call print_str
    mov rdi, r13
    call print_itoa
    pop r13
    pop r12
    pop rbx
    ret
