; src/http/static.asm
; Static file server: maps a request path to static/<path>, streams the
; file with a proper Content-Type + Content-Length.
; http_serve_static(rdi = path) -> rax = 0 ok, -1 not found/error
; The path comes from the `route` buffer ("/app.wasm") and starts with
; '/', so "static" + path = "static/app.wasm". Directories are rejected
; (serving static/ for "/" would be wrong - "/" is a real route).
; On -1 nothing was sent; the caller decides the status (404).

%include "http/http.inc"

extern client_fd
extern resp_buf
extern itoa_buf
extern cl_prefix, crlf2, cc_nocache
extern memcpy_adv, strcpy_adv
extern strlen
extern mime_lookup
extern write_status_line

section .data
    ; public/ lives INSIDE static/: user assets (images, videos, favicons)
    ; are served from static/public/<path>; the route wasm modules stay at
    ; static/<path>. One tree, no separate public/ dir at the project root.
    pub_str db "static/public", 0
    pub_str_len equ $ - pub_str - 1   ; copy without the null (path appends its own)
    static_str db "static", 0
    static_str_len equ $ - static_str - 1

section .text

global http_serve_static
http_serve_static:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14, rdi              ; path (callee-saved, survives calls)

    ; try static/public/<path> first, then static/<path>
    lea rdi, [pub_str]
    mov rsi, pub_str_len
    call .try_open
    test rax, rax
    jns .have_fd
    lea rdi, [static_str]
    mov rsi, static_str_len
    call .try_open
    test rax, rax
    js .nf
.have_fd:
    mov r12, rax              ; fd

    ; fstat(fd, stat_buf)
    mov rax, SYS_fstat
    mov rdi, r12
    lea rsi, [stat_buf]
    syscall
    test rax, rax
    js .err

    ; reject directories: (st_mode & S_IFMT) == S_IFDIR
    mov eax, [stat_buf + 24]
    and eax, 0o170000
    cmp eax, 0o040000
    je .err

    ; file size for Content-Length
    mov r13, [stat_buf + 48]

    ; content-type line (full "Content-Type: X\r\n" template)
    mov rdi, r14
    call mime_lookup          ; rax = ct ptr, rdx = ct len
    mov rbx, rax
    mov r14, rdx              ; path dead - r14 now holds ct len

    ; build header in resp_buf (write pos tracked in r15)
    lea r15, [resp_buf]
    call write_status_line    ; "HTTP/1.1 <code><reason>\r\n"
    mov rdi, r15
    mov rsi, rbx
    mov rdx, r14
    call memcpy_adv           ; Content-Type line
    mov r15, rax
    mov rdi, r15
    lea rsi, [cc_nocache]
    call strcpy_adv           ; "Cache-Control: no-cache\r\n" (the glue
    mov r15, rax              ; re-checks wasm bytes on every hot reload)
    mov rdi, r15
    lea rsi, [cl_prefix]
    call strcpy_adv           ; "Content-Length: "
    mov r15, rax
    mov rdi, r13              ; file size
    lea rsi, [itoa_buf]
    call itoa                 ; rax = ptr to first digit
    mov rsi, rax
    lea rdx, [itoa_buf + 11]
    sub rdx, rsi
    mov rdi, r15
    call memcpy_adv           ; size digits
    mov r15, rax
    mov rdi, r15
    lea rsi, [crlf2]
    mov rdx, 4
    call memcpy_adv           ; end of headers
    mov r15, rax

    ; write header
    lea rax, [resp_buf]
    sub r15, rax
    mov rax, SYS_write
    mov rdi, [client_fd]
    lea rsi, [resp_buf]
    mov rdx, r15
    syscall
    test rax, rax
    js .err

    ; stream file: read 4096 -> write to client until EOF
.stream:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [file_buf]
    mov rdx, 4096
    syscall
    test rax, rax
    jl .err
    je .done_ok               ; EOF
    mov r15, rax              ; bytes read
    mov rax, SYS_write
    mov rdi, [client_fd]
    lea rsi, [file_buf]
    mov rdx, r15
    syscall
    test rax, rax
    js .err
    jmp .stream

.done_ok:
    mov rax, SYS_close
    mov rdi, r12
    syscall
    xor rax, rax
    jmp .out
.nf:
    mov rax, -1
    jmp .out
.err:
    mov rax, SYS_close
    mov rdi, r12
    syscall
    mov rax, -1
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; .try_open(rdi = prefix ptr, rsi = prefix len) -> rax = fd or -1
; Builds path_buf = "<prefix>/<path>" and opens it read-only. The path
; is copied verbatim - a dynamic route's wasm lives at the literal [id]
; path (static/profile/[id]/page.wasm), same as the URL.
; memcpy_adv(rdi = dst, rsi = src, rdx = len) -> rax = dst + len
; ----------------------------------------------------------------------
.try_open:
    push rbx
    push r12
    push r13
    mov r13, rdi              ; prefix ptr
    mov r12, rsi              ; prefix len
    ; path_buf = prefix
    lea rdi, [path_buf]
    mov rsi, r13
    mov rdx, r12
    call memcpy_adv           ; rax = path_buf + prefix_len
    ; append '/'
    mov byte [rax], '/'
    inc rax
    mov rbx, rax              ; append dest (after '/')
    ; append the path + null
    mov rdi, r14
    call strlen
    inc rax                   ; copy the null too
    mov rdx, rax
    mov rdi, rbx
    mov rsi, r14
    call memcpy_adv
    ; openat(AT_FDCWD, path_buf, O_RDONLY)
    mov rax, SYS_openat
    mov rdi, -100
    lea rsi, [path_buf]
    xor rdx, rdx
    syscall
    pop r13
    pop r12
    pop rbx
    ret

section .bss
    path_buf resb 1024
    stat_buf resb 144
    file_buf resb 4096
