;; asmx/wasm/ui.wat - WASM UI domain: pixel-level abstractions for the
;; frontend. This is FRAMEWORK territory (like asmx/http, asmx/json) -
;; apps in src/ui/ include this file and compose the scene; the scaffold
;; does not ship any UI library.
;;
;; Fragment: the app Makefile wraps this file + the component (.wat) inside
;; a single (module ...) - every src/ui/*.wat gets these functions, like
;; %include in NASM. Components must define $w and $h globals (canvas
;; size) and declare a memory big enough for w*h*4 bytes.
;;
;; available: $put_pixel, $clear, $fill_rect, $draw_line, $draw_ring,
;;            $draw_circle_filled, $blend_pixel, $draw_text
;;
;; $draw_text uses a bitmap 5x7 font stored at $font_base (default
;; offset 147456 = right after a 192x192 RGBA buffer; chars 0x20..0x7F,
;; 5 bytes per char, one column per byte, bit 0 (LSB) = top row).

(global $font_base i32 (i32.const 147456))

;; put_pixel(x, y, r, g, b) - write one RGBA pixel (alpha 255)
(func $put_pixel (param $x i32) (param $y i32)
                 (param $r i32) (param $g i32) (param $b i32)
  (local $off i32)
  ;; off = (y * w + x) * 4
  local.get $y
  global.get $w
  i32.mul
  local.get $x
  i32.add
  i32.const 4
  i32.mul
  local.set $off
  local.get $off
  local.get $r
  i32.store8
  local.get $off
  i32.const 1
  i32.add
  local.get $g
  i32.store8
  local.get $off
  i32.const 2
  i32.add
  local.get $b
  i32.store8
  local.get $off
  i32.const 3
  i32.add
  i32.const 255
  i32.store8
)

;; blend_pixel(x, y, r, g, b, a) - alpha-blend one pixel over the buffer
;; (a = 0..255; 255 = opaque). out = (src*a + dst*(255-a)) / 255
(func $blend_pixel (param $x i32) (param $y i32)
                   (param $r i32) (param $g i32) (param $b i32) (param $a i32)
  (local $off i32) (local $dr i32) (local $dg i32) (local $db i32)
  (local $ia i32)
  ;; off = (y * w + x) * 4
  local.get $y
  global.get $w
  i32.mul
  local.get $x
  i32.add
  i32.const 4
  i32.mul
  local.set $off
  ;; ia = 255 - a
  i32.const 255
  local.get $a
  i32.sub
  local.set $ia
  ;; dr = (r*a + dst_r*ia) / 255
  local.get $r
  local.get $a
  i32.mul
  local.get $off
  i32.load8_u
  local.get $ia
  i32.mul
  i32.add
  i32.const 255
  i32.div_u
  local.set $dr
  local.get $g
  local.get $a
  i32.mul
  local.get $off
  i32.const 1
  i32.add
  i32.load8_u
  local.get $ia
  i32.mul
  i32.add
  i32.const 255
  i32.div_u
  local.set $dg
  local.get $b
  local.get $a
  i32.mul
  local.get $off
  i32.const 2
  i32.add
  i32.load8_u
  local.get $ia
  i32.mul
  i32.add
  i32.const 255
  i32.div_u
  local.set $db
  local.get $off
  local.get $dr
  i32.store8
  local.get $off
  i32.const 1
  i32.add
  local.get $dg
  i32.store8
  local.get $off
  i32.const 2
  i32.add
  local.get $db
  i32.store8
  local.get $off
  i32.const 3
  i32.add
  i32.const 255
  i32.store8
)

;; clear(r, g, b) - fill the whole canvas
(func $clear (param $r i32) (param $g i32) (param $b i32)
  (local $i i32) (local $off i32)
  i32.const 0
  local.set $i
  block $end
  loop $l
    local.get $i
    global.get $w
    global.get $h
    i32.mul
    i32.ge_u
    br_if $end
    local.get $i
    i32.const 4
    i32.mul
    local.set $off
    local.get $off
    local.get $r
    i32.store8
    local.get $off
    i32.const 1
    i32.add
    local.get $g
    i32.store8
    local.get $off
    i32.const 2
    i32.add
    local.get $b
    i32.store8
    local.get $off
    i32.const 3
    i32.add
    i32.const 255
    i32.store8
    local.get $i
    i32.const 1
    i32.add
    local.set $i
    br $l
  end
  end
)

;; fill_rect(x0, y0, x1, y1, r, g, b) - filled rectangle (x1/y1 exclusive)
(func $fill_rect (param $x0 i32) (param $y0 i32) (param $x1 i32) (param $y1 i32)
                 (param $r i32) (param $g i32) (param $b i32)
  (local $x i32) (local $y i32)
  local.get $y0
  local.set $y
  block $y_end
  loop $y_loop
    local.get $y
    local.get $y1
    i32.ge_u
    br_if $y_end
    local.get $x0
    local.set $x
    block $x_end
    loop $x_loop
      local.get $x
      local.get $x1
      i32.ge_u
      br_if $x_end
      local.get $x
      local.get $y
      local.get $r
      local.get $g
      local.get $b
      call $put_pixel
      local.get $x
      i32.const 1
      i32.add
      local.set $x
      br $x_loop
    end
    end
    local.get $y
    i32.const 1
    i32.add
    local.set $y
    br $y_loop
  end
  end
)

;; draw_line(x0, y0, x1, y1, r, g, b) - Bresenham line
(func $draw_line (param $x0 i32) (param $y0 i32) (param $x1 i32) (param $y1 i32)
                 (param $r i32) (param $g i32) (param $b i32)
  (local $dx i32) (local $dy i32) (local $sx i32) (local $sy i32)
  (local $err i32) (local $e2 i32)
  ;; dx = |x1-x0|, sx = sign
  local.get $x1
  local.get $x0
  i32.sub
  local.tee $dx
  i32.const 0
  i32.lt_s
  if
    i32.const -1
    local.set $sx
    local.get $dx
    i32.const 0
    i32.sub
    local.set $dx
  else
    i32.const 1
    local.set $sx
  end
  local.get $y1
  local.get $y0
  i32.sub
  local.tee $dy
  i32.const 0
  i32.lt_s
  if
    i32.const -1
    local.set $sy
    local.get $dy
    i32.const 0
    i32.sub
    local.set $dy
  else
    i32.const 1
    local.set $sy
  end
  ;; err = dx - dy
  local.get $dx
  local.get $dy
  i32.sub
  local.set $err
  block $end
  loop $l
    ;; put_pixel(x0, y0, ...)
    local.get $x0
    local.get $y0
    local.get $r
    local.get $g
    local.get $b
    call $put_pixel
    ;; stop at (x1, y1)
    local.get $x0
    local.get $x1
    i32.eq
    local.get $y0
    local.get $y1
    i32.eq
    i32.and
    br_if $end
    ;; e2 = 2*err
    local.get $err
    i32.const 2
    i32.mul
    local.set $e2
    ;; if e2 > -dy: err -= dy; x0 += sx
    local.get $e2
    local.get $dy
    i32.const 0
    i32.sub
    i32.gt_s
    if
      local.get $err
      local.get $dy
      i32.sub
      local.set $err
      local.get $x0
      local.get $sx
      i32.add
      local.set $x0
    end
    ;; if e2 < dx: err += dx; y0 += sy
    local.get $e2
    local.get $dx
    i32.lt_s
    if
      local.get $err
      local.get $dx
      i32.add
      local.set $err
      local.get $y0
      local.get $sy
      i32.add
      local.set $y0
    end
    br $l
  end
  end
)

;; draw_circle_filled(cx, cy, radius, r, g, b) - filled circle
(func $draw_circle_filled (param $cx i32) (param $cy i32)
                          (param $radius i32)
                          (param $r i32) (param $g i32) (param $b i32)
  (local $x i32) (local $y i32) (local $dx i32) (local $dy i32) (local $d2 i32)
  (local $r2 i32)
  local.get $radius
  local.get $radius
  i32.mul
  local.set $r2
  i32.const 0
  local.set $y
  block $y_end
  loop $y_loop
    local.get $y
    global.get $h
    i32.ge_u
    br_if $y_end
    i32.const 0
    local.set $x
    block $x_end
    loop $x_loop
      local.get $x
      global.get $w
      i32.ge_u
      br_if $x_end
      local.get $x
      local.get $cx
      i32.sub
      local.set $dx
      local.get $y
      local.get $cy
      i32.sub
      local.set $dy
      local.get $dx
      local.get $dx
      i32.mul
      local.get $dy
      local.get $dy
      i32.mul
      i32.add
      local.get $r2
      i32.le_u
      if
        local.get $x
        local.get $y
        local.get $r
        local.get $g
        local.get $b
        call $put_pixel
      end
      local.get $x
      i32.const 1
      i32.add
      local.set $x
      br $x_loop
    end
    end
    local.get $y
    i32.const 1
    i32.add
    local.set $y
    br $y_loop
  end
  end
)

;; draw_ring(cx, cy, radius, thickness, r, g, b) - ring band around (cx,cy)
(func $draw_ring (param $cx i32) (param $cy i32)
                 (param $radius i32) (param $thickness i32)
                 (param $r i32) (param $g i32) (param $b i32)
  (local $x i32) (local $y i32) (local $dx i32) (local $dy i32) (local $d2 i32)
  (local $ri2 i32) (local $ro2 i32)
  ;; ri2 = (radius - thickness)^2, ro2 = (radius + thickness)^2
  local.get $radius
  local.get $thickness
  i32.sub
  local.tee $ri2
  local.get $ri2
  i32.mul
  local.set $ri2
  local.get $radius
  local.get $thickness
  i32.add
  local.tee $ro2
  local.get $ro2
  i32.mul
  local.set $ro2
  i32.const 0
  local.set $y
  block $y_end
  loop $y_loop
    local.get $y
    global.get $h
    i32.ge_u
    br_if $y_end
    i32.const 0
    local.set $x
    block $x_end
    loop $x_loop
      local.get $x
      global.get $w
      i32.ge_u
      br_if $x_end
      ;; d2 = (x-cx)^2 + (y-cy)^2
      local.get $x
      local.get $cx
      i32.sub
      local.set $dx
      local.get $y
      local.get $cy
      i32.sub
      local.set $dy
      local.get $dx
      local.get $dx
      i32.mul
      local.get $dy
      local.get $dy
      i32.mul
      i32.add
      local.set $d2
      local.get $d2
      local.get $ri2
      i32.ge_u
      local.get $d2
      local.get $ro2
      i32.le_u
      i32.and
      if
        local.get $x
        local.get $y
        local.get $r
        local.get $g
        local.get $b
        call $put_pixel
      end
      local.get $x
      i32.const 1
      i32.add
      local.set $x
      br $x_loop
    end
    end
    local.get $y
    i32.const 1
    i32.add
    local.set $y
    br $y_loop
  end
  end
)

;; draw_text(x, y, str_ptr, r, g, b) - bitmap 5x7 text, 1px spacing
(func $draw_text (param $x i32) (param $y i32) (param $str i32)
                 (param $r i32) (param $g i32) (param $b i32)
  (local $cx i32) (local $i i32) (local $j i32) (local $ch i32)
  (local $glyph i32) (local $byte i32)
  local.get $x
  local.set $cx
  block $end
  loop $l
    ;; ch = str[0]; 0 ends the string
    local.get $str
    i32.load8_u
    local.tee $ch
    i32.eqz
    br_if $end
    ;; glyph ptr = font_base + (ch - 32) * 5
    local.get $ch
    i32.const 32
    i32.sub
    i32.const 5
    i32.mul
    global.get $font_base
    i32.add
    local.set $glyph
    ;; for each of the 5 columns
    i32.const 0
    local.set $i
    block $i_end
    loop $i_loop
      local.get $i
      i32.const 5
      i32.ge_u
      br_if $i_end
      local.get $glyph
      local.get $i
      i32.add
      i32.load8_u
      local.set $byte
      ;; for each of the 7 rows (bit 0 = top)
      i32.const 0
      local.set $j
      block $j_end
      loop $j_loop
        local.get $j
        i32.const 7
        i32.ge_u
        br_if $j_end
        local.get $byte
        local.get $j
        i32.shr_u
        i32.const 1
        i32.and
        if
          local.get $cx
          local.get $i
          i32.add
          local.get $y
          local.get $j
          i32.add
          local.get $r
          local.get $g
          local.get $b
          call $put_pixel
        end
        local.get $j
        i32.const 1
        i32.add
        local.set $j
        br $j_loop
      end
      end
      local.get $i
      i32.const 1
      i32.add
      local.set $i
      br $i_loop
    end
    end
    ;; next char: advance 6px (5 + 1 spacing)
    local.get $cx
    i32.const 6
    i32.add
    local.set $cx
    local.get $str
    i32.const 1
    i32.add
    local.set $str
    br $l
  end
  end
)

;; bitmap 5x7 font (chars 0x20..0x7F, 480 bytes) at $font_base
(data (i32.const 147456) "\00\00\00\00\00\00\00\5f\00\00\00\07\00\07\00\14")
(data (i32.const 147472) "\7f\14\7f\14\24\2a\7f\2a\12\23\13\08\64\62\36\49")
(data (i32.const 147488) "\55\22\50\00\05\03\00\00\00\1c\22\41\00\00\41\22")
(data (i32.const 147504) "\1c\00\14\08\3e\08\14\08\08\3e\08\08\00\50\30\00")
(data (i32.const 147520) "\00\08\08\08\08\08\00\60\60\00\00\20\10\08\04\02")
(data (i32.const 147536) "\3e\51\49\45\3e\00\42\7f\40\00\42\61\51\49\46\21")
(data (i32.const 147552) "\41\45\4b\31\18\14\12\7f\10\27\45\45\45\39\3c\4a")
(data (i32.const 147568) "\49\49\30\01\71\09\05\03\36\49\49\49\36\06\49\49")
(data (i32.const 147584) "\29\1e\00\36\36\00\00\00\56\36\00\00\08\14\22\41")
(data (i32.const 147600) "\00\14\14\14\14\14\00\41\22\14\08\02\01\51\09\06")
(data (i32.const 147616) "\32\49\79\41\3e\7e\11\11\11\7e\7f\49\49\49\36\3e")
(data (i32.const 147632) "\41\41\41\22\7f\41\41\22\1c\7f\49\49\49\41\7f\09")
(data (i32.const 147648) "\09\09\01\3e\41\49\49\7a\7f\08\08\08\7f\00\41\7f")
(data (i32.const 147664) "\41\00\20\40\41\3f\01\7f\08\14\22\41\7f\40\40\40")
(data (i32.const 147680) "\40\7f\02\0c\02\7f\7f\04\08\10\7f\3e\41\41\41\3e")
(data (i32.const 147696) "\7f\09\09\09\06\3e\41\51\21\5e\7f\09\19\29\46\46")
(data (i32.const 147712) "\49\49\49\31\01\01\7f\01\01\3f\40\40\40\3f\1f\20")
(data (i32.const 147728) "\40\20\1f\3f\40\38\40\3f\63\14\08\14\63\07\08\70")
(data (i32.const 147744) "\08\07\61\51\49\45\43\00\7f\41\41\00\02\04\08\10")
(data (i32.const 147760) "\20\00\41\41\7f\00\04\02\01\02\04\40\40\40\40\40")
(data (i32.const 147776) "\00\01\02\04\00\20\54\54\54\78\7f\48\44\44\38\38")
(data (i32.const 147792) "\44\44\44\20\38\44\44\48\7f\38\54\54\54\18\08\7e")
(data (i32.const 147808) "\09\01\02\0c\52\52\52\3e\7f\08\04\04\78\00\44\7d")
(data (i32.const 147824) "\40\00\20\40\44\3d\00\7f\10\28\44\00\00\41\7f\40")
(data (i32.const 147840) "\00\7c\04\18\04\78\7c\08\04\04\78\38\44\44\44\38")
(data (i32.const 147856) "\7c\14\14\14\08\08\14\14\18\7c\7c\08\04\04\08\48")
(data (i32.const 147872) "\54\54\54\20\04\3f\44\40\20\3c\40\40\20\7c\1c\20")
(data (i32.const 147888) "\40\20\1c\3c\40\30\40\3c\44\28\10\28\44\0c\50\50")
(data (i32.const 147904) "\50\3c\44\64\54\4c\44\00\08\36\41\00\00\00\7f\00")
(data (i32.const 147920) "\00\00\41\36\08\00\10\08\08\10\08\78\46\41\46\78")

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
