; tests/app/page.s - home page fixture for the CI (hydrates + interactive)
; The @ DSL block becomes the SSR shell; state/onclick/interp exercise the
; declarative state pipeline end to end.

section .data
    index_content:
        @theme bg #0b1020 text #eef2ff accent #8b5cf6
        @main min-h-screen p-8
            state count: int = 0
            @p text-2xl:
                "count: {count}"
            @button onclick="count++" bg-violet-500 p-4 rounded-xl font-bold:
                "CLICK HERE"
            @button onclick="count = 0" p-4 rounded-xl text-gray-300:
                "reset"
        @end

page get_index

section .SERVER
get_index:
    res.content index_content
    asx.next
