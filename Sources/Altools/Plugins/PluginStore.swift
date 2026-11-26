import AltoolsCore
import Foundation

/// The plugin store: featured plugins from plugins/registry.json in the Altools repository (a copy
/// ships with the app for when GitHub can't be reached), plus every GitHub repository tagged with
/// the `altools-plugin` topic. Each listing's details come from its own plugin.json. Installing
/// goes through PluginPackage, which asks before copying anything.
final class PluginStore: ObservableObject {
  struct Listing: Identifiable {
    var id: String { repo + (path.map { "/" + $0 } ?? "") }
    let repo: String
    let path: String?
    /// Branch or tag; nil for the repository's default branch.
    let ref: String?
    let manifest: PluginManifest
    let stars: Int?
    let featured: Bool
  }

  @Published private(set) var listings: [Listing] = []
  @Published private(set) var isLoading = false
  @Published private(set) var problem: String?

  static let topic = "altools-plugin"
  private static var registryURL: URL {
    #if DEBUG
    if let override = ProcessInfo.processInfo.environment["ALTOOLS_REGISTRY_URL"], let url = URL(string: override) { return url }
    #endif
    return URL(string: "https://raw.githubusercontent.com/matyle/altools/main/plugins/registry.json")!
  }

  private struct Registry: Decodable {
    struct Entry: Decodable { let repo: String; let path: String?; let ref: String? }
    let plugins: [Entry]
  }

  func load() {
    guard !isLoading else { return }
    isLoading = true
    problem = nil
    Task { @MainActor in
      async let featured = Self.featured()
      async let community = Self.community()
      let (f, c) = await (featured, community)
      let featuredIDs = Set(f.map(\.id))
      listings = f + c.listings.filter { !featuredIDs.contains($0.id) }
      problem = c.problem
      isLoading = false
    }
  }

  private static func featured() async -> [Listing] {
    var data = try? await fetch(registryURL)
    if data == nil, let bundled = Bundle.main.url(forResource: "registry", withExtension: "json") { data = try? Data(contentsOf: bundled) }
    guard let data, let registry = try? JSONDecoder().decode(Registry.self, from: data) else { return [] }
    return await withTaskGroup(of: (Int, Listing?).self) { group in
      for (index, entry) in registry.plugins.enumerated() {
        group.addTask { (index, await listing(repo: entry.repo, path: entry.path, ref: entry.ref, stars: nil, featured: true)) }
      }
      var found: [(Int, Listing)] = []
      for await (index, listing) in group { if let listing { found.append((index, listing)) } }
      return found.sorted { $0.0 < $1.0 }.map(\.1)
    }
  }

  private static func community() async -> (listings: [Listing], problem: String?) {
    var components = URLComponents(string: "https://api.github.com/search/repositories")!
    components.queryItems = [URLQueryItem(name: "q", value: "topic:\(topic)"), URLQueryItem(name: "sort", value: "stars"),
                             URLQueryItem(name: "per_page", value: "50")]
    struct Search: Decodable {
      struct Repo: Decodable { let full_name: String; let stargazers_count: Int }
      let items: [Repo]
    }
    guard let data = try? await fetch(components.url!, json: true), let search = try? JSONDecoder().decode(Search.self, from: data) else {
      return ([], "GitHub search is unavailable right now (offline, proxy, or rate limit); featured plugins are still listed.")
    }
    let listings = await withTaskGroup(of: Listing?.self) { group in
      for repo in search.items { group.addTask { await listing(repo: repo.full_name, path: nil, ref: nil, stars: repo.stargazers_count, featured: false) } }
      var found: [Listing] = []
      for await listing in group { if let listing { found.append(listing) } }
      return found
    }
    return (listings.sorted { ($0.stars ?? 0) > ($1.stars ?? 0) }, nil)
  }

  /// Reads the plugin.json at the repository's default branch; nil when missing or invalid.
  private static func listing(repo: String, path: String?, ref: String?, stars: Int?, featured: Bool) async -> Listing? {
    let file = [path, "plugin.json"].compactMap { $0 }.joined(separator: "/")
    guard let url = URL(string: "https://raw.githubusercontent.com/\(repo)/\(ref ?? "HEAD")/\(file)"),
          let data = try? await fetch(url), let manifest = try? PluginManifest.decode(data) else { return nil }
    return Listing(repo: repo, path: path, ref: ref, manifest: manifest, stars: stars, featured: featured)
  }

  private static func fetch(_ url: URL, json: Bool = false) async throws -> Data {
    var request = URLRequest(url: url, timeoutInterval: 12)
    request.setValue("Altools", forHTTPHeaderField: "User-Agent")
    if json { request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
    let (data, response) = try await ProxySession.shared.data(for: request)
    // A file:// registry (the runtime test) has no HTTP status.
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw URLError(.badServerResponse) }
    return data
  }

  func install(_ listing: Listing) {
    PluginPackage.install(repo: listing.repo, path: listing.path, ref: listing.ref)
  }

  /// "owner/name" or "owner/name/sub/folder", as typed under Install from GitHub.
  static func installFromGitHub(_ text: String) {
    var trimmed = text.trimmingCharacters(in: .whitespaces)
    for prefix in ["https://github.com/", "http://github.com/", "github.com/"] where trimmed.hasPrefix(prefix) { trimmed.removeFirst(prefix.count) }
    var parts = trimmed.split(separator: "/").map(String.init)
    // github.com/owner/repo/tree/<branch>/<path>
    var ref: String?
    if parts.count > 3, parts[2] == "tree" { ref = parts[3]; parts.removeSubrange(2...3) }
    guard parts.count >= 2 else { return PluginPackage.install(repo: trimmed) }
    let path = parts.count > 2 ? parts[2...].joined(separator: "/") : nil
    PluginPackage.install(repo: parts[0] + "/" + parts[1], path: path, ref: ref)
  }
}
