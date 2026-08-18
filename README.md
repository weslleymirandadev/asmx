# asmx

A web framework written in x86-64 assembly (NASM) for Linux. No libc, no
runtime, no dependencies — just a static ELF binary that speaks HTTP.

Next.js-style file conventions: `page.s` for HTML pages, `route.s` for API
handlers, `not-found.s` for the 404 page, and a `public/` folder served
automatically. Includes a JSON parser and stringifier for handling request
bodies and building responses.

## Requirements

- Linux x86-64
- NASM (`nasm`)
- GNU ld (`ld`)
- GNU make
- git (for `asmx init`)

## Quick start

The easiest way to bootstrap a project is the [asmx-cli](https://github.com/weslleymirandadev/asmx-cli)
tool — the "npm" for this framework. Build it, then scaffold:

```bash
git clone https://github.com/weslleymirandadev/asmx-cli.git
cd asmx-cli && make          # produces build/asmx
sudo ln -s "$PWD/build/asmx" /usr/local/bin/asmx   # optional

mkdir myapp && cd myapp
asmx init myapp              # clones the framework + scaffolds a project
make
./build/server
```

That's it. The server listens on port 8080:

```
[ASMX]: listening on http://localhost:8080
```

## Project structure

```
myapp/
├── asmx/                <- the framework (this repo), installed per-project
│   ├── asmx.inc         <- public API: macros + externs
│   ├── asmx/            <- core: accept loop, router, senders, state
│   ├── common/          <- syscalls, macros, strings, errors
│   ├── http/            <- HTTP parsing, MIME, static files
│   ├── json/            <- JSON parser + stringifier
│   └── net/             <- socket_bind_listen
├── public/              <- static assets, served automatically
│   └── index.html
├── src/
│   ├── main.asm         <- entry point: listen + route dispatch
│   └── app/             <- your routes (see Routing below)
└── Makefile             <- zero-maintenance (auto-discovers everything)
```

## Routing (Next.js-style)

The route path **derives from the file location** — you never declare it.
The build passes it to the assembler via `-DROUTE_PATH`.

| file                          | route       | kind         |
|-------------------------------|-------------|--------------|
| `src/app/page.s`              | `/`         | HTML page    |
| `src/app/sobre/page.s`        | `/sobre`    | HTML page    |
| `src/app/api/hello/route.s`   | `/api/hello`| API handler  |
| `src/app/not-found.s`         | (reserved)  | 404 page     |

- `page.s` = a page that sends HTML.
- `route.s` = an API handler (any response: JSON, text, ...).
- `not-found.s` = the custom 404 page (path reserved as `/__not_found`).
- Anything in `public/` is served at `/` automatically — **no route needed**.

### Minimal page

```nasm
; src/app/page.s  ->  GET /
%include "asmx.inc"

section .data
    home_html db '<h1>hello from assembly</h1>', 0

route get_home, 0

section .GET
get_home:
    send_html home_html
    jmp requests
```

### Minimal API

```nasm
; src/app/api/hello/route.s  ->  GET /api/hello
%include "asmx.inc"

section .data
    hello db '{"hello": "world"}', 0

route get_hello, 0

section .GET
get_hello:
    send_json hello
    jmp requests
```

### Route with GET + POST

```nasm
; src/app/api/user/route.s  ->  /api/user
%include "asmx.inc"

section .data
    ok db '{"ok": true}', 0

route get_user, post_user

section .GET
get_user:
    send_json ok
    jmp requests

section .POST
post_user:
    send_json ok
    jmp requests
```

Every handler must end with `jmp requests` (the accept loop). `requests` is a
reserved symbol. A missing handler (`0` in the route entry) yields an
automatic `405 Method Not Allowed`.

## Public API

Include `%include "asmx.inc"` in every route file.

### Macros

| macro                     | description |
|---------------------------|-------------|
| `listen PORT`             | bind + accept loop; code after it runs once per request |
| `route get, post`         | register handlers for this file's path (`0` = not supported) |
| `cmp route, "/path"`      | string compare of the current path (works with `je`/`jne`) |
| `send_json ptr`           | respond 200, `application/json` |
| `send_text ptr`           | respond 200, `text/plain` |
| `send_html ptr`           | respond 200, `text/html` |
| `send_status code`        | respond with a status code, empty body (e.g. `send_status 404`) |
| `send_json_bytes ptr, len`| respond 200 JSON with explicit length (raw buffers) |
| `body_get_json ptr_var, len_var` | store POST body pointer/length into two `.bss` qwords |

### Symbols

| symbol | description |
|--------|-------------|
| `route` | buffer holding the current request path |
| `requests` | the accept loop — `jmp requests` ends a handler |
| `buffer` | 4096-byte request buffer |
| `resp_buf` | 512-byte response header buffer |
| `client_fd` | current connection fd |

### Handling a POST body

```nasm
; src/app/api/echo/route.s
%include "asmx.inc"

section .bss
    req_body resq 1
    req_len  resq 1

route 0, post_echo          ; POST only

section .POST
post_echo:
    body_get_json req_body, req_len
    send_json_bytes [req_body], [req_len]   ; echo the body back
    jmp requests
```

## Static files

Any file in `public/` is served automatically when no route matches
(GET only). MIME types and `Content-Length` are resolved from the file:

```
public/index.html   ->  GET /index.html   (text/html)
public/app.wasm     ->  GET /app.wasm     (application/wasm)
public/style.css    ->  GET /style.css    (text/css)
```

Supported extensions: `.wasm .html .css .js .png .jpg .jpeg .json .txt`
(fallback: `application/octet-stream`). Directories are never served.
Resolution order: declared routes > static fallback > custom 404.

## JSON

The `json/` domain parses and stringifies JSON without libc. Include
`%include "json/json.inc"`.

### Parsing and extracting fields

```nasm
; src/app/api/login/route.s
%include "asmx.inc"
%include "json/json.inc"

section .data
    bad db '{"error": "invalid json"}', 0
    ok  db '{"login": "ok"}', 0
    k_user db "user", 0

section .bss
    req_body resq 1
    req_len  resq 1

route 0, post_login

section .POST
post_login:
    body_get_json req_body, req_len

    ; validate the whole document first
    mov rdi, [req_body]
    mov rsi, [req_len]
    call json_parse
    test rax, rax
    jnz .bad_json

    ; extract a field: json_find(buf, len, key)
    mov rdi, [req_body]
    mov rsi, [req_len]
    lea rdx, [k_user]
    call json_find
    cmp rax, -1
    je .bad_json
    ; rax = value ptr, rdx = value len, rcx = type
    ; (strings come without the surrounding quotes)
    send_json ok
    jmp requests
.bad_json:
    send_json bad
    jmp requests
```

### Stringifying

The stringifier primitives write at `rsi` and return the length in `rax`
(no null terminator — concatenate into your own buffer):

```nasm
; build {"n":42,"ok":true} into a .bss buffer
%include "asmx.inc"
extern strcpy_adv            ; from common: (dest, src) -> dest+len

section .data
    open   db '{"n":', 0
    comma  db ',"ok":', 0
    close  db '}', 0

section .bss
    payload resb 128

; in a handler:
    lea rdi, [payload]
    lea rsi, [open]
    call strcpy_adv          ; rax = payload + 5
    mov rbx, rax             ; write pos (callee-saved)
    mov rdi, 42
    mov rsi, rbx
    call json_str_int        ; writes "42", rax = len
    add rbx, rax
    mov rdi, rbx
    lea rsi, [comma]
    call strcpy_adv
    mov rbx, rax
    mov rdi, 1
    mov rsi, rbx
    call json_str_bool       ; writes "true"
    add rbx, rax
    mov rdi, rbx
    lea rsi, [close]
    call strcpy_adv
    ; payload = {"n":42,"ok":true}
```

| function | description |
|----------|-------------|
| `json_parse(buf, len)` | validate a JSON document; `0` ok, `-1` invalid |
| `json_find(buf, len, key)` | `rax` = value ptr, `rdx` = len, `rcx` = type (`JSON_T_*`); `-1` if missing |
| `json_str_int(value, dst)` | write an integer, return len |
| `json_str_bool(0/1, dst)` | write `true`/`false`, return len |
| `json_str_null(dst)` | write `null`, return len |
| `json_str_string(src, dst, cap)` | write an escaped string (`"`, `\`, `\b\f\n\r\t`, controls as `\u00XX`); writes what fits in `cap`, returns the total length needed |

Value types (`rcx`): `JSON_T_STRING 0`, `JSON_T_NUMBER 1`, `JSON_T_OBJECT 2`,
`JSON_T_ARRAY 3`, `JSON_T_BOOL 4`, `JSON_T_NULL 5`.

The parser is a full RFC 8259 validator: strings with `\uXXXX` escapes,
numbers (`-1.5e3`), `true`/`false`/`null`, nested objects/arrays, depth
limit 32, trailing garbage rejected. Keys with escapes match literal
equivalents (`"a\u0041"` matches key `aA`).

## Custom 404 page

```nasm
; src/app/not-found.s
%include "asmx.inc"

section .data
    nf db '<h1>404</h1><p>nada por aqui</p>', 0

route nf_handler, 0

section .GET
nf_handler:
    send_html nf
    jmp requests
```

## Makefile

The generated Makefile is zero-maintenance: every `.asm` under the
framework and every `.asm`/`.s` under `src/` is discovered automatically.
New routes and new framework modules build with no edits.

- `make` — build `build/server`
- `make run` — build and run
- `make clean` — remove build artifacts

## Testing

```bash
curl -v http://localhost:8080/
curl http://localhost:8080/api/hello
curl http://localhost:8080/app.wasm        # static file
curl -X POST http://localhost:8080/api/echo -d '{"x":1}'
curl http://localhost:8080/nonexistent     # custom 404
```

## How it works

- `main.asm` calls `listen 8080`, which grabs the return address as the
  per-request handler, binds the socket and falls into the `requests`
  accept loop: accept -> read -> parse request line + headers -> copy the
  path into `route` -> dispatch.
- The router scans a linker-generated section (`__start_route` /
  `__stop_route`, 24-byte entries: path, GET handler, POST handler). No
  match -> static fallback (`public/`) -> custom 404.
- Responses are built into `resp_buf` (status line + content-type +
  content-length) and written with the body in two syscalls.
- Single-threaded, blocking accept loop. Concurrency (fork, epoll) is on
  the roadmap.

## License

MIT (add your own).
