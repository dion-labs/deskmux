import DeskMuxCore
import DeskMuxInputTransport
import DeskMuxMacInput
import Foundation

private actor SimulationDriver: ProfileOperationDriver {
  private var operations: [String] = []

  func prepare(peerID: PeerID, for profile: DeskProfile) async throws {
    operations.append("prepare \(peerID.rawValue) for \(profile.name)")
  }

  func switchMonitor(_ command: MonitorSwitchCommand) async throws {
    operations.append(
      "switch \(command.monitorID.rawValue) from \(command.controllingPeerID.rawValue) "
        + "to \(command.destinationPeerID.rawValue) using input \(command.destinationInput.rawValue)"
    )
  }

  func waitForDisplay(_ confirmation: DisplayConfirmation, timeout: Duration) async throws {
    operations.append(
      "confirm \(confirmation.monitorID.rawValue) on \(confirmation.destinationPeerID.rawValue)"
    )
  }

  func routeInput(to peerID: PeerID) async throws {
    operations.append("route input to \(peerID.rawValue)")
  }

  func operationLog() -> [String] {
    operations
  }
}

private struct SimulationOutput: Encodable {
  let profile: String
  let learnedRoutes: [LearnedRoute]
  let operations: [String]
  let report: TransactionReport
}

@main
struct DeskMuxAgentCommand {
  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
      printUsage()
      return
    }

    do {
      switch command {
      case "input":
        try runInputCommand(Array(arguments.dropFirst()))
      case "logitech":
        try runLogitechCommand(Array(arguments.dropFirst()))
      case "asus":
        try runASUSCommand(Array(arguments.dropFirst()))
      case "update":
        try runUpdateCommand(Array(arguments.dropFirst()))
      case "research":
        try runResearchCommand(Array(arguments.dropFirst()))
      case "snapshot" where arguments.count <= 2:
        try writeJSON(
          LocalSnapshotCollector.collect(
            peerID: PeerID(rawValue: arguments.dropFirst().first ?? "local"))
        )
      case "simulate" where arguments.count == 2:
        try await writeJSON(simulate(profileName: arguments[1]))
      default:
        printUsage()
        Foundation.exit(EXIT_FAILURE)
      }
    } catch {
      FileHandle.standardError.write(Data("deskmux-agent: \(error)\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    }
  }

  private static func writeJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    FileHandle.standardOutput.write(try encoder.encode(value))
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private static func runInputCommand(_ arguments: [String]) throws {
    if arguments == ["permissions"] {
      try writeJSON(MacInputPermissions.status())
    } else if arguments == ["permissions", "--request"] {
      try writeJSON(MacInputPermissions.request())
    } else if arguments.count == 2, arguments[0] == "monitor" {
      let rawSeconds = arguments[1]
      guard let seconds = Double(rawSeconds), seconds > 0, seconds <= 60 else {
        throw AgentError.invalidMonitorDuration(rawSeconds)
      }
      try writeJSON(MacInputMonitor.run(durationSeconds: seconds))
    } else if arguments.count == 2, arguments[0] == "loopback" {
      let rawSeconds = arguments[1]
      guard let seconds = Double(rawSeconds), seconds > 0, seconds <= 30 else {
        throw AgentError.invalidLoopbackDuration(rawSeconds)
      }
      try writeJSON(MacInputLoopback.run(durationSeconds: seconds))
    } else if arguments.count == 3, arguments[0] == "receive", arguments[1] == "--peer" {
      try BonjourInputReceiver(
        peerID: PeerID(rawValue: arguments[2]),
        sharedKey: InputRelayEnvironment.sharedKey()
      ).run()
    } else if arguments.count == 5, arguments[0] == "probe", arguments[1] == "--peer",
      arguments[3] == "--to"
    {
      let sourcePeerID = PeerID(rawValue: arguments[2])
      let destinationPeerID = PeerID(rawValue: arguments[4])
      let acknowledgedPeerID = try BonjourInputRelaySource(
        sourcePeerID: sourcePeerID,
        destinationPeerID: destinationPeerID,
        sharedKey: InputRelayEnvironment.sharedKey()
      ).probe()
      try writeJSON(
        InputProbeOutput(
          sourcePeerID: sourcePeerID,
          destinationPeerID: destinationPeerID,
          acknowledgedPeerID: acknowledgedPeerID
        ))
    } else if arguments.count == 5 || arguments.count == 6, arguments[0] == "relay",
      arguments[1] == "--peer", arguments[3] == "--to",
      arguments.count == 5 || arguments[5] == "--keyboard-only"
    {
      try BonjourInputRelaySource(
        sourcePeerID: PeerID(rawValue: arguments[2]),
        destinationPeerID: PeerID(rawValue: arguments[4]),
        sharedKey: InputRelayEnvironment.sharedKey(),
        mode: arguments.count == 6 ? .keyboardOnly : .allInput
      ).run()
    } else {
      throw AgentError.unknownInputCommand(arguments)
    }
  }

  private static func runUpdateCommand(_ arguments: [String]) throws {
    if arguments == ["trigger"] {
      DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("dev.deskmux.sendUpdateToMacBook"),
        object: nil,
        userInfo: nil,
        deliverImmediately: true
      )
      return
    }
    guard arguments.count == 7, arguments[0] == "send", arguments[1] == "--peer",
      arguments[3] == "--to", arguments[5] == "--app"
    else {
      throw AgentError.unknownUpdateCommand(arguments)
    }
    let package = try DeskMuxAppUpdatePackager.packageApp(
      at: URL(fileURLWithPath: arguments[6], isDirectory: true))
    try writeJSON(
      BonjourAppUpdateSource(
        sourcePeerID: PeerID(rawValue: arguments[2]),
        destinationPeerID: PeerID(rawValue: arguments[4]),
        sharedKey: InputRelayEnvironment.sharedKey()
      ).send(package)
    )
  }

  private static func runLogitechCommand(_ arguments: [String]) throws {
    if arguments == ["discover"] {
      try writeJSON(LogitechHIDPlus.discover())
    } else if arguments == ["probe"] {
      try writeJSON(LogitechHIDPlus.probeChangeHost())
    } else if arguments.count == 5, arguments[0] == "switch", arguments[1] == "--from",
      arguments[3] == "--to", let from = Int(arguments[2]), let target = Int(arguments[4])
    {
      try writeJSON(try LogitechHIDPlus.switchHost(from: from, to: target))
    } else {
      throw AgentError.unknownLogitechCommand(arguments)
    }
  }

  private static func runASUSCommand(_ arguments: [String]) throws {
    if arguments == ["receiver-factory-input-test", "--acknowledge-temporary-factory-mode-and-recovery-plan"] {
      try writeJSON(try ASUSReceiverFactoryExperiment.run())
    } else if arguments == ["inventory"] {
      try writeJSON(ASUSKeyboardResearchInventory.discover())
    } else if arguments == ["receiver-status"] {
      try writeJSON(try ASUSReceiverStatusProbe.probe())
    } else if arguments == ["rf-test", "--acknowledge-transient-input-loss"] {
      try writeJSON(try ASUSRFModeExperiment.run())
    } else if arguments == [
      "factory-rf-test", "--acknowledge-temporary-factory-mode-and-recovery-plan",
    ] {
      try writeJSON(try ASUSFactoryRFModeExperiment.run())
    } else if arguments.count == 3, arguments[0] == "factory-rf-input-test",
      let seconds = Double(arguments[1]), seconds >= 1, seconds <= 15,
      arguments[2] == "--acknowledge-temporary-factory-mode-and-recovery-plan"
    {
      try writeJSON(try ASUSFactoryRFModeExperiment.run(activeDurationSeconds: seconds))
    } else if arguments.count == 2, arguments[0] == "paths",
      let seconds = Double(arguments[1]), seconds > 0, seconds <= 30
    {
      try writeJSON(try ASUSKeyboardPathMonitor.monitor(durationSeconds: seconds))
    } else if arguments.count == 2, arguments[0] == "inspect",
      let seconds = Double(arguments[1]), seconds > 0, seconds <= 60
    {
      try writeJSON(try ASUSHIDInspector.inspect(durationSeconds: seconds))
    } else {
      throw AgentError.unknownASUSCommand(arguments)
    }
  }

  private static func runResearchCommand(_ arguments: [String]) throws {
    if arguments == ["seed"]
      || (arguments.count == 3 && arguments[0] == "seed" && arguments[1] == "--rate")
    {
      let sampleRate: Double
      if arguments.count == 3, let parsed = Double(arguments[2]) {
        sampleRate = parsed
      } else {
        sampleRate = 125
      }
      let trace = try SyntheticMotionTraceFactory.make(sampleRateHz: sampleRate)
      let directory =
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser)
        .appendingPathComponent("DeskMux", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent("latest-motion-trace.json")
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.sortedKeys]
      try encoder.encode(trace).write(to: url, options: .atomic)
      try writeJSON(
        SyntheticTraceOutput(
          path: url.path,
          sampleCount: trace.samples.count,
          durationNanoseconds: trace.durationNanoseconds
        ))
      return
    }
    let candidate: String
    if arguments == ["trigger"] {
      candidate = "working-tree"
    } else if arguments.count == 3, arguments[0] == "trigger",
      arguments[1] == "--candidate"
    {
      candidate = arguments[2]
    } else {
      throw AgentError.unknownResearchCommand(arguments)
    }
    DistributedNotificationCenter.default().postNotificationName(
      Notification.Name("dev.deskmux.runMotionResearch"),
      object: nil,
      userInfo: ["candidate": candidate],
      deliverImmediately: true
    )
  }

  private static func simulate(profileName: String) async throws -> SimulationOutput {
    let studio = PeerID(rawValue: "studio")
    let macBook = PeerID(rawValue: "macbook")
    let viewSonic = MonitorID(rawValue: "viewsonic-vp2768")
    let aoc = MonitorID(rawValue: "aoc-u27b3cf")

    let registry = RouteRegistry()
    let probeID = UUID()
    // These represent four separate moments in a guided setup flow. A route
    // is only learned while its peer actually sees that display online.
    let routeObservations = [
      DisplayObservation(
        peerID: studio,
        monitorID: viewSonic,
        currentInput: .hdmi1,
        isActiveSource: true,
        evidence: .guided(probeID: probeID)
      ),
      DisplayObservation(
        peerID: macBook,
        monitorID: viewSonic,
        currentInput: .hdmi2,
        isActiveSource: true,
        evidence: .guided(probeID: probeID)
      ),
      DisplayObservation(
        peerID: studio,
        monitorID: aoc,
        currentInput: .hdmi1,
        isActiveSource: true,
        evidence: .guided(probeID: probeID)
      ),
      DisplayObservation(
        peerID: macBook,
        monitorID: aoc,
        currentInput: .usbC,
        isActiveSource: true,
        evidence: .guided(probeID: probeID)
      ),
    ]
    for observation in routeObservations {
      await registry.observe(observation)
    }

    // This is the current desk state after setup: ViewSonic on Studio and
    // AOC on MacBook. It is intentionally distinct from route evidence.
    let topologyObservations = [
      DisplayObservation(
        peerID: studio,
        monitorID: viewSonic,
        currentInput: .hdmi1,
        isActiveSource: true,
        evidence: .passive(session: ObservationSessionID())
      ),
      DisplayObservation(
        peerID: macBook,
        monitorID: aoc,
        currentInput: .usbC,
        isActiveSource: true,
        evidence: .passive(session: ObservationSessionID())
      ),
    ]

    let profile: DeskProfile
    switch profileName.lowercased() {
    case "studio":
      profile = DeskProfile(
        name: "Studio",
        assignments: [
          MonitorAssignment(monitorID: viewSonic, destinationPeerID: studio),
          MonitorAssignment(monitorID: aoc, destinationPeerID: studio),
        ],
        inputDestinationPeerID: studio
      )
    case "macbook":
      profile = DeskProfile(
        name: "MacBook",
        assignments: [
          MonitorAssignment(monitorID: viewSonic, destinationPeerID: macBook),
          MonitorAssignment(monitorID: aoc, destinationPeerID: macBook),
        ],
        inputDestinationPeerID: macBook
      )
    case "split":
      profile = DeskProfile(
        name: "Split",
        assignments: [
          MonitorAssignment(monitorID: viewSonic, destinationPeerID: studio),
          MonitorAssignment(monitorID: aoc, destinationPeerID: macBook),
        ],
        inputDestinationPeerID: studio
      )
    default:
      throw AgentError.unknownProfile(profileName)
    }

    let driver = SimulationDriver()
    let routes = await registry.snapshot()
    let topology = TopologySnapshot(observations: topologyObservations)
    let report = await TransactionEngine().execute(
      profile: profile,
      topology: topology,
      confirmedRoutes: routes,
      driver: driver
    )
    return SimulationOutput(
      profile: profile.name,
      learnedRoutes: routes,
      operations: await driver.operationLog(),
      report: report
    )
  }

  private static func printUsage() {
    print(
      """
      Usage:
        deskmux-agent snapshot [peer-id]
        deskmux-agent simulate <studio|macbook|split>
        deskmux-agent input permissions [--request]
        deskmux-agent input monitor <seconds>
        deskmux-agent input loopback <seconds>
        deskmux-agent logitech discover
        deskmux-agent logitech probe
        deskmux-agent logitech switch --from <zero-based-host> --to <zero-based-host>
        deskmux-agent asus inventory
        deskmux-agent asus receiver-status
        deskmux-agent asus rf-test --acknowledge-transient-input-loss
        deskmux-agent asus factory-rf-test --acknowledge-temporary-factory-mode-and-recovery-plan
        deskmux-agent asus factory-rf-input-test <1-15 seconds> --acknowledge-temporary-factory-mode-and-recovery-plan
        deskmux-agent asus inspect <seconds>
        deskmux-agent asus paths <seconds>
        DESKMUX_SHARED_KEY=... deskmux-agent input receive --peer <peer-id>
        DESKMUX_SHARED_KEY=... deskmux-agent input probe --peer <peer-id> --to <peer-id>
        DESKMUX_SHARED_KEY=... deskmux-agent input relay --peer <peer-id> --to <peer-id>
        DESKMUX_SHARED_KEY=... deskmux-agent input relay --peer <peer-id> --to <peer-id> --keyboard-only
        DESKMUX_SHARED_KEY=... deskmux-agent update send --peer <peer-id> --to <peer-id> --app <path>
        deskmux-agent update trigger
        deskmux-agent research trigger [--candidate <name>]
        deskmux-agent research seed [--rate <hz>]

      snapshot emits a sanitized local machine/display observation.
      simulate exercises the known two-Mac, two-monitor topology without
      emitting DDC commands or input events.
      input permissions reports or requests the two required macOS grants.
      input monitor passively counts event types and never suppresses input.
      input loopback suppresses and immediately reinjects events on this Mac,
      with a maximum duration of 30 seconds.
      logitech discover lists compatible HID++ control interfaces without opening them.
      logitech probe read-only checks whether those interfaces expose ChangeHost 0x1814.
      logitech switch requires the expected current host and refuses stale or ambiguous routing.
      asus inventory lists only the exact wired keyboard and RF receiver without opening them.
      asus receiver-status sends only the receiver's non-mutating battery/status query.
      asus rf-test sends one reversible RF enter/leave pair; it contains no factory,
      pairing, or firmware commands and pins both observed hardware revisions.
      asus factory-rf-test reproduces only ASUS's transient factory/RF connection test;
      it omits every pairing-data and firmware command and requires explicit acknowledgement.
      asus factory-rf-input-test holds that same state for a bounded counter-only path test.
      asus inspect passively records only the keyboard's vendor input reports and never writes.
      asus paths passively counts wired and RF input changes without retaining their values.
      receive advertises an encrypted Bonjour input receiver.
      probe verifies discovery and the encrypted ready handshake without capturing input.
      relay transfers local input to a ready receiver; --keyboard-only never captures
      mouse motion, buttons, or scrolling.
      Press ⌃⌥⌘Esc at the source to end a relay immediately.
      update sends a newer signed DeskMux app to a paired peer for validation,
      installation, and relaunch.
      update trigger asks the running Studio menu-bar app to send itself.
      research trigger asks the running Studio app to replay the saved motion-only trace.
      research seed creates a deterministic net-zero trace for unattended transport tests.
      """
    )
  }
}

private struct SyntheticTraceOutput: Encodable {
  let path: String
  let sampleCount: Int
  let durationNanoseconds: UInt64
}

private struct InputProbeOutput: Encodable {
  let sourcePeerID: PeerID
  let destinationPeerID: PeerID
  let acknowledgedPeerID: PeerID
}

private enum AgentError: Error, CustomStringConvertible {
  case unknownProfile(String)
  case unknownInputCommand([String])
  case unknownUpdateCommand([String])
  case unknownLogitechCommand([String])
  case unknownASUSCommand([String])
  case unknownResearchCommand([String])
  case invalidMonitorDuration(String)
  case invalidLoopbackDuration(String)

  var description: String {
    switch self {
    case .unknownProfile(let name):
      return "unknown simulated profile '\(name)'"
    case .unknownInputCommand(let arguments):
      return "unknown input command '\(arguments.joined(separator: " "))'"
    case .unknownUpdateCommand(let arguments):
      return "unknown update command '\(arguments.joined(separator: " "))'"
    case .unknownLogitechCommand(let arguments):
      return "unknown Logitech command '\(arguments.joined(separator: " "))'"
    case .unknownASUSCommand(let arguments):
      return "unknown ASUS command '\(arguments.joined(separator: " "))'"
    case .unknownResearchCommand(let arguments):
      return "unknown research command '\(arguments.joined(separator: " "))'"
    case .invalidMonitorDuration(let value):
      return "input monitor duration must be between 0 and 60 seconds, got '\(value)'"
    case .invalidLoopbackDuration(let value):
      return "input loopback duration must be between 0 and 30 seconds, got '\(value)'"
    }
  }
}
