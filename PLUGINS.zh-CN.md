# Altools 插件

[English](PLUGINS.md) · **简体中文**

插件可以把你自己的信息放进 Altools 的刘海：刘海旁边的一个数字、主页上的一张卡片、「插件」标签页里的一页，
以及从刘海弹下来的提醒卡片。一个插件就是一个文件夹，里面有 `plugin.json` 和一个任意语言写的程序。
Altools 定时运行这个程序，程序打印一段 JSON 告诉 Altools 要显示什么。整个 API 就这么多。

你可以手写，也可以把这一页交给 Claude Code 或其他编程 agent 让它来写，或者在
**设置 › 刘海 › 插件 › 用 AI 做一个插件** 里直接描述你想要什么。

## 文件夹

```
~/Library/Application Support/Altools/Plugins/
  ticktick/            ← 文件夹名 = 插件 id
    plugin.json
    run.py             ← 任意可执行文件：shell、Python、Node、编译好的程序……
```

放进文件夹的插件默认是 **关闭** 的：它们是以你的身份运行的程序，信任它才在设置里打开。
文件夹里的改动会被自动识别。

## plugin.json

```json
{
  "id": "ticktick",
  "name": "TickTick",
  "version": "1.0.0",
  "author": "you",
  "description": "今天到期的任务",
  "api": 1,
  "icon": "checklist",
  "tint": "#E5C07B",
  "run": "run.py",
  "interval": 300,
  "timeout": 20,
  "slots": ["ears", "home", "tab", "alerts"],
  "settings": [
    { "key": "token", "title": "API token", "type": "secret" },
    { "key": "region", "title": "区域", "type": "choice", "options": ["ticktick.com", "dida365.com"], "default": "dida365.com" }
  ]
}
```

| 字段 | 含义 |
|---|---|
| `id` | 小写字母、数字和短横线，必须和文件夹名一致。 |
| `name`、`version`、`author`、`description` | 显示在设置里。 |
| `api` | 插件按哪个版本的 API 写的。本页描述的是 `1`。 |
| `icon` | 一个 [SF Symbol](https://developer.apple.com/sf-symbols/) 名称。 |
| `tint` | `#RRGGBB` 强调色。 |
| `run` | 程序路径，相对于插件文件夹；没有可执行权限会自动加上。 |
| `interval` | 两次运行之间的秒数，至少 10，默认 300。 |
| `timeout` | 一次运行最多多少秒，超时就停止，1 到 120，默认 20。 |
| `slots` | 输出可以出现在哪里：`ears`、`home`、`tab`、`alerts`，默认全部。 |
| `settings` | 用户在设置里填写的字段：`type` 可以是 `text`、`secret`（存在钥匙串里）、`toggle`（`"1"`/`"0"`）或 `choice`（配合 `options`）。 |

## 一次运行是怎样的

Altools 以插件文件夹为工作目录启动程序，环境里带着用户的 PATH（包括 Homebrew）和代理，另外还有：

| 变量 | 值 |
|---|---|
| `ALTOOLS_API` | `1` |
| `ALTOOLS_EVENT` | 定时运行时是 `refresh`；用户点了 `run` 动作时是 `action:<id>` |
| `ALTOOLS_PLUGIN_ID` | 插件 id |
| `ALTOOLS_PLUGIN_DIR` | 插件文件夹 |
| `ALTOOLS_DATA_DIR` | 可写的文件夹，放缓存和状态，多次运行之间会保留 |
| `ALTOOLS_LANG` | `en` 或 `zh` |
| `ALTOOLS_SETTING_<KEY>` | 每个设置项的值，比如 `ALTOOLS_SETTING_TOKEN` |

程序在 stdout 打印 **一个 JSON 对象**，然后以状态 0 退出。最后一个以 `{` 开头的行之前的输出都会被忽略，
所以往 stdout 打日志不会出问题；stderr 会进到设置里这个插件的日志。非零退出、JSON 不合法或者超时，
错误会显示在设置和插件卡片上，刘海照常工作。

## 输出

每一部分都可以省略；`slots` 里没有列出的部分会被忽略。

```json
{
  "ears": { "symbol": "checklist", "text": "3", "tint": "#E5C07B" },
  "home": {
    "title": "今天到期",
    "rows": [ { "title": "发出发票", "value": "15:00", "action": { "open": "https://dida365.com" } } ]
  },
  "tab": {
    "title": "滴答清单",
    "sections": [
      { "title": "工作", "rows": [
        { "title": "发出发票", "subtitle": "今天 15:00", "symbol": "circle", "action": { "run": "complete:abc123" } }
      ] }
    ]
  },
  "alerts": [
    { "id": "due-abc123", "title": "发出发票", "body": "10 分钟后到期", "action": { "open": "ticktick://" } }
  ],
  "next": 60
}
```

| 部分 | 显示在 |
|---|---|
| `ears` | 刘海旁边，在没有更重要的动态（会议、音乐、agent）时显示。`text` 最多 24 个字符。 |
| `home` | 主页上的一张卡片，显示前三行。用户在 设置 › 刘海 › 主页布局 里添加。 |
| `tab` | 刘海「插件」标签页里的一页。`sections` 可以带标题；直接写 `rows` 也可以。 |
| `alerts` | 从刘海弹下来的卡片。每个 `id` 只会出现一次，所以重复输出也没关系。 |
| `next` | 距离下一次运行的秒数，只覆盖一次 `interval`（至少 10）。 |

**行（row）** 是 `{ "title", "subtitle"?, "symbol"?, "tint"?, "value"?, "action"? }`；`value` 是右侧的短文字，比如时间或数字。

**动作（action）** 是下面其中一种：

- `{ "open": "<url>" }` 打开网页、某个 app 的 URL scheme，或者 `file://` 路径。
- `{ "run": "<id>" }` 以 `ALTOOLS_EVENT=action:<id>` 再运行一次程序，这次的输出替换当前显示的内容。
  适合「标记完成」「立即刷新」「稍后提醒」这类操作。
- `{ "copy": "<text>" }` 把文字复制到剪贴板。

## 最小的插件

`plugin.json`：

```json
{ "id": "hello", "name": "Hello", "icon": "hand.wave.fill", "run": "run.sh", "interval": 60 }
```

`run.sh`：

```sh
#!/bin/sh
if [ "$ALTOOLS_EVENT" = "action:greet" ]; then greeting="Hi again"; else greeting="Hello"; fi
cat <<EOF
{ "ears": { "text": "$(date +%H:%M)" },
  "tab": { "rows": [
    { "title": "$greeting", "symbol": "hand.wave", "action": { "run": "greet" } },
    { "title": "Copy the time", "value": "$(date +%H:%M)", "action": { "copy": "$(date)" } }
  ] } }
EOF
```

更多例子在 [`examples/plugins`](examples/plugins)：`hello`，以及一个滴答清单 / TickTick 任务列表。

## 让 AI agent 来写

把这一页和一句话交给你的 agent，比如：

> 按照 PLUGINS.md，在 `~/Library/Application Support/Altools/Plugins/hn/` 写一个 Altools 插件，
> 在「插件」页显示 Hacker News 前 5 条，在刘海旁边显示第一条的分数。
> 用 `ALTOOLS_EVENT=refresh` 运行一次，确认它打印的是合法 JSON。

然后在 设置 › 刘海 › 插件 里打开它。

## 建议

- 每次运行尽量快；慢的 API 请求缓存到 `$ALTOOLS_DATA_DIR`。
- 不要打印密钥，从 `ALTOOLS_SETTING_*` 读取。
- 优先用 macOS 自带的工具（`sh`、`curl`、`osascript`）。`python3` 需要苹果的 Command Line Tools，
  大多数开发者都装了。
- 手拼 JSON 时注意转义字符串；用 JSON 库更稳妥。
