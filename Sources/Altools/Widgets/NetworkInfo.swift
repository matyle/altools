import CoreWLAN
import Foundation
import SystemConfiguration

/// The active connection: interface, addresses, router and Wi-Fi details.
struct NetworkInfo: Equatable {
  var interface = ""
  var isWiFi = false
  var connected = false
  var localIP: String?
  var router: String?
  /// nil when macOS withholds it (Wi-Fi names need Location Services access).
  var ssid: String?
  var rssi: Int?
  var channel: String?
  var linkRate: Double?
  var security: String?

  var signalLabel: String? {
    guard let rssi else { return nil }
    if rssi >= -55 { return "Excellent" }
    if rssi >= -67 { return "Good" }
    if rssi >= -75 { return "Fair" }
    return "Weak"
  }

  static func read() -> NetworkInfo {
    var info = NetworkInfo()
    // The primary interface from the system configuration store.
    if let store = SCDynamicStoreCreate(nil, "Altools" as CFString, nil, nil),
       let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
      info.interface = global["PrimaryInterface"] as? String ?? ""
      info.router = global["Router"] as? String
      info.connected = !info.interface.isEmpty
    }
    info.localIP = address(of: info.interface)
    if let wifi = CWWiFiClient.shared().interface(), wifi.interfaceName == info.interface {
      info.isWiFi = true
      info.ssid = wifi.ssid()
      info.rssi = wifi.rssiValue() == 0 ? nil : wifi.rssiValue()
      info.linkRate = wifi.transmitRate() > 0 ? wifi.transmitRate() : nil
      if let channel = wifi.wlanChannel() {
        let band = switch channel.channelBand {
        case .band2GHz: "2.4 GHz"
        case .band5GHz: "5 GHz"
        case .band6GHz: "6 GHz"
        default: ""
        }
        info.channel = "\(channel.channelNumber)\(band.isEmpty ? "" : " · \(band)")"
      }
      info.security = securityName(wifi.security())
    }
    return info
  }

  private static func address(of interface: String) -> String? {
    guard !interface.isEmpty else { return nil }
    var addrs: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
    defer { freeifaddrs(addrs) }
    var pointer: UnsafeMutablePointer<ifaddrs>? = first
    while let ifa = pointer {
      if String(cString: ifa.pointee.ifa_name) == interface, let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        return String(cString: host)
      }
      pointer = ifa.pointee.ifa_next
    }
    return nil
  }

  private static func securityName(_ security: CWSecurity) -> String? {
    switch security {
    case .none: "Open"
    case .WEP: "WEP"
    case .wpaPersonal, .wpaPersonalMixed: "WPA Personal"
    case .wpa2Personal: "WPA2 Personal"
    case .wpa3Personal: "WPA3 Personal"
    case .wpa3Transition: "WPA2/WPA3"
    case .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .wpa3Enterprise: "Enterprise"
    default: nil
    }
  }

  /// Asks a public echo service for this network's public address. Called only when the user clicks.
  static func lookUpPublicIP(_ completion: @escaping (String?) -> Void) {
    var request = URLRequest(url: URL(string: "https://api.ipify.org")!)
    request.timeoutInterval = 8
    URLSession.shared.dataTask(with: request) { data, _, _ in
      let ip = data.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
      DispatchQueue.main.async { completion(ip) }
    }.resume()
  }
}
