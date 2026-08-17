; src/common/common.inc
; Common library interface
; Include from any file that needs syscalls, macros, or string functions:
;   %include "common/common.inc"
; Leaf interface: only includes and docs. No symbols defined here.

%ifndef COMMON_INC
%define COMMON_INC

%include "common/syscalls.inc"
%include "common/macros.inc"
%include "common/strings.inc"

; API (defined in this domain):
;   strings.asm: strcmp, strncmp, strlen, strncpy, strstr, atoi, itoa
;   errors.asm:  die, socket_error, bind_error, listen_error, accept_error,
;                read_error, write_error
%endif
