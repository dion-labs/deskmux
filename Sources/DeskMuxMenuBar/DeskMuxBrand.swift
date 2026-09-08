import SwiftUI

enum DeskMuxBrand {
  // MenuBarExtra extracts an NSImage for its status item. A bare SwiftUI Shape
  // can render inside windows but leave that status-item image empty.
  static let menuBarMark: NSImage = {
    let size = NSSize(width: 20, height: 19)
    let image = NSImage(size: size, flipped: true) { rect in
      guard let context = NSGraphicsContext.current?.cgContext else { return false }
      context.setFillColor(NSColor.black.cgColor)
      context.addPath(MuxMark().path(in: rect).cgPath)
      context.drawPath(using: .eoFill)
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "DeskMux"
    return image
  }()

  static let teal = Color(red: 0.17, green: 0.48, blue: 0.46)
  // Foreground accents need a separate, appearance-aware color from filled
  // surfaces: the dark brand teal is intentionally retained behind white text.
  static let accent = Color(nsColor: NSColor(name: "DeskMuxAccent") { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor(srgbRed: 0.54, green: 0.88, blue: 0.81, alpha: 1)
      : NSColor(srgbRed: 0.08, green: 0.36, blue: 0.33, alpha: 1)
  })
  static let coral = Color(red: 0.90, green: 0.42, blue: 0.28)
}

/// Mux's ear silhouette forms an M; the two eyes echo the paired Macs.
struct MuxMark: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let points: [CGPoint] = [
      .init(x: 0.10, y: 0.08), .init(x: 0.35, y: 0.30),
      .init(x: 0.65, y: 0.30), .init(x: 0.90, y: 0.08),
      .init(x: 0.93, y: 0.64), .init(x: 0.70, y: 0.89),
      .init(x: 0.50, y: 0.98), .init(x: 0.30, y: 0.89),
      .init(x: 0.07, y: 0.64),
    ]
    path.addLines(points.map { .init(x: rect.minX + $0.x * rect.width,
                                    y: rect.minY + $0.y * rect.height) })
    path.closeSubpath()
    for x in [0.25, 0.60] {
      path.addRoundedRect(in: CGRect(x: rect.minX + x * rect.width,
        y: rect.minY + 0.52 * rect.height, width: rect.width * 0.15,
        height: rect.height * 0.10), cornerSize: CGSize(width: 1, height: 1))
    }
    return path
  }
}

struct DeskMuxBrandHeader: View {
  var body: some View {
    HStack(spacing: 12) {
      MuxMark().fill(DeskMuxBrand.accent, style: FillStyle(eoFill: true))
        .frame(width: 33, height: 33)
        .padding(10)
        .background(DeskMuxBrand.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
      VStack(alignment: .leading, spacing: 3) {
        Text("DeskMux").font(.system(size: 22, weight: .semibold, design: .rounded))
        Text("Two Macs. One flow.").font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      Link("DION LABS ↗", destination: URL(string: "https://deskmux.dionlabs.ai")!)
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(DeskMuxBrand.accent)
    }
  }
}
