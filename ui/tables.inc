; =============================================================================
; tables.inc - tag table + Tailwind tables (colors/fonts/scale)
; =============================================================================

; --- tag table (dq ptr, dq id) ---
s_main        db "main", 0
s_div         db "div", 0
s_section     db "section", 0
s_nav         db "nav", 0
s_header      db "header", 0
s_footer      db "footer", 0
s_h1          db "h1", 0
s_h2          db "h2", 0
s_h3          db "h3", 0
s_p_tag       db "p", 0
s_span        db "span", 0
s_a           db "a", 0
s_button      db "button", 0

tags:         dq s_main, 0
              dq s_div, 0
              dq s_section, 0
              dq s_nav, 0
              dq s_header, 0
              dq s_footer, 0
              dq s_h1, 1
              dq s_h2, 1
              dq s_h3, 1
              dq s_p_tag, 1
              dq s_span, 1
              dq s_a, 1
              dq s_button, 2
tags_end:

; ----------------------------------------------------------------------
; TAILWIND TABLES (default v3 palette - ALL keys)
; tw_colors: bg-*/text-* (242 shades + black/white) | tw_sizes: text-*
; tw_scale: p-*/m-*/mt-*/mb-*/w-* (spacing scale + widths)
; ----------------------------------------------------------------------
s_slate_50 db "slate-50", 0
s_slate_100 db "slate-100", 0
s_slate_200 db "slate-200", 0
s_slate_300 db "slate-300", 0
s_slate_400 db "slate-400", 0
s_slate_500 db "slate-500", 0
s_slate_600 db "slate-600", 0
s_slate_700 db "slate-700", 0
s_slate_800 db "slate-800", 0
s_slate_900 db "slate-900", 0
s_slate_950 db "slate-950", 0
s_gray_50 db "gray-50", 0
s_gray_100 db "gray-100", 0
s_gray_200 db "gray-200", 0
s_gray_300 db "gray-300", 0
s_gray_400 db "gray-400", 0
s_gray_500 db "gray-500", 0
s_gray_600 db "gray-600", 0
s_gray_700 db "gray-700", 0
s_gray_800 db "gray-800", 0
s_gray_900 db "gray-900", 0
s_gray_950 db "gray-950", 0
s_zinc_50 db "zinc-50", 0
s_zinc_100 db "zinc-100", 0
s_zinc_200 db "zinc-200", 0
s_zinc_300 db "zinc-300", 0
s_zinc_400 db "zinc-400", 0
s_zinc_500 db "zinc-500", 0
s_zinc_600 db "zinc-600", 0
s_zinc_700 db "zinc-700", 0
s_zinc_800 db "zinc-800", 0
s_zinc_900 db "zinc-900", 0
s_zinc_950 db "zinc-950", 0
s_neutral_50 db "neutral-50", 0
s_neutral_100 db "neutral-100", 0
s_neutral_200 db "neutral-200", 0
s_neutral_300 db "neutral-300", 0
s_neutral_400 db "neutral-400", 0
s_neutral_500 db "neutral-500", 0
s_neutral_600 db "neutral-600", 0
s_neutral_700 db "neutral-700", 0
s_neutral_800 db "neutral-800", 0
s_neutral_900 db "neutral-900", 0
s_neutral_950 db "neutral-950", 0
s_stone_50 db "stone-50", 0
s_stone_100 db "stone-100", 0
s_stone_200 db "stone-200", 0
s_stone_300 db "stone-300", 0
s_stone_400 db "stone-400", 0
s_stone_500 db "stone-500", 0
s_stone_600 db "stone-600", 0
s_stone_700 db "stone-700", 0
s_stone_800 db "stone-800", 0
s_stone_900 db "stone-900", 0
s_stone_950 db "stone-950", 0
s_red_50 db "red-50", 0
s_red_100 db "red-100", 0
s_red_200 db "red-200", 0
s_red_300 db "red-300", 0
s_red_400 db "red-400", 0
s_red_500 db "red-500", 0
s_red_600 db "red-600", 0
s_red_700 db "red-700", 0
s_red_800 db "red-800", 0
s_red_900 db "red-900", 0
s_red_950 db "red-950", 0
s_orange_50 db "orange-50", 0
s_orange_100 db "orange-100", 0
s_orange_200 db "orange-200", 0
s_orange_300 db "orange-300", 0
s_orange_400 db "orange-400", 0
s_orange_500 db "orange-500", 0
s_orange_600 db "orange-600", 0
s_orange_700 db "orange-700", 0
s_orange_800 db "orange-800", 0
s_orange_900 db "orange-900", 0
s_orange_950 db "orange-950", 0
s_amber_50 db "amber-50", 0
s_amber_100 db "amber-100", 0
s_amber_200 db "amber-200", 0
s_amber_300 db "amber-300", 0
s_amber_400 db "amber-400", 0
s_amber_500 db "amber-500", 0
s_amber_600 db "amber-600", 0
s_amber_700 db "amber-700", 0
s_amber_800 db "amber-800", 0
s_amber_900 db "amber-900", 0
s_amber_950 db "amber-950", 0
s_yellow_50 db "yellow-50", 0
s_yellow_100 db "yellow-100", 0
s_yellow_200 db "yellow-200", 0
s_yellow_300 db "yellow-300", 0
s_yellow_400 db "yellow-400", 0
s_yellow_500 db "yellow-500", 0
s_yellow_600 db "yellow-600", 0
s_yellow_700 db "yellow-700", 0
s_yellow_800 db "yellow-800", 0
s_yellow_900 db "yellow-900", 0
s_yellow_950 db "yellow-950", 0
s_lime_50 db "lime-50", 0
s_lime_100 db "lime-100", 0
s_lime_200 db "lime-200", 0
s_lime_300 db "lime-300", 0
s_lime_400 db "lime-400", 0
s_lime_500 db "lime-500", 0
s_lime_600 db "lime-600", 0
s_lime_700 db "lime-700", 0
s_lime_800 db "lime-800", 0
s_lime_900 db "lime-900", 0
s_lime_950 db "lime-950", 0
s_green_50 db "green-50", 0
s_green_100 db "green-100", 0
s_green_200 db "green-200", 0
s_green_300 db "green-300", 0
s_green_400 db "green-400", 0
s_green_500 db "green-500", 0
s_green_600 db "green-600", 0
s_green_700 db "green-700", 0
s_green_800 db "green-800", 0
s_green_900 db "green-900", 0
s_green_950 db "green-950", 0
s_emerald_50 db "emerald-50", 0
s_emerald_100 db "emerald-100", 0
s_emerald_200 db "emerald-200", 0
s_emerald_300 db "emerald-300", 0
s_emerald_400 db "emerald-400", 0
s_emerald_500 db "emerald-500", 0
s_emerald_600 db "emerald-600", 0
s_emerald_700 db "emerald-700", 0
s_emerald_800 db "emerald-800", 0
s_emerald_900 db "emerald-900", 0
s_emerald_950 db "emerald-950", 0
s_teal_50 db "teal-50", 0
s_teal_100 db "teal-100", 0
s_teal_200 db "teal-200", 0
s_teal_300 db "teal-300", 0
s_teal_400 db "teal-400", 0
s_teal_500 db "teal-500", 0
s_teal_600 db "teal-600", 0
s_teal_700 db "teal-700", 0
s_teal_800 db "teal-800", 0
s_teal_900 db "teal-900", 0
s_teal_950 db "teal-950", 0
s_cyan_50 db "cyan-50", 0
s_cyan_100 db "cyan-100", 0
s_cyan_200 db "cyan-200", 0
s_cyan_300 db "cyan-300", 0
s_cyan_400 db "cyan-400", 0
s_cyan_500 db "cyan-500", 0
s_cyan_600 db "cyan-600", 0
s_cyan_700 db "cyan-700", 0
s_cyan_800 db "cyan-800", 0
s_cyan_900 db "cyan-900", 0
s_cyan_950 db "cyan-950", 0
s_sky_50 db "sky-50", 0
s_sky_100 db "sky-100", 0
s_sky_200 db "sky-200", 0
s_sky_300 db "sky-300", 0
s_sky_400 db "sky-400", 0
s_sky_500 db "sky-500", 0
s_sky_600 db "sky-600", 0
s_sky_700 db "sky-700", 0
s_sky_800 db "sky-800", 0
s_sky_900 db "sky-900", 0
s_sky_950 db "sky-950", 0
s_blue_50 db "blue-50", 0
s_blue_100 db "blue-100", 0
s_blue_200 db "blue-200", 0
s_blue_300 db "blue-300", 0
s_blue_400 db "blue-400", 0
s_blue_500 db "blue-500", 0
s_blue_600 db "blue-600", 0
s_blue_700 db "blue-700", 0
s_blue_800 db "blue-800", 0
s_blue_900 db "blue-900", 0
s_blue_950 db "blue-950", 0
s_indigo_50 db "indigo-50", 0
s_indigo_100 db "indigo-100", 0
s_indigo_200 db "indigo-200", 0
s_indigo_300 db "indigo-300", 0
s_indigo_400 db "indigo-400", 0
s_indigo_500 db "indigo-500", 0
s_indigo_600 db "indigo-600", 0
s_indigo_700 db "indigo-700", 0
s_indigo_800 db "indigo-800", 0
s_indigo_900 db "indigo-900", 0
s_indigo_950 db "indigo-950", 0
s_violet_50 db "violet-50", 0
s_violet_100 db "violet-100", 0
s_violet_200 db "violet-200", 0
s_violet_300 db "violet-300", 0
s_violet_400 db "violet-400", 0
s_violet_500 db "violet-500", 0
s_violet_600 db "violet-600", 0
s_violet_700 db "violet-700", 0
s_violet_800 db "violet-800", 0
s_violet_900 db "violet-900", 0
s_violet_950 db "violet-950", 0
s_purple_50 db "purple-50", 0
s_purple_100 db "purple-100", 0
s_purple_200 db "purple-200", 0
s_purple_300 db "purple-300", 0
s_purple_400 db "purple-400", 0
s_purple_500 db "purple-500", 0
s_purple_600 db "purple-600", 0
s_purple_700 db "purple-700", 0
s_purple_800 db "purple-800", 0
s_purple_900 db "purple-900", 0
s_purple_950 db "purple-950", 0
s_fuchsia_50 db "fuchsia-50", 0
s_fuchsia_100 db "fuchsia-100", 0
s_fuchsia_200 db "fuchsia-200", 0
s_fuchsia_300 db "fuchsia-300", 0
s_fuchsia_400 db "fuchsia-400", 0
s_fuchsia_500 db "fuchsia-500", 0
s_fuchsia_600 db "fuchsia-600", 0
s_fuchsia_700 db "fuchsia-700", 0
s_fuchsia_800 db "fuchsia-800", 0
s_fuchsia_900 db "fuchsia-900", 0
s_fuchsia_950 db "fuchsia-950", 0
s_pink_50 db "pink-50", 0
s_pink_100 db "pink-100", 0
s_pink_200 db "pink-200", 0
s_pink_300 db "pink-300", 0
s_pink_400 db "pink-400", 0
s_pink_500 db "pink-500", 0
s_pink_600 db "pink-600", 0
s_pink_700 db "pink-700", 0
s_pink_800 db "pink-800", 0
s_pink_900 db "pink-900", 0
s_pink_950 db "pink-950", 0
s_rose_50 db "rose-50", 0
s_rose_100 db "rose-100", 0
s_rose_200 db "rose-200", 0
s_rose_300 db "rose-300", 0
s_rose_400 db "rose-400", 0
s_rose_500 db "rose-500", 0
s_rose_600 db "rose-600", 0
s_rose_700 db "rose-700", 0
s_rose_800 db "rose-800", 0
s_rose_900 db "rose-900", 0
s_rose_950 db "rose-950", 0
s_black db "black", 0
s_white db "white", 0

tw_colors:
    dq s_slate_50, 0xf8fafc
    dq s_slate_100, 0xf1f5f9
    dq s_slate_200, 0xe2e8f0
    dq s_slate_300, 0xcbd5e1
    dq s_slate_400, 0x94a3b8
    dq s_slate_500, 0x64748b
    dq s_slate_600, 0x475569
    dq s_slate_700, 0x334155
    dq s_slate_800, 0x1e293b
    dq s_slate_900, 0x0f172a
    dq s_slate_950, 0x020617
    dq s_gray_50, 0xf9fafb
    dq s_gray_100, 0xf3f4f6
    dq s_gray_200, 0xe5e7eb
    dq s_gray_300, 0xd1d5db
    dq s_gray_400, 0x9ca3af
    dq s_gray_500, 0x6b7280
    dq s_gray_600, 0x4b5563
    dq s_gray_700, 0x374151
    dq s_gray_800, 0x1f2937
    dq s_gray_900, 0x111827
    dq s_gray_950, 0x030712
    dq s_zinc_50, 0xfafafa
    dq s_zinc_100, 0xf4f4f5
    dq s_zinc_200, 0xe4e4e7
    dq s_zinc_300, 0xd4d4d8
    dq s_zinc_400, 0xa1a1aa
    dq s_zinc_500, 0x71717a
    dq s_zinc_600, 0x52525b
    dq s_zinc_700, 0x3f3f46
    dq s_zinc_800, 0x27272a
    dq s_zinc_900, 0x18181b
    dq s_zinc_950, 0x09090b
    dq s_neutral_50, 0xfafafa
    dq s_neutral_100, 0xf5f5f5
    dq s_neutral_200, 0xe5e5e5
    dq s_neutral_300, 0xd4d4d4
    dq s_neutral_400, 0xa3a3a3
    dq s_neutral_500, 0x737373
    dq s_neutral_600, 0x525252
    dq s_neutral_700, 0x404040
    dq s_neutral_800, 0x262626
    dq s_neutral_900, 0x171717
    dq s_neutral_950, 0x0a0a0a
    dq s_stone_50, 0xfafaf9
    dq s_stone_100, 0xf5f5f4
    dq s_stone_200, 0xe7e5e4
    dq s_stone_300, 0xd6d3d1
    dq s_stone_400, 0xa8a29e
    dq s_stone_500, 0x78716c
    dq s_stone_600, 0x57534e
    dq s_stone_700, 0x44403c
    dq s_stone_800, 0x292524
    dq s_stone_900, 0x1c1917
    dq s_stone_950, 0x0c0a09
    dq s_red_50, 0xfef2f2
    dq s_red_100, 0xfee2e2
    dq s_red_200, 0xfecaca
    dq s_red_300, 0xfca5a5
    dq s_red_400, 0xf87171
    dq s_red_500, 0xef4444
    dq s_red_600, 0xdc2626
    dq s_red_700, 0xb91c1c
    dq s_red_800, 0x991b1b
    dq s_red_900, 0x7f1d1d
    dq s_red_950, 0x450a0a
    dq s_orange_50, 0xfff7ed
    dq s_orange_100, 0xffedd5
    dq s_orange_200, 0xfed7aa
    dq s_orange_300, 0xfdba74
    dq s_orange_400, 0xfb923c
    dq s_orange_500, 0xf97316
    dq s_orange_600, 0xea580c
    dq s_orange_700, 0xc2410c
    dq s_orange_800, 0x9a3412
    dq s_orange_900, 0x7c2d12
    dq s_orange_950, 0x431407
    dq s_amber_50, 0xfffbeb
    dq s_amber_100, 0xfef3c7
    dq s_amber_200, 0xfde68a
    dq s_amber_300, 0xfcd34d
    dq s_amber_400, 0xfbbf24
    dq s_amber_500, 0xf59e0b
    dq s_amber_600, 0xd97706
    dq s_amber_700, 0xb45309
    dq s_amber_800, 0x92400e
    dq s_amber_900, 0x78350f
    dq s_amber_950, 0x451a03
    dq s_yellow_50, 0xfefce8
    dq s_yellow_100, 0xfef9c3
    dq s_yellow_200, 0xfef08a
    dq s_yellow_300, 0xfde047
    dq s_yellow_400, 0xfacc15
    dq s_yellow_500, 0xeab308
    dq s_yellow_600, 0xca8a04
    dq s_yellow_700, 0xa16207
    dq s_yellow_800, 0x854d0e
    dq s_yellow_900, 0x713f12
    dq s_yellow_950, 0x422006
    dq s_lime_50, 0xf7fee7
    dq s_lime_100, 0xecfccb
    dq s_lime_200, 0xd9f99d
    dq s_lime_300, 0xbef264
    dq s_lime_400, 0xa3e635
    dq s_lime_500, 0x84cc16
    dq s_lime_600, 0x65a30d
    dq s_lime_700, 0x4d7c0f
    dq s_lime_800, 0x3f6212
    dq s_lime_900, 0x365314
    dq s_lime_950, 0x1a2e05
    dq s_green_50, 0xf0fdf4
    dq s_green_100, 0xdcfce7
    dq s_green_200, 0xbbf7d0
    dq s_green_300, 0x86efac
    dq s_green_400, 0x4ade80
    dq s_green_500, 0x22c55e
    dq s_green_600, 0x16a34a
    dq s_green_700, 0x15803d
    dq s_green_800, 0x166534
    dq s_green_900, 0x14532d
    dq s_green_950, 0x052e16
    dq s_emerald_50, 0xecfdf5
    dq s_emerald_100, 0xd1fae5
    dq s_emerald_200, 0xa7f3d0
    dq s_emerald_300, 0x6ee7b7
    dq s_emerald_400, 0x34d399
    dq s_emerald_500, 0x10b981
    dq s_emerald_600, 0x059669
    dq s_emerald_700, 0x047857
    dq s_emerald_800, 0x065f46
    dq s_emerald_900, 0x064e3b
    dq s_emerald_950, 0x022c22
    dq s_teal_50, 0xf0fdfa
    dq s_teal_100, 0xccfbf1
    dq s_teal_200, 0x99f6e4
    dq s_teal_300, 0x5eead4
    dq s_teal_400, 0x2dd4bf
    dq s_teal_500, 0x14b8a6
    dq s_teal_600, 0x0d9488
    dq s_teal_700, 0x0f766e
    dq s_teal_800, 0x115e59
    dq s_teal_900, 0x134e4a
    dq s_teal_950, 0x042f2e
    dq s_cyan_50, 0xecfeff
    dq s_cyan_100, 0xcffafe
    dq s_cyan_200, 0xa5f3fc
    dq s_cyan_300, 0x67e8f9
    dq s_cyan_400, 0x22d3ee
    dq s_cyan_500, 0x06b6d4
    dq s_cyan_600, 0x0891b2
    dq s_cyan_700, 0x0e7490
    dq s_cyan_800, 0x155e75
    dq s_cyan_900, 0x164e63
    dq s_cyan_950, 0x083344
    dq s_sky_50, 0xf0f9ff
    dq s_sky_100, 0xe0f2fe
    dq s_sky_200, 0xbae6fd
    dq s_sky_300, 0x7dd3fc
    dq s_sky_400, 0x38bdf8
    dq s_sky_500, 0x0ea5e9
    dq s_sky_600, 0x0284c7
    dq s_sky_700, 0x0369a1
    dq s_sky_800, 0x075985
    dq s_sky_900, 0x0c4a6e
    dq s_sky_950, 0x082f49
    dq s_blue_50, 0xeff6ff
    dq s_blue_100, 0xdbeafe
    dq s_blue_200, 0xbfdbfe
    dq s_blue_300, 0x93c5fd
    dq s_blue_400, 0x60a5fa
    dq s_blue_500, 0x3b82f6
    dq s_blue_600, 0x2563eb
    dq s_blue_700, 0x1d4ed8
    dq s_blue_800, 0x1e40af
    dq s_blue_900, 0x1e3a8a
    dq s_blue_950, 0x172554
    dq s_indigo_50, 0xeef2ff
    dq s_indigo_100, 0xe0e7ff
    dq s_indigo_200, 0xc7d2fe
    dq s_indigo_300, 0xa5b4fc
    dq s_indigo_400, 0x818cf8
    dq s_indigo_500, 0x6366f1
    dq s_indigo_600, 0x4f46e5
    dq s_indigo_700, 0x4338ca
    dq s_indigo_800, 0x3730a3
    dq s_indigo_900, 0x312e81
    dq s_indigo_950, 0x1e1b4b
    dq s_violet_50, 0xf5f3ff
    dq s_violet_100, 0xede9fe
    dq s_violet_200, 0xddd6fe
    dq s_violet_300, 0xc4b5fd
    dq s_violet_400, 0xa78bfa
    dq s_violet_500, 0x8b5cf6
    dq s_violet_600, 0x7c3aed
    dq s_violet_700, 0x6d28d9
    dq s_violet_800, 0x5b21b6
    dq s_violet_900, 0x4c1d95
    dq s_violet_950, 0x2e1065
    dq s_purple_50, 0xfaf5ff
    dq s_purple_100, 0xf3e8ff
    dq s_purple_200, 0xe9d5ff
    dq s_purple_300, 0xd8b4fe
    dq s_purple_400, 0xc084fc
    dq s_purple_500, 0xa855f7
    dq s_purple_600, 0x9333ea
    dq s_purple_700, 0x7e22ce
    dq s_purple_800, 0x6b21a8
    dq s_purple_900, 0x581c87
    dq s_purple_950, 0x3b0764
    dq s_fuchsia_50, 0xfdf4ff
    dq s_fuchsia_100, 0xfae8ff
    dq s_fuchsia_200, 0xf5d0fe
    dq s_fuchsia_300, 0xf0abfc
    dq s_fuchsia_400, 0xe879f9
    dq s_fuchsia_500, 0xd946ef
    dq s_fuchsia_600, 0xc026d3
    dq s_fuchsia_700, 0xa21caf
    dq s_fuchsia_800, 0x86198f
    dq s_fuchsia_900, 0x701a75
    dq s_fuchsia_950, 0x4a044e
    dq s_pink_50, 0xfdf2f8
    dq s_pink_100, 0xfce7f3
    dq s_pink_200, 0xfbcfe8
    dq s_pink_300, 0xf9a8d4
    dq s_pink_400, 0xf472b6
    dq s_pink_500, 0xec4899
    dq s_pink_600, 0xdb2777
    dq s_pink_700, 0xbe185d
    dq s_pink_800, 0x9d174d
    dq s_pink_900, 0x831843
    dq s_pink_950, 0x500724
    dq s_rose_50, 0xfff1f2
    dq s_rose_100, 0xffe4e6
    dq s_rose_200, 0xfecdd3
    dq s_rose_300, 0xfda4af
    dq s_rose_400, 0xfb7185
    dq s_rose_500, 0xf43f5e
    dq s_rose_600, 0xe11d48
    dq s_rose_700, 0xbe123c
    dq s_rose_800, 0x9f1239
    dq s_rose_900, 0x881337
    dq s_rose_950, 0x4c0519
    dq s_black, 0x000000
    dq s_white, 0xffffff
tw_colors_end:

s_fs_xs db "xs", 0
s_fs_sm db "sm", 0
s_fs_base db "base", 0
s_fs_lg db "lg", 0
s_fs_xl db "xl", 0
s_fs_2xl db "2xl", 0
s_fs_3xl db "3xl", 0
s_fs_4xl db "4xl", 0
s_fs_5xl db "5xl", 0
s_fs_6xl db "6xl", 0
s_fs_7xl db "7xl", 0
s_fs_8xl db "8xl", 0
s_fs_9xl db "9xl", 0

tw_sizes:
    dq s_fs_xs, 12
    dq s_fs_sm, 14
    dq s_fs_base, 16
    dq s_fs_lg, 18
    dq s_fs_xl, 20
    dq s_fs_2xl, 24
    dq s_fs_3xl, 30
    dq s_fs_4xl, 36
    dq s_fs_5xl, 48
    dq s_fs_6xl, 60
    dq s_fs_7xl, 72
    dq s_fs_8xl, 96
    dq s_fs_9xl, 128
tw_sizes_end:

s_sc_0 db "0", 0
s_sc_px db "px", 0
s_sc_0_5 db "0.5", 0
s_sc_1 db "1", 0
s_sc_1_5 db "1.5", 0
s_sc_2 db "2", 0
s_sc_2_5 db "2.5", 0
s_sc_3 db "3", 0
s_sc_3_5 db "3.5", 0
s_sc_4 db "4", 0
s_sc_5 db "5", 0
s_sc_6 db "6", 0
s_sc_7 db "7", 0
s_sc_8 db "8", 0
s_sc_9 db "9", 0
s_sc_10 db "10", 0
s_sc_11 db "11", 0
s_sc_12 db "12", 0
s_sc_14 db "14", 0
s_sc_16 db "16", 0
s_sc_20 db "20", 0
s_sc_24 db "24", 0
s_sc_28 db "28", 0
s_sc_32 db "32", 0
s_sc_36 db "36", 0
s_sc_40 db "40", 0
s_sc_44 db "44", 0
s_sc_48 db "48", 0
s_sc_52 db "52", 0
s_sc_56 db "56", 0
s_sc_60 db "60", 0
s_sc_64 db "64", 0
s_sc_72 db "72", 0
s_sc_80 db "80", 0
s_sc_96 db "96", 0
s_sc_full db "full", 0
s_sc_screen db "screen", 0
s_sc_f1_2 db "1/2", 0
s_sc_f1_3 db "1/3", 0
s_sc_f2_3 db "2/3", 0
s_sc_f1_4 db "1/4", 0
s_sc_f2_4 db "2/4", 0
s_sc_f3_4 db "3/4", 0
s_sc_f1_5 db "1/5", 0
s_sc_f2_5 db "2/5", 0
s_sc_f3_5 db "3/5", 0
s_sc_f4_5 db "4/5", 0
s_sc_f1_6 db "1/6", 0
s_sc_f5_6 db "5/6", 0
s_sc_f1_12 db "1/12", 0
s_sc_f5_12 db "5/12", 0
s_sc_f7_12 db "7/12", 0
s_sc_f11_12 db "11/12", 0

tw_scale:
    dq s_sc_0, 0
    dq s_sc_px, 1
    dq s_sc_0_5, 2
    dq s_sc_1, 4
    dq s_sc_1_5, 6
    dq s_sc_2, 8
    dq s_sc_2_5, 10
    dq s_sc_3, 12
    dq s_sc_3_5, 14
    dq s_sc_4, 16
    dq s_sc_5, 20
    dq s_sc_6, 24
    dq s_sc_7, 28
    dq s_sc_8, 32
    dq s_sc_9, 36
    dq s_sc_10, 40
    dq s_sc_11, 44
    dq s_sc_12, 48
    dq s_sc_14, 56
    dq s_sc_16, 64
    dq s_sc_20, 80
    dq s_sc_24, 96
    dq s_sc_28, 112
    dq s_sc_32, 128
    dq s_sc_36, 144
    dq s_sc_40, 160
    dq s_sc_44, 176
    dq s_sc_48, 192
    dq s_sc_52, 208
    dq s_sc_56, 224
    dq s_sc_60, 240
    dq s_sc_64, 256
    dq s_sc_72, 288
    dq s_sc_80, 320
    dq s_sc_96, 384
    dq s_sc_full, 0
    dq s_sc_screen, 720
    dq s_sc_f1_2, 360
    dq s_sc_f1_3, 240
    dq s_sc_f2_3, 480
    dq s_sc_f1_4, 180
    dq s_sc_f2_4, 360
    dq s_sc_f3_4, 540
    dq s_sc_f1_5, 144
    dq s_sc_f2_5, 288
    dq s_sc_f3_5, 432
    dq s_sc_f4_5, 576
    dq s_sc_f1_6, 120
    dq s_sc_f5_6, 600
    dq s_sc_f1_12, 60
    dq s_sc_f5_12, 300
    dq s_sc_f7_12, 420
    dq s_sc_f11_12, 660
tw_scale_end:
