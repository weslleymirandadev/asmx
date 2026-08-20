; tests/app/not-found.s - custom 404 fixture

section .data
    nf_content:
        @main p-8
            @h1 text-4xl: "404"
            @p: "não encontrado"
        @end

page get_not_found

section .SERVER
get_not_found:
    res.content nf_content
    asx.next
