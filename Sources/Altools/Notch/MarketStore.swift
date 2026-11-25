import Foundation

/// Prices for the watchlist in Settings: crypto pairs from Binance (through the proxy, like
/// the ticker), US and Hong Kong stocks from Tencent's public quote service, which answers
/// without a proxy. Polls every 15 s, but only while `isVisible` says someone is looking.
final class MarketStore: ObservableObject {
  enum Market: String, CaseIterable, Identifiable {
    case crypto, us, hk
    var id: String { rawValue }
    var title: String {
      switch self {
      case .crypto: "Crypto"
      case .us: "US"
      case .hk: "HK"
      }
    }
    var placeholder: String {
      switch self {
      case .crypto: "BTCUSDT"
      case .us: "AAPL"
      case .hk: "00700"
      }
    }
  }

  /// One watchlist entry, stored as "market:CODE" (e.g. "hk:00700").
  struct Instrument: Hashable, Identifiable {
    let market: Market
    let code: String
    var id: String { "\(market.rawValue):\(code)" }

    init(market: Market, code: String) {
      self.market = market
      let cleaned = code.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "." }
      // HK codes are five digits in Tencent's API: 700 → 00700.
      self.code = market == .hk && cleaned.allSatisfy(\.isNumber) ? String(repeating: "0", count: max(0, 5 - cleaned.count)) + cleaned : cleaned
    }

    init?(id: String) {
      let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
      guard parts.count == 2, let market = Market(rawValue: parts[0]), !parts[1].isEmpty else { return nil }
      self.init(market: market, code: parts[1])
    }

    /// Where a click on the row goes.
    var pageURL: URL? {
      switch market {
      case .crypto: return URL(string: "https://www.binance.com/en/trade/\(code)?type=spot")
      case .us: return URL(string: "https://finance.yahoo.com/quote/\(code)")
      case .hk:
        // Yahoo writes HK codes with four digits: 00700 → 0700.HK.
        let digits = String(code.drop { $0 == "0" })
        return URL(string: "https://finance.yahoo.com/quote/\(String(repeating: "0", count: max(0, 4 - digits.count)) + digits).HK")
      }
    }
  }

  struct Quote: Equatable {
    var name: String
    var price: Double
    /// Change since the previous close (stocks) or over 24 h (crypto), in percent.
    var changePercent: Double
    var updated: Date
  }

  static let defaultWatchlist = ["crypto:BTCUSDT", "crypto:ETHUSDT", "us:AAPL", "us:NVDA", "hk:00700"]

  @Published private(set) var quotes: [String: Quote] = [:]
  @Published private(set) var lastError: String?
  var isVisible: () -> Bool = { false }

  private var timer: Timer?

  var watchlist: [Instrument] {
    AppSettings.shared.marketWatchlist.compactMap(Instrument.init(id:))
  }

  func start() {
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      guard let self, self.isVisible() else { return }
      self.refresh()
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  func add(_ instrument: Instrument) {
    guard !instrument.code.isEmpty, !AppSettings.shared.marketWatchlist.contains(instrument.id) else { return }
    AppSettings.shared.marketWatchlist.append(instrument.id)
    refresh()
  }

  func remove(_ instrument: Instrument) {
    AppSettings.shared.marketWatchlist.removeAll { $0 == instrument.id }
    quotes[instrument.id] = nil
  }

  #if DEBUG
  func loadDemo() {
    let now = Date()
    quotes = [
      "crypto:BTCUSDT": Quote(name: "BTCUSDT", price: 98_420, changePercent: 2.31, updated: now),
      "crypto:ETHUSDT": Quote(name: "ETHUSDT", price: 3_612.5, changePercent: -1.08, updated: now),
      "us:AAPL": Quote(name: "Apple", price: 231.47, changePercent: 0.86, updated: now),
      "us:NVDA": Quote(name: "Nvidia", price: 142.19, changePercent: 3.42, updated: now),
      "hk:00700": Quote(name: "Tencent", price: 412.6, changePercent: -0.53, updated: now),
    ]
  }
  #endif

  func refresh() {
    let list = watchlist
    let crypto = list.filter { $0.market == .crypto }
    let stocks = list.filter { $0.market != .crypto }
    if !crypto.isEmpty { fetchCrypto(crypto) }
    if !stocks.isEmpty { fetchStocks(stocks) }
  }

  // MARK: Search

  struct Suggestion: Identifiable, Hashable {
    let instrument: Instrument
    let name: String
    var id: String { instrument.id }
  }

  private static let cryptoNames: [String: String] = [
    "比特币": "BTC", "bitcoin": "BTC", "以太坊": "ETH", "ethereum": "ETH", "ether": "ETH", "solana": "SOL", "索拉纳": "SOL",
    "狗狗币": "DOGE", "dogecoin": "DOGE", "瑞波": "XRP", "ripple": "XRP", "币安币": "BNB", "莱特币": "LTC", "litecoin": "LTC",
    "艾达币": "ADA", "cardano": "ADA", "波卡": "DOT", "polkadot": "DOT", "波场": "TRX", "tron": "TRX", "柴犬币": "SHIB",
  ]

  /// Matches for a name or code: crypto pairs against USDT, stocks from Tencent's search
  /// (US and HK only). Calls back on the main queue; an empty query gives no matches.
  func search(_ text: String, market: Market, completion: @escaping ([Suggestion]) -> Void) {
    let query = text.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return completion([]) }
    if market == .crypto {
      let base = Self.cryptoNames[query.lowercased()] ?? query.uppercased().filter { $0.isLetter || $0.isNumber }
      guard !base.isEmpty else { return completion([]) }
      let pair = base.hasSuffix("USDT") || base.hasSuffix("USDC") || base.hasSuffix("BTC") && base.count > 3 ? base : base + "USDT"
      return completion([Suggestion(instrument: Instrument(market: .crypto, code: pair), name: base)])
    }
    var components = URLComponents(string: "https://smartbox.gtimg.cn/s3/")!
    components.queryItems = [URLQueryItem(name: "v", value: "2"), URLQueryItem(name: "t", value: "all"), URLQueryItem(name: "q", value: query)]
    guard let url = components.url else { return completion([]) }
    URLSession.shared.dataTask(with: url) { data, _, _ in
      let found = data.flatMap { String(data: $0, encoding: .utf8) }.map(Self.parseSearch) ?? []
      DispatchQueue.main.async { completion(found) }
    }.resume()
  }

  /// `v_hint="hk~00700~\u817e…~txkg~GP^us~aapl.oq~Apple~apple~GP"`: market, code (US codes
  /// carry an exchange suffix), name with \u escapes, pinyin, type. GP is a stock or fund.
  static func parseSearch(_ text: String) -> [Suggestion] {
    guard let start = text.firstIndex(of: "\""), let end = text.lastIndex(of: "\""), start < end else { return [] }
    let body = String(text[text.index(after: start)..<end])
    return body.split(separator: "^").compactMap { entry in
      let fields = entry.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
      guard fields.count >= 5, fields[4] == "GP", let market = Market(rawValue: fields[0]), market != .crypto else { return nil }
      let code = market == .us ? String(fields[1].split(separator: ".").first ?? "") : fields[1]
      let name = (try? JSONSerialization.jsonObject(with: Data("\"\(fields[2])\"".utf8), options: .fragmentsAllowed) as? String) ?? fields[2]
      return Suggestion(instrument: Instrument(market: market, code: code), name: name)
    }
  }

  // MARK: Crypto (Binance)

  private func fetchCrypto(_ list: [Instrument]) {
    let symbols = "[" + list.map { "\"\($0.code)\"" }.joined(separator: ",") + "]"
    var components = URLComponents(string: "https://api.binance.com/api/v3/ticker/24hr")!
    components.queryItems = [URLQueryItem(name: "symbols", value: symbols)]
    guard let url = components.url else { return }
    ProxySession.shared.dataTask(with: url) { [weak self] data, _, error in
      guard let data, let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        DispatchQueue.main.async { self?.lastError = error == nil ? "Binance didn't recognise a pair" : "Binance unreachable (proxy?)" }
        return
      }
      var fresh: [String: Quote] = [:]
      for row in rows {
        guard let symbol = row["symbol"] as? String,
              let price = (row["lastPrice"] as? String).flatMap(Double.init),
              let change = (row["priceChangePercent"] as? String).flatMap(Double.init) else { continue }
        fresh["crypto:\(symbol)"] = Quote(name: symbol, price: price, changePercent: change, updated: Date())
      }
      DispatchQueue.main.async { self?.merge(fresh) }
    }.resume()
  }

  // MARK: Stocks (Tencent)

  private func fetchStocks(_ list: [Instrument]) {
    let codes = list.map { $0.market.rawValue + $0.code }.joined(separator: ",")
    guard let url = URL(string: "https://qt.gtimg.cn/q=\(codes)") else { return }
    URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data, let text = Self.decodeGBK(data) else {
        DispatchQueue.main.async { self?.lastError = "Stock quotes unreachable" }
        return
      }
      let fresh = Self.parseTencent(text)
      DispatchQueue.main.async { self?.merge(fresh) }
    }.resume()
  }

  /// Lines like `v_usAAPL="200~苹果~AAPL.OQ~354.07~349.08~…~4.99~1.43~…";` — field 1 is the
  /// name, 3 the price, 32 the change in percent. Unknown codes come back as `v_pv_none_match`.
  static func parseTencent(_ text: String) -> [String: Quote] {
    var result: [String: Quote] = [:]
    for line in text.split(separator: ";") {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed.hasPrefix("v_"), let eq = trimmed.firstIndex(of: "=") else { continue }
      let key = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<eq]
      guard key.count > 2 else { continue }
      let market = String(key.prefix(2)), code = String(key.dropFirst(2))
      let body = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
      let fields = body.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
      guard fields.count > 32, let price = Double(fields[3]), price > 0 else { continue }
      result["\(market):\(code)"] = Quote(name: fields[1], price: price, changePercent: Double(fields[32]) ?? 0, updated: Date())
    }
    return result
  }

  private static func decodeGBK(_ data: Data) -> String? {
    let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    return String(data: data, encoding: String.Encoding(rawValue: encoding))
  }

  private func merge(_ fresh: [String: Quote]) {
    guard !fresh.isEmpty else { return }
    lastError = nil
    quotes.merge(fresh) { _, new in new }
  }

  static func format(_ price: Double) -> String {
    switch price {
    case 10_000...: String(format: "%.0f", price)
    case 100...: String(format: "%.2f", price)
    case 1...: String(format: "%.3f", price)
    default: String(format: "%.5f", price)
    }
  }
}
