;; asmx/wasm/widgets.wat - declarative widget system (RN-like).
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

;; view(x, y, w, h, r, g, b, parent) -> widget index
(func $view (param $x i32) (param $y i32) (param $w i32) (param $h i32)
            (param $r i32) (param $g i32) (param $b i32) (param $parent i32)
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
  i32.const 255
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
