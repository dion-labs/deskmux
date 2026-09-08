import DeskMuxCore
import Foundation
import Network

public enum DeskMuxServiceComponent: String, Sendable {
  case app
  case agent
}

public struct DeskMuxVersionAdvertisement: Equatable, Sendable {
  public static let componentKey = "component"
  public static let buildKey = "build"
  public static let protocolKey = "protocol"

  public let component: DeskMuxServiceComponent
  public let build: String
  public let protocolVersion: Int

  public init(component: DeskMuxServiceComponent, build: String, protocolVersion: Int) {
    self.component = component
    self.build = build
    self.protocolVersion = protocolVersion
  }

  public var txtRecord: NWTXTRecord {
    NWTXTRecord([
      Self.componentKey: component.rawValue,
      Self.buildKey: build,
      Self.protocolKey: String(protocolVersion),
    ])
  }

  public init?(txtRecord: NWTXTRecord) {
    let values = txtRecord.dictionary
    guard let rawComponent = values[Self.componentKey],
      let component = DeskMuxServiceComponent(rawValue: rawComponent),
      let build = values[Self.buildKey], !build.isEmpty,
      let rawProtocol = values[Self.protocolKey],
      let protocolVersion = Int(rawProtocol)
    else { return nil }
    self.init(component: component, build: build, protocolVersion: protocolVersion)
  }
}

public struct DeskMuxPeerVersionSnapshot: Equatable, Sendable {
  public var appServiceFound: Bool
  public var app: DeskMuxVersionAdvertisement?
  public var agentServiceFound: Bool
  public var agent: DeskMuxVersionAdvertisement?

  public init(
    appServiceFound: Bool = false,
    app: DeskMuxVersionAdvertisement? = nil,
    agentServiceFound: Bool = false,
    agent: DeskMuxVersionAdvertisement? = nil
  ) {
    self.appServiceFound = appServiceFound
    self.app = app
    self.agentServiceFound = agentServiceFound
    self.agent = agent
  }
}

/// Watches the paired Mac's app-update and stable-agent Bonjour records. The
/// records are diagnostic only; updates still require the encrypted protocol,
/// signature validation, and the matching designated requirement.
public final class BonjourPeerVersionMonitor: @unchecked Sendable {
  public typealias SnapshotHandler = @Sendable (DeskMuxPeerVersionSnapshot) -> Void

  private let peerID: PeerID
  private let snapshotHandler: SnapshotHandler
  private let queue = DispatchQueue(label: "dev.deskmux.version-monitor")
  private let lock = NSLock()
  private var appBrowser: NWBrowser?
  private var agentBrowser: NWBrowser?
  private var snapshot = DeskMuxPeerVersionSnapshot()

  public init(peerID: PeerID, snapshotHandler: @escaping SnapshotHandler) {
    self.peerID = peerID
    self.snapshotHandler = snapshotHandler
  }

  public func start() {
    let shouldStart = lock.withLock { self.appBrowser == nil && self.agentBrowser == nil }
    guard shouldStart else { return }

    let newAppBrowser = makeBrowser(
      serviceType: BonjourAppUpdateSource.serviceType,
      expectedComponent: .app
    )
    let newAgentBrowser = makeBrowser(
      serviceType: BonjourInputRelaySource.serviceType,
      expectedComponent: .agent
    )
    lock.withLock {
      self.appBrowser = newAppBrowser
      self.agentBrowser = newAgentBrowser
    }
    newAppBrowser.start(queue: queue)
    newAgentBrowser.start(queue: queue)
  }

  public func stop() {
    let browsers = lock.withLock { () -> (NWBrowser?, NWBrowser?) in
      let browsers = (appBrowser, agentBrowser)
      appBrowser = nil
      agentBrowser = nil
      snapshot = DeskMuxPeerVersionSnapshot()
      return browsers
    }
    browsers.0?.cancel()
    browsers.1?.cancel()
  }

  private func makeBrowser(
    serviceType: String,
    expectedComponent: DeskMuxServiceComponent
  ) -> NWBrowser {
    let browser = NWBrowser(
      for: .bonjourWithTXTRecord(type: serviceType, domain: nil),
      using: inputRelayTCPParameters()
    )
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      self?.consume(results: results, expectedComponent: expectedComponent)
    }
    return browser
  }

  private func consume(
    results: Set<NWBrowser.Result>,
    expectedComponent: DeskMuxServiceComponent
  ) {
    let matches = results.compactMap { result -> (Int, DeskMuxVersionAdvertisement?)? in
      guard case .service(let name, _, _, _) = result.endpoint,
        let rank = deskMuxServiceRank(name: name, peerID: peerID)
      else { return nil }
      let advertisement: DeskMuxVersionAdvertisement?
      if case .bonjour(let txtRecord) = result.metadata,
        let decoded = DeskMuxVersionAdvertisement(txtRecord: txtRecord),
        decoded.component == expectedComponent
      {
        advertisement = decoded
      } else {
        advertisement = nil
      }
      return (rank, advertisement)
    }
    let selected = matches.max(by: { $0.0 < $1.0 })
    let newSnapshot = lock.withLock { () -> DeskMuxPeerVersionSnapshot in
      switch expectedComponent {
      case .app:
        snapshot.appServiceFound = selected != nil
        snapshot.app = selected?.1
      case .agent:
        snapshot.agentServiceFound = selected != nil
        snapshot.agent = selected?.1
      }
      return snapshot
    }
    snapshotHandler(newSnapshot)
  }
}
