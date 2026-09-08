import AppKit

// Offscreen rendering only: never orders a window or moves/captures input.
// swiftc Sources/DeskMuxMenuBar/CursorHandoffFeedbackController.swift \
//   Tools/cursor-feedback-preview/main.swift -o .build/cursor-feedback-preview
let application = NSApplication.shared
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for (name, phase) in [
  ("preparing", CursorHandoffPhase.preparing),
  ("sent", .sent),
  ("failed", .failed),
] {
  let frame = NSRect(origin: .zero, size: CursorHandoffLayout.size)
  let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
  let view = CursorHandoffFeedbackView(frame: frame, pointsLeft: true)
  window.contentView = view
  view.update(phase: phase, destinationName: "MacBook")
  view.layoutSubtreeIfNeeded()
  window.displayIfNeeded()
  guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
    fatalError("Could not allocate preview bitmap")
  }
  view.cacheDisplay(in: view.bounds, to: bitmap)
  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode preview bitmap")
  }
  try png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
  view.stopAnimating()
}
