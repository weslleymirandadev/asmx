;; asx/wasm/text.wat - bitmap 5x7 text (framework domain).
;; $draw_text(x, y, str, r, g, b) + font at $font_base (147456 = right
;; after a 192x192 RGBA buffer; chars 0x20..0x7F, 5 bytes per char, one
;; column per byte, bit 0 (LSB) = top row).

(global $font_base i32 (i32.const 147456))

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
