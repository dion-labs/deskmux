import CryptoKit
import DeskMuxCore
import Foundation
import Testing

@testable import DeskMuxInputTransport

@Test func installerRejectedArchiveRemovesOwnedStaging() throws {
  let fixture = try InstallerFixture()
  defer { fixture.remove() }
  let package = fixture.package(Data("synthetic invalid zip".utf8))
  let result = fixture.install(package)
  guard case .rejected = result else {
    Issue.record("Invalid archive was accepted")
    return
  }
  #expect(fixture.relaunches.isEmpty)
  #expect(try Data(contentsOf: fixture.current.appendingPathComponent("Contents/Resources/marker")) == Data("old".utf8))
  #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.staging.path).isEmpty)
  #expect(!FileManager.default.fileExists(atPath: fixture.receipt.path))
}

private final class InstallerFixture {
  let root: URL
  let applications: URL
  let staging: URL
  let current: URL
  let receipt: URL
  var relaunches: [URL] = []

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("deskmux-installer-fixture-\(UUID())")
    applications = root.appendingPathComponent("Applications")
    staging = root.appendingPathComponent("staging")
    current = applications.appendingPathComponent("DeskMux.app")
    receipt = root.appendingPathComponent("receipt/last-update.json")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: current.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": "dev.deskmux.app", "CFBundleVersion": "1", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: current.appendingPathComponent("Contents/Info.plist"))
    try Data("old".utf8).write(to: current.appendingPathComponent("Contents/Resources/marker"))
  }

  func package(_ bytes: Data) -> DeskMuxUpdatePackage {
    DeskMuxUpdatePackage(version: "test", build: "2", bundleIdentifier: "dev.deskmux.app",
      archiveSHA256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), archiveData: bytes)
  }

  func install(_ package: DeskMuxUpdatePackage) -> DeskMuxUpdateResult {
    DeskMuxAppUpdateInstaller.verifyInstall(package, currentAppURL: current,
      applicationsDirectory: applications, stagingParent: staging, receiptURL: receipt,
      relaunch: { self.relaunches.append($0) })
  }

  func remove() { try? FileManager.default.removeItem(at: root) }
}

@Test func installerSignedCanonicalUpdatePreservesBackupAndWritesReceipt() throws {
  let fixture = try InstallerFixture()
  defer { fixture.remove() }
  try fixture.sign(fixture.current)
  let candidate = try fixture.candidate()
  let result = fixture.install(try DeskMuxAppUpdatePackager.packageApp(at: candidate))
  #expect(result == .accepted(build: "2"))
  #expect(fixture.relaunches.map { $0.standardizedFileURL.path } == [fixture.current.standardizedFileURL.path])
  #expect(try Data(contentsOf: fixture.current.appendingPathComponent("Contents/Resources/marker")) == Data("new".utf8))
  #expect(try Data(contentsOf: fixture.applications.appendingPathComponent(".DeskMux.previous/Contents/Resources/marker")) == Data("old".utf8))
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  let receipt = try decoder.decode(DeskMuxAppUpdateReceipt.self, from: Data(contentsOf: fixture.receipt))
  #expect(receipt.previousBuild == "1")
  #expect(receipt.installedBuild == "2")
  #expect(receipt.installedVersion == "test")
  #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.staging.path).isEmpty)
}

@Test func installerWrongDesignatedRequirementPreservesCurrentBundle() throws {
  let fixture = try InstallerFixture()
  defer { fixture.remove() }
  try fixture.sign(fixture.current)
  let candidate = try fixture.candidate(signingIdentifier: "dev.deskmux.other")
  let result = fixture.install(try DeskMuxAppUpdatePackager.packageApp(at: candidate))
  #expect(result == .rejected(reason: DeskMuxAppUpdateError.signerMismatch.description))
  #expect(fixture.relaunches.isEmpty)
  #expect(try Data(contentsOf: fixture.current.appendingPathComponent("Contents/Resources/marker")) == Data("old".utf8))
  #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.staging.path).isEmpty)
  #expect(!FileManager.default.fileExists(atPath: fixture.receipt.path))
}

extension InstallerFixture {
  func candidate(signingIdentifier: String = "dev.deskmux.app") throws -> URL {
    let url = root.appendingPathComponent("source/DeskMux.app")
    try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": "dev.deskmux.app", "CFBundleVersion": "2", "CFBundleShortVersionString": "test", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: url.appendingPathComponent("Contents/Info.plist"))
    try Data("new".utf8).write(to: url.appendingPathComponent("Contents/Resources/marker"))
    try sign(url, signingIdentifier: signingIdentifier)
    return url
  }

  func sign(_ url: URL, signingIdentifier: String = "dev.deskmux.app") throws {
    // This disposable shell executable is signed for verification, never launched.
    let executable = url.appendingPathComponent("Contents/MacOS/Fixture")
    try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let infoURL = url.appendingPathComponent("Contents/Info.plist")
    var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as! [String: Any]
    info["CFBundleExecutable"] = "Fixture"
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = ["--force", "--sign", "-", "--identifier", signingIdentifier, "--requirements", "=designated => identifier \(signingIdentifier)", url.path]
    process.environment = ["PATH": "/usr/bin:/bin", "LANG": "C"]
    try process.run()
    process.waitUntilExit()
    try #require(process.terminationStatus == 0)
  }
}

@Test func installerRelaunchFailureReportsRejectionAfterReplacement() throws {
  let fixture = try InstallerFixture()
  defer { fixture.remove() }
  try fixture.sign(fixture.current)
  let candidate = try fixture.candidate()
  let package = try DeskMuxAppUpdatePackager.packageApp(at: candidate)
  let result = DeskMuxAppUpdateInstaller.verifyInstall(package, currentAppURL: fixture.current,
    applicationsDirectory: fixture.applications, stagingParent: fixture.staging,
    receiptURL: fixture.receipt, relaunch: { _ in throw DeskMuxAppUpdateError.installFailed("synthetic relaunch failure") })
  #expect(result == .rejected(reason: DeskMuxAppUpdateError.installFailed("synthetic relaunch failure").description))
  #expect(try Data(contentsOf: fixture.current.appendingPathComponent("Contents/Resources/marker")) == Data("new".utf8))
  #expect(try Data(contentsOf: fixture.applications.appendingPathComponent(".DeskMux.previous/Contents/Resources/marker")) == Data("old".utf8))
  #expect(FileManager.default.fileExists(atPath: fixture.receipt.path))
  #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.staging.path).isEmpty)
}

@Test func installerReceiptFailureRemainsBestEffort() throws {
  let fixture = try InstallerFixture()
  defer { fixture.remove() }
  try fixture.sign(fixture.current)
  let candidate = try fixture.candidate()
  let package = try DeskMuxAppUpdatePackager.packageApp(at: candidate)
  let blocker = fixture.root.appendingPathComponent("blocked-receipt")
  try Data("sentinel".utf8).write(to: blocker)
  let result = DeskMuxAppUpdateInstaller.verifyInstall(package, currentAppURL: fixture.current,
    applicationsDirectory: fixture.applications, stagingParent: fixture.staging,
    receiptURL: blocker.appendingPathComponent("receipt.json"), relaunch: { fixture.relaunches.append($0) })
  #expect(result == .accepted(build: "2"))
  #expect(fixture.relaunches.map { $0.standardizedFileURL.path } == [fixture.current.standardizedFileURL.path])
  #expect(try Data(contentsOf: fixture.current.appendingPathComponent("Contents/Resources/marker")) == Data("new".utf8))
  #expect(try Data(contentsOf: blocker) == Data("sentinel".utf8))
  #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.staging.path).isEmpty)
}

@Test(arguments: ["hash", "identifier", "older", "large"])
func installerRejectsEnvelopeBeforeExtraction(_ failure: String) throws {
  let fixture = try InstallerFixture()
  defer { fixture.remove() }
  let bytes = failure == "large" ? Data(repeating: 0, count: DeskMuxAppUpdatePackager.maximumArchiveSize + 1) : Data("synthetic".utf8)
  let valid = fixture.package(bytes)
  let package = DeskMuxUpdatePackage(version: valid.version,
    build: failure == "older" ? "1" : valid.build,
    bundleIdentifier: failure == "identifier" ? "dev.synthetic.other" : valid.bundleIdentifier,
    archiveSHA256: failure == "hash" ? "bad" : valid.archiveSHA256, archiveData: bytes)
  let expected: DeskMuxAppUpdateError
  switch failure {
  case "hash": expected = .corruptArchive
  case "identifier": expected = .wrongBundleIdentifier("dev.synthetic.other")
  case "older": expected = .downgrade(current: "1", offered: "1")
  default: expected = .archiveTooLarge(bytes.count)
  }
  #expect(fixture.install(package) == .rejected(reason: expected.description))
  #expect(fixture.relaunches.isEmpty)
  #expect(try Data(contentsOf: fixture.current.appendingPathComponent("Contents/Resources/marker")) == Data("old".utf8))
  #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.staging.path).isEmpty)
}

@Test func installerTamperedSignaturePreservesCurrentBundle() throws {
  let fixture = try InstallerFixture()
  defer { fixture.remove() }
  try fixture.sign(fixture.current)
  let candidate = try fixture.candidate()
  try Data("tampered".utf8).write(to: candidate.appendingPathComponent("Contents/Resources/marker"))
  let result = fixture.install(try DeskMuxAppUpdatePackager.packageApp(at: candidate))
  #expect(result == .rejected(reason: DeskMuxAppUpdateError.signatureInvalid.description))
  #expect(fixture.relaunches.isEmpty)
  #expect(try Data(contentsOf: fixture.current.appendingPathComponent("Contents/Resources/marker")) == Data("old".utf8))
  #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.staging.path).isEmpty)
}

@Test func installerMigratesDisposableBootstrapToCanonicalPath() throws {
  let fixture = try InstallerFixture()
  defer { fixture.remove() }
  try fixture.sign(fixture.current)
  let bootstrap = fixture.root.appendingPathComponent("Downloads/DeskMux.app")
  try FileManager.default.createDirectory(at: bootstrap.deletingLastPathComponent(), withIntermediateDirectories: true)
  try FileManager.default.moveItem(at: fixture.current, to: bootstrap)
  let candidate = try fixture.candidate()
  let result = DeskMuxAppUpdateInstaller.verifyInstall(try DeskMuxAppUpdatePackager.packageApp(at: candidate),
    currentAppURL: bootstrap, applicationsDirectory: fixture.applications,
    stagingParent: fixture.staging, receiptURL: fixture.receipt, relaunch: { fixture.relaunches.append($0) })
  #expect(result == .accepted(build: "2"))
  #expect(fixture.relaunches.map { $0.standardizedFileURL.path } == [fixture.current.standardizedFileURL.path])
  #expect(!FileManager.default.fileExists(atPath: bootstrap.path))
  #expect(try Data(contentsOf: bootstrap.deletingLastPathComponent().appendingPathComponent(".DeskMux.migrated.previous/Contents/Resources/marker")) == Data("old".utf8))
  #expect(try Data(contentsOf: fixture.current.appendingPathComponent("Contents/Resources/marker")) == Data("new".utf8))
  #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.staging.path).isEmpty)
}

@Test(arguments: ["identifier", "build", "missing"])
func installerRejectsExtractedBundleMismatch(_ failure: String) throws {
  let fixture = try InstallerFixture()
  defer { fixture.remove() }
  try fixture.sign(fixture.current)
  var candidate = try fixture.candidate()
  if failure == "missing" {
    let renamed = candidate.deletingLastPathComponent().appendingPathComponent("Other.app")
    try FileManager.default.moveItem(at: candidate, to: renamed)
    candidate = renamed
  } else {
    let infoURL = candidate.appendingPathComponent("Contents/Info.plist")
    var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as! [String: Any]
    if failure == "identifier" { info["CFBundleIdentifier"] = "dev.synthetic.other" }
    else { info["CFBundleVersion"] = "3" }
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)
    try fixture.sign(candidate)
  }
  let archive = try DeskMuxAppUpdatePackager.packageApp(at: candidate)
  let package = DeskMuxUpdatePackage(version: "test", build: "2", bundleIdentifier: "dev.deskmux.app",
    archiveSHA256: archive.archiveSHA256, archiveData: archive.archiveData)
  let expected: DeskMuxAppUpdateError = failure == "identifier" ? .wrongBundleIdentifier("dev.synthetic.other") : .invalidBundle
  #expect(fixture.install(package) == .rejected(reason: expected.description))
  #expect(fixture.relaunches.isEmpty)
  #expect(try Data(contentsOf: fixture.current.appendingPathComponent("Contents/Resources/marker")) == Data("old".utf8))
  #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.staging.path).isEmpty)
  #expect(!FileManager.default.fileExists(atPath: fixture.receipt.path))
}

@Test(arguments: [true, false])
func installerMigrationRetirementFailureRestoresCanonicalBundle(hasCanonical: Bool) throws {
  let fixture = try InstallerFixture()
  let bootstrap = fixture.root.appendingPathComponent("Downloads/DeskMux.app")
  let migratedBackup = bootstrap.deletingLastPathComponent()
    .appendingPathComponent(".DeskMux.migrated.previous")
  let protected = migratedBackup.appendingPathComponent("protected")
  defer {
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: protected.path)
    fixture.remove()
  }
  try fixture.sign(fixture.current)
  try FileManager.default.createDirectory(at: bootstrap.deletingLastPathComponent(), withIntermediateDirectories: true)
  try FileManager.default.moveItem(at: fixture.current, to: bootstrap)
  if hasCanonical {
    try FileManager.default.copyItem(at: bootstrap, to: fixture.current)
  }
  try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
  let sentinel = protected.appendingPathComponent("sentinel")
  try Data("previous migration backup".utf8).write(to: sentinel)
  try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: protected.path)
  try #require(!FileManager.default.isReadableFile(atPath: protected.path))
  let candidate = try fixture.candidate()
  let result = DeskMuxAppUpdateInstaller.verifyInstall(try DeskMuxAppUpdatePackager.packageApp(at: candidate),
    currentAppURL: bootstrap, applicationsDirectory: fixture.applications,
    stagingParent: fixture.staging, receiptURL: fixture.receipt, relaunch: { fixture.relaunches.append($0) })
  guard case .rejected(let reason) = result else {
    Issue.record("Backup-retirement failure was not rejected")
    return
  }
  #expect(reason.contains(".DeskMux.migrated.previous"))
  #expect(fixture.relaunches.isEmpty)
  #expect(!FileManager.default.fileExists(atPath: fixture.receipt.path))
  #expect(try Data(contentsOf: bootstrap.appendingPathComponent("Contents/Resources/marker")) == Data("old".utf8))
  if hasCanonical {
    #expect(try Data(contentsOf: fixture.current.appendingPathComponent("Contents/Resources/marker")) == Data("old".utf8))
  } else {
    #expect(!FileManager.default.fileExists(atPath: fixture.current.path))
  }
  #expect(!FileManager.default.fileExists(atPath: fixture.applications.appendingPathComponent(".DeskMux.previous").path))
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: protected.path)
  #expect(try Data(contentsOf: sentinel) == Data("previous migration backup".utf8))
  #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.staging.path).isEmpty)
}
