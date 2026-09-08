import AppKit
import CryptoKit
import DeskMuxCore
import Foundation

public enum DeskMuxAppUpdateError: Error, CustomStringConvertible {
  case notRunningFromAppBundle
  case archiveTooLarge(Int)
  case processFailed(String)
  case corruptArchive
  case invalidBundle
  case wrongBundleIdentifier(String?)
  case signatureInvalid
  case signerMismatch
  case downgrade(current: String, offered: String)
  case installLocationNotWritable
  case installFailed(String)

  public var description: String {
    switch self {
    case .notRunningFromAppBundle:
      return "DeskMux is not running from an application bundle"
    case .archiveTooLarge(let size):
      return "the update archive is too large (\(size) bytes)"
    case .processFailed(let message):
      return message
    case .corruptArchive:
      return "the update archive hash does not match"
    case .invalidBundle:
      return "the update does not contain a valid DeskMux.app bundle"
    case .wrongBundleIdentifier(let identifier):
      return "the update has the wrong bundle identifier: \(identifier ?? "missing")"
    case .signatureInvalid:
      return "the update's code signature is invalid"
    case .signerMismatch:
      return "the update is not signed by the same DeskMux development identity"
    case .downgrade(let current, let offered):
      return "build \(offered) is not newer than installed build \(current)"
    case .installLocationNotWritable:
      return "DeskMux cannot update its current Applications folder"
    case .installFailed(let message):
      return "install failed: \(message)"
    }
  }
}

public enum DeskMuxAppUpdatePackager {
  public static let maximumArchiveSize = 12 * 1_024 * 1_024

  public static func packageRunningApp() throws -> DeskMuxUpdatePackage {
    try packageApp(at: Bundle.main.bundleURL)
  }

  public static func packageApp(at appURL: URL) throws -> DeskMuxUpdatePackage {
    guard appURL.pathExtension == "app", let appBundle = Bundle(url: appURL) else {
      throw DeskMuxAppUpdateError.notRunningFromAppBundle
    }
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("deskmux-update-source-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let archiveURL = temporaryDirectory.appendingPathComponent("DeskMux.zip")
    try runProcess(
      executable: "/usr/bin/ditto",
      arguments: ["-c", "-k", "--keepParent", appURL.path, archiveURL.path]
    )
    let archive = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
    guard archive.count <= maximumArchiveSize else {
      throw DeskMuxAppUpdateError.archiveTooLarge(archive.count)
    }
    let info = appBundle.infoDictionary ?? [:]
    return DeskMuxUpdatePackage(
      version: info["CFBundleShortVersionString"] as? String ?? "0",
      build: info["CFBundleVersion"] as? String ?? "0",
      bundleIdentifier: appBundle.bundleIdentifier ?? "",
      archiveSHA256: sha256(archive),
      archiveData: archive
    )
  }
}

public struct DeskMuxAppUpdateReceipt: Codable, Equatable, Sendable {
  public let sourcePeerID: PeerID?
  public let previousBuild: String
  public let installedVersion: String
  public let installedBuild: String
  public let installedAt: Date

  public init(
    sourcePeerID: PeerID?,
    previousBuild: String,
    installedVersion: String,
    installedBuild: String,
    installedAt: Date
  ) {
    self.sourcePeerID = sourcePeerID
    self.previousBuild = previousBuild
    self.installedVersion = installedVersion
    self.installedBuild = installedBuild
    self.installedAt = installedAt
  }
}

struct DeskMuxInstallLayout: Equatable, Sendable {
  let currentAppURL: URL
  let applicationsDirectory: URL

  var installedAppURL: URL {
    applicationsDirectory.appendingPathComponent("DeskMux.app", isDirectory: true)
  }

  var canonicalBackupURL: URL {
    applicationsDirectory.appendingPathComponent(".DeskMux.previous", isDirectory: true)
  }

  var migratedBackupURL: URL {
    currentAppURL.deletingLastPathComponent()
      .appendingPathComponent(".DeskMux.migrated.previous", isDirectory: true)
  }

  var currentIsCanonical: Bool {
    currentAppURL.standardizedFileURL.path == installedAppURL.standardizedFileURL.path
  }
}

public enum DeskMuxAppUpdateInstaller {
  public static func verifyInstallAndScheduleRelaunch(
    _ package: DeskMuxUpdatePackage,
    sourcePeerID: PeerID? = nil
  ) -> DeskMuxUpdateResult {
    do {
      let currentAppURL = try runningDeskMuxAppURL()
      let installedBuild =
        Bundle(url: currentAppURL)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        ?? "0"
      let candidateURL = try verifyAndExtract(
        package,
        installedBuild: installedBuild,
        currentAppURL: currentAppURL
      )
      let installedURL = try install(candidateURL, currentAppURL: currentAppURL)
      try? saveReceipt(
        DeskMuxAppUpdateReceipt(
          sourcePeerID: sourcePeerID,
          previousBuild: installedBuild,
          installedVersion: package.version,
          installedBuild: package.build,
          installedAt: Date()
        ))
      try scheduleRelaunch(installedURL)
      return .accepted(build: package.build)
    } catch {
      return .rejected(reason: String(describing: error))
    }
  }

  public static func loadReceipt() -> DeskMuxAppUpdateReceipt? {
    guard let data = try? Data(contentsOf: receiptURL()) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(DeskMuxAppUpdateReceipt.self, from: data)
  }

  public static func dismissReceipt() {
    try? FileManager.default.removeItem(at: receiptURL())
  }

  private static func verifyAndExtract(
    _ package: DeskMuxUpdatePackage,
    installedBuild: String,
    currentAppURL: URL
  ) throws -> URL {
    guard package.archiveData.count <= DeskMuxAppUpdatePackager.maximumArchiveSize else {
      throw DeskMuxAppUpdateError.archiveTooLarge(package.archiveData.count)
    }
    guard sha256(package.archiveData) == package.archiveSHA256 else {
      throw DeskMuxAppUpdateError.corruptArchive
    }
    guard package.bundleIdentifier == "dev.deskmux.app" else {
      throw DeskMuxAppUpdateError.wrongBundleIdentifier(package.bundleIdentifier)
    }
    guard package.build.compare(installedBuild, options: .numeric) == .orderedDescending else {
      throw DeskMuxAppUpdateError.downgrade(current: installedBuild, offered: package.build)
    }

    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("deskmux-update-target-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    let archiveURL = temporaryDirectory.appendingPathComponent("DeskMux.zip")
    try package.archiveData.write(to: archiveURL, options: .atomic)
    let extractedURL = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)
    try FileManager.default.createDirectory(at: extractedURL, withIntermediateDirectories: true)
    try runProcess(
      executable: "/usr/bin/ditto",
      arguments: ["-x", "-k", archiveURL.path, extractedURL.path]
    )
    let candidateURL = extractedURL.appendingPathComponent("DeskMux.app", isDirectory: true)
    guard let candidateBundle = Bundle(url: candidateURL) else {
      throw DeskMuxAppUpdateError.invalidBundle
    }
    guard candidateBundle.bundleIdentifier == "dev.deskmux.app" else {
      throw DeskMuxAppUpdateError.wrongBundleIdentifier(candidateBundle.bundleIdentifier)
    }
    let candidateBuild = candidateBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    guard candidateBuild == package.build else { throw DeskMuxAppUpdateError.invalidBundle }

    do {
      try runProcess(
        executable: "/usr/bin/codesign",
        arguments: ["--verify", "--deep", "--strict", candidateURL.path]
      )
    } catch {
      throw DeskMuxAppUpdateError.signatureInvalid
    }
    let currentRequirement = try designatedRequirement(currentAppURL)
    let candidateRequirement = try designatedRequirement(candidateURL)
    guard currentRequirement == candidateRequirement else {
      throw DeskMuxAppUpdateError.signerMismatch
    }
    return candidateURL
  }

  private static func install(_ candidateURL: URL, currentAppURL: URL) throws -> URL {
    let fileManager = FileManager.default
    let applicationsDirectory =
      fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        "Applications",
        isDirectory: true
      )
    let layout = DeskMuxInstallLayout(
      currentAppURL: currentAppURL,
      applicationsDirectory: applicationsDirectory
    )
    do {
      try fileManager.createDirectory(
        at: applicationsDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      throw DeskMuxAppUpdateError.installLocationNotWritable
    }
    guard fileManager.isWritableFile(atPath: applicationsDirectory.path) else {
      throw DeskMuxAppUpdateError.installLocationNotWritable
    }

    if layout.currentIsCanonical {
      return try replaceCanonicalApp(
        candidateURL,
        layout: layout,
        fileManager: fileManager
      )
    }

    return try migrateToCanonicalLocation(
      candidateURL,
      layout: layout,
      fileManager: fileManager
    )
  }

  private static func replaceCanonicalApp(
    _ candidateURL: URL,
    layout: DeskMuxInstallLayout,
    fileManager: FileManager
  ) throws -> URL {
    do {
      if fileManager.fileExists(atPath: layout.canonicalBackupURL.path) {
        try fileManager.removeItem(at: layout.canonicalBackupURL)
      }
      try fileManager.moveItem(
        at: layout.currentAppURL,
        to: layout.canonicalBackupURL
      )
      do {
        try fileManager.moveItem(at: candidateURL, to: layout.installedAppURL)
      } catch {
        try? fileManager.moveItem(
          at: layout.canonicalBackupURL,
          to: layout.installedAppURL
        )
        throw error
      }
      return layout.installedAppURL
    } catch {
      throw DeskMuxAppUpdateError.installFailed(String(describing: error))
    }
  }

  private static func migrateToCanonicalLocation(
    _ candidateURL: URL,
    layout: DeskMuxInstallLayout,
    fileManager: FileManager
  ) throws -> URL {
    do {
      if fileManager.fileExists(atPath: layout.canonicalBackupURL.path) {
        try fileManager.removeItem(at: layout.canonicalBackupURL)
      }
      let hadCanonicalApp = fileManager.fileExists(atPath: layout.installedAppURL.path)
      if hadCanonicalApp {
        try fileManager.moveItem(
          at: layout.installedAppURL,
          to: layout.canonicalBackupURL
        )
      }

      do {
        try fileManager.moveItem(at: candidateURL, to: layout.installedAppURL)
      } catch {
        if hadCanonicalApp {
          try? fileManager.moveItem(
            at: layout.canonicalBackupURL,
            to: layout.installedAppURL
          )
        }
        throw error
      }

      // Keep the running bootstrap bundle available until the new canonical
      // copy has been installed. Its hidden, extensionless name prevents
      // Finder and Launch Services from presenting a second DeskMux app.
      if fileManager.isWritableFile(
        atPath: layout.currentAppURL.deletingLastPathComponent().path
      ) {
        if fileManager.fileExists(atPath: layout.migratedBackupURL.path) {
          try fileManager.removeItem(at: layout.migratedBackupURL)
        }
        do {
          try fileManager.moveItem(
            at: layout.currentAppURL,
            to: layout.migratedBackupURL
          )
        } catch {
          try? fileManager.removeItem(at: layout.installedAppURL)
          if hadCanonicalApp {
            try? fileManager.moveItem(
              at: layout.canonicalBackupURL,
              to: layout.installedAppURL
            )
          }
          throw error
        }
      }
      return layout.installedAppURL
    } catch {
      throw DeskMuxAppUpdateError.installFailed(String(describing: error))
    }
  }

  private static func scheduleRelaunch(_ installedURL: URL) throws {
    let helperURL = installedURL.appendingPathComponent(
      "Contents/Helpers/DeskMuxRelauncher", isDirectory: false)
    guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
      throw DeskMuxAppUpdateError.installFailed("the relaunch helper is missing")
    }
    let helper = Process()
    helper.executableURL = helperURL
    helper.arguments = [
      installedURL.path,
      String(ProcessInfo.processInfo.processIdentifier),
    ]
    try helper.run()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      NSApplication.shared.terminate(nil)
    }
  }

  static func enclosingDeskMuxAppURL(startingAt bundleURL: URL) -> URL? {
    var candidate = bundleURL.standardizedFileURL
    while candidate.pathComponents.count > 1 {
      if candidate.pathExtension == "app",
        Bundle(url: candidate)?.bundleIdentifier == "dev.deskmux.app"
      {
        return candidate
      }
      candidate.deleteLastPathComponent()
    }
    return nil
  }

  private static func runningDeskMuxAppURL() throws -> URL {
    guard let appURL = enclosingDeskMuxAppURL(startingAt: Bundle.main.bundleURL) else {
      throw DeskMuxAppUpdateError.notRunningFromAppBundle
    }
    return appURL
  }

  private static func saveReceipt(_ receipt: DeskMuxAppUpdateReceipt) throws {
    let url = receiptURL()
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(receipt).write(to: url, options: .atomic)
  }

  private static func receiptURL() -> URL {
    let applicationSupport =
      FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first ?? FileManager.default.homeDirectoryForCurrentUser
    return
      applicationSupport
      .appendingPathComponent("DeskMux", isDirectory: true)
      .appendingPathComponent("last-update.json", isDirectory: false)
  }
}

private func sha256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func designatedRequirement(_ appURL: URL) throws -> String {
  let process = Process()
  let output = Pipe()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
  process.arguments = ["-d", "-r", "-", appURL.path]
  process.standardOutput = output
  process.standardError = output
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw DeskMuxAppUpdateError.signatureInvalid
  }
  let text = String(
    decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  guard
    let requirement = text.split(separator: "\n").first(where: { $0.hasPrefix("designated =>") })
  else { throw DeskMuxAppUpdateError.signatureInvalid }
  return String(requirement)
}

private func runProcess(executable: String, arguments: [String]) throws {
  let process = Process()
  let errors = Pipe()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.standardOutput = errors
  process.standardError = errors
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    let message = String(
      decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    throw DeskMuxAppUpdateError.processFailed(
      "\(URL(fileURLWithPath: executable).lastPathComponent) failed: \(message)")
  }
}
