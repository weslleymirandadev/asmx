; utils/syscalls.inc
; Linux x86-64 syscall numbers
; Reference: /usr/include/asm/unistd_64.h

%ifndef SYSCALLS_INC
%define SYSCALLS_INC

%define SYS_read         0
%define SYS_write        1
%define SYS_open         2
%define SYS_rt_sigaction 13
%define SYS_close        3
%define SYS_fstat        5
%define SYS_mmap         9
%define SYS_munmap       11
%define SYS_socket       41
%define SYS_accept       43
%define SYS_bind         49
%define SYS_listen       50
%define SYS_setsockopt   54
%define SYS_fork         57
%define SYS_clone        56
%define SYS_exit         60
%define SYS_epoll_ctl   233
%define SYS_epoll_wait  232
%define SYS_openat      257
%define SYS_epoll_create1 291
%endif
