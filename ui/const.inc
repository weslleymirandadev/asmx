; =============================================================================
; const.inc - constants and node struct (included via ui.inc)
; =============================================================================

; asx/ui/compile.asm - the @ DSL compiler (UI in page.s), pure asm.
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

%define NODE_SIZE    128
%define MAX_NODES    128
%define MAX_STACK    32
%define MAX_RECORDS  128

; @@ components (expand.asm)
%define MAX_ARGS        16
%define MAX_TYPED_PROPS  8
%define ARG_ENTRY_SIZE  32      ; key_ptr, key_len, val_ptr, val_len (dq each)
%define MAX_COMP_DEPTH  16

; node struct offsets (u32 unless noted)
%define N_TAG        0               ; u8: 0=view 1=label 2=button
%define N_TEXT_PTR   2               ; u32 offset into in_buf (0 = no text)
%define N_TEXT_LEN   6               ; u32
%define N_BG         10              ; u32 0xRRGGBB (0xFFFFFFFF = none)
%define N_COLOR      14              ; u32 (0xFFFFFFFF = none)
%define N_FS         18              ; u32
%define N_PAD        22              ; u32 (p-*)
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
%define N_FLAGS      70              ; u32 style flags (see F_* below)
%define N_GAP        74              ; u32 (gap-*)
%define N_RADIUS     78              ; u32 (rounded-*)
%define N_PX         82              ; u32 (px-*)
%define N_PY         86              ; u32 (py-*)
%define N_H          90              ; u32 explicit height (h-*)
%define N_WEIGHT     94              ; u32 font weight (font-*)
%define N_ALIGN      98              ; u32 0 left 1 center 2 right 3 justify
%define N_BORDER     102             ; u32 border width px
%define N_OPACITY    106             ; u32 0-100
%define N_SHADOW     110             ; u32 0 none 1 sm 2 md 3 lg 4 xl
%define N_BORDER_COLOR 114           ; u32 0xRRGGBB (0xFFFFFFFF = default)
%define N_PT         118             ; u32 padding-top (pt-*)
%define N_PB         122             ; u32 padding-bottom (pb-*)
%define N_GRID_COLS  126             ; u8 grid-template-columns count (grid-cols-N)

; style flags (N_FLAGS bits - u32 now)
%define F_FLEX       1
%define F_FLEXCOL    2
%define F_ITEMSC     4
%define F_ITEMSE     8
%define F_JUSTC      16
%define F_JUSTB      32
%define F_JUSTE      64
%define F_HIDDEN     128
%define F_WRAP       256
%define F_GROW       512
%define F_BOLD       1024
%define F_CENTER     2048
%define F_RIGHT      4096
%define F_UPPER      8192
%define F_ITALIC     16384
%define F_UNDER      32768
%define F_GRID       65536
%define F_JUSTA      131072          ; justify-around
%define F_JUSTV      262144          ; justify-evenly
%define F_ITEMST     524288          ; items-stretch
%define F_LOWER      1048576         ; lowercase
%define F_LINE       2097152         ; line-through (distinct from underline)
%define F_ITEMSS     4194304         ; items-start (explicit flex-start)

; rec_order entry: 12 bytes (kind u32, node u32, parent_rec u32)
;   kind 0 = node record (tag), kind 1 = button view, kind 2 = button label
; style record (20 bytes, emitted as a data segment + exported as styles()):
;   +0 flags u32 | +4 weight u16 | +6 align u8 | +7 gap u8 | +8 radius u8
;   +9 px u8 | +10 py u8 | +11 border u8 | +12 opacity u8 | +13 shadow u8
;   +14 role u8 (0 normal, 1 button) | +15 pad u8 | +16 mt u8 | +17 mb u8
;   +18 h u8 | +19 grid_cols u8
; NOTE: 20B record (was 16B) - weight became u16 (font-black=900 no longer
; truncates to 32) and flags grew to u32 (grid/justify-around/evenly/
; items-stretch/lowercase/line-through). ssr.asm + glue.asm + emit.asm
; must ALL agree on these offsets.

; ----------------------------------------------------------------------
; declarative state (ui/state.asm): types, states, interpolations, actions
; ----------------------------------------------------------------------
%define MAX_TYPES     8
%define MAX_FIELDS    16
%define MAX_STATES    8
%define MAX_DYN_TEXTS 16
%define MAX_ACTIONS   16
%define STR_DEFAULT_CAP 128

; field kinds
%define K_INT   0
%define K_BOOL  1
%define K_STR   2

; type entry (32B)
%define T_NAME_PTR    0
%define T_NAME_LEN    8
%define T_SIZE        16      ; u32 bytes total
%define T_N_FIELDS    24      ; u32
%define T_FIELDS_IDX  28      ; u32 (index into field_tab)
%define TYPE_ENTRY    32

; field entry (28B)
%define F_NAME_PTR    0
%define F_NAME_LEN    8
%define F_OFFSET      16      ; u32 offset within the type
%define F_KIND        20      ; u32 K_INT/K_BOOL/K_STR
%define F_STR_CAP     24      ; u32 (strings only; 0 = STR_DEFAULT_CAP)
%define FIELD_ENTRY   28

; state entry (32B)
%define S_NAME_PTR    0
%define S_NAME_LEN    8
%define S_TYPE_IDX    16      ; u32 (-1 = scalar)
%define S_DATA_OFF    20      ; u32 offset in the state data area
%define S_IS_OBJ      24      ; u32 0 = scalar, 1 = object
%define S_KIND        28      ; u32 scalar kind (K_INT/K_BOOL) or -1 for objects
%define STATE_ENTRY   32

; dyn text entry (24B): a text widget with {state} / {state.field}
%define D_NODE        0       ; u32 node idx
%define D_STATE       4       ; u32 state idx
%define D_FIELD       8       ; u32 field idx (-1 = scalar)
%define D_PREFIX_LEN  12      ; u32 bytes before the placeholder
%define D_SUFFIX_OFF  16      ; u32 offset of the suffix in in_buf
%define D_SUFFIX_LEN  20      ; u32
%define DYN_ENTRY     24

; action entry (32B): an onclick on a button widget
%define A_WIDGET      0       ; u32 record idx of the button view
%define A_STATE       4       ; u32 state idx
%define A_FIELD       8       ; u32 field idx (-1 = scalar)
%define A_OP          12      ; u32 OP_*
%define A_OPERAND     16      ; u32 int value / bool 0-1 / in_buf offset of str
%define ACTION_ENTRY  32

; action ops
%define OP_INC        1
%define OP_DEC        2
%define OP_SET        3       ; = operand
%define OP_ADD        4       ; += operand
%define OP_SUB        5       ; -= operand
%define OP_SET_TRUE   6
%define OP_SET_FALSE  7
