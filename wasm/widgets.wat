;; asx/wasm/widgets.wat - declarative widget system (RN-like).
;; Components call $view/$text and compose parents/children via the
;; returned index; module exports widgets()/widget_count() and the JS
;; glue renders HTML/CSS. struct 32B: type u8 (0=view 1=text 2=canvas),
;; x/y/w/h i16, r/g/b/a, text_ptr i32, parent i32, font_size u8.

;; =====================================================================
;; widget system - declarative UI (React-Native-like, no HTML tags).
;; Components call $view / $text (props = params) and compose parents
;; with children via the returned index (parent prop). The module
;; exports widgets()/widget_count() and the JS glue renders HTML/CSS.
;;
;; widget struct (32 bytes):
;;   0  type     u8   0=view (div), 1=text (span), 2=canvas
;;   1  pad
;;   2  x        i16
;;   4  y        i16
;;   6  w        i16
;;   8  h        i16
;;   10 pad pad
;;   12 r,g,b,a  u8 x4
;;   16 text_ptr i32  (type 1)
;;   20 parent   i32  (-1 = root)
;;   24 font_size u8  (type 1; 0 = default 13px)
;;   25..31 pad
(global $widget_base i32 (i32.const 148512))
(global $widget_count (mut i32) (i32.const 0))
(global $widget_cap i32 (i32.const 64))
(global $ui_dirty (mut i32) (i32.const 1))

;; ssr_checksum() -> FNV-1a 32 over the canonical first-render IR:
;; every 32B record EXCEPT bytes [16..20) (text_ptr: relative in the
;; build-time blob, absolute address here), then every string in record
;; order (up to, not including, the null). The server embeds the same
;; hash in data-asx-checksum (ui/ssr.asm) - the glue compares both to
;; detect SSR <-> module divergence. Must match ui/ssr.asm ssr_hash.
(func (export "ssr_checksum") (result i32)
  (local $h i32) (local $i i32) (local $j i32) (local $b i32)
  (local $tp i32)
  i32.const 0x811c9dc5
  local.set $h
  ;; records
  i32.const 0
  local.set $i
  block $rec_end
  loop $rec
    local.get $i
    global.get $widget_count
    i32.ge_u
    br_if $rec_end
    i32.const 0
    local.set $j
    block $rb_end
    loop $rb
      local.get $j
      i32.const 32
      i32.ge_u
      br_if $rb_end
      ;; skip the text_ptr field (record bytes 16..19)
      local.get $j
      i32.const 16
      i32.ge_u
      if
        local.get $j
        i32.const 20
        i32.lt_u
        if
          local.get $j
          i32.const 1
          i32.add
          local.set $j
          br $rb
        end
      end
      global.get $widget_base
      local.get $i
      i32.const 32
      i32.mul
      i32.add
      local.get $j
      i32.add
      i32.load8_u
      local.set $b
      local.get $h
      local.get $b
      i32.xor
      i32.const 0x01000193
      i32.mul
      local.set $h
      local.get $j
      i32.const 1
      i32.add
      local.set $j
      br $rb
    end
    end
    local.get $i
    i32.const 1
    i32.add
    local.set $i
    br $rec
  end
  end
  ;; strings in record order (up to the null). Interpolated strings
  ;; (dyn flag in record byte 25) are SKIPPED: the value is runtime
  ;; data (ssr.state may override it), not part of the canonical IR -
  ;; the server-side ssr_hash skips them too (dyn_find).
  i32.const 0
  local.set $i
  block $str_end
  loop $str
    local.get $i
    global.get $widget_count
    i32.ge_u
    br_if $str_end
    ;; dyn flag? skip the string
    global.get $widget_base
    local.get $i
    i32.const 32
    i32.mul
    i32.add
    i32.const 25
    i32.add
    i32.load8_u
    if
      local.get $i
      i32.const 1
      i32.add
      local.set $i
      br $str
    end
    global.get $widget_base
    local.get $i
    i32.const 32
    i32.mul
    i32.add
    i32.const 16
    i32.add
    i32.load
    local.set $tp
    block $no_tp
    local.get $tp
    i32.eqz
    br_if $no_tp
    block $s_end
    loop $s
      local.get $tp
      i32.load8_u
      local.set $b
      local.get $b
      i32.eqz
      br_if $s_end
      local.get $h
      local.get $b
      i32.xor
      i32.const 0x01000193
      i32.mul
      local.set $h
      local.get $tp
      i32.const 1
      i32.add
      local.set $tp
      br $s
    end
    end
    end
    local.get $i
    i32.const 1
    i32.add
    local.set $i
    br $str
  end
  end
  local.get $h
)

;; ui_reset() - start a fresh widget list (call at the top of render())
(func $ui_reset
  i32.const 0
  global.set $widget_count
)

;; itoa(val, buf) -> writes decimal digits + null terminator, returns len
(func $itoa (param $val i32) (param $buf i32) (result i32)
  (local $i i32) (local $tmp i32) (local $j i32) (local $t i32)
  ;; digits in reverse order
  i32.const 0
  local.set $i
  local.get $val
  local.set $tmp
  block $end
  loop $l
    ;; store8: stack must be [addr, value]
    local.get $buf
    local.get $i
    i32.add
    local.get $tmp
    i32.const 10
    i32.rem_u
    i32.const 48
    i32.add
    i32.store8
    local.get $tmp
    i32.const 10
    i32.div_u
    local.set $tmp
    local.get $i
    i32.const 1
    i32.add
    local.set $i
    local.get $tmp
    i32.eqz
    br_if $end
    br $l
  end
  end
  ;; reverse in place
  i32.const 0
  local.set $j
  block $inv_end
  loop $inv
    local.get $j
    local.get $i
    i32.const 1
    i32.sub
    local.get $j
    i32.sub
    i32.ge_u
    br_if $inv_end
    local.get $buf
    local.get $j
    i32.add
    i32.load8_u
    local.set $t
    local.get $buf
    local.get $j
    i32.add
    local.get $buf
    local.get $i
    i32.const 1
    i32.sub
    local.get $j
    i32.sub
    i32.add
    i32.load8_u
    i32.store8
    local.get $buf
    local.get $i
    i32.const 1
    i32.sub
    local.get $j
    i32.sub
    i32.add
    local.get $t
    i32.store8
    local.get $j
    i32.const 1
    i32.add
    local.set $j
    br $inv
  end
  end
  ;; null terminator
  local.get $buf
  local.get $i
  i32.add
  i32.const 0
  i32.store8
  local.get $i
)

;; view(x, y, w, h, r, g, b, a, parent) -> widget index
;; (a = alpha 0..255: 0 = transparent, the glue skips the background)
(func $view (param $x i32) (param $y i32) (param $w i32) (param $h i32)
            (param $r i32) (param $g i32) (param $b i32) (param $a i32)
            (param $parent i32)
            (result i32)
  (local $off i32)
  global.get $widget_base
  global.get $widget_count
  i32.const 32
  i32.mul
  i32.add
  local.set $off
  local.get $off
  i32.const 0
  i32.store8              ;; type = 0 (view)
  local.get $off
  i32.const 2
  i32.add
  local.get $x
  i32.store16
  local.get $off
  i32.const 4
  i32.add
  local.get $y
  i32.store16
  local.get $off
  i32.const 6
  i32.add
  local.get $w
  i32.store16
  local.get $off
  i32.const 8
  i32.add
  local.get $h
  i32.store16
  local.get $off
  i32.const 12
  i32.add
  local.get $r
  i32.store8
  local.get $off
  i32.const 13
  i32.add
  local.get $g
  i32.store8
  local.get $off
  i32.const 14
  i32.add
  local.get $b
  i32.store8
  local.get $off
  i32.const 15
  i32.add
  local.get $a
  i32.store8
  local.get $off
  i32.const 16
  i32.add
  i32.const 0
  i32.store                ;; text_ptr = 0
  local.get $off
  i32.const 20
  i32.add
  local.get $parent
  i32.store
  global.get $widget_count
  i32.const 1
  i32.add
  global.set $widget_count
  global.get $widget_count
  i32.const 1
  i32.sub
)

;; text(x, y, w, h, r, g, b, text_ptr, parent, font_size) -> widget index
(func $text (param $x i32) (param $y i32) (param $w i32) (param $h i32)
            (param $r i32) (param $g i32) (param $b i32)
            (param $text_ptr i32) (param $parent i32) (param $font_size i32)
            (result i32)
  (local $off i32)
  global.get $widget_base
  global.get $widget_count
  i32.const 32
  i32.mul
  i32.add
  local.set $off
  local.get $off
  i32.const 1
  i32.store8              ;; type = 1 (text)
  local.get $off
  i32.const 2
  i32.add
  local.get $x
  i32.store16
  local.get $off
  i32.const 4
  i32.add
  local.get $y
  i32.store16
  local.get $off
  i32.const 6
  i32.add
  local.get $w
  i32.store16
  local.get $off
  i32.const 8
  i32.add
  local.get $h
  i32.store16
  local.get $off
  i32.const 12
  i32.add
  local.get $r
  i32.store8
  local.get $off
  i32.const 13
  i32.add
  local.get $g
  i32.store8
  local.get $off
  i32.const 14
  i32.add
  local.get $b
  i32.store8
  local.get $off
  i32.const 15
  i32.add
  i32.const 255
  i32.store8
  local.get $off
  i32.const 16
  i32.add
  local.get $text_ptr
  i32.store
  local.get $off
  i32.const 20
  i32.add
  local.get $parent
  i32.store
  local.get $off
  i32.const 24
  i32.add
  local.get $font_size
  i32.store8
  global.get $widget_count
  i32.const 1
  i32.add
  global.set $widget_count
  global.get $widget_count
  i32.const 1
  i32.sub
)

;; strcpy(dst, src) - copies bytes up to and including the null terminator
(func $strcpy (param $dst i32) (param $src i32)
  (local $i i32) (local $b i32)
  block $end
  loop $l
    local.get $src
    local.get $i
    i32.add
    i32.load8_u
    local.set $b
    ;; store8 wants [addr, value] - addr first, value on top
    local.get $dst
    local.get $i
    i32.add
    local.get $b
    i32.store8
    local.get $b
    i32.eqz
    br_if $end
    local.get $i
    i32.const 1
    i32.add
    local.set $i
    br $l
  end
  end
)

;; fmt(dst, prefix, plen, val, suffix) - mounts dst = prefix + itoa(val) + suffix
;; used by the compiler for interpolated int/bool texts
(func $fmt (param $dst i32) (param $prefix i32) (param $plen i32) (param $val i32) (param $suffix i32)
  (local $pos i32) (local $n i32)
  local.get $dst
  local.get $prefix
  call $strcpy
  local.get $dst
  local.get $plen
  i32.add
  local.set $pos
  local.get $val
  local.get $pos
  call $itoa
  local.set $n
  local.get $pos
  local.get $n
  i32.add
  local.set $pos
  local.get $pos
  local.get $suffix
  call $strcpy
)

;; fmt_str(dst, prefix, plen, str, suffix) - mounts dst = prefix + str + suffix
;; used by the compiler for interpolated string texts
(func $fmt_str (param $dst i32) (param $prefix i32) (param $plen i32) (param $str i32) (param $suffix i32)
  (local $pos i32)
  local.get $dst
  local.get $prefix
  call $strcpy
  local.get $dst
  local.get $plen
  i32.add
  local.set $pos
  block $end
  loop $l
    local.get $str
    i32.load8_u
    i32.eqz
    br_if $end
    ;; store8 wants [addr, value] - addr first, value on top
    local.get $pos
    local.get $str
    i32.load8_u
    i32.store8
    local.get $str
    i32.const 1
    i32.add
    local.set $str
    local.get $pos
    i32.const 1
    i32.add
    local.set $pos
    br $l
  end
  end
  local.get $pos
  local.get $suffix
  call $strcpy
)
