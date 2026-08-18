; src/json/json.inc
; JSON domain interface - parser + stringifier for the asmx framework.
; Pure interface: only includes, constants and docs. NO symbols declared
; (each .asm declares the externs it uses - see common.inc pattern).
;
; Include from app code with:  %include "json/json.inc"   (-I asmx)

%ifndef JSON_INC
%define JSON_INC

%include "common/common.inc"

; ----------------------------------------------------------------------
; JSON value types (returned by json_find in rcx)
; ----------------------------------------------------------------------
%define JSON_T_STRING  0
%define JSON_T_NUMBER  1
%define JSON_T_OBJECT  2
%define JSON_T_ARRAY   3
%define JSON_T_BOOL    4
%define JSON_T_NULL    5

; ----------------------------------------------------------------------
; API REGISTRY (documentation only)
; ----------------------------------------------------------------------
; parse.asm      : json_parse (full-document validation)
;                  json_skip_ws, json_parse_string, json_skip_value
;                  (internal helpers, exported for json_find)
; find.asm       : json_find (extract a value by key from the root object)
; stringify.asm  : json_str_int, json_str_bool, json_str_null,
;                  json_str_string (escaped, snprintf-like)
;
; Usage:
;   ; validate a POST body before touching it
;   call http_get_body          ; rax = body ptr
;   call http_get_body_len      ; rax = body len
;   mov rdi, <body ptr>
;   mov rsi, <body len>
;   call json_parse             ; rax = 0 ok / -1 invalid
;
;   ; read a field from the root object
;   mov rdi, <body ptr>
;   mov rsi, <body len>
;   lea rdx, [my_key]           ; null-terminated key
;   call json_find              ; rax = value ptr, rdx = value len,
;                               ; rcx = type; rax = -1 if key missing
;                               ; (strings: ptr = content, no quotes)
;
;   ; build a response body with the stringifier primitives - they write
;   ; at rsi and return the length in rax, so concatenate into your own
;   ; buffer (resp_buf is only 512 bytes - use a .bss buffer for payloads):
;   ;   lea rdi, [my_json]      ; resb 128
;   ;   lea rsi, [open_obj]     ; '{"n":'
;   ;   call json_str_string?   ; no - see below
;   ;   mov rdi, 42
;   ;   lea rsi, [dst]
;   ;   call json_str_int       ; rax = 2, dst = "42"
;   ;   ... (keys/commas are plain strings - use memcpy/strcpy or db blocks)
;
;   Stringifier primitives write AT rsi and return the length in rax:
;     json_str_int(rdi = value, rsi = dst) -> rax = len
;     json_str_bool(rdi = 0/1, rsi = dst) -> rax = len
;     json_str_null(rsi = dst) -> rax = len
;     json_str_string(rdi = src, rsi = dst, rdx = cap) -> rax = total len
;       (writes what fits in cap, returns the full length needed, like
;       snprintf; escapes " \ \b \f \n \r \t and other <0x20 as \u00XX)

%endif
