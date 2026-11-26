# Altools 插件

[English](PLUGINS.md) · **简体中文**

插件可以扩展 Altools 的任何地方：刘海（旁边的文字、主页小组件、自己的标签页、提醒卡片）、菜单栏、
启动器（带快捷键的命令和搜索），以及选中的文字。插件也可以完全没有界面，只在发生某件事时弹出提醒。一个插件就是一个文件夹，里面有 `plugin.json` 和一个任意语言写的程序。
Altools 定时运行这个程序，程序打印一段 JSON 告诉 Altools 要显示什么。整个 API 就这么多。

你可以手写，也可以把这一页交给 Claude Code 或其他编程 agent 让它来写，或者在
**设置 › 插件 › 用 AI 做一个插件** 里直接描述你想要什么。

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
| `mode` | `interval`（默认）：每 `interval` 秒运行一次。`stream`：启动一次后一直运行，见 [常驻插件](#常驻插件)。 |
| `interval` | 两次运行之间的秒数，至少 10，默认 300。 |
| `timeout` | 一次运行最多多少秒，超时就停止，1 到 120，默认 20。 |
| `slots` | 输出可以出现在哪里：`ears`、`home`、`tab`、`alerts`、`menubar`，默认全部。 |
| `commands` | 启动器命令，每条 `{ "id", "title", "subtitle"?, "icon"?, "keywords"?, "hotkey"? }`，见 [刘海之外](#刘海之外)。 |
| `selection` | 划词操作，每条 `{ "id", "title", "icon"? }`。 |
| `search` | `{ "keyword", "placeholder"? }`：以这个关键词开头的启动器输入会交给插件。 |
| `settings` | 用户在设置里填写的字段：`type` 可以是 `text`、`secret`（存在钥匙串里）、`toggle`（`"1"`/`"0"`）或 `choice`（配合 `options`）。 |

## 一次运行是怎样的

Altools 以插件文件夹为工作目录启动程序，环境里带着用户的 PATH（包括 Homebrew）和代理，另外还有：

| 变量 | 值 |
|---|---|
| `ALTOOLS_API` | `1` |
| `ALTOOLS_EVENT` | 定时运行时是 `refresh`；用户点了 `run` 动作时是 `action:<id>`；[触发链接](#触发链接) 是 `trigger:<name>`；还有 `command:<id>`、`selection:<id>`、`search`（见 [刘海之外](#刘海之外)） |
| `ALTOOLS_INPUT` | 选中的文字（`selection:<id>`）或搜索内容（`search`）；其他情况没有这个变量 |
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
| `ears` | 刘海旁边，在没有更重要的动态（会议、音乐、agent）时显示。简单写法：左边 `symbol`，右边 `text`（最多 24 个字符），宽度随文字变化。也可以把 `left`、`right` 写成 [视图](#视图自己的界面)，并用 `width` 指定每边宽度（30–140，默认 64），比如左边币种图标、右边价格叠涨跌幅。 |
| `home` | 主页上的小组件：你自己的 `view`，或者 `title` 加前三行 `rows`。用户在 设置 › 刘海 › 主页布局 里摆放，和同一行的其他卡片平分宽度。 |
| `tab` | 刘海标签栏里插件自己的标签页（图标用 `icon`，打开时显示 `title`）：一个 `view`，或者 `sections` / `rows`。 |
| `alerts` | 从刘海弹下来的卡片。每个 `id` 只会出现一次，所以重复输出也没关系。 |
| `next` | 距离下一次运行的秒数，只覆盖一次 `interval`（至少 10）。 |

**行（row）** 是 `{ "title", "subtitle"?, "symbol"?, "tint"?, "value"?, "action"? }`；`value` 是右侧的短文字，比如时间或数字。

`home` 和 `tab` 可以用简单的 `rows`，也可以用自己排版的 [`view`](#视图自己的界面)。

**动作（action）** 是下面其中一种：

- `{ "open": "<url>" }` 打开网页、某个 app 的 URL scheme，或者 `file://` 路径。
- `{ "run": "<id>" }` 以 `ALTOOLS_EVENT=action:<id>` 再运行一次程序，这次的输出替换当前显示的内容。
  适合「标记完成」「立即刷新」「稍后提醒」这类操作。
- `{ "copy": "<text>" }` 把文字复制到剪贴板。

## 视图：自己的界面

和小组件一样，插件可以自己排版界面。在 `home.view` 或 `tab.view` 里放一棵节点树，Altools 会按刘海的风格原生绘制。
任何节点都可以带 `action`，带了就能点击。

```json
{ "tab": { "title": "行情", "view":
  { "type": "grid", "columns": 2, "children": [
    { "type": "card", "action": { "open": "https://finance.yahoo.com/quote/AAPL" }, "children": [
      { "type": "hstack", "children": [
        { "type": "badge", "text": "美股" },
        { "type": "text", "text": "AAPL", "weight": "bold" },
        { "type": "spacer" },
        { "type": "text", "text": "231.47", "mono": true } ] },
      { "type": "text", "text": "+0.86%", "size": 10, "color": "green" },
      { "type": "sparkline", "values": [228, 230, 229, 231.5], "color": "green" } ] } ] } } }
```

| 类型 | 属性 |
|---|---|
| `vstack`、`hstack` | `children`、`spacing`、`align`（`leading`/`center`/`trailing`；hstack 用 `top`/`center`/`bottom`） |
| `grid` | `children`、`columns`（1–6）、`spacing` |
| `card` | `children`（竖排）、`padding`、`color`（背景色调） |
| `text` | `text`、`size`（9–28）、`weight`（`regular`/`medium`/`semibold`/`bold`）、`color`、`mono`（数字等宽）、`lines` |
| `symbol` | `name`（SF Symbol）、`size`、`color` |
| `image` | `url`：`https://…` 或插件文件夹里的文件；`width`、`height`、`radius` |
| `badge` | `text`、`color` |
| `progress` | `value` 0–1、`color` |
| `sparkline` | `values`（数字数组）、`color`、`height` |
| `spacer`、`divider` | — |

所有节点还可以带 `width`、`height`、`flex`（`true` 表示撑满宽度）、`opacity` 和 `action`。
颜色用 `#RRGGBB` 或 `primary`、`secondary`、`tertiary`、`green`、`red`、`orange`、`yellow`、`blue`、`purple`、`cyan`。
节点树最多 12 层、400 个节点；不认识的类型会被跳过。

## 刘海之外

**菜单栏。** `slots` 里有 `menubar` 时，输出 `"menubar": { "symbol"?, "text"?, "tint"? }`（文字最多 20 个字符）
就会出现一个菜单栏图标；点开是一个面板，显示插件的 `tab` 页面。

**启动器命令。** `commands` 里的每一条都会出现在 ⌥ Space 启动器里（按标题、`keywords` 和插件名匹配）。
运行时插件收到 `ALTOOLS_EVENT=command:<id>`。`hotkey` 可以写 `"⌥⇧T"` 或 `"ctrl+option+u"`，在任何地方都能触发；
被别的 app 占用的组合会被跳过。输出里有 `result` 时，会复制并显示出来：

```json
{ "result": { "text": "5747fb34-ee34-4438-82c4-0a240b0fc22f", "title": "UUID" } }
```

**划词。** `selection` 里的每一条会出现在划词工具条的 ⋯ 菜单里。插件以 `ALTOOLS_EVENT=selection:<id>` 运行，
选中的文字在 `ALTOOLS_INPUT`；`result` 显示在结果面板里，有 **复制**，`"replace": true` 时还有 **替换**。

**启动器搜索。** 写了 `"search": { "keyword": "b64" }` 后，输入 `b64 hello` 会以 `ALTOOLS_EVENT=search`、
`ALTOOLS_INPUT=hello` 运行插件；它输出的 `"results"`（行）会替换启动器的列表，回车执行这一行的动作（没有动作就复制标题）。
停止输入四分之一秒后才发请求。

命令、划词和搜索总是单独运行一次，不论哪种 `mode`；这次输出里的其他部分（ears、home……）也会更新显示。
插件可以只用这些、不写任何刘海 slot，例子见 [`examples/plugins/text-tools`](examples/plugins/text-tools)。

## 常驻插件

响应事件而不是按时间运行的插件，设置 `"mode": "stream"`。Altools 启动程序一次，然后让它一直运行：

- **每打印一行**（stdout）就是一个输出对象，立即生效。某一行没写的部分保留原来显示的内容，所以只含 `alerts` 的一行就只弹出卡片；
  `slots` 只有 `["alerts"]` 的插件完全没有界面。
- **事件从 stdin 按行传进来**：用户点了 `run` 动作是 `action:<id>`，触发链接是 `trigger:<name>`。
- 程序退出后 5 秒重启，之后每次翻倍，最长 5 分钟；插件被关闭时停止。

例子见 [`examples/plugins/site-monitor`](examples/plugins/site-monitor)：网站挂掉或恢复时才弹提醒。

## 触发链接

任何程序都可以运行插件：hook、cron、快捷指令、CI 脚本。

```sh
open -g "altools://plugin/deploys/run?event=finished"
```

定时插件会以 `ALTOOLS_EVENT=trigger:finished` 运行一次；常驻插件会从 stdin 收到 `trigger:finished`。

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

更多例子在 [`examples/plugins`](examples/plugins)：`hello`（行和视图）、`ticktick`（滴答清单 / TickTick：在刘海、启动器和划词里读取、添加任务，带 OAuth 登录）、
`site-monitor`（没有界面的常驻插件），以及 `text-tools`（划词、带快捷键的命令、启动器搜索）。内置的行情插件（[`Resources/BuiltinPlugins/markets`](Resources/BuiltinPlugins/markets)）
是视图的完整例子。

## 让 AI agent 来写

把这一页和一句话交给你的 agent，比如：

> 按照 PLUGINS.md，在 `~/Library/Application Support/Altools/Plugins/hn/` 写一个 Altools 插件，
> 在「插件」页显示 Hacker News 前 5 条，在刘海旁边显示第一条的分数。
> 用 `ALTOOLS_EVENT=refresh` 运行一次，确认它打印的是合法 JSON。

然后在 设置 › 插件 里打开它。

## 分享和发布

**文件。** 设置 › 插件 › **导出…** 会把插件存成 `<id>.altoolsplugin`（就是压缩后的文件夹）。
别人装了 Altools 后，双击它、拖到 Altools 上，或者用 **导入…** 都可以安装；Altools 会先显示名字、作者和显示位置，
确认后才安装。

**链接。** 把插件放进一个 GitHub 仓库，然后分享：

```
altools://install-plugin?repo=you/your-plugin
altools://install-plugin?repo=you/plugins&path=weather&ref=v1.2
```

`path` 指向子文件夹里的插件，`ref` 指定分支或标签（默认是默认分支）。`url=https://…` 可以安装任何包含插件的 zip。
在设置里的 **从 GitHub 安装** 粘贴 `you/your-plugin` 或 GitHub 链接，效果一样。

**插件商店。** 设置 › 插件 › **插件商店** 会列出：

- 所有带 **`altools-plugin`** 话题（topic）、根目录有 `plugin.json` 的公开 GitHub 仓库。
  发布方法：推送插件，再给仓库加上这个话题（仓库 › About › ⚙ › Topics）。按 star 数排序。
  更新就是再推送一次；`version` 变了，用户会看到 **更新**。
- 本仓库 [`plugins/registry.json`](plugins/registry.json) 里的 **精选** 插件。想被精选，按本页检查过后，
  提一个 PR 加上 `{ "repo": "you/your-plugin" }`（子文件夹再加 `"path"`，固定分支或标签加 `"ref"`）。

商店直接从 GitHub 读取 `plugin.json`，所以请填好 `name`、`description`、`author`、`icon` 和 `version`。
商店里的插件依然是以用户身份运行的程序：保持代码易读，不要在运行时再下载代码来执行。

## 建议

- 每次运行尽量快；慢的 API 请求缓存到 `$ALTOOLS_DATA_DIR`。
- 不要打印密钥，从 `ALTOOLS_SETTING_*` 读取。
- 优先用 macOS 自带的工具（`sh`、`curl`、`osascript`）。`python3` 需要苹果的 Command Line Tools，
  大多数开发者都装了。
- 手拼 JSON 时注意转义字符串；用 JSON 库更稳妥。
