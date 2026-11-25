import SwiftUI

/// The watchlist with live prices; symbols are added at the top and removed on hover.
struct MarketsTab: View {
  @ObservedObject var markets: MarketStore
  @ObservedObject private var settings = AppSettings.shared
  @State private var market = MarketStore.Market.crypto
  @State private var draft = ""
  @State private var suggestions: [MarketStore.Suggestion] = []
  @State private var searchWork: DispatchWorkItem?

  private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

  var body: some View {
    VStack(spacing: 6) {
      addBar
      if let error = markets.lastError {
        Text(error).font(.system(size: 10)).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
      }
      ScrollView {
        if draft.isEmpty {
          LazyVGrid(columns: columns, spacing: 6) {
            ForEach(markets.watchlist) { instrument in
              MarketRow(instrument: instrument, quote: markets.quotes[instrument.id], remove: { markets.remove(instrument) })
            }
          }
        } else {
          suggestionList
        }
      }
    }
    .onAppear { markets.refresh() }
  }

  private var addBar: some View {
    HStack(spacing: 8) {
      Picker("", selection: $market) {
        ForEach(MarketStore.Market.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented).labelsHidden().frame(width: 150)
      TextField(market == .crypto ? "Name or code, e.g. bitcoin, SOL" : "Name or code, e.g. 腾讯, Apple, \(market.placeholder)", text: $draft)
        .textFieldStyle(.plain).font(.system(size: 12))
        .onSubmit(add)
        .onChange(of: draft) { _, _ in scheduleSearch() }
        .onChange(of: market) { _, _ in scheduleSearch() }
      Button(action: add) { Image(systemName: "plus.circle.fill").foregroundStyle(.orange) }
        .buttonStyle(.plain).disabled(draft.isEmpty)
    }
    .padding(.horizontal, 10).frame(height: 28)
    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
  }

  @ViewBuilder private var suggestionList: some View {
    VStack(spacing: 2) {
      if suggestions.isEmpty {
        Text("No matches yet; Enter adds “\(draft)” as a \(market.title) code")
          .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
      }
      ForEach(suggestions) { suggestion in
        let added = settings.marketWatchlist.contains(suggestion.id)
        Button { pick(suggestion) } label: {
          HStack(spacing: 8) {
            Text(suggestion.instrument.market.title)
              .font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
              .frame(width: 34, height: 16).background(Color.white.opacity(0.08), in: Capsule())
            Text(suggestion.instrument.code).font(.system(size: 12, weight: .semibold))
            Text(suggestion.name).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            Spacer()
            Image(systemName: added ? "checkmark" : "plus").font(.system(size: 10, weight: .bold))
              .foregroundStyle(added ? .green : .orange)
          }
          .padding(.horizontal, 9).frame(height: 26)
          .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
      }
    }
  }

  private func scheduleSearch() {
    searchWork?.cancel()
    let query = draft, market = market
    guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return suggestions = [] }
    let work = DispatchWorkItem {
      markets.search(query, market: market) { found in
        if draft == query { suggestions = Array(found.prefix(8)) }
      }
    }
    searchWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
  }

  private func pick(_ suggestion: MarketStore.Suggestion) {
    markets.add(suggestion.instrument)
    draft = ""
    suggestions = []
  }

  /// Enter takes the first match, or the text as a code when nothing matched.
  private func add() {
    if let first = suggestions.first(where: { !settings.marketWatchlist.contains($0.id) }) {
      pick(first)
    } else {
      markets.add(MarketStore.Instrument(market: market, code: draft))
      draft = ""
      suggestions = []
    }
  }
}

private struct MarketRow: View {
  let instrument: MarketStore.Instrument
  let quote: MarketStore.Quote?
  let remove: () -> Void
  @State private var hovering = false

  var body: some View {
    HStack(spacing: 8) {
      Text(instrument.market.title)
        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
        .frame(width: 34, height: 16).background(Color.white.opacity(0.08), in: Capsule())
      VStack(alignment: .leading, spacing: 0) {
        Text(instrument.code).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        if let quote, quote.name != instrument.code {
          Text(quote.name).font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      if hovering {
        Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5)) }
          .buttonStyle(.plain).help("Remove from watchlist")
      } else if let quote {
        VStack(alignment: .trailing, spacing: 0) {
          Text(MarketStore.format(quote.price)).font(.system(size: 12, weight: .semibold).monospacedDigit())
            .contentTransition(.numericText(value: quote.price))
          ChangeText(percent: quote.changePercent, size: 10)
        }
      } else {
        ProgressView().controlSize(.mini)
      }
    }
    .padding(.horizontal, 9).frame(height: 38)
    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .onTapGesture { if let url = instrument.pageURL { NSWorkspace.shared.open(url) } }
    .help("Open \(instrument.code) in the browser")
  }
}

/// The first few watchlist entries, for the Home tab.
struct MarketsSummary: View {
  @ObservedObject var markets: MarketStore
  var limit = 3

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      ForEach(markets.watchlist.prefix(limit)) { instrument in
        HStack(spacing: 4) {
          Text(instrument.code).font(.system(size: 11, weight: .semibold)).lineLimit(1)
          Spacer(minLength: 2)
          if let quote = markets.quotes[instrument.id] {
            VStack(alignment: .trailing, spacing: -1) {
              Text(MarketStore.format(quote.price)).font(.system(size: 11, weight: .medium).monospacedDigit())
              ChangeText(percent: quote.changePercent, size: 9)
            }
          } else {
            Text("—").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
          }
        }
      }
      if markets.watchlist.isEmpty {
        Text("Add symbols in Markets").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct ChangeText: View {
  let percent: Double
  let size: CGFloat

  var body: some View {
    Text(String(format: "%@%.2f%%", percent >= 0 ? "+" : "", percent))
      .font(.system(size: size, weight: .semibold).monospacedDigit())
      .foregroundStyle(percent >= 0 ? Color.green : Color.red)
  }
}
