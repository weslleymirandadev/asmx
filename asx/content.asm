; src/asx/content.asm
; Server-side state injection (ROADMAP item 3: "ssr.state").
; The @ DSL compiler marks every interpolated text in the SSR shell with
; a substitution slot: <prefix> 0x01 <state name> 0x02 <default> 0x03
; <suffix>, and the hydration snapshot with an injection point (0x04).
; The page handler calls ssr.state "name", value (asx_ssr_set_state);
; asx_send_content resolves the slots against that table and sends the
; final HTML - the SSR DOM shows the SERVER value (no flicker) and the
; snapshot carries it so the glue restores it BEFORE the first render.
;
;   section .SERVER
;   get_home:
;       ; count = database()
;       ssr.state "count", rax     ; inject into the HTML + snapshot
;       res.content index_content
;       asx.next
;
; Without any ssr.state call the table is empty and the shell is sent
; unchanged (slots stripped, defaults kept, snapshot untouched).

%include "common/common.inc"

extern client_fd
extern resp_buf
extern itoa_buf
extern ct_html, ct_html_len
extern cl_prefix, crlf2
extern write_status_line
extern strlen, strncmp, strcmp
extern memcpy_adv, strcpy_adv
extern asx_send_status

%define MAX_SSR_STATE 16
%define SSR_OUT_CAP 32768

section .bss
    ssr_state_keys resq MAX_SSR_STATE   ; key ptr (null-terminated)
    ssr_state_vals resq MAX_SSR_STATE   ; value (i64)
    ssr_state_count resq 1
    ssr_out_buf    resb SSR_OUT_CAP     ; processed body

section .text

; ----------------------------------------------------------------------
; asx_ssr_set_state(rdi = key ptr, rsi = value) - add or update one entry.
; The key pointer must stay valid until asx_send_content (the macro
; emits it inline with jump-over-data, so it does).
; ----------------------------------------------------------------------
global asx_ssr_set_state
asx_ssr_set_state:
    push rbx
    push r12
    push r13
    mov r12, rdi                ; key
    mov r13, rsi                ; value
    xor rbx, rbx
.lookup:
    cmp rbx, [ssr_state_count]
    jge .add
    mov rdi, r12
    mov rsi, [ssr_state_keys + rbx*8]
    call strcmp                 ; clobbers rdi/rsi/rcx - rbx/r12/r13 safe
    test rax, rax
    jz .update
    inc rbx
    jmp .lookup
.update:
    mov [ssr_state_vals + rbx*8], r13
    jmp .done
.add:
    cmp qword [ssr_state_count], MAX_SSR_STATE
    jge .done
    mov rax, [ssr_state_count]
    mov [ssr_state_keys + rax*8], r12
    mov [ssr_state_vals + rax*8], r13
    inc qword [ssr_state_count]
.done:
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------
; asx_ssr_state_reset() - clear the table (called once per request by
; the accept loop, before dispatch).
; ----------------------------------------------------------------------
global asx_ssr_state_reset
asx_ssr_state_reset:
    mov qword [ssr_state_count], 0
    ret

; ----------------------------------------------------------------------
; asx_send_content(rdi = shell) - resolve the ssr.state slots and send
; the page as text/html. Body built in ssr_out_buf (cap SSR_OUT_CAP),
; header in resp_buf (status line + content-type + content-length).
; ----------------------------------------------------------------------
global asx_send_content
asx_send_content:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; shell (in ptr)
    lea r13, [ssr_out_buf]      ; out ptr
    xor r14, r14                ; out pos
    xor r15, r15                ; in pos
.loop:
    mov al, [r12 + r15]
    test al, al
    jz .done
    cmp al, 1
    je .slot
    cmp al, 4
    je .snap
    mov [r13 + r14], al
    inc r14
    inc r15
    cmp r14, SSR_OUT_CAP
    jae .big
    jmp .loop
.slot:
    ; ---- substitution slot: 0x01 <name> 0x02 <default> 0x03 ----
    inc r15                     ; skip 0x01
    mov rbx, r15                ; name offset
.nscan:
    mov al, [r12 + r15]
    cmp al, 2
    je .nend
    inc r15
    jmp .nscan
.nend:
    mov rax, r15
    sub rax, rbx                ; name len
    push rax                    ; [rsp+24] name len
    lea rax, [r12 + rbx]        ; name PTR (absolute)
    push rax                    ; [rsp+16] name ptr
    inc r15                     ; skip 0x02
    mov rbx, r15                ; default offset
.dscan:
    mov al, [r12 + r15]
    cmp al, 3
    je .dend
    inc r15
    jmp .dscan
.dend:
    mov rax, r15
    sub rax, rbx                ; default len
    push rax                    ; [rsp+8] default len
    lea rax, [r12 + rbx]        ; default PTR (absolute)
    push rax                    ; [rsp] default ptr
    ; lookup: name len == key len && strncmp == 0
    xor rbx, rbx                ; entry idx (callee-saved, survives calls)
.lookup:
    cmp rbx, [ssr_state_count]
    jge .not_found
    mov rdi, [ssr_state_keys + rbx*8]
    call strlen                 ; rax = key len (rdi clobbered)
    cmp rax, [rsp + 24]
    jne .look_next
    mov rdi, [ssr_state_keys + rbx*8]
    mov rsi, [rsp + 16]
    mov rdx, [rsp + 24]
    call strncmp                ; clobbers rdi/rsi/rcx/rdx/r8 - rbx safe
    test rax, rax
    jz .found
.look_next:
    inc rbx
    jmp .lookup
.found:
    ; replace the default with the value (itoa)
    mov rdi, [ssr_state_vals + rbx*8]
    lea rsi, [itoa_buf]
    call itoa                   ; rax = ptr to first digit
    mov rsi, rax
.cval:
    mov al, [rsi]
    test al, al
    jz .after_slot
    mov [r13 + r14], al
    inc r14
    inc rsi
    jmp .cval
.not_found:
    ; keep the default: copy [rsp] (ptr) .. +[rsp+8] (len)
    mov rsi, [rsp]
    mov rcx, [rsp + 8]
.cdef:
    test rcx, rcx
    jz .after_slot
    mov al, [rsi]
    mov [r13 + r14], al
    inc r14
    inc rsi
    dec rcx
    jmp .cdef
.after_slot:
    add rsp, 32                 ; drop the 4 saved values
    inc r15                     ; skip 0x03
    jmp .loop
.snap:
    ; ---- snapshot injection point (0x04): ,"key":value per entry ----
    inc r15                     ; skip 0x04
    xor rbx, rbx
.snap_loop:
    cmp rbx, [ssr_state_count]
    jge .loop
    mov byte [r13 + r14], ','
    inc r14
    mov byte [r13 + r14], '"'
    inc r14
    ; key
    mov rdi, [ssr_state_keys + rbx*8]
    mov rsi, rdi
.klen:
    mov al, [rsi]
    test al, al
    jz .klen_end
    inc rsi
    jmp .klen
.klen_end:
    sub rsi, rdi                ; key len
    mov rcx, rsi
    mov rsi, rdi
.kcopy:
    test rcx, rcx
    jz .kcopy_end
    mov al, [rsi]
    mov [r13 + r14], al
    inc r14
    inc rsi
    dec rcx
    jmp .kcopy
.kcopy_end:
    mov byte [r13 + r14], '"'
    inc r14
    mov byte [r13 + r14], ':'
    inc r14
    ; value (itoa)
    mov rdi, [ssr_state_vals + rbx*8]
    lea rsi, [itoa_buf]
    call itoa
    mov rsi, rax
.vcopy:
    mov al, [rsi]
    test al, al
    jz .vcopy_end
    mov [r13 + r14], al
    inc r14
    inc rsi
    jmp .vcopy
.vcopy_end:
    inc rbx
    jmp .snap_loop
.big:
    ; body exceeded the buffer: honest 500 instead of broken HTML
    mov rdi, 500
    call asx_send_status
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.done:
    ; build the header in resp_buf (write pos in r15)
    lea r15, [resp_buf]
    call write_status_line       ; HTTP/1.1 200 OK\r\n
    mov rdi, r15
    lea rsi, [ct_html]
    mov rdx, ct_html_len
    call memcpy_adv
    mov r15, rax
    mov rdi, r15
    lea rsi, [cl_prefix]
    call strcpy_adv
    mov r15, rax
    ; Content-Length: body len (r14)
    mov rdi, r14
    lea rsi, [itoa_buf]
    call itoa
    mov rsi, rax
    lea rdx, [itoa_buf + 11]
    sub rdx, rsi
    mov rdi, r15
    call memcpy_adv
    mov r15, rax
    mov rdi, r15
    lea rsi, [crlf2]
    mov rdx, 4
    call memcpy_adv
    mov r15, rax
    ; write header
    lea rax, [resp_buf]
    sub r15, rax
    mov rax, SYS_write
    mov rdi, [client_fd]
    lea rsi, [resp_buf]
    mov rdx, r15
    syscall
    ; write body
    mov rax, SYS_write
    mov rdi, [client_fd]
    lea rsi, [ssr_out_buf]
    mov rdx, r14
    syscall
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
