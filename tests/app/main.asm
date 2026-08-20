; tests/app/main.asm - asx app entry (CI fixture)
; Mirrors src/main.asm of the example app.

section .text
global _start
_start:
    asx.listen 3000
    jmp route_dispatch
