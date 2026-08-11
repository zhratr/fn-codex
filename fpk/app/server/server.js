#!/usr/bin/env node

const http = require("node:http");
const fs = require("node:fs");
const fsp = fs.promises;
const path = require("node:path");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");

const execFileAsync = promisify(execFile);
const PORT = Number.parseInt(process.env.FN_CODEX_PORT || process.env.PORT || "3010", 10);
const BIND = process.env.FN_CODEX_BIND || "127.0.0.1";
const APP_ROOT = path.resolve(__dirname, "..");
const CONFIGURED_WORKSPACE = path.resolve(process.env.FN_CODEX_WORKSPACE || path.join(process.env.TRIM_APPHOME || APP_ROOT, "workspace"));
let WORKSPACE = CONFIGURED_WORKSPACE;
const STATE_DIR = path.resolve(process.env.FN_CODEX_STATE_DIR || process.env.TRIM_APPDATA || path.join(APP_ROOT, "state"));
const STATE_FILE = path.join(STATE_DIR, "state.json");
const STATIC_ROOT = fs.existsSync(path.join(APP_ROOT, "ui")) ? path.join(APP_ROOT, "ui") : path.join(__dirname, "ui");
const MAX_BODY = 1024 * 1024;
const MAX_FILE = 512 * 1024;
const MAX_OUTPUT = 64 * 1024;

const tasks = new Map();

function json(res, status, value) {
  const body = JSON.stringify(value);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store",
  });
  res.end(body);
}

function text(res, status, value, contentType = "text/plain; charset=utf-8") {
  res.writeHead(status, {
    "Content-Type": contentType,
    "Content-Length": Buffer.byteLength(value),
    "Cache-Control": "no-store",
  });
  res.end(value);
}

function fail(res, status, message) {
  json(res, status, { error: message });
}

function id() {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

function withinWorkspace(relative = "") {
  if (typeof relative !== "string" || relative.includes("\0")) throw new Error("Invalid workspace path");
  const normalized = relative.replaceAll("\\", "/");
  if (normalized.startsWith("/") || normalized.split("/").includes("..")) throw new Error("Path must stay inside the configured workspace");
  const candidate = path.resolve(WORKSPACE, normalized || ".");
  if (candidate !== WORKSPACE && !candidate.startsWith(`${WORKSPACE}${path.sep}`)) throw new Error("Path must stay inside the configured workspace");
  return candidate;
}

async function existingWorkspacePath(relative = "") {
  const candidate = withinWorkspace(relative);
  const real = await fsp.realpath(candidate);
  if (real !== WORKSPACE && !real.startsWith(`${WORKSPACE}${path.sep}`)) throw new Error("Symlink escapes are not allowed");
  return real;
}

async function readBody(req) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY) throw new Error("Request body is too large");
    chunks.push(chunk);
  }
  if (!chunks.length) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new Error("Request body must be JSON");
  }
}

async function loadState() {
  await fsp.mkdir(CONFIGURED_WORKSPACE, { recursive: true });
  WORKSPACE = await fsp.realpath(CONFIGURED_WORKSPACE);
  await fsp.mkdir(STATE_DIR, { recursive: true });
  try {
    const saved = JSON.parse(await fsp.readFile(STATE_FILE, "utf8"));
    for (const task of saved.tasks || []) tasks.set(task.id, task);
  } catch (error) {
    if (error.code !== "ENOENT") console.warn(`[fn-codex] state was not loaded: ${error.message}`);
  }
}

let saveTimer;
function saveState() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(async () => {
    try {
      await fsp.writeFile(STATE_FILE, JSON.stringify({ tasks: [...tasks.values()].slice(-50) }, null, 2));
    } catch (error) {
      console.warn(`[fn-codex] state was not saved: ${error.message}`);
    }
  }, 100);
}

async function fileTree(relative = "") {
  const root = await existingWorkspacePath(relative);
  const entries = await fsp.readdir(root, { withFileTypes: true });
  const result = [];
  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    if (entry.name === ".git" || entry.name === "node_modules") continue;
    const childRelative = path.relative(WORKSPACE, path.join(root, entry.name)).replaceAll(path.sep, "/");
    if (entry.isDirectory()) {
      result.push({ name: entry.name, path: childRelative, kind: "directory" });
    } else if (entry.isFile()) {
      const stat = await fsp.stat(path.join(root, entry.name));
      result.push({ name: entry.name, path: childRelative, kind: "file", size: stat.size });
    }
  }
  return result;
}

async function gitDiff() {
  try {
    const result = await execFileAsync("git", ["-C", WORKSPACE, "diff", "--no-ext-diff", "--unified=3"], { timeout: 5000, maxBuffer: MAX_OUTPUT * 2 });
    return result.stdout.slice(0, MAX_OUTPUT);
  } catch {
    return "";
  }
}

function parseCommand(command) {
  if (typeof command !== "string" || !command.trim()) throw new Error("Command is required");
  if (command.length > 1000 || /[;&|<>`\n\r]|\$\(|\$\{/.test(command)) throw new Error("Only a single, non-shell command is allowed");
  const pieces = command.match(/(?:[^\s"']+|"[^"]*"|'[^']*')+/g) || [];
  const args = pieces.map((piece) => piece.replace(/^['"]|['"]$/g, ""));
  const allowed = new Set(["cat", "echo", "find", "git", "head", "ls", "make", "node", "npm", "npx", "python", "python3", "pwd", "rg", "sed", "sort", "tail", "wc"]);
  if (!allowed.has(args[0]) || args[0].includes("/")) throw new Error(`Command '${args[0] || ""}' is not enabled by the local command policy`);
  return args;
}

async function runCommand(command, relativeCwd = "") {
  if (process.env.FN_CODEX_ALLOW_COMMANDS === "0") throw new Error("Command execution is disabled; set FN_CODEX_ALLOW_COMMANDS=1 to enable it");
  const args = parseCommand(command);
  const cwd = await existingWorkspacePath(relativeCwd);
  const env = {
    PATH: process.env.PATH || "/usr/bin:/bin",
    HOME: path.join(WORKSPACE, ".fn-codex-home"),
    TMPDIR: path.join(WORKSPACE, ".fn-codex-tmp"),
    LANG: "C.UTF-8",
  };
  await fsp.mkdir(env.HOME, { recursive: true });
  await fsp.mkdir(env.TMPDIR, { recursive: true });
  try {
    const result = await execFileAsync(args[0], args.slice(1), { cwd, env, timeout: 120000, maxBuffer: MAX_OUTPUT });
    return { command, cwd: path.relative(WORKSPACE, cwd) || ".", code: 0, output: `${result.stdout}${result.stderr}`.slice(0, MAX_OUTPUT) };
  } catch (error) {
    return { command, cwd: path.relative(WORKSPACE, cwd) || ".", code: error.code || 1, output: `${error.stdout || ""}${error.stderr || error.message}`.slice(0, MAX_OUTPUT) };
  }
}

function providerConfig() {
  return {
    configured: Boolean(process.env.CODEX_API_URL),
    model: process.env.CODEX_MODEL || "not configured",
  };
}

async function askProvider(messages) {
  if (!process.env.CODEX_API_URL) {
    return {
      mode: "local-preview",
      content: "No agent provider is configured. fn-codex is ready as a local workspace preview. Set CODEX_API_URL and CODEX_API_KEY in the service environment to connect an OpenAI-compatible agent; credentials are never stored by this app.",
    };
  }
  const baseUrl = process.env.CODEX_API_URL.replace(/\/$/, "");
  const endpoint = baseUrl.endsWith("/chat/completions")
    ? baseUrl
    : `${baseUrl}${baseUrl.endsWith("/v1") ? "" : "/v1"}/chat/completions`;
  const headers = { "Content-Type": "application/json" };
  if (process.env.CODEX_API_KEY) headers.Authorization = `Bearer ${process.env.CODEX_API_KEY}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 90000);
  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers,
      body: JSON.stringify({ model: process.env.CODEX_MODEL || "codex", messages, stream: false }),
      signal: controller.signal,
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error?.message || `Provider returned HTTP ${response.status}`);
    const content = payload.choices?.[0]?.message?.content;
    if (typeof content !== "string") throw new Error("Provider response did not contain message content");
    return { mode: "provider", content };
  } finally {
    clearTimeout(timer);
  }
}

async function chat(task, message) {
  const context = `Workspace: ${WORKSPACE}\nSelected path: ${task.selectedPath || "."}\nRecent diff:\n${(await gitDiff()).slice(0, 12000) || "(clean or not a git workspace)"}`;
  task.messages.push({ role: "user", content: message, createdAt: new Date().toISOString() });
  const answer = await askProvider([{ role: "system", content: "You are a coding agent in the community fn-codex browser workspace. Stay within the configured workspace and explain proposed changes clearly." }, { role: "user", content: `${context}\n\n${message}` }]);
  task.messages.push({ role: "assistant", content: answer.content, mode: answer.mode, createdAt: new Date().toISOString() });
  task.updatedAt = new Date().toISOString();
  saveState();
  return answer;
}

async function serveStatic(res, pathname) {
  let decoded;
  try { decoded = decodeURIComponent(pathname); } catch { return fail(res, 400, "Invalid URL"); }
  const relative = decoded === "/" ? "index.html" : decoded.replace(/^\//, "");
  if (!relative || relative.includes("..")) return fail(res, 400, "Invalid asset path");
  const file = path.resolve(STATIC_ROOT, relative);
  if (file !== STATIC_ROOT && !file.startsWith(`${STATIC_ROOT}${path.sep}`)) return fail(res, 400, "Invalid asset path");
  try {
    const data = await fsp.readFile(file);
    const type = { ".css": "text/css; charset=utf-8", ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".json": "application/json; charset=utf-8", ".svg": "image/svg+xml" }[path.extname(file)] || "application/octet-stream";
    res.writeHead(200, { "Content-Type": type, "Content-Length": data.length, "Cache-Control": "no-cache" });
    res.end(data);
  } catch (error) {
    if (error.code === "ENOENT") return fail(res, 404, "Not found");
    fail(res, 500, "Asset could not be read");
  }
}

async function handler(req, res) {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  try {
    if (req.method === "GET" && url.pathname === "/api/state") {
      return json(res, 200, { app: "fn-codex", version: "0.1.5", workspace: WORKSPACE, provider: providerConfig(), tasks: [...tasks.values()], diff: await gitDiff() });
    }
    if (req.method === "GET" && url.pathname === "/api/files") return json(res, 200, { path: url.searchParams.get("path") || ".", entries: await fileTree(url.searchParams.get("path") || "") });
    if (req.method === "GET" && url.pathname === "/api/file") {
      const relative = url.searchParams.get("path") || "";
      const file = await existingWorkspacePath(relative);
      const stat = await fsp.stat(file);
      if (!stat.isFile()) return fail(res, 400, "A file path is required");
      if (stat.size > MAX_FILE) return fail(res, 413, "File is larger than the preview limit");
      return json(res, 200, { path: relative, content: await fsp.readFile(file, "utf8") });
    }
    if (req.method === "POST" && url.pathname === "/api/tasks") {
      const body = await readBody(req);
      const now = new Date().toISOString();
      const task = { id: id(), title: String(body.title || "Untitled task").slice(0, 120), selectedPath: "", messages: [], createdAt: now, updatedAt: now };
      tasks.set(task.id, task); saveState(); return json(res, 201, task);
    }
    const messageMatch = url.pathname.match(/^\/api\/tasks\/([^/]+)\/messages$/);
    if (req.method === "POST" && messageMatch) {
      const task = tasks.get(messageMatch[1]); if (!task) return fail(res, 404, "Task not found");
      const body = await readBody(req); const answer = await chat(task, String(body.message || "").slice(0, 12000)); return json(res, 200, { task, answer });
    }
    const selectMatch = url.pathname.match(/^\/api\/tasks\/([^/]+)\/selection$/);
    if (req.method === "POST" && selectMatch) {
      const task = tasks.get(selectMatch[1]); if (!task) return fail(res, 404, "Task not found");
      const body = await readBody(req); await existingWorkspacePath(String(body.path || "")); task.selectedPath = String(body.path || ""); task.updatedAt = new Date().toISOString(); saveState(); return json(res, 200, task);
    }
    if (req.method === "POST" && url.pathname === "/api/run") {
      const body = await readBody(req); return json(res, 200, await runCommand(body.command, body.cwd || ""));
    }
    return serveStatic(res, url.pathname);
  } catch (error) {
    return fail(res, 400, error.message || "Request failed");
  }
}

async function main() {
  await loadState();
  const server = http.createServer((req, res) => handler(req, res));
  server.listen(PORT, BIND, () => console.log(`[fn-codex] community workspace listening at http://${BIND}:${PORT}; workspace=${WORKSPACE}`));
  const shutdown = () => server.close(() => process.exit(0));
  process.on("SIGTERM", shutdown); process.on("SIGINT", shutdown);
}

main().catch((error) => { console.error(error); process.exit(1); });
