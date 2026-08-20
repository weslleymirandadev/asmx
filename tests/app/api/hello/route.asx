; tests/app/api/hello/route.s - JSON API fixture (CI fuzz target)

section .data
    hello db '{"hello": "world"}', 0

route get_hello, post_hello, 0, 0, 0

section .GET
get_hello:
    res.json hello
    asx.next

section .POST
post_hello:
    res.json hello
    asx.next
