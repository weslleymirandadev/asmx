; src/http/http.inc
; HTTP module interface - THE parent file
; Every src/http/*.asm starts with: %include "http/http.inc"
;
; Pure interface: utils, constants, conventions. Defines NO symbols
; (no extern/global) so including it never causes "inconsistently
; redefined" errors. Each .asm declares the externs IT needs.

%ifndef HTTP_INC
%define HTTP_INC

%include "common/common.inc"

; ---------------------------------------------------------------
; HTTP method constants (order must match http_state.asm table)
; ---------------------------------------------------------------
%define HTTP_M_GET      0
%define HTTP_M_POST     1
%define HTTP_M_PUT      2
%define HTTP_M_DELETE   3
%define HTTP_M_HEAD     4
%define HTTP_M_OPTIONS  5
%define HTTP_M_UNKNOWN  -1

; Number of entries in the method table (must match the table in http_state.asm)
%define HTTP_METHOD_COUNT 6

; ---------------------------------------------------------------
; CONVENTIONS - follow these to keep the codebase uniform
; ---------------------------------------------------------------
; Naming     : public symbols = http_<thing>; file = <thing>.asm
; Registers  : args rdi,rsi,rdx,rcx (SysV); return in rax
; Preserve   : rbx, r12-r15 (push at entry, pop before ret)
; Errors     : return -1 in rax; never die() from library code
; New module : create <feature>.asm -> %include "http.inc" ->
;              extern what you USE -> global what you EXPORT ->
;              register it in the API list below (docs only)
; Build      : Makefile globs src/http/*.asm automatically

; ---------------------------------------------------------------
; API REGISTRY (documentation only - externs go in each .asm)
; ---------------------------------------------------------------
; http_state.asm    : http_req_method, http_req_path, http_req_version,
;                     http_req_method_idx, http_line_start/end/count,
;                     http_method_table, http_method_count,
;                     http_response_200/405/404 + *_len,
;                     http_space_char, http_newline_char, http_cr_char
; getters.asm       : http_get_method, http_get_path, http_get_method_idx,
;                     http_get_body, http_get_body_len
; request_line.asm  : http_parse_request_line
; header_parse.asm  : http_parse_headers
; method_check.asm  : http_method_includes
; line_scanner.asm  : http_scan_lines
; response.asm      : http_send_response, http_send_method_denied,
;                     http_send_not_found
; mime.asm          : mime_lookup (ext -> Content-Type header line)
; static.asm        : http_serve_static (stream public/<path>)
; handler.asm       : handle_client (entry point called by main.asm)

%endif
