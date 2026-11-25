import Darwin
import Foundation
import IOKit.ps

/// Samples CPU, memory, storage and network every two seconds and keeps the last
/// minute of each for the widget charts.
final class SystemStats: ObservableObject {
  struct CPU: Equatable { var user: Double; var system: Double; var total: Double { user + system } }
  struct Memory: Equatable {
    var total: UInt64
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var used: UInt64 { app + wired + compressed }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
  }
  struct Storage: Equatable { var total: Int64; var free: Int64; var fraction: Double { total > 0 ? 1 - Double(free) / Double(total) : 0 } }
  struct Process: Identifiable, Equatable { var id: String { name }; var name: String; var cpu: Double }

  /// 0…1 fractions of all cores.
  @Published private(set) var cpu = CPU(user: 0, system: 0)
  @Published private(set) var cpuHistory: [Double] = []
  @Published private(set) var memory = Memory(total: ProcessInfo.processInfo.physicalMemory, app: 0, wired: 0, compressed: 0)
  @Published private(set) var memoryHistory: [Double] = []
  @Published private(set) var storage = Storage(total: 0, free: 0)
  /// Bytes per second.
  @Published private(set) var download: Double = 0
  @Published private(set) var upload: Double = 0
  @Published private(set) var downloadHistory: [Double] = []
  @Published private(set) var uploadHistory: [Double] = []
  /// Bytes moved since Altools started.
  @Published private(set) var downloadedTotal: UInt64 = 0
  @Published private(set) var uploadedTotal: UInt64 = 0
  @Published private(set) var topProcesses: [Process] = []

  private var timer: Timer?
  private var lastTicks: (user: UInt64, system: UInt64, idle: UInt64)?
  private var lastBytes: (in: UInt64, out: UInt64, at: Date)?
  private var startBytes: (in: UInt64, out: UInt64)?
  private static let historyLength = 30
  /// Top processes are read with `ps` only while a panel shows them.
  var wantsProcesses = false

  func start() {
    guard timer == nil else { return }
    sample()
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  private func sample() {
    sampleCPU()
    sampleMemory()
    sampleNetwork()
    if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
      storage = Storage(total: Int64(values.volumeTotalCapacity ?? 0), free: values.volumeAvailableCapacityForImportantUsage ?? 0)
    }
    if wantsProcesses { sampleProcesses() }
  }

  private func push(_ value: Double, to history: inout [Double]) {
    history.append(value)
    if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
  }

  private func sampleCPU() {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
    }
    guard result == KERN_SUCCESS else { return }
    let user = UInt64(info.cpu_ticks.0) + UInt64(info.cpu_ticks.3) // user + nice
    let system = UInt64(info.cpu_ticks.1)
    let idle = UInt64(info.cpu_ticks.2)
    defer { lastTicks = (user, system, idle) }
    guard let last = lastTicks else { return }
    let du = Double(user - last.user), ds = Double(system - last.system), di = Double(idle - last.idle)
    let total = du + ds + di
    guard total > 0 else { return }
    cpu = CPU(user: du / total, system: ds / total)
    push(cpu.total, to: &cpuHistory)
  }

  private func sampleMemory() {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
    }
    guard result == KERN_SUCCESS else { return }
    let page = UInt64(vm_kernel_page_size)
    // "App memory" as Activity Monitor counts it: anonymous pages that can't simply be purged.
    let app = (UInt64(stats.internal_page_count) - min(UInt64(stats.internal_page_count), UInt64(stats.purgeable_count))) * page
    memory = Memory(total: ProcessInfo.processInfo.physicalMemory, app: app,
                    wired: UInt64(stats.wire_count) * page, compressed: UInt64(stats.compressor_page_count) * page)
    push(memory.fraction, to: &memoryHistory)
  }

  private func sampleNetwork() {
    var bytesIn: UInt64 = 0, bytesOut: UInt64 = 0
    var addrs: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addrs) == 0, let first = addrs else { return }
    defer { freeifaddrs(addrs) }
    var pointer: UnsafeMutablePointer<ifaddrs>? = first
    while let ifa = pointer {
      let name = String(cString: ifa.pointee.ifa_name)
      // Physical interfaces only; loopback and tunnels would double-count.
      if ifa.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), name.hasPrefix("en"),
         let data = ifa.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
        bytesIn += UInt64(data.pointee.ifi_ibytes)
        bytesOut += UInt64(data.pointee.ifi_obytes)
      }
      pointer = ifa.pointee.ifa_next
    }
    let now = Date()
    if startBytes == nil { startBytes = (bytesIn, bytesOut) }
    if let last = lastBytes, bytesIn >= last.in, bytesOut >= last.out {
      let seconds = max(now.timeIntervalSince(last.at), 0.5)
      download = Double(bytesIn - last.in) / seconds
      upload = Double(bytesOut - last.out) / seconds
      push(download, to: &downloadHistory)
      push(upload, to: &uploadHistory)
    }
    if let start = startBytes {
      downloadedTotal = bytesIn >= start.in ? bytesIn - start.in : 0
      uploadedTotal = bytesOut >= start.out ? bytesOut - start.out : 0
    }
    lastBytes = (bytesIn, bytesOut, now)
  }

  private func sampleProcesses() {
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let process = Foundation.Process()
      process.executableURL = URL(fileURLWithPath: "/bin/ps")
      process.arguments = ["-Aceo", "pcpu,comm", "-r"]
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      guard (try? process.run()) != nil else { return }
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      let lines = String(data: data, encoding: .utf8)?.split(separator: "\n").dropFirst() ?? []
      let top = lines.prefix(5).compactMap { line -> Process? in
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let cpu = Double(parts[0]) else { return nil }
        return Process(name: String(parts[1]), cpu: cpu)
      }
      DispatchQueue.main.async { self?.topProcesses = top }
    }
  }

  static func bytes(_ value: Double, perSecond: Bool = false) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var v = value
    var i = 0
    while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
    let number = v >= 100 || i == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    return "\(number) \(units[i])\(perSecond ? "/s" : "")"
  }
}

/// Battery details from the smart battery controller: health, cycles, adapter.
struct BatteryDetails {
  var percent = 0
  var isCharging = false
  var onAC = false
  var minutesRemaining: Int?
  var minutesToFull: Int?
  var cycles: Int?
  /// Current full-charge capacity as a fraction of design capacity.
  var health: Double?
  var adapterWatts: Int?
  var temperature: Double?
  var hasBattery = true

  static func read() -> BatteryDetails {
    var details = BatteryDetails()
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
          let source = list.first(where: { (IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any])?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }),
          let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
      details.hasBattery = false
      return details
    }
    let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
    let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
    details.percent = max > 0 ? current * 100 / max : current
    details.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
    details.onAC = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
    if let empty = desc[kIOPSTimeToEmptyKey] as? Int, empty > 0 { details.minutesRemaining = empty }
    if let full = desc[kIOPSTimeToFullChargeKey] as? Int, full > 0 { details.minutesToFull = full }
    if let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
      details.adapterWatts = adapter[kIOPSPowerAdapterWattsKey] as? Int
    }
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    if service != 0 {
      defer { IOObjectRelease(service) }
      func number(_ key: String) -> Int? {
        (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
      }
      details.cycles = number("CycleCount")
      // Newer macOS keeps the raw capacities inside a "BatteryData" dictionary.
      let data = IORegistryEntryCreateCFProperty(service, "BatteryData" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
      let raw = number("AppleRawMaxCapacity") ?? (data?["AppleRawMaxCapacity"] as? Int)
      let design = number("DesignCapacity") ?? (data?["DesignCapacity"] as? Int)
      if let raw, let design, design > 0 { details.health = min(Double(raw) / Double(design), 1) }
      if let temp = number("Temperature") { details.temperature = Double(temp) / 100 }
    }
    return details
  }
}
