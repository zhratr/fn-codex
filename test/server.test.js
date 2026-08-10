const assert = require("node:assert/strict");
const { execFile } = require("node:child_process");
const fsp = require("node:fs").promises;
const os = require("node:os");
const path = require("node:path");
const { promisify } = require("node:util");

const execFileAsync = promisify(execFile);
const root = path.resolve(__dirname, "..");
const port = 31277;

async function main() {
  const workspace = await fsp.mkdtemp(path.join(os.tmpdir(), "fn-codex-test-"));
  await fsp.writeFile(path.join(workspace, "hello.txt"), "hello fn-codex\n");
  const child = execFile("node", [path.join(root, "app/server/server.js")], {
    cwd: root,
    env: { ...process.env, FN_CODEX_PORT: String(port), FN_CODEX_BIND: "127.0.0.1", FN_CODEX_WORKSPACE: workspace, FN_CODEX_STATE_DIR: path.join(workspace, ".state"), FN_CODEX_ALLOW_COMMANDS: "1" },
  });
  let output = "";
  child.stdout.on("data", (chunk) => { output += chunk; });
  child.stderr.on("data", (chunk) => { output += chunk; });
  for (let attempt = 0; attempt < 40 && !output.includes("listening"); attempt += 1) await new Promise((resolve) => setTimeout(resolve, 50));
  assert.match(output, /listening/);
  const base = `http://127.0.0.1:${port}`;
  const get = async (url) => (await fetch(`${base}${url}`)).json();
  const state = await get("/api/state");
  assert.equal(state.workspace, await fsp.realpath(workspace));
  const files = await get("/api/files");
  assert.ok(files.entries.some((entry) => entry.path === "hello.txt"));
  const file = await get("/api/file?path=hello.txt");
  assert.equal(file.content, "hello fn-codex\n");
  const traversal = await fetch(`${base}/api/file?path=../etc/passwd`);
  assert.equal(traversal.status, 400);
  const task = await (await fetch(`${base}/api/tasks`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ title: "Test task" }) })).json();
  assert.equal(task.title, "Test task");
  const answer = await (await fetch(`${base}/api/tasks/${task.id}/messages`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ message: "hello" }) })).json();
  assert.equal(answer.answer.mode, "local-preview");
  const run = await (await fetch(`${base}/api/run`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ command: "pwd" }) })).json();
  assert.equal(run.code, 0);
  child.kill("SIGTERM");
  console.log("server checks passed");
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
