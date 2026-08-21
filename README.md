<div align="center">

<img width="180" alt="ASX Logo" src="https://github.com/user-attachments/assets/d603403f-aec4-4636-929a-91d89fc35839" />

**A fullstack framework that brings modern web development to Assembly.**

Native performance. Fullstack. x86_64 Assembly & WebAssembly.

<br>

[Documentation](#) · [Examples](#) · [Roadmap](#) · [asx-cli](https://github.com/weslleymirandadev/asx-cli)

<br>

![License](https://img.shields.io/badge/license-MIT-blue)
![Platform](https://img.shields.io/badge/platform-Linux%20x86--64-green)
![Language](https://img.shields.io/badge/language-Assembly-orange)
![Frontend](https://img.shields.io/badge/frontend-WebAssembly-purple)

</div>

<br>

## Why ASX?

What if you could build a complete web application without giving up the control and performance of low-level code?

ASX brings a familiar modern web development experience — pages, components, routing, SSR, state, and hot reload — directly to **Assembly**.

The entire stack (server + browser) is written in Assembly.  
The server is a static ELF binary. The frontend is WebAssembly.

No runtime. No libc. No dependency tree.

---

## One project. Fullstack.

```
┌─────────────────┐          ┌─────────────────┐
│     SERVER      │          │     BROWSER     │
│                 │          │                 │
│   Assembly      │ ───────► │   WebAssembly   │
│   HTTP + SSR    │          │   UI + State    │
└─────────────────┘          └─────────────────┘
```

You write pages and components in Assembly using a simple DSL.  
ASX handles routing, server-side rendering, hydration, and the browser runtime for you.

---

## Familiar project structure

Inspired by Next.js conventions:

```
myapp/
├── src/
│   ├── app/
│   │   ├── page.asx          → /
│   │   ├── about/page.asx    → /about
│   │   ├── api/hello/route.asx → /api/hello
│   │   └── profile/[id]/page.asx → /profile/:id
│   ├── components/
│   └── middleware.asx
│   └── main.asx
├── static/
└── Makefile
```

File-based routing. Components. Dynamic routes. Middleware.  
It feels familiar — even though everything underneath is Assembly.

---

## Quick Start

The easiest way is with the [asx-cli](https://github.com/weslleymirandadev/asx-cli):

```bash
# Install the CLI
git clone https://github.com/weslleymirandadev/asx-cli.git
cd asx-cli && make
sudo ln -s "$PWD/build/asx" /usr/local/bin/asx   # optional

# Create a new project
mkdir myapp && cd myapp
asx init myapp

# Run
asx dev
```

Open [http://localhost:3000](http://localhost:3000).

That's it. The server is already listening and hot-reloading on file changes.

### Requirements

- Linux x86-64
- NASM, GNU ld, GNU make, WABT (`wat2wasm`), git

```bash
sudo apt install nasm binutils wabt git -y
```

---

## What makes ASX different?

| Feature              | Description                                      |
|----------------------|--------------------------------------------------|
| **No runtime**       | Pure static binary. No interpreter, no GC.       |
| **No libc**          | Direct syscalls only.                            |
| **Native server**    | Assembly HTTP server with fork-per-connection.   |
| **WebAssembly UI**   | Frontend compiled from the same language.        |
| **File-based routing** | Next.js-style `page.asx` / `route.asx`.        |
| **Components**       | Reusable `@@component` blocks with props.        |
| **SSR + Hydration**  | Real HTML on first paint, then interactive.      |
| **Declarative state**| `state count: int = 0` + `onclick="count++"`.   |
| **Hot reload**       | Instant rebuild + browser refresh in dev.        |
| **Zero deps**        | One binary. Nothing else.                        |

---

## A taste of the code

### A simple page

```nasm
; src/app/page.asx → GET /

section .data
    home_content:
        @main bg-black text-white min-h-screen p-8:
            @h1 text-4xl font-bold text-orange-500:
                "Hello from Assembly"
            @p text-gray-400 mt-4:
                "Server in Assembly. UI in WebAssembly."
            @button bg-orange-500 mt-6 p-3 onclick="count++":
                "Clicked {count} times"
        @end

        state count: int = 0

page get_home
section .SERVER
get_home:
    res.content home_content
    asx.next
```

### An API route

```nasm
; src/app/api/hello/route.asx → /api/hello

section .data
    hello db '{"hello": "world"}', 0

route.get get_hello
section .GET
get_hello:
    res.json hello
    asx.next
```

### A reusable component

```nasm
; src/components/card.asx

card:
    @div bg-{color} p-6 rounded:
        @h2 text-white text-2xl: "{title}"
        {children}
    @end
```

Usage:

```nasm
@@card color="blue-600" title="Welcome":
    "This is a component written in Assembly."
```

---

## Core concepts

### Routing

Routes are derived from the file system — you never declare paths manually.

| File                              | Route            | Type        |
|-----------------------------------|------------------|-------------|
| `src/app/page.asx`                | `/`              | Page        |
| `src/app/about/page.asx`          | `/about`         | Page        |
| `src/app/api/hello/route.asx`     | `/api/hello`     | API         |
| `src/app/profile/[id]/page.asx`  | `/profile/[id]`  | Dynamic     |
| `src/app/not-found.asx`           | (404)            | Not found   |

### The `@` DSL

Declare UI with a clean, indentation-based syntax inspired by Tailwind:

```nasm
@main p-8 bg-black text-white:
    @h1 text-3xl: "Title"
    @p text-gray-400: "Subtitle"
    @button onclick="count++": "Click me"
@end
```

Supports real HTML tags, attributes, classes, nested components, state, and events.

### Middleware

Protect routes the same way you would in Next.js:

```nasm
; src/middleware.asx

middleware mw_auth
section .MIDDLEWARE
mw_auth:
    ; your logic here
    mw.next          ; or mw.redirect "/login"
```

### Server-side state injection

```nasm
get_home:
    mov rax, 42
    ssr.state "count", rax    ; inject real data into the first paint
    res.content home_content
    asx.next
```

---

## Learn more

| Topic              | Description                                      |
|--------------------|--------------------------------------------------|
| **Getting Started**| Full installation and first project walkthrough  |
| **Routing**        | Pages, APIs, dynamic segments, middleware        |
| **Components**     | Reusable blocks, props, typed state              |
| **UI & State**     | The `@` DSL, events, reactive updates            |
| **SSR & Hydration**| How the first paint and interactivity work       |
| **Architecture**   | Internals, WASM pipeline, runtime details        |

> Detailed technical documentation (architecture, IR, checksums, WASM exports, etc.) lives in the docs.  
> The README is meant to show you what you can build.

---

## Philosophy

ASX is not "an HTTP server written in Assembly".

It is an experiment in bringing the **developer experience** of modern web frameworks to the lowest level of the stack — without sacrificing control, performance, or simplicity.

Everything you see (routing, components, SSR, state, hot reload) is built on top of pure Assembly and WebAssembly.

No frameworks underneath. No runtime. Just the machine.

---

<div align="center">

**Built with Assembly · x86-64 · WebAssembly**

<br>

⭐ If this project interests you, consider giving it a star!

</div>

---

## License

MIT
