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
comp_buf:     resb IN_CAP
comp_len:     resq 1
expand_buf:   resb IN_CAP
expand_len:   resq 1
arg_list:     resb MAX_ARGS * ARG_ENTRY_SIZE
arg_count:    resq 1
tp_props:     resb MAX_TYPED_PROPS * 136  ; {state_name[64], state_len u32, type_name[64], type_len u32}
                                ; names are COPIED: the @@ splice overwrites
                                ; the line the offsets pointed into
tp_prop_count: resq 1
comp_path:    resb 512
comp_name:    resb 64
comp_name_len: resq 1
comp_stack:   resb MAX_COMP_DEPTH * 8
comp_depth:   resq 1
save_label_buf: resb 64
save_label_len: resq 1
style_buf:    resb MAX_RECORDS * 20   ; style records (flags u32/weight u16/...)
style_len:    resq 1
style_addr:   resq 1                  ; wasm address of the styles data segment
variant_tab:  resb MAX_VARIANTS * VAR_ENTRY
variant_count: resq 1
node_tmp:     resb NODE_SIZE          ; scratch copy for variant diffing
; html attributes per node: attr_buf holds 'name="value" ...' strings,
; attr_off/attr_len are per-node offsets into it (0 = no attributes)
attr_buf:     resb 4096
attr_cur:     resq 1
attr_off:     resd MAX_NODES
attr_len:     resd MAX_NODES
ssr_stack:    resb MAX_RECORDS * 8    ; open-view stack for SSR HTML emission
ssr_top:      resq 1
; declarative state tables
type_tab:     resb MAX_TYPES * TYPE_ENTRY
type_count:   resq 1
field_tab:    resb MAX_FIELDS * FIELD_ENTRY
field_count:  resq 1
state_tab:    resb MAX_STATES * STATE_ENTRY
state_count:  resq 1
dyn_tab:      resb MAX_DYN_TEXTS * DYN_ENTRY
dyn_count:    resq 1
action_tab:   resb MAX_ACTIONS * ACTION_ENTRY
action_count: resq 1
state_data:   resb 512                ; initial values of the states
state_data_len: resq 1
state_str_buf: resb 512               ; bytes of the state strings
state_str_len: resq 1
state_base_addr: resq 1               ; wasm address of the state data segment
state_str_base: resq 1                ; str_cursor offset where state strings start
dyn_tmp_buf:  resb 64                 ; per-state resolved-value scratch
dyn_dst:      resb MAX_DYN_TEXTS * 4  ; wasm addrs of the dyn texts (montage)
dyn_prefix:   resb MAX_DYN_TEXTS * 4  ; wasm addrs of the dyn prefixes
dyn_suffix:   resb MAX_DYN_TEXTS * 4  ; wasm addrs of the dyn suffixes
dyn_parts_len: resq 1                 ; total bytes of the prefix/suffix segments
str_addr_buf: resb MAX_FIELDS * 4     ; resolved wasm addrs of the state strings
state_data_out: resb 512              ; state_data with resolved string ptrs
