; src/http/request_line.asm
; HTTP request line parser
; Parses "GET /path HTTP/1.1" -> method, path, version
; Uses http.inc (interface) - state from http_state.asm
;
; WARNING: strncpy/strcmp clobber rdi/rsi/rcx. All positions are saved in
; r12 (buffer start), r13 (buffer len), r14 (current offset) BEFORE any
; call, and recomputed from those after. Never rely on rdi surviving a call.

%include "http/http.inc"

extern http_req_method
extern http_req_path
extern http_req_version
extern http_req_method_idx
extern http_method_table
extern http_space_char

; Parse the HTTP request line into method, path, version
; Arguments: rdi = buffer pointer, rsi = buffer length
; Returns: rax = 0 on success, -1 on error
global http_parse_request_line
http_parse_request_line:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi              ; buffer start
    mov r13, rsi              ; buffer length
    xor r14, r14              ; current offset

    ; Clear parsed fields
    mov byte [http_req_method], 0
    mov byte [http_req_path], 0
    mov byte [http_req_version], 0
    mov qword [http_req_method_idx], -1

    ; ============================================================
    ; METHOD: token before first space
    ; ============================================================
    lea rdi, [r12]            ; start scanning at buffer start
    mov rcx, r13              ; scan at most buffer length
    mov al, [http_space_char]
    repne scasb               ; rdi = space_pos + 1
    jne .no_method_space

    lea rbx, [rdi - 1]        ; rbx = space position
    mov rdx, rbx
    sub rdx, r12              ; rdx = method length
    test rdx, rdx
    jle .no_method_space

    ; Copy method (saved rdx = length, r12 = start)
    ; cap at 15 so null fits in http_req_method[16]
    cmp rdx, 15
    jle .method_len_ok
    mov rdx, 15
.method_len_ok:
    push rdx               ; save length for manual null-termination
    mov rdi, http_req_method
    mov rsi, r12
    call strncpy           ; clobbers rdi/rsi/rcx - fine, we use rbx/r12
    pop rdx
    mov byte [http_req_method + rdx], 0

    ; Save offset of the space for path extraction
    mov r14, rbx
    sub r14, r12

    ; ============================================================
    ; Match method against table using strcmp
    ; ============================================================
    mov r8, http_method_table
    xor r9d, r9d              ; index

.compare_loop:
    cmp r9d, HTTP_METHOD_COUNT
    jge .method_not_found

    movsxd r10, dword [r8]    ; sign-extend offset (strings precede table)
    lea rsi, [http_method_table + r10]
    mov rdi, http_req_method
    call strcmp
    test rax, rax
    jz .method_found

    add r8, 4
    inc r9d
    jmp .compare_loop

.method_found:
    mov qword [http_req_method_idx], r9
    jmp .extract_path

.method_not_found:
    mov rax, -1
    jmp .done

.no_method_space:
    mov rax, -1
    jmp .done

    ; ============================================================
    ; PATH: token between first space (offset r14) and second space
    ; ============================================================
.extract_path:
    lea rbx, [r12 + r14 + 1]  ; rbx = path start (after first space)
    mov rdi, rbx
    mov rcx, r13
    sub rcx, r14              ; remaining bytes after first space
    dec rcx
    mov al, [http_space_char]
    repne scasb               ; rdi = second_space_pos + 1
    jne .no_path_space

    lea rdx, [rdi - 1]        ; rdx = second space position
    sub rdx, rbx              ; rdx = path length
    test rdx, rdx
    jle .no_path_space

    ; Copy path
    ; cap at 255 so null fits in http_req_path[256]
    cmp rdx, 255
    jle .path_len_ok
    mov rdx, 255
.path_len_ok:
    push rdx               ; save length for manual null-termination
    mov rdi, http_req_path
    mov rsi, rbx
    call strncpy
    pop rdx
    mov byte [http_req_path + rdx], 0

    ; Update offset: past the second space
    lea r14, [rbx + rdx]      ; offset of second space (rbx+rdx = space pos)
    sub r14, r12              ; make it relative to buffer
    inc r14                   ; skip it
    jmp .extract_version

.no_path_space:
    ; No second space: path = rest of line (up to \r or \n)
    mov rdx, r13
    sub rdx, r14
    dec rdx
    ; trim trailing \r\n
    lea rax, [r12 + r14 + 1]
    add rax, rdx
    dec rax
    cmp byte [rax], 10
    jne .path_no_crlf
    dec rdx
    dec rax
    cmp byte [rax], 13
    jne .path_no_crlf
    dec rdx
.path_no_crlf:
    test rdx, rdx
    jle .no_path_space_short

    ; cap at 255 so null fits in http_req_path[256]
    cmp rdx, 255
    jle .path2_len_ok
    mov rdx, 255
.path2_len_ok:
    push rdx               ; save length for manual null-termination
    mov rdi, http_req_path
    lea rsi, [r12 + r14 + 1]
    call strncpy
    pop rdx
    mov byte [http_req_path + rdx], 0
    ; no version present
    xor rax, rax
    jmp .done

.no_path_space_short:
    mov rax, -1
    jmp .done

    ; ============================================================
    ; VERSION: token after second space (offset r14)
    ; ============================================================
.extract_version:
    lea rbx, [r12 + r14]      ; rbx = version start
    mov rcx, r13
    sub rcx, r14              ; remaining bytes

    ; trim trailing \r\n
    lea rdx, [rbx + rcx]
    dec rdx
    cmp byte [rdx], 10
    jne .ver_no_crlf
    dec rcx
    dec rdx
    cmp byte [rdx], 13
    jne .ver_no_crlf
    dec rcx
.ver_no_crlf:
    test rcx, rcx
    jle .no_version_space

    ; cap at 15 so null fits in http_req_version[16]
    cmp rcx, 15
    jle .ver_len_ok
    mov rcx, 15
.ver_len_ok:
    push rcx               ; save length for manual null-termination
    mov rdi, http_req_version
    mov rsi, rbx
    mov rdx, rcx
    call strncpy
    pop rcx
    mov byte [http_req_version + rcx], 0

    xor rax, rax              ; success
    jmp .done

.no_version_space:
    mov rax, -1
    jmp .done

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
