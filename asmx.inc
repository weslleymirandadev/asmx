; __asmx__/asmx.inc
; asmx - mini web framework over the assembly HTTP server
; Package root: __asmx__/ (npm-style). App code lives in src/
; (src/main.asm + src/app/**/route.s). Include from anywhere with
;   %include "asmx.inc"     (ASFLAGS: -I __asmx__)
;
; Usage in your app (current pattern - port 3000 by default):
;
;   section .data
;       my_json db '{"ok": true}', 0
;
;   section .text
;   global _start
;   _start:
;       asmx.listen 3000      ; bind + accept loop
;       jmp route_dispatch    ; Next.js-style file routing
;
;   ; Routes: `route get_h, post_h, ...` for APIs (section .GET/.POST),
;   ; `page handler` for pages (implicit GET, section .SERVER), custom
;   ; 404 via src/app/not-found.s. Handlers respond and return:
;   ;
;   ;   section .POST
;   ;   post_h:
;   ;       res.json my_json
;   ;       asmx.next
;
;   ; UI lives IN the page.s, declared with the @ DSL (tailwind-like):
;   ; asmx/ui/ui-compile (pure assembly, zero Python) pre-processes the
;   ; @ block into (1) the HTML shell <label>_shell (data-modules),
;   ; (2) one .wat per component, (3) a _main.wat; the Makefile links
;   ; the framework wasm lib + those .wat -> static/<route>/page.wasm
;   ; (root: static/index.wasm), rendered by the glue. res.content sends
;   ; the shell:
;   ;
;   ;   section .data
;   ;       sobre_content:
;   ;           @main bg-black text-white min-h-screen p-8
;   ;               @h1 text-4xl font-bold
;   ;                   "Sobre o ASMX"
;   ;               @p text-gray-400
;   ;                   "Fullstack Assembly + WebAssembly"
;   ;           @end
;   ;
;   ;   page get_sobre
;   ;
;   ;   section .SERVER
;   ;   get_sobre:
;   ;       res.content sobre_content
;   ;       asmx.next
;
; NOTE: `requests` is a reserved symbol (the accept loop). Do NOT define
; a label named `requests` in your app - use `jmp requests` (or
; `asmx.next`) to return to the accept loop after responding.

%ifndef ASMX_INC
%define ASMX_INC

%include "common/common.inc"
%include "net/net.inc"
%include "http/http.inc"
%include "json/json.inc"

; ----------------------------------------------------------------------
; Public API (defined in src/asmx/*.asm)
; ----------------------------------------------------------------------
; core.asm    : asmx_listen, requests (accept loop label)
; router.asm  : route_dispatch (Next.js-style path+method dispatch)
; send.asm    : asmx_send_json, asmx_send_text, asmx_send_html, asmx_send_status
; state.asm   : route (current path buffer), buffer, resp_buf, client_fd,
;               http_200, ct_json, ct_text, ct_html, status_table...
; helpers.asm : memcpy_adv, strcpy_adv (internal)
extern asmx_listen
extern asmx_send_json
extern asmx_send_text
extern asmx_send_html
extern asmx_send_status
extern asmx_send_bytes
extern route_dispatch
extern route
extern slug_buf
extern slug_len
extern requests
; Request accessors available to handlers (http/getters.asm)
extern http_get_method_idx
extern http_get_body
extern http_get_body_len
; Request object wrappers (asmx/req.asm) + method string buffer
extern asmx_req_body
extern asmx_req_body_len
extern asmx_req_get
extern asmx_req_has
extern http_req_method
; SSR helper (asmx/ssr.asm)
extern ssr_render
; JSON domain (json/*.asm) - available through the json. object macros
extern json_parse
extern json_find
extern json_str_int
extern json_str_bool
extern json_str_null
extern json_str_string
; Content-type templates (asmx/state.asm) - used by send_*_bytes macros
extern ct_json, ct_json_len
extern ct_ui, ct_ui_len

; ----------------------------------------------------------------------
; listen PORT - create listening socket and enter the accept loop.
; The code that follows the macro runs once per request.
; ----------------------------------------------------------------------
%macro listen 1
    mov rdi, %1
    call asmx_listen          ; never returns
%endmacro

; ----------------------------------------------------------------------
; cmp a, b - if b is a string literal, compares `route` against it with
; strcmp (ZF set if equal, so `je`/`jne` work). Otherwise falls back to
; the native cmp instruction.
; Strings are emitted inline with a jump-over-data pattern.
; ----------------------------------------------------------------------
%macro cmp 2
    %ifstr %2
        jmp %%skip
    %%str:
        db %2, 0
    %%skip:
        lea rsi, [%%str]
        mov rdi, route
        call strcmp
        test rax, rax
    %else
        cmp %1, %2
    %endif
%endmacro

; ----------------------------------------------------------------------
; Response helpers - send a 200 with the given null-terminated payload.
; ----------------------------------------------------------------------
%macro send_json 1
    mov rdi, %1
    call asmx_send_json
%endmacro

%macro send_text 1
    mov rdi, %1
    call asmx_send_text
%endmacro

%macro send_html 1
    mov rdi, %1
    call asmx_send_html
%endmacro

; ----------------------------------------------------------------------
; send_status CODE - respond with a status code and empty body
; (e.g. send_status 404)
; ----------------------------------------------------------------------
%macro send_status 1
    mov rdi, %1
    call asmx_send_status
%endmacro

; ----------------------------------------------------------------------
; send_json_bytes PTR, LEN - respond 200 with raw JSON of explicit length
; (for request bodies / data without null terminator)
; ----------------------------------------------------------------------
%macro send_json_bytes 2
    mov rdi, %1
    mov rsi, %2
    lea rdx, [ct_json]
    mov rcx, ct_json_len
    call asmx_send_bytes
%endmacro

; ----------------------------------------------------------------------
; body_get_json BODY_PTR_VAR, BODY_LEN_VAR - load the request body into
; two user-reserved qwords (declare them in your .bss, resq 1 each).
;   section .bss
;       req_body resq 1
;       req_len  resq 1
;   section .POST
;   post_user:
;       body_get_json req_body, req_len
;       send_json_bytes [req_body], [req_len]   ; echo the body back
; BODY_LEN_VAR can be 0 (POST without body).
; ----------------------------------------------------------------------
%macro body_get_json 2
    call http_get_body
    mov [%1], rax
    call http_get_body_len
    mov [%2], rax
%endmacro

; ----------------------------------------------------------------------
; File routes (Next.js-style) - route declaration
;   route get_user, post_user      (0 = method not supported)
;
;   section .GET
;   get_user:
;       send_json user_data
;       jmp requests
;
; The route PATH is NOT declared here - it derives from the file location
; at build time (Makefile passes -DROUTE_PATH="..."), exactly like Next.js:
;   src/app/page.s            -> "/"
;   src/app/sobre/page.s      -> "/sobre"
;   src/app/api/hello/route.s -> "/api/hello"
;   src/app/not-found.s       -> "/__not_found" (reserved 404 route)
; Static files are NOT routes: anything in static/ is served automatically
; by the router fallback (asmx/router.asm), no route declaration needed.
;
; Emits one 24-byte entry in the `route` section (dq path, GET, POST);
; GNU ld defines __start_route/__stop_route over it and the router
; (asmx/router.asm) scans it to dispatch. `.GET`/`.POST` are pre-declared
; as CODE sections below - NASM defaults unknown section names to DATA,
; which would make handlers non-executable (segfault).
; ----------------------------------------------------------------------
section .GET exec progbits align=16
section .POST exec progbits align=16
section .PUT exec progbits align=16
section .PATCH exec progbits align=16
section .DELETE exec progbits align=16
section .SERVER exec progbits align=16
section .CLIENT progbits align=16

; route GET, POST, PUT, PATCH, DELETE (0 = method not supported).
; All 5 args are REQUIRED - NASM expands omitted macro args as empty
; (the declared default only fills the first missing one), so wrappers
; pass the zeros explicitly.
%macro route 5
    section .data
    %%path: db ROUTE_PATH, 0
    section route
    dq %%path, %1, %2, %3, %4, %5
    section .text
%endmacro

; ----------------------------------------------------------------------
; page HANDLER - page route with IMPLICIT GET (Next.js: pages are
; GET-only; POST gets an automatic 405). Page code lives in
; `section .SERVER` (runs on the server, SSR); client assets live in
; `section .CLIENT` and are injected into the HTML by ssr_render.
; ----------------------------------------------------------------------
%macro page 1
    route %1, 0, 0, 0, 0
%endmacro

; ----------------------------------------------------------------------
; client "PATH" - register a client asset (e.g. "/app.wasm"). Each entry
; goes into the `client` linker section (__start_client/__stop_client),
; which ssr_render turns into <script src="PATH"></script> tags.
; ----------------------------------------------------------------------
%macro client 1
    section .data
    %%path: db %1, 0
    section client
    dq %%path
    section .text
%endmacro

; ----------------------------------------------------------------------
; component "name" - declare a WASM UI component for the page (like
; <Component/> in React). LEGACY (kept for compatibility): the UI now
; lives in the page.s @ DSL (see res.content); this macro only registers
; data-modules entries for hand-written src/ui/<name>.wat modules built
; by the Makefile into static/<name>.wasm.
; ----------------------------------------------------------------------
%macro component 1
    section .data
    %%path: db "/", %1, ".wasm", 0
    section ui_modules
    dq %%path
    section .text
%endmacro

; ----------------------------------------------------------------------
; Objects (dot notation) - the framework as a "class".
; Properties are %define aliases (zero cost), methods are %macro wrappers
; around the existing functions. Everything resolves at assembly time.
;
;   asmx.listen PORT     bind + accept loop (alias of `listen`)
;   asmx.next            end the handler (jmp requests)
;
;   req.path             current path buffer (property)
;   req.method           method string "GET" (property)
;   req.method_idx       rax = method index (GET=0, POST=1)
;   req.body             rax = POST body ptr
;   req.body_len         rax = POST body len
;   req.get "key"        json_find over the body (rax/rdx/rcx, -1 if missing)
;   req.has "key"        rax = 1 if key exists
;
;   res.json/text/html PTR    respond 200 with that content type
;   res.status CODE           respond with a status code, empty body
;   res.bytes PTR, LEN        respond 200 JSON, explicit length
;   res.content PTR           page.s @ DSL block: sends the HTML shell
;                             (<label>_shell built by asmx/ui/ui-compile)
;                             whose glue loads <route>/page.wasm (the
;                             per-route UI module from static/).
;
;   json.parse BUF, LEN
;   json.find BUF, LEN, "key"
;   json.str_int VALUE, DST | json.str_bool VALUE, DST | json.str_null DST
;   json.str_string SRC, DST, CAP
;
;   route.get HANDLER / route.post HANDLER / route.put HANDLER /
;   route.patch HANDLER / route.delete HANDLER / route.both GET, POST
;   (or route GET, POST, PUT, PATCH, DELETE - 0 = not supported)
; ----------------------------------------------------------------------
%macro asmx.listen 1
    mov rdi, %1
    call asmx_listen
%endmacro

%macro asmx.next 0
    jmp requests
%endmacro

%define req.path    route
%define req.method  http_req_method

; req.slug - dynamic route slug ("/profile/joao" on /profile/[id] ->
; "joao"). Null-terminated string buffer; the macro leaves the pointer
; in rdi and the length in rsi. Empty ("") for static routes.
%macro req.slug 0
    lea rdi, [slug_buf]
    mov rsi, [slug_len]
%endmacro

%macro req.method_idx 0
    call http_get_method_idx
%endmacro

%macro req.body 0
    call asmx_req_body
%endmacro

%macro req.body_len 0
    call asmx_req_body_len
%endmacro

%macro req.get 1
    %ifstr %1
        jmp %%skip
    %%key: db %1, 0
    %%skip:
        lea rdi, [%%key]
    %else
        lea rdi, [%1]
    %endif
    call asmx_req_get
%endmacro

%macro req.has 1
    %ifstr %1
        jmp %%skip
    %%key: db %1, 0
    %%skip:
        lea rdi, [%%key]
    %else
        lea rdi, [%1]
    %endif
    call asmx_req_has
%endmacro

%macro res.json 1
    mov rdi, %1
    call asmx_send_json
%endmacro

%macro res.text 1
    mov rdi, %1
    call asmx_send_text
%endmacro

%macro res.html 1
    mov rdi, %1
    call asmx_send_html
%endmacro

%macro res.status 1
    mov rdi, %1
    call asmx_send_status
%endmacro

%macro res.bytes 2
    mov rdi, %1
    mov rsi, %2
    lea rdx, [ct_json]
    mov rcx, ct_json_len
    call asmx_send_bytes
%endmacro

; ----------------------------------------------------------------------
; res.content PTR - send the page shell of an @ DSL block (page.s).
; The @ block compiler (asmx/ui/ui-compile) generates, next to the UI
; shell <label>_shell (the page container with
; data-modules="/<route>[/page].wasm" + the framework glue script) and
; one .wat per component + a _main.wat. The Makefile links them with
; the framework wasm lib -> static/<route>/page.wasm (root:
; static/index.wasm), which the glue instantiates and renders.
; ----------------------------------------------------------------------
%macro res.content 1
    mov rdi, %1%+_shell
    call asmx_send_html
%endmacro

%macro json.parse 2
    mov rdi, %1
    mov rsi, %2
    call json_parse
%endmacro

%macro json.find 3
    mov rdi, %1
    mov rsi, %2
    %ifstr %3
        jmp %%skip
    %%key: db %3, 0
    %%skip:
        lea rdx, [%%key]
    %else
        lea rdx, [%3]
    %endif
    call json_find
%endmacro

%macro json.str_int 2
    mov rdi, %1
    mov rsi, %2
    call json_str_int
%endmacro

%macro json.str_bool 2
    mov rdi, %1
    mov rsi, %2
    call json_str_bool
%endmacro

%macro json.str_null 1
    mov rsi, %1
    call json_str_null
%endmacro

%macro json.str_string 3
    mov rdi, %1
    mov rsi, %2
    mov rdx, %3
    call json_str_string
%endmacro

%macro route.get 1
    route %1, 0, 0, 0, 0
%endmacro

%macro route.post 1
    route 0, %1, 0, 0, 0
%endmacro

%macro route.put 1
    route 0, 0, %1, 0, 0
%endmacro

%macro route.patch 1
    route 0, 0, 0, %1, 0
%endmacro

%macro route.delete 1
    route 0, 0, 0, 0, %1
%endmacro

%macro route.both 2
    route %1, %2, 0, 0, 0
%endmacro

%endif
