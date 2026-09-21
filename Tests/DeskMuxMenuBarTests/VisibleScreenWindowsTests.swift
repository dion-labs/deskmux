import Foundation
import Testing
@testable import DeskMuxMenuBar

@Test func windowsFitSmallerFallbackWithoutGoingOffscreen() {
  let source = CGRect(x: -2560, y: -500, width: 2560, height: 1440)
  let destination = CGRect(x: 0, y: 25, width: 1512, height: 920)
  let moved = WindowPlacementGeometry.evacuate(CGRect(x: -1800, y: -200, width: 1900, height: 1100), from: source, to: destination)
  #expect(destination.contains(moved))
  #expect(moved.size == destination.size)
}

@Test func deliberateMovesAndResizesPreventRestoration() {
  let placed = CGRect(x: 20, y: 50, width: 800, height: 600)
  #expect(WindowPlacementGeometry.unchanged(placed, placed.offsetBy(dx: 1, dy: 1)))
  #expect(!WindowPlacementGeometry.unchanged(placed, placed.offsetBy(dx: 30, dy: 0)))
  #expect(!WindowPlacementGeometry.unchanged(placed, CGRect(x: 20, y: 50, width: 850, height: 600)))
}
