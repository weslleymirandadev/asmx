; =============================================================================
; bss.inc - global variables (section .bss)
; =============================================================================


; ----------------------------------------------------------------------
section .bss
in_buf:       resb IN_CAP
in_len:       resq 1
out_buf:      resb OUT_CAP
out_len:      resq 1
blob_buf:     resb BLOB_CAP
blob_len:     resq 1
label_buf:    resb 64
label_len:    resq 1
nodes:        resb MAX_NODES * NODE_SIZE
node_count:   resq 1
istack:       resb MAX_STACK * 8       ; (indent u32, idx u32)
stack_top:    resq 1
rec_order:    resb MAX_RECORDS * 12    ; (kind u32, node u32, parent u32)
rec_count:    resq 1
theme_bg:     resq 1
theme_text:   resq 1
theme_accent: resq 1
theme_given:  resq 1
itoa_buf:     resb 12
src_path:     resq 1
out_path:     resq 1
ui_name_buf:  resb 64
ui_name_len:  resq 1
str_cursor:   resq 1
wat_buf:      resb WAT_CAP
wat_len:      resq 1
main_buf:     resb WAT_CAP
main_len:     resq 1
main_started: resq 1
wat_count:    resq 1
mkdir_done:   resq 1
path_buf:     resb 512
local_of:     resb MAX_RECORDS * 4
