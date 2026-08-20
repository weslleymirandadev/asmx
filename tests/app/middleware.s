; tests/app/middleware.s - pass-through middleware (CI fixture).
; The router scans the `middleware` linker section; this fixture registers
; one handler that lets everything through (mw.next).

middleware mw_pass

section .MIDDLEWARE
mw_pass:
    mw.next
