; src/http/mime.asm
; MIME type lookup for static files.
; mime_lookup(rdi = filename) -> rax = content-type line ptr, rdx = len
; The returned line is a full header template ("Content-Type: X\r\n"),
; same shape as ct_json/ct_html in state.asm - ready to copy into the
; response header. Unknown extensions fall back to octet-stream.

%include "http/http.inc"

extern strcmp
extern ct_html, ct_html_len, ct_json, ct_json_len, ct_text, ct_text_len

section .data
    ct_wasm db "Content-Type: application/wasm", 13, 10
    ct_wasm_len equ $ - ct_wasm
    ct_css  db "Content-Type: text/css", 13, 10
    ct_css_len equ $ - ct_css
    ct_js   db "Content-Type: application/javascript", 13, 10
    ct_js_len equ $ - ct_js
    ct_png  db "Content-Type: image/png", 13, 10
    ct_png_len equ $ - ct_png
    ct_jpg  db "Content-Type: image/jpeg", 13, 10
    ct_jpg_len equ $ - ct_jpg
    ct_gif  db "Content-Type: image/gif", 13, 10
    ct_gif_len equ $ - ct_gif
    ct_webp db "Content-Type: image/webp", 13, 10
    ct_webp_len equ $ - ct_webp
    ct_svg  db "Content-Type: image/svg+xml", 13, 10
    ct_svg_len equ $ - ct_svg
    ct_avif db "Content-Type: image/avif", 13, 10
    ct_avif_len equ $ - ct_avif
    ct_ico  db "Content-Type: image/x-icon", 13, 10
    ct_ico_len equ $ - ct_ico
    ct_mp4  db "Content-Type: video/mp4", 13, 10
    ct_mp4_len equ $ - ct_mp4
    ct_webm db "Content-Type: video/webm", 13, 10
    ct_webm_len equ $ - ct_webm
    ct_ogg  db "Content-Type: video/ogg", 13, 10
    ct_ogg_len equ $ - ct_ogg
    ct_mov  db "Content-Type: video/quicktime", 13, 10
    ct_mov_len equ $ - ct_mov
    ct_octet db "Content-Type: application/octet-stream", 13, 10
    ct_octet_len equ $ - ct_octet

    ext_wasm db ".wasm", 0
    ext_html db ".html", 0
    ext_css  db ".css", 0
    ext_js   db ".js", 0
    ext_png  db ".png", 0
    ext_jpg  db ".jpg", 0
    ext_jpeg db ".jpeg", 0
    ext_gif  db ".gif", 0
    ext_webp db ".webp", 0
    ext_svg  db ".svg", 0
    ext_avif db ".avif", 0
    ext_ico  db ".ico", 0
    ext_mp4  db ".mp4", 0
    ext_webm db ".webm", 0
    ext_ogg  db ".ogg", 0
    ext_mov  db ".mov", 0
    ext_json db ".json", 0
    ext_txt  db ".txt", 0

section .text

global mime_lookup
mime_lookup:
    push r12
    mov r12, rdi              ; filename

    ; find last '.' - offset kept in rcx (0 = none)
    xor rcx, rcx
    xor rax, rax
.find_dot:
    cmp byte [r12 + rcx], 0
    je .dot_done
    cmp byte [r12 + rcx], '.'
    jne .next_char
    mov rax, rcx
.next_char:
    inc rcx
    jmp .find_dot
.dot_done:
    test rax, rax
    jz .default_ct            ; no extension

    ; extension ptr = filename + last_dot_offset
    lea r12, [r12 + rax]

    ; strcmp chain - strcmp clobbers rdi/rsi/rcx, so reload both args
    mov rdi, r12
    lea rsi, [ext_wasm]
    call strcmp
    test rax, rax
    jz .wasm
    lea rsi, [ext_html]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .html
    lea rsi, [ext_css]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .css
    lea rsi, [ext_js]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .js
    lea rsi, [ext_png]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .png
    lea rsi, [ext_jpg]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .jpg
    lea rsi, [ext_jpeg]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .jpg
    lea rsi, [ext_gif]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .gif
    lea rsi, [ext_webp]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .webp
    lea rsi, [ext_svg]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .svg
    lea rsi, [ext_avif]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .avif
    lea rsi, [ext_ico]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .ico
    lea rsi, [ext_mp4]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .mp4
    lea rsi, [ext_webm]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .webm
    lea rsi, [ext_ogg]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .ogg
    lea rsi, [ext_mov]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .mov
    lea rsi, [ext_json]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .json
    lea rsi, [ext_txt]
    mov rdi, r12
    call strcmp
    test rax, rax
    jz .txt
    jmp .default_ct

.wasm:
    lea rax, [ct_wasm]
    mov rdx, ct_wasm_len
    jmp .done
.html:
    lea rax, [ct_html]
    mov rdx, ct_html_len
    jmp .done
.css:
    lea rax, [ct_css]
    mov rdx, ct_css_len
    jmp .done
.js:
    lea rax, [ct_js]
    mov rdx, ct_js_len
    jmp .done
.png:
    lea rax, [ct_png]
    mov rdx, ct_png_len
    jmp .done
.jpg:
    lea rax, [ct_jpg]
    mov rdx, ct_jpg_len
    jmp .done
.gif:
    lea rax, [ct_gif]
    mov rdx, ct_gif_len
    jmp .done
.webp:
    lea rax, [ct_webp]
    mov rdx, ct_webp_len
    jmp .done
.svg:
    lea rax, [ct_svg]
    mov rdx, ct_svg_len
    jmp .done
.avif:
    lea rax, [ct_avif]
    mov rdx, ct_avif_len
    jmp .done
.ico:
    lea rax, [ct_ico]
    mov rdx, ct_ico_len
    jmp .done
.mp4:
    lea rax, [ct_mp4]
    mov rdx, ct_mp4_len
    jmp .done
.webm:
    lea rax, [ct_webm]
    mov rdx, ct_webm_len
    jmp .done
.ogg:
    lea rax, [ct_ogg]
    mov rdx, ct_ogg_len
    jmp .done
.mov:
    lea rax, [ct_mov]
    mov rdx, ct_mov_len
    jmp .done
.json:
    lea rax, [ct_json]
    mov rdx, ct_json_len
    jmp .done
.txt:
    lea rax, [ct_text]
    mov rdx, ct_text_len
    jmp .done
.default_ct:
    lea rax, [ct_octet]
    mov rdx, ct_octet_len
.done:
    pop r12
    ret
