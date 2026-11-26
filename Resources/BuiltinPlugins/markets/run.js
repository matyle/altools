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
  : "https://finance.yahoo.com/quote/" + String(+i.code).padStart(4, "0") + ".HK"
const label = { crypto: zh ? "加密货币" : "Crypto", us: zh ? "美股" : "US stocks", hk: zh ? "港股" : "Hong Kong" }

function run() {
  const cachePath = dataDir + "/resolved.json"
  const cache = readJSON(cachePath) || {}
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
  const rows = list.map(i => {
    const p = prices[i.market + ":" + i.code]
    const name = p && p.name ? p.name : i.name
    return {
      title: i.code,
      subtitle: name !== i.code ? name : undefined,
      value: p ? fmt(p.price) + "  " + pct(p.change) : "—",
      symbol: p ? (p.change >= 0 ? "arrow.up.right" : "arrow.down.right") : "questionmark",
      tint: p ? (p.change >= 0 ? "#98C379" : "#E06C75") : undefined,
      action: { open: pageURL(i) },
      market: i.market,
    }
  })
  const sections = ["crypto", "us", "hk"].map(m => ({ title: label[m], rows: rows.filter(r => r.market === m) })).filter(s => s.rows.length)
  if (unknown.length) sections.push({ title: zh ? "找不到" : "Not found", rows: unknown.map(u => ({ title: u, symbol: "questionmark.circle", subtitle: zh ? "检查拼写，或加上 us: / hk: / crypto:" : "Check the spelling, or add us: / hk: / crypto:" })) })
  for (const r of rows) delete r.market

  const first = rows.find(r => r.value !== "—")
  const earsOn = (getenv("ALTOOLS_SETTING_EARS") || "First symbol") !== "Off"
  return JSON.stringify({
    ears: earsOn && first ? { symbol: first.symbol, text: first.title.replace(/USDT$/, "") + " " + first.value.split("  ")[0], tint: first.tint } : undefined,
    home: { title: zh ? "行情" : "Markets", rows: rows.slice(0, 3) },
    tab: { title: zh ? "行情" : "Markets", sections },
  })
}
