import AVFoundation
import CoreMedia
import DeskMuxScreenTransport
import Foundation
import SwiftUI

@MainActor
final class ScreenViewerModel: ObservableObject {
  @Published private(set) var state: DeskMuxScreenClientState = .idle
  @Published private(set) var frameCount = 0
  @Published private(set) var hasRemoteFocus = false

  let destinationName: String
  let renderer = ScreenVideoRenderer()

  private let localPeerID: String
  private let destinationPeerID: String
  private let sharedKey: String
  private var client: BonjourScreenStreamClient?

  init(localPeerID: String, destinationPeerID: String, sharedKey: String) {
    self.localPeerID = localPeerID
    self.destinationPeerID = destinationPeerID
    self.sharedKey = sharedKey
    destinationName = destinationPeerID == "studio" ? "Studio" : "MacBook"
  }

  var isStreaming: Bool {
    if case .streaming = state { return true }
    return false
  }

  var statusText: String {
    switch state {
    case .idle: return "Ready to open \(destinationName)'s virtual display"
    case .discovering: return "Finding \(destinationName)…"
    case .connecting: return "Starting \(destinationName)'s virtual display…"
    case .streaming: return "Live from \(destinationName) · \(frameCount) frames"
    case .failed(let reason): return reason
    case .stopped: return "Screen stream stopped"
    }
  }

  func connect() {
    disconnect(publishStopped: false)
    renderer.reset()
    frameCount = 0
    let client = BonjourScreenStreamClient(
      localPeerID: localPeerID,
      destinationPeerID: destinationPeerID,
      sharedKey: sharedKey,
      stateHandler: { [weak self] state in
        Task { @MainActor [weak self] in self?.state = state }
      },
      messageHandler: { [weak self] message in
        Task { @MainActor [weak self] in self?.handle(message) }
      }
    )
    self.client = client
    client.start()
  }

  func disconnect() { disconnect(publishStopped: true) }

  func sendInput(_ event: DeskMuxScreenInputEvent) {
    guard isStreaming else { return }
    client?.sendInput(event)
  }

  func setRemoteFocus(_ focused: Bool) {
    hasRemoteFocus = focused
  }

  private func disconnect(publishStopped: Bool) {
    client?.stop()
    client = nil
    if publishStopped { state = .stopped }
  }

  private func handle(_ message: DeskMuxScreenWireMessage) {
    switch message {
    case .format(let format):
      renderer.configure(format)
    case .frame(let frame):
      renderer.enqueue(frame)
      frameCount += 1
    case .failure(let reason):
      state = .failed(reason)
    default:
      break
    }
  }
}

@MainActor
final class ScreenVideoRenderer {
  weak var view: ScreenVideoNSView?
  private var formatDescription: CMVideoFormatDescription?
  private var videoSize = CGSize(width: 16, height: 10)

  func attach(_ view: ScreenVideoNSView) {
    self.view = view
    view.videoSize = videoSize
    view.displayLayer.flushAndRemoveImage()
  }

  func reset() {
    formatDescription = nil
    view?.displayLayer.flushAndRemoveImage()
  }

  func configure(_ format: DeskMuxScreenFormat) {
    videoSize = CGSize(width: format.width, height: format.height)
    view?.videoSize = videoSize
    let storage = format.parameterSets.map { $0 as NSData }
    let pointers = storage.map { $0.bytes.assumingMemoryBound(to: UInt8.self) }
    let sizes = storage.map(\.length)
    var description: CMFormatDescription?
    let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
      allocator: kCFAllocatorDefault,
      parameterSetCount: pointers.count,
      parameterSetPointers: pointers,
      parameterSetSizes: sizes,
      nalUnitHeaderLength: 4,
      formatDescriptionOut: &description
    )
    guard status == noErr, let description else { return }
    formatDescription = description
    view?.displayLayer.flushAndRemoveImage()
  }

  func enqueue(_ frame: DeskMuxScreenVideoFrame) {
    guard let formatDescription,
      let sampleBuffer = Self.makeSampleBuffer(
        data: frame.data,
        formatDescription: formatDescription
      ),
      let layer = view?.displayLayer
    else { return }
    if layer.status == .failed { layer.flush() }
    layer.enqueue(sampleBuffer)
  }

  private static func makeSampleBuffer(
    data: Data,
    formatDescription: CMVideoFormatDescription
  ) -> CMSampleBuffer? {
    var blockBuffer: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault,
      memoryBlock: nil,
      blockLength: data.count,
      blockAllocator: kCFAllocatorDefault,
      customBlockSource: nil,
      offsetToData: 0,
      dataLength: data.count,
      flags: 0,
      blockBufferOut: &blockBuffer
    ) == kCMBlockBufferNoErr, let blockBuffer else { return nil }
    let copyStatus = data.withUnsafeBytes { bytes in
      CMBlockBufferReplaceDataBytes(
        with: bytes.baseAddress!,
        blockBuffer: blockBuffer,
        offsetIntoDestination: 0,
        dataLength: data.count
      )
    }
    guard copyStatus == kCMBlockBufferNoErr else { return nil }
    var sampleSize = data.count
    var sampleBuffer: CMSampleBuffer?
    guard CMSampleBufferCreateReady(
      allocator: kCFAllocatorDefault,
      dataBuffer: blockBuffer,
      formatDescription: formatDescription,
      sampleCount: 1,
      sampleTimingEntryCount: 0,
      sampleTimingArray: nil,
      sampleSizeEntryCount: 1,
      sampleSizeArray: &sampleSize,
      sampleBufferOut: &sampleBuffer
    ) == noErr, let sampleBuffer else { return nil }
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(
      sampleBuffer,
      createIfNecessary: true
    ),
      let first = (attachments as NSArray).firstObject as? NSMutableDictionary
    {
      first[kCMSampleAttachmentKey_DisplayImmediately] = true
    }
    return sampleBuffer
  }
}

final class ScreenVideoNSView: NSView {
  let displayLayer = AVSampleBufferDisplayLayer()
  var videoSize = CGSize(width: 16, height: 10)
  var inputHandler: ((DeskMuxScreenInputEvent) -> Void)?
  var focusHandler: ((Bool) -> Void)?
  private var trackingAreaReference: NSTrackingArea?

  override var acceptsFirstResponder: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer = CALayer()
    layer?.backgroundColor = NSColor.black.cgColor
    displayLayer.videoGravity = .resizeAspect
    layer?.addSublayer(displayLayer)
  }

  required init?(coder: NSCoder) { nil }

  override func layout() {
    super.layout()
    displayLayer.frame = bounds
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
      owner: self
    )
    addTrackingArea(area)
    trackingAreaReference = area
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func becomeFirstResponder() -> Bool {
    focusHandler?(true)
    return true
  }

  override func resignFirstResponder() -> Bool {
    inputHandler?(.releaseAll)
    focusHandler?(false)
    return true
  }

  override func mouseMoved(with event: NSEvent) { sendPointer(event) }
  override func mouseExited(with event: NSEvent) {
    window?.makeFirstResponder(nil)
  }
  override func mouseDragged(with event: NSEvent) { sendPointer(event, draggingButton: 0) }
  override func rightMouseDragged(with event: NSEvent) { sendPointer(event, draggingButton: 1) }
  override func otherMouseDragged(with event: NSEvent) {
    sendPointer(event, draggingButton: Int(event.buttonNumber))
  }

  override func mouseDown(with event: NSEvent) { sendButton(event, button: 0, down: true) }
  override func mouseUp(with event: NSEvent) { sendButton(event, button: 0, down: false) }
  override func rightMouseDown(with event: NSEvent) { sendButton(event, button: 1, down: true) }
  override func rightMouseUp(with event: NSEvent) { sendButton(event, button: 1, down: false) }
  override func otherMouseDown(with event: NSEvent) {
    sendButton(event, button: Int(event.buttonNumber), down: true)
  }
  override func otherMouseUp(with event: NSEvent) {
    sendButton(event, button: Int(event.buttonNumber), down: false)
  }

  override func scrollWheel(with event: NSEvent) {
    guard let point = normalizedPoint(event) else { return }
    inputHandler?(
      .scroll(
        x: point.x,
        y: point.y,
        deltaX: event.scrollingDeltaX,
        deltaY: event.scrollingDeltaY
      )
    )
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      window?.makeFirstResponder(nil)
      return
    }
    inputHandler?(
      .key(
        keyCode: event.keyCode,
        isDown: true,
        flags: UInt64(event.modifierFlags.rawValue)
      )
    )
  }

  override func keyUp(with event: NSEvent) {
    inputHandler?(
      .key(
        keyCode: event.keyCode,
        isDown: false,
        flags: UInt64(event.modifierFlags.rawValue)
      )
    )
  }

  override func flagsChanged(with event: NSEvent) {
    inputHandler?(
      .flagsChanged(
        keyCode: event.keyCode,
        isDown: Self.modifierIsDown(event),
        flags: UInt64(event.modifierFlags.rawValue)
      )
    )
  }

  private func sendPointer(_ event: NSEvent, draggingButton: Int? = nil) {
    guard let point = normalizedPoint(event) else { return }
    inputHandler?(.pointerMove(x: point.x, y: point.y, draggingButton: draggingButton))
  }

  private func sendButton(_ event: NSEvent, button: Int, down: Bool) {
    guard let point = normalizedPoint(event) else { return }
    window?.makeFirstResponder(self)
    inputHandler?(
      .mouseButton(
        x: point.x,
        y: point.y,
        button: button,
        isDown: down,
        clickCount: event.clickCount
      )
    )
  }

  private func normalizedPoint(_ event: NSEvent) -> (x: Double, y: Double)? {
    let point = convert(event.locationInWindow, from: nil)
    guard bounds.width > 0, bounds.height > 0, videoSize.width > 0, videoSize.height > 0
    else { return nil }
    let scale = min(bounds.width / videoSize.width, bounds.height / videoSize.height)
    let renderedSize = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
    let renderedRect = CGRect(
      x: bounds.midX - renderedSize.width / 2,
      y: bounds.midY - renderedSize.height / 2,
      width: renderedSize.width,
      height: renderedSize.height
    )
    guard renderedRect.contains(point) else { return nil }
    return (
      min(max((point.x - renderedRect.minX) / renderedRect.width, 0), 1),
      min(max((renderedRect.maxY - point.y) / renderedRect.height, 0), 1)
    )
  }

  private static func modifierIsDown(_ event: NSEvent) -> Bool {
    switch event.keyCode {
    case 54, 55: return event.modifierFlags.contains(.command)
    case 56, 60: return event.modifierFlags.contains(.shift)
    case 58, 61: return event.modifierFlags.contains(.option)
    case 59, 62: return event.modifierFlags.contains(.control)
    case 57: return event.modifierFlags.contains(.capsLock)
    default: return false
    }
  }
}

struct ScreenVideoSurface: NSViewRepresentable {
  let renderer: ScreenVideoRenderer
  let inputHandler: (DeskMuxScreenInputEvent) -> Void
  let focusHandler: (Bool) -> Void

  func makeNSView(context: Context) -> ScreenVideoNSView {
    let view = ScreenVideoNSView()
    view.inputHandler = inputHandler
    view.focusHandler = focusHandler
    renderer.attach(view)
    return view
  }

  func updateNSView(_ nsView: ScreenVideoNSView, context: Context) {
    nsView.inputHandler = inputHandler
    nsView.focusHandler = focusHandler
    if renderer.view !== nsView { renderer.attach(nsView) }
  }
}

struct DeskMuxScreenViewerWindow: View {
  @ObservedObject var model: ScreenViewerModel

  var body: some View {
    ZStack(alignment: .topLeading) {
      Color.black
      ScreenVideoSurface(
        renderer: model.renderer,
        inputHandler: { model.sendInput($0) },
        focusHandler: { model.setRemoteFocus($0) }
      )
      if !model.isStreaming {
        VStack(spacing: 12) {
          if case .failed = model.state {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.largeTitle)
              .foregroundStyle(.orange)
          } else {
            ProgressView().controlSize(.large)
          }
          Text(model.statusText)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .frame(maxWidth: 440)
          if case .failed = model.state {
            Button("Retry") { model.connect() }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Text(model.statusText)
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(10)
        .opacity(model.isStreaming ? 1 : 0)
      if model.isStreaming && model.hasRemoteFocus {
        RoundedRectangle(cornerRadius: 4)
          .stroke(.blue, lineWidth: 3)
          .allowsHitTesting(false)
        Text("Keyboard → \(model.destinationName)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(.blue, in: Capsule())
          .frame(maxWidth: .infinity, alignment: .topTrailing)
          .padding(10)
          .allowsHitTesting(false)
      }
    }
    .frame(minWidth: 640, minHeight: 400)
    .onAppear { model.connect() }
    .onDisappear { model.disconnect() }
  }
}
