import Foundation
import Testing

@testable import DeskMuxCore

@Test func keyboardOnlySessionIgnoresNativeDestinationMouseAndKeyboard() {
  #expect(!InputSessionMode.keyboardOnly.returnsOnDestinationLocalInput)
  #expect(InputSessionMode.allInput.returnsOnDestinationLocalInput)
}

@Test func inputOwnershipFailsClosedWhenDestinationDisconnects() async throws {
  let studio = PeerID(rawValue: "studio")
  let macBook = PeerID(rawValue: "macbook")
  let session = UUID()
  let coordinator = InputOwnershipCoordinator(localPeerID: studio)

  await coordinator.peerBecameAvailable(macBook)
  #expect(
    try await coordinator.handOff(to: macBook, sessionID: session)
      == .remote(
        peerID: macBook,
        sessionID: session
      ))
  #expect(await coordinator.peerBecameUnavailable(macBook) == .local)
  #expect(await coordinator.ownership == .local)
}

@Test func inputOwnershipRejectsAnUnavailableDestination() async {
  let coordinator = InputOwnershipCoordinator(localPeerID: PeerID(rawValue: "studio"))
  let macBook = PeerID(rawValue: "macbook")

  await #expect(throws: InputOwnershipIssue.destinationUnavailable(macBook)) {
    try await coordinator.handOff(to: macBook)
  }
  #expect(await coordinator.ownership == .local)
}
