;; asx/wasm/components.wat - composable components on the primitives
;; (the <View>/<Text>/<Button> of asx). Apps compose these instead of
;; raw $view/$text. NOTE: widgets are positioned ABSOLUTE in the #ui
;; container - children use parent.x+off / parent.y+off coords.

;; =====================================================================
;; Component layer (React-Native-like): composable components built on
;; the primitives. Apps compose these instead of raw $view/$text.
;;
;; card(x, y, w, h, parent) -> dark card view (default #151823)
(func $card (param $x i32) (param $y i32) (param $w i32) (param $h i32)
            (param $parent i32) (result i32)
  local.get $x
  local.get $y
  local.get $w
  local.get $h
  i32.const 21
  i32.const 24
  i32.const 35
  i32.const 255
  local.get $parent
  call $view)

;; label(x, y, w, h, text_ptr, parent, font_size, r, g, b) -> text widget
(func $label (param $x i32) (param $y i32) (param $w i32) (param $h i32)
             (param $text_ptr i32) (param $parent i32) (param $font_size i32)
             (param $r i32) (param $g i32) (param $b i32) (result i32)
  local.get $x
  local.get $y
  local.get $w
  local.get $h
  local.get $r
  local.get $g
  local.get $b
  local.get $text_ptr
  local.get $parent
  local.get $font_size
  call $text)

;; button(x, y, w, h, text_ptr, parent) -> orange view + dark label,
;; returns the button widget index (for hit-testing)
(func $button (param $x i32) (param $y i32) (param $w i32) (param $h i32)
              (param $text_ptr i32) (param $parent i32) (result i32)
  (local $b i32)
  local.get $x
  local.get $y
  local.get $w
  local.get $h
  i32.const 249
  i32.const 115
  i32.const 22
  i32.const 255
  local.get $parent
  call $view
  local.set $b
  local.get $x
  local.get $y
  local.get $w
  local.get $h
  i32.const 15
  i32.const 17
  i32.const 23
  local.get $text_ptr
  local.get $b
  i32.const 13
  call $text
  drop
  local.get $b)

;; canvas(x, y, w, h, r, g, b, parent) -> widget index (type 2)
;; the glue creates a <canvas>; if the module exports frame/pixels the
;; glue runs the animation loop into it
(func $canvas (param $x i32) (param $y i32) (param $w i32) (param $h i32)
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
  i32.const 2
  i32.store8              ;; type = 2 (canvas)
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
