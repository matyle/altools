#!/usr/bin/osascript -l JavaScript
// Altools plugin example: no notch UI, only selected-text actions, a command and a search.
// Contract: PLUGINS.md › Beyond the notch.
ObjC.import("Foundation")
const env = $.NSProcessInfo.processInfo.environment
const getenv = key => { const v = env.objectForKey(key); return v ? ObjC.unwrap(v) : "" }

function base64(text, decode) {
  if (decode) {
    const data = $.NSData.alloc.initWithBase64EncodedStringOptions(text, 0)
    if (data.isNil()) return null
    const out = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)
    return out.isNil() ? null : ObjC.unwrap(out)
  }
  return ObjC.unwrap($(text).dataUsingEncoding($.NSUTF8StringEncoding).base64EncodedStringWithOptions(0))
}

function run() {
  const event = getenv("ALTOOLS_EVENT")
  const input = getenv("ALTOOLS_INPUT")
  if (event === "selection:json") {
    try { return JSON.stringify({ result: { text: JSON.stringify(JSON.parse(input), null, 2), title: "Formatted JSON", replace: true } }) }
    catch (e) { return JSON.stringify({ result: { text: "Not valid JSON: " + e.message } }) }
  }
  if (event === "selection:count") {
    const words = (input.trim().match(/\S+/g) || []).length
    const cjk = (input.match(/[㐀-鿿]/g) || []).length
    return JSON.stringify({ result: { text: words + " words · " + input.length + " characters" + (cjk ? " · " + cjk + " CJK" : "") } })
  }
  if (event === "command:uuid") {
    return JSON.stringify({ result: { text: ObjC.unwrap($.NSUUID.UUID.UUIDString).toLowerCase(), title: "UUID" } })
  }
  if (event === "search") {
    const text = input.trim()
    if (!text) return JSON.stringify({ results: [] })
    const rows = [{ title: base64(text, false), subtitle: "Encode", symbol: "lock", action: { copy: base64(text, false) } }]
    const decoded = base64(text, true)
    if (decoded) rows.unshift({ title: decoded, subtitle: "Decode", symbol: "lock.open", action: { copy: decoded } })
    return JSON.stringify({ results: rows })
  }
  return JSON.stringify({})
}
