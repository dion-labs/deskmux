import AppKit
import DeskMuxAgentIPC
import DeskMuxMacInput
import Foundation
import ServiceManagement

@MainActor
final class BackgroundAgentModel: ObservableObject {
  // Bump whenever the bundled agent must be replaced even if its on-disk layout
  // is unchanged. Version 26 keeps an authenticated input channel warm in the
  // stable agent so edge handoffs do not pay discovery and handshake latency.
  // Version 29 re-registers the stable agent after an update migrates a
  // bootstrap DeskMux bundle into the user's Applications folder.
  // Version 31 installs the always-on bidirectional clipboard bridge and its
  // delivery acknowledgement path.
  private static let currentAgentLayoutVersion = 31
  private static let agentLayoutDefaultsKey = "DeskMuxAgentLayoutVersion"
  private static let inputAnchorDefaultsKey = "DeskMuxInputAnchor"

  @Published private(set) var serviceStatus: SMAppService.Status = .notRegistered
  @Published private(set) var agentStatus: DeskMuxAgentStatus?
  @Published private(set) var message: String?
  @Published private(set) var hasError = false
  @Published private(set) var logitechStatus: DeskMuxLogitechStatus?
  @Published private(set) var logitechSwitching = false
  @Published private(set) var logitechMessage: String?
  @Published private(set) var edgeSwitchConfiguration: MacPointerEdgeConfiguration
  @Published private(set) var edgeSwitchMessage: String?
  @Published private(set) var logitechFlowConflict = false
  @Published private(set) var disablingLogitechFlow = false

  private let localPeerID: String
  private let destinationPeerID: String
  private let service = SMAppService.agent(plistName: deskMuxAgentPlistName)
  private var connection: NSXPCConnection?
  private var desiredReceiverConfiguration: DeskMuxAgentReceiverConfiguration?
  private var lastReceiverConfiguration: DeskMuxAgentReceiverConfiguration?
  private var healthTask: Task<Void, Never>?
  private var migrationInProgress = false
  private var edgeMonitor: MacPointerEdgeMonitor?
  private var edgeMonitorTask: Task<Void, Never>?
  private var activeEdgeConfiguration: MacPointerEdgeConfiguration?
  private let cursorFeedback = CursorHandoffFeedbackController()

  init(localPeerID: String) {
    self.localPeerID = localPeerID
    destinationPeerID = localPeerID == "studio" ? "macbook" : "studio"
    Self.importBundledLogitechHostMap()
    Self.importBundledEdgeConfiguration(localPeerID: localPeerID)
    edgeSwitchConfiguration = Self.loadEdgeConfiguration(localPeerID: localPeerID)
    refreshFlowConflict()
    recordHandoff("app_started")
    serviceStatus = service.status
    if serviceStatus == .enabled || serviceStatus == .requiresApproval,
      UserDefaults.standard.integer(forKey: Self.agentLayoutDefaultsKey)
        < Self.currentAgentLayoutVersion
    {
      migrateRegisteredService()
    } else if serviceStatus == .notRegistered {
      enable()
    } else {
      refresh()
    }
    healthTask = Task { @MainActor [weak self] in
      var healthCheckCount = 0
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard let self else { return }
        self.refresh()
        self.configureDesiredReceiver()
        self.updateEdgeMonitor()
        healthCheckCount += 1
        if healthCheckCount == 1 || healthCheckCount.isMultiple(of: 5) {
          self.refreshLogitechStatus()
        }
      }
    }
  }

  var isEnabled: Bool { serviceStatus == .enabled }
  var needsApproval: Bool { serviceStatus == .requiresApproval }
  var receiverReady: Bool {
    agentStatus?.receiverState == .ready || agentStatus?.receiverState == .receiving
  }

  var inputOwnerName: String {
    if agentStatus?.keyboardRelayState == .active {
      return destinationPeerID == "macbook" ? "MacBook" : "Studio"
    }
    if agentStatus?.receiverState == .receiving {
      return localPeerID == "macbook" ? "MacBook" : "Studio"
    }
    let anchorPeerID =
      UserDefaults.standard.string(forKey: Self.inputAnchorDefaultsKey) ?? "studio"
    return anchorPeerID == "macbook" ? "MacBook" : "Studio"
  }

  var receiverSummary: String? {
    guard let status = agentStatus else { return nil }
    switch status.receiverState {
    case .unconfigured: return "Input receiver is waiting for configuration"
    case .starting: return "Starting the stable input receiver…"
    case .ready: return "Stable input receiver is ready"
    case .receiving:
      return "Receiving input from \(status.activeSourcePeerID ?? "paired Mac")"
    case .failed: return status.receiverError ?? "Stable input receiver failed"
    }
  }

  var keyboardRelaySummary: String? {
    guard let state = agentStatus?.keyboardRelayState else { return nil }
    switch state {
    case .idle: return agentStatus?.keyboardRelayError
    case .connecting: return "Preparing the keyboard-only relay…"
    case .active: return "Keyboard is routed to the paired Mac"
    case .failed:
      return agentStatus?.keyboardRelayError ?? "Keyboard relay failed"
    }
  }

  var warmConnectionSummary: String? {
    guard let state = agentStatus?.warmConnectionState else { return nil }
    switch state {
    case .idle: return "Warm keyboard and clipboard channel is idle"
    case .connecting:
      if let error = agentStatus?.warmConnectionError {
        return "Reconnecting warm keyboard channel: \(error)"
      }
      return "Preparing warm keyboard and clipboard channel…"
    case .ready:
      if let milliseconds = agentStatus?.warmConnectionRoundTripMilliseconds {
        return String(format: "Warm keyboard channel ready · %.1f ms", milliseconds)
      }
      return "Warm keyboard and clipboard channel ready"
    }
  }

  var summary: String {
    switch serviceStatus {
    case .enabled:
      if let agentStatus {
        return "Running as PID \(agentStatus.processIdentifier)"
      }
      return "Enabled; checking service health…"
    case .requiresApproval:
      return "Approval required in Login Items"
    case .notRegistered:
      return "Not enabled yet"
    case .notFound:
      return "Agent is missing from this app build"
    @unknown default:
      return "Unknown service state"
    }
  }

  var permissionsSummary: String? {
    guard let agentStatus else { return nil }
    if agentStatus.canListen && agentStatus.canPost {
      return "Agent input permissions are ready"
    }
    var missing: [String] = []
    if !agentStatus.canListen { missing.append("Input Monitoring") }
    if !agentStatus.canPost { missing.append("Accessibility") }
    return "Agent still needs \(missing.joined(separator: " and "))"
  }

  func refresh() {
    serviceStatus = service.status
    guard serviceStatus == .enabled else {
      disconnect()
      agentStatus = nil
      return
    }
    queryAgent(requestPermissions: false)
  }

  func enable() {
    do {
      try service.register()
      UserDefaults.standard.set(
        Self.currentAgentLayoutVersion,
        forKey: Self.agentLayoutDefaultsKey
      )
      hasError = false
      message = "Background agent submitted to macOS."
    } catch {
      migrationInProgress = false
      hasError = true
      message = "Could not enable the background agent: \(error.localizedDescription)"
    }
    refresh()
  }

  func openLoginItems() {
    SMAppService.openSystemSettingsLoginItems()
  }

  func requestAgentPermissions() {
    guard serviceStatus == .enabled else { return }
    queryAgent(requestPermissions: true)
  }

  func requestScreenCapturePermission() {
    guard let proxy = agentProxy() else { return }
    proxy.requestScreenCapturePermission(withReply: statusReply())
  }

  func restartAgent() {
    guard serviceStatus == .enabled else { return }
    connection?.invalidate()
    connection = nil
    migrationInProgress = false
    migrateRegisteredService()
  }

  func configureReceiver(peerID: String, sharedKey: String) {
    guard sharedKey.count >= 16 else { return }
    desiredReceiverConfiguration = DeskMuxAgentReceiverConfiguration(
      peerID: peerID,
      sharedKey: sharedKey
    )
    configureDesiredReceiver()
  }

  private func configureDesiredReceiver() {
    guard serviceStatus == .enabled, let configuration = desiredReceiverConfiguration else {
      return
    }
    if lastReceiverConfiguration == configuration,
      agentStatus?.receiverState != .unconfigured,
      agentStatus?.receiverState != .failed
    {
      return
    }
    guard let data = try? JSONEncoder().encode(configuration), let proxy = agentProxy() else {
      return
    }
    lastReceiverConfiguration = configuration
    proxy.configureReceiver(data, withReply: statusReply())
  }

  func returnInputToSource() {
    guard let proxy = agentProxy() else { return }
    proxy.returnInputToSource(withReply: statusReply())
  }

  func refreshLogitechStatus() {
    refreshFlowConflict()
    guard !logitechSwitching, serviceStatus == .enabled, let proxy = agentProxy() else { return }
    proxy.logitechStatus { [weak self] data in
      let decoded = try? JSONDecoder().decode(DeskMuxLogitechStatus.self, from: data)
      Task { @MainActor in
        guard self?.logitechSwitching == false else { return }
        self?.logitechStatus = decoded
      }
    }
  }

  func disableLogitechFlow() {
    guard !disablingLogitechFlow else { return }
    disablingLogitechFlow = true
    logitechMessage = "Disabling Logitech Flow on this Mac…"
    recordHandoff("logitech_flow_disable_requested")

    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        var modifiedFileCount = 0
        for attempt in 0..<5 {
          let result = try LogitechFlowConfiguration.disable()
          modifiedFileCount += result.modifiedFileCount
          if attempt == 0 {
            NSWorkspace.shared.runningApplications
              .filter { $0.bundleIdentifier == "com.logi.cp-dev-mgr" }
              .forEach { _ = $0.terminate() }
          }
          try await Task.sleep(for: .milliseconds(400))
        }
        self.refreshFlowConflict()
        self.disablingLogitechFlow = false
        if self.logitechFlowConflict {
          self.logitechMessage =
            "Flow turned itself back on. Quit Logi Options+ and try Disable Flow again."
          self.recordHandoff("logitech_flow_disable_failed", detail: "setting_reenabled")
        } else {
          self.logitechMessage =
            "Logitech Flow is off on this Mac. Options+ remains installed; repeat this on the other Mac if it also reports a conflict."
          self.recordHandoff(
            "logitech_flow_disabled", detail: "writes=\(modifiedFileCount)")
        }
      } catch {
        self.disablingLogitechFlow = false
        self.refreshFlowConflict()
        self.logitechMessage = "DeskMux could not disable Flow: \(error.localizedDescription)"
        self.recordHandoff("logitech_flow_disable_failed", detail: error.localizedDescription)
      }
    }
  }

  func configuredLogitechHost(peerID: String) -> Int? {
    let key = "DeskMuxLogitechHost.\(peerID)"
    guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
    return UserDefaults.standard.integer(forKey: key)
  }

  func switchLogitechMouse(from localPeerID: String, to destinationPeerID: String) {
    guard !logitechSwitching else { return }
    recordHandoff("handoff_requested")
    logitechSwitching = true
    cursorFeedback.begin(
      destinationName: destinationPeerID == "macbook" ? "MacBook" : "Studio",
      pointsLeft: edgeSwitchConfiguration.edge == .left
    )
    guard let expectedLocalHost = configuredLogitechHost(peerID: localPeerID),
      let targetHost = configuredLogitechHost(peerID: destinationPeerID)
    else {
      failPreparedHandoff("The native mouse channel mapping is incomplete.")
      return
    }
    // A ready snapshot is enough to start keyboard preparation: the actual
    // switch command revalidates the host. Only re-probe an unavailable/stale
    // snapshot here, avoiding a second HID round trip on the normal fast path.
    if logitechStatus?.isReady == true, logitechStatus?.currentHost == expectedLocalHost {
      prepareValidatedMouseHandoff(
        status: logitechStatus, expectedLocalHost: expectedLocalHost, targetHost: targetHost,
        localPeerID: localPeerID, destinationPeerID: destinationPeerID)
      return
    }
    guard let proxy = agentProxy() else {
      failPreparedHandoff("The background agent is unavailable.")
      return
    }
    logitechMessage = "Edge accepted; checking the current mouse channel…"
    // A just-returned mouse can be usable while the periodic status still says
    // absent. Acknowledge the gesture now and resolve current hardware state;
    // do not force the user to cross the edge again after a five-second poll.
    proxy.freshLogitechStatus { [weak self] data in
      let status = try? JSONDecoder().decode(DeskMuxLogitechStatus.self, from: data)
      Task { @MainActor in
        guard let self, self.logitechSwitching else { return }
        self.logitechStatus = status
        self.recordHandoff(
          "edge_mouse_status_checked",
          detail: status?.error ?? "channel=\(status?.currentHost.map(String.init) ?? "unknown")"
        )
        self.prepareValidatedMouseHandoff(
          status: status, expectedLocalHost: expectedLocalHost, targetHost: targetHost,
          localPeerID: localPeerID, destinationPeerID: destinationPeerID)
      }
    }
  }

  private func prepareValidatedMouseHandoff(
    status: DeskMuxLogitechStatus?, expectedLocalHost: Int, targetHost: Int,
    localPeerID: String, destinationPeerID: String
  ) {
    guard status?.isReady == true, status?.currentHost == expectedLocalHost,
      let request = try? JSONEncoder().encode(
        DeskMuxLogitechSwitchRequest(
          expectedCurrentHost: expectedLocalHost, targetHost: targetHost))
    else {
      failPreparedHandoff(
        status?.error ?? "The mouse is not active on this Mac's configured channel.")
      return
    }
    prepareKeyboardHandoff(
      request: request, targetHost: targetHost,
      localPeerID: localPeerID, destinationPeerID: destinationPeerID)
  }

  private func prepareKeyboardHandoff(
    request: Data, targetHost: Int, localPeerID: String, destinationPeerID: String
  ) {
    let anchorPeerID =
      UserDefaults.standard.string(forKey: Self.inputAnchorDefaultsKey) ?? "studio"
    if anchorPeerID == localPeerID {
      logitechMessage = "Connecting the keyboard-only relay…"
      guard let proxy = agentProxy() else {
        failPreparedHandoff("The background agent is unavailable.")
        return
      }
      proxy.startKeyboardRelay(to: destinationPeerID) { [weak self] data in
        let status = try? JSONDecoder().decode(DeskMuxAgentStatus.self, from: data)
        Task { @MainActor in
          guard let self, self.logitechSwitching else { return }
          self.agentStatus = status
          self.recordHandoff("keyboard_prepare_result")
          guard status?.keyboardRelayState == .active else {
            self.failPreparedHandoff(
              status?.keyboardRelayError ?? "The keyboard relay did not become active."
            )
            return
          }
          self.performLogitechSwitch(request: request, targetHost: targetHost)
        }
      }
    } else {
      logitechMessage = "Returning the keyboard to \(anchorPeerID)…"
      guard let proxy = agentProxy() else {
        failPreparedHandoff("The background agent is unavailable.")
        return
      }
      proxy.returnInputToSource { [weak self] data in
        let status = try? JSONDecoder().decode(DeskMuxAgentStatus.self, from: data)
        Task { @MainActor in
          guard let self, self.logitechSwitching else { return }
          guard let status else {
            self.failPreparedHandoff("The background agent returned an invalid status.")
            return
          }
          self.agentStatus = status
          self.waitForKeyboardReturn(
            request: request,
            targetHost: targetHost,
            deadline: Date().addingTimeInterval(2)
          )
        }
      }
    }
  }

  private func waitForKeyboardReturn(request: Data, targetHost: Int, deadline: Date) {
    guard logitechSwitching else { return }
    guard agentStatus?.receiverState == .receiving else {
      performLogitechSwitch(request: request, targetHost: targetHost)
      return
    }
    guard Date() < deadline else {
      failPreparedHandoff(
        "The keyboard did not confirm its return, so the mouse was left on this Mac."
      )
      return
    }
    guard let proxy = agentProxy() else {
      failPreparedHandoff("The background agent became unavailable during keyboard return.")
      return
    }
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(20))
      guard let self, self.logitechSwitching else { return }
      proxy.status { [weak self] data in
        let status = try? JSONDecoder().decode(DeskMuxAgentStatus.self, from: data)
        Task { @MainActor [weak self] in
          guard let self, let status else {
            self?.failPreparedHandoff(
              "The background agent returned an invalid keyboard-return status."
            )
            return
          }
          self.agentStatus = status
          self.waitForKeyboardReturn(
            request: request,
            targetHost: targetHost,
            deadline: deadline
          )
        }
      }
    }
  }

  private func performLogitechSwitch(request: Data, targetHost: Int) {
    guard logitechSwitching else { return }
    recordHandoff("mouse_switch_requested")
    guard let proxy = agentProxy() else {
      rollbackKeyboardRelayAfterMouseFailure("The background agent is unavailable.")
      return
    }
    logitechMessage = "Keyboard ready; switching the mouse to channel \(targetHost + 1)…"
    proxy.switchLogitechHost(request) { [weak self] data in
      let receipt = try? JSONDecoder().decode(DeskMuxLogitechSwitchReceipt.self, from: data)
      Task { @MainActor in
        guard let self else { return }
        self.logitechSwitching = false
        if receipt?.commandAccepted == true {
          self.cursorFeedback.sent()
          self.recordHandoff("mouse_switch_accepted")
          self.logitechMessage =
            "Mouse switch accepted; it should reconnect on channel \(targetHost + 1)."
          self.logitechStatus = nil
        } else {
          self.rollbackKeyboardRelayAfterMouseFailure(
            receipt?.error ?? "The native mouse switch failed."
          )
        }
      }
    }
  }

  private func failPreparedHandoff(_ failure: String) {
    cursorFeedback.failed()
    recordHandoff("handoff_failed", detail: failure)
    logitechSwitching = false
    logitechMessage = failure
    refreshLogitechStatus()
  }

  private func agentDisconnectedDuringHandoff() {
    guard logitechSwitching else { return }
    // Do not query the broken connection again from its own error callback.
    // The normal health poll will reconnect; meanwhile let a new gesture retry.
    let failure = "The background agent disconnected. Wait for it to reconnect, then try the edge again."
    cursorFeedback.failed()
    recordHandoff("handoff_failed", detail: failure)
    logitechSwitching = false
    logitechMessage = failure
  }

  private func rollbackKeyboardRelayAfterMouseFailure(_ failure: String) {
    cursorFeedback.failed()
    recordHandoff("mouse_switch_failed", detail: failure)
    logitechSwitching = false
    logitechMessage = "\(failure) Keyboard routing was returned locally."
    agentProxy()?.stopKeyboardRelay { [weak self] data in
      let status = try? JSONDecoder().decode(DeskMuxAgentStatus.self, from: data)
      Task { @MainActor in
        self?.agentStatus = status
        self?.refreshLogitechStatus()
      }
    }
  }

  func setEdgeSwitchEnabled(_ enabled: Bool) {
    edgeSwitchConfiguration.enabled = enabled
    persistEdgeConfiguration()
    updateEdgeMonitor()
  }

  func previewHandoffFeedback() {
    guard !logitechSwitching else { return }
    let token = cursorFeedback.begin(
      destinationName: destinationPeerID == "macbook" ? "MacBook" : "Studio",
      pointsLeft: edgeSwitchConfiguration.edge == .left
    )
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      self?.cursorFeedback.sent(ifCurrent: token)
    }
  }

  func setEdgeSwitchEdge(_ edge: MacPointerEdge) {
    edgeSwitchConfiguration.edge = edge
    persistEdgeConfiguration()
    updateEdgeMonitor()
  }

  func setEdgeSwitchDwell(milliseconds: Int) {
    edgeSwitchConfiguration.dwellMilliseconds = min(max(milliseconds, 100), 1_000)
    persistEdgeConfiguration()
    updateEdgeMonitor()
  }

  func setEdgeSwitchTriggerMode(_ mode: MacPointerEdgeTriggerMode) {
    edgeSwitchConfiguration.triggerMode = mode
    persistEdgeConfiguration()
    updateEdgeMonitor()
  }

  func setEdgeSwitchModifier(_ modifier: MacPointerEdgeModifier) {
    edgeSwitchConfiguration.modifier = modifier
    persistEdgeConfiguration()
    updateEdgeMonitor()
  }

  private static func importBundledLogitechHostMap() {
    guard
      let hosts = Bundle.main.object(forInfoDictionaryKey: "DeskMuxLogitechHosts")
        as? [String: Any]
    else { return }
    for peerID in ["studio", "macbook"] {
      guard let host = hosts[peerID] as? NSNumber, (0...2).contains(host.intValue) else {
        continue
      }
      UserDefaults.standard.set(host.intValue, forKey: "DeskMuxLogitechHost.\(peerID)")
    }
  }

  private static func importBundledEdgeConfiguration(localPeerID: String) {
    guard
      let edges = Bundle.main.object(forInfoDictionaryKey: "DeskMuxLogitechEdges")
        as? [String: Any],
      let rawEdge = edges[localPeerID] as? String,
      MacPointerEdge(rawValue: rawEdge) != nil
    else { return }
    let defaults = UserDefaults.standard
    let edgeKey = "DeskMuxLogitechEdge.\(localPeerID)"
    if defaults.object(forKey: edgeKey) == nil {
      defaults.set(rawEdge, forKey: edgeKey)
    }
    if let enabled = Bundle.main.object(forInfoDictionaryKey: "DeskMuxLogitechEdgeEnabled")
      as? NSNumber
    {
      let enabledKey = "DeskMuxLogitechEdgeEnabled.\(localPeerID)"
      if defaults.object(forKey: enabledKey) == nil {
        defaults.set(enabled.boolValue, forKey: enabledKey)
      }
    }
    if let dwell = Bundle.main.object(
      forInfoDictionaryKey: "DeskMuxLogitechEdgeDwellMilliseconds") as? NSNumber
    {
      let dwellKey = "DeskMuxLogitechEdgeDwell.\(localPeerID)"
      if defaults.object(forKey: dwellKey) == nil {
        defaults.set(dwell.intValue, forKey: dwellKey)
      }
    }
  }

  private static func loadEdgeConfiguration(localPeerID: String)
    -> MacPointerEdgeConfiguration
  {
    let defaults = UserDefaults.standard
    let defaultEdge: MacPointerEdge = localPeerID == "studio" ? .left : .right
    let edge =
      defaults.string(forKey: "DeskMuxLogitechEdge.\(localPeerID)")
      .flatMap(MacPointerEdge.init(rawValue:)) ?? defaultEdge
    let dwellKey = "DeskMuxLogitechEdgeDwell.\(localPeerID)"
    let dwell = defaults.object(forKey: dwellKey) == nil ? 200 : defaults.integer(forKey: dwellKey)
    let triggerMode = defaults.string(forKey: "DeskMuxLogitechEdgeTriggerMode.\(localPeerID)")
      .flatMap(MacPointerEdgeTriggerMode.init(rawValue:)) ?? .holdModifier
    let modifier = defaults.string(forKey: "DeskMuxLogitechEdgeModifier.\(localPeerID)")
      .flatMap(MacPointerEdgeModifier.init(rawValue:)) ?? .option
    return MacPointerEdgeConfiguration(
      enabled: defaults.bool(forKey: "DeskMuxLogitechEdgeEnabled.\(localPeerID)"),
      edge: edge,
      dwellMilliseconds: dwell,
      triggerMode: triggerMode,
      modifier: modifier
    )
  }

  private func persistEdgeConfiguration() {
    let defaults = UserDefaults.standard
    defaults.set(
      edgeSwitchConfiguration.enabled,
      forKey: "DeskMuxLogitechEdgeEnabled.\(localPeerID)"
    )
    defaults.set(
      edgeSwitchConfiguration.edge.rawValue,
      forKey: "DeskMuxLogitechEdge.\(localPeerID)"
    )
    defaults.set(
      edgeSwitchConfiguration.dwellMilliseconds,
      forKey: "DeskMuxLogitechEdgeDwell.\(localPeerID)"
    )
    defaults.set(
      edgeSwitchConfiguration.triggerMode.rawValue,
      forKey: "DeskMuxLogitechEdgeTriggerMode.\(localPeerID)"
    )
    defaults.set(
      edgeSwitchConfiguration.modifier.rawValue,
      forKey: "DeskMuxLogitechEdgeModifier.\(localPeerID)"
    )
  }

  private func updateEdgeMonitor() {
    guard activeEdgeConfiguration != edgeSwitchConfiguration else { return }
    edgeMonitor?.stop()
    edgeMonitorTask?.cancel()
    edgeMonitor = nil
    edgeMonitorTask = nil
    activeEdgeConfiguration = edgeSwitchConfiguration
    guard edgeSwitchConfiguration.enabled else {
      edgeSwitchMessage = "Keyboard-following edge handoff is off."
      return
    }

    let monitor = MacPointerEdgeMonitor(configuration: edgeSwitchConfiguration) {
      [weak self] in
      Task { @MainActor in
        self?.edgeDidTrigger()
      }
    }
    edgeMonitor = monitor
    switch edgeSwitchConfiguration.triggerMode {
    case .holdModifier:
      edgeSwitchMessage =
        "Watching the \(edgeSwitchConfiguration.edge.rawValue) edge · hold \(edgeSwitchConfiguration.modifier.displayName)."
    case .pushAndDwell:
      edgeSwitchMessage =
        "Watching the \(edgeSwitchConfiguration.edge.rawValue) edge · \(edgeSwitchConfiguration.dwellMilliseconds) ms push."
    }
    edgeMonitorTask = Task.detached(priority: .userInitiated) { [weak self, monitor] in
      do {
        try monitor.run()
      } catch {
        Task { @MainActor in
          guard let self, self.edgeMonitor === monitor else { return }
          self.edgeSwitchMessage = String(describing: error)
          self.activeEdgeConfiguration = nil
        }
      }
    }
  }

  private func edgeDidTrigger() {
    recordHandoff("edge_triggered", detail:
      "edge=\(edgeSwitchConfiguration.edge.rawValue) mode=\(edgeSwitchConfiguration.triggerMode.rawValue) modifier=\(edgeSwitchConfiguration.modifier.rawValue) dwell_ms=\(edgeSwitchConfiguration.dwellMilliseconds) cached_mouse_ready=\(logitechStatus?.isReady == true)")
    guard edgeSwitchConfiguration.enabled, !logitechSwitching else {
      let reason = logitechSwitching ? "handoff_already_in_progress" : "edge_switching_disabled"
      recordHandoff("edge_ignored", detail: reason)
      edgeSwitchMessage = logitechSwitching
        ? "The previous edge handoff is still in progress."
        : "Edge switching is disabled."
      return
    }
    edgeSwitchMessage = "Edge gesture detected; switching mouse…"
    switchLogitechMouse(from: localPeerID, to: destinationPeerID)
  }

  private func migrateRegisteredService() {
    guard !migrationInProgress else { return }
    migrationInProgress = true
    message = "Updating the background agent…"
    service.unregister { [weak self] error in
      Task { @MainActor in
        guard let self else { return }
        if let error {
          self.migrationInProgress = false
          self.hasError = true
          self.message = "Could not migrate the background agent: \(error.localizedDescription)"
          self.refresh()
          return
        }
        self.serviceStatus = self.service.status
        self.enable()
      }
    }
  }

  private func queryAgent(requestPermissions: Bool) {
    guard let proxy = agentProxy() else { return }
    let reply = statusReply()
    if requestPermissions {
      proxy.requestPermissions(withReply: reply)
    } else {
      proxy.status(withReply: reply)
    }
  }

  private func agentProxy() -> DeskMuxAgentXPCProtocol? {
    if connection == nil {
      let connection = NSXPCConnection(machServiceName: deskMuxAgentMachServiceName)
      connection.remoteObjectInterface = NSXPCInterface(with: DeskMuxAgentXPCProtocol.self)
      connection.invalidationHandler = { [weak self] in
        Task { @MainActor in
          self?.connection = nil
          self?.agentStatus = nil
          self?.lastReceiverConfiguration = nil
          self?.agentDisconnectedDuringHandoff()
        }
      }
      connection.interruptionHandler = { [weak self] in
        Task { @MainActor in
          self?.agentStatus = nil
          self?.agentDisconnectedDuringHandoff()
        }
      }
      connection.resume()
      self.connection = connection
    }

    let errorHandler: @Sendable (Error) -> Void = { [weak self] error in
      Task { @MainActor in
        self?.hasError = true
        self?.message = "Background agent did not respond: \(error.localizedDescription)"
        self?.agentStatus = nil
        self?.agentDisconnectedDuringHandoff()
      }
    }
    guard
      let proxy = connection?.remoteObjectProxyWithErrorHandler(errorHandler)
        as? DeskMuxAgentXPCProtocol
    else {
      hasError = true
      message = "Could not connect to the background agent."
      return nil
    }

    return proxy
  }

  private func statusReply() -> @Sendable (Data) -> Void {
    { [weak self] data in
      let decoded = try? JSONDecoder().decode(DeskMuxAgentStatus.self, from: data)
      Task { @MainActor in
        guard let self else { return }
        if let decoded {
          let appBuild =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
          if decoded.agentBuild != appBuild {
            self.agentStatus = decoded
            self.migrateRegisteredService()
            return
          }
          self.migrationInProgress = false
          let relayChanged = self.agentStatus?.keyboardRelayState != decoded.keyboardRelayState
            || self.agentStatus?.keyboardRelayError != decoded.keyboardRelayError
          self.agentStatus = decoded
          if relayChanged { self.recordHandoff("keyboard_state_changed") }
          self.hasError = false
          self.message = nil
          self.configureDesiredReceiver()
        } else {
          self.hasError = true
          self.message = "The background agent returned an invalid health response."
        }
      }
    }
  }

  private func disconnect() {
    connection?.invalidationHandler = nil
    connection?.interruptionHandler = nil
    connection?.invalidate()
    connection = nil
    lastReceiverConfiguration = nil
  }

  private func refreshFlowConflict() {
    // The saved Flow setting is authoritative. Logitech's launch agent can
    // disappear briefly while it restarts, but that does not clear the conflict.
    let conflict = LogitechFlowConfiguration.isEnabled()
    guard conflict != logitechFlowConflict else { return }
    logitechFlowConflict = conflict
    recordHandoff(conflict ? "logitech_flow_conflict_detected" : "logitech_flow_conflict_cleared")
  }

  private func recordHandoff(_ event: String, detail: String? = nil) {
    let timestampFormatter = ISO8601DateFormatter()
    timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let record: [String: String] = [
      "timestamp": timestampFormatter.string(from: Date()),
      "event": event,
      "peer": localPeerID,
      "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
      "anchor": UserDefaults.standard.string(forKey: Self.inputAnchorDefaultsKey) ?? "studio",
      "keyboardRelayState": agentStatus?.keyboardRelayState?.rawValue ?? "unknown",
      "keyboardRelayError": agentStatus?.keyboardRelayError ?? "",
      "logitechFlowConflict": String(logitechFlowConflict),
      "detail": detail ?? "",
    ]
    do {
      let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DeskMux", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent("handoff.jsonl")
      if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
      }
      let handle = try FileHandle(forWritingTo: url)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
      try handle.write(contentsOf: Data([0x0a]))
    } catch {
      // Diagnostics must never interfere with input handoff.
    }
  }
}
