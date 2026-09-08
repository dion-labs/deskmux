import AppKit

@main
struct CheckMenuBarIcon {
  @MainActor static func main() {
    let image = DeskMuxBrand.menuBarMark
    precondition(image.isTemplate, "Menu-bar icon must adapt to light/dark appearance")
    precondition(image.size == NSSize(width: 20, height: 19))
    guard let data = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: data) else {
      fatalError("Menu-bar icon could not be rasterized")
    }
    var opaque = 0
    var transparent = 0
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
        if alpha > 0.5 { opaque += 1 } else { transparent += 1 }
      }
    }
    precondition(opaque > 50, "Menu-bar image is blank")
    precondition(transparent > 50, "Menu-bar silhouette has no transparent detail")
    print("PASS: template status image rasterizes with visible silhouette and transparent detail")
  }
}
