// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "DeskMux",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "DeskMuxCore", targets: ["DeskMuxCore"]),
    .library(name: "DeskMuxMacInput", targets: ["DeskMuxMacInput"]),
    .library(name: "DeskMuxInputTransport", targets: ["DeskMuxInputTransport"]),
    .library(name: "DeskMuxAgentIPC", targets: ["DeskMuxAgentIPC"]),
    .library(name: "DeskMuxVirtualDisplay", targets: ["DeskMuxVirtualDisplay"]),
    .library(name: "DeskMuxScreenTransport", targets: ["DeskMuxScreenTransport"]),
    .executable(name: "DeskMux", targets: ["DeskMuxMenuBar"]),
    .executable(name: "DeskMuxRelauncher", targets: ["DeskMuxRelauncher"]),
    .executable(name: "DeskMuxService", targets: ["DeskMuxService"]),
    .executable(name: "deskmux-agent", targets: ["DeskMuxAgent"]),
    .executable(name: "deskmux-diagnostics", targets: ["DeskMuxDiagnostics"]),
    .executable(name: "deskmux-control", targets: ["DeskMuxControl"]),
    .executable(name: "deskmux-virtual-display-probe", targets: ["DeskMuxVirtualDisplayProbe"]),
    .executable(name: "deskmux-screen-loopback-probe", targets: ["DeskMuxScreenLoopbackProbe"]),
  ],
  targets: [
    .target(
      name: "DeskMuxCore",
      path: "Sources/DeskMuxCore"
    ),
    .target(
      name: "DeskMuxMacInput",
      dependencies: ["DeskMuxCore"],
      path: "Sources/DeskMuxMacInput"
    ),
    .target(
      name: "DeskMuxInputTransport",
      dependencies: ["DeskMuxCore", "DeskMuxMacInput"],
      path: "Sources/DeskMuxInputTransport"
    ),
    .target(
      name: "DeskMuxAgentIPC",
      path: "Sources/DeskMuxAgentIPC"
    ),
    .target(
      name: "CVirtualDisplayBridge",
      path: "Sources/CVirtualDisplayBridge",
      publicHeadersPath: "include",
      cSettings: [.unsafeFlags(["-fobjc-arc"])],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("CoreGraphics"),
      ]
    ),
    .target(
      name: "DeskMuxVirtualDisplay",
      dependencies: ["CVirtualDisplayBridge"],
      path: "Sources/DeskMuxVirtualDisplay"
    ),
    .target(
      name: "DeskMuxScreenTransport",
      dependencies: ["DeskMuxVirtualDisplay"],
      path: "Sources/DeskMuxScreenTransport"
    ),
    .executableTarget(
      name: "DeskMuxAgent",
      dependencies: ["DeskMuxCore", "DeskMuxMacInput", "DeskMuxInputTransport"],
      path: "Sources/DeskMuxAgent"
    ),
    .executableTarget(
      name: "DeskMuxMenuBar",
      dependencies: [
        "DeskMuxCore", "DeskMuxMacInput", "DeskMuxInputTransport", "DeskMuxAgentIPC",
        "DeskMuxScreenTransport",
      ],
      path: "Sources/DeskMuxMenuBar"
    ),
    .executableTarget(
      name: "DeskMuxDiagnostics",
      dependencies: ["DeskMuxAgentIPC"],
      path: "Sources/DeskMuxDiagnostics"
    ),
    .executableTarget(
      name: "DeskMuxControl",
      dependencies: ["DeskMuxAgentIPC"],
      path: "Sources/DeskMuxControl"
    ),
    .executableTarget(
      name: "DeskMuxVirtualDisplayProbe",
      dependencies: ["DeskMuxVirtualDisplay"],
      path: "Sources/DeskMuxVirtualDisplayProbe"
    ),
    .executableTarget(
      name: "DeskMuxScreenLoopbackProbe",
      dependencies: ["DeskMuxScreenTransport"],
      path: "Sources/DeskMuxScreenLoopbackProbe"
    ),
    .executableTarget(
      name: "DeskMuxRelauncher",
      path: "Sources/DeskMuxRelauncher"
    ),
    .executableTarget(
      name: "DeskMuxService",
      dependencies: [
        "DeskMuxAgentIPC", "DeskMuxCore", "DeskMuxInputTransport", "DeskMuxMacInput",
        "DeskMuxScreenTransport",
      ],
      path: "Sources/DeskMuxService"
    ),
    .testTarget(
      name: "DeskMuxCoreTests",
      dependencies: ["DeskMuxCore"],
      path: "Tests/DeskMuxCoreTests"
    ),
    .testTarget(
      name: "DeskMuxAgentTests",
      dependencies: ["DeskMuxAgent", "DeskMuxAgentIPC", "DeskMuxInputTransport"],
      path: "Tests/DeskMuxAgentTests"
    ),
    .testTarget(
      name: "DeskMuxMacInputTests",
      dependencies: ["DeskMuxMacInput"],
      path: "Tests/DeskMuxMacInputTests"
    ),
    .testTarget(
      name: "DeskMuxMenuBarTests",
      dependencies: ["DeskMuxMenuBar"],
      path: "Tests/DeskMuxMenuBarTests"
    ),
    .testTarget(
      name: "DeskMuxDiagnosticsTests",
      dependencies: ["DeskMuxDiagnostics"],
      path: "Tests/DeskMuxDiagnosticsTests"
    ),
    .testTarget(
      name: "DeskMuxVirtualDisplayTests",
      dependencies: ["DeskMuxVirtualDisplay", "DeskMuxScreenTransport"],
      path: "Tests/DeskMuxVirtualDisplayTests"
    ),
  ]
)
