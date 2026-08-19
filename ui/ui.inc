; ui.inc - final include of the @ DSL compiler (module order)
; NASM assembles everything as one unit: .data/.bss/.text sections accumulate.
; (ui/-prefixed paths resolve via -I asx)
%include "ui/const.inc"
%include "ui/literals.inc"
%include "ui/tables.inc"
%include "ui/bss.inc"
%include "ui/main.asm"
%include "ui/io.asm"
%include "ui/process.asm"
%include "ui/expand.asm"
%include "ui/parse.asm"
%include "ui/layout.asm"
%include "ui/serialize.asm"
%include "ui/emit.asm"
%include "ui/ssr.asm"
%include "ui/mainwat.asm"
%include "ui/write.asm"
%include "ui/out.asm"
