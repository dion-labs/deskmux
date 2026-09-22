import CoreGraphics
import DeskMuxCore
import DeskMuxMacInput
import Foundation

// Internal side-effect boundaries. Production always supplies the native
// adapters below; isolated receiver tests supply only in-memory sinks.
// Synchronous dependency entry points must not reenter the owning
// ReceiverSession. Escape handlers are deferred; clipboard completion may run
// synchronously or asynchronously and only sends an acknowledgement. This
// preserves the existing native lock contract.
protocol ReceiverInputSink: AnyObject, Sendable {
  var sessionID: UUID { get }
  func inject(_ packet: InputEventPacket) throws
  func injectPointerMotion(_ state: PointerMotionState) throws
  func releaseAll()
}

protocol ReceiverEscapeMonitor: AnyObject, Sendable {
  func run() throws
  func stop()
}

extension MacInputInjector: ReceiverInputSink {}
extension MacLocalEscapeMonitor: ReceiverEscapeMonitor {}

struct ReceiverSessionDependencies: Sendable {
  let makeInput: @Sendable (UUID) throws -> any ReceiverInputSink
  let registerInput: @Sendable (any ReceiverInputSink) -> Void
  let unregisterInput: @Sendable (UUID) -> Void
  let publishModifiers: @Sendable (UInt64) -> Void
  let makeEscapeMonitor: @Sendable (@escaping @Sendable () -> Void) -> any ReceiverEscapeMonitor
  let applyClipboard: @Sendable (DeskMuxClipboardUpdate, @escaping @Sendable () -> Void) -> Void
  let installUpdate: @Sendable (DeskMuxUpdatePackage, PeerID?) -> DeskMuxUpdateResult

  static func production(motionSessions: MotionSessionRegistry) -> Self {
    Self(
      makeInput: { try MacInputInjector(sessionID: $0) },
      registerInput: { motionSessions.register($0) },
      unregisterInput: { motionSessions.unregister(sessionID: $0) },
      publishModifiers: { MacInputModifierBridge.publish(CGEventFlags(rawValue: $0)) },
      makeEscapeMonitor: { MacLocalEscapeMonitor(handler: $0) },
      applyClipboard: { DeskMuxClipboardBridge.shared.applyRemote($0, completion: $1) },
      installUpdate: { DeskMuxAppUpdateInstaller.verifyInstallAndScheduleRelaunch($0, sourcePeerID: $1) }
    )
  }
}
