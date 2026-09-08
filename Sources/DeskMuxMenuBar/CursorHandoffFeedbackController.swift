import AppKit
import QuartzCore

enum CursorHandoffPhase {
  case preparing, sent, failed, waiting

  var detail: String {
    switch self {
    case .preparing: return "Preparing keyboard & mouse…"
    case .sent: return "Switch sent · mouse reconnecting…"
    case .failed: return "Check DeskMux for details"
    case .waiting: return "Check DeskMux for progress"
    }
  }
}

enum CursorHandoffLayout {
  static let size = NSSize(width: 252, height: 68)

  /// AppKit screen and mouse coordinates share a bottom-left origin. Place
  /// inward from an edge and keep the entire cue on the cursor's display.
  static func frame(near cursor: NSPoint, within screen: NSRect) -> NSRect {
    let safe = screen.insetBy(dx: 8, dy: 8)
    let width = min(size.width, safe.width)
    let height = min(size.height, safe.height)
    let preferredX = cursor.x + 20 + width <= safe.maxX
      ? cursor.x + 20 : cursor.x - 20 - width
    let preferredY = cursor.y - 16 - height >= safe.minY
      ? cursor.y - 16 - height : cursor.y + 16
    return NSRect(
      x: min(max(preferredX, safe.minX), safe.maxX - width),
      y: min(max(preferredY, safe.minY), safe.maxY - height),
      width: width, height: height
    )
  }
}

@MainActor
final class CursorHandoffFeedbackController {
  private var panel: CursorHandoffPanel?
  private var feedbackView: CursorHandoffFeedbackView?
  private var hideTask: Task<Void, Never>?
  private var token: UUID?
  private var destinationName = ""

  @discardableResult
  func begin(destinationName: String, pointsLeft: Bool) -> UUID {
    hide()
    let token = UUID()
    self.token = token
    self.destinationName = destinationName
    let cursor = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
      ?? NSScreen.main
    else { return token }

    let frame = CursorHandoffLayout.frame(near: cursor, within: screen.visibleFrame)
    let panel = CursorHandoffPanel(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false
    )
    panel.level = .screenSaver
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    let view = CursorHandoffFeedbackView(
      frame: NSRect(origin: .zero, size: frame.size), pointsLeft: pointsLeft)
    view.update(phase: .preparing, destinationName: destinationName)
    panel.contentView = view
    feedbackView = view
    self.panel = panel
    panel.orderFrontRegardless()

    // Do not leave a perpetual spinner if an XPC callback never arrives. This
    // changes only the cue; it does not cancel or misreport the actual handoff.
    hideTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(35))
      guard !Task.isCancelled, self?.token == token else { return }
      self?.feedbackView?.update(phase: .waiting, destinationName: destinationName)
      self?.hide(after: 3, token: token)
    }
    return token
  }

  func sent(ifCurrent expectedToken: UUID? = nil) {
    guard let token, expectedToken == nil || token == expectedToken else { return }
    feedbackView?.update(phase: .sent, destinationName: destinationName)
    // HID++ acceptance is not proof of Bluetooth reconnection. Deliberately
    // avoid a green checkmark or a "connected" claim here.
    hide(after: 2, token: token)
  }

  func failed() {
    guard let token else { return }
    feedbackView?.update(phase: .failed, destinationName: destinationName)
    hide(after: 3, token: token)
  }

  private func hide(after seconds: Double, token: UUID) {
    hideTask?.cancel()
    hideTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled, self?.token == token else { return }
      self?.hide()
    }
  }

  private func hide() {
    hideTask?.cancel()
    hideTask = nil
    feedbackView?.stopAnimating()
    panel?.orderOut(nil)
    panel = nil
    feedbackView = nil
    token = nil
  }
}

private final class CursorHandoffPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

final class CursorHandoffFeedbackView: NSView {
  private let title = NSTextField(labelWithString: "")
  private let subtitle = NSTextField(labelWithString: "")
  private let glyph = NSImageView()
  private let ring = CAShapeLayer()
  private let pointsLeft: Bool

  init(frame: NSRect, pointsLeft: Bool) {
    self.pointsLeft = pointsLeft
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 0.97).cgColor
    layer?.cornerRadius = 17
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.systemCyan.withAlphaComponent(0.55).cgColor

    ring.frame = NSRect(x: 13, y: 16, width: 36, height: 36)
    ring.path = CGPath(ellipseIn: CGRect(x: 2, y: 2, width: 32, height: 32), transform: nil)
    ring.fillColor = NSColor.clear.cgColor
    ring.strokeColor = NSColor.systemCyan.cgColor
    ring.lineWidth = 2
    ring.lineCap = .round
    ring.strokeEnd = 0.72
    layer?.addSublayer(ring)

    glyph.frame = NSRect(x: 23, y: 26, width: 16, height: 16)
    glyph.contentTintColor = .systemCyan
    addSubview(glyph)
    title.frame = NSRect(x: 61, y: 35, width: frame.width - 73, height: 18)
    title.font = .systemFont(ofSize: 12, weight: .semibold)
    title.textColor = .white
    subtitle.frame = NSRect(x: 61, y: 16, width: frame.width - 73, height: 16)
    subtitle.font = .systemFont(ofSize: 10)
    subtitle.textColor = NSColor.white.withAlphaComponent(0.78)
    addSubview(title)
    addSubview(subtitle)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func update(phase: CursorHandoffPhase, destinationName: String) {
    stopAnimating()
    let isPending = phase == .preparing || phase == .sent
    let color: NSColor = isPending ? .systemCyan : .systemOrange
    title.stringValue = switch phase {
    case .preparing, .sent: "To \(destinationName)"
    case .failed: "Switch failed"
    case .waiting: "Still waiting…"
    }
    subtitle.stringValue = phase.detail
    glyph.image = NSImage(
      systemSymbolName: isPending ? (pointsLeft ? "arrow.left" : "arrow.right") : "exclamationmark",
      accessibilityDescription: title.stringValue
    )
    glyph.contentTintColor = color
    ring.strokeColor = color.cgColor
    ring.strokeEnd = isPending ? 0.72 : 1
    layer?.borderColor = color.withAlphaComponent(0.55).cgColor
    if isPending, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      let spin = CABasicAnimation(keyPath: "transform.rotation.z")
      spin.fromValue = 0
      spin.toValue = -2 * Double.pi
      spin.duration = 0.9
      spin.repeatCount = .infinity
      ring.add(spin, forKey: "handoff-spin")
    }
  }

  func stopAnimating() { ring.removeAllAnimations() }
}
