import CoreMedia
import CoreGraphics
import DeskMuxVirtualDisplay
import Foundation
import ScreenCaptureKit
import VideoToolbox

final class VirtualDisplayVideoSource: NSObject, SCStreamOutput, SCStreamDelegate,
  @unchecked Sendable
{
  typealias MessageHandler = @Sendable (DeskMuxScreenWireMessage) -> Void

  private let messageHandler: MessageHandler
  private var displaySession: DeskMuxVirtualDisplaySession?
  private var stream: SCStream?
  private var encoder: H264RealtimeEncoder?
  private var pressedKeys = Set<UInt16>()
  private var pressedButtons = Set<Int>()
  private var lastPointerLocation: CGPoint?
  private let frameQueue = DispatchQueue(label: "dev.deskmux.screen.capture", qos: .userInteractive)

  init(messageHandler: @escaping MessageHandler) {
    self.messageHandler = messageHandler
  }

  @MainActor
  func start() async throws {
    guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
      throw DeskMuxScreenTransportError.captureFailed(
        "Enable Screen & System Audio Recording for DeskMux Agent, then restart DeskMux."
      )
    }
    let displaySession = try DeskMuxVirtualDisplaySession()
    self.displaySession = displaySession
    guard await DeskMuxVirtualDisplayInspector.waitForDisplay(displaySession.displayID, present: true)
    else {
      throw DeskMuxScreenTransportError.captureFailed(
        "The virtual display did not appear in Core Graphics."
      )
    }
    let content = try await SCShareableContent.excludingDesktopWindows(
      false,
      onScreenWindowsOnly: false
    )
    guard let display = content.displays.first(where: { $0.displayID == displaySession.displayID })
    else {
      throw DeskMuxScreenTransportError.captureFailed(
        "ScreenCaptureKit did not enumerate the virtual display."
      )
    }

    let encoder = try H264RealtimeEncoder(width: 1920, height: 1200) { [messageHandler] message in
      messageHandler(message)
    }
    self.encoder = encoder
    let configuration = SCStreamConfiguration()
    configuration.width = 1920
    configuration.height = 1200
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    configuration.queueDepth = 3
    configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    configuration.showsCursor = false
    let filter = SCContentFilter(
      display: display,
      excludingApplications: [],
      exceptingWindows: []
    )
    let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
    self.stream = stream
    try await stream.startCapture()
  }

  @MainActor
  func stop() async {
    if let stream { try? await stream.stopCapture() }
    stream = nil
    encoder?.finish()
    encoder = nil
    displaySession?.invalidate()
    displaySession = nil
  }

  @MainActor
  func inject(_ event: DeskMuxScreenInputEvent) {
    guard let displayID = displaySession?.displayID else { return }
    let bounds = CGDisplayBounds(displayID)
    switch event {
    case .pointerMove(let x, let y, let draggingButton):
      let point = Self.point(x: x, y: y, in: bounds)
      lastPointerLocation = point
      let type: CGEventType = switch draggingButton {
      case 0: .leftMouseDragged
      case 1: .rightMouseDragged
      case .some: .otherMouseDragged
      case nil: .mouseMoved
      }
      CGEvent(
        mouseEventSource: nil,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: Self.button(draggingButton ?? 0)
      )?.post(tap: .cghidEventTap)
    case .mouseButton(let x, let y, let button, let isDown, let clickCount):
      let point = Self.point(x: x, y: y, in: bounds)
      lastPointerLocation = point
      if isDown { pressedButtons.insert(button) } else { pressedButtons.remove(button) }
      let type: CGEventType = switch (button, isDown) {
      case (0, true): .leftMouseDown
      case (0, false): .leftMouseUp
      case (1, true): .rightMouseDown
      case (1, false): .rightMouseUp
      case (_, true): .otherMouseDown
      case (_, false): .otherMouseUp
      }
      let cgEvent = CGEvent(
        mouseEventSource: nil,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: Self.button(button)
      )
      cgEvent?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
      cgEvent?.post(tap: .cghidEventTap)
    case .scroll(_, _, let deltaX, let deltaY):
      CGEvent(
        scrollWheelEvent2Source: nil,
        units: .pixel,
        wheelCount: 2,
        wheel1: Int32(deltaY.rounded()),
        wheel2: Int32(deltaX.rounded()),
        wheel3: 0
      )?.post(tap: .cghidEventTap)
    case .key(let keyCode, let isDown, let flags),
      .flagsChanged(let keyCode, let isDown, let flags):
      if isDown { pressedKeys.insert(keyCode) } else { pressedKeys.remove(keyCode) }
      let cgEvent = CGEvent(
        keyboardEventSource: nil,
        virtualKey: CGKeyCode(keyCode),
        keyDown: isDown
      )
      cgEvent?.flags = CGEventFlags(rawValue: flags)
      cgEvent?.post(tap: .cghidEventTap)
    case .releaseAll:
      let point = lastPointerLocation ?? CGPoint(x: bounds.midX, y: bounds.midY)
      for button in pressedButtons {
        let type: CGEventType = button == 0 ? .leftMouseUp : (button == 1 ? .rightMouseUp : .otherMouseUp)
        CGEvent(
          mouseEventSource: nil,
          mouseType: type,
          mouseCursorPosition: point,
          mouseButton: Self.button(button)
        )?.post(tap: .cghidEventTap)
      }
      for keyCode in pressedKeys {
        CGEvent(
          keyboardEventSource: nil,
          virtualKey: CGKeyCode(keyCode),
          keyDown: false
        )?.post(tap: .cghidEventTap)
      }
      pressedButtons.removeAll()
      pressedKeys.removeAll()
    }
  }

  private static func point(x: Double, y: Double, in bounds: CGRect) -> CGPoint {
    CGPoint(
      x: bounds.minX + min(max(x, 0), 1) * bounds.width,
      y: bounds.minY + min(max(y, 0), 1) * bounds.height
    )
  }

  private static func button(_ value: Int) -> CGMouseButton {
    switch value {
    case 0: return .left
    case 1: return .right
    default: return .center
    }
  }

  nonisolated func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    guard outputType == .screen, sampleBuffer.isValid,
      let imageBuffer = sampleBuffer.imageBuffer
    else { return }
    encoder?.encode(
      imageBuffer,
      presentationTimeStamp: sampleBuffer.presentationTimeStamp
    )
  }

  nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
    messageHandler(.failure("ScreenCaptureKit stopped: \(error.localizedDescription)"))
  }
}

private final class H264RealtimeEncoder: @unchecked Sendable {
  private var session: VTCompressionSession?
  private let messageHandler: @Sendable (DeskMuxScreenWireMessage) -> Void
  private let lock = NSLock()
  private var sentFormat = false
  private var sequence: UInt64 = 0

  init(
    width: Int32,
    height: Int32,
    messageHandler: @escaping @Sendable (DeskMuxScreenWireMessage) -> Void
  ) throws {
    self.messageHandler = messageHandler
    var session: VTCompressionSession?
    let status = VTCompressionSessionCreate(
      allocator: kCFAllocatorDefault,
      width: width,
      height: height,
      codecType: kCMVideoCodecType_H264,
      encoderSpecification: nil,
      imageBufferAttributes: nil,
      compressedDataAllocator: nil,
      outputCallback: { refcon, _, status, _, sampleBuffer in
        guard status == noErr, let refcon, let sampleBuffer else { return }
        let encoder = Unmanaged<H264RealtimeEncoder>.fromOpaque(refcon).takeUnretainedValue()
        encoder.didEncode(sampleBuffer)
      },
      refcon: Unmanaged.passUnretained(self).toOpaque(),
      compressionSessionOut: &session
    )
    guard status == noErr, let session else {
      throw DeskMuxScreenTransportError.captureFailed(
        "VideoToolbox could not create an H.264 encoder (\(status))."
      )
    }
    self.session = session
    VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
    VTSessionSetProperty(
      session,
      key: kVTCompressionPropertyKey_AllowFrameReordering,
      value: kCFBooleanFalse
    )
    VTSessionSetProperty(
      session,
      key: kVTCompressionPropertyKey_ProfileLevel,
      value: kVTProfileLevel_H264_Main_AutoLevel
    )
    VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: 8_000_000 as CFNumber)
    VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 30 as CFNumber)
    VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 60 as CFNumber)
    VTCompressionSessionPrepareToEncodeFrames(session)
  }

  func encode(_ imageBuffer: CVImageBuffer, presentationTimeStamp: CMTime) {
    guard let session else { return }
    VTCompressionSessionEncodeFrame(
      session,
      imageBuffer: imageBuffer,
      presentationTimeStamp: presentationTimeStamp,
      duration: CMTime(value: 1, timescale: 30),
      frameProperties: nil,
      sourceFrameRefcon: nil,
      infoFlagsOut: nil
    )
  }

  func finish() {
    guard let session else { return }
    VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
    VTCompressionSessionInvalidate(session)
    self.session = nil
  }

  private func didEncode(_ sampleBuffer: CMSampleBuffer) {
    guard sampleBuffer.isValid, let formatDescription = sampleBuffer.formatDescription,
      let dataBuffer = sampleBuffer.dataBuffer
    else { return }
    lock.withLock {
      if !sentFormat, let format = Self.format(from: formatDescription) {
        messageHandler(.format(format))
        sentFormat = true
      }
      guard sentFormat, let data = Self.data(from: dataBuffer) else { return }
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer,
        createIfNecessary: false
      ) as? [[CFString: Any]]
      let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
      messageHandler(
        .frame(
          DeskMuxScreenVideoFrame(
            data: data,
            isKeyFrame: !notSync,
            sequence: sequence
          )
        )
      )
      sequence &+= 1
    }
  }

  private static func format(from description: CMFormatDescription) -> DeskMuxScreenFormat? {
    var parameterSets: [Data] = []
    var parameterSetCount = 0
    var nalHeaderLength: Int32 = 0
    guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
      description,
      parameterSetIndex: 0,
      parameterSetPointerOut: nil,
      parameterSetSizeOut: nil,
      parameterSetCountOut: &parameterSetCount,
      nalUnitHeaderLengthOut: &nalHeaderLength
    ) == noErr, nalHeaderLength == 4 else { return nil }
    for index in 0..<parameterSetCount {
      var pointer: UnsafePointer<UInt8>?
      var size = 0
      guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        description,
        parameterSetIndex: index,
        parameterSetPointerOut: &pointer,
        parameterSetSizeOut: &size,
        parameterSetCountOut: nil,
        nalUnitHeaderLengthOut: nil
      ) == noErr, let pointer else { return nil }
      parameterSets.append(Data(bytes: pointer, count: size))
    }
    let dimensions = CMVideoFormatDescriptionGetDimensions(description)
    return DeskMuxScreenFormat(
      width: Int(dimensions.width),
      height: Int(dimensions.height),
      parameterSets: parameterSets
    )
  }

  private static func data(from blockBuffer: CMBlockBuffer) -> Data? {
    let length = CMBlockBufferGetDataLength(blockBuffer)
    var data = Data(count: length)
    let status = data.withUnsafeMutableBytes { bytes in
      CMBlockBufferCopyDataBytes(
        blockBuffer,
        atOffset: 0,
        dataLength: length,
        destination: bytes.baseAddress!
      )
    }
    return status == kCMBlockBufferNoErr ? data : nil
  }
}
