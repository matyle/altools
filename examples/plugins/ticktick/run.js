#!/usr/bin/osascript -l JavaScript
// Altools plugin: TickTick / 滴答清单 through its Open API. Plain JavaScript for macOS's own
// osascript, so it needs nothing installed. Contract: PLUGINS.md; setup: README.md.
ObjC.import("Foundation")
ObjC.import("stdlib")

const env = $.NSProcessInfo.processInfo.environment
const getenv = key => { const v = ObjC.unwrap(env.objectForKey(key)); return v == null ? "" : String(v) }
const app = Application.currentApplication()
app.includeStandardAdditions = true

const zh = getenv("ALTOOLS_LANG") === "zh"
const t = (en, cn) => zh ? cn : en
const EVENT = getenv("ALTOOLS_EVENT") || "refresh"
const INPUT = getenv("ALTOOLS_INPUT")
const DATA = getenv("ALTOOLS_DATA_DIR") || "/tmp"
const REGION = getenv("ALTOOLS_SETTING_REGION") || "dida365.com"
const CLIENT_ID = getenv("ALTOOLS_SETTING_CLIENT_ID").trim()
const CLIENT_SECRET = getenv("ALTOOLS_SETTING_CLIENT_SECRET").trim()
const ALERTS = getenv("ALTOOLS_SETTING_ALERTS") !== "0"
const MENUBAR = getenv("ALTOOLS_SETTING_MENUBAR") === "1"
const API = getenv("TICKTICK_API_BASE") || `https://api.${REGION}/open/v1`
const WEB = `https://${REGION}/webapp`
const REDIRECT_PORT = 8765
const REDIRECT = `http://localhost:${REDIRECT_PORT}/callback`
// Tokens from Connect live in the login Keychain, one per service.
const KEYCHAIN_SERVICE = "Altools TickTick " + REGION

const sh = cmd => { try { return app.doShellScript(cmd, { alteringLineEndings: false }).replace(/\n$/, "") } catch (e) { return "" } }
const q = s => "'" + String(s).replace(/'/g, "'\\''") + "'"
const warn = text => $.NSFileHandle.fileHandleWithStandardError.writeData($(text + "\n").dataUsingEncoding($.NSUTF8StringEncoding))
const emit = value => {
  $.NSFileHandle.fileHandleWithStandardOutput.writeData($(JSON.stringify(value) + "\n").dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(0)
}
const readJSON = path => { try { return JSON.parse(sh("/bin/cat " + q(path))) } catch (e) { return null } }
const writeJSON = (path, value) => sh("/usr/bin/printf %s " + q(JSON.stringify(value)) + " > " + q(path))
const CACHE = DATA + "/tasks.json"

const storedToken = () => sh(`/usr/bin/security find-generic-password -s ${q(KEYCHAIN_SERVICE)} -a token -w`).trim()
const TOKEN = getenv("ALTOOLS_SETTING_TOKEN").trim() || getenv("TICKTICK_TOKEN") || storedToken()

class HTTPError extends Error {
  constructor(status, body) { super(status ? `HTTP ${status}: ${body.slice(0, 200)}` : "can't reach " + API); this.status = status }
}

// curl honours the HTTP(S)_PROXY Altools passes. The status code comes back on the last line.
function call(method, path, body) {
  let cmd = `/usr/bin/curl -s -m 15 -X ${method} -H ${q("Authorization: Bearer " + TOKEN)} -w '\\n%{http_code}'`
  if (body !== undefined) cmd += ` -H 'Content-Type: application/json' --data-binary ${q(JSON.stringify(body))}`
  const out = sh(cmd + " " + q(API + path))
  const cut = out.lastIndexOf("\n")
  const status = Number(out.slice(cut + 1)) || 0
  const text = cut >= 0 ? out.slice(0, cut) : ""
  if (status < 200 || status >= 300) throw new HTTPError(status, text)
  return text ? JSON.parse(text) : null
}

// MARK: Data

function fetchAll() {
  const projects = [{ id: "inbox", name: t("Inbox", "收集箱") }].concat((call("GET", "/project") || []).filter(p => !p.closed))
  const tasks = []
  for (const p of projects) {
    const data = call("GET", `/project/${p.id}/data`) || {}
    for (const task of data.tasks || []) if (!task.status) tasks.push(slim(task, p))
  }
  const cache = { at: Date.now(), projects: projects.map(p => ({ id: p.id, name: p.name })), tasks }
  writeJSON(CACHE, cache)
  return cache
}

function slim(task, project) {
  return { id: task.id, projectId: task.projectId || project.id, list: project.name, title: task.title || t("Untitled", "无标题"),
           due: task.dueDate || null, allDay: !!task.isAllDay, priority: task.priority || 0 }
}

// "2026-11-26T07:00:00.000+0000" → Date
const parseDue = raw => raw ? new Date(raw.replace(/\.\d+/, "").replace(/([+-]\d\d)(\d\d)$/, "$1:$2")) : null
const pad = n => String(n).padStart(2, "0")
const apiDate = d => `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}T${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:00+0000`
const timeZone = () => (sh("/usr/bin/readlink /etc/localtime").match(/zoneinfo\/(.+)$/) || [])[1] || "UTC"
const startOfDay = d => new Date(d.getFullYear(), d.getMonth(), d.getDate())
const addDays = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes())

// MARK: Quick add — "buy milk tomorrow 3pm #Work !high", "明天下午3点开会 #工作 !高"

const WEEKDAYS = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6, "日": 0, "天": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6 }
const PRIORITIES = { "1": 5, high: 5, h: 5, "高": 5, "2": 3, med: 3, medium: 3, m: 3, "中": 3, "3": 1, low: 1, l: 1, "低": 1 }
const CN_NUMBERS = { "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10, "十一": 11, "十二": 12 }

function parseQuick(text, projects, now = new Date()) {
  let rest = " " + text.trim() + " "
  const take = (re, fn) => { const m = rest.match(re); if (!m) return; rest = rest.replace(m[0], " \u0001 "); fn(m) }
  let priority = 0, list = null, day = null, time = null

  take(/\s!(\S+)/, m => { priority = PRIORITIES[m[1].toLowerCase()] || 0 })
  take(/\s#(\S+)/, m => {
    const name = m[1].toLowerCase()
    list = projects.find(p => p.name.toLowerCase() === name) || projects.find(p => p.name.toLowerCase().startsWith(name))
      || { id: null, name: m[1], missing: true }
  })

  // Times: 3pm, 3:30pm, 15:30, 下午3点, 晚上8点半, 10点
  take(/\s(\d{1,2})(?::(\d\d))?\s*(am|pm)(?=[\s,.，。])/i, m => {
    let h = Number(m[1]) % 12
    if (m[3].toLowerCase() === "pm") h += 12
    time = [h, Number(m[2] || 0)]
  })
  if (!time) take(/(上午|早上|中午|下午|晚上)?\s*(\d{1,2}|[一二两三四五六七八九十]{1,3})\s*[点:：时]\s*(半|\d{1,2}(?:分)?)?/, m => {
    let h = Number(m[2]) || CN_NUMBERS[m[2]] || 0
    const min = m[3] === "半" ? 30 : Number((m[3] || "0").replace("分", "")) || 0
    if ((m[1] === "下午" || m[1] === "晚上") && h < 12) h += 12
    if (m[1] === "中午" && h < 11) h += 12
    if (!m[1] && h >= 1 && h <= 7) h += 12  // a bare "3点" means the afternoon
    if (h < 24 && min < 60) time = [h, min]
  })

  const today = startOfDay(now)
  take(/今天|\stoday\s|\stod\s/i, () => { day = today })
  if (!day) take(/明天|\stomorrow\s|\stmr\s|\stmrw\s/i, () => { day = addDays(today, 1) })
  if (!day) take(/后天/, () => { day = addDays(today, 2) })
  if (!day) take(/(下|这|本)?(?:周|星期|礼拜)([一二三四五六日天])|\s(next\s)?(sun|mon|tue|wed|thu|fri|sat)[a-z]*(?=[\s,.，。])/i, m => {
    const target = WEEKDAYS[m[2] || m[4].slice(0, 3).toLowerCase()]
    // "下周一" / "next mon": that day in the week after this one (weeks start on Monday); otherwise the next one from today.
    const nextWeek = m[1] === "下" || !!m[3]
    const monday = addDays(today, -((today.getDay() + 6) % 7))
    day = nextWeek ? addDays(monday, 7 + (target + 6) % 7) : addDays(today, (target - today.getDay() + 7) % 7)
  })
  if (!day) take(/(\d{1,2})月(\d{1,2})[日号]?|\s(\d{1,2})[\/-](\d{1,2})\s/, m => {
    const month = Number(m[1] || m[3]) - 1, date = Number(m[2] || m[4])
    let d = new Date(today.getFullYear(), month, date)
    if (d < today) d = new Date(today.getFullYear() + 1, month, date)
    day = d
  })

  let due = null, allDay = false
  if (time) {
    const base = day || today
    due = new Date(base.getFullYear(), base.getMonth(), base.getDate(), time[0], time[1])
    if (!day && due < now) due = addDays(due, 1)
  } else if (day) {
    due = day
    allDay = true
  }
  // Drop the gaps left by what was taken out, with an "at" / "on" / "by" that led into them.
  const title = rest.replace(/\s(?:at|on|by)\s+\u0001/gi, " ").replace(/\u0001/g, " ").replace(/\s+/g, " ")
    .replace(/\s+([,，。.])/g, "$1").replace(/^[\s,，。.]+|[\s,，。.]+$/g, "")
  return { title, due, allDay, priority, list }
}

function describe(p) {
  const parts = []
  if (p.due) parts.push(whenText(p.due, p.allDay, new Date(), true))
  parts.push(p.list ? (p.list.missing ? t(`#${p.list.name} not found · Inbox`, `没有清单 #${p.list.name} · 收集箱`) : p.list.name) : t("Inbox", "收集箱"))
  if (p.priority) parts.push({ 5: t("High", "高"), 3: t("Medium", "中"), 1: t("Low", "低") }[p.priority])
  return parts.join(" · ")
}

// `keepTitle`: selected text is prose, so its words stay in the title and only the due date is read from it.
function create(text, projects, keepTitle = false) {
  const p = parseQuick(text, projects)
  if (keepTitle) p.title = text.trim()
  if (!p.title) return null
  const body = { title: p.title, priority: p.priority }
  if (p.list && !p.list.missing) body.projectId = p.list.id
  if (p.due) Object.assign(body, { dueDate: apiDate(p.due), startDate: apiDate(p.due), isAllDay: p.allDay, timeZone: timeZone() })
  const task = call("POST", "/task", body)
  return { parsed: p, task: slim(task, p.list && !p.list.missing ? p.list : { id: "inbox", name: t("Inbox", "收集箱") }) }
}

// MARK: Presentation

const PRIORITY_COLOR = { 5: "red", 3: "yellow", 1: "blue", 0: "secondary" }

function whenText(d, allDay, now = new Date(), withToday = false) {
  const days = Math.round((startOfDay(d) - startOfDay(now)) / 86400000)
  const dayText = days === 0 ? t("Today", "今天") : days === 1 ? t("Tomorrow", "明天") : days === -1 ? t("Yesterday", "昨天")
    : days > 1 && days < 7 ? d.toLocaleDateString(zh ? "zh-CN" : "en-US", { weekday: "short" }) : `${d.getMonth() + 1}/${d.getDate()}`
  return allDay ? dayText : (days === 0 && !withToday ? "" : dayText + " ") + `${pad(d.getHours())}:${pad(d.getMinutes())}`
}

function group(tasks, now = new Date()) {
  const today = startOfDay(now), tomorrow = addDays(today, 1), week = addDays(today, 8)
  const g = { overdue: [], today: [], tomorrow: [], week: [], later: [], none: [] }
  for (const task of tasks) {
    const d = parseDue(task.due)
    task._d = d
    if (!d) g.none.push(task)
    else if (task.allDay ? d < today : d < now) g.overdue.push(task)
    else if (d < tomorrow) g.today.push(task)
    else if (d < addDays(tomorrow, 1)) g.tomorrow.push(task)
    else if (d < week) g.week.push(task)
    else g.later.push(task)
  }
  const byDue = (a, b) => a._d - b._d || b.priority - a.priority
  for (const k of ["overdue", "today", "tomorrow", "week", "later"]) g[k].sort(byDue)
  g.none.sort((a, b) => b.priority - a.priority)
  return g
}

const completeAction = task => ({ run: `complete:${task.projectId}/${task.id}` })
const openTask = task => ({ open: `${WEB}/#p/${task.projectId}/tasks/${task.id}` })

function taskRow(task, overdue) {
  const row = { title: task.title, subtitle: task.list, symbol: overdue ? "exclamationmark.circle" : "circle",
                value: task._d ? whenText(task._d, task.allDay) : undefined, action: completeAction(task) }
  if (overdue) row.tint = "#E06C75"
  else if (task.priority >= 3) row.tint = task.priority === 5 ? "#E06C75" : "#E5C07B"
  return row
}

function taskLine(task, overdue) {
  return { type: "hstack", spacing: 8, children: [
    { type: "symbol", name: task.priority ? "circle.inset.filled" : "circle", size: 14, color: PRIORITY_COLOR[task.priority] || "secondary",
      action: completeAction(task) },
    { type: "text", text: task.title, size: 12, lines: 1, flex: true, action: openTask(task) },
    { type: "badge", text: task.list },
    task._d ? { type: "text", text: whenText(task._d, task.allDay), size: 11, mono: true, color: overdue ? "red" : "secondary", width: 78 } : null
  ].filter(Boolean) }
}

function section(title, tasks, color, overdue, limit) {
  if (!tasks.length) return []
  const shown = tasks.slice(0, limit)
  const nodes = [{ type: "hstack", spacing: 6, children: [
    { type: "text", text: title, size: 11, weight: "semibold", color },
    { type: "text", text: String(tasks.length), size: 11, color: "tertiary" } ] }]
  for (const task of shown) nodes.push(taskLine(task, overdue))
  if (tasks.length > shown.length) nodes.push({ type: "text", text: t(`+${tasks.length - shown.length} more`, `还有 ${tasks.length - shown.length} 项`), size: 10, color: "tertiary" })
  return [{ type: "vstack", spacing: 6, children: nodes }]
}

function render(cache, extra = {}) {
  const g = group(cache.tasks)
  const dueNow = g.overdue.length + g.today.length
  const hint = t("Add: ⌥Space › tt buy milk tomorrow 3pm #List !high", "添加：⌥Space › tt 明天下午3点 开会 #清单 !高")
  const page = { type: "vstack", spacing: 12, children: [
    { type: "hstack", spacing: 8, children: [
      { type: "text", text: dueNow ? t(`${dueNow} for today`, `今天 ${dueNow} 项`) : t("All clear today", "今天没有待办"), size: 15, weight: "bold" },
      g.overdue.length ? { type: "badge", text: t(`${g.overdue.length} overdue`, `过期 ${g.overdue.length}`), color: "red" } : null,
      { type: "spacer" },
      { type: "symbol", name: "arrow.up.forward.app", size: 12, color: "secondary", action: { open: WEB } } ].filter(Boolean) },
    ...section(t("Overdue", "已过期"), g.overdue, "red", true, 8),
    ...section(t("Today", "今天"), g.today, "primary", false, 12),
    ...section(t("Tomorrow", "明天"), g.tomorrow, "secondary", false, 6),
    ...section(t("Next 7 days", "未来 7 天"), g.week, "secondary", false, 6),
    ...section(t("No date", "无日期"), g.none, "tertiary", false, 5),
    { type: "text", text: hint, size: 10, color: "tertiary" } ] }

  const urgent = g.overdue.map(x => taskRow(x, true)).concat(g.today.map(x => taskRow(x, false)))
  const now = new Date()
  const alerts = !ALERTS ? [] : g.today.filter(x => !x.allDay && x._d - now >= 0 && x._d - now <= 10 * 60000).map(x => ({
    id: `due-${x.id}-${x.due}`, title: x.title, body: t(`Due at ${whenText(x._d, false)}`, `${whenText(x._d, false)} 到期`),
    symbol: "alarm", action: openTask(x) }))
  const soon = g.today.some(x => !x.allDay && x._d - now > 0 && x._d - now <= 15 * 60000)
  return Object.assign({
    ears: dueNow ? { symbol: "checkmark.square", text: String(dueNow), tint: g.overdue.length ? "#E06C75" : undefined } : null,
    home: { title: dueNow ? t(`${dueNow} for today`, `今天 ${dueNow} 项`) : "TickTick",
            rows: urgent.length ? urgent.slice(0, 3) : [{ title: t("All clear today", "今天没有待办"), subtitle: hint, symbol: "checkmark.circle", tint: "#98C379" }] },
    tab: { title: "TickTick", view: page },
    menubar: MENUBAR ? { symbol: "checkmark.square", text: dueNow ? String(dueNow) : undefined, tint: g.overdue.length ? "#E06C75" : undefined } : undefined,
    alerts: (extra.alerts || []).concat(alerts),
    next: soon ? 60 : undefined
  }, extra.result ? { result: extra.result } : {}, extra.results ? { results: extra.results } : {})
}

function setupOutput(title, subtitle, action) {
  const row = { title, subtitle, symbol: "link", action }
  return { ears: null, home: { title: "TickTick", rows: [row] }, tab: { title: "TickTick", rows: [row] } }
}

// MARK: Connect (OAuth code flow with a one-shot listener on localhost)

function connect() {
  if (!CLIENT_ID || !CLIENT_SECRET) {
    sh("/usr/bin/open " + q("https://developer." + REGION + "/manage"))
    return { alerts: [{ id: `connect-missing-${Date.now()}`, title: t("Client ID and secret needed", "需要 Client ID 和 secret"),
      body: t("Create an app, set its redirect URL to " + REDIRECT + ", then fill them in Settings › Plugins › TickTick.",
              "创建应用，回调地址填 " + REDIRECT + "，再把它们填到 设置 › 插件 › TickTick。"), symbol: "key" }] }
  }
  const state = String(Math.floor(Math.random() * 1e9))
  const auth = `https://${REGION}/oauth/authorize?scope=${encodeURIComponent("tasks:read tasks:write")}&client_id=${encodeURIComponent(CLIENT_ID)}`
    + `&state=${state}&redirect_uri=${encodeURIComponent(REDIRECT)}&response_type=code`
  const page = "<meta charset=utf-8><body style='font:16px -apple-system;padding:40px'>" + t("Altools is connected to TickTick. You can close this tab.", "Altools 已连接滴答清单，可以关闭这个页面了。")
  const reply = `HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n${page}`
  // The listener gives up after 100 s so the run ends inside its 120 s timeout.
  const request = sh(`r=$(/usr/bin/mktemp); /usr/bin/printf %s ${q(reply)} > "$r"; /usr/bin/open ${q(auth)};`
    + ` (/bin/sleep 100; /usr/bin/pkill -f 'nc -l 127.0.0.1 ${REDIRECT_PORT}') >/dev/null 2>&1 & k=$!;`
    + ` /usr/bin/nc -l 127.0.0.1 ${REDIRECT_PORT} < "$r" | /usr/bin/head -1; kill $k 2>/dev/null; rm -f "$r"`)
  const code = (request.match(/[?&]code=([^&\s]+)/) || [])[1]
  if (!code || !request.includes("state=" + state)) {
    return { alerts: [{ id: `connect-failed-${Date.now()}`, title: t("TickTick wasn't connected", "没有连上滴答清单"),
      body: t("No answer from the browser in time. Run Connect again.", "浏览器没有及时返回，请再运行一次 Connect。"), symbol: "exclamationmark.triangle" }] }
  }
  const out = sh(`/usr/bin/curl -s -m 15 -u ${q(CLIENT_ID + ":" + CLIENT_SECRET)} -d grant_type=authorization_code -d ${q("code=" + decodeURIComponent(code))}`
    + ` --data-urlencode ${q("redirect_uri=" + REDIRECT)} --data-urlencode 'scope=tasks:read tasks:write' ${q(`https://${REGION}/oauth/token`)}`)
  let token = null
  try { token = JSON.parse(out).access_token } catch (e) {}
  if (!token) {
    warn("token exchange failed: " + out.slice(0, 300))
    return { alerts: [{ id: `connect-failed-${Date.now()}`, title: t("TickTick refused the sign-in", "滴答清单拒绝了登录"),
      body: t("Check the client ID, secret and redirect URL.", "请检查 Client ID、secret 和回调地址。"), symbol: "exclamationmark.triangle" }] }
  }
  sh(`/usr/bin/security add-generic-password -U -s ${q(KEYCHAIN_SERVICE)} -a token -w ${q(token)}`)
  return { connected: true }
}

// MARK: Events

if (EVENT === "command:open") { sh("/usr/bin/open " + q(WEB)); emit({}) }

if (EVENT === "command:connect" || EVENT === "action:connect") {
  const r = connect()
  if (!r.connected) emit({ alerts: r.alerts })
  // Run again so the fresh token from the Keychain is read; the second run renders the tasks.
  const rerun = sh(`ALTOOLS_EVENT=refresh ALTOOLS_SETTING_TOKEN= /usr/bin/osascript -l JavaScript ${q(getenv("ALTOOLS_PLUGIN_DIR") + "/run.js")}`)
  let output = {}
  try { output = JSON.parse(rerun) } catch (e) {}
  output.alerts = (output.alerts || []).concat([{ id: `connected-${Date.now()}`, title: t("TickTick connected", "已连接滴答清单"), symbol: "checkmark.circle" }])
  emit(output)
}

if (!TOKEN) {
  const connectRow = setupOutput(t("Connect TickTick", "连接滴答清单"), t("Click, then approve in the browser", "点击后在浏览器里授权"), { run: "connect" })
  if (EVENT === "search") emit({ results: [{ title: t("Connect TickTick first", "先连接滴答清单"), subtitle: t("Settings › Plugins › TickTick", "设置 › 插件 › TickTick"), symbol: "link", action: { run: "connect" } }] })
  if (EVENT.startsWith("selection:")) emit({ result: { text: t("Connect TickTick first: Settings › Plugins › TickTick, then Connect.", "请先连接滴答清单：设置 › 插件 › TickTick，然后运行 Connect。") } })
  emit(connectRow)
}

try {
  if (EVENT === "search") {
    const cache = readJSON(CACHE) || fetchAll()
    const text = INPUT.trim()
    const results = []
    const p = parseQuick(text, cache.projects)
    if (p.title) {
      results.push({ title: t(`Add “${p.title}”`, `添加「${p.title}」`), subtitle: describe(p), symbol: "plus.circle.fill", tint: "#4772FA",
                     action: { run: "add:" + encodeURIComponent(text) } })
    }
    const needle = p.title.toLowerCase()
    const g = group(cache.tasks)
    const open = g.overdue.concat(g.today, g.tomorrow, g.week, g.later, g.none)
    for (const task of open.filter(x => !needle || x.title.toLowerCase().includes(needle)).slice(0, 8)) {
      const row = taskRow(task, g.overdue.includes(task))
      row.subtitle = t("Complete · ", "完成 · ") + task.list
      results.push(row)
    }
    emit({ results })
  }

  if (EVENT.startsWith("selection:add")) {
    const cache = readJSON(CACHE) || fetchAll()
    const lines = INPUT.trim().split(/\r?\n/).filter(l => l.trim())
    if (!lines.length) emit({ result: { text: t("Nothing selected", "没有选中文字") } })
    const made = create(lines[0].slice(0, 200), cache.projects, true)
    if (lines.length > 1) call("POST", `/task/${made.task.id}`, { id: made.task.id, projectId: made.task.projectId, content: lines.slice(1).join("\n") })
    cache.tasks.push(made.task)
    writeJSON(CACHE, cache)
    emit(render(cache, { result: { text: t(`Added “${made.parsed.title}” · `, `已添加「${made.parsed.title}」· `) + describe(made.parsed) } }))
  }

  if (EVENT.startsWith("action:add:")) {
    const cache = readJSON(CACHE) || fetchAll()
    const made = create(decodeURIComponent(EVENT.slice("action:add:".length)), cache.projects)
    if (made) cache.tasks.push(made.task)
    writeJSON(CACHE, cache)
    emit(render(cache, { alerts: made ? [{ id: `added-${made.task.id}`, title: t(`Added “${made.parsed.title}”`, `已添加「${made.parsed.title}」`),
                                            body: describe(made.parsed), symbol: "checkmark.circle", tint: "#98C379", action: openTask(made.task) }] : [] }))
  }

  if (EVENT.startsWith("action:complete:")) {
    const [projectId, taskId] = EVENT.slice("action:complete:".length).split("/")
    call("POST", `/project/${projectId}/task/${taskId}/complete`)
    const cache = readJSON(CACHE) || fetchAll()
    const done = cache.tasks.find(x => x.id === taskId)
    cache.tasks = cache.tasks.filter(x => x.id !== taskId)
    writeJSON(CACHE, cache)
    emit(render(cache, { alerts: done ? [{ id: `done-${taskId}`, title: t(`Done: ${done.title}`, `已完成：${done.title}`), symbol: "checkmark.circle.fill", tint: "#98C379" }] : [] }))
  }

  emit(render(fetchAll()))
} catch (e) {
  if (e instanceof HTTPError && e.status === 401) {
    if (EVENT === "search") emit({ results: [{ title: t("Reconnect TickTick", "重新连接滴答清单"), subtitle: t("The sign-in has expired", "登录已过期"), symbol: "link", action: { run: "connect" } }] })
    if (EVENT.startsWith("selection:")) emit({ result: { text: t("The TickTick sign-in has expired. Run Connect TickTick again.", "滴答清单登录已过期，请重新运行 Connect TickTick。") } })
    emit(setupOutput(t("Reconnect TickTick", "重新连接滴答清单"), t("The sign-in has expired", "登录已过期"), { run: "connect" }))
  }
  warn(String(e))
  $.exit(1)
}
