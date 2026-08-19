; =============================================================================
; const.inc - constants and node struct (included via ui.inc)
; =============================================================================

; asmx/ui/compile.asm - the @ DSL compiler (UI in page.s), pure asm.
; Pre-processes a page.s: finds @ DSL blocks inside section .data and
; replaces each block with:
;   1) the HTML shell <label>_shell (data-modules="/<ui_name>[/page].wasm")
;      - what res.content sends;
;   2) one .wat per component (build/<page>.s.d/<label>.wat);
;   3) the _main.wat orchestrator (render + theme + exports).
; The final module per page = framework lib + components, linked by the
; Makefile (cat -> wat2wasm) into static/<ui_name>[/page].wasm.
;
; Usage: ui-compile <src.s> <out.s>   (out = pre-processed NASM)
; Files without @ pass through untouched. Exit 0 ok / 1 error.
;
; The DSL core (tags, tailwind-ish classes, vertical auto layout) lives
; here; the tool reuses common/strings.asm (strcmp/strncmp/strlen/atoi/itoa).

%include "common/syscalls.inc"
%include "common/macros.inc"
%include "common/strings.asm"

; ----------------------------------------------------------------------
; constants
; ----------------------------------------------------------------------
%define O_RDONLY     0
%define O_WRONLY     1
%define O_CREAT      64
%define O_TRUNC      512
%define OUT_MODE     420             ; 0644

%define IN_CAP       65536
%define OUT_CAP      131072
%define BLOB_CAP     8192
%define WAT_CAP      65536
%define STR_BASE     148000

%define NODE_SIZE    72
%define MAX_NODES    64
%define MAX_STACK    32
%define MAX_RECORDS  128

; @@ components (expand.asm)
%define MAX_ARGS        16
%define ARG_ENTRY_SIZE  32      ; key_ptr, key_len, val_ptr, val_len (dq each)
%define MAX_COMP_DEPTH  16

; node struct offsets (u32 unless noted)
%define N_TAG        0               ; u8: 0=view 1=label 2=button
%define N_TEXT_PTR   2               ; u32 offset into in_buf (0 = no text)
%define N_TEXT_LEN   6               ; u32
%define N_BG         10              ; u32 0xRRGGBB (0 = default)
%define N_COLOR      14              ; u32
%define N_FS         18              ; u32
%define N_PAD        22              ; u32
%define N_MT         26              ; u32
%define N_MB         30              ; u32
%define N_W          34              ; u32 (0 = auto)
%define N_AX         38              ; u32
%define N_AY         42              ; u32
%define N_AW         46              ; u32
%define N_AH         50              ; u32
%define N_PARENT     54              ; i32 (-1 = root)
%define N_FIRST      58              ; i32
%define N_LAST       62              ; i32
%define N_NEXT       66              ; i32

; rec_order entry: 12 bytes (kind u32, node u32, parent_rec u32)
;   kind 0 = node record (tag), kind 1 = button view, kind 2 = button label
