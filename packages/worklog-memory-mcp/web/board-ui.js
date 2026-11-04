const $ = id => document.getElementById(id);
const statusLabels = { draft: "Draft", ready: "Ready", "in-progress": "In progress", "in-review": "In review", blocked: "Blocked", shipping: "Shipping", archived: "Done" };
const columns = [
  { id: "todo", title: "To do", states: ["draft", "ready"], target: "ready" },
  { id: "in-progress", title: "In progress", states: ["in-progress"], target: "in-progress" },
  { id: "review", title: "Review", states: ["in-review", "shipping"], target: "in-review" },
  { id: "blocked", title: "Blocked", states: ["blocked"], target: "blocked" },
  { id: "done", title: "Done", states: ["archived"], target: "archived" },
];
let data, project = "", selected, busy = false, refreshId = 0, returnFocus;
const sessionKey = "worklog-board-session";
const session = sessionStorage.getItem(sessionKey) || `board-${crypto.randomUUID()}`;
sessionStorage.setItem(sessionKey, session);
function node(tag, className, text) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text !== undefined) element.textContent = text;
  return element;
}
function notice(message) { $("notice").textContent = message || ""; $("notice").hidden = !message; }
async function json(url, options) {
  const response = await fetch(url, options);
  const value = await response.json();
  if (!response.ok) throw new Error(value.error || value.content?.map(c => c.text || "").join("\n") || "The update failed. Refresh and try again.");
  return value;
}
async function refresh() {
  const id = ++refreshId;
  try {
    const next = await json("/api/state");
    if (id !== refreshId) return;
    const changed = !data || JSON.stringify(data.tasks) !== JSON.stringify(next.tasks) || data.archived_total !== next.archived_total;
    data = next;
    $("vault").textContent = data.vault;
    $("namespace").textContent = data.namespace;
    $("sync-state").textContent = "Up to date";
    $("board").setAttribute("aria-busy", "false");
    if (changed) render();
  } catch {
    $("sync-state").textContent = "Connection lost";
    notice("The board is unavailable. Run worklog-board to reconnect, then refresh this page.");
  }
}
function render() {
  const focusedSlug = document.activeElement?.dataset.slug;
  const focusedProject = document.activeElement?.dataset.project;
  const scrollLeft = $("board").scrollLeft;
  const needle = $("search").value.trim().toLowerCase();
  const filtered = data.tasks.filter(t => (!project || t.project === project) && (!needle || `${t.title} ${t.slug} ${t.next_action} ${t.project}`.toLowerCase().includes(needle)));
  $("total").textContent = filtered.filter(t => !t.archived).length;
  $("no-results").hidden = filtered.length > 0 || (!needle && !project);
  $("archive-note").textContent = data.archived_total > 50 ? `Showing the latest 50 of ${data.archived_total} completed tasks` : "";
  const projects = [...new Set(data.tasks.map(t => t.project).filter(p => p && p !== "none"))].sort();
  $("mobile-project").replaceChildren(...["", ...projects].map(value => {
    const option = node("option", "", value ? value.replaceAll("-", " ") : "All tasks");
    option.value = value;
    return option;
  }));
  $("mobile-project").value = project;
  $("projects").replaceChildren();
  for (const value of ["", ...projects]) {
    const button = node("button", `project${project === value ? " active" : ""}`);
    button.dataset.project = value;
    button.append(node("span", "", value ? value.replaceAll("-", " ") : "All tasks"));
    button.append(node("span", "count", data.tasks.filter(t => !t.archived && (!value || t.project === value)).length));
    button.addEventListener("click", () => { project = value; render(); });
    $("projects").append(button);
  }
  $("board").replaceChildren();
  for (const column of columns) {
    const section = node("section", `column ${column.id}`);
    section.setAttribute("aria-label", column.title);
    const header = node("div", "column-header");
    const title = node("h2", "column-title");
    title.append(node("span", "status-dot"), document.createTextNode(column.title));
    const tasks = filtered.filter(t => column.states.includes(t.status));
    header.append(title, node("span", "column-count", tasks.length));
    const cards = node("div", "cards");
    for (const task of tasks) {
      const card = node("button", "card");
      card.type = "button";
      card.draggable = !task.archived;
      card.dataset.slug = task.slug;
      card.setAttribute("aria-label", `${task.title}, ${statusLabels[task.status]}`);
      card.append(node("strong", "card-title", task.title));
      if (task.next_action) card.append(node("span", "card-next", task.next_action));
      const footer = node("span", "card-footer");
      const label = task.claim?.session_id ? "Agent working" : task.status === "shipping" ? "Shipping" : task.project !== "none" ? task.project.replaceAll("-", " ") : task.kind;
      footer.append(node("span", `tag${task.claim?.session_id ? " claimed" : task.status === "shipping" ? " shipping" : ""}`, label));
      footer.append(node("time", "card-date", task.updated));
      card.append(footer);
      card.addEventListener("click", () => openTask(task.slug));
      card.addEventListener("dragstart", event => { event.dataTransfer.setData("text/plain", task.slug); event.dataTransfer.effectAllowed = "move"; card.classList.add("dragging"); });
      card.addEventListener("dragend", () => card.classList.remove("dragging"));
      cards.append(card);
    }
    if (!tasks.length) cards.append(node("div", "column-empty", column.id === "todo" && !data.tasks.length ? "No tasks yet. Add your first task above." : "Drop a task here"));
    section.append(header, cards);
    section.addEventListener("dragover", event => { event.preventDefault(); section.classList.add("drag-over"); });
    section.addEventListener("dragleave", event => { if (!section.contains(event.relatedTarget)) section.classList.remove("drag-over"); });
    section.addEventListener("drop", async event => {
      event.preventDefault(); section.classList.remove("drag-over");
      const slug = event.dataTransfer.getData("text/plain");
      if (!data.tasks.some(t => t.slug === slug && !t.archived)) return;
      await mutate("memory_update_status", { slug, status: column.target, session_id: session });
    });
    $("board").append(section);
  }
  $("board").scrollLeft = scrollLeft;
  if (focusedSlug !== undefined || focusedProject !== undefined) {
    const target = [...document.querySelectorAll("button[data-slug], button[data-project]")].find(b =>
      focusedSlug !== undefined ? b.dataset.slug === focusedSlug : b.dataset.project === focusedProject);
    target?.focus({ preventScroll: true });
  }
}
async function mutate(name, args) {
  if (busy || !data) return false;
  busy = true; refreshId++;
  document.querySelectorAll("form button").forEach(b => { b.disabled = true; });
  $("sync-state").textContent = "Saving…";
  notice("");
  let saved = false;
  try {
    await json("/api/tool", { method: "POST", headers: { "Content-Type": "application/json", "X-Worklog-Token": data.token }, body: JSON.stringify({ name, arguments: args }) });
    saved = true;
  } catch (error) { notice(error.message.slice(0, 700)); }
  finally {
    busy = false;
    document.querySelectorAll("form button").forEach(b => { b.disabled = false; });
    await refresh();
    if (selected) await openTask(selected, false);
  }
  return saved;
}
async function openTask(slug, focus = true) {
  try {
    if (focus) returnFocus = document.activeElement;
    const task = await json(`/api/task?slug=${encodeURIComponent(slug)}`);
    selected = slug;
    $("detail").hidden = false;
    $("create-form").hidden = true;
    $("edit-form").hidden = false;
    $("detail-id").textContent = task.slug;
    $("detail-title").textContent = task.title;
    $("task-status").replaceChildren(...Object.entries(statusLabels).map(([value, text]) => { const o = node("option", "", text); o.value = value; return o; }));
    $("task-status").value = task.status;
    $("task-next").value = task.next_action;
    $("task-body").textContent = task.body;
    $("task-owner").textContent = task.archived ? "Completed tasks are archived." : task.claim?.session_id ? `Claimed by ${task.claim.session_id}. Only that session can update this task.` : "Changes are shared with your agents.";
    for (const id of ["task-status", "task-next", "save-task"]) $(id).disabled = task.archived;
    if (focus) (task.archived ? $("close-detail") : $("task-status")).focus();
  } catch (error) { notice(error.message); }
}
function closeDetail() {
  if ($("detail").hidden) return;
  $("detail").hidden = true; selected = null;
  const slug = returnFocus?.dataset.slug;
  const target = slug ? [...document.querySelectorAll("button[data-slug]")].find(b => b.dataset.slug === slug) : returnFocus;
  (target?.isConnected ? target : $("new-task")).focus({ preventScroll: true });
}
$("new-task").addEventListener("click", () => {
  returnFocus = $("new-task");
  selected = null; $("detail").hidden = false; $("edit-form").hidden = true; $("create-form").hidden = false;
  $("detail-id").textContent = "New task"; $("detail-title").textContent = "New task";
  $("create-form").reset(); $("create-title").focus();
});
$("close-detail").addEventListener("click", closeDetail);
document.addEventListener("keydown", event => { if (event.key === "Escape") closeDetail(); });
$("search").addEventListener("input", () => data && render());
$("mobile-project").addEventListener("change", event => { project = event.target.value; render(); });
$("refresh").addEventListener("click", () => { notice(""); refresh(); });
$("clear-filters").addEventListener("click", () => { project = ""; $("search").value = ""; render(); });
$("edit-form").addEventListener("submit", async event => {
  event.preventDefault();
  await mutate("memory_update_status", { slug: selected, status: $("task-status").value, next_action: $("task-next").value, session_id: session });
});
$("create-form").addEventListener("submit", async event => {
  event.preventDefault();
  const title = $("create-title").value.trim();
  const prefix = title.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 65) || "task";
  const slug = `${prefix}-${crypto.randomUUID().slice(0, 6)}`;
  const saved = await mutate("memory_task_create", { slug, kind: "impl", context: `${title}\n\n${$("create-body").value.trim()}`, next_action: $("create-next").value.trim() || "Start this task." });
  if (saved) await openTask(slug);
});
refresh();
setInterval(() => { if (!document.hidden && !busy) refresh(); }, 3000);
