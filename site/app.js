// Altools homepage: a simulated Mac desktop running Altools. Everything here is demo data.
(() => {
  "use strict";
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch {} },
  };

  // ---------- Icons (stroke drawings on a 24-unit grid) ----------
  const P = (d, extra = "") => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" ${extra}>${d}</svg>`;
  const ICONS = {
    grid: `<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="1.4" width="12" height="3.4" rx="1.7"/><rect x="4.3" y="7.4" width="4" height="4" rx="1.1"/><rect x="9.7" y="7.4" width="4" height="4" rx="1.1"/><rect x="15.1" y="7.4" width="4" height="4" rx="1.1"/><rect x="4.3" y="12.8" width="4" height="4" rx="1.1"/><rect x="9.7" y="12.8" width="4" height="4" rx="1.1"/><rect x="15.1" y="12.8" width="4" height="4" rx="1.1"/><rect x="4.3" y="18.2" width="4" height="4" rx="1.1"/><rect x="9.7" y="18.2" width="4" height="4" rx="1.1"/><rect x="15.1" y="18.2" width="4" height="4" rx="1.1"/></svg>`,
    cloud: P('<path d="M7 18h10a4 4 0 0 0 .5-8 6 6 0 0 0-11.4 1.5A3.3 3.3 0 0 0 7 18z"/>'),
    chat: P('<path d="M4 5h16v11H9l-5 4z"/>'),
    shield: P('<path d="M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z"/>'),
    key: P('<circle cx="8" cy="12" r="4"/><path d="M12 12h9M18 12v3M21 12v2"/>'),
    cpu: P('<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M9 2v3M15 2v3M9 19v3M15 19v3M2 9h3M2 15h3M19 9h3M19 15h3"/>'),
    battery: P('<rect x="2" y="7" width="17" height="10" rx="2.5"/><path d="M22 10v4"/><rect x="4.5" y="9.5" width="11" height="5" rx="1" fill="currentColor" stroke="none"/>'),
    wifi: P('<path d="M2 9a15 15 0 0 1 20 0M5.5 12.5a10 10 0 0 1 13 0M9 16a5 5 0 0 1 6 0"/><circle cx="12" cy="19.5" r="1" fill="currentColor"/>'),
    house: P('<path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>'),
    music: P('<path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/>'),
    gauge: P('<path d="M4 18a8 8 0 1 1 16 0"/><path d="M12 14l4-5"/><circle cx="12" cy="14" r="1.2" fill="currentColor"/>'),
    chart: P('<path d="M3 20h18M4 16l5-6 4 3 7-8"/>'),
    back: `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M11 6v12L3 12zM21 6v12l-8-6z"/></svg>`,
    fwd: `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M13 6v12l8-6zM3 6v12l8-6z"/></svg>`,
    pause: `<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>`,
    check: P('<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M8 12l3 3 5-6"/>'),
    capture: P('<path d="M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3"/><circle cx="12" cy="12" r="3"/>'),
    drop: P('<path d="M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z"/>'),
    clip: P('<rect x="6" y="4" width="12" height="17" rx="2"/><path d="M9 4V3h6v1M9 10h6M9 14h6"/>'),
    translate: P('<path d="M4 5h9M8.5 3v2M6 5c0 4 3 7 6 8M11 5c0 4-3 7-7 9"/><path d="M13 21l4-9 4 9M14.5 18h5"/>'),
    spark: P('<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="M19 16l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8z"/>'),
    gear: P('<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1"/>'),
    note: P('<path d="M5 3h10l4 4v14H5z"/><path d="M15 3v4h4M8 12h8M8 16h6"/>'),
    download: P('<path d="M12 4v11M7 10l5 5 5-5M5 20h14"/>'),
    github: `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2a10 10 0 0 0-3.2 19.5c.5.1.7-.2.7-.5v-1.7c-2.8.6-3.4-1.3-3.4-1.3-.4-1.2-1.1-1.5-1.1-1.5-.9-.6.1-.6.1-.6 1 .1 1.6 1 1.6 1 .9 1.6 2.4 1.1 3 .9.1-.7.4-1.1.6-1.4-2.2-.3-4.6-1.1-4.6-5 0-1.1.4-2 1-2.7-.1-.3-.4-1.3.1-2.7 0 0 .8-.3 2.8 1a9.6 9.6 0 0 1 5 0c1.9-1.3 2.7-1 2.7-1 .6 1.4.2 2.4.1 2.7.6.7 1 1.6 1 2.7 0 3.9-2.3 4.7-4.6 5 .4.3.7.9.7 1.9V21c0 .3.2.6.7.5A10 10 0 0 0 12 2z"/></svg>`,
    search: P('<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/>'),
    copy: P('<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3"/>'),
    pen: P('<path d="M4 20l4-1 11-11-3-3L5 16z"/>'),
    hand: P('<path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V11M11 10V4.5a1.5 1.5 0 0 1 3 0V11M14 10.5V6a1.5 1.5 0 0 1 3 0v7c0 4-2.5 7-6 7-2.5 0-4-1.3-5.5-3.5L3.5 13a1.5 1.5 0 0 1 2.5-1.6L8 14"/>'),
    question: P('<path d="M4 5h16v11H9l-5 4z"/><path d="M10 9a2 2 0 1 1 2.5 1.9c-.4.2-.5.5-.5.9V12M12 14.5v.1"/>'),
    checksq: P('<rect x="3.5" y="3.5" width="17" height="17" rx="4"/><path d="M8 12.2l2.8 2.8L16.2 9.4"/>'),
    puzzle: P('<path d="M9 4.5a2 2 0 1 1 4 0V6h4a1 1 0 0 1 1 1v4h-1.5a2 2 0 1 0 0 4H18v4a1 1 0 0 1-1 1h-4v-1.5a2 2 0 1 0-4 0V20H5a1 1 0 0 1-1-1v-4h1.5a2 2 0 1 0 0-4H4V7a1 1 0 0 1 1-1h4z"/>'),
    done: P('<circle cx="12" cy="12" r="9"/><path d="M8 12.5l2.7 2.7L16 9.5"/>'),
    island: P('<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M9 5h6v2a1 1 0 0 1-1 1h-4a1 1 0 0 1-1-1z" fill="currentColor"/>'),
    cursor: P('<path d="M9 4h6M9 20h6M12 4v16"/>'),
    widgets: P('<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>'),
    menubar: P('<rect x="3" y="4" width="18" height="16" rx="2.5"/><path d="M3 9h18"/>'),
    overview: P('<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>'),
    terminal: P('<rect x="3" y="4" width="18" height="16" rx="2.5"/><path d="M7 9l3 3-3 3M12 15h5"/>'),
    calc: P('<rect x="5" y="3" width="14" height="18" rx="2.5"/><path d="M8 7h8M8.5 12h.01M12 12h.01M15.5 12h.01M8.5 16h.01M12 16h.01M15.5 16h.01"/>'),
    link: P('<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>'),
    text: P('<path d="M5 6h14M5 10h14M5 14h10M5 18h7"/>'),
    code: P('<path d="M8 8l-4 4 4 4M16 8l4 4-4 4M13.5 5l-3 14"/>'),
  };
  function paintIcons(root = document) {
    $$("[data-icon]", root).forEach(el => { if (!el.dataset.painted) { el.innerHTML = ICONS[el.dataset.icon] || ""; el.dataset.painted = "1"; } });
  }

  // ---------- Language ----------
  const TEXT = {
    en: {
      menuFile: "File", menuEdit: "Edit", menuView: "View", menuWindow: "Window", menuHelp: "Help",
      tabHome: "Home", tabMedia: "Media", tabUsage: "AI usage", tabMarkets: "Markets",
      meetingTitle: "Design review", join: "Join", due: "3 due today", todo1: "· Send the Q3 invoice", todo2: "· Reply to Lena's doc",
      qCapture: "Capture", qColor: "Color", qClips: "Clips", qTranslate: "Translate", qAI: "Ask AI",
      u5h: "5 hours", uWeek: "This week", uReset2h: "resets in 2 h", uReset3h: "resets in 3 h", uReset4d: "resets in 4 days", uReset6d: "resets in 6 days", uTokens: "Tokens today",
      hintTitle: "Try the notch", hintBody: "Point at the black island at the top of the screen.",
      welcomeTitle: "Altools is running", welcomeBody: "This page is a live demo. Hover the notch, press ⌥ Space, select text in Notes, or open Settings and switch modules off.", openSettings: "Open Settings",
      iconSettings: "Altools Settings", iconNotes: "Notes", iconDownload: "Download",
      keysTitle: "Try it here", kLauncher: "Launcher", kClips: "Clipboard", kCapture: "Capture", kHide: "Hidden icons", kNotch: "Notch",
      notesTitle: "Notes — select some text", annotateTitle: "Annotate", settingsTitle: "Altools Settings",
      note1: "The quick brown fox jumps over the lazy dog, then naps in the warm afternoon sun.",
      note2: "Ship small changes often; a release that fixes one thing is easier to trust than one that fixes ten.",
      note3: "Meeting moved to Thursday at 3pm, room 4B. Bring the Q4 numbers.",
      selCopy: "Copy", selTranslate: "Translate", selExplain: "Explain", selRewrite: "Rewrite", selReplace: "Replace",
      capTip: "Drag to capture an area · Esc cancels",
      mTagline: "A notch island, launcher, clipboard, AI and menu-bar tools in one native Mac app.", mDownload: "Download for macOS", mNote: "Open this page on a Mac to try the live desktop demo.",
      startsIn: m => `Starts in ${m} min`, startsNow: "Starting now",
      lnPlaceholder: "Search apps, commands, clipboard — or type math", lnAIPlaceholder: "Ask Claude Code anything…", lnClipPlaceholder: "Search clipboard history",
      lnApps: "Apps", lnCommands: "Commands", lnClipboard: "Recent clipboard", lnHintSearch: "↩ open · ⇥ ask AI · ⌥⇧V clipboard", lnHintAI: "↩ send · esc back", lnHintClip: "↩ paste · esc close",
      lnAskAI: q => `Ask AI: “${q}”`, lnCopyResult: "Copy result", toolsUsed: "Used 2 tools", readOnly: "Read-only",
      aiAnswer: "Your Mac is fine: 9.4 GB of 16 GB is in use.\n\n1. Xcode — 3.1 GB, mostly indexing\n2. Safari — 1.8 GB across 24 tabs\n3. OrbStack — 1.2 GB\n\nTo free Safari's memory, run `killall -HUP \"Safari Web Content\"`.",
      aiQuestion: "Which apps use the most memory right now?",
      pasted: "Pasted", copied: "Copied", colorCopied: c => `Copied ${c}`, captured: "Captured — annotate, copy or pin",
      off: name => `${name} is switched off in Settings`,
      translateTitle: "Translate → 中文", explainTitle: "Explain", rewriteTitle: "Rewrite",
      replaced: "Replaced the selection",
      cmdCapture: "Capture Area", cmdOCR: "Capture Text (OCR)", cmdClipboard: "Clipboard History", cmdAsk: "Ask AI", cmdSettings: "Altools Settings", cmdNotch: "Open the Notch", cmdHide: "Show Hidden Menu-Bar Icons",
      agentApproval: "Needs approval", agentQuestion: "Has a question", agentDone: "Finished",
      termAllow: "Yes, run it", termDeny: "No", termAnswered: "Answered. The card is gone from the notch.",
      stOverview: "Overview", stModules: "Modules", stOverviewTag: "Every module can be switched off. Try it: the desktop changes with it.",
      liveTag: "live on this page",
      selTickTick: "Add to TickTick",
      ttToday: n => n ? `${n} for today` : "All clear today", ttOverdue: n => `${n} overdue`, ttSecOverdue: "Overdue", ttSecToday: "Today", ttSecTomorrow: "Tomorrow", ttSecLater: "Later",
      ttHint: "Add one: <kbd>⌥ Space</kbd> tt buy milk tomorrow 3pm #Home !high", ttAdd: x => `Add “${x}”`, ttAdded: "Added", ttDone: x => `Done: ${x}`, ttComplete: "Complete",
      ttInbox: "Inbox", ttHigh: "High", ttMed: "Medium", ttLow: "Low", ttTypeTask: "Type a task: tt call mom tomorrow 6pm", lnPlugins: "Plugins", ttLauncherRow: "Add a TickTick task", ttLauncherHint: "type tt …",
      ttWhenToday: "Today", ttWhenTomorrow: "Tomorrow", ttWhenYesterday: "Yesterday",
    },
    zh: {
      menuFile: "文件", menuEdit: "编辑", menuView: "显示", menuWindow: "窗口", menuHelp: "帮助",
      tabHome: "主页", tabMedia: "媒体", tabUsage: "AI 用量", tabMarkets: "行情",
      meetingTitle: "设计评审", join: "加入", due: "今天 3 项到期", todo1: "· 发出第三季度发票", todo2: "· 回复 Lena 的文档",
      qCapture: "截图", qColor: "取色", qClips: "剪贴板", qTranslate: "翻译", qAI: "问 AI",
      u5h: "5 小时", uWeek: "本周", uReset2h: "2 小时后重置", uReset3h: "3 小时后重置", uReset4d: "4 天后重置", uReset6d: "6 天后重置", uTokens: "今日 token",
      hintTitle: "试试刘海", hintBody: "把鼠标移到屏幕顶部的黑色小岛上。",
      welcomeTitle: "Altools 正在运行", welcomeBody: "这个页面是一台可以操作的演示 Mac：悬停刘海、按 ⌥ Space、在笔记里划词，或者打开设置关掉某个模块。", openSettings: "打开设置",
      iconSettings: "Altools 设置", iconNotes: "笔记", iconDownload: "下载",
      keysTitle: "在这里试试", kLauncher: "启动器", kClips: "剪贴板", kCapture: "截图", kHide: "隐藏的图标", kNotch: "刘海",
      notesTitle: "笔记 — 选中一段文字", annotateTitle: "标注", settingsTitle: "Altools 设置",
      note1: "敏捷的棕色狐狸跳过了那只懒狗，然后在温暖的午后阳光下打了个盹。",
      note2: "小步快发；只修一件事的版本，比一次修十件的更让人放心。",
      note3: "会议改到周四下午 3 点，4B 会议室。请带上第四季度的数据。",
      selCopy: "复制", selTranslate: "翻译", selExplain: "解释", selRewrite: "改写", selReplace: "替换",
      capTip: "拖动选取区域 · Esc 取消",
      mTagline: "刘海岛、启动器、剪贴板、AI 和菜单栏工具，集成在一个原生 Mac 应用里。", mDownload: "下载 macOS 版", mNote: "在 Mac 上打开这个页面，可以体验可操作的桌面演示。",
      startsIn: m => `${m} 分钟后开始`, startsNow: "正在开始",
      lnPlaceholder: "搜索应用、命令、剪贴板，或输入算式", lnAIPlaceholder: "问 Claude Code 任何问题…", lnClipPlaceholder: "搜索剪贴板历史",
      lnApps: "应用", lnCommands: "命令", lnClipboard: "最近的剪贴板", lnHintSearch: "↩ 打开 · ⇥ 问 AI · ⌥⇧V 剪贴板", lnHintAI: "↩ 发送 · esc 返回", lnHintClip: "↩ 粘贴 · esc 关闭",
      lnAskAI: q => `问 AI：“${q}”`, lnCopyResult: "复制结果", toolsUsed: "调用了 2 个工具", readOnly: "只读",
      aiAnswer: "你的 Mac 状态正常：16 GB 内存用了 9.4 GB。\n\n1. Xcode — 3.1 GB，主要在建索引\n2. Safari — 1.8 GB，开着 24 个标签页\n3. OrbStack — 1.2 GB\n\n想释放 Safari 的内存，可以运行 `killall -HUP \"Safari Web Content\"`。",
      aiQuestion: "现在哪些应用最占内存？",
      pasted: "已粘贴", copied: "已复制", colorCopied: c => `已复制 ${c}`, captured: "已截图：可以标注、复制或钉在屏幕上",
      off: name => `${name} 已在设置里关闭`,
      translateTitle: "翻译 → English", explainTitle: "解释", rewriteTitle: "改写",
      replaced: "已替换选中的文字",
      cmdCapture: "截取区域", cmdOCR: "截图识别文字", cmdClipboard: "剪贴板历史", cmdAsk: "问 AI", cmdSettings: "Altools 设置", cmdNotch: "打开刘海", cmdHide: "显示隐藏的菜单栏图标",
      agentApproval: "需要批准", agentQuestion: "有问题要问", agentDone: "已完成",
      termAllow: "可以，运行", termDeny: "不行", termAnswered: "已回答，刘海上的卡片随之消失。",
      stOverview: "总览", stModules: "模块", stOverviewTag: "每个模块都可以关掉。试试看：桌面会跟着变。",
      liveTag: "本页可体验",
      selTickTick: "添加到滴答清单",
      ttToday: n => n ? `今天 ${n} 项` : "今天没有待办", ttOverdue: n => `过期 ${n}`, ttSecOverdue: "已过期", ttSecToday: "今天", ttSecTomorrow: "明天", ttSecLater: "以后",
      ttHint: "添加：<kbd>⌥ Space</kbd> tt 明天下午3点 开会 #工作 !高", ttAdd: x => `添加「${x}」`, ttAdded: "已添加", ttDone: x => `已完成：${x}`, ttComplete: "完成",
      ttInbox: "收集箱", ttHigh: "高", ttMed: "中", ttLow: "低", ttTypeTask: "输入任务：tt 明天下午6点 给妈妈打电话", lnPlugins: "插件", ttLauncherRow: "添加滴答清单任务", ttLauncherHint: "输入 tt …",
      ttWhenToday: "今天", ttWhenTomorrow: "明天", ttWhenYesterday: "昨天",
    },
  };
  let lang = store.get("altools-lang") || ((navigator.language || "").toLowerCase().startsWith("zh") ? "zh" : "en");
  const t = (k, ...a) => { const v = TEXT[lang][k] ?? TEXT.en[k] ?? k; return typeof v === "function" ? v(...a) : v; };
  function applyLang() {
    document.documentElement.lang = lang;
    $$("[data-i18n]").forEach(el => { el.textContent = t(el.dataset.i18n); });
    $("#lang-btn").textContent = lang === "zh" ? "中" : "EN";
    renderMarkets(); renderTickTick(); renderSettings(); renderAgentStrip(); updateMeeting(); renderTerminal();
    if (!$("#launcher").hidden) renderLauncher();
  }

  // ---------- Module state (what Settings switches) ----------
  const MODULES = [
    { id: "notch", icon: "island", color: "--green", name: { en: "Notch", zh: "刘海" }, tag: { en: "What is happening now, beside the notch.", zh: "刘海旁边显示正在发生的事。" },
      caps: [
        { id: "agents", live: true, en: ["Agent alerts", "A card drops when a tuios agent needs approval, asks a question or finishes."], zh: ["Agent 提醒", "tuios 里的 agent 需要批准、提问或完成时，弹出卡片。"] },
        { id: "nowplaying", live: true, en: ["Now playing", "Cover, title and playback controls in the ears."], zh: ["正在播放", "封面、歌名和播放控制显示在刘海两侧。"] },
        { id: "usage", en: ["AI usage", "Claude Code and Codex plan quotas and tokens today."], zh: ["AI 用量", "Claude Code 和 Codex 的额度与今日 token。"] },
        { id: "meetings", en: ["Meetings", "A countdown before meetings, with a Join button."], zh: ["会议", "会议前倒计时，附带加入按钮。"] },
      ] },
    { id: "plugins", icon: "puzzle", color: "--cyan", name: { en: "Plugins", zh: "插件" }, tag: { en: "A folder with plugin.json and a script in any language. Plugins can use the notch, the menu bar, the launcher, hotkeys and selected text.", zh: "一个文件夹，放 plugin.json 和任意语言的脚本。插件可以用刘海、菜单栏、启动器、快捷键和划词。" },
      caps: [
        { id: "markets", live: true, en: ["Markets (built in)", "Crypto, US and HK stocks on Home and in their own tab."], zh: ["行情（内置）", "加密货币、美股、港股，显示在主页和行情页。"] },
        { id: "ticktick", live: true, en: ["TickTick / 滴答清单", "Today's tasks in their own tab; add with tt in the launcher or from selected text."], zh: ["滴答清单 / TickTick", "今天的任务有自己的标签页；在启动器输入 tt 或划词添加。"] },
        { id: "texttools", en: ["Text tools", "Format JSON from selected text, ⌃⌥U for a UUID, b64 in the launcher."], zh: ["文本工具", "划词格式化 JSON，⌃⌥U 生成 UUID，启动器里 b64 编解码。"] },
      ] },
    { id: "launcher", icon: "search", color: "--purple", name: { en: "Launcher", zh: "启动器" }, tag: { en: "One box for apps, commands, maths, clipboard and AI.", zh: "一个输入框：应用、命令、算式、剪贴板和 AI。" },
      caps: [
        { id: "launcher", live: true, en: ["⌥ Space launcher", "Search apps and commands, or type maths."], zh: ["⌥ Space 启动器", "搜索应用和命令，或者直接输入算式。"] },
        { id: "clipboard", live: true, en: ["Clipboard history (⌥⇧V)", "Text, links and images; password managers are skipped."], zh: ["剪贴板历史（⌥⇧V）", "文字、链接、图片；跳过密码管理器的内容。"] },
        { id: "ai", live: true, en: ["Ask AI (⇥)", "Through your Claude Code or Codex CLI."], zh: ["问 AI（⇥）", "通过你本机的 Claude Code 或 Codex CLI。"] },
      ] },
    { id: "selection", icon: "cursor", color: "--blue", name: { en: "Selection", zh: "划词" }, tag: { en: "Actions on selected text, anywhere.", zh: "在任何地方对选中的文字操作。" },
      caps: [
        { id: "selection", live: true, en: ["Selection bar", "Select text and a small bar appears."], zh: ["划词工具条", "选中文字就会出现小工具条。"] },
        { id: "replace", en: ["Replace the selection", "Put the result back where the text was."], zh: ["替换选中文字", "把结果直接放回原处。"] },
      ] },
    { id: "capture", icon: "capture", color: "--red", name: { en: "Capture", zh: "截图" }, tag: { en: "Screenshots to annotate, pin or read text from.", zh: "截图后标注、钉住或识别文字。" },
      caps: [
        { id: "capture", live: true, en: ["Capture area (⌥⇧A)", "Drag an area, then annotate, copy, save or pin."], zh: ["截取区域（⌥⇧A）", "拖出区域后标注、复制、保存或钉住。"] },
        { id: "ocr", en: ["Recognize text (⌥⇧O)", "On-device OCR copies the text in an area."], zh: ["识别文字（⌥⇧O）", "在本机识别区域里的文字并复制。"] },
      ] },
    { id: "widgets", icon: "widgets", color: "--yellow", name: { en: "Widgets", zh: "小组件" }, tag: { en: "CPU, battery and network in the menu bar.", zh: "菜单栏里的 CPU、电池和网速。" },
      caps: [
        { id: "widgets", live: true, en: ["Menu-bar widgets", "Each opens its own panel on the real app."], zh: ["菜单栏小组件", "在真实应用里点开各有面板。"] },
      ] },
    { id: "menubar", icon: "menubar", color: "--orange", name: { en: "Menu Bar", zh: "菜单栏" }, tag: { en: "Hide the menu-bar icons you rarely need.", zh: "隐藏不常用的菜单栏图标。" },
      caps: [
        { id: "hider", live: true, en: ["Hide icons", "Click the dot or press ⌥B to show them again."], zh: ["隐藏图标", "点小圆点或按 ⌥B 重新显示。"] },
      ] },
  ];
  const state = { modules: {}, caps: {} };
  MODULES.forEach(m => { state.modules[m.id] = true; m.caps.forEach(c => { state.caps[c.id] = true; }); });
  const on = (cap, mod) => state.modules[mod] && state.caps[cap];
  const modName = id => MODULES.find(m => m.id === id).name[lang];

  // ---------- Toast ----------
  let toastTimer;
  function toast(html) {
    const el = $("#toast");
    el.innerHTML = html; el.hidden = false;
    clearTimeout(toastTimer); toastTimer = setTimeout(() => { el.hidden = true; }, 2200);
  }

  // ---------- Clock, widgets ----------
  function tick() {
    const d = new Date();
    const weekday = d.toLocaleDateString(lang === "zh" ? "zh-CN" : "en-US", { weekday: "short" });
    const day = lang === "zh" ? `${d.getMonth() + 1}月${d.getDate()}日 ${weekday}` : `${weekday} ${d.getDate()}`;
    const time = d.toLocaleTimeString(lang === "zh" ? "zh-CN" : "en-US", { hour: "numeric", minute: "2-digit" });
    $("#clock").textContent = `${day} ${time}`;
    $("#w-cpu b").textContent = `${8 + Math.round(Math.random() * 14)}%`;
    const up = (Math.random() * 4).toFixed(1), down = Math.round(20 + Math.random() * 180);
    $("#w-net").innerHTML = `<i>${up} KB/s ↑</i><i>${down} KB/s ↓</i>`;
  }

  // ---------- Hidden menu-bar icons ----------
  let revealed = false, revealTimer;
  function setRevealed(v) {
    revealed = v;
    $("#hidden-icons").classList.toggle("tucked", !v);
    $("#hide-dot").classList.toggle("revealed", v);
    clearTimeout(revealTimer);
    if (v) revealTimer = setTimeout(() => setRevealed(false), 6000);
  }
  function toggleHidden() {
    if (!state.modules.menubar || !state.caps.hider) return toast(t("off", modName("menubar")));
    setRevealed(!revealed);
  }

  // ---------- Notch ----------
  const notch = $("#notch");
  let collapseTimer, cardTimer;
  function expand() {
    if (!state.modules.notch) return;
    clearTimeout(collapseTimer);
    hideCard(true);
    notch.classList.add("expanded");
    $("#notch-hint").classList.add("gone");
  }
  function collapse() { notch.classList.remove("expanded"); }
  notch.addEventListener("mouseenter", expand);
  notch.addEventListener("mouseleave", () => { collapseTimer = setTimeout(collapse, 350); });
  $$(".tabs button").forEach(b => b.addEventListener("click", () => showTab(b.dataset.tab)));
  function showTab(name) {
    $$(".tabs button").forEach(b => b.classList.toggle("on", b.dataset.tab === name));
    $$(".pane").forEach(p => { p.hidden = p.dataset.pane !== name; });
  }
  $("#markets-mini").addEventListener("click", () => showTab("markets"));

  // Usage segments
  $$(".seg").forEach(s => { const v = +s.dataset.v; s.innerHTML = Array.from({ length: 20 }, (_, i) => `<i class="${i < Math.round(v / 5) ? "on" : ""}"></i>`).join(""); });

  // Meeting countdown
  const meetingAt = Date.now() + 12 * 60 * 1000;
  function updateMeeting() {
    const m = Math.max(0, Math.ceil((meetingAt - Date.now()) / 60000));
    $("#meeting-left").textContent = m > 0 ? t("startsIn", m) : t("startsNow");
  }

  // Markets: a random walk around plausible prices.
  const MARKETS = [
    { m: "Crypto", code: "BTCUSDT", name: { en: "Bitcoin", zh: "比特币" }, px: 98420, ch: 2.31 },
    { m: "Crypto", code: "ETHUSDT", name: { en: "Ether", zh: "以太坊" }, px: 3612.5, ch: -1.08 },
    { m: "US", code: "AAPL", name: { en: "Apple", zh: "苹果" }, px: 231.47, ch: 0.86 },
    { m: "US", code: "NVDA", name: { en: "Nvidia", zh: "英伟达" }, px: 142.19, ch: 3.42 },
    { m: "HK", code: "00700", name: { en: "Tencent", zh: "腾讯控股" }, px: 412.6, ch: -0.53 },
    { m: "Crypto", code: "SOLUSDT", name: { en: "Solana", zh: "Solana" }, px: 186.3, ch: 4.12 },
  ];
  const fmt = p => p >= 10000 ? p.toFixed(0) : p >= 100 ? p.toFixed(2) : p.toFixed(3);
  const chg = c => `<small class="${c >= 0 ? "up" : "down"}">${c >= 0 ? "+" : ""}${c.toFixed(2)}%</small>`;
  function stepMarkets() {
    MARKETS.forEach(q => { const d = (Math.random() - .5) * .0016; q.px *= 1 + d; q.ch += d * 100; });
    renderMarkets();
  }
  function renderMarkets() {
    $("#markets-mini").innerHTML = MARKETS.slice(0, 3).map(q => `<div class="mm-row"><b>${q.code}</b><span>${fmt(q.px)}${chg(q.ch)}</span></div>`).join("");
    $("#markets-grid").innerHTML = MARKETS.map(q => `<div class="mk"><span class="badge">${q.m}</span><div class="nm"><b>${q.code}</b><small>${q.name[lang]}</small></div><div class="px"><b>${fmt(q.px)}</b>${chg(q.ch)}</div></div>`).join("");
    const show = on("markets", "plugins");
    $("#markets-mini").style.display = show ? "" : "none";
    $("#tab-markets").style.display = show ? "" : "none";
    if (!show && $("#tab-markets").classList.contains("on")) showTab("home");
  }

  // ---------- TickTick plugin ----------
  const TASKS = [
    { title: { en: "Renew the passport photos", zh: "重拍护照照片" }, list: { en: "Personal", zh: "个人" }, day: -1, prio: 5 },
    { title: { en: "Send the Q3 invoice", zh: "发出第三季度发票" }, list: { en: "Work", zh: "工作" }, day: 0, time: "15:00", prio: 3 },
    { title: { en: "Reply to Lena's doc", zh: "回复 Lena 的文档" }, list: { en: "Work", zh: "工作" }, day: 0, time: "17:30", prio: 0 },
    { title: { en: "Book the dentist", zh: "预约牙医" }, list: { en: "Personal", zh: "个人" }, day: 1, prio: 0 },
    { title: { en: "Plan the offsite", zh: "规划团建" }, list: { en: "Work", zh: "工作" }, day: 4, prio: 1 },
  ];
  const ttLabel = x => typeof x === "string" ? x : x[lang];
  const ttWhen = x => {
    const d = x.day === 0 ? t("ttWhenToday") : x.day === 1 ? t("ttWhenTomorrow") : x.day === -1 ? t("ttWhenYesterday") : `+${x.day}d`;
    return x.time ? (x.day === 0 ? x.time : `${d} ${x.time}`) : d;
  };
  const PRIO_COLOR = { 5: "var(--red)", 3: "var(--yellow)", 1: "var(--blue)" };
  function renderTickTick() {
    const show = on("ticktick", "plugins");
    $("#tab-ticktick").style.display = show ? "" : "none";
    if (!show && $("#tab-ticktick").classList.contains("on")) showTab("home");
    const open = TASKS.filter(x => !x.done);
    const over = open.filter(x => x.day < 0), today = open.filter(x => x.day === 0);
    const groups = [["ttSecOverdue", TASKS.filter(x => x.day < 0), "red"], ["ttSecToday", TASKS.filter(x => x.day === 0), ""],
                    ["ttSecTomorrow", TASKS.filter(x => x.day === 1), ""], ["ttSecLater", TASKS.filter(x => x.day > 1), ""]];
    let html = `<div class="tt-head"><b>${t("ttToday", over.length + today.length)}</b>${over.length ? `<span class="pill-red">${t("ttOverdue", over.length)}</span>` : ""}</div>`;
    for (const [key, list, cls] of groups) {
      if (!list.length) continue;
      html += `<div class="tt-sec ${cls}">${t(key)}<i>${list.filter(x => !x.done).length}</i></div>`;
      for (const x of list) {
        const i = TASKS.indexOf(x);
        html += `<div class="tt-row ${x.day < 0 ? "over" : ""} ${x.done ? "done" : ""} ${x.fresh ? "fresh" : ""}"><span class="ck" data-tt="${i}" style="color:${PRIO_COLOR[x.prio] || "rgba(255,255,255,.4)"}" title="${t("ttComplete")}"></span><span class="ti">${ttLabel(x.title)}</span><span class="ls">${ttLabel(x.list)}</span><span class="du">${ttWhen(x)}</span></div>`;
      }
    }
    html += `<div class="tt-hint">${t("ttHint")}</div>`;
    $("#tt-list").innerHTML = html;
    $$("[data-tt]").forEach(el => el.addEventListener("click", e => { e.stopPropagation(); completeTask(+el.dataset.tt); }));
  }
  function completeTask(i) {
    const x = TASKS[i];
    if (!x || x.done) return;
    x.done = true; renderTickTick();
    toast(t("ttDone", ttLabel(x.title)));
    setTimeout(() => { const j = TASKS.indexOf(x); if (j >= 0) TASKS.splice(j, 1); renderTickTick(); }, 1400);
  }
  // A small version of the plugin's quick add: day, time, #list and !priority come out of the text.
  const WEEK = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6, "日": 0, "天": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6 };
  function parseTask(text) {
    let s = " " + text.trim() + " ", day = null, time = null, list = null, prio = 0;
    const take = (re, fn) => { const m = s.match(re); if (m) { s = s.replace(m[0], " \u0001 "); fn(m); } };
    take(/\s!(\S+)/, m => { prio = { high: 5, h: 5, "1": 5, "高": 5, med: 3, m: 3, "2": 3, "中": 3, low: 1, l: 1, "3": 1, "低": 1 }[m[1].toLowerCase()] || 0; });
    take(/\s#(\S+)/, m => { list = m[1]; });
    take(/\s(\d{1,2})(?::(\d\d))?\s*(am|pm)(?=[\s,.，。])/i, m => { time = [(+m[1] % 12) + (m[3].toLowerCase() === "pm" ? 12 : 0), +(m[2] || 0)]; });
    if (!time) take(/(上午|早上|中午|下午|晚上)?\s*(\d{1,2})\s*[点:：]\s*(半|\d\d)?/, m => {
      let h = +m[2]; const min = m[3] === "半" ? 30 : +(m[3] || 0);
      if ((m[1] === "下午" || m[1] === "晚上") && h < 12) h += 12;
      if (!m[1] && h >= 1 && h <= 7) h += 12;
      time = [h, min];
    });
    take(/今天|\stoday\s/i, () => { day = 0; });
    if (day === null) take(/明天|\stomorrow\s|\stmr\s/i, () => { day = 1; });
    if (day === null) take(/后天/, () => { day = 2; });
    if (day === null) take(/(?:周|星期)([一二三四五六日天])|\s(sun|mon|tue|wed|thu|fri|sat)[a-z]*(?=[\s,.，。])/i, m => { day = (WEEK[m[1] || m[2].toLowerCase()] - new Date().getDay() + 7) % 7; });
    const hm = time ? `${String(time[0]).padStart(2, "0")}:${String(time[1]).padStart(2, "0")}` : null;
    if (hm && day === null) { const n = new Date(); day = time[0] * 60 + time[1] < n.getHours() * 60 + n.getMinutes() ? 1 : 0; }
    return { title: cleanTitle(s), day, time: hm, list, prio };
  }
  // Drops the gaps left by what was taken out, with an "at" / "on" / "by" that led into them.
  const cleanTitle = s => s.replace(/\s(?:at|on|by)\s+\u0001/gi, " ").replace(/\u0001/g, " ").replace(/\s+/g, " ")
    .replace(/\s+([,，。.])/g, "$1").replace(/^[\s,，。.]+|[\s,，。.]+$/g, "");
  function describeTask(p) {
    const parts = [];
    if (p.day !== null) parts.push(ttWhen({ day: p.day, time: p.time }).replace(/^(\d\d:\d\d)$/, `${t("ttWhenToday")} $1`));
    parts.push(p.list ? p.list : t("ttInbox"));
    if (p.prio) parts.push(t(p.prio === 5 ? "ttHigh" : p.prio === 3 ? "ttMed" : "ttLow"));
    return parts.join(" · ");
  }
  function addTask(text, keepTitle = false) {
    const p = parseTask(text);
    if (keepTitle) p.title = text.trim();
    if (!p.title) return;
    TASKS.forEach(x => { x.fresh = false; });
    TASKS.push({ title: p.title, list: p.list || t("ttInbox"), day: p.day === null ? 0 : p.day, time: p.time, prio: p.prio, fresh: true });
    TASKS.sort((a, b) => a.day - b.day || String(a.time || "99").localeCompare(String(b.time || "99")));
    renderTickTick();
    pluginCard(t("ttAdded"), `${p.title} · ${describeTask(p)}`);
  }
  // Plugin alert cards drop from the notch like agent cards; clicking opens the plugin's tab.
  function pluginCard(kind, text) {
    if (!state.modules.notch || notch.classList.contains("expanded")) return toast(`${kind}: ${text}`);
    const card = $("#agent-card");
    const color = "#4772fa";
    card.innerHTML = `<span class="ic" style="background:color-mix(in srgb, ${color} 26%, transparent);color:#8aa7ff" data-icon="checksq"></span>
      <span class="tx"><span class="row"><b>TickTick</b><span class="k" style="color:var(--green)">${kind}</span></span><span class="s">${text.replace(/</g, "&lt;")}</span></span>`;
    paintIcons(card); card.hidden = false; card.dataset.plugin = "ticktick";
    notch.classList.add("with-card");
    clearTimeout(cardTimer); cardTimer = setTimeout(() => hideCard(), 5000);
  }

  // ---------- Agent alerts ----------
  const AGENTS = [
    { kind: "approval", name: "api-server refactor", color: "--orange", icon: "hand",
      text: { en: "Run `npm test -- router` to check the new routes?", zh: "运行 `npm test -- router` 检查新的路由？" },
      term: { en: ["<span class='c'>●</span> Edited <span class='w'>src/router.ts</span> (+42 −17)", "<span class='c'>●</span> Edited <span class='w'>src/routes/orders.ts</span> (+8 −3)", "", "<span class='o'>Allow this command?</span>", "<span class='w'>  npm test -- router</span>"], zh: ["<span class='c'>●</span> 修改了 <span class='w'>src/router.ts</span>（+42 −17）", "<span class='c'>●</span> 修改了 <span class='w'>src/routes/orders.ts</span>（+8 −3）", "", "<span class='o'>允许运行这个命令吗？</span>", "<span class='w'>  npm test -- router</span>"] } },
    { kind: "question", name: "refund flow", color: "--orange", icon: "question",
      text: { en: "Should partial refunds keep the original currency, or convert to USD?", zh: "部分退款保留原币种，还是换算成美元？" },
      term: { en: ["<span class='c'>●</span> Read <span class='w'>billing/refunds.py</span>", "", "<span class='o'>Question:</span> Should partial refunds keep the original", "currency, or convert to USD?"], zh: ["<span class='c'>●</span> 读取了 <span class='w'>billing/refunds.py</span>", "", "<span class='o'>问题：</span>部分退款保留原币种，", "还是换算成美元？"] } },
    { kind: "done", name: "docs site", color: "--green", icon: "done",
      text: { en: "Added the Chinese README and fixed 3 broken links.", zh: "加上了中文 README，修好了 3 个失效链接。" },
      term: { en: ["<span class='g'>✓</span> Wrote <span class='w'>README.zh-CN.md</span>", "<span class='g'>✓</span> Fixed 3 links in <span class='w'>docs/</span>", "", "Done. Anything else?"], zh: ["<span class='g'>✓</span> 写好了 <span class='w'>README.zh-CN.md</span>", "<span class='g'>✓</span> 修好了 <span class='w'>docs/</span> 里的 3 个链接", "", "完成了，还有别的吗？"] } },
  ];
  const kindLabel = k => t(k === "approval" ? "agentApproval" : k === "question" ? "agentQuestion" : "agentDone");
  let waiting = [], agentIndex = 0, shownAgent = null;
  function agentCardHTML(a) {
    const color = `var(${a.color})`;
    return `<span class="ic" style="background:color-mix(in srgb, ${color} 22%, transparent);color:${color}" data-icon="${a.icon}"></span>
      <span class="tx"><span class="row"><b>${a.name}</b><span class="k" style="color:${color}">${kindLabel(a.kind)}</span></span><span class="s">${a.text[lang]}</span></span>`;
  }
  function nextAgent() {
    if (!on("agents", "notch") || notch.classList.contains("expanded") || !$("#launcher").hidden) return;
    const a = AGENTS[agentIndex++ % AGENTS.length];
    if (!waiting.includes(a)) waiting.push(a);
    shownAgent = a;
    const card = $("#agent-card");
    delete card.dataset.plugin;
    card.innerHTML = agentCardHTML(a); paintIcons(card); card.hidden = false;
    notch.classList.add("with-card");
    renderAgentStrip();
    clearTimeout(cardTimer); cardTimer = setTimeout(() => hideCard(), 9000);
  }
  function hideCard(instant) {
    clearTimeout(cardTimer);
    notch.classList.remove("with-card");
    setTimeout(() => { if (!notch.classList.contains("with-card")) $("#agent-card").hidden = true; }, instant ? 0 : 300);
  }
  $("#agent-card").addEventListener("click", e => {
    e.stopPropagation();
    if ($("#agent-card").dataset.plugin) { hideCard(true); expand(); showTab("ticktick"); return; }
    if (shownAgent) openAgent(shownAgent);
    hideCard();
  });
  function renderAgentStrip() {
    const strip = $("#agent-strip");
    const a = waiting[0];
    const show = a && on("agents", "notch");
    strip.hidden = !show; $("#quick").hidden = !!show;
    if (!show) return;
    const color = `var(${a.color})`;
    strip.style.background = `color-mix(in srgb, ${color} 16%, transparent)`;
    strip.innerHTML = `<span data-icon="${a.icon}" style="color:${color}"></span><b>${a.name}</b><span class="k" style="color:${color}">${kindLabel(a.kind)}</span><span class="s">${a.text[lang]}</span>${waiting.length > 1 ? `<span style="margin-left:auto;opacity:.6">+${waiting.length - 1}</span>` : ""}`;
    paintIcons(strip);
  }
  $("#agent-strip").addEventListener("click", () => { if (waiting[0]) openAgent(waiting[0]); collapse(); });
  let termAgent = null, termAnswered = false;
  function openAgent(a) {
    waiting = waiting.filter(x => x !== a); renderAgentStrip();
    termAgent = a; termAnswered = false;
    renderTerminal();
    openWindow("terminal");
  }
  function renderTerminal() {
    const a = termAgent;
    if (!a) return;
    $("#term-title").textContent = `tuios — ${a.name}`;
    const lines = a.term[lang].map(l => `<div>${l || "&nbsp;"}</div>`).join("");
    const prompt = `<div><span class='c'>›</span> claude</div>`;
    const answered = `<div class="g" style="margin-top:10px">✓ ${t("termAnswered")}</div>`;
    const opts = a.kind !== "approval" ? "" : termAnswered ? answered
      : `<div class="opts"><button data-ans="1">${t("termAllow")}</button><button data-ans="0">${t("termDeny")}</button></div>`;
    $("#term-body").innerHTML = prompt + lines + opts;
    $$("#term-body .opts button").forEach(b => b.addEventListener("click", () => { termAnswered = true; renderTerminal(); }));
  }

  // ---------- Windows ----------
  let z = 20;
  function openWindow(name) {
    const w = $(`[data-win="${name}"]`);
    w.hidden = false; w.style.zIndex = ++z;
    if (name === "settings") renderSettings();
  }
  $$(".window").forEach(w => {
    w.addEventListener("mousedown", () => { w.style.zIndex = ++z; });
    $(".lights .close", w).addEventListener("click", e => { e.stopPropagation(); w.hidden = true; });
    const bar = $(".titlebar", w);
    bar.addEventListener("mousedown", e => {
      if (e.target.closest(".lights")) return;
      const sx = e.clientX - w.offsetLeft, sy = e.clientY - w.offsetTop;
      const move = ev => { w.style.left = `${Math.max(-200, ev.clientX - sx)}px`; w.style.top = `${Math.max(30, ev.clientY - sy)}px`; };
      const up = () => { removeEventListener("mousemove", move); removeEventListener("mouseup", up); };
      addEventListener("mousemove", move); addEventListener("mouseup", up);
    });
  });
  $$("[data-open]").forEach(b => b.addEventListener("click", () => {
    const what = b.dataset.open;
    if (what === "launcher") openLauncher("search"); else openWindow(what);
  }));

  // ---------- Settings ----------
  let stPage = "overview";
  const tonal = (icon, color, cls = "") => `<span class="tonal ${cls}" style="background:color-mix(in srgb, var(${color}) 16%, transparent);color:var(${color})" data-icon="${icon}"></span>`;
  function renderSettings() {
    const side = $("#st-side"), main = $("#st-main");
    side.innerHTML = `<button data-p="overview" class="${stPage === "overview" ? "on" : ""}">${tonal("overview", "--blue")}${t("stOverview")}</button><h6>${t("stModules")}</h6>` +
      MODULES.map(m => `<button data-p="${m.id}" class="${stPage === m.id ? "on" : ""} ${state.modules[m.id] ? "" : "off"}">${tonal(m.icon, state.modules[m.id] ? m.color : "--faint")}${m.name[lang]}</button>`).join("");
    if (stPage === "overview") {
      main.innerHTML = `<div class="st-head"><h2>${t("stOverview")}</h2></div><p class="st-tag">${t("stOverviewTag")}</p><div class="ov-grid">` +
        MODULES.map(m => `<div class="ov-card ${state.modules[m.id] ? "" : "off"}"><div class="top">${tonal(m.icon, m.color)}<b>${m.name[lang]}</b><span class="switch ${state.modules[m.id] ? "on" : ""}" data-mod="${m.id}"></span></div><p>${m.tag[lang]}</p></div>`).join("") + `</div>`;
    } else {
      const m = MODULES.find(x => x.id === stPage);
      main.innerHTML = `<div class="st-head">${tonal(m.icon, m.color, "lg")}<h2>${m.name[lang]}</h2><span class="switch ${state.modules[m.id] ? "on" : ""}" data-mod="${m.id}"></span></div><p class="st-tag">${m.tag[lang]}</p>` +
        m.caps.map(c => `<div class="st-row ${c.live ? "live" : ""}"><div><b>${c[lang][0]}</b><span>${c[lang][1]}</span></div><span class="switch ${state.caps[c.id] ? "on" : ""}" data-cap="${c.id}"></span></div>`).join("");
    }
    paintIcons(side); paintIcons(main);
    $$("button[data-p]", side).forEach(b => b.addEventListener("click", () => { stPage = b.dataset.p; renderSettings(); }));
    $$("[data-mod]", main).forEach(s => s.addEventListener("click", e => { e.stopPropagation(); state.modules[s.dataset.mod] = !state.modules[s.dataset.mod]; applyState(); }));
    $$("[data-cap]", main).forEach(s => s.addEventListener("click", () => { state.caps[s.dataset.cap] = !state.caps[s.dataset.cap]; applyState(); }));
  }
  function applyState() {
    notch.style.display = state.modules.notch ? "" : "none";
    if (!state.modules.notch) $("#notch-hint").classList.add("gone");
    $(".ears .left").style.visibility = on("nowplaying", "notch") ? "" : "hidden";
    $(".ears .right").style.visibility = on("nowplaying", "notch") ? "" : "hidden";
    $("#widgets").style.display = on("widgets", "widgets") ? "" : "none";
    const hider = on("hider", "menubar");
    $("#hide-dot").style.display = hider ? "" : "none";
    if (!hider) { $("#hidden-icons").classList.remove("tucked"); } else if (!revealed) { $("#hidden-icons").classList.add("tucked"); }
    if (!on("agents", "notch")) hideCard(true);
    renderMarkets(); renderTickTick(); renderAgentStrip(); renderSettings();
  }

  // ---------- Launcher ----------
  const APPS = [
    { n: "Safari", c: "t-blue-bg", i: "search" }, { n: "Mail", c: "t-blue-bg", i: "chat" }, { n: "Terminal", c: "t-dark-bg", i: "terminal" },
    { n: "Notes", c: "t-yellow-bg", i: "note", open: "notes" }, { n: "Calculator", c: "t-dark-bg", i: "calc" }, { n: "Music", c: "t-purple-bg", i: "music" },
  ];
  const COMMANDS = () => [
    { n: t("cmdAsk"), c: "t-purple-bg", i: "spark", run: () => setLnMode("ai") },
    { n: t("cmdClipboard"), c: "t-dark-bg", i: "clip", run: () => setLnMode("clip") },
    { n: t("cmdCapture"), c: "t-dark-bg", i: "capture", run: () => { closeLauncher(); startCapture(); } },
    { n: t("cmdOCR"), c: "t-dark-bg", i: "text", run: () => { closeLauncher(); startCapture(); } },
    { n: t("cmdNotch"), c: "t-dark-bg", i: "island", run: () => { closeLauncher(); expand(); } },
    { n: t("cmdHide"), c: "t-dark-bg", i: "menubar", run: () => { closeLauncher(); toggleHidden(); } },
    { n: t("cmdSettings"), c: "t-blue-bg", i: "gear", run: () => { closeLauncher(); openWindow("settings"); } },
  ];
  const CLIPS = [
    { v: "https://github.com/matyle/altools", i: "link", ago: "1 min" },
    { v: "func greet(name: String) -> String { \"Hello, \\(name)!\" }", i: "code", ago: "5 min" },
    { v: "Meeting moved to Thursday 3pm — room 4B.", i: "text", ago: "1 h" },
    { v: "#61AFEF", i: "drop", ago: "2 h" },
    { v: "brew install --cask altools", i: "terminal", ago: "1 d" },
  ];
  let lnMode = "search", lnSel = 0, lnItems = [];
  const input = $("#ln-q");
  function openLauncher(mode) {
    const cap = mode === "clip" ? "clipboard" : mode === "ai" ? "ai" : "launcher";
    if (!on(cap, "launcher")) return toast(t("off", modName("launcher")));
    hideCard(true); collapse(); hideSel();
    $("#launcher").hidden = false;
    setLnMode(mode);
  }
  function closeLauncher() { $("#launcher").hidden = true; input.blur(); }
  function setLnMode(mode) {
    lnMode = mode; input.value = ""; lnSel = 0;
    input.placeholder = t(mode === "ai" ? "lnAIPlaceholder" : mode === "clip" ? "lnClipPlaceholder" : "lnPlaceholder");
    $("#ln-mode").textContent = mode === "ai" ? "Claude Code" : mode === "clip" ? "⌥⇧V" : "";
    $("#ln-mode").style.display = mode === "search" ? "none" : "";
    $("#ln-foot-hint").textContent = t(mode === "ai" ? "lnHintAI" : mode === "clip" ? "lnHintClip" : "lnHintSearch");
    renderLauncher(); setTimeout(() => input.focus(), 0);
  }
  function mathResult(q) {
    if (!/^[\d\s+\-*/().^%]+$/.test(q) || !/\d\s*[+\-*/^%]\s*[\d(]/.test(q)) return null;
    try { const v = Function(`"use strict";return (${q.replace(/\^/g, "**")})`)(); return Number.isFinite(v) ? +v.toFixed(10) : null; } catch { return null; }
  }
  function item(x, extra = "") { return `<button class="ln-item" data-k="${lnItems.length - 1}"><span class="tile ${x.c || "t-dark-bg"}" data-icon="${x.i}"></span><b>${x.n}</b><small>${extra}</small></button>`; }
  function renderLauncher() {
    const q = input.value.trim(), list = $("#ln-list"); lnItems = [];
    let html = "";
    if (lnMode === "ai") {
      html = `<div class="ln-ai" id="ln-ai">${q || aiShown ? "" : `<div class="ln-sec" style="margin:0">${t("readOnly")}</div><div style="color:var(--dim)">${t("aiQuestion")}</div>`}</div>`;
      if (aiShown) html = aiShown;
    } else if (lnMode === "clip") {
      CLIPS.filter(c => !q || c.v.toLowerCase().includes(q.toLowerCase())).forEach(c => { lnItems.push({ run: () => { closeLauncher(); toast(`${t("pasted")}: ${c.v.slice(0, 28)}`); } }); html += item({ n: c.v, i: c.i, c: "t-dark-bg" }, c.ago); });
    } else if (/^tt(\s|$)/i.test(q) && on("ticktick", "plugins")) {
      const text = q.slice(2).trim(), p = parseTask(text);
      html += `<div class="ln-sec">TickTick</div>`;
      if (p.title) { lnItems.push({ run: () => { closeLauncher(); addTask(text); } }); html += item({ n: t("ttAdd", p.title.replace(/</g, "&lt;")), i: "checksq", c: "t-blue-bg" }, describeTask(p)); }
      else { lnItems.push({ run: () => {} }); html += item({ n: t("ttTypeTask"), i: "checksq", c: "t-blue-bg" }); }
      TASKS.filter(x => !x.done && (!p.title || ttLabel(x.title).toLowerCase().includes(p.title.toLowerCase()))).slice(0, 5).forEach(x => {
        lnItems.push({ run: () => { closeLauncher(); completeTask(TASKS.indexOf(x)); } });
        html += item({ n: ttLabel(x.title), i: "done", c: "t-dark-bg" }, `${t("ttComplete")} · ${ttWhen(x)}`);
      });
    } else {
      const m = mathResult(q);
      if (m !== null) { lnItems.push({ run: () => { closeLauncher(); toast(`${t("copied")} ${m}`); } }); html += `<button class="ln-item ln-calc" data-k="0"><span style="color:var(--dim)">${q} =</span><b>${m}</b></button>`; }
      const apps = APPS.filter(a => !q || a.n.toLowerCase().includes(q.toLowerCase()));
      const cmds = COMMANDS().filter(c => !q || c.n.toLowerCase().includes(q.toLowerCase()));
      if (!q) { html += `<div class="ln-sec">${t("lnClipboard")}</div>`; CLIPS.slice(0, 2).forEach(c => { lnItems.push({ run: () => { closeLauncher(); toast(`${t("pasted")}: ${c.v.slice(0, 28)}`); } }); html += item({ n: c.v, i: c.i }, c.ago); }); }
      if (apps.length) { html += `<div class="ln-sec">${t("lnApps")}</div>`; apps.forEach(a => { lnItems.push({ run: () => { closeLauncher(); if (a.open) openWindow(a.open); else toast(`${a.n}`); } }); html += item(a); }); }
      if (cmds.length) { html += `<div class="ln-sec">${t("lnCommands")}</div>`; cmds.forEach(c => { lnItems.push({ run: c.run }); html += item(c); }); }
      if (!q && on("ticktick", "plugins")) { html += `<div class="ln-sec">${t("lnPlugins")}</div>`; lnItems.push({ run: () => { input.value = "tt "; renderLauncher(); input.focus(); } }); html += item({ n: t("ttLauncherRow"), i: "checksq", c: "t-blue-bg" }, t("ttLauncherHint")); }
      if (q && m === null) { lnItems.push({ run: () => askAI(q) }); html += item({ n: t("lnAskAI", q), i: "spark", c: "t-purple-bg" }, "⇥"); }
    }
    list.innerHTML = html; paintIcons(list);
    $$(".ln-item", list).forEach((b, i) => { b.dataset.k = i; b.addEventListener("click", () => lnItems[i]?.run()); b.addEventListener("mousemove", () => { lnSel = i; markSel(); }); });
    lnSel = Math.min(lnSel, Math.max(0, lnItems.length - 1)); markSel();
  }
  function markSel() { $$(".ln-item").forEach((b, i) => b.classList.toggle("sel", i === lnSel)); $$(".ln-item")[lnSel]?.scrollIntoView({ block: "nearest" }); }
  let aiShown = "", typing;
  function askAI(q) {
    if (lnMode !== "ai") { lnMode = "ai"; setLnMode("ai"); }
    const question = q || t("aiQuestion");
    clearInterval(typing);
    const answer = t("aiAnswer");
    let n = 0;
    const draw = () => {
      const shown = answer.slice(0, n).replace(/`([^`]+)`/g, "<code>$1</code>");
      aiShown = `<div class="ln-ai"><div class="q">${question.replace(/</g, "&lt;")}</div><div class="tools">${t("toolsUsed")} · ${t("readOnly")}</div><div class="a">${shown}</div></div>`;
      $("#ln-list").innerHTML = aiShown;
    };
    typing = setInterval(() => { n += 3; draw(); if (n >= answer.length) clearInterval(typing); }, 16);
    input.value = "";
  }
  input.addEventListener("input", () => { lnSel = 0; if (lnMode !== "ai") renderLauncher(); });
  input.addEventListener("keydown", e => {
    if (e.key === "ArrowDown") { lnSel = Math.min(lnSel + 1, lnItems.length - 1); markSel(); e.preventDefault(); }
    else if (e.key === "ArrowUp") { lnSel = Math.max(lnSel - 1, 0); markSel(); e.preventDefault(); }
    else if (e.key === "Enter") { e.preventDefault(); if (lnMode === "ai") askAI(input.value.trim()); else lnItems[lnSel]?.run(); }
    else if (e.key === "Tab") { e.preventDefault(); if (lnMode === "search") { const q = input.value.trim(); setLnMode("ai"); aiShown = ""; if (q) askAI(q); else askAI(""); } }
    else if (e.key === "Escape") { e.preventDefault(); if (lnMode !== "search") { aiShown = ""; clearInterval(typing); setLnMode("search"); } else closeLauncher(); }
  });
  $("#launcher").addEventListener("mousedown", e => { if (e.target.id === "launcher") closeLauncher(); });

  // ---------- Selection ----------
  const TRANSLATIONS = {
    en: ["敏捷的棕色狐狸跳过了那只懒狗，然后在温暖的午后阳光下打了个盹。", "小步快发；只修一件事的版本，比一次修十件的更让人放心。", "会议改到周四下午 3 点，4B 会议室。请带上第四季度的数据。"],
    zh: ["The quick brown fox jumps over the lazy dog, then naps in the warm afternoon sun.", "Ship small changes often; a release that fixes one thing is easier to trust than one that fixes ten.", "Meeting moved to Thursday at 3pm, room 4B. Bring the Q4 numbers."],
  };
  const EXPLAIN = {
    en: ["A pangram: it uses every letter of the English alphabet, which is why it's used to test fonts and keyboards.", "Release advice: smaller releases are easier to review, test and roll back, so people trust them more.", "A schedule change: the meeting is now Thursday 3pm in room 4B, and you should bring the Q4 figures."],
    zh: ["这是英文“全字母句”的中文版，原句用到了全部 26 个字母，常用来测试字体和键盘。", "发布建议：版本越小越容易评审、测试和回滚，所以更让人信任。", "日程变更：会议改到周四下午 3 点、4B 会议室，需要带上第四季度的数据。"],
  };
  const REWRITE = {
    en: ["A nimble brown fox leaps over a sleepy dog, then dozes in the warm afternoon light.", "Release little and often: one fix per release is easier to trust than ten at once.", "Heads up: the meeting is now Thursday at 3pm in 4B. Please bring the Q4 numbers."],
    zh: ["一只灵巧的棕色狐狸跃过打盹的狗，随后在午后暖阳里眯了一会儿。", "少量多次地发布：每次只修一件事，比一次修十件更可靠。", "提醒一下：会议改到周四下午 3 点，地点 4B，记得带第四季度的数据。"],
  };
  let selInfo = null;
  function hideSel() { $("#selbar").hidden = true; }
  $("#notes-body").addEventListener("mouseup", () => setTimeout(() => {
    const s = getSelection(), text = s.toString().trim();
    if (!text) return hideSel();
    if (!on("selection", "selection")) return toast(t("off", modName("selection")));
    const range = s.getRangeAt(0), rect = range.getBoundingClientRect();
    const p = range.startContainer.parentElement.closest("p");
    selInfo = { text, index: $$("#notes-body p").indexOf(p), range: range.cloneRange() };
    const bar = $("#selbar");
    bar.hidden = false;
    bar.style.left = `${Math.max(8, rect.left + rect.width / 2 - bar.offsetWidth / 2)}px`;
    bar.style.top = `${rect.top - bar.offsetHeight - 10}px`;
  }, 0));
  document.addEventListener("mousedown", e => {
    if (!e.target.closest("#selbar, #selresult, #notes-body")) { hideSel(); }
  });
  $$("#selbar button").forEach(b => b.addEventListener("click", () => {
    const act = b.dataset.sel; hideSel();
    if (!selInfo) return;
    if (act === "copy") return toast(t("copied"));
    if (act === "ticktick") {
      if (!on("ticktick", "plugins")) return toast(t("off", modName("plugins")));
      getSelection().removeAllRanges();
      return addTask(selInfo.text.split(/[。.!?]/)[0].slice(0, 80), true);
    }
    const i = Math.max(0, selInfo.index);
    const out = act === "translate" ? TRANSLATIONS[lang][i] : act === "explain" ? EXPLAIN[lang][i] : REWRITE[lang][i];
    const box = $("#selresult");
    $("#sr-title").textContent = t(act === "translate" ? "translateTitle" : act === "explain" ? "explainTitle" : "rewriteTitle");
    $("#sr-src").textContent = selInfo.text.length > 90 ? selInfo.text.slice(0, 90) + "…" : selInfo.text;
    $("#sr-replace").style.display = act === "explain" ? "none" : "";
    box.hidden = false;
    const bar = $("#selbar");
    box.style.left = `${Math.min(innerWidth - 420, Math.max(8, parseFloat(bar.style.left)))}px`;
    box.style.top = `${Math.max(40, parseFloat(bar.style.top))}px`;
    let n = 0; const outEl = $("#sr-out"); outEl.textContent = "";
    clearInterval(box._t); box._t = setInterval(() => { n += 2; outEl.textContent = out.slice(0, n); if (n >= out.length) clearInterval(box._t); }, 18);
    box._out = out;
  }));
  $("#sr-close").addEventListener("click", () => { $("#selresult").hidden = true; });
  $("#sr-copy").addEventListener("click", () => { $("#selresult").hidden = true; toast(t("copied")); });
  $("#sr-replace").addEventListener("click", () => {
    const box = $("#selresult");
    if (selInfo?.range) { const r = selInfo.range; r.deleteContents(); r.insertNode(document.createTextNode(box._out)); getSelection().removeAllRanges(); }
    box.hidden = true; toast(t("replaced"));
  });

  // ---------- Capture ----------
  function startCapture() {
    if (!on("capture", "capture")) return toast(t("off", modName("capture")));
    collapse(); hideCard(true);
    const ov = $("#capture"), r = $("#cap-rect");
    ov.hidden = false; r.style.display = "none";
    let sx, sy, drag = false;
    ov.onmousedown = e => { drag = true; sx = e.clientX; sy = e.clientY; r.style.display = "block"; $(".cap-tip").style.display = "none"; };
    ov.onmousemove = e => { if (!drag) return; const x = Math.min(sx, e.clientX), y = Math.min(sy, e.clientY); Object.assign(r.style, { left: `${x}px`, top: `${y}px`, width: `${Math.abs(e.clientX - sx)}px`, height: `${Math.abs(e.clientY - sy)}px` }); };
    ov.onmouseup = () => { drag = false; endCapture(true); };
  }
  function endCapture(done) {
    const ov = $("#capture"); ov.hidden = true; $(".cap-tip").style.display = "";
    if (done) { openWindow("annotate"); toast(t("captured")); }
  }

  // ---------- Quick actions ----------
  $$("#quick button").forEach(b => b.addEventListener("click", () => {
    const a = b.dataset.action;
    if (a === "capture") startCapture();
    else if (a === "color") { const c = ["#61AFEF", "#C678DD", "#98C379", "#E5C07B", "#E06C75"][Math.floor(Math.random() * 5)]; toast(`<span class="sw" style="background:${c}"></span>${t("colorCopied", c)}`); }
    else if (a === "clips") openLauncher("clip");
    else if (a === "translate") { collapse(); openWindow("notes"); }
    else if (a === "ai") { openLauncher("ai"); aiShown = ""; askAI(""); }
  }));

  // ---------- Keyboard ----------
  document.addEventListener("keydown", e => {
    if (e.key === "Escape") {
      if (!$("#capture").hidden) return endCapture(false);
      if (!$("#selresult").hidden) return void ($("#selresult").hidden = true);
      if (notch.classList.contains("expanded")) return collapse();
    }
    if (!e.altKey || e.metaKey || e.ctrlKey) return;
    const k = e.code;
    if (k === "Space" && !e.shiftKey) { e.preventDefault(); $("#launcher").hidden ? openLauncher("search") : closeLauncher(); }
    else if (k === "Space" && e.shiftKey) { e.preventDefault(); openLauncher("ai"); aiShown = ""; askAI(""); }
    else if (k === "KeyV" && e.shiftKey) { e.preventDefault(); openLauncher("clip"); }
    else if (k === "KeyA" && e.shiftKey) { e.preventDefault(); startCapture(); }
    else if (k === "KeyB" && !e.shiftKey) { e.preventDefault(); toggleHidden(); }
    else if (k === "KeyN" && !e.shiftKey) { e.preventDefault(); notch.classList.contains("expanded") ? collapse() : expand(); }
  });

  // ---------- Misc wiring ----------
  $("#hide-dot").addEventListener("click", toggleHidden);
  $("#lang-btn").addEventListener("click", () => { lang = lang === "zh" ? "en" : "zh"; store.set("altools-lang", lang); applyLang(); tick(); });
  $("#welcome-open").addEventListener("click", () => { $("#welcome").classList.add("gone"); openWindow("settings"); });
  setTimeout(() => $("#welcome").classList.add("gone"), 14000);

  paintIcons();
  setRevealed(false);
  applyLang(); tick();
  setInterval(tick, 2000);
  setInterval(stepMarkets, 1500);
  setInterval(updateMeeting, 15000);
  setTimeout(nextAgent, 7000);
  setInterval(nextAgent, 22000);
  setTimeout(() => { if (!notch.classList.contains("expanded")) $("#notch-hint").classList.add("gone"); }, 12000);
})();
