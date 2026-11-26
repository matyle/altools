# TickTick / 滴答清单 plugin

Read and add TickTick tasks from anywhere in Altools. Plain JavaScript for macOS's own `osascript`:
nothing to install.

| Where | What |
|---|---|
| Beside the notch | How many tasks are due today (red when something is overdue) |
| Home | The next three: overdue first, then today |
| Its own tab | Overdue, Today, Tomorrow, Next 7 days and No date. Click the circle to complete a task, the title to open it in TickTick |
| Launcher (⌥ Space) | `tt buy milk tomorrow 3pm #Work !high` adds a task; `tt milk` also finds open tasks to complete |
| Selected text | ⋯ › **Add to TickTick**: the first line becomes the title, the rest the description |
| Alerts | A card 10 minutes before a timed task is due |
| Menu bar | Optional count (setting "Count in the menu bar") |

## Quick add

Dates, times, lists and priority are taken out of the text; what's left is the title.

| Type | Examples |
|---|---|
| Day | `today` `tomorrow` `tmr` `fri` `next mon` `12/25` · `今天` `明天` `后天` `周五` `下周一` `12月25日` |
| Time | `3pm` `9:30pm` `14:00` · `下午3点` `晚上8点半` `3点半` (a bare 1–7点 means the afternoon) |
| List | `#Work` (a name or its start; unknown lists go to the Inbox) |
| Priority | `!high` `!med` `!low` · `!1` `!2` `!3` · `!高` `!中` `!低` |

A time with no day means today, or tomorrow if that time has passed. A day with no time is an
all-day task.

## Connect

1. Install it (Settings › Plugins › **Install examples**, or copy this folder to
   `~/Library/Application Support/Altools/Plugins/ticktick`) and switch it on.
2. Sign in at <https://developer.dida365.com> (滴答清单) or <https://developer.ticktick.com>,
   choose **Manage Apps › New App**, and set its redirect URL to exactly
   `http://localhost:8765/callback`.
3. In Settings › Plugins › TickTick choose the service and fill in the app's **Client ID** and
   **Client secret**.
4. Click **Connect TickTick** in its tab (or run *Connect TickTick* from the launcher) and approve in
   the browser. The token is saved in your login Keychain under "Altools TickTick".

If you already have an access token, paste it into "Access token" instead and skip steps 2–4.
When the sign-in expires (about every six months), the tab shows **Reconnect TickTick**.

---

# 滴答清单插件

在 Altools 的各个地方读取和添加滴答清单任务。用 macOS 自带的 `osascript` 运行，不用装任何东西。

- **刘海旁**：今天到期的数量（有过期任务时变红）
- **主页**：最近三项，过期的在前
- **自己的标签页**：已过期、今天、明天、未来 7 天、无日期；点圆圈完成，点标题在滴答清单里打开
- **启动器（⌥ 空格）**：`tt 明天下午3点 开会 #工作 !高` 添加任务；`tt 开会` 也会列出能完成的任务
- **划词**：⋯ › **Add to TickTick**，第一行做标题，其余做描述
- **提醒**：定时任务到期前 10 分钟弹卡片
- **菜单栏**：可选显示数量

连接方法：在 <https://developer.dida365.com> 新建应用，回调地址填 `http://localhost:8765/callback`；
把 Client ID 和 secret 填到 设置 › 插件 › TickTick，然后点标签页里的 **Connect TickTick**，在浏览器里授权即可。
token 存在登录钥匙串里。
