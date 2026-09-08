import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginModel: ObservableObject {
  @Published private(set) var status: SMAppService.Status
  @Published private(set) var message: String?
  @Published private(set) var hasError = false

  private let service = SMAppService.mainApp

  init() {
    status = service.status
  }

  var isRequested: Bool {
    status == .enabled || status == .requiresApproval
  }

  var statusSummary: String {
    switch status {
    case .enabled:
      return "DeskMux will open automatically when you log in."
    case .requiresApproval:
      return "Allow DeskMux in System Settings → General → Login Items."
    case .notRegistered:
      return "DeskMux opens only when you launch it yourself."
    case .notFound:
      return "Launch at login is unavailable from this app location."
    @unknown default:
      return "Launch-at-login status is unavailable."
    }
  }

  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try service.register()
      } else {
        try service.unregister()
      }
      hasError = false
      message = nil
    } catch {
      hasError = true
      message = error.localizedDescription
    }
    refresh()
  }

  func refresh() {
    status = service.status
  }

  func openLoginItems() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
