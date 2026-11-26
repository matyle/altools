#!/usr/bin/osascript -l JavaScript
// Altools built-in plugin: market prices. Plain JavaScript for macOS's own osascript, so it
// needs nothing installed. Contract: PLUGINS.md.
ObjC.import("Foundation")

const env = $.NSProcessInfo.processInfo.environment
const getenv = key => { const v = env.objectForKey(key); return v ? ObjC.unwrap(v) : "" }
const zh = getenv("ALTOOLS_LANG") === "zh"
const dataDir = getenv("ALTOOLS_DATA_DIR") || "/tmp"
const app = Application.currentApplication()
app.includeStandardAdditions = true

const sh = cmd => { try { return app.doShellScript(cmd) } catch (e) { return "" } }
const q = s => "'" + String(s).replace(/'/g, "'\\''") + "'"
// curl honours the HTTP(S)_PROXY Altools passes; Tencent answers in GBK.
const fetch = (url, gbk) => sh("/usr/bin/curl -s -m 8 " + q(url) + (gbk ? " | /usr/bin/iconv -f GBK -t UTF-8" : ""))

const readJSON = path => { try { return JSON.parse(sh("/bin/cat " + q(path))) } catch (e) { return null } }
const writeJSON = (path, value) => sh("/bin/echo " + q(JSON.stringify(value)) + " > " + q(path))

const CRYPTO_NAMES = { "比特币": "BTC", bitcoin: "BTC", "以太坊": "ETH", ethereum: "ETH", ether: "ETH", solana: "SOL",
  "狗狗币": "DOGE", dogecoin: "DOGE", "瑞波": "XRP", ripple: "XRP", "币安币": "BNB", "莱特币": "LTC", litecoin: "LTC" }
const KNOWN_CRYPTO = ["BTC", "ETH", "SOL", "BNB", "XRP", "DOGE", "ADA", "TRX", "LTC", "DOT", "LINK", "AVAX", "SHIB", "TON", "SUI", "PEPE"]

// "BTC" / "腾讯" / "us:AAPL" → { market, code, name }. Names are looked up once and cached.
function resolve(entry, cache) {
  const raw = entry.trim()
  if (!raw) return null
  if (cache[raw]) return cache[raw]
  const lower = raw.toLowerCase()
  let found = null
  const prefixed = raw.match(/^(crypto|us|hk):(.+)$/i)
  if (prefixed) {
    const market = prefixed[1].toLowerCase()
    let code = prefixed[2].trim().toUpperCase()
    if (market === "crypto" && !/(USDT|USDC|BTC)$/.test(code)) code += "USDT"
    if (market === "hk") code = code.padStart(5, "0")
    found = { market, code, name: code }
  } else if (CRYPTO_NAMES[lower] || KNOWN_CRYPTO.includes(raw.toUpperCase()) || /USDT$|USDC$/i.test(raw)) {
    let code = (CRYPTO_NAMES[lower] || raw).toUpperCase()
    if (!/(USDT|USDC)$/.test(code)) code += "USDT"
    found = { market: "crypto", code, name: code }
  } else if (/^\d{1,5}$/.test(raw)) {
    found = { market: "hk", code: raw.padStart(5, "0"), name: raw }
  } else {
    // Tencent's search: v_hint="hk~00700~腾讯控股~txkg~GP^us~aapl.oq~Apple~apple~GP"
    const hint = fetch("https://smartbox.gtimg.cn/s3/?v=2&t=all&q=" + encodeURIComponent(raw))
    const body = (hint.match(/"(.*)"/) || [])[1] || ""
    for (const item of body.split("^")) {
      const f = item.split("~")
      if (f.length >= 5 && f[4] === "GP" && (f[0] === "us" || f[0] === "hk")) {
        found = { market: f[0], code: f[0] === "us" ? f[1].split(".")[0].toUpperCase() : f[1], name: JSON.parse('"' + f[2] + '"') }
        break
      }
    }
  }
  if (found) cache[raw] = found
  return found
}

function quotes(list) {
  const out = {}
  const crypto = list.filter(i => i.market === "crypto")
  if (crypto.length) {
    const symbols = encodeURIComponent(JSON.stringify(crypto.map(i => i.code)))
    let rows = []
    try { rows = JSON.parse(fetch("https://api.binance.com/api/v3/ticker/24hr?symbols=" + symbols)) } catch (e) {}
    if (Array.isArray(rows)) for (const r of rows) out["crypto:" + r.symbol] = { price: +r.lastPrice, change: +r.priceChangePercent }
  }
  const stocks = list.filter(i => i.market !== "crypto")
  if (stocks.length) {
    // v_usAAPL="200~苹果~AAPL.OQ~354.07~…"; field 1 name, 3 price, 32 change %.
    const text = fetch("https://qt.gtimg.cn/q=" + stocks.map(i => i.market + i.code).join(","), true)
    for (const line of text.split(";")) {
      const m = line.trim().match(/^v_(us|hk)([^=]+)="(.*)"$/)
      if (!m) continue
      const f = m[3].split("~")
      if (f.length > 32 && +f[3] > 0) out[m[1] + ":" + m[2]] = { price: +f[3], change: +f[32], name: f[1] }
    }
  }
  return out
}

const fmt = p => p >= 10000 ? p.toFixed(0) : p >= 100 ? p.toFixed(2) : p >= 1 ? p.toFixed(3) : p.toPrecision(4)
const pct = c => (c >= 0 ? "+" : "") + c.toFixed(2) + "%"
const pageURL = i => i.market === "crypto" ? "https://www.binance.com/en/trade/" + i.code + "?type=spot"
  : i.market === "us" ? "https://finance.yahoo.com/quote/" + i.code
  : "https://finance.yahoo.com/quote/" + yahooHK(i.code)
const yahooHK = code => String(+code).padStart(4, "0") + ".HK"
const badge = { crypto: zh ? "币" : "Crypto", us: zh ? "美股" : "US", hk: zh ? "港股" : "HK" }
const short = code => code.replace(/USDT$/, "")
const COIN_NAMES = { BTC: ["Bitcoin", "比特币"], ETH: ["Ethereum", "以太坊"], SOL: ["Solana", "Solana"], BNB: ["BNB", "币安币"],
  XRP: ["XRP", "瑞波币"], DOGE: ["Dogecoin", "狗狗币"], ADA: ["Cardano", "艾达币"], TRX: ["TRON", "波场"], LTC: ["Litecoin", "莱特币"],
  DOT: ["Polkadot", "波卡"], LINK: ["Chainlink", "Chainlink"], AVAX: ["Avalanche", "雪崩"], SHIB: ["Shiba Inu", "柴犬币"],
  TON: ["Toncoin", "Toncoin"], SUI: ["Sui", "Sui"], PEPE: ["Pepe", "Pepe"] }
const coinName = code => { const n = COIN_NAMES[short(code)]; return n ? n[zh ? 1 : 0] : "" }

// Recent prices for the sparkline: 24 hourly closes (Binance) or a month of daily closes (Yahoo).
// Cached for 10 minutes so the 15-second refresh doesn't refetch them.
function history(item, cache) {
  const key = item.market + ":" + item.code
  const hit = cache[key]
  if (hit && Date.now() - hit.at < 600000) return hit.values
  let values = []
  try {
    if (item.market === "crypto") {
      values = JSON.parse(fetch("https://api.binance.com/api/v3/klines?symbol=" + item.code + "&interval=1h&limit=24")).map(k => +k[4])
    } else {
      const symbol = item.market === "us" ? item.code : yahooHK(item.code)
      const chart = JSON.parse(sh("/usr/bin/curl -s -m 8 -A Mozilla/5.0 " + q("https://query1.finance.yahoo.com/v8/finance/chart/" + symbol + "?interval=1d&range=1mo")))
      values = chart.chart.result[0].indicators.quote[0].close.filter(v => v != null)
    }
  } catch (e) {}
  if (values.length >= 2) cache[key] = { at: Date.now(), values }
  return values.length >= 2 ? values : (hit ? hit.values : [])
}

const text = (t, extra) => Object.assign({ type: "text", text: t }, extra || {})

function run() {
  const cachePath = dataDir + "/resolved.json"
  const historyPath = dataDir + "/history.json"
  const cache = readJSON(cachePath) || {}
  const historyCache = readJSON(historyPath) || {}
  const entries = (getenv("ALTOOLS_SETTING_WATCHLIST") || "BTC, ETH, AAPL, NVDA, 00700").split(/[,，\n]/)
  const list = []
  const unknown = []
  for (const e of entries) {
    if (!e.trim()) continue
    const item = resolve(e, cache)
    if (item && !list.some(x => x.market === item.market && x.code === item.code)) list.push(item)
    else if (!item) unknown.push(e.trim())
  }
  writeJSON(cachePath, cache)

  const prices = quotes(list)
  const quotesList = list.map(i => {
    const p = prices[i.market + ":" + i.code]
    const name = i.market === "crypto" ? coinName(i.code) : (p && p.name ? p.name : i.name)
    return { item: i, price: p, name, color: p ? (p.change >= 0 ? "green" : "red") : "tertiary" }
  })

  // Home: code on the left, price over the coloured change on the right.
  const homeRows = quotesList.slice(0, 4).map(({ item, price, color }) => ({
    type: "hstack", action: { open: pageURL(item) }, children: [
      text(short(item.code), { size: 11, weight: "semibold", lines: 1 }),
      { type: "spacer" },
      { type: "vstack", align: "trailing", spacing: 0, children: [
        text(price ? fmt(price.price) : "—", { size: 11, weight: "medium", mono: true }),
        text(price ? pct(price.change) : "", { size: 9, weight: "semibold", color, mono: true }),
      ] },
    ],
  }))

  // Page: a card per symbol with its market, name, price, change and a sparkline.
  const cards = quotesList.map(({ item, price, name, color }) => {
    const values = history(item, historyCache)
    const children = [
      { type: "hstack", children: [
        { type: "badge", text: badge[item.market], color: "secondary" },
        text(short(item.code), { size: 12, weight: "bold", lines: 1 }),
        { type: "spacer" },
        text(price ? fmt(price.price) : "—", { size: 12, weight: "semibold", mono: true }),
      ] },
      { type: "hstack", children: [
        text(name && name !== item.code ? name : badge[item.market], { size: 10, color: "tertiary", lines: 1 }),
        { type: "spacer" },
        text(price ? pct(price.change) : "", { size: 10, weight: "semibold", color, mono: true }),
      ] },
    ]
    if (values.length >= 2) children.push({ type: "sparkline", values, color: price ? color : "tertiary", height: 12 })
    return { type: "card", padding: 8, action: { open: pageURL(item) }, children }
  })
  writeJSON(historyPath, historyCache)

  // Two rows of cards fit the open notch; more scroll.
  const page = [{ type: "grid", columns: cards.length > 4 ? 3 : 2, spacing: 5, children: cards }]
  if (unknown.length) {
    page.push(text((zh ? "找不到：" : "Not found: ") + unknown.join(", ") + (zh ? "（检查拼写，或加上 us: / hk: / crypto:）" : " (check the spelling, or add us: / hk: / crypto:)"),
      { size: 10, color: "orange" }))
  }

  const first = quotesList.find(q => q.price)
  const earsOn = (getenv("ALTOOLS_SETTING_EARS") || "First symbol") !== "Off"
  // Ears like the old ticker: the coin on the left (₿ for Bitcoin), price over change on the right.
  const ears = earsOn && first ? {
    width: 62,
    left: short(first.item.code) === "BTC"
      ? { type: "symbol", name: "bitcoinsign.circle.fill", size: 14, color: "orange" }
      : text(first.item.market === "crypto" ? short(first.item.code) : first.item.code, { size: 11, weight: "bold", color: "orange", lines: 1 }),
    right: { type: "vstack", align: "trailing", spacing: 0, children: [
      text(fmt(first.price.price), { size: 11, weight: "semibold", mono: true, lines: 1 }),
      text(pct(first.price.change), { size: 9, weight: "semibold", mono: true, color: first.color }),
    ] },
  } : undefined
  return JSON.stringify({
    ears,
    home: { view: { type: "vstack", spacing: 5, children: [
      { type: "hstack", spacing: 5, children: [
        { type: "symbol", name: "chart.line.uptrend.xyaxis", size: 10, color: "green" },
        text(zh ? "行情" : "Markets", { size: 11, weight: "semibold" }),
      ] },
    ].concat(homeRows) } },
    tab: { title: zh ? "行情" : "Markets", view: { type: "vstack", spacing: 6, children: page } },
  })
}
