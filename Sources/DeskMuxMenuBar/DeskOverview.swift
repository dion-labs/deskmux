import SwiftUI

/// Presentation-only dashboard: all control and transport remain in existing models.
struct DeskOverview: View {
  let owner: String
  let anchor: String
  let connected: Bool
  let ready: Bool
  let openPage: (String) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Two Macs. One flow.")
            .font(.system(size: 34, weight: .medium, design: .serif))
          Text(connected ? "Your desk is connected. Make yourself at home." : "Your other Mac is out of reach. Local input stays yours.")
            .font(.callout).foregroundStyle(.secondary)
        }
        HStack(spacing: 14) {
          device("Studio", symbol: "display")
          Image(systemName: connected ? "link" : "link.badge.plus")
            .foregroundStyle(.secondary).accessibilityLabel(connected ? "Connected" : "Disconnected")
          device("MacBook", symbol: "laptopcomputer")
        }
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Label("Keyboard anchor", systemImage: "keyboard")
              .font(.callout.weight(.semibold))
            Spacer()
            Text(anchor).font(.callout.weight(.medium)).foregroundStyle(DeskMuxBrand.accent)
          }
          Text("Keep your keyboard connected here. DeskMux carries its input to the Mac you’re using.")
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(20).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))

        HStack(alignment: .top, spacing: 14) {
          feature("Move with intention", detail: "Choose your edge and modifier. Make switching feel like second nature.", icon: "cursorarrow.motionlines", page: "Handoff")
          feature("A shared clipboard", detail: "Plain text follows across your paired Macs. Manage your connection and pairing.", icon: "doc.on.clipboard", page: "Connection")
        }
        HStack(spacing: 12) {
          Image(systemName: ready ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
            .foregroundStyle(ready ? DeskMuxBrand.accent : .orange)
          VStack(alignment: .leading, spacing: 4) {
            Text(ready ? "Set up. Out of your way." : "Let’s finish setting up.").font(.callout.weight(.semibold))
            Text(ready ? "Permissions are ready. You can close this window." : "Review the access DeskMux needs to move input safely.")
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button(ready ? "Review" : "Continue") { openPage("Setup & access") }
        }.padding(.vertical, 4)
      }.padding(.bottom, 12)
    }
  }

  private func device(_ name: String, symbol: String) -> some View {
    let active = owner == name
    return VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text(name.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced))
        Spacer()
        if active { Image(systemName: "cursorarrow").font(.caption) }
      }
      Image(systemName: symbol).font(.system(size: 48, weight: .ultraLight))
        .frame(maxWidth: .infinity).padding(.vertical, 12)
      Text(active ? "You’re here." : "Across the desk.")
        .font(.system(size: 22, weight: .medium, design: .serif))
      Text(active ? "Current input destination" : "Paired destination")
        .font(.caption)
    }
    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(active ? Color.white : Color.primary)
    .background(active ? DeskMuxBrand.teal : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(DeskMuxBrand.teal.opacity(active ? 0 : 0.2)))
    .accessibilityElement(children: .combine)
  }

  private func feature(_ title: String, detail: String, icon: String, page: String) -> some View {
    Button { openPage(page) } label: {
      VStack(alignment: .leading, spacing: 10) {
        HStack { Image(systemName: icon).foregroundStyle(DeskMuxBrand.accent); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.secondary) }
        Text(title).font(.callout.weight(.semibold))
        Text(detail).font(.caption).foregroundStyle(.secondary).lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
      }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }.buttonStyle(.plain)
  }
}
