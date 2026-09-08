import AppKit
import QuartzCore

@MainActor
final class InputDestinationOverlayController {
  private var panels: [NSPanel] = []
  private var hideTask: Task<Void, Never>?

  func show(sourceName: String) {
    hide()
    panels = NSScreen.screens.map { screen in
      let panel = NSPanel(
        contentRect: screen.frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      panel.level = .screenSaver
      panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
      panel.backgroundColor = .clear
      panel.isOpaque = false
      panel.hasShadow = false
      panel.ignoresMouseEvents = true
      panel.contentView = InputDestinationOverlayView(
        frame: NSRect(origin: .zero, size: screen.frame.size),
        sourceName: sourceName
      )
      panel.orderFrontRegardless()
      return panel
    }
    hideTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      self?.hide()
    }
  }

  func hide() {
    hideTask?.cancel()
    hideTask = nil
    for panel in panels { panel.orderOut(nil) }
    panels.removeAll()
  }
}

private final class InputDestinationOverlayView: NSView {
  private let label = NSTextField(labelWithString: "")

  init(frame frameRect: NSRect, sourceName: String) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.borderWidth = 6
    layer?.borderColor = NSColor.systemCyan.cgColor
    layer?.cornerRadius = 12
    layer?.shadowColor = NSColor.systemCyan.cgColor
    layer?.shadowOpacity = 0.95
    layer?.shadowRadius = 18
    layer?.shadowOffset = .zero

    let pulse = CABasicAnimation(keyPath: "shadowOpacity")
    pulse.fromValue = 0.35
    pulse.toValue = 1.0
    pulse.duration = 0.85
    pulse.autoreverses = true
    pulse.repeatCount = .infinity
    layer?.add(pulse, forKey: "deskmux-input-pulse")

    label.stringValue = "DeskMux • Input from \(sourceName)"
    label.font = .systemFont(ofSize: 16, weight: .semibold)
    label.textColor = .white
    label.alignment = .center
    label.drawsBackground = true
    label.backgroundColor = NSColor.black.withAlphaComponent(0.72)
    label.wantsLayer = true
    label.layer?.cornerRadius = 9
    label.layer?.masksToBounds = true
    addSubview(label)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func layout() {
    super.layout()
    let labelWidth = min(CGFloat(330), max(CGFloat(220), bounds.width - 40))
    label.frame = NSRect(
      x: (bounds.width - labelWidth) / 2,
      y: bounds.height - 55,
      width: labelWidth,
      height: 34
    )
  }
}
