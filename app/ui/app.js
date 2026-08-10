const el = (id) => document.getElementById(id);
const state = { tasks: [], current: null, path: "" };

async function api(path, options = {}) {
  const response = await fetch(path, { headers: { "Content-Type": "application/json" }, ...options });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error || "Request failed");
  return payload;
}

function toast(message) { const node = el("toast"); node.textContent = message; node.classList.add("show"); setTimeout(() => node.classList.remove("show"), 2600); }

function renderTasks() {
  el("tasks").innerHTML = state.tasks.length ? state.tasks.map((task) => `<button class="task ${state.current?.id === task.id ? "selected" : ""}" data-task="${task.id}"><span class="task-title">${escapeHtml(task.title)}</span><span class="task-time">${new Date(task.updatedAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</span></button>`).join("") : `<div class="muted" style="padding:9px">No tasks yet</div>`;
  document.querySelectorAll("[data-task]").forEach((node) => node.addEventListener("click", () => selectTask(node.dataset.task)));
}

function renderMessages() {
  if (!state.current) { el("messages").innerHTML = `<div class="empty-state"><div class="empty-glyph">✦</div><h2>A browser-first coding workspace for fnOS</h2><p>Choose a task or start a new one. This community implementation keeps the workspace, files, terminal output, and change preview together in one local interface.</p><p class="small-note">It is not an official OpenAI desktop application.</p></div>`; return; }
  el("taskTitle").textContent = state.current.title; el("taskId").textContent = state.current.id; el("messages").innerHTML = state.current.messages.length ? state.current.messages.map((message) => `<article class="message ${message.role}"><div class="message-meta">${message.role === "assistant" ? "fn-codex" : "you"}${message.mode ? ` · ${message.mode}` : ""}</div>${escapeHtml(message.content)}</article>`).join("") : `<div class="empty-state" style="margin-top:12vh"><div class="empty-glyph">↗</div><h2>What should we work on?</h2><p>Describe a task, ask about a file, or use the run panel to inspect the configured workspace.</p></div>`;
  el("messages").scrollTop = el("messages").scrollHeight;
}

async function selectTask(taskId) { state.current = state.tasks.find((task) => task.id === taskId) || null; renderTasks(); renderMessages(); }

async function refresh() {
  try {
    const data = await api("/api/state"); state.tasks = data.tasks || []; state.current = state.current ? state.tasks.find((task) => task.id === state.current.id) : state.tasks.at(-1) || null;
    el("workspaceName").textContent = data.workspace.split("/").at(-1) || data.workspace; el("providerStatus").textContent = data.provider.configured ? `provider · ${data.provider.model}` : "local preview · provider off"; el("diff").textContent = data.diff || "No local changes detected."; el("diffCount").textContent = data.diff ? "modified" : "clean"; renderTasks(); renderMessages(); await loadFiles(state.path);
  } catch (error) { toast(error.message); }
}

async function loadFiles(relative = "") { state.path = relative; const data = await api(`/api/files?path=${encodeURIComponent(relative)}`); el("pathCrumb").textContent = `/${relative}`; el("files").innerHTML = data.entries.length ? data.entries.map((entry) => `<div class="file-row ${entry.kind === "directory" ? "dir" : ""}" data-path="${escapeAttr(entry.path)}" data-kind="${entry.kind}"><span class="file-icon">${entry.kind === "directory" ? "▸" : "·"}</span><span class="file-name">${escapeHtml(entry.name)}</span></div>`).join("") : `<div class="muted" style="padding:7px 5px">Empty directory</div>`; document.querySelectorAll(".file-row").forEach((node) => node.addEventListener("click", () => node.dataset.kind === "directory" ? loadFiles(node.dataset.path) : openFile(node.dataset.path))); }

async function openFile(relative) { try { const file = await api(`/api/file?path=${encodeURIComponent(relative)}`); if (state.current) { state.current = await api(`/api/tasks/${state.current.id}/selection`, { method: "POST", body: JSON.stringify({ path: relative }) }); state.tasks = state.tasks.map((task) => task.id === state.current.id ? state.current : task); renderTasks(); } el("message").value = `Please inspect ${relative}.\n\n${file.content.slice(0, 4000)}`; toast(`Loaded ${relative} into the composer`); } catch (error) { toast(error.message); } }

function escapeHtml(value) { return String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#039;" })[char]); }
function escapeAttr(value) { return escapeHtml(value).replace(/`/g, "&#096;"); }

el("newTask").addEventListener("click", async () => { const title = prompt("Task name", "Explore the workspace"); if (!title) return; state.current = await api("/api/tasks", { method: "POST", body: JSON.stringify({ title }) }); state.tasks.push(state.current); renderTasks(); renderMessages(); });
el("refresh").addEventListener("click", refresh);
el("upDir").addEventListener("click", () => loadFiles(state.path.includes("/") ? state.path.split("/").slice(0, -1).join("/") : ""));
el("clearOutput").addEventListener("click", () => { el("runOutput").textContent = ""; });
el("chatForm").addEventListener("submit", async (event) => { event.preventDefault(); const message = el("message").value.trim(); if (!message) return; if (!state.current) { state.current = await api("/api/tasks", { method: "POST", body: JSON.stringify({ title: message.slice(0, 54) }) }); state.tasks.push(state.current); } el("message").value = ""; renderMessages(); try { const result = await api(`/api/tasks/${state.current.id}/messages`, { method: "POST", body: JSON.stringify({ message }) }); state.current = result.task; state.tasks = state.tasks.map((task) => task.id === state.current.id ? state.current : task); renderTasks(); renderMessages(); } catch (error) { toast(error.message); } });
el("runForm").addEventListener("submit", async (event) => { event.preventDefault(); el("runOutput").textContent = "running…"; try { const result = await api("/api/run", { method: "POST", body: JSON.stringify({ command: el("command").value, cwd: state.path }) }); el("runOutput").textContent = `$ ${result.command}\n\n${result.output || `(exit ${result.code})`}`; } catch (error) { el("runOutput").textContent = error.message; } });
el("message").addEventListener("keydown", (event) => { if ((event.metaKey || event.ctrlKey) && event.key === "Enter") { event.preventDefault(); el("chatForm").requestSubmit(); } });
el("command").addEventListener("keydown", (event) => { if (event.key === "Enter") { event.preventDefault(); el("runForm").requestSubmit(); } });
refresh();
