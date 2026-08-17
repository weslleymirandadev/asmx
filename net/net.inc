; src/net/net.inc
; Network layer interface
; Include from any file that needs network setup:
;   %include "net/net.inc"
; Provides: common (syscalls/macros/strings) + net API docs

%ifndef NET_INC
%define NET_INC

%include "common/common.inc"

; API (defined in net.asm):
;   socket_bind_listen(port) -> rax = server_fd
;   Uses: socket_error, bind_error, listen_error (common/errors.asm)
%endif
