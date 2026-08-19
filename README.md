# ASMX

Fullstack web framework written in **x86-64 assembly (NASM)** for Linux.
No libc, no runtime, no dependencies — just a static ELF binary that speaks
HTTP. The frontend is **WebAssembly** (also generated from assembly), so the
whole stack — server and browser — is assembly.

Next.js-style file conventions: `page.s` for HTML pages, `route.s` for API
handlers, `not-found.s` for the 404 page, and a `static/` folder served
automatically. Pages declare their UI with the `@` DSL (Tailwind-like) which
compiles to a WASM module per route; the server renders the shell, the glue
script instantiates the module and renders the widgets to the DOM.

## Requirements

- Linux x86-64
- NASM (`nasm`)
- GNU ld (`ld`)
- GNU make (`make`)
- WABT (`wat2wasm`)
- git (for `asmx init`)

```bash
sudo apt install nasm binutils wabt git -y
```

## Quick start

The easiest way to bootstrap a project is the [asmx-cli](https://github.com/weslleymirandadev/asmx-cli)
tool — the "npm" for this framework. Build it, then scaffold:

```bash
git clone https://github.com/weslleymirandadev/asmx-cli.git
cd asmx-cli && make          # produces build/asmx
sudo ln -s "$PWD/build/asmx" /usr/local/bin/asmx   # optional

mkdir myapp && cd myapp
asmx init myapp              # clones the framework + scaffolds a project

# Build the server
make
./build/server

# Build and run
asmx dev
```

That's it. The server listens on port 3000:

```
[ASMX]: listening on http://localhost:3000
```

The dev server logs one line per request:

```
GET / 200 (66μs)
GET /api/hello 200 (55μs)
GET /missing 404 (61μs)
POST /about 405 (54μs)
```

With the CLI (`asmx dev`) it also watches sources, rebuilds on change and
hot-reloads the browser via the `/_asmx/events` stream (see Hot reload
below).

## Project structure

```
myapp/
├── asmx/                  <- the framework
│   ├── asmx.inc           <- public API: macros + externs (include this)
│   ├── asmx/              <- core: listen loop, router, senders, state
│   ├── common/            <- syscalls, strings, macros, errors
│   ├── http/              <- HTTP parsing, MIME, static files
│   ├── json/              <- JSON parser + stringifier
│   ├── net/               <- socket_bind_listen
│   ├── ui/                <- the @ DSL compiler (build tool, pure asm)
│   └── wasm/              <- framework WAT lib + glue.js generator
├── static/                <- per-route UI wasm modules (served automatically)
│   ├── index.wasm         <- root page module (src/app/page.s)
│   └── about/page.wasm    <- /about module (src/app/about/page.s)
├── src/
│   ├── main.asm           <- entry: listen + route dispatch
│   ├── app/               <- your routes (see Routing)
│   └── components/        <- reusable @ DSL components (see Components)
└── Makefile               <- zero-maintenance (auto-discovers everything)
```

## Routing (Next.js-style)

The route path **derives from the file location** — you never declare it.
The Makefile passes it to the assembler via `-DROUTE_PATH`.

| file                              | route            | kind          |
|-----------------------------------|------------------|---------------|
| `src/app/page.s`                  | `/`              | HTML page     |
| `src/app/about/page.s`            | `/about`         | HTML page     |
| `src/app/api/hello/route.s`       | `/api/hello`     | API handler   |
| `src/app/profile/[id]/page.s`     | `/profile/[id]`  | dynamic page  |
| `src/app/not-found.s`             | (reserved)       | 404 page      |

- `page.s` = a page that sends HTML (implicit GET, like `app/page.tsx`).
- `route.s` = an API handler (any response: JSON, text, ...).
- `not-found.s` = the custom 404 page (path reserved as `/__not_found`).
- Anything in `static/` is served at `/` automatically — **no route needed**.

### Minimal page

Pages run in `section .SERVER` and end with `asmx.next`:

```nasm
; src/app/page.s  ->  GET /
; asmx.inc is pre-included by the Makefile

section .data
    home_html db '<h1>hello from assembly</h1>', 0

page get_home

section .SERVER
get_home:
    res.html home_html
    asmx.next
```

A `page` route is GET-only — POST yields an automatic 405.

### Middleware (`src/middleware.s`)

Next.js `middleware.ts` style: a `src/middleware.s` file runs BEFORE routing,
on every request. It can let the request through, redirect it, rewrite the
path, or answer directly. It lives at the same level as `app/` and
`components/`:

```nasm
; src/middleware.s - protect /admin/* with a session cookie
; asmx.inc is pre-included by the Makefile

middleware mw_auth

section .MIDDLEWARE
mw_auth:
    ; only guard paths under /admin (config.matcher equivalent)
    lea rdi, [route]
    lea rsi, [admin_prefix]
    mov rdx, 7              ; len("/admin/")
    call strncmp
    test rax, rax
    jnz .pass               ; not /admin/* -> let everything through

    req.cookie "session"    ; rax = value ptr, rdx = len, 0 if absent
    test rax, rax
    jz .deny

.pass:
    mw.next                 ; continue routing (the page/API runs)

.deny:
    mw.redirect "/login"    ; 302 + Location, stop

section .data
    admin_prefix db "/admin/", 0
```

The handler must end with ONE of:

| macro                  | effect                                          |
|------------------------|-------------------------------------------------|
| `mw.next`              | continue routing (the matched page/API runs)    |
| `mw.redirect "path"`   | 302 Found + `Location: path`, stop              |
| `mw.rewrite "path"`    | rewrite `req.path` to `path`, continue routing  |
| `mw.status code`       | respond with a status code, empty body, stop    |
| `mw.json/text/html ptr`| respond directly, stop                          |

Request access inside the middleware (also usable in any handler):

| macro               | result                                          |
|---------------------|-------------------------------------------------|
| `req.header "Name"` | header value: `rax` = ptr, `rdx` = len, 0 absent (case-insensitive name) |
| `req.cookie "name"` | cookie value: `rax` = ptr, `rdx` = len, 0 absent (exact name, up to `;`) |
| `req.path`          | current path (the `route` buffer)               |

Register with `middleware mw_auth` (one entry per project); without the
file, routing is unchanged. A single middleware handler is called for every
request, so the matcher check is up to you (as in Next.js `config.matcher`).


### Minimal API

```nasm
; src/app/api/hello/route.s  ->  /api/hello
; asmx.inc is pre-included by the Makefile

section .data
    hello db '{"hello": "world"}', 0

route.get get_hello

section .GET
get_hello:
    res.json hello
    asmx.next
```

### Route with all methods

```nasm
; src/app/api/user/route.s  ->  /api/user
; asmx.inc is pre-included by the Makefile

section .data
    ok db '{"ok": true}', 0

route get_user, post_user, put_user, patch_user, delete_user

section .GET
get_user:
    res.json ok
    asmx.next

section .POST
post_user:
    res.json ok
    asmx.next

section .PUT
put_user:
    res.json ok
    asmx.next

section .PATCH
patch_user:
    res.json ok
    asmx.next

section .DELETE
delete_user:
    res.json ok
    asmx.next
```

Every handler must end with `asmx.next` (back to the accept loop). A missing
handler (`0` in the route entry) yields an automatic `405 Method Not
Allowed`. HEAD/OPTIONS are parsed but not dispatched yet (405). Single-method
convenience macros: `route.get`, `route.post`, `route.put`, `route.patch`,
`route.delete`, `route.both` (GET+POST).

## The `@` DSL (declaring UI in page.s)

Pages can declare their UI directly in `.data` with the `@` DSL — a
Tailwind-flavored, indentation-based tree language. It is NOT HTML: the
build compiles each block into a serialized widget tree, an HTML shell, and
a WASM module that renders it in the browser.

```nasm
; src/app/about/page.s  ->  GET /about
; asmx.inc is pre-included by the Makefile

section .data
    about_content:
        @main bg-black text-white min-h-screen p-8:
            @h1 text-4xl: "About o ASMX"
            @p text-blue-500: "Fullstack Assembly + WebAssembly"

            @div bg-white w-10:
                @h2 text-black font-bold: "Oi"

            @@card color="#f00" title="Blog":
                "Today's blog is about..."
        @end

page get_about

section .SERVER
get_about:
    res.content about_content
    asmx.next
```

- **Tags**: `@main @div @section @nav @header @footer @h1 @h2 @h3 @p @span
  @a @button`. Text-bearing tags (`h1 h2 h3 p span a button`) take inline
  text after a colon: `@h1 text-4xl: "Texto"`.
- **Classes**: `bg-<color> text-<color> text-<size> font-bold p-* m-* mt-*
  mb-* w-* min-h-screen` — full Tailwind v3 palette (slate→rose, 50–950,
  black/white) and spacing scale (0→96, px, fractions, screen).
- **Children**: indentation is the tree. A bare string on its own line is a
  text child of the nearest open tag.
- `@theme bg #hex text #hex accent #hex` (optional, anywhere in the block).
  Without it, the root view's `bg-*` becomes the page background.
- **`@end`** closes the block.
- `res.content <label>` sends the generated shell (`<label>_shell`); the
  glue script loads `<route>/page.wasm` and renders the widgets.

### Interactive elements

A page with a `@button` and a `@p` containing `"count: 0"` gets a wired
`handle_event` automatically: clicking the button (or pressing SPACE)
increments the digit. The generated WASM keeps a `$count` global and
re-renders the dirty widget (the glue polls `ui_dirty`).

```nasm
; src/app/page.s (the home page)
section .data
    index_content:
        @theme bg #0f1117 text #f5f5f5 accent #f97316
        @main p-8
            @h1 text-5xl font-bold text-orange-500:
                "OLHA O MACACeO"
            @p text-gray-400 mt-4:
                "assembly no servidor - wasm no browser"
            @div mt-8 p-6:
                @p text-2xl:
                    "count: 0"
                @button bg-orange-500 mt-6 p-3:
                    "CLIQUE AQUI"
            @p text-gray-400 mt-8:
                "aperte ESPACO ou clique no botao"
        @end
```

The build recognizes the `count: N` text pattern and emits a hit-test +
increment handler in the module (see `asmx/ui/literals.inc`).

## Components (`@@name`)

Reusable blocks live in `src/components/<name>.s` and are invoked with
`@@name key="value"` (or `@@name key="value":` + children on the next line).
They take `{param}` placeholders and a special `{children}` slot.

```nasm
; src/components/badge.s
; Usage: @@badge cor="green-500": "texto"
badge:
    @div bg-{cor} p-2
        {children}
    @end
```

```nasm
; src/components/card.s
; Usage: @@card cor="blue-500" titulo="...": "children aqui"
card:
    @div bg-{cor} p-6
        @h1 text-white text-2xl
            "{titulo}"
        {children}
        @@badge cor="green-500": "componente aninhado"
    @end
```

- Parameters are substituted into class names and text (`bg-{cor}`).
- `{children}` is replaced by whatever the caller passes — inline after the
  `:` (`@@card ...: "texto"`) or as a following line.
- Components nest recursively (up to depth 16) and any change to a component
  rebuilds every page (`COMP_SRCS` in the Makefile).
- The page block also gets an implicit label: `@@card` in `about_content`
  compiles to `about_content.wat` + `_main.wat` under
  `build/<page>.s.d/`, linked into the page's module.

## Dynamic routes (`[id]` segments)

Next.js-style slugs: a `[id]` segment in the file path becomes a pattern
route. `src/app/profile/[id]/page.s` matches `/profile/joao`, `/profile/42`,
etc.

```nasm
; src/app/profile/[id]/page.s  ->  GET /profile/<slug>
; asmx.inc is pre-included by the Makefile

section .data
    profile_content:
        @main p-8:
            @h1 text-4xl font-bold text-orange-500:
                "Perfil"
            @div mt-8:
                @@card cor="#1e3a5f" titulo="Oi {slug}":
                    "Bem-vindo, {slug}!"
        @end

page get_profile

section .SERVER
get_profile:
    res.content profile_content
    asmx.next
```

How it works:

- The router tries exact string matches first; if none, it tests the pattern
  (prefix before `[`, suffix after `]`). The matched segment is copied to
  `slug_buf` (null-terminated) and `slug_len`.
- Server-side: `req.slug` gives you the slug (`rdi` = ptr, `rsi` = len) in
  any `.SERVER` handler.
- Client-side: the glue writes the last path segment of `location.pathname`
  into the module's `slug_area` export, and **`{slug}` in any text is
  replaced at render time**. `/profile/joao` renders the card with
  "Oi joao".
- The wasm module is shared by every slug — one module per route pattern:
  `static/profile/[id]/page.wasm`, served at the literal `/profile/[id]/page.wasm`
  URL (the file keeps the brackets exactly like the route).
- A slug containing a `.` is treated as a static asset (e.g.
  `/profile/page.wasm` is a file, not a slug) so dynamic routes never shadow
  static files.
- You can have BOTH `src/app/profile/page.s` (static `/profile`) and
  `src/app/profile/[id]/page.s` (dynamic `/profile/<slug>`) — they get
  separate modules (`static/profile/page.wasm` and
  `static/profile/[id]/page.wasm`) and the exact route wins.

## How the frontend is built

Each `@` block in a `page.s` goes through `build/tools/ui-compile` — a
**pure-assembly preprocessor** (no Python):

1. parses the block (tags, classes, params, children),
2. expands `@@component` calls from `src/components/`,
3. emits one `.wat` file per component + a `_main.wat` (render + theme +
   event wiring) into `build/<page>.s.d/`,
4. rewrites the page with an **SSR HTML shell**:
   `<div id="ui" data-asmx-root="..." data-asmx-checksum="...">` + the full
   server-rendered widget tree + the state snapshot + the glue script tag.

The Makefile then links the framework WAT lib (`asmx/wasm/*.wat`: draw,
text, widgets, components) + those `.wat` files into one module per page:
`static/<route>/page.wasm` (root = `static/index.wasm`), via `cat | wat2wasm`.

The module exports (all framework-provided):

| export         | purpose                                              |
|----------------|------------------------------------------------------|
| `render`       | rebuild the widget tree (also resets dirty flag)     |
| `widgets`      | base pointer of the widget array (32-byte records)   |
| `widget_count` | number of widgets                                    |
| `ui_dirty`     | 1 if a re-render is pending (events set it)          |
| `ui_theme_bg/text/accent` | theme colors                            |
| `slug_area`    | writable address where the glue stores the slug      |
| `styles`       | base pointer of the 16-byte style records            |
| `ssr_checksum` | FNV-1a of the canonical IR (see SSR below)           |
| `set_count`/`get_count` | counter state accessors (hydration snapshot)  |
| `handle_event` | (type, x, y, key) — clicks/mouse/keyboard dispatch   |

`/_asmx/glue.js` is a virtual file served by the framework (no entry in
`static/`): it instantiates the module, applies the theme, syncs the widget
tree to DOM (`View → div`, `Text → span`), forwards mouse/keyboard events,
and polls `ui_dirty` to re-render on interaction.

## SSR + hydration

The shell the server sends is not an empty container: `ui-compile` renders
the **full widget tree as HTML** at build time (same IR as the WASM — the
serialized blob + style records — so both backends cannot diverge by
construction). Each widget gets a stable `data-asmx-id` (its record index,
deterministic pre-order) and inline CSS identical to what the glue would
compute. The page also carries:

- `data-asmx-root="<route>"` on `#ui` — the root id the runtime hydrates;
- `data-asmx-checksum="<hex>"` — FNV-1a over the canonical IR (records
  with the text_ptr field skipped + strings in record order);
- `<script type="application/asmx-state">` — the hydration snapshot
  (minimal render state, e.g. `{"root":"index","count":0}`);
- `<style data-asmx-base>` — the global reset + theme (`body` background
  and color), served WITH the HTML so the first paint is already the
  final layout; the glue skips injecting its own copy when this tag is
  present (no layout flicker on reload).

```html
<div id="ui" data-asmx-root="index" data-asmx-checksum="587c9529"
     data-modules="/index.wasm">
  <div data-asmx-id="0" style="position:relative;display:flex;...">
    <span data-asmx-id="1" style="...">OLHA O MACACO</span>
    ...
  </div>
</div>
<script type="application/asmx-state">{"root":"index","count":0}</script>
<script type="module" src="/_asmx/glue.js"></script>
```

The runtime is an explicit phase machine:

```text
SSR  ->  HYDRATING  ->  INTERACTIVE
```

During **HYDRATING** the glue:

1. locates the root by `data-asmx-root` (falls back to client rendering
   when absent);
2. parses the snapshot and restores the render state **before** the first
   render (`set_count`);
3. recomputes the checksum in the module (`ssr_checksum`) and compares it
   with `data-asmx-checksum` — a mismatch logs an `ASMX Hydration Error`
   with the server/client hashes;
4. maps the SSR DOM by `data-asmx-id` and **reuses** those nodes — no
   structural changes unless a node is missing or its tag type diverges
   (that subtree alone is re-created, with a diagnostic);
5. validates text per node (slug replacement happens here; `{slug}` in the
   SSR DOM is expected and not reported);
6. attaches behavior (event listeners) and enters **INTERACTIVE**.

So the browser never rebuilds the page: SSR produces the appearance,
hydration connects the behavior. `curl` shows the full rendered UI even
with JavaScript disabled.

### Determinism rules

- The first render is deterministic: SSR and client read the same IR, and
  the snapshot carries the render state (never re-query a database or
  `random()`/`Date` for first-render values).
- `{slug}` is a browser-only value: the SSR DOM shows the placeholder and
  the glue substitutes it during hydration (documented divergence, not an
  error).
- If you break SSR/client equivalence (e.g. stale `static/` wasm after
  editing a page), the checksum mismatch tells you exactly which root and
  which hashes diverged, and the glue repairs the tree node by node.

### Hot reload (dev)

The glue opens `/_asmx/events` (EventSource) which answers once with
`retry: 250` and closes (the server is single-threaded). The browser
reconnects on its own; each `onopen` re-fetches the wasm with
`cache: "no-store"` and, if the bytes changed, re-instantiates and
re-renders. `asmx dev` (the CLI) rebuilds on file change and the page
updates without a manual refresh.

## Public API

**No `%include` needed.** The Makefile pre-includes `asmx.inc` into every
`src/` file via NASM `-P` (see Makefile below) — just write your handlers.
A manual `%include "asmx.inc"` in a src file is harmless (the file has an
`%ifndef` guard).

Include `%include "asmx.inc"` in every route file if you assemble outside
the Makefile.

### Response (`res.`)

```nasm
res.json ptr        ; 200, application/json
res.text ptr        ; 200, text/plain
res.html ptr        ; 200, text/html
res.status code     ; status code, empty body (e.g. res.status 404)
res.bytes ptr, len  ; 200 JSON with explicit length (raw buffers)
res.content ptr     ; page.s @ DSL block: send the HTML shell whose glue
                    ; renders the per-route wasm module
```

### Request (`req.`)

```nasm
req.path            ; current path buffer (property = `route`)
req.method          ; method string "GET" (property)
req.method_idx      ; rax = method index (GET=0, POST=1, DELETE=4, -1 unknown)
req.body            ; rax = POST body ptr
req.body_len        ; rax = POST body len
req.get "key"       ; json_find over the body -> rax ptr, rdx len, rcx type
req.has "key"       ; rax = 1 if the key exists, 0 otherwise
req.slug            ; dynamic route slug: rdi = ptr, rsi = len ("" if none)
```

Keys passed as string literals (`req.get "user"`) are emitted inline with a
jump-over-data pattern; labels work too (`req.get k_user`).

### Framework (`asmx.`)

```nasm
asmx.listen PORT    ; bind + accept loop (code after runs per request)
asmx.next           ; end the handler (jmp requests)
```

`requests` is a reserved symbol (the accept loop). Never define a label with
that name.

### Route registration

```nasm
route get, post, put, patch, delete   ; all five, 0 = not supported
route.get h   route.post h   route.put h   route.patch h   route.delete h
route.both get, post
```

### Symbols

| symbol     | description                                    |
|------------|------------------------------------------------|
| `route`    | buffer holding the current request path        |
| `requests` | the accept loop — `asmx.next` ends a handler   |
| `buffer`   | 4096-byte request buffer                       |
| `resp_buf` | 512-byte response header buffer                |
| `client_fd`| current connection fd                          |

### Section conventions

| section    | use                              | exec |
|------------|----------------------------------|------|
| `.GET`     | GET API handler (`route.s`)      | yes  |
| `.POST`    | POST API handler (`route.s`)     | yes  |
| `.PUT` / `.PATCH` / `.DELETE` | same        | yes  |
| `.SERVER`  | page handler (`page.s`, SSR)     | yes  |
| `.CLIENT`  | client assets (`client` macro)   | no   |

## JSON

`json.parse buf, len` validates a whole document (`rax` = 0 ok / -1
invalid). `json.find buf, len, "key"` extracts a value: `rax` = value ptr,
`rdx` = len, `rcx` = type (`JSON_T_*`), `-1` if missing. Strings come
without quotes.

```nasm
; src/app/api/login/route.s
; asmx.inc is pre-included by the Makefile

section .data
    bad db '{"error": "invalid json"}', 0
    ok  db '{"login": "ok"}', 0

route.post post_login

section .POST
post_login:
    ; reject malformed JSON first:
    req.body
    mov rbx, rax
    req.body_len
    mov rsi, rax
    mov rdi, rbx
    call json_parse          ; rax = 0 ok, -1 invalid
    test rax, rax
    jnz .bad
    ; now read a field
    req.get "user"
    cmp rax, -1
    je .bad
    res.json ok              ; rax = value ptr, rdx = len, rcx = type
    asmx.next
.bad:
    res.json bad
    asmx.next
```

Stringifying primitives write at `rsi` and return the length in `rax` (no
null terminator — concatenate into your own buffer):

```nasm
section .data
    open  db '{"n":', 0
    comma db ',"ok":', 0
    close db '}', 0

section .bss
    payload resb 128

; inside a handler:
    lea rdi, [payload]
    lea rsi, [open]
    call strcpy_adv          ; rax = payload + 5
    mov rbx, rax
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

The parser is a full RFC 8259 validator: `\uXXXX` escapes, numbers
(`-1.5e3`), booleans/null, nested objects/arrays, depth limit 32, trailing
garbage rejected.

## POST body

```nasm
; src/app/api/echo/route.s
; asmx.inc is pre-included by the Makefile

route.post post_echo

section .POST
post_echo:
    req.body
    mov rbx, rax             ; body ptr (callee-saved)
    req.body_len
    res.bytes rbx, rax       ; echo the body back
    asmx.next
```

Or with explicit variables: `body_get_json req_body, req_len` stores the
pointer/length into two `.bss` qwords.

## Static files

Any file in `static/` is served automatically when no route matches (GET
only). MIME types and `Content-Length` are resolved from the file:

```
static/index.wasm        ->  GET /index.wasm      (application/wasm)
static/about/page.wasm   ->  GET /about/page.wasm (application/wasm)
static/profile/[id]/page.wasm -> GET /profile/[id]/page.wasm
static/style.css         ->  GET /style.css       (text/css)
```

Supported extensions: `.wasm .html .css .js .png .jpg .jpeg .json .txt`
(fallback: `application/octet-stream`). Directories are never served.
Resolution order: declared routes > dynamic patterns > static fallback >
custom 404.

## Custom 404 page

```nasm
; src/app/not-found.s
; asmx.inc is pre-included by the Makefile

section .data
    nf db '<h1>404</h1><p>nothing here</p>', 0

page nf_handler

section .SERVER
nf_handler:
    res.html nf
    asmx.next
```

## Makefile

The Makefile is zero-maintenance: every `.asm` in the framework and every
`.asm`/`.s` under `src/` is discovered automatically. New routes and new
framework modules build with no edits. The only exception is `asmx/ui/`,
which is the @ DSL compiler build tool (never linked into the server).

- `make` — build `build/server` + all `static/**/page.wasm` modules
- `make run` — build and run
- `make clean` — remove build artifacts

### Automatic `asmx.inc` pre-include

App files (`src/`) are assembled with NASM `-P asmx/asmx.inc`, so you never
write `%include "asmx.inc"` by hand. The framework (`asmx/**`) and the
ui-compile tool are NOT pre-included: they declare their own externs and a
pre-include would conflict (extern vs global on the same symbol). A manual
`%include` in a src file still works (the `%ifndef` guard in asmx.inc makes
it idempotent).

### Dynamic-route build details

A `[id]` segment in a source path maps to the glob-safe `_id` directory in
`build/` (the shell treats `[` as a glob char), while `ROUTE_PATH` keeps the
literal `[id]` for the router pattern and the static output keeps the
brackets: `static/profile/[id]/page.wasm`.

## How it works

- `src/main.asm` calls `asmx.listen 3000`, which grabs the return address as
  the per-request handler, binds the socket and falls into the `requests`
  accept loop: accept -> read -> parse request line + headers -> copy the
  path into `route` -> dispatch.
- The router scans a linker-generated section (`__start_route` /
  `__stop_route`, 48-byte entries: path, GET, POST, PUT, PATCH, DELETE).
  Exact match first, then dynamic `[id]` patterns (prefix + suffix match,
  slug into `slug_buf`). No match -> `/_asmx` virtual files -> static
  fallback (`static/`) -> custom 404.
- Responses are built into `resp_buf` (status line + content-type +
  content-length) and written with the body in two syscalls.
- Frontend modules are plain WebAssembly: the glue JS is a tiny DOM syncer
  (~5 KB) that reads the widget array from module memory and mirrors it into
  the DOM.
- Single-threaded, blocking accept loop. Concurrency (fork, epoll) is on
  the roadmap.

## Testing

```bash
curl -v http://localhost:3000/
curl http://localhost:3000/api/hello
curl http://localhost:3000/profile/joao       # dynamic route
curl http://localhost:3000/about/page.wasm    # static file
curl -X POST http://localhost:3000/api/echo -d '{"x":1}'
curl http://localhost:3000/nonexistent        # custom 404
```

## License

MIT (add your own).
