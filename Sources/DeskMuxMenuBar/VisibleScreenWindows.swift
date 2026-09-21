import AppKit
import ApplicationServices
import SwiftUI

struct VisibleScreenWindowSettings: View {
  @ObservedObject var model: VisibleScreenWindows
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle("Keep windows on visible screens", isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) }))
      Text("Enable separately on each Mac. Ordinary windows move off the hidden AOC after stable readback. Positions are remembered until DeskMux quits; windows you rearrange are not restored. Display layout and pointer boundaries stay unchanged.")
        .font(.caption).foregroundStyle(.secondary)
      Text(model.status).font(.caption).foregroundStyle(.secondary)
    }
  }
}

enum WindowPlacementGeometry {
  static func evacuate(_ window: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
    let width = min(window.width, destination.width)
    let height = min(window.height, destination.height)
    let x = destination.minX + max(0, window.minX - source.minX)
    let y = destination.minY + max(0, window.minY - source.minY)
    return CGRect(x: min(x, destination.maxX - width), y: min(y, destination.maxY - height), width: width, height: height)
  }
  static func unchanged(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 3 && abs(a.minY - b.minY) < 3 && abs(a.width - b.width) < 3 && abs(a.height - b.height) < 3
  }
}

@MainActor final class VisibleScreenWindows: ObservableObject {
  @Published private(set) var enabled: Bool
  @Published private(set) var status = "Off. Windows stay where macOS puts them."
  private var task: Task<Void, Never>?
  private var candidate: Int?
  private var matches = 0
  private let localPeerID: String
  private let engine = WindowPlacementEngine()

  init(localPeerID: String) {
    self.localPeerID = localPeerID
    enabled = UserDefaults.standard.bool(forKey: "DeskMux.KeepWindowsVisible")
  }
  func setEnabled(_ value: Bool) {
    enabled = value
    UserDefaults.standard.set(value, forKey: "DeskMux.KeepWindowsVisible")
    candidate = nil; matches = 0
    if !value {
      Task { await engine.clear() }
      status = "Off. Current positions kept; saved restoration positions cleared."
    }
  }
  func start() {
    guard task == nil else { return }
    task = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(4))
        guard let self else { return }
        if self.enabled { await self.check() }
      }
    }
  }

  private func check() async {
    guard AXIsProcessTrusted() else { status = "Accessibility access is required for window placement."; return }
    let screens = NSScreen.screens
    let frames = screens.map(\.frame)
    let matches = screens.filter {
      guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return false }
      return CGDisplayVendorNumber(id) == 1507 && CGDisplayModelNumber(id) == 9987
    }
    guard matches.count == 1, let monitor = matches.first,
      let id = monitor.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
      let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else {
      candidate = nil; self.matches = 0
      status = "Waiting for exactly one AOC U27B3CF. No windows moved."; return
    }
    let identity = CFUUIDCreateString(nil, uuid) as String
    let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/deskmux-ddc")
    let input = await Task.detached {
      (try? MonitorDDC.run(helper: helper, arguments: ["display", identity, "get", "input"]))
        .flatMap(PhysicalMonitorRoute.parseInput)
    }.value
    guard enabled else { return }
    guard frames == NSScreen.screens.map(\.frame) else {
      candidate = nil; self.matches = 0
      status = "Display layout changed. Waiting before moving windows."; return
    }
    guard let input, [17, 21].contains(input) else {
      candidate = nil; self.matches = 0
      status = "Input readback unavailable or unknown. Windows left untouched."; return
    }
    if candidate == input { self.matches += 1 } else { candidate = input; self.matches = 1 }
    guard self.matches >= 2 else { status = "Waiting for stable monitor input…"; return }
    // The active physical input, not keyboard ownership, decides visibility.
    let isMacBook = localPeerID == "macbook"
    let visible = input == (isMacBook ? 17 : 21)
    let top = screens.first?.frame.maxY ?? 0
    func axRect(_ rect: CGRect) -> CGRect {
      CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }
    let source = axRect(monitor.frame)
    let pids = NSWorkspace.shared.runningApplications.filter {
      $0.activationPolicy == .regular && $0.processIdentifier != getpid()
    }.map(\.processIdentifier)
    if visible {
      await engine.restore(source: source, pids: pids)
      status = "AOC is visible. Restoration checked; user changes and unsupported windows left untouched."
      return
    }
    let alternatives = screens.filter { $0 != monitor }
    guard let fallback = alternatives.first(where: { screen in
      guard let value = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return false }
      return CGDisplayIsBuiltin(value) != 0
    }) ?? alternatives.first else {
      status = "No other screen available. No windows moved."; return
    }
    let count = await engine.evacuate(source: source, destination: axRect(fallback.visibleFrame), pids: pids)
    if enabled { status = "AOC shows the other Mac. \(count) window(s) held on a visible screen. Full-screen, minimized and unsupported windows are skipped." }
  }
}

// AX calls can stall inside other apps. Keep them off the menu/edge-monitor
// main actor and serialize migration/restoration in this dedicated actor.
private actor WindowPlacementEngine {
  private struct Saved {
    let window: AXUIElement
    let pid: pid_t
    let original: CGRect
    let placed: CGRect
    let source: CGRect
  }
  private var saved: [Saved] = []
  func clear() { saved.removeAll() }

  private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
  }
  private func rect(_ window: AXUIElement) -> CGRect? {
    guard let p = attribute(window, kAXPositionAttribute), let s = attribute(window, kAXSizeAttribute),
      CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero; var size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
  }
  private func eligible(_ window: AXUIElement) -> Bool {
    guard attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
      attribute(window, kAXMinimizedAttribute) as? Bool != true,
      attribute(window, "AXFullScreen") as? Bool != true else { return false }
    var position: DarwinBoolean = false; var size: DarwinBoolean = false
    AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &position)
    AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &size)
    return position.boolValue && size.boolValue
  }
  private func place(_ window: AXUIElement, _ frame: CGRect) {
    var size = frame.size; var point = frame.origin
    if let value = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) }
    if let value = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) }
  }
  func evacuate(source: CGRect, destination: CGRect, pids: [pid_t]) -> Int {
    saved.removeAll { !pids.contains($0.pid) }
    for pid in pids {
      let element = AXUIElementCreateApplication(pid)
      AXUIElementSetMessagingTimeout(element, 0.15)
      guard let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] else { continue }
      for window in windows {
        guard eligible(window), let original = rect(window),
          source.contains(CGPoint(x: original.midX, y: original.midY)),
          !saved.contains(where: { CFEqual($0.window, window) }) else { continue }
        let target = WindowPlacementGeometry.evacuate(original, from: source, to: destination)
        place(window, target)
        if let actual = rect(window), WindowPlacementGeometry.unchanged(actual, target) {
          saved.append(Saved(window: window, pid: pid, original: original, placed: actual, source: source))
        }
      }
    }
    return saved.count
  }
  func restore(source: CGRect, pids: [pid_t]) {
    for record in saved {
      guard pids.contains(record.pid),
        WindowPlacementGeometry.unchanged(source, record.source), eligible(record.window),
        let current = rect(record.window), WindowPlacementGeometry.unchanged(current, record.placed) else { continue }
      place(record.window, record.original)
    }
    saved.removeAll()
  }
}
