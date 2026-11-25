import Foundation

/// Live price for one trading pair (default BTCUSDT) from Binance's public market data.
///
/// Streams the 24h ticker over a WebSocket through the proxy set in Settings › AI; if the
/// stream can't connect (blocked network, no proxy), it polls the REST endpoint every few
/// seconds instead. Updates reach the UI at most once a second.
final class CryptoTicker: ObservableObject {
  struct Quote: Equatable {
    var symbol: String
    var price: Double
    /// 24h change in percent.
    var change: Double
    var updated: Date
  }

  @Published private(set) var quote: Quote?

  private var socket: URLSessionWebSocketTask?
  private var session: URLSession?
  private var pollTimer: Timer?
  private var reconnectDelay: TimeInterval = 2
  private var lastPublish = Date.distantPast
  private var running = false
  private var symbol = "BTCUSDT"

  /// The quote is stale when nothing arrived for a minute; the notch then stops showing it.
  var freshQuote: Quote? {
    guard let quote, Date().timeIntervalSince(quote.updated) < 60 else { return nil }
    return quote
  }

  func start(symbol: String) {
    let cleaned = symbol.uppercased().filter { $0.isLetter || $0.isNumber }
    stop()
    self.symbol = cleaned.isEmpty ? "BTCUSDT" : cleaned
    running = true
    connect()
  }

  func stop() {
    running = false
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
    pollTimer?.invalidate()
    pollTimer = nil
  }

  // MARK: Stream

  private func connect() {
    guard running else { return }
    session = ProxySession.shared
    let url = URL(string: "wss://stream.binance.com:9443/ws/\(symbol.lowercased())@ticker")!
    let task = session!.webSocketTask(with: url)
    socket = task
    task.resume()
    receive(on: task)
    // No message within 8 s: fall back to polling while the stream keeps retrying.
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
      guard let self, self.running, self.quote == nil || Date().timeIntervalSince(self.quote!.updated) > 8 else { return }
      self.startPolling()
    }
  }

  private func receive(on task: URLSessionWebSocketTask) {
    task.receive { [weak self] result in
      guard let self, self.socket === task else { return }
      switch result {
      case .success(let message):
        if case .string(let text) = message, let data = text.data(using: .utf8) { self.handleTicker(data) }
        self.reconnectDelay = 2
        self.receive(on: task)
      case .failure:
        self.scheduleReconnect()
      }
    }
  }

  private func scheduleReconnect() {
    socket = nil
    guard running else { return }
    startPolling()
    let delay = reconnectDelay
    reconnectDelay = min(reconnectDelay * 2, 60)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.connect() }
  }

  /// Stream payload: "c" last price, "P" 24h change percent (strings).
  private func handleTicker(_ data: Data) {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let price = (json["c"] as? String).flatMap(Double.init),
          let change = (json["P"] as? String).flatMap(Double.init) else { return }
    publish(price: price, change: change)
    // The stream works again: polling is no longer needed.
    DispatchQueue.main.async { [weak self] in
      self?.pollTimer?.invalidate()
      self?.pollTimer = nil
    }
  }

  // MARK: Polling fallback

  private func startPolling() {
    guard pollTimer == nil, running else { return }
    poll()
    pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.poll() }
  }

  private func poll() {
    let url = URL(string: "https://api.binance.com/api/v3/ticker/24hr?symbol=\(symbol)")!
    ProxySession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let price = (json["lastPrice"] as? String).flatMap(Double.init),
            let change = (json["priceChangePercent"] as? String).flatMap(Double.init) else { return }
      self?.publish(price: price, change: change)
    }.resume()
  }

  private func publish(price: Double, change: Double) {
    let now = Date()
    guard now.timeIntervalSince(lastPublish) >= 1 else { return }
    lastPublish = now
    let quote = Quote(symbol: symbol, price: price, change: change, updated: now)
    DispatchQueue.main.async { [weak self] in self?.quote = quote }
  }

  /// "97,234" for large prices, more decimals for small ones.
  static func format(_ price: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = price >= 1000 ? 0 : price >= 1 ? 2 : 5
    formatter.minimumFractionDigits = formatter.maximumFractionDigits
    return formatter.string(from: NSNumber(value: price)) ?? String(price)
  }

  /// "BTC" from "BTCUSDT".
  static func base(of symbol: String) -> String {
    for quote in ["USDT", "USDC", "FDUSD", "BUSD", "USD", "BTC", "ETH"] where symbol.hasSuffix(quote) && symbol.count > quote.count {
      return String(symbol.dropLast(quote.count))
    }
    return symbol
  }
}
