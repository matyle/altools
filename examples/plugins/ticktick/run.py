#!/usr/bin/env python3
"""Altools plugin: TickTick / 滴答清单 tasks due today and overdue.

Uses the TickTick Open API with an OAuth access token (see README.md). The contract with
Altools (environment in, one JSON object out) is in PLUGINS.md.
"""
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.request

TOKEN = os.environ.get("ALTOOLS_SETTING_TOKEN", "").strip()
REGION = os.environ.get("ALTOOLS_SETTING_REGION", "dida365.com") or "dida365.com"
ALERTS = os.environ.get("ALTOOLS_SETTING_ALERTS", "1") == "1"
EVENT = os.environ.get("ALTOOLS_EVENT", "refresh")
ZH = os.environ.get("ALTOOLS_LANG") == "zh"
API = os.environ.get("TICKTICK_API_BASE") or f"https://api.{REGION}/open/v1"
APP_URL = "https://dida365.com/webapp" if REGION == "dida365.com" else "https://ticktick.com/webapp"


def t(en, zh):
    return zh if ZH else en


def emit(payload):
    print(json.dumps(payload, ensure_ascii=False))
    sys.exit(0)


def request(method, path):
    req = urllib.request.Request(API + path, method=method, headers={"Authorization": f"Bearer {TOKEN}"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        body = resp.read()
        return json.loads(body) if body else None


def parse_due(task):
    raw = task.get("dueDate")
    if not raw:
        return None
    # "2026-11-26T07:00:00.000+0000"
    try:
        return dt.datetime.strptime(raw, "%Y-%m-%dT%H:%M:%S.%f%z")
    except ValueError:
        return None


def message_only(title, subtitle, action=None):
    row = {"title": title, "subtitle": subtitle, "symbol": "exclamationmark.triangle"}
    if action:
        row["action"] = action
    return {"ears": {"symbol": "checklist", "text": "!"},
            "home": {"title": "TickTick", "rows": [row]},
            "tab": {"title": "TickTick", "rows": [row]}}


if not TOKEN:
    emit(message_only(t("Add your access token", "填写 access token"),
                      t("Settings › Notch › Plugins › TickTick", "设置 › 刘海 › 插件 › TickTick"),
                      {"open": "https://github.com/matyle/altools/blob/main/examples/plugins/ticktick/README.md"}))

try:
    if EVENT.startswith("action:complete:"):
        project_id, _, task_id = EVENT[len("action:complete:"):].partition("/")
        request("POST", f"/project/{project_id}/task/{task_id}/complete")

    projects = request("GET", "/project") or []
    projects = [{"id": "inbox", "name": t("Inbox", "收集箱")}] + [p for p in projects if not p.get("closed")]
    tasks = []
    for project in projects:
        data = request("GET", f"/project/{project['id']}/data") or {}
        for task in data.get("tasks", []):
            if task.get("status", 0) == 0:
                task["_project"] = project.get("name", "")
                tasks.append(task)
except urllib.error.HTTPError as error:
    if error.code == 401:
        emit(message_only(t("The access token was refused", "access token 无效"), t("Get a new one and paste it in Settings", "重新获取后填到设置里")))
    print(f"HTTP {error.code}: {error.reason}", file=sys.stderr)
    sys.exit(1)
except (urllib.error.URLError, TimeoutError) as error:
    print(f"network: {error}", file=sys.stderr)
    sys.exit(1)

now = dt.datetime.now(dt.timezone.utc).astimezone()
end_of_today = now.replace(hour=23, minute=59, second=59, microsecond=0)
due = []
for task in tasks:
    when = parse_due(task)
    if when is not None and when.astimezone() <= end_of_today:
        task["_due"] = when.astimezone()
        due.append(task)
due.sort(key=lambda task: task["_due"])


def row(task):
    when = task["_due"]
    overdue = when < now.replace(hour=0, minute=0, second=0, microsecond=0) or (when < now and not task.get("isAllDay"))
    if task.get("isAllDay"):
        value = t("Overdue", "已过期") if when.date() < now.date() else t("Today", "今天")
    else:
        value = when.strftime("%H:%M") if when.date() == now.date() else when.strftime("%m-%d")
    return {"title": task.get("title") or t("Untitled", "无标题"),
            "subtitle": task.get("_project"),
            "symbol": "exclamationmark.circle" if overdue else "circle",
            "tint": "#E06C75" if overdue else None,
            "value": value,
            "action": {"run": f"complete:{task.get('projectId', 'inbox')}/{task['id']}"}}


rows = [row(task) for task in due]
for r in rows:
    if r["tint"] is None:
        del r["tint"]

sections = {}
for task, r in zip(due, rows):
    sections.setdefault(task["_project"], []).append(r)

alerts = []
if ALERTS:
    for task in due:
        minutes = (task["_due"] - now).total_seconds() / 60
        if not task.get("isAllDay") and 0 <= minutes <= 10:
            alerts.append({"id": f"due-{task['id']}-{task['_due'].isoformat()}",
                           "title": task.get("title") or "TickTick",
                           "body": t(f"Due at {task['_due']:%H:%M}", f"{task['_due']:%H:%M} 到期"),
                           "symbol": "alarm",
                           "action": {"open": APP_URL}})

open_app = {"title": t("Open TickTick", "打开滴答清单"), "symbol": "arrow.up.forward.app", "action": {"open": APP_URL}}
emit({
    "ears": {"symbol": "checklist", "text": str(len(due))} if due else None,
    "home": {"title": t(f"{len(due)} due today", f"今天 {len(due)} 项"), "rows": rows[:3] or [open_app]},
    "tab": {"title": "TickTick",
            "sections": [{"title": name, "rows": items} for name, items in sections.items()]
                        or [{"title": t("Nothing due today", "今天没有到期任务"), "rows": [open_app]}]},
    "alerts": alerts,
    "next": 60 if alerts else None,
})
