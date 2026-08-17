; src/common/errors.asm
; Error handling routines

%include "common/common.inc"

global die
global socket_error
global bind_error
global listen_error
global accept_error
global read_error
global write_error

section .rodata
    ; Error messages in English, one per line
    socket_err_msg db "Error: socket failed", 10
    socket_err_len equ $ - socket_err_msg

    bind_err_msg db "Error: bind failed", 10
    bind_err_len equ $ - bind_err_msg

    listen_err_msg db "Error: listen failed", 10
    listen_err_len equ $ - listen_err_msg

    accept_err_msg db "Error: accept failed", 10
    accept_err_len equ $ - accept_err_msg

    read_err_msg db "Error: read failed", 10
    read_err_len equ $ - read_err_msg

    write_err_msg db "Error: write failed", 10
    write_err_len equ $ - write_err_msg

section .text

; die() - exit with error code 1
die:
    exit_code 1

; socket_error() - report socket error and exit
socket_error:
    write_stderr socket_err_msg, socket_err_len
    exit_code 1

; bind_error() - report bind error and exit
bind_error:
    write_stderr bind_err_msg, bind_err_len
    exit_code 1

; listen_error() - report listen error and exit
listen_error:
    write_stderr listen_err_msg, listen_err_len
    exit_code 1

; accept_error() - report accept error and exit
accept_error:
    write_stderr accept_err_msg, accept_err_len
    exit_code 1

; read_error() - report read error and exit
read_error:
    write_stderr read_err_msg, read_err_len
    exit_code 1

; write_error() - report write error and exit
write_error:
    write_stderr write_err_msg, write_err_len
    exit_code 1
