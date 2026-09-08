import AppKit
import CVirtualDisplayBridge
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

public struct DeskMuxVirtualDisplayConfiguration: Codable, Equatable, Sendable {
  public var name: String
  public var nativeWidth: Int
  public var nativeHeight: Int
  public var logicalWidth: Int
  public var logicalHeight: Int
  public var refreshRate: Double

  public init(
    name: String = "DeskMux Virtual Display",
    nativeWidth: Int = 3840,
    nativeHeight: Int = 2400,
    logicalWidth: Int = 1920,
    logicalHeight: Int = 1200,
    refreshRate: Double = 60
  ) {
    self.name = name
    self.nativeWidth = nativeWidth
    self.nativeHeight = nativeHeight
    self.logicalWidth = logicalWidth
    self.logicalHeight = logicalHeight
    self.refreshRate = refreshRate
  }

  public var isValid: Bool {
    !name.isEmpty
      && nativeWidth >= logicalWidth
      && nativeHeight >= logicalHeight
      && logicalWidth >= 640
      && logicalHeight >= 480
      && (30...120).contains(refreshRate)
  }
}

public enum DeskMuxVirtualDisplayError: Error, CustomStringConvertible, Equatable, Sendable {
  case unsupported
  case invalidConfiguration
  case creationFailed(String)

  public var description: String {
    switch self {
    case .unsupported:
      return "This macOS version does not expose the virtual-display runtime."
    case .invalidConfiguration:
      return "The requested virtual-display configuration is invalid."
    case .creationFailed(let reason):
      return "The virtual display could not be created: \(reason)"
    }
  }
}

@MainActor
public final class DeskMuxVirtualDisplaySession {
  private var referenceBits: UInt = 0
  public let displayID: CGDirectDisplayID
  public let configuration: DeskMuxVirtualDisplayConfiguration

  public static var isSupported: Bool { DMXVirtualDisplayIsSupported() }

  public init(configuration: DeskMuxVirtualDisplayConfiguration = .init()) throws {
    guard configuration.isValid else { throw DeskMuxVirtualDisplayError.invalidConfiguration }
    guard Self.isSupported else { throw DeskMuxVirtualDisplayError.unsupported }

    var errorBytes = [CChar](repeating: 0, count: 512)
    let created = configuration.name.withCString { name in
      DMXVirtualDisplayCreate(
        name,
        configuration.nativeWidth,
        configuration.nativeHeight,
        configuration.logicalWidth,
        configuration.logicalHeight,
        configuration.refreshRate,
        0xD35C,
        0x4D58,
        1,
        &errorBytes,
        errorBytes.count
      )
    }
    guard let created else {
      let reason = String(
        decoding: errorBytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
      )
      throw DeskMuxVirtualDisplayError.creationFailed(
        reason.isEmpty ? "the private runtime returned no display" : reason)
    }
    let displayID = DMXVirtualDisplayGetDisplayID(created)
    guard displayID != kCGNullDirectDisplay else {
      DMXVirtualDisplayRelease(created)
      throw DeskMuxVirtualDisplayError.creationFailed("the display has no Core Graphics ID")
    }
    referenceBits = UInt(bitPattern: created)
    self.displayID = displayID
    self.configuration = configuration
  }

  deinit {
    if let reference = DMXVirtualDisplayRef(bitPattern: referenceBits) {
      DMXVirtualDisplayRelease(reference)
    }
  }

  public func invalidate() {
    guard let reference = DMXVirtualDisplayRef(bitPattern: referenceBits) else { return }
    DMXVirtualDisplayRelease(reference)
    referenceBits = 0
  }
}

public struct DeskMuxDisplaySnapshot: Codable, Equatable, Sendable {
  public let displayID: UInt32
  public let width: Int
  public let height: Int
  public let isMain: Bool
  public let isOnline: Bool

  public init(
    displayID: UInt32,
    width: Int,
    height: Int,
    isMain: Bool,
    isOnline: Bool
  ) {
    self.displayID = displayID
    self.width = width
    self.height = height
    self.isMain = isMain
    self.isOnline = isOnline
  }
}

public enum DeskMuxScreenCaptureCheck: Codable, Equatable, Sendable {
  case permissionMissing
  case displayNotEnumerated
  case frameReceived(width: Int, height: Int)
  case noFrame
  case failed(String)
}

public enum DeskMuxVirtualDisplayInspector {
  public static func onlineDisplays() -> [DeskMuxDisplaySnapshot] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var identifiers = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &identifiers, &count) == .success else { return [] }
    return identifiers.prefix(Int(count)).map { identifier in
      let bounds = CGDisplayBounds(identifier)
      return DeskMuxDisplaySnapshot(
        displayID: identifier,
        width: Int(bounds.width),
        height: Int(bounds.height),
        isMain: CGDisplayIsMain(identifier) != 0,
        isOnline: CGDisplayIsOnline(identifier) != 0
      )
    }
  }

  public static func waitForDisplay(
    _ displayID: CGDirectDisplayID,
    present: Bool,
    attempts: Int = 50
  ) async -> Bool {
    for _ in 0..<attempts {
      let found = onlineDisplays().contains { $0.displayID == displayID }
      if found == present { return true }
      try? await Task.sleep(for: .milliseconds(100))
    }
    return false
  }

  public static func captureFirstFrame(
    displayID: CGDirectDisplayID
  ) async -> DeskMuxScreenCaptureCheck {
    guard CGPreflightScreenCaptureAccess() else { return .permissionMissing }
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(
        false,
        onScreenWindowsOnly: false
      )
      guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
        return .displayNotEnumerated
      }

      let configuration = SCStreamConfiguration()
      configuration.width = min(display.width, 1920)
      configuration.height = min(display.height, 1200)
      configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
      configuration.queueDepth = 2
      configuration.showsCursor = false
      let filter = SCContentFilter(
        display: display,
        excludingApplications: [],
        exceptingWindows: []
      )
      let output = FirstFrameOutput()
      let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
      try stream.addStreamOutput(
        output,
        type: .screen,
        sampleHandlerQueue: DispatchQueue(label: "dev.deskmux.virtual-display-probe.frames")
      )
      try await stream.startCapture()
      for _ in 0..<40 where output.frameSize == nil {
        try? await Task.sleep(for: .milliseconds(50))
      }
      try await stream.stopCapture()
      guard let frameSize = output.frameSize else { return .noFrame }
      return .frameReceived(width: frameSize.width, height: frameSize.height)
    } catch {
      return .failed(String(describing: error))
    }
  }
}

private final class FirstFrameOutput: NSObject, SCStreamOutput, @unchecked Sendable {
  private let lock = NSLock()
  private var storedFrameSize: (width: Int, height: Int)?

  var frameSize: (width: Int, height: Int)? {
    lock.withLock { storedFrameSize }
  }

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    guard outputType == .screen,
      sampleBuffer.isValid,
      let imageBuffer = sampleBuffer.imageBuffer
    else { return }
    lock.withLock {
      if storedFrameSize == nil {
        storedFrameSize = (
          CVPixelBufferGetWidth(imageBuffer),
          CVPixelBufferGetHeight(imageBuffer)
        )
      }
    }
  }
}
