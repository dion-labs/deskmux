import AppKit
import SwiftUI

enum DeskMuxPermissionPane: String, CaseIterable, Sendable {
  case inputMonitoring
  case accessibility
  case screenRecording

  var title: String {
    switch self {
    case .inputMonitoring: "Input Monitoring"
    case .accessibility: "Accessibility"
    case .screenRecording: "Screen & System Audio Recording"
    }
  }

  var settingsPane: String {
    switch self {
    case .inputMonitoring: "Privacy_ListenEvent"
    case .accessibility: "Privacy_Accessibility"
    case .screenRecording: "Privacy_ScreenCapture"
    }
  }

  var systemImage: String {
    switch self {
    case .inputMonitoring: "keyboard.badge.eye"
    case .accessibility: "accessibility"
    case .screenRecording: "rectangle.dashed.badge.record"
    }
  }
}

enum DeskMuxPermissionComponent: Sendable {
  case app
  case agent

  var displayName: String {
    switch self {
    case .app: "DeskMux"
    case .agent: "DeskMux Agent"
    }
  }

  func bundleURL(mainBundleURL: URL) -> URL {
    switch self {
    case .app:
      return mainBundleURL
    case .agent:
      return
        mainBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("LoginItems", isDirectory: true)
        .appendingPathComponent("DeskMux Agent.app", isDirectory: true)
    }
  }
}

struct DeskMuxPermissionAssistantRequest: Sendable {
  let pane: DeskMuxPermissionPane
  let component: DeskMuxPermissionComponent

  var instruction: String {
    "Drag \(component.displayName) into the \(pane.title) list"
  }
}

@MainActor
final class PermissionAssistantController {
  static let shared = PermissionAssistantController()

  private var panel: NSPanel?

  func present(
    pane: DeskMuxPermissionPane,
    component: DeskMuxPermissionComponent
  ) {
    let request = DeskMuxPermissionAssistantRequest(pane: pane, component: component)
    let appURL = component.bundleURL(mainBundleURL: Bundle.main.bundleURL)

    guard FileManager.default.fileExists(atPath: appURL.path) else {
      openSystemSettings(pane)
      return
    }

    openSystemSettings(pane)

    // Give System Settings enough time to put the requested privacy pane on screen,
    // then place our small drag source above it without hiding either window.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
      self?.showPanel(request: request, appURL: appURL)
    }
  }

  func dismiss() {
    panel?.orderOut(nil)
    panel = nil
  }

  private func openSystemSettings(_ pane: DeskMuxPermissionPane) {
    guard
      let url = URL(
        string:
          "x-apple.systempreferences:com.apple.preference.security?\(pane.settingsPane)"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }

  private func showPanel(
    request: DeskMuxPermissionAssistantRequest,
    appURL: URL
  ) {
    panel?.orderOut(nil)

    let content = PermissionAssistantView(
      request: request,
      appURL: appURL,
      reopenSettings: { [weak self] in
        self?.openSystemSettings(request.pane)
      },
      close: { [weak self] in
        self?.dismiss()
      }
    )

    let size = NSSize(width: 470, height: 144)
    let panel = PermissionAssistantPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.contentView = NSHostingView(rootView: content)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false

    if let screen = NSScreen.main ?? NSScreen.screens.first {
      let visible = screen.visibleFrame
      panel.setFrameOrigin(
        NSPoint(
          x: visible.midX - (size.width / 2),
          y: visible.minY + 34
        )
      )
    }

    self.panel = panel
    panel.orderFrontRegardless()
  }
}

private final class PermissionAssistantPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

private struct PermissionAssistantView: View {
  let request: DeskMuxPermissionAssistantRequest
  let appURL: URL
  let reopenSettings: () -> Void
  let close: () -> Void

  private var applicationIcon: NSImage {
    NSWorkspace.shared.icon(forFile: appURL.path)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(spacing: 9) {
        Image(systemName: "arrow.up")
          .font(.headline.weight(.bold))
        Text(request.instruction)
          .font(.headline)
          .lineLimit(1)
        Spacer()
        Button(action: close) {
          Image(systemName: "xmark")
            .font(.caption.weight(.bold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Close permission helper")
      }

      HStack(spacing: 11) {
        Image(nsImage: applicationIcon)
          .resizable()
          .scaledToFit()
          .frame(width: 30, height: 30)
        VStack(alignment: .leading, spacing: 1) {
          Text(request.component.displayName)
            .font(.callout.weight(.semibold))
          Text("Drag this row into System Settings, then turn its switch on.")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "line.3.horizontal")
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
      .contentShape(Rectangle())
      .onDrag {
        NSItemProvider(object: appURL as NSURL)
      } preview: {
        HStack(spacing: 8) {
          Image(nsImage: applicationIcon)
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
          Text(request.component.displayName)
            .font(.callout.weight(.semibold))
        }
        .padding(9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
      }

      HStack {
        Text("Already listed? Just enable the switch.")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Reopen System Settings", action: reopenSettings)
          .buttonStyle(.plain)
          .font(.caption)
      }
    }
    .padding(14)
    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .stroke(.white.opacity(0.14), lineWidth: 1)
    )
  }
}
