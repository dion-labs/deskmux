<div align="center">

<img src="docs/brand/mux.png" alt="Mux, DeskMux's twin-tailed lynx companion" width="220" />

# DeskMux

### Two Macs. One flow.

Your mouse crosses the desk. Your keyboard and clipboard come along.

[Website](https://deskmux.dionlabs.ai) · [Download](https://github.com/dion-labs/deskmux/releases) · [Sponsor](https://github.com/sponsors/dion-labs)

</div>

DeskMux is a native, open-source macOS utility for sharing input between a
desktop Mac and a MacBook. It combines a supported Logitech mouse's native
host switch with encrypted keyboard forwarding and shared text clipboard.
Different Apple Accounts work. No cloud account or subscription is needed.

## What works today

- **Native mouse handoff.** A compatible Logitech HID++ ChangeHost interface
  changes the mouse's actual connection to the other Mac.
- **Keyboard follows.** Keep the keyboard attached to an anchor Mac; DeskMux
  forwards its input only when you work on the other Mac.
- **Shared text clipboard.** Copy on either Mac and paste on the other.
- **Intentional edges.** Hold Option and touch the configured outer screen
  edge. The modifier and edge are configurable; push-and-dwell is also available.
- **A quiet menu-bar companion.** Connection state, permission guidance,
  launch at login, emergency return and paired-Mac updates.

## Before you download

This is **v0.1.1, a public preview**. Daily use has been validated with a
Mac Studio M1 Ultra, MacBook Pro M1 Pro and Logitech MX Master 4 (Bolt on the
desktop, Bluetooth on the laptop), on macOS 26.5.2. The deployment target is
macOS 14+, but older versions and other HID++ mice need testing. The download
is for Apple silicon. Role selection currently assumes one desktop and one
MacBook; arbitrary multi-Mac arrangements are not supported yet.

The preview is Apple Development signed, **not notarized**. macOS may require
an explicit approval in Privacy & Security after you try opening it. Do not
disable Gatekeeper system-wide. You can also build from source.

Clipboard sharing currently transfers plain text up to 1 MiB; rich text,
images and files stay local. Sensitive copied text is shared too. See
[Security and privacy](SECURITY.md).

Virtual-display streaming is **experimental**. Physical monitor input
switching and complete video routing are **not part of this release**.

## Set up your desk

1. Download the same build on both Macs, extract it, and put `DeskMux.app` in
   Applications before opening it.
2. Follow the Permissions page to enable Accessibility, Input Monitoring and
   Local Network access. Screen Recording is only needed for streaming.
3. In Connection, save the same pairing code on both Macs. Keep it private.
4. Select the keyboard anchor: the Mac physically connected to your keyboard.
5. Pair your supported mouse with each Mac, then identify its return channel
   on each side. DeskMux unlocks switching once both channels are configured.
6. Configure the outer edge and trigger on each Mac. Hold Option (by default)
   and move to that edge to switch.

**Return input immediately:** press Control–Option–Command–Escape on the
keyboard's source Mac, or use DeskMux's return control. DeskMux runs after
login; it does not replace input at FileVault unlock or in Recovery.

If Logi Options+ Flow is enabled, turn Flow off to prevent competing handoffs.
DeskMux includes conflict detection for the supported Flow configuration.

## Build and contribute

Requires Swift 6 / Xcode command-line tools on macOS.

```sh
git clone https://github.com/dion-labs/deskmux.git
cd deskmux
swift test
Scripts/build-app.sh
```

The app is built at `.build/DeskMux.app`; `Scripts/install-app.sh` installs it
locally and restarts the menu app. The build uses an available signing identity
or falls back to ad-hoc signing. See [development notes](docs/development.md),
[architecture](docs/architecture.md) and [contributing](CONTRIBUTING.md).

Please report your Mac, macOS version, mouse model and connection type when
filing a compatibility issue. Review diagnostic output before sharing it.

## Made at Dion Labs

DeskMux grew out of a real desk: two Macs, a good mouse, too many switches.
Mux, our twin-tailed lynx, keeps an eye on both sides.

MIT licensed. [Third-party acknowledgements](THIRD_PARTY_NOTICES.md).
The presentation site has its own [repository](https://github.com/dion-labs/deskmux-site).
