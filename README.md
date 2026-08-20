# ASX

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
- git (for `asx init`)

```bash
sudo apt install nasm binutils wabt git -y
```

## Quick start

The easiest way to bootstrap a project is the [asx-cli](https://github.com/weslleymirandadev/asx-cli)
tool — the "npm" for this framework. Build it, then scaffold:

```bash
git clone https://github.com/weslleymirandadev/asx-cli.git
cd asx-cli && make          # produces build/asx
sudo ln -s "$PWD/build/asx" /usr/local/bin/asx   # optional

mkdir myapp && cd myapp
asx init myapp              # clones the framework + scaffolds a project

# Build the server
make
./build/server

# Build and run
asx dev
```

That's it. The server listens on port 3000:

```
[ASX]: listening on http://localhost:3000
```

The dev server logs one line per request:

```
GET / 200 (66μs)
GET /api/hello 200 (55μs)
GET /missing 404 (61μs)
POST /about 405 (54μs)
```

With the CLI (`asx dev`) it also watches sources, rebuilds on change and
hot-reloads the browser via the `/_asx/events` stream (see Hot reload
below).

## Project structure

```
myapp/
├── asx/                  <- the framework
│   ├── asx.inc           <- public API: macros + externs (include this)
│   ├── asx/              <- core: listen loop, router, senders, state
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

Pages run in `section .SERVER` and end with `asx.next`:

```nasm
; src/app/page.s  ->  GET /
; asx.inc is pre-included by the Makefile

section .data
    home_html db '<h1>hello from assembly</h1>', 0

page get_home

section .SERVER
get_home:
    res.html home_html
    asx.next
```

A `page` route is GET-only — POST yields an automatic 405.

### Middleware (`src/middleware.s`)

Next.js `middleware.ts` style: a `src/middleware.s` file runs BEFORE routing,
on every request. It can let the request through, redirect it, rewrite the
path, or answer directly. It lives at the same level as `app/` and
`components/`:

```nasm
; src/middleware.s - protect /admin/* with a session cookie
; asx.inc is pre-included by the Makefile

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
; asx.inc is pre-included by the Makefile

section .data
    hello db '{"hello": "world"}', 0

route.get get_hello

section .GET
get_hello:
    res.json hello
    asx.next
```

### Route with all methods

```nasm
; src/app/api/user/route.s  ->  /api/user
; asx.inc is pre-included by the Makefile

section .data
    ok db '{"ok": true}', 0

route get_user, post_user, put_user, patch_user, delete_user

section .GET
get_user:
    res.json ok
    asx.next

section .POST
post_user:
    res.json ok
    asx.next

section .PUT
put_user:
    res.json ok
    asx.next

section .PATCH
patch_user:
    res.json ok
    asx.next

section .DELETE
delete_user:
    res.json ok
    asx.next
```

Every handler must end with `asx.next` (back to the accept loop). A missing
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
; asx.inc is pre-included by the Makefile

section .data
    about_content:
        @main bg-black text-white min-h-screen p-8:
            @h1 text-4xl: "About ASX"
            @p text-blue-500: "Fullstack Assembly + WebAssembly"

            @div bg-white w-10:
                @h2 text-black font-bold: "Hi"

            @@card color="#f00" title="Blog":
                "Today's blog is about..."
        @end

page get_about

section .SERVER
get_about:
    res.content about_content
    asx.next
```

- **Tags**: `@main @div @section @nav @header @footer @h1 @h2 @h3 @p @span
  @a @button`. Text-bearing tags (`h1 h2 h3 p span a button`) take inline
  text after a colon: `@h1 text-4xl: "Text"`.
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

### Interactive elements (declarative state)

Pages declare state with `state` directives and wire events with the
`onclick` attribute — no magic string patterns. State lives in WASM
linear memory (scalars or typed records); the compiler emits the render
+ update logic, and the glue only forwards clicks by widget id.

```nasm
; src/app/page.s (the home page)
section .data
    index_content:
        @theme bg #0f1117 text #f5f5f5 accent #f97316
        @main p-8
            state count: int = 0
            @h1 text-5xl font-bold text-orange-500:
                "LOOK AT THE MONKEY"
            @p text-gray-400 mt-4:
                "assembly on the server - wasm in the browser"
            @div mt-8 p-6:
                @p text-2xl:
                    "count: {count}"
                @button bg-orange-500 mt-6 p-3 onclick="count++":
                    "CLICK HERE"
                @button bg-orange-500 mt-2 p-3 onclick="count = 0":
                    "RESET"
            @p text-gray-400 mt-8:
                "press SPACE or click the button"
        @end
```

- `state <name>: <type> = <value>` declares a mutable WASM global
  (`int`, `bool`, `string` — default 128 bytes) or a typed record
  (`type user_t` + `state user: user_t` with fields).
- `onclick="<expr>"` supports `count++`, `count = 0`, `user.age++`,
  `user.admin = true`.
- `{state}` / `{state.field}` in any text is re-rendered from the state
  on every render; SSR interpolates the initial value, so the first
  paint already shows it (no flicker).
- Strict typing: `if`/conditions require `bool`; unknown states/fields
  are compile-time errors.
- Clicks dispatch by widget id: the glue resolves `data-asx-id` (via
  `closest`) and calls `handle_event(1, id, 0, 0, 0)`; the module's
  switch runs only the matching action and marks the widget dirty
  (`ui_dirty` → the glue re-renders).

## Components (`@@name`)

Reusable blocks live in `src/components/<name>.s` and are invoked with
`@@name key="value"` (or `@@name key="value":` + children on the next line).
They take `{param}` placeholders and a special `{children}` slot.

```nasm
; src/components/badge.s
; Usage: @@badge color="green-500": "text"
badge:
    @div bg-{color} p-2
        {children}
    @end
```

```nasm
; src/components/card.s
; Usage: @@card color="blue-500" title="...": "children here"
card:
    @div bg-{color} p-6
        @h1 text-white text-2xl
            "{title}"
        {children}
        @@badge color="green-500": "nested component"
    @end
```

- Parameters are substituted into class names and text (`bg-{color}`).
- `{children}` is replaced by whatever the caller passes — inline after the
  `:` (`@@card ...: "text"`) or as a following line.
- Components nest recursively (up to depth 16) and any change to a component
  rebuilds every page (`COMP_SRCS` in the Makefile).
- The page block also gets an implicit label: `@@card` in `about_content`
  compiles to `about_content.wat` + `_main.wat` under
  `build/<page>.s.d/`, linked into the page's module.

### Typed props

A component can bind a global state by name with a type annotation:

```nasm
; src/app/page.s
section .data
    index_content:
        @main p-8
            type user_t
                name: string
                age: int
                admin: bool
            state user: user_t
                name: "weslley"
                age: 30
                admin: false
            @@usercard user: user_t
        @end

; src/components/usercard.s
usercard:
    @div bg-orange-500 p-4
        @p text-white: "{user.name}"
        @p text-white: "{user.age} anos"
    @end
```

`@@usercard user: user_t` is validated at compile time: the state `user`
must exist and be an object of type `user_t` (unknown states, scalar
states and type mismatches are errors). Inside the component body,
`{user.name}` / `{user.age}` interpolate the global state like anywhere
else — the body is expanded before the compile pass, so states remain
accessible and typed.

## Dynamic routes (`[id]` segments)

Next.js-style slugs: a `[id]` segment in the file path becomes a pattern
route. `src/app/profile/[id]/page.s` matches `/profile/joao`, `/profile/42`,
etc.

```nasm
; src/app/profile/[id]/page.s  ->  GET /profile/<slug>
; asx.inc is pre-included by the Makefile

section .data
    profile_content:
        @main p-8:
            @h1 text-4xl font-bold text-orange-500:
                "Profile"
            @div mt-8:
                @@card color="#1e3a5f" title="Hi {slug}":
                    "Welcome, {slug}!"
        @end

page get_profile

section .SERVER
get_profile:
    res.content profile_content
    asx.next
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
  "Hi joao".
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

1. parses the block (tags, classes, params, children, `state`/`type`
   directives, `onclick` attributes, `{state.field}` interpolations),
2. expands `@@component` calls from `src/components/`,
3. emits one `.wat` file per component + a `_main.wat` (render + theme +
   event wiring) into `build/<page>.s.d/`,
4. rewrites the page with an **SSR HTML shell**:
   `<div id="ui" data-asx-root="..." data-asx-checksum="...">` + the full
   server-rendered widget tree + the state snapshot + the glue script tag.

The Makefile then links the framework WAT lib (`asx/wasm/*.wat`: draw,
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
| `set_count`/`get_count` | legacy counter accessors (optional — new modules carry state via directives) |
| `handle_event` | (type, widget_id, x, y, key) — clicks dispatch by `data-asx-id`; mouse/keyboard by coords |

`/_asx/glue.js` is a virtual file served by the framework (no entry in
`static/`): it instantiates the module, applies the theme, syncs the widget
tree to DOM (`View → div`, `Text → span`), forwards mouse/keyboard events,
and polls `ui_dirty` to re-render on interaction.

## SSR + hydration

The shell the server sends is not an empty container: `ui-compile` renders
the **full widget tree as HTML** at build time (same IR as the WASM — the
serialized blob + style records — so both backends cannot diverge by
construction). Each widget gets a stable `data-asx-id` (its record index,
deterministic pre-order) and inline CSS identical to what the glue would
compute. The page also carries:

- `data-asx-root="<route>"` on `#ui` — the root id the runtime hydrates;
- `data-asx-checksum="<hex>"` — FNV-1a over the canonical IR (records
  with the text_ptr field skipped + strings in record order);
- `<script type="application/asx-state">` — the hydration snapshot
  (minimal render state, e.g. `{"root":"index"}`; initial state values
  live in the module itself, emitted from the `state` directives);
- `<style data-asx-base>` — the global reset + theme (`body` background
  and color), served WITH the HTML so the first paint is already the
  final layout; the glue skips injecting its own copy when this tag is
  present (no layout flicker on reload).

```html
<div id="ui" data-asx-root="index" data-asx-checksum="474ea74f"
     data-modules="/index.wasm">
  <div data-asx-id="0" style="position:relative;display:flex;...">
    <span data-asx-id="1" style="...">LOOK AT THE MONKEY</span>
    ...
  </div>
</div>
<script type="application/asx-state">{"root":"index"}</script>
<script type="module" src="/_asx/glue.js"></script>
```

The runtime is an explicit phase machine:

```text
SSR  ->  HYDRATING  ->  INTERACTIVE
```

During **HYDRATING** the glue:

1. locates the root by `data-asx-root` (falls back to client rendering
   when absent);
2. parses the snapshot and restores the render state **before** the first
   render (every `set_<name>` export from the snapshot keys — declarative
   states and ssr.state values; legacy `set_count` still works);
3. recomputes the checksum in the module (`ssr_checksum`) and compares it
   with `data-asx-checksum` — a mismatch logs an `ASX Hydration Error`
   with the server/client hashes;
4. maps the SSR DOM by `data-asx-id` and **reuses** those nodes — no
   structural changes unless a node is missing or its tag type diverges
   (that subtree alone is re-created, with a diagnostic);
5. validates text per node (slug replacement happens here; `{slug}` in the
   SSR DOM is expected and not reported);
6. attaches behavior (event listeners) and enters **INTERACTIVE**.

So the browser never rebuilds the page: SSR produces the appearance,
hydration connects the behavior. `curl` shows the full rendered UI even
with JavaScript disabled.

### Server state (`ssr.state`) — real data in the first paint

By default the SSR shell renders the state's **initial value** (declared in
the `state` directive). To inject a real value server-side, the page handler
calls `ssr.state` before `res.content`:

```nasm
; src/app/page.s
section .data
    index_content:
        @main p-8
            state count: int = 0
            @p text-2xl: "count: {count}"
            @button onclick="count++": "CLICK HERE"
        @end

page get_home

section .SERVER
get_home:
    ; count = database()
    mov rax, 42
    ssr.state "count", rax     ; inject into the HTML + hydration snapshot
    res.content index_content
    asx.next
```

`GET /` then serves `count: 42` in the SSR DOM **and**
`{"root":"index","count":42}` in the snapshot. The glue restores the value
via the module's `set_<name>` export **before** the first render, so the
first paint is the server value — no flicker, no second render. Without
any `ssr.state` call the page is served exactly as before (initial values).

- Value must be an integer (int/bool states; string states are fixed
  buffers — setters for them come with the allocator work).
- Object fields use the dotted key: `ssr.state "user.age", rax` (the
  module exports `set_user.age`).
- The table is reset per request (no leakage between requests).

How it works: the compiler marks every interpolated text in the shell with
a substitution slot (`0x01 <state name> 0x02 <default> 0x03`) and the
snapshot with an injection point (`0x04`). `asx_send_content` resolves the
slots against the `ssr.state` table. Interpolated strings are excluded
from the canonical checksum on both sides (the value is runtime data, not
IR) — the glue still validates the rendered text node by node during
hydration.

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

The glue opens `/_asx/events` (EventSource) which answers once with
`retry: 250` and closes (the server is single-threaded). The browser
reconnects on its own; each `onopen` re-fetches the wasm with
`cache: "no-store"` and, if the bytes changed, re-instantiates and
re-renders. `asx dev` (the CLI) rebuilds on file change and the page
updates without a manual refresh.

## Public API

**No `%include` needed.** The Makefile pre-includes `asx.inc` into every
`src/` file via NASM `-P` (see Makefile below) — just write your handlers.
A manual `%include "asx.inc"` in a src file is harmless (the file has an
`%ifndef` guard).

Include `%include "asx.inc"` in every route file if you assemble outside
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

### Framework (`asx.`)

```nasm
asx.listen PORT    ; bind + accept loop (code after runs per request)
asx.next           ; end the handler (jmp requests)
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
| `requests` | the accept loop — `asx.next` ends a handler   |
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
; asx.inc is pre-included by the Makefile

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
    asx.next
.bad:
    res.json bad
    asx.next
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
; asx.inc is pre-included by the Makefile

route.post post_echo

section .POST
post_echo:
    req.body
    mov rbx, rax             ; body ptr (callee-saved)
    req.body_len
    res.bytes rbx, rax       ; echo the body back
    asx.next
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
; asx.inc is pre-included by the Makefile

section .data
    nf db '<h1>404</h1><p>nothing here</p>', 0

page nf_handler

section .SERVER
nf_handler:
    res.html nf
    asx.next
```

## Makefile

The Makefile is zero-maintenance: every `.asm` in the framework and every
`.asm`/`.s` under `src/` is discovered automatically. New routes and new
framework modules build with no edits. The only exception is `asx/ui/`,
which is the @ DSL compiler build tool (never linked into the server).

- `make` — build `build/server` + all `static/**/page.wasm` modules
- `make run` — build and run
- `make clean` — remove build artifacts

### Automatic `asx.inc` pre-include

App files (`src/`) are assembled with NASM `-P asx/asx.inc`, so you never
write `%include "asx.inc"` by hand. The framework (`asx/**`) and the
ui-compile tool are NOT pre-included: they declare their own externs and a
pre-include would conflict (extern vs global on the same symbol). A manual
`%include` in a src file still works (the `%ifndef` guard in asx.inc makes
it idempotent).

### Dynamic-route build details

A `[id]` segment in a source path maps to the glob-safe `_id` directory in
`build/` (the shell treats `[` as a glob char), while `ROUTE_PATH` keeps the
literal `[id]` for the router pattern and the static output keeps the
brackets: `static/profile/[id]/page.wasm`.

## How it works

- `src/main.asm` calls `asx.listen 3000`, which grabs the return address as
  the per-request handler, binds the socket and falls into the `requests`
  accept loop: accept -> fork -> (child) read -> parse request line +
  headers -> copy the path into `route` -> dispatch.
- **Concurrency: fork-per-connection.** The parent accepts and forks; the
  child processes exactly ONE request and exits; the parent closes its
  copy of the client fd and keeps accepting. A slow request (upload,
  large static, SSE) never blocks the queue. No locks, no shared state:
  the fork copies memory (COW), so `buffer`/`route`/`resp_buf` are
  per-connection by construction. `SIGCHLD=SIG_IGN` (set in `asx_listen`)
  makes the kernel reap finished children — no zombies, no waitpid. The
  child closes `server_fd` at fork time so a slow child never holds the
  port after the parent dies (hot reload rebinds immediately).
- The router scans a linker-generated section (`__start_route` /
  `__stop_route`, 48-byte entries: path, GET, POST, PUT, PATCH, DELETE).
  Exact match first, then dynamic `[id]` patterns (prefix + suffix match,
  slug into `slug_buf`). No match -> `/_asx` virtual files -> static
  fallback (`static/`) -> custom 404.
- Responses are built into `resp_buf` (status line + content-type +
  content-length) and written with the body in two syscalls.
- Frontend modules are plain WebAssembly: the glue JS is a tiny DOM syncer
  (~5 KB) that reads the widget array from module memory and mirrors it into
  the DOM.
- Single-threaded per request, but concurrent across requests (fork).
  epoll / shared workers is on the roadmap.

## RPC wasm→servidor (`fetch_req` import)

The wasm module cannot touch sockets — the browser owns the network. The
module imports `env.fetch_req`, implemented by the glue with a
**synchronous XHR** (the wasm call blocks, so async fetch would never
resume on the main thread), and the app decides *when* to call and *what*
to do with the response — all in wasm:

```wat
(import "env" "fetch_req" (func $fetch_req (param $up i32) (param $ul i32)
  (param $mp i32) (param $ml i32) (param $bp i32) (param $bl i32)
  (result i32)))   ;; returns the HTTP status
```

- Arguments are pointers into linear memory: `url_ptr/url_len`,
  `method_ptr/method_len`, `body_ptr/body_len` (body 0/0 for none; a
  non-empty body sends `Content-Type: application/json`).
- The glue writes the response body into the module memory at
  `resp_area()` (a 4096-byte buffer after the widget records) and sets
  `resp_len.value` (mutable exported global). The wasm side reads the
  buffer directly.
- `rpc_call(up, ul, mp, ml, bp, bl) -> status` is the exported thin
  wrapper over the import (also handy for tests/drivers).
- Exports added by the framework: `resp_area`, `resp_cap` (4096),
  `resp_len` (global). `$resp_base` is emitted by the compiler right
  after the widget area (dynamic, like `$widget_base`).

Example (from the wasm side, e.g. a future `onclick="fn()"` handler):

```wat
;; GET /api/hello -> status; body at resp_area()/resp_len
i32.const <url> i32.const 11   ;; "/api/hello"
i32.const <get> i32.const 3    ;; "GET"
i32.const 0 i32.const 0        ;; no body
call $fetch_req                ;; status in the stack
```

Limitations (fase 1): synchronous XHR blocks the UI thread during the
request (fine for local APIs; a worker + Atomics.wait is the async path
on the roadmap). The `onclick="fn()"` DSL + `.WASM` section (the "todo
app with zero JS logic" test of fire) is the next step.

## Testing

```bash
curl -v http://localhost:3000/
curl http://localhost:3000/api/hello
curl http://localhost:3000/profile/joao       # dynamic route
curl http://localhost:3000/about/page.wasm    # static file
curl -X POST http://localhost:3000/api/echo -d '{"x":1}'
curl http://localhost:3000/nonexistent        # custom 404
```

### Automated suites (ROADMAP item 5)

```bash
make -C tests            # CI build: framework + tiny fixture app -> server + wasm
cd tests && ./build/server &
node tests/hydration_test.mjs <html> <glue.js> <index.wasm>  # 9 hydration cases
node tests/fuzz_http.mjs 500                                # HTTP parser fuzz
```

- `tests/hydration_test.mjs` runs the **real glue** against the **real
  SSR HTML** with a minimal fake DOM (no jsdom): clean hydration, text
  mismatch, style divergence, missing/extra node, tag divergence,
  checksum mismatch, CSR fallback, snapshot restore — 9 cases, exit 0 =
  all pass.
- `tests/fuzz_http.mjs` is a black-box socket fuzzer for the HTTP
  parsers (afl++ cannot instrument pure NASM; with fork-per-connection a
  crashed child must never take the accept loop down — the health check
  proves it).
- `.github/workflows/ci.yml` runs the whole pipeline on push/PR: build,
  hydration, fuzz, checksum + routes.

## License

MIT (add your own).
