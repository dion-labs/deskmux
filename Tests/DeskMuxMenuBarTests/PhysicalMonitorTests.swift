import Testing
import Foundation
@testable import DeskMuxMenuBar

@Test func monitorFollowDebouncesAndKeepsOnlyLatestOwner() {
  var gate = MonitorFollowGate()
  let t = Date(timeIntervalSince1970: 100)
  #expect(gate.target(owner: "Studio", enabled: true, busy: false, now: t) == nil)
  #expect(gate.target(owner: "MacBook", enabled: true, busy: true, now: t.addingTimeInterval(1)) == nil)
  #expect(gate.target(owner: "Studio", enabled: true, busy: true, now: t.addingTimeInterval(2)) == nil)
  #expect(gate.target(owner: "Studio", enabled: true, busy: false, now: t.addingTimeInterval(3)) == nil)
  #expect(gate.target(owner: "Studio", enabled: true, busy: false, now: t.addingTimeInterval(4)) == "Studio")
  gate.nextAllowed = t.addingTimeInterval(10)
  #expect(gate.target(owner: "MacBook", enabled: true, busy: false, now: t.addingTimeInterval(5)) == nil)
  #expect(gate.target(owner: "MacBook", enabled: true, busy: false, now: t.addingTimeInterval(8)) == nil)
  #expect(gate.target(owner: "MacBook", enabled: true, busy: false, now: t.addingTimeInterval(10)) == "MacBook")
}

@Test func monitorFollowNeverActsWhenDisabledOrOwnerUnknown() {
  var gate = MonitorFollowGate()
  let t = Date()
  #expect(gate.target(owner: "Studio", enabled: false, busy: false, now: t) == nil)
  #expect(gate.target(owner: nil, enabled: true, busy: false, now: t) == nil)
  #expect(gate.target(owner: "Unknown", enabled: true, busy: false, now: t) == nil)
  #expect(gate.target(owner: "Studio", enabled: true, busy: false, now: t) == nil)
  #expect(gate.target(owner: nil, enabled: true, busy: false, now: t.addingTimeInterval(5)) == nil)
  #expect(gate.target(owner: "Studio", enabled: true, busy: false, now: t.addingTimeInterval(6)) == nil)
}

@Test func monitorReadbackRejectsErrorsAndInvalidValues() {
  #expect(PhysicalMonitorRoute.parseInput("17\n") == 17)
  #expect(PhysicalMonitorRoute.parseInput("21\n") == 21)
  #expect(PhysicalMonitorRoute.parseInput("Writing 17") == nil)
  #expect(PhysicalMonitorRoute.parseInput("DDC communication failure") == nil)
  #expect(PhysicalMonitorRoute.parseInput("-1") == nil)
  #expect(PhysicalMonitorRoute.parseInput("256") == nil)
  #expect(PhysicalMonitorRoute.parseInput("17\n21") == nil)
}

@Test func monitorMappingMatchesObservedHardwareNotGenericUSBCCode() {
  #expect(PhysicalMonitorRoute.validatedDesk.studioInput == 21)
  #expect(PhysicalMonitorRoute.validatedDesk.macbookInput == 17)
}

@Test func monitorIdentityIsPeerLocalAndRejectsAmbiguousDisplays() {
  #expect(PhysicalMonitorRoute.uniqueLocalDisplay(["macbook-local"]) == "macbook-local")
  #expect(PhysicalMonitorRoute.uniqueLocalDisplay([]) == nil)
  #expect(PhysicalMonitorRoute.uniqueLocalDisplay(["a", "b"]) == nil)
}
