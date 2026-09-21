import AppKit
import SwiftUI
import Darwin

struct MonitorFollowGate {
  var candidate: String?
  var since = Date.distantPast
  var nextAllowed = Date.distantPast
  mutating func target(owner: String?, enabled: Bool, busy: Bool, now: Date) -> String? {
    guard enabled, let owner, ["Studio", "MacBook"].contains(owner) else {
      candidate = nil
      return nil
    }
    if candidate != owner { candidate = owner; since = now }
    guard !busy, now.timeIntervalSince(since) >= 2, now >= nextAllowed else { return nil }
    return owner
  }
}

struct PhysicalMonitorRoute: Codable, Equatable, Sendable {
  let displayUUID: String
  let studioInput: Int
  let macbookInput: Int

  static let validatedDesk = PhysicalMonitorRoute(
    displayUUID: "ED93552C-3BAA-41AB-A7B8-A416042AB4E5", studioInput: 21, macbookInput: 17)

  static func uniqueLocalDisplay(_ identities: [String]) -> String? {
    identities.count == 1 ? identities.first : nil
  }

  static func parseInput(_ output: String) -> Int? {
    guard let value = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)),
      (0...255).contains(value) else { return nil }
    return value
  }
}

enum MonitorDDC {
  private static let operationLock = NSLock()
  static func run(helper: URL, arguments: [String]) throws -> String {
    try operationLock.withLock { try runUnlocked(helper: helper, arguments: arguments) }
  }
  private static func runUnlocked(helper: URL, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = helper
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let deadline = Date().addingTimeInterval(3)
    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    if process.isRunning {
      kill(process.processIdentifier, SIGKILL)
      process.waitUntilExit()
      throw NSError(domain: "Monitor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Monitor query timed out. Use the monitor’s physical input menu if needed."])
    }
    let result = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus == 0 else {
      throw NSError(domain: "Monitor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Monitor control unavailable (exit \(process.terminationStatus)): \(result.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)). Check the connection and DDC/CI setting."])
    }
    return result
  }
}

@MainActor final class PhysicalMonitorModel: ObservableObject {
  @Published var input: Int?
  @Published var busy = false
  @Published var message = "Read the monitor to check its current input."
  @Published var failed = false
  @Published private(set) var followsInput = false
  private let defaults: UserDefaults
  private var followGate = MonitorFollowGate()
  private var followTask: Task<Void, Never>?
  let route: PhysicalMonitorRoute
  let windows: VisibleScreenWindows

  init(defaults: UserDefaults = .standard, localPeerID: String = "studio") {
    windows = VisibleScreenWindows(localPeerID: localPeerID)
    windows.start()
    self.defaults = defaults
    followsInput = defaults.bool(forKey: "DeskMux.Experimental.AOCFollowsInput")
    let key = "DeskMux.Experimental.AOCPhysicalRoute"
    route = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(PhysicalMonitorRoute.self, from: $0) }
      ?? .validatedDesk
    if let data = try? JSONEncoder().encode(route) { defaults.set(data, forKey: key) }
  }

  func observe(_ agent: BackgroundAgentModel) {
    guard followTask == nil else { return }
    followTask = Task { [weak self, weak agent] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(500))
        guard let self, let agent else { return }
        // Do not interpret missing/failed agent state as an ownership change.
        let owner = agent.receiverReady && agent.agentStatus != nil ? agent.inputOwnerName : nil
        if let destination = self.followGate.target(owner: owner, enabled: self.followsInput,
                                                    busy: self.busy, now: Date()) {
          let target = destination == "Studio" ? self.route.studioInput : self.route.macbookInput
          if self.input != target { self.perform(target: target) }
        }
      }
    }
  }

  func setFollowing(_ enabled: Bool) {
    followsInput = enabled
    defaults.set(enabled, forKey: "DeskMux.Experimental.AOCFollowsInput")
    followGate.candidate = nil
  }

  var source: String {
    guard let input else { return "Input not confirmed" }
    if input == route.studioInput { return "Studio · USB-C" }
    if input == route.macbookInput { return "MacBook · HDMI 1" }
    return "Other input (\(input))"
  }

  private var localDisplayUUID: String? {
    let ids = NSScreen.screens.compactMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 }
      .filter { CGDisplayVendorNumber($0) == 1507 && CGDisplayModelNumber($0) == 9987 }
    return PhysicalMonitorRoute.uniqueLocalDisplay(ids.compactMap { id in
      guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
      return CFUUIDCreateString(nil, uuid) as String
    })
  }

  var health: String {
    for screen in NSScreen.screens {
      guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
        let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
        (CFUUIDCreateString(nil, uuid) as String).caseInsensitiveCompare(localDisplayUUID ?? "") == .orderedSame,
        let mode = CGDisplayCopyDisplayMode(id) else { continue }
      let hz = mode.refreshRate > 0 ? String(format: "%.0f Hz", mode.refreshRate) : "Refresh rate unavailable"
      return "This Mac reports \(hz) · desktop \(mode.width) × \(mode.height). AOC panel: 4K / 60 Hz. Desktop scaling is not physical link resolution; cable bandwidth and active HDMI mode are not measured."
    }
    return "Monitor is not currently visible to macOS. Cable bandwidth and MacBook HDMI mode are not measured."
  }

  func refresh() { perform(target: nil) }
  func showStudio() { setFollowing(false); perform(target: route.studioInput) }
  func showMacBook() { setFollowing(false); perform(target: route.macbookInput) }

  private func perform(target: Int?) {
    guard !busy else { return }
    guard let displayUUID = localDisplayUUID else {
      failed = true; input = nil
      setFollowing(false)
      message = "Could not identify exactly one local AOC U27B3CF. No switch was attempted."
      return
    }
    busy = true; failed = false; input = nil
    message = target == nil ? "Reading monitor…" : "Switching and checking stability (up to 30 seconds)…"
    let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/deskmux-ddc")
    Task {
      let result: Result<Int, Error> = await Task.detached {
        do {
          let args = ["display", displayUUID]
          // Resolve the exact display and prove read access before issuing any write.
          let first = try MonitorDDC.run(helper: helper, arguments: args + ["get", "input"])
          guard let current = PhysicalMonitorRoute.parseInput(first) else { throw Self.readError() }
          guard let target else { return .success(current) }
          if current == target { return .success(current) }
          _ = try MonitorDDC.run(helper: helper, arguments: args + ["set", "input", String(target)])
          let deadline = Date().addingTimeInterval(30)
          var stable = 0
          while Date() < deadline {
            try await Task.sleep(for: .seconds(3))
            let output = try? MonitorDDC.run(helper: helper, arguments: args + ["get", "input"])
            let value = output.flatMap(PhysicalMonitorRoute.parseInput)
            stable = value == target ? stable + 1 : 0
            if stable >= 3 { return .success(target) }
          }
          throw NSError(domain: "Monitor", code: 3, userInfo: [NSLocalizedDescriptionKey: "The requested input did not stay selected. No automatic switch-back was sent. Check the destination Mac and use the monitor’s input menu if needed."])
        } catch { return .failure(error) }
      }.value
      busy = false
      followGate.nextAllowed = Date().addingTimeInterval(3)
      switch result {
      case .success(let value):
        input = value
        message = target == nil ? "Input read from the monitor." : "Input selection confirmed. Check the screen for the expected desktop; readback cannot verify the picture."
      case .failure(let error):
        let wasFollowing = followsInput
        setFollowing(false)
        failed = true
        message = "Local display \(displayUUID): " + error.localizedDescription + (wasFollowing ? " Automatic following was turned off; re-enable it after checking the monitor." : "")
      }
    }
  }

  nonisolated private static func readError() -> Error {
    NSError(domain: "Monitor", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not read this desk’s AOC monitor. No switch was attempted."])
  }
}

struct PhysicalMonitorCard: View {
  @ObservedObject var model: PhysicalMonitorModel
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label("AOC U27B3CF", systemImage: "display").font(.headline)
        Spacer()
        Text("LOCAL EXPERIMENT").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
      }
      Text(model.source).font(.title3.weight(.medium))
      Text("This desk: Studio USB-C ↔ MacBook HDMI 1. Only this monitor switches; keyboard and mouse routing stay unchanged.")
        .font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("Studio desk") { model.showStudio() }
        Button("Split desk") { model.showMacBook() }
        Spacer()
        Button("Refresh") { model.refresh() }
        if model.busy { ProgressView().controlSize(.small) }
      }.disabled(model.busy)
      Text("Studio desk: both screens on Studio. Split desk: AOC on MacBook, ViewSonic stays on Studio. Presets only switch the AOC; they turn off automatic following.")
        .font(.caption).foregroundStyle(.secondary)
      Toggle("AOC follows mouse and keyboard", isOn: Binding(get: { model.followsInput }, set: { model.setFollowing($0) }))
      Text("Waits for input ownership to settle. Rapid crossings are coalesced, not queued. Works with this window closed. Turning off stops future switches, not a command already sent.")
        .font(.caption).foregroundStyle(.secondary)
      Text(model.message).font(.caption).foregroundStyle(model.failed ? .red : .secondary)
      Divider()
      VisibleScreenWindowSettings(model: model.windows)
      Divider()
      Label("Connection health", systemImage: "waveform.path.ecg").font(.caption.weight(.semibold))
      Text(model.health).font(.caption).foregroundStyle(.secondary)
    }
    .padding(18)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
    .task { model.refresh() }
  }
}
