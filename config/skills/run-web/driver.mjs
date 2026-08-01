// REPL driver for headless-Chromium-based smoke testing of any browser-driven
// app (Flutter web, Vite/React dev servers, etc.) under Windows, where
// chromium-cli is unavailable. Uses the globally installed "playwright"
// package (npm install -g playwright && playwright install chromium).
//
// Commands mirror chromium-cli's vocabulary so the "run" skill's
// playwright.md pattern (nav / wait-for / screenshot / click / fill / press
// / console --errors) transfers without translation.
import { createRequire } from "node:module";
import { execSync } from "node:child_process";
import * as readline from "node:readline";
import * as fs from "node:fs";
import * as path from "node:path";

const require = createRequire(import.meta.url);
const globalRoot = execSync("npm root -g", { encoding: "utf8" }).trim();
const { chromium } = require(path.join(globalRoot, "playwright"));

const SESSION = process.env.SESSION || "default";
const SHOT_DIR = path.join(process.env.SCREENSHOT_DIR || path.join(process.cwd(), "playwright-shots"), SESSION);
fs.mkdirSync(SHOT_DIR, { recursive: true });

let browser = null;
let page = null;
let consoleLog = [];
let netLog = [];

function resolveSelector(sel) {
  if (sel.startsWith("text=")) {
    return `text=${sel.slice(5)}`;
  }
  return sel;
}

const FLUTTER_BOOT_PROBE = `
window.addEventListener('dart-app-ready', () => console.log('PROBE: dart-app-ready event fired'));
let _f;
Object.defineProperty(window, '_flutter', {
  configurable: true, enumerable: true,
  get() { return _f; },
  set(v) {
    _f = v;
    const patchLoader = () => {
      if (_f.loader && _f.loader.didCreateEngineInitializer && !_f.loader.__patched) {
        const orig = _f.loader.didCreateEngineInitializer.bind(_f.loader);
        _f.loader.didCreateEngineInitializer = function(engineInitializer) {
          console.log('PROBE: didCreateEngineInitializer called');
          try {
            const origInit = engineInitializer.initializeEngine.bind(engineInitializer);
            engineInitializer.initializeEngine = function(...args) {
              console.log('PROBE: initializeEngine called');
              return origInit(...args).then(appRunner => {
                console.log('PROBE: initializeEngine RESOLVED');
                const origRun = appRunner.runApp.bind(appRunner);
                appRunner.runApp = function(...a2) {
                  console.log('PROBE: runApp called');
                  return origRun(...a2).then(r => { console.log('PROBE: runApp RESOLVED'); return r; })
                    .catch(e => { console.log('PROBE: runApp REJECTED: ' + e); throw e; });
                };
                return appRunner;
              }).catch(e => { console.log('PROBE: initializeEngine REJECTED: ' + e); throw e; });
            };
          } catch (e) { console.log('PROBE: patch error: ' + e); }
          return orig(engineInitializer);
        };
        _f.loader.__patched = true;
      }
    };
    patchLoader();
    if (_f && !_f.__loaderPatched) {
      _f.__loaderPatched = true;
      let _l = _f.loader;
      Object.defineProperty(_f, 'loader', {
        configurable: true,
        get() { return _l; },
        set(l) { _l = l; patchLoader(); },
      });
    }
  },
});
`;

async function ensureLaunched() {
  if (browser) return;
  browser = await chromium.launch({
    headless: true,
    args: [
      "--no-sandbox",
      "--use-gl=angle",
      "--use-angle=swiftshader-webgl",
      "--enable-webgl",
      "--enable-unsafe-swiftshader",
      "--ignore-gpu-blocklist",
      "--disable-gpu-sandbox",
    ],
  });
  page = await browser.newPage();
  page.on("console", msg => consoleLog.push({ type: msg.type(), text: msg.text() }));
  page.on("pageerror", err => consoleLog.push({ type: "pageerror", text: err.message }));
  page.on("crash", () => consoleLog.push({ type: "crash", text: "page crashed" }));
  page.on("requestfailed", req => netLog.push({ url: req.url(), status: "FAILED", error: req.failure()?.errorText }));
  page.on("response", res => netLog.push({ url: res.url(), status: res.status() }));
}

const COMMANDS = {
  async "probe-boot"() {
    await ensureLaunched();
    await page.addInitScript(FLUTTER_BOOT_PROBE);
    console.log("probe injected (effective on next nav)");
  },

  async nav(url) {
    await ensureLaunched();
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30_000 });
    console.log("nav →", url);
  },

  async "wait-for"(args) {
    if (!page) return console.log("ERROR: nav first");
    const [sel, timeoutMs] = args.split(/\s+/);
    try {
      await page.waitForSelector(resolveSelector(sel), { timeout: Number(timeoutMs) || 15_000 });
      console.log("found:", sel);
    } catch {
      console.log("TIMEOUT:", sel);
    }
  },

  async screenshot(name) {
    if (!page) return console.log("ERROR: nav first");
    const f = path.join(SHOT_DIR, (name || `ss-${consoleLog.length}-${Date.now()}`) + ".png");
    await page.screenshot({ path: f });
    fs.copyFileSync(f, path.join(SHOT_DIR, "screenshot.png"));
    console.log("screenshot:", f);
  },

  async "screenshot-element"(sel) {
    if (!page) return console.log("ERROR: nav first");
    const el = await page.$(resolveSelector(sel));
    if (!el) return console.log("NOT_FOUND:", sel);
    const f = path.join(SHOT_DIR, `el-${Date.now()}.png`);
    await el.screenshot({ path: f });
    console.log("screenshot:", f);
  },

  async click(sel) {
    if (!page) return console.log("ERROR: nav first");
    try {
      await page.click(resolveSelector(sel), { timeout: 10_000 });
      console.log("click", sel, "→ OK");
    } catch (e) {
      console.log("click", sel, "→ ERROR:", e.message);
    }
  },

  async "click-xy"(args) {
    if (!page) return console.log("ERROR: nav first");
    const [x, y] = args.split(/\s+/).map(Number);
    await page.mouse.click(x, y);
    console.log("click-xy", x, y, "→ OK");
  },

  async fill(args) {
    if (!page) return console.log("ERROR: nav first");
    const [sel, ...rest] = args.split(/\s+/);
    const value = rest.join(" ");
    try {
      await page.fill(sel, value, { timeout: 10_000 });
      console.log("fill", sel, "→ OK");
    } catch (e) {
      console.log("fill", sel, "→ ERROR:", e.message);
    }
  },

  async type(text) { if (page) await page.keyboard.type(text, { delay: 20 }); },
  async press(key) { if (page) await page.keyboard.press(key); },

  async console(flag) {
    const entries = flag === "--errors"
      ? consoleLog.filter(e => e.type === "error" || e.type === "pageerror")
      : consoleLog;
    if (!entries.length) return console.log("(aucun message)");
    for (const e of entries) console.log(`[${e.type}] ${e.text}`);
  },

  async eval(expr) {
    if (!page) return console.log("ERROR: nav first");
    try { console.log(JSON.stringify(await page.evaluate(expr))); }
    catch (e) { console.log("ERROR:", e.message); }
  },

  async text(sel) {
    if (!page) return console.log("ERROR: nav first");
    console.log(await page.evaluate(
      s => (s ? document.querySelector(s) : document.body)?.innerText ?? "(null)",
      sel || null,
    ));
  },

  async sleep(ms) { await new Promise(r => setTimeout(r, Number(ms) || 1000)); },

  async netcount() { console.log("requêtes:", netLog.length); },

  async network(flag) {
    const entries = flag === "--failed" ? netLog.filter(e => e.status === "FAILED" || e.status >= 400) : netLog;
    if (!entries.length) return console.log("(aucune requête)");
    for (const e of entries) console.log(e.status, e.url, e.error || "");
  },

  async quit() { if (browser) await browser.close().catch(() => {}); browser = null; page = null; },
  help() { console.log("commands:", Object.keys(COMMANDS).join(", ")); },
};

const rl = readline.createInterface({ input: process.stdin, output: process.stdout, prompt: "driver> " });

console.log("playwright driver — screenshots →", SHOT_DIR);
console.log('"help" for commands, "nav <url>" to start');
rl.prompt();

// for-await serializes command execution: each line's async handler runs to
// completion before the next line is pulled. A plain rl.on("line", async …)
// fires every queued line synchronously (readline doesn't await listeners),
// so piped scripts (heredocs) race — e.g. "wait-for" running before "nav"'s
// browser launch resolves.
for await (const line of rl) {
  const trimmed = line.trim();
  if (!trimmed) { rl.prompt(); continue; }
  const spaceIdx = trimmed.indexOf(" ");
  const cmd = spaceIdx === -1 ? trimmed : trimmed.slice(0, spaceIdx);
  const rest = spaceIdx === -1 ? "" : trimmed.slice(spaceIdx + 1);
  const fn = COMMANDS[cmd];
  if (!fn) { console.log("unknown:", cmd, "— try: help"); rl.prompt(); continue; }
  try { await fn(rest); } catch (e) { console.log("ERROR:", e.message); }
  if (cmd === "quit") break;
  rl.prompt();
}
await COMMANDS.quit();
process.exit(0);
