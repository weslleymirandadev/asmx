;; asx/wasm/draw.wat - pixel primitives (framework domain, like http/json).
;; Fragment: concatenated by the app Makefile inside one (module ...);
;; every src/ui/*.wat gets these, like %include in NASM.
;; available: $put_pixel, $blend_pixel, $clear, $fill_rect, $draw_line,
;;            $draw_circle_filled

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

