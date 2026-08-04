---
name: run-web
description: Drive a web app headlessly on Windows (navigate, click, screenshot, read console/network) when chromium-cli is unavailable. Covers the Flutter-web-specific gotchas (debug mode hangs headless, CanvasKit has no real DOM). Use for any project under w:/balossi, not just one repo.
---

Windows has no `chromium-cli` (it's not an npm package, not bundled here).
This skill replaces it with a small Playwright-based REPL driver, usable for
any browser-driven app, not just Flutter.

## Prerequisites (one-time, already done on this machine)

```bash
npm install -g playwright
npx playwright install chromium
```

## Files

- `driver.mjs` — headless-Chromium REPL. Pipe commands to stdin.
- `static-proxy.mjs` — serves a static build directory and proxies one
  URL prefix to a real backend. Needed for SPAs whose release build talks
  to the backend on the same origin (no dev server involved).

## Driving any web app

```bash
SCREENSHOT_DIR=/path/to/shots node driver.mjs <<'EOF'
nav http://localhost:PORT
wait-for text=Dashboard
screenshot 01-landing
click text=New item
type Smoke test
press Enter
screenshot 02-after
console --errors
network --failed
quit
EOF
```

Screenshots land in `<SCREENSHOT_DIR>/<SESSION>/` (`SESSION` env var,
default `default`); the latest is also copied to `screenshot.png`.

### Commands

| command | what it does |
|---|---|
| `nav <url>` | launch Chromium (first call) and navigate |
| `wait-for <sel\|text=…> [timeoutMs]` | wait for an element (default 15s) |
| `screenshot [name]` | full-page screenshot |
| `screenshot-element <sel>` | crop to one element |
| `click <sel\|text=…>` | CSS click (works for real DOM apps) |
| `click-xy <x> <y>` | pixel-coordinate click — **required for CanvasKit** (see below) |
| `fill <sel> <value…>` | fill a real DOM input |
| `type <text>` / `press <key>` | keyboard input at current focus |
| `eval <js-expression>` | evaluate in page, prints JSON |
| `text [sel]` | print innerText |
| `console [--errors]` | dump captured console messages |
| `network [--failed]` | dump captured requests (status + URL) |
| `netcount` | quick count of requests seen so far — cheap progress probe |
| `sleep <ms>` | blind wait, use when there's no reliable selector to wait for |
| `probe-boot` | (Flutter only, call before `nav`) instruments `_flutter.loader` to log each boot stage — see Gotchas |
| `quit` | close browser |

Each `node driver.mjs` invocation is one fresh browser (no session reuse
across invocations). Commands run strictly sequentially even when piped in
one heredoc — don't add manual synchronization.

## Flutter web — critical gotcha: never `flutter run` for headless testing

`flutter run -d web-server` (or `-d chrome`) serves a **debug** build via
`dwds`. In debug mode, dwds deliberately withholds `main()` from executing
until a real debugger attaches to the app's VM-service websocket — this is
by design (so you can debug from the first line), but a headless Playwright
tab is not a debugger, so that websocket never connects and the app **hangs
forever** on a blank page. Symptoms that confirm this diagnosis rather than
a real bug: all ~2000+ DDC module requests succeed (`network` shows no
failures), `console --errors` is empty, but `window.$dartMainTearOffs`
exists (length 1) while `window.$dartMainExecuted` stays `undefined` even
after several minutes. `probe-boot` (called before `nav`) confirms this
directly — it patches `_flutter.loader.didCreateEngineInitializer` and
logs each boot stage; with the debug hang, none of the `PROBE:` lines ever
print.

**Fix: always build release for headless verification.**

```bash
flutter build web
# if it fails with "Avoid non-constant invocations of IconData":
flutter build web --no-tree-shake-icons
```

A release build has no dwds, no debug gate, no VM service — it's a plain
static SPA and boots in Chromium the moment its JS runs (tens of requests,
not thousands — DDC's per-module debug files collapse into one bundle).

### Serving it: static-proxy.mjs

A release build resolves its backend URL relative to its own origin (no
`localhost:8080` debug default), so if the client and backend aren't
already served from the same origin, plain static hosting isn't enough —
API calls 404/501 against the static server. `static-proxy.mjs` serves the
build and forwards one path prefix to the real backend:

```bash
MSYS_NO_PATHCONV=1 node static-proxy.mjs <build/web dir> <port> <api-prefix> <backend-url>
# example (deployment_client, backend already running on 8282):
MSYS_NO_PATHCONV=1 node static-proxy.mjs \
  w:/balossi/deployment/deployment_client/build/web 8767 /deployment http://localhost:8282
```

`MSYS_NO_PATHCONV=1` is required in Git Bash — without it, an argument
starting with `/` (the API prefix) gets silently rewritten into a Windows
path (`/deployment` → `C:/Program Files/Git/deployment`).

Find the right `<api-prefix>` by grepping the client's `main.dart` (or
equivalent) for where it builds its base `Uri` — for Sing-based clients
it's `AppDataControler`'s first argument in `main()`.

### CanvasKit gotcha: there is no real DOM until you click

Flutter's CanvasKit renderer paints everything to a single `<canvas>`.
`querySelectorAll('input')` returns **0** on a fresh page even when a
visible text field is on screen — the native `<input>` backing a field is
only created once that field gains focus. Consequences:

- `click <css-selector>` will time out on anything Flutter-rendered.
  Use `click-xy <x> <y>` with pixel coordinates read off a screenshot
  instead (viewport is 1280×720 by default).
- After `click-xy` on a text field, a real `<input>` now exists — verify
  with `eval document.querySelectorAll('input').length` if unsure — then
  `type <text>` goes to it via the keyboard, not `fill`.
- Multi-step forms (e.g. a login that reveals the password field only
  after a first submit) need a `click-xy` → `type` → `click-xy` (submit)
  → `screenshot` → repeat sequence; don't assume all fields exist upfront.

## Non-Flutter web apps (Vite/Node dev servers, etc.)

No special handling needed — start the dev server, poll its port, then use
`nav`/`wait-for`/`click`/`fill` as in the generic table above (real DOM,
`click`/`fill` work directly). See the built-in `run` skill's
`examples/playwright.md` for the general dev-server pattern this driver
was built to substitute for `chromium-cli` in.
