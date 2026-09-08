import AppKit
@preconcurrency import ApplicationServices
import DeskMuxAgentIPC
import DeskMuxCore
import DeskMuxInputTransport
import DeskMuxMacInput
import Security
import SwiftUI

@main
struct DeskMuxMenuBarApp: App {
  @StateObject private var permissions: PermissionModel
  @StateObject private var inputRelay: InputRelayModel
  @StateObject private var backgroundAgent: BackgroundAgentModel
  @StateObject private var screenViewer: ScreenViewerModel
  @StateObject private var launchAtLogin: LaunchAtLoginModel

  init() {
    let permissions = PermissionModel()
    let inputRelay = InputRelayModel()
    let backgroundAgent = BackgroundAgentModel(localPeerID: inputRelay.localPeerID.rawValue)
    let screenViewer = ScreenViewerModel(
      localPeerID: inputRelay.localPeerID.rawValue,
      destinationPeerID: inputRelay.destinationPeerID.rawValue,
      sharedKey: inputRelay.agentSharedKey
    )
    inputRelay.configure(permissions: permissions.status)
    backgroundAgent.configureReceiver(
      peerID: inputRelay.localPeerID.rawValue,
      sharedKey: inputRelay.agentSharedKey
    )
    _permissions = StateObject(wrappedValue: permissions)
    _inputRelay = StateObject(wrappedValue: inputRelay)
    _backgroundAgent = StateObject(wrappedValue: backgroundAgent)
    _screenViewer = StateObject(wrappedValue: screenViewer)
    _launchAtLogin = StateObject(wrappedValue: LaunchAtLoginModel())
  }

  var body: some Scene {
    MenuBarExtra {
      DeskMuxCompactPanel(
        permissions: permissions,
        inputRelay: inputRelay,
        backgroundAgent: backgroundAgent
      )
    } label: {
      DeskMuxMenuBarStatusIcon(
        permissions: permissions,
        inputRelay: inputRelay,
        backgroundAgent: backgroundAgent
      )
    }
    .menuBarExtraStyle(.window)

    Settings {
      DeskMuxSettingsWindow(
        permissions: permissions,
        inputRelay: inputRelay,
        backgroundAgent: backgroundAgent,
        screenViewer: screenViewer,
        launchAtLogin: launchAtLogin
      )
    }

    WindowGroup("DeskMux Remote Display", id: "remote-display") {
      DeskMuxScreenViewerWindow(model: screenViewer)
    }
    .defaultSize(width: 960, height: 600)
  }
}

@MainActor
private func peerIsConnected(
  inputRelay: InputRelayModel,
  backgroundAgent: BackgroundAgentModel
) -> Bool {
  let peerAdvertisesBothComponents =
    inputRelay.peerVersions.appServiceFound && inputRelay.peerVersions.agentServiceFound
  return peerAdvertisesBothComponents
    || backgroundAgent.agentStatus?.warmConnectionState == .ready
}

@MainActor
private func localSetupIsReady(
  permissions: PermissionModel,
  backgroundAgent: BackgroundAgentModel
) -> Bool {
  permissions.allGranted
    && backgroundAgent.isEnabled
    && backgroundAgent.agentStatus?.canListen == true
    && backgroundAgent.agentStatus?.canPost == true
    && backgroundAgent.receiverReady
}

private struct DeskMuxMenuBarStatusIcon: View {
  @ObservedObject var permissions: PermissionModel
  @ObservedObject var inputRelay: InputRelayModel
  @ObservedObject var backgroundAgent: BackgroundAgentModel

  private var connected: Bool {
    peerIsConnected(inputRelay: inputRelay, backgroundAgent: backgroundAgent)
  }

  private var setupReady: Bool {
    localSetupIsReady(permissions: permissions, backgroundAgent: backgroundAgent)
  }

  private var inputIsLocal: Bool {
    backgroundAgent.inputOwnerName
      == (inputRelay.localPeerID.rawValue == "studio" ? "Studio" : "MacBook")
  }

  private var statusColor: Color {
    if !setupReady { return .orange }
    return connected ? .green : .red
  }

  private var statusDescription: String {
    if !setupReady { return "DeskMux needs setup attention" }
    return connected ? "Both Macs connected" : "Paired Mac unavailable"
  }

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      MuxMark()
        .fill(.primary, style: FillStyle(eoFill: true))
        .frame(width: 20, height: 19)
        .opacity(inputIsLocal ? 1 : 0.7)
      Circle()
        .fill(statusColor)
        .frame(width: 6, height: 6)
        .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 0.5))
        .offset(x: 2, y: 1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(statusDescription). Input is on \(backgroundAgent.inputOwnerName)."
    )
  }
}

private struct DeskMuxCompactPanel: View {
  @ObservedObject var permissions: PermissionModel
  @ObservedObject var inputRelay: InputRelayModel
  @ObservedObject var backgroundAgent: BackgroundAgentModel
  @Environment(\.openSettings) private var openSettings

  private var connected: Bool {
    peerIsConnected(inputRelay: inputRelay, backgroundAgent: backgroundAgent)
  }

  private var setupReady: Bool {
    localSetupIsReady(permissions: permissions, backgroundAgent: backgroundAgent)
  }

  private var localName: String {
    inputRelay.localPeerID.rawValue == "studio" ? "Studio" : "MacBook"
  }

  private var destinationPeerID: String {
    inputRelay.localPeerID.rawValue == "studio" ? "macbook" : "studio"
  }

  private var destinationName: String {
    destinationPeerID == "studio" ? "Studio" : "MacBook"
  }

  private var canSwitchFromThisMac: Bool {
    guard let currentHost = backgroundAgent.logitechStatus?.currentHost,
      backgroundAgent.logitechStatus?.isReady == true,
      let localHost = backgroundAgent.configuredLogitechHost(
        peerID: inputRelay.localPeerID.rawValue),
      backgroundAgent.configuredLogitechHost(peerID: destinationPeerID) != nil
    else { return false }
    return currentHost == localHost
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        MuxMark()
          .fill(DeskMuxBrand.teal, style: FillStyle(eoFill: true))
          .frame(width: 30, height: 30)
        VStack(alignment: .leading, spacing: 2) {
          Text("DeskMux")
            .font(.headline)
          Text(connected ? "Connected to \(destinationName)" : "\(destinationName) unavailable")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Circle()
          .fill(!setupReady ? Color.orange : connected ? Color.green : Color.red)
          .frame(width: 9, height: 9)
      }

      HStack(spacing: 12) {
        Image(
          systemName: backgroundAgent.inputOwnerName == "Studio"
            ? "display" : "laptopcomputer"
        )
        .font(.title2)
        .foregroundStyle(.tint)
        .frame(width: 34)
        VStack(alignment: .leading, spacing: 2) {
          Text("Input is on \(backgroundAgent.inputOwnerName)")
            .font(.callout.weight(.semibold))
          Text("Keyboard and Logitech mouse move together")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(11)
      .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))

      if canSwitchFromThisMac,
        backgroundAgent.inputOwnerName == localName
      {
        Button(backgroundAgent.logitechSwitching ? "Switching…" : "Switch to \(destinationName)") {
          backgroundAgent.switchLogitechMouse(
            from: inputRelay.localPeerID.rawValue,
            to: destinationPeerID
          )
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .disabled(backgroundAgent.logitechSwitching)
      }

      if backgroundAgent.agentStatus?.receiverState == .receiving {
        Button("Return Input to Source") {
          backgroundAgent.returnInputToSource()
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
      }

      if !setupReady || !connected || backgroundAgent.logitechFlowConflict {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(!setupReady || backgroundAgent.logitechFlowConflict ? .orange : .red)
          VStack(alignment: .leading, spacing: 2) {
            Text(
              !setupReady
                ? "DeskMux needs setup attention"
                : backgroundAgent.logitechFlowConflict
                  ? "Logitech Flow is conflicting"
                  : "\(destinationName) is not reachable"
            )
            .font(.caption.weight(.semibold))
            Text("Open Settings for details and recovery controls.")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }

      Divider()

      HStack {
        Button("Settings…", systemImage: "gearshape") {
          NSApplication.shared.activate(ignoringOtherApps: true)
          openSettings()
        }
        Spacer()
        Button("Quit") {
          NSApplication.shared.terminate(nil)
        }
      }
    }
    .padding(16)
    .frame(width: 320)
    .task {
      while !Task.isCancelled {
        permissions.refresh()
        inputRelay.observeAgentStatus(backgroundAgent.agentStatus)
        inputRelay.configure(permissions: permissions.status)
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }
}

private struct DeskMuxSettingsWindow: View {
  @ObservedObject var permissions: PermissionModel
  @ObservedObject var inputRelay: InputRelayModel
  @ObservedObject var backgroundAgent: BackgroundAgentModel
  @ObservedObject var screenViewer: ScreenViewerModel
  @ObservedObject var launchAtLogin: LaunchAtLoginModel

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      DeskMuxBrandHeader()
      TabView {
      GeneralSettingsPage(
        inputRelay: inputRelay,
        backgroundAgent: backgroundAgent,
        launchAtLogin: launchAtLogin
      )
        .tabItem { Label("General", systemImage: "switch.2") }

      ConnectionSettingsPage(inputRelay: inputRelay, backgroundAgent: backgroundAgent)
        .tabItem { Label("Connection", systemImage: "network") }

      DisplaySettingsPage(model: screenViewer, backgroundAgent: backgroundAgent)
        .tabItem { Label("Displays · Preview", systemImage: "display.2") }

      PermissionsSettingsPage(permissions: permissions, backgroundAgent: backgroundAgent)
        .tabItem { Label("Permissions", systemImage: "hand.raised") }
      }
    }
    .tint(DeskMuxBrand.teal)
    .padding(20)
    .frame(width: 720, height: 670)
    .task {
      while !Task.isCancelled {
        permissions.refresh()
        inputRelay.observeAgentStatus(backgroundAgent.agentStatus)
        inputRelay.configure(permissions: permissions.status)
        launchAtLogin.refresh()
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }
}

private struct DisplaySettingsPage: View {
  @ObservedObject var model: ScreenViewerModel
  @ObservedObject var backgroundAgent: BackgroundAgentModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsPageHeader(
        title: "Virtual displays",
        subtitle: "Open an additional display rendered by your paired Mac."
      )
      HStack(spacing: 14) {
        Image(systemName: "rectangle.inset.filled.and.person.filled")
          .font(.largeTitle)
          .foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 3) {
          Text("\(model.destinationName) virtual display")
            .font(.headline)
          Text(model.statusText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Open Display") {
          openWindow(id: "remote-display")
        }
        .buttonStyle(.borderedProminent)
      }
      .padding(16)
      .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
      Text(
        "The source Mac treats this as a real 1920×1200 HiDPI monitor. The display exists only while its DeskMux window is open."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      HStack(alignment: .top, spacing: 12) {
        Image(
          systemName: backgroundAgent.agentStatus?.canCaptureScreen == true
            ? "checkmark.circle.fill" : "record.circle"
        )
        .foregroundStyle(
          backgroundAgent.agentStatus?.canCaptureScreen == true ? .green : .orange
        )
        VStack(alignment: .leading, spacing: 4) {
          Text("Share this Mac")
            .font(.callout.weight(.semibold))
          Text(
            backgroundAgent.agentStatus?.canCaptureScreen == true
              ? "DeskMux Agent can create and stream a virtual display from this Mac."
              : "Allow DeskMux Agent in Screen & System Audio Recording, then restart the agent."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          if backgroundAgent.agentStatus?.canCaptureScreen != true {
            HStack {
              Button("Allow") {
                backgroundAgent.requestScreenCapturePermission()
                PermissionAssistantController.shared.present(
                  pane: .screenRecording,
                  component: .agent
                )
              }
              Button("Restart Agent") { backgroundAgent.restartAgent() }
            }
            .controlSize(.small)
          }
        }
        Spacer()
      }
      .padding(14)
      .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
      Spacer()
    }
    .padding(.vertical, 4)
  }
}

private struct SettingsPageHeader: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.title2.weight(.semibold))
      Text(subtitle)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct GeneralSettingsPage: View {
  @ObservedObject var inputRelay: InputRelayModel
  @ObservedObject var backgroundAgent: BackgroundAgentModel
  @ObservedObject var launchAtLogin: LaunchAtLoginModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        SettingsPageHeader(
          title: "Input switching",
          subtitle: "Choose how the pointer edge moves your keyboard and mouse between Macs."
        )

        HStack(spacing: 12) {
          Image(systemName: "cursorarrow.motionlines")
            .font(.title2)
            .foregroundStyle(.tint)
          VStack(alignment: .leading, spacing: 2) {
            Text("Input is currently on \(backgroundAgent.inputOwnerName)")
              .font(.headline)
            Text("Keyboard anchor: \(inputRelay.anchorName)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
        .padding(14)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))

        LogitechMouseSection(model: backgroundAgent, localPeerID: inputRelay.localPeerID)

        Divider()

        VStack(alignment: .leading, spacing: 10) {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text("Launch DeskMux at login")
                .font(.callout.weight(.semibold))
              Text(launchAtLogin.statusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(
              "Launch DeskMux at login",
              isOn: Binding(
                get: { launchAtLogin.isRequested },
                set: { launchAtLogin.setEnabled($0) }
              )
            )
            .labelsHidden()
          }

          if launchAtLogin.status == .requiresApproval {
            Button("Open Login Items") { launchAtLogin.openLoginItems() }
              .controlSize(.small)
          }
          if let message = launchAtLogin.message {
            Text(message)
              .font(.caption)
              .foregroundStyle(launchAtLogin.hasError ? .red : .secondary)
          }
        }
        .padding(14)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
      }
      .padding(.vertical, 4)
    }
  }
}

private struct ConnectionSettingsPage: View {
  @ObservedObject var inputRelay: InputRelayModel
  @ObservedObject var backgroundAgent: BackgroundAgentModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        SettingsPageHeader(
          title: "Connection",
          subtitle:
            "Pair the two Macs, verify their encrypted link, and keep versions synchronized."
        )
        HStack(spacing: 10) {
          Circle()
            .fill(
              peerIsConnected(inputRelay: inputRelay, backgroundAgent: backgroundAgent)
                ? Color.green : Color.red
            )
            .frame(width: 9, height: 9)
          Text(
            peerIsConnected(inputRelay: inputRelay, backgroundAgent: backgroundAgent)
              ? "\(inputRelay.destinationName) is connected"
              : "\(inputRelay.destinationName) is unavailable"
          )
          .font(.headline)
          Spacer()
        }
        .padding(14)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
        InputRelaySection(model: inputRelay)
      }
      .padding(.vertical, 4)
    }
  }
}

private struct PermissionsSettingsPage: View {
  @ObservedObject var permissions: PermissionModel
  @ObservedObject var backgroundAgent: BackgroundAgentModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        SettingsPageHeader(
          title: "Permissions & background agent",
          subtitle:
            "These are one-time setup requirements. Return here only when macOS needs attention."
        )

        VStack(spacing: 12) {
          PermissionRow(
            title: "Input capture",
            detail: permissions.status.canListen
              ? "Keyboard and mouse event capture is available"
              : "Requires Accessibility or Input Monitoring",
            isGranted: permissions.status.canListen,
            allow: { permissions.guidePermission(.inputMonitoring) }
          )
          PermissionRow(
            title: "Accessibility",
            detail: "Control the keyboard on the destination Mac",
            isGranted: permissions.status.canPost,
            allow: { permissions.guidePermission(.accessibility) }
          )
        }
        .padding(14)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))

        if permissions.allGranted {
          VStack(alignment: .leading, spacing: 9) {
            Label("DeskMux has the required app permissions", systemImage: "checkmark.circle.fill")
              .font(.callout.weight(.semibold))
              .foregroundStyle(.green)

            switch permissions.selfTestState {
            case .idle:
              Text("Run a local five-second capture test if input permissions seem stale.")
                .font(.caption)
                .foregroundStyle(.secondary)
            case .running:
              HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Testing… move the mouse, scroll, and press Shift.")
                  .font(.caption)
              }
            case .passed(let eventCount):
              Label("Passed — received \(eventCount) events", systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(.green)
            case .failed(let message):
              Label(message, systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
            }

            Button("Run 5-Second Input Test") { permissions.runInputSelfTest() }
              .disabled(permissions.selfTestState == .running)
          }
        } else {
          VStack(alignment: .leading, spacing: 10) {
            Text("DeskMux needs both permissions before it can switch input safely.")
              .font(.callout)
              .foregroundStyle(.secondary)
            Button("Set Up Next Permission") {
              permissions.guideNextMissingPermission()
            }
            .buttonStyle(.borderedProminent)
            HStack {
              Text("Already enabled them? macOS may require an app restart.")
                .font(.caption)
                .foregroundStyle(.secondary)
              Spacer()
              Button("Restart DeskMux") { permissions.restartApplication() }
            }
          }
        }

        Divider()
        BackgroundAgentSection(model: backgroundAgent)
      }
      .padding(.vertical, 4)
    }
  }
}

private struct LogitechMouseSection: View {
  @ObservedObject var model: BackgroundAgentModel
  let localPeerID: PeerID

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Label("Native Logitech mouse", systemImage: "computermouse")
          .font(.callout.weight(.semibold))
        Spacer()
        if model.logitechStatus?.isReady == true {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }
      }

      if let status = model.logitechStatus, status.isReady,
        let currentHost = status.currentHost, let hostCount = status.hostCount
      {
        Text(
          "Mouse channel \(currentHost + 1) is active on this \(localPeerID.rawValue == "studio" ? "Studio" : "MacBook") (\(hostCount) channels available)."
        )
        .font(.caption)
        .foregroundStyle(.green)
        Text(
          "\(status.deviceName ?? "Logitech mouse") via \(status.transport ?? "HID++"). The pointer switches natively; DeskMux routes only the keyboard."
        )
        .font(.caption2)
        .foregroundStyle(.secondary)

        let destinationPeerID = localPeerID.rawValue == "studio" ? "macbook" : "studio"
        if let localHost = model.configuredLogitechHost(peerID: localPeerID.rawValue),
          let targetHost = model.configuredLogitechHost(peerID: destinationPeerID),
          localHost == currentHost
        {
          Button(
            model.logitechSwitching
              ? "Switching…"
              : "Switch Input to \(destinationPeerID == "studio" ? "Studio" : "MacBook") (Mouse Channel \(targetHost + 1))"
          ) {
            model.switchLogitechMouse(
              from: localPeerID.rawValue,
              to: destinationPeerID
            )
          }
          .buttonStyle(.borderedProminent)
          .disabled(model.logitechSwitching)
        }
      } else if let error = model.logitechStatus?.error {
        Text(error)
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Text("Checking for a local HID++ Easy-Switch path…")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      HStack {
        Text(
          model.configuredLogitechHost(peerID: "studio") != nil
            && model.configuredLogitechHost(peerID: "macbook") != nil
            ? "Native mapping ready: Studio channel 1 ↔ MacBook channel 2."
            : "Switch controls unlock after both Macs identify their return channel."
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        Spacer()
        Button("Recheck") { model.refreshLogitechStatus() }
          .controlSize(.small)
      }

      if let message = model.logitechMessage {
        Text(message)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Divider()

      if model.logitechFlowConflict {
        Label("Logitech Flow is enabled on this Mac", systemImage: "exclamationmark.triangle.fill")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.orange)
        Text(
          "Flow can move the mouse without starting DeskMux’s keyboard relay. Disable it on each Mac where this warning appears."
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        Button(model.disablingLogitechFlow ? "Disabling Flow…" : "Disable Flow on This Mac") {
          model.disableLogitechFlow()
        }
        .controlSize(.small)
        .disabled(model.disablingLogitechFlow)
      }

      Toggle(
        "Keyboard follows native mouse",
        isOn: Binding(
          get: { model.edgeSwitchConfiguration.enabled },
          set: { model.setEdgeSwitchEnabled($0) }
        )
      )
      .toggleStyle(.switch)

      HStack {
        Label("Input owner: \(model.inputOwnerName)", systemImage: "cursorarrow.motionlines")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.green)
        Spacer()
      }

      Text(
        model.edgeSwitchConfiguration.triggerMode == .holdModifier
          ? "Hold the selected key while touching the configured edge for an immediate handoff. The edge does nothing without the key."
          : "Push through the configured edge to switch the keyboard relay and Logitech mouse after a short delay."
      )
      .font(.caption2)
      .foregroundStyle(.secondary)

      Button("Preview cursor cue") { model.previewHandoffFeedback() }
        .controlSize(.small)
        .disabled(model.logitechSwitching)
        .help("Preview the animation without switching the mouse or keyboard.")

      if model.edgeSwitchConfiguration.enabled {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Picker(
              "Trigger",
              selection: Binding(
                get: { model.edgeSwitchConfiguration.triggerMode },
                set: { model.setEdgeSwitchTriggerMode($0) }
              )
            ) {
              Text("Hold key + edge").tag(MacPointerEdgeTriggerMode.holdModifier)
              Text("Push + wait").tag(MacPointerEdgeTriggerMode.pushAndDwell)
            }
            Picker(
              "Edge",
              selection: Binding(
                get: { model.edgeSwitchConfiguration.edge },
                set: { model.setEdgeSwitchEdge($0) }
              )
            ) {
              Text("Left edge").tag(MacPointerEdge.left)
              Text("Right edge").tag(MacPointerEdge.right)
            }
          }

          if model.edgeSwitchConfiguration.triggerMode == .holdModifier {
            Picker(
              "Hold",
              selection: Binding(
                get: { model.edgeSwitchConfiguration.modifier },
                set: { model.setEdgeSwitchModifier($0) }
              )
            ) {
              ForEach(MacPointerEdgeModifier.allCases, id: \.self) { modifier in
                Text(modifier.displayName).tag(modifier)
              }
            }
          } else {
            Picker(
              "Delay",
              selection: Binding(
                get: { model.edgeSwitchConfiguration.dwellMilliseconds },
                set: { model.setEdgeSwitchDwell(milliseconds: $0) }
              )
            ) {
              Text("0.15 s").tag(150)
              Text("0.20 s").tag(200)
              Text("0.30 s").tag(300)
              Text("0.50 s").tag(500)
            }
          }
        }
        .pickerStyle(.menu)
      }

      if let edgeMessage = model.edgeSwitchMessage {
        Text(edgeMessage)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct BackgroundAgentSection: View {
  @ObservedObject var model: BackgroundAgentModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Stable background agent", systemImage: "gearshape.2")
          .font(.callout.weight(.semibold))
        Spacer()
        if model.agentStatus != nil {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }
      }

      Text(
        "Keeps DeskMux's identity and permissions stable while the menu app is updated. macOS lists it separately as DeskMux Agent."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      if let permissions = model.permissionsSummary {
        Text(permissions)
          .font(.caption)
          .foregroundStyle(
            model.agentStatus?.canListen == true && model.agentStatus?.canPost == true
              ? .green : .orange)
      }

      if let receiver = model.receiverSummary {
        Label(
          receiver,
          systemImage: model.receiverReady
            ? "antenna.radiowaves.left.and.right.circle.fill"
            : "antenna.radiowaves.left.and.right"
        )
        .font(.caption)
        .foregroundStyle(
          model.agentStatus?.receiverState == .failed
            ? .red : model.receiverReady ? .green : .secondary)
      }

      if let keyboardRelay = model.keyboardRelaySummary {
        Label(keyboardRelay, systemImage: "keyboard")
          .font(.caption)
          .foregroundStyle(
            model.agentStatus?.keyboardRelayState == .failed
              ? .red : model.agentStatus?.keyboardRelayState == .active ? .green : .orange)
      }

      if let warmConnection = model.warmConnectionSummary {
        Label(warmConnection, systemImage: "bolt.horizontal.circle")
          .font(.caption)
          .foregroundStyle(
            model.agentStatus?.warmConnectionState == .ready ? .green : .orange)
      }

      if model.agentStatus?.receiverState == .receiving {
        Button("Return Input to Source") {
          model.returnInputToSource()
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
      }

      if let message = model.message {
        Text(message)
          .font(.caption)
          .foregroundStyle(model.hasError ? .red : .secondary)
      }

      HStack {
        if !model.isEnabled && !model.needsApproval {
          Button("Enable Background Agent") {
            model.enable()
          }
          .buttonStyle(.borderedProminent)
        }
        if model.needsApproval {
          Button("Open Login Items to Approve") {
            model.openLoginItems()
          }
          .buttonStyle(.borderedProminent)
        }
        if model.isEnabled,
          let status = model.agentStatus,
          !status.canListen || !status.canPost
        {
          if !status.canListen {
            Button("Allow Input Monitoring") {
              model.requestAgentPermissions()
              PermissionAssistantController.shared.present(
                pane: .inputMonitoring,
                component: .agent
              )
            }
          }
          if !status.canPost {
            Button("Allow Accessibility") {
              model.requestAgentPermissions()
              PermissionAssistantController.shared.present(
                pane: .accessibility,
                component: .agent
              )
            }
          }
        }
        Spacer()
        Button("Recheck") {
          model.refresh()
        }
        .controlSize(.small)
      }
    }
  }
}

private struct InputRelaySection: View {
  @ObservedObject var model: InputRelayModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let receipt = model.updateReceipt {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "arrow.down.app.fill")
            .foregroundStyle(.cyan)
          VStack(alignment: .leading, spacing: 2) {
            Text("DeskMux was updated")
              .font(.caption.weight(.semibold))
            Text(model.updateReceiptDescription(receipt))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            model.dismissUpdateReceipt()
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.plain)
          .help("Dismiss update notice")
        }
        .padding(9)
        .background(.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
      }

      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Encrypted input link")
            .font(.callout.weight(.semibold))
          Text("This Mac is “\(model.localPeerID.rawValue)”")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Label(
          model.receiverLabel,
          systemImage: model.receiverReady ? "antenna.radiowaves.left.and.right" : "clock"
        )
        .font(.caption)
        .foregroundStyle(model.receiverReady ? .green : .secondary)
      }

      Text("Use the same pairing code on both Macs")
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Label("Keyboard anchor: \(model.anchorName)", systemImage: "keyboard")
            .font(.callout.weight(.semibold))
          Spacer()
          if !model.isLocalAnchor {
            Button("Make This Mac Anchor") {
              model.makeThisMacAnchor()
            }
            .controlSize(.small)
          }
        }
        Text(
          "Keep the physical keyboard connected to \(model.anchorName). The Logitech mouse changes channels natively."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      if model.isReceivingInput {
        Button("Return Input to \(model.activeSourceName)") {
          model.returnInputToSource()
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
      }

      HStack(spacing: 7) {
        TextField("Pairing code", text: $model.pairingCodeDraft)
          .textFieldStyle(.roundedBorder)
          .font(.system(.caption, design: .monospaced))
        Button("Save") { model.savePairingCode() }
          .disabled(!model.hasUnsavedPairingCode)
        Button {
          model.copyPairingCode()
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .help("Copy pairing code")
      }

      if let message = model.message {
        Text(message)
          .font(.caption)
          .foregroundStyle(model.hasError ? .red : .secondary)
      }

      if model.needsLocalNetworkPermission {
        Button("Open Local Network Settings") {
          model.openLocalNetworkSettings()
        }
      }

      Button("Test Keyboard on \(model.destinationName) for 15 Seconds") {
        model.sendInput()
      }
      .buttonStyle(.borderedProminent)
      .disabled(
        !model.isLocalAnchor || !model.receiverReady || model.relayRunning
          || model.hasUnsavedPairingCode)

      if !model.isLocalAnchor {
        Text("Handoff is disabled here because \(model.anchorName) is the configured anchor.")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Divider()
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: model.versionsSynchronized ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath.circle")
          .foregroundStyle(model.versionsSynchronized ? .green : .orange)
        VStack(alignment: .leading, spacing: 2) {
          Text("DeskMux versions")
            .font(.caption.weight(.semibold))
          Text(model.versionSummary)
            .font(.caption2)
            .foregroundStyle(model.versionsSynchronized ? .green : .secondary)
        }
        Spacer()
      }

      if model.canSendMacBookUpdate {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("MacBook update available")
              .font(.caption.weight(.semibold))
            Text("Send the newer signed Studio build over the encrypted link")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button(model.updateRunning ? "Sending…" : "Send Update") {
            model.sendUpdateToMacBook()
          }
          .disabled(model.updateRunning || model.relayRunning || model.hasUnsavedPairingCode)
        }
        if let updateMessage = model.updateMessage {
          Text(updateMessage)
            .font(.caption2)
            .foregroundStyle(model.updateFailed ? .red : .secondary)
        }
      }

      Text(
        "Only keyboard events are captured. The mouse, clicks, and scrolling remain native and local throughout the test."
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
  }
}

private struct PermissionRow: View {
  let title: String
  let detail: String
  let isGranted: Bool
  let allow: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        .foregroundStyle(isGranted ? .green : .orange)
        .font(.title3)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(.medium))
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if !isGranted {
        Button("Allow") {
          allow()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
    }
  }
}

@MainActor
private final class PermissionModel: ObservableObject {
  @Published private(set) var status = MacInputPermissions.status()
  @Published private(set) var selfTestState: SelfTestState = .idle

  var allGranted: Bool { status.canListen && status.canPost }

  func refresh() {
    status = MacInputPermissions.status()
  }

  func guideNextMissingPermission() {
    guidePermission(status.canListen ? .accessibility : .inputMonitoring)
  }

  func guidePermission(_ pane: DeskMuxPermissionPane) {
    switch pane {
    case .inputMonitoring:
      _ = CGRequestListenEventAccess()
    case .accessibility:
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
      _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
      _ = CGRequestPostEventAccess()
    case .screenRecording:
      break
    }
    refresh()
    PermissionAssistantController.shared.present(pane: pane, component: .app)
  }

  func runInputSelfTest() {
    guard allGranted, selfTestState != .running else { return }
    selfTestState = .running
    Task {
      let outcome = await Task.detached(priority: .userInitiated) {
        do {
          let report = try MacInputLoopback.run(durationSeconds: 5)
          if report.relayedEventCount == 0 {
            return SelfTestState.failed(
              "No input events were observed; run the test again and move the mouse.")
          }
          return SelfTestState.passed(eventCount: report.relayedEventCount)
        } catch {
          return SelfTestState.failed(String(describing: error))
        }
      }.value
      selfTestState = outcome
      refresh()
    }
  }

  func restartApplication() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-n", Bundle.main.bundlePath]
    do {
      try process.run()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        NSApplication.shared.terminate(nil)
      }
    } catch {
      // Keep the current instance alive if relaunching fails.
    }
  }

}

private enum SelfTestState: Equatable, Sendable {
  case idle
  case running
  case passed(eventCount: Int)
  case failed(String)
}

@MainActor
private final class InputRelayModel: ObservableObject {
  let localPeerID: PeerID
  let destinationPeerID: PeerID

  @Published var pairingCodeDraft: String
  @Published private(set) var receiverState: BonjourInputReceiverState = .stopped
  @Published private(set) var anchorPeerID: PeerID
  @Published private(set) var relayRunning = false
  @Published private(set) var message: String?
  @Published private(set) var hasError = false
  @Published private(set) var needsLocalNetworkPermission = false
  @Published private(set) var updateRunning = false
  @Published private(set) var updateMessage: String?
  @Published private(set) var updateFailed = false
  @Published private(set) var updateReceipt: DeskMuxAppUpdateReceipt?
  @Published private(set) var peerVersions = DeskMuxPeerVersionSnapshot()
  @Published private(set) var localAgentBuild: String?

  private var savedPairingCode: String
  private var receiver: BonjourInputReceiver?
  private var activeRelay: BonjourInputRelaySource?
  private var updateTriggerObserver: NSObjectProtocol?
  private var researchTriggerObserver: NSObjectProtocol?
  private var versionMonitor: BonjourPeerVersionMonitor?
  private let overlay = InputDestinationOverlayController()
  private var agentReceivingSource: String?
  private static let anchorDefaultsKey = "DeskMuxInputAnchor"

  init() {
    let role = LocalMachineRole.detect()
    localPeerID = role.peerID
    destinationPeerID = role.destinationPeerID
    anchorPeerID = PeerID(
      rawValue: UserDefaults.standard.string(forKey: Self.anchorDefaultsKey) ?? "studio")
    let code = PairingCodeStore.load() ?? PairingCodeStore.generate()
    savedPairingCode = code
    pairingCodeDraft = code
    updateReceipt = DeskMuxAppUpdateInstaller.loadReceipt()
    try? PairingCodeStore.save(code)
    updateTriggerObserver = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name("dev.deskmux.sendUpdateToMacBook"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.sendUpdateToMacBook()
      }
    }
    researchTriggerObserver = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name("dev.deskmux.runMotionResearch"),
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let candidate = notification.userInfo?["candidate"] as? String ?? "working-tree"
      Task { @MainActor [weak self] in
        self?.runMotionResearch(candidate: candidate)
      }
    }
    let monitor = BonjourPeerVersionMonitor(peerID: destinationPeerID) { [weak self] snapshot in
      Task { @MainActor [weak self] in
        self?.peerVersions = snapshot
      }
    }
    versionMonitor = monitor
    monitor.start()
  }

  var destinationName: String {
    destinationPeerID.rawValue == "macbook" ? "MacBook" : "Studio"
  }
  var localAppBuild: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
  }
  var versionsSynchronized: Bool {
    guard localAgentBuild == localAppBuild,
      let app = peerVersions.app,
      let agent = peerVersions.agent
    else { return false }
    return app.build == localAppBuild
      && agent.build == localAppBuild
      && app.protocolVersion == InputWireMessage.currentProtocolVersion
      && agent.protocolVersion == InputWireMessage.currentProtocolVersion
  }
  var versionSummary: String {
    if localAgentBuild == nil {
      return "Checking this Mac's background agent…"
    }
    if localAgentBuild != localAppBuild {
      return "This Mac's app is build \(localAppBuild), but its agent is build \(localAgentBuild ?? "unknown")."
    }
    if versionsSynchronized {
      return "Both Macs and both background agents are on build \(localAppBuild)."
    }
    if !peerVersions.appServiceFound && !peerVersions.agentServiceFound {
      return "Waiting for \(destinationName) version information…"
    }
    if peerVersions.appServiceFound && peerVersions.app == nil {
      return "\(destinationName) is running an older build without version reporting."
    }
    if peerVersions.agentServiceFound && peerVersions.agent == nil {
      return "\(destinationName)'s background agent needs an update."
    }
    guard let app = peerVersions.app, let agent = peerVersions.agent else {
      return "Cannot confirm both the app and background agent on \(destinationName) yet."
    }
    if app.build != agent.build {
      return "\(destinationName)'s app is build \(app.build), but its agent is build \(agent.build)."
    }
    if app.protocolVersion != InputWireMessage.currentProtocolVersion
      || agent.protocolVersion != InputWireMessage.currentProtocolVersion
    {
      return "\(destinationName) uses a different input protocol version."
    }
    return "This Mac is build \(localAppBuild); \(destinationName) is build \(app.build)."
  }
  var canSendMacBookUpdate: Bool {
    guard localPeerID.rawValue == "studio",
      peerVersions.appServiceFound || peerVersions.agentServiceFound
    else { return false }
    guard let remoteBuild = peerVersions.app?.build ?? peerVersions.agent?.build else {
      return true
    }
    return localAppBuild.compare(remoteBuild, options: .numeric) == .orderedDescending
  }
  var anchorName: String { anchorPeerID.rawValue == "macbook" ? "MacBook" : "Studio" }
  var isLocalAnchor: Bool { anchorPeerID == localPeerID }

  var receiverReady: Bool {
    switch receiverState {
    case .ready, .receiving: return true
    default: return false
    }
  }
  var isReceivingInput: Bool {
    if case .receiving = receiverState { return true }
    return false
  }
  var activeSourceName: String {
    guard case .receiving(let peerID) = receiverState else { return "Source" }
    return peerID.rawValue == "studio" ? "Studio" : "MacBook"
  }
  var hasUnsavedPairingCode: Bool { normalized(pairingCodeDraft) != savedPairingCode }
  var agentSharedKey: String { savedPairingCode }

  var receiverLabel: String {
    switch receiverState {
    case .starting: return "Starting receiver"
    case .ready: return "Receiver ready"
    case .receiving(let peerID): return "Receiving from \(peerID.rawValue)"
    case .failed: return "Receiver failed"
    case .stopped: return "Receiver stopped"
    }
  }

  func configure(permissions: MacInputPermissionStatus) {
    // This listener only accepts authenticated app updates. Input injection is
    // owned by the stable agent, so update availability must not depend on the
    // menu-bar app's Accessibility permission or on opening its panel.
    _ = permissions
    guard receiver == nil else { return }
    startReceiver()
  }

  func observeAgentStatus(_ status: DeskMuxAgentStatus?) {
    localAgentBuild = status?.agentBuild
    let source = status?.receiverState == .receiving ? status?.activeSourcePeerID : nil
    guard source != agentReceivingSource else { return }
    agentReceivingSource = source
    if let source {
      let peerID = PeerID(rawValue: source)
      setAnchor(peerID)
      hasError = false
      message = "The background agent is receiving keyboard from \(source)."
      overlay.show(sourceName: source == "studio" ? "Studio" : "MacBook")
    } else {
      overlay.hide()
    }
  }

  func makeThisMacAnchor() {
    setAnchor(localPeerID)
    hasError = false
    message = "\(anchorName) is now the keyboard anchor. Keep the keyboard connected here."
  }

  func savePairingCode() {
    let code = normalized(pairingCodeDraft)
    guard code.count >= 16 else {
      hasError = true
      message = "The pairing code must contain at least 16 characters."
      return
    }
    do {
      try PairingCodeStore.save(code)
      savedPairingCode = code
      pairingCodeDraft = code
      receiver?.stop()
      receiver = nil
      receiverState = .stopped
      hasError = false
      message = "Pairing code saved in Keychain."
      startReceiver()
    } catch {
      hasError = true
      message = "Could not save the pairing code: \(error)"
    }
  }

  func copyPairingCode() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(savedPairingCode, forType: .string)
    hasError = false
    message = "Pairing code copied."
  }

  func sendInput() {
    guard !relayRunning, !hasUnsavedPairingCode else { return }
    let relay = BonjourInputRelaySource(
      sourcePeerID: localPeerID,
      destinationPeerID: destinationPeerID,
      sharedKey: savedPairingCode,
      mode: .keyboardOnly
    )
    activeRelay = relay
    relayRunning = true
    hasError = false
    needsLocalNetworkPermission = false
    message = "Connecting to \(destinationName)… input will return automatically."
    Task {
      let outcome = await Task.detached(priority: .userInitiated) {
        let startedAt = Date()
        do {
          try relay.run(maxDuration: 15)
          return InputRelayOutcome.returned(
            relay.latencyReport,
            Date().timeIntervalSince(startedAt)
          )
        } catch BonjourInputRelayError.localNetworkPermissionMissing {
          return InputRelayOutcome.localNetworkDenied
        } catch {
          return InputRelayOutcome.failed(String(describing: error))
        }
      }.value
      activeRelay = nil
      relayRunning = false
      switch outcome {
      case .localNetworkDenied:
        hasError = true
        needsLocalNetworkPermission = true
        _ = try? persistInputRelayFailure(
          String(describing: BonjourInputRelayError.localNetworkPermissionMissing))
        message = String(describing: BonjourInputRelayError.localNetworkPermissionMissing)
      case .failed(let failure):
        hasError = true
        do {
          let url = try persistInputRelayFailure(failure)
          message = "Connection failed. Details saved to \(url.lastPathComponent)."
        } catch {
          message = "Connection failed: \(failure)"
        }
      case .returned(let latency, let elapsedSeconds):
        let acknowledgedEvents = latency.injectionAckSamplesMilliseconds.count
        hasError = acknowledgedEvents == 0
        do {
          _ = try persistLatencyDiagnostics(latency, durationSeconds: elapsedSeconds)
          message =
            acknowledgedEvents == 0
            ? "The link closed without acknowledging a keyboard event; this test did not pass."
            : "Keyboard test passed — \(acknowledgedEvents) events acknowledged."
        } catch {
          hasError = true
          message = "Input returned, but diagnostics could not be saved: \(error)"
        }
      }
    }
  }

  func runMotionResearch(candidate: String) {
    guard !relayRunning, !hasUnsavedPairingCode else { return }
    let trace: MotionReplayTrace
    do {
      trace = try loadMotionTrace()
    } catch {
      hasError = true
      message = "Motion research could not start: \(error)"
      return
    }
    let relay = BonjourInputRelaySource(
      sourcePeerID: localPeerID,
      destinationPeerID: destinationPeerID,
      sharedKey: savedPairingCode
    )
    activeRelay = relay
    relayRunning = true
    hasError = false
    message = "Replaying motion experiment \(candidate)…"
    Task {
      let outcome = await Task.detached(priority: .userInitiated) {
        do {
          try relay.replay(trace)
          let report = relay.latencyReport
          return MotionResearchOutcome.completed(
            report,
            MotionResearchAssessment.assess(report)
          )
        } catch {
          return MotionResearchOutcome.failed(String(describing: error))
        }
      }.value
      activeRelay = nil
      relayRunning = false
      switch outcome {
      case .completed(let report, let assessment):
        do {
          try persistMotionResearch(
            candidate: candidate,
            trace: trace,
            latency: report,
            assessment: assessment
          )
          hasError = !assessment.meetsNativeLatencyTarget
          message =
            assessment.meetsNativeLatencyTarget
            ? "Motion experiment \(candidate) met the latency target."
            : "Motion experiment \(candidate) finished; result saved for analysis."
        } catch {
          hasError = true
          message = "Motion experiment finished, but its result could not be saved: \(error)"
        }
      case .failed(let failure):
        hasError = true
        try? persistMotionResearchFailure(candidate: candidate, failure: failure)
        message = "Motion experiment \(candidate) failed; details saved."
      }
    }
  }

  func openLocalNetworkSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")
    else { return }
    NSWorkspace.shared.open(url)
  }

  func returnInputToSource() {
    receiver?.returnInputToSource()
    hasError = false
    message = "Returning input to \(activeSourceName)…"
  }

  func sendUpdateToMacBook() {
    guard canSendMacBookUpdate, !updateRunning, !hasUnsavedPairingCode else { return }
    updateRunning = true
    updateFailed = false
    updateMessage = "Packaging the running Studio build…"
    persistUpdateStatus("running")
    let sharedKey = savedPairingCode
    let sourcePeerID = localPeerID
    let destinationPeerID = PeerID(rawValue: "macbook")
    let updateServiceType =
      peerVersions.appServiceFound
      ? BonjourAppUpdateSource.serviceType
      : BonjourInputRelaySource.serviceType
    Task {
      let outcome = await Task.detached(priority: .userInitiated) {
        do {
          let package = try DeskMuxAppUpdatePackager.packageRunningApp()
          let result = try BonjourAppUpdateSource(
            sourcePeerID: sourcePeerID,
            destinationPeerID: destinationPeerID,
            sharedKey: sharedKey,
            serviceType: updateServiceType
          ).send(package)
          switch result {
          case .accepted(let build):
            return AppUpdateOutcome.accepted(build)
          case .rejected(let reason):
            return AppUpdateOutcome.failed(reason)
          }
        } catch {
          return AppUpdateOutcome.failed(String(describing: error))
        }
      }.value
      updateRunning = false
      switch outcome {
      case .accepted(let build):
        updateFailed = false
        updateMessage = "MacBook installed build \(build) and is restarting DeskMux."
        persistUpdateStatus("accepted:\(build)")
      case .failed(let reason):
        updateFailed = true
        updateMessage = reason
        persistUpdateStatus("failed:\(reason)")
      }
    }
  }

  func updateReceiptDescription(_ receipt: DeskMuxAppUpdateReceipt) -> String {
    let source = receipt.sourcePeerID?.rawValue == "studio" ? "Studio" : "a paired Mac"
    return "Installed \(receipt.installedVersion) (build \(receipt.installedBuild)) from \(source)."
  }

  func dismissUpdateReceipt() {
    DeskMuxAppUpdateInstaller.dismissReceipt()
    updateReceipt = nil
  }

  private func startReceiver() {
    let receiver = BonjourInputReceiver(
      peerID: localPeerID,
      sharedKey: savedPairingCode,
      acceptsAppUpdates: true,
      serviceType: BonjourAppUpdateSource.serviceType,
      versionAdvertisement: DeskMuxVersionAdvertisement(
        component: .app,
        build: localAppBuild,
        protocolVersion: InputWireMessage.currentProtocolVersion
      ),
      stateHandler: { [weak self] state in
        Task { @MainActor [weak self] in
          self?.receiverState = state
          switch state {
          case .receiving(let peerID):
            self?.setAnchor(peerID)
            self?.hasError = false
            self?.message = "Receiving keyboard from \(peerID.rawValue)."
            self?.overlay.show(
              sourceName: peerID.rawValue == "studio" ? "Studio" : "MacBook")
          case .failed(let reason):
            self?.overlay.hide()
            self?.hasError = true
            self?.message = "Receiver failed: \(reason)"
          case .ready, .stopped:
            self?.overlay.hide()
          default:
            break
          }
        }
      }
    )
    self.receiver = receiver
    do {
      try receiver.start()
    } catch {
      self.receiver = nil
      receiverState = .failed(String(describing: error))
      hasError = true
      message = "Receiver failed: \(error)"
    }
  }

  private func normalized(_ code: String) -> String {
    code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
  }

  private func setAnchor(_ peerID: PeerID) {
    anchorPeerID = peerID
    UserDefaults.standard.set(peerID.rawValue, forKey: Self.anchorDefaultsKey)
  }

  private func persistUpdateStatus(_ status: String) {
    UserDefaults.standard.set(status, forKey: "DeskMuxLastUpdateStatus")
  }

  private func persistLatencyDiagnostics(
    _ latency: InputRelayLatencyReport,
    durationSeconds: TimeInterval
  ) throws -> URL {
    let directory = try diagnosticsDirectory()
    let record = InputRelayDiagnosticRecord(
      schemaVersion: 2,
      recordedAt: Date(),
      sourcePeerID: localPeerID.rawValue,
      destinationPeerID: destinationPeerID.rawValue,
      appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
      protocolVersion: InputWireMessage.currentProtocolVersion,
      motionRateHz: 120,
      durationSeconds: durationSeconds,
      latency: latency
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    var line = try encoder.encode(record)
    line.append(0x0A)

    let logURL = directory.appendingPathComponent("input-latency.jsonl")
    if !FileManager.default.fileExists(atPath: logURL.path) {
      guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
        throw InputRelayDiagnosticError.couldNotCreateLog
      }
    }
    let handle = try FileHandle(forWritingTo: logURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
    try handle.close()

    let latestURL = directory.appendingPathComponent("latest-input-latency.json")
    try encoder.encode(record).write(to: latestURL, options: .atomic)
    return logURL
  }

  private func persistInputRelayFailure(_ failure: String) throws -> URL {
    let record = InputRelayFailureRecord(
      schemaVersion: 1,
      recordedAt: Date(),
      sourcePeerID: localPeerID.rawValue,
      destinationPeerID: destinationPeerID.rawValue,
      appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
      protocolVersion: InputWireMessage.currentProtocolVersion,
      failure: failure
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    var line = try encoder.encode(record)
    line.append(0x0A)
    let logURL = try diagnosticsDirectory().appendingPathComponent("input-relay-errors.jsonl")
    if !FileManager.default.fileExists(atPath: logURL.path) {
      guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
        throw InputRelayDiagnosticError.couldNotCreateLog
      }
    }
    let handle = try FileHandle(forWritingTo: logURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
    try handle.close()
    return logURL
  }

  private func persistMotionTrace(_ trace: MotionReplayTrace) throws -> URL {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    let url = try diagnosticsDirectory().appendingPathComponent("latest-motion-trace.json")
    try encoder.encode(trace).write(to: url, options: .atomic)
    return url
  }

  private func loadMotionTrace() throws -> MotionReplayTrace {
    let url = try diagnosticsDirectory().appendingPathComponent("latest-motion-trace.json")
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(MotionReplayTrace.self, from: Data(contentsOf: url))
  }

  private func persistMotionResearch(
    candidate: String,
    trace: MotionReplayTrace,
    latency: InputRelayLatencyReport,
    assessment: MotionResearchAssessment
  ) throws {
    let record = MotionResearchRecord(
      schemaVersion: 1,
      recordedAt: Date(),
      candidate: candidate,
      appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
      protocolVersion: InputWireMessage.currentProtocolVersion,
      traceSampleCount: trace.samples.count,
      traceDurationNanoseconds: trace.durationNanoseconds,
      latency: latency,
      assessment: assessment
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    var line = try encoder.encode(record)
    line.append(0x0A)
    let directory = try diagnosticsDirectory()
    let logURL = directory.appendingPathComponent("motion-research.jsonl")
    if !FileManager.default.fileExists(atPath: logURL.path) {
      guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
        throw InputRelayDiagnosticError.couldNotCreateLog
      }
    }
    let handle = try FileHandle(forWritingTo: logURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
    try handle.close()
    try encoder.encode(record).write(
      to: directory.appendingPathComponent("latest-motion-research.json"),
      options: .atomic
    )
  }

  private func persistMotionResearchFailure(candidate: String, failure: String) throws {
    let record = MotionResearchFailureRecord(
      schemaVersion: 1,
      recordedAt: Date(),
      candidate: candidate,
      appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
      failure: failure
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(record).write(
      to: diagnosticsDirectory().appendingPathComponent("latest-motion-research-failure.json"),
      options: .atomic
    )
  }

  private func diagnosticsDirectory() throws -> URL {
    let directory =
      (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser)
      .appendingPathComponent("DeskMux", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}

private struct InputRelayDiagnosticRecord: Codable, Sendable {
  let schemaVersion: Int
  let recordedAt: Date
  let sourcePeerID: String
  let destinationPeerID: String
  let appBuild: String
  let protocolVersion: Int
  let motionRateHz: Double
  let durationSeconds: Double
  let latency: InputRelayLatencyReport
}

private struct InputRelayFailureRecord: Codable, Sendable {
  let schemaVersion: Int
  let recordedAt: Date
  let sourcePeerID: String
  let destinationPeerID: String
  let appBuild: String
  let protocolVersion: Int
  let failure: String
}

private struct MotionResearchRecord: Codable, Sendable {
  let schemaVersion: Int
  let recordedAt: Date
  let candidate: String
  let appBuild: String
  let protocolVersion: Int
  let traceSampleCount: Int
  let traceDurationNanoseconds: UInt64
  let latency: InputRelayLatencyReport
  let assessment: MotionResearchAssessment
}

private struct MotionResearchFailureRecord: Codable, Sendable {
  let schemaVersion: Int
  let recordedAt: Date
  let candidate: String
  let appBuild: String
  let failure: String
}

private enum InputRelayDiagnosticError: Error {
  case couldNotCreateLog
}

private enum InputRelayOutcome: Sendable {
  case returned(InputRelayLatencyReport, TimeInterval)
  case localNetworkDenied
  case failed(String)
}

private enum AppUpdateOutcome: Sendable {
  case accepted(String)
  case failed(String)
}

private enum MotionResearchOutcome: Sendable {
  case completed(InputRelayLatencyReport, MotionResearchAssessment)
  case failed(String)
}

private enum LocalMachineRole {
  case studio
  case macbook

  var peerID: PeerID { PeerID(rawValue: self == .macbook ? "macbook" : "studio") }
  var destinationPeerID: PeerID { PeerID(rawValue: self == .macbook ? "studio" : "macbook") }

  static func detect() -> Self {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return .studio }
    var value = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &value, &size, nil, 0) == 0 else { return .studio }
    let model = String(
      decoding: value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    return model.hasPrefix("MacBook") ? .macbook : .studio
  }
}

private enum PairingCodeStore {
  private static let service = "dev.deskmux.app.pairing"
  private static let account = "default"

  static func load() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func save(_ code: String) throws {
    let identity: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let attributes = [kSecValueData as String: Data(code.utf8)]
    let status: OSStatus
    if SecItemCopyMatching(identity as CFDictionary, nil) == errSecSuccess {
      status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
    } else {
      status = SecItemAdd(identity.merging(attributes) { _, new in new } as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw PairingCodeStoreError.keychain(status) }
  }

  static func generate() -> String {
    let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    var bytes = [UInt8](repeating: 0, count: 20)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      return UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
    let characters = bytes.map { alphabet[Int($0) % alphabet.count] }
    return stride(from: 0, to: characters.count, by: 4)
      .map { String(characters[$0..<min($0 + 4, characters.count)]) }
      .joined(separator: "-")
  }
}

private enum PairingCodeStoreError: Error, CustomStringConvertible {
  case keychain(OSStatus)

  var description: String {
    switch self {
    case .keychain(let status):
      return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
  }
}
