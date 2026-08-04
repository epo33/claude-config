// Sert un build web statique (Flutter build/web) et relaie les appels API
// vers un backend séparé, pour simuler le reverse-proxy de production sans
// toucher au code de l'application.
import * as http from "node:http";
import * as fs from "node:fs";
import * as path from "node:path";

const STATIC_DIR = path.resolve(process.argv[2]);
const PORT = Number(process.argv[3] || 8767);
const BACKEND_PREFIX = process.argv[4] || "/deployment";
const BACKEND_TARGET = process.argv[5] || "http://localhost:8282";

const MIME = {
  ".html": "text/html", ".js": "application/javascript", ".json": "application/json",
  ".css": "text/css", ".png": "image/png", ".svg": "image/svg+xml", ".wasm": "application/wasm",
  ".ico": "image/x-icon", ".ttf": "font/ttf", ".otf": "font/otf",
};

function proxy(req, res) {
  const target = new URL(req.url, BACKEND_TARGET);
  const upstream = http.request(target, { method: req.method, headers: req.headers }, upRes => {
    res.writeHead(upRes.statusCode, upRes.headers);
    upRes.pipe(res);
  });
  upstream.on("error", err => { res.writeHead(502); res.end("proxy error: " + err.message); });
  req.pipe(upstream);
}

function serveStatic(req, res) {
  let urlPath = decodeURIComponent(req.url.split("?")[0]);
  if (urlPath === "/") urlPath = "/index.html";
  let filePath = path.join(STATIC_DIR, urlPath);
  if (!filePath.startsWith(STATIC_DIR)) { res.writeHead(403); res.end(); return; }
  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(404); res.end("not found: " + urlPath); return; }
    res.writeHead(200, { "Content-Type": MIME[path.extname(filePath)] || "application/octet-stream" });
    res.end(data);
  });
}

http.createServer((req, res) => {
  if (req.url.startsWith(BACKEND_PREFIX)) proxy(req, res);
  else serveStatic(req, res);
}).listen(PORT, () => console.log(`static-proxy: http://localhost:${PORT} (static=${STATIC_DIR}, backend=${BACKEND_TARGET}${BACKEND_PREFIX})`));
