# DeskMux

DeskMux is an open-source, profile-driven display and input router for a desk
with multiple Macs. It coordinates monitor inputs, keyboard and mouse routing,
clipboard sharing, and optional use of one Mac as a streamed display for the
other.

The project has a tested routing core and is still in its hardware-validation
phase. The first supported topology is a Mac Studio paired with an M1 MacBook
and two external monitors.

## Intended profiles

- **Studio**: both external monitors and input are routed to the Mac Studio.
- **Split**: one external monitor is assigned to each Mac; input follows focus.
- **MacBook**: both external monitors and input are routed to the MacBook.
- **Studio max**: both external monitors are assigned to the Studio and the
  MacBook runs a full-screen receiver as a third Studio display.

## Current hardware findings

- Mac Studio (`Mac13,2`), M1 Ultra, 128 GB, macOS 26.5.2.
- 14-inch 2021 MacBook Pro (`MacBookPro18,1`), M1 Pro, 32 GB, macOS
  26.5.2. It natively supports both external monitors alongside its built-in
  display.
- ViewSonic VP2768, 2560×1440 at 60 Hz. DDC/CI is reachable from the Studio;
  its current input reports as HDMI 1 (`17`).
- AOC U27B3CF, 3840×2160 at 60 Hz, recovered from the Studio's ColorSync and
  display-layout history. Its manual documents DDC/CI, HDMI, and USB-C DP Alt
  Mode with power delivery.
- ASUS ROG Strix Scope RX TKL Wireless Deluxe keyboard, currently connected by
  USB. It supports wired, 2.4 GHz, and three manually selected Bluetooth hosts.
- Logitech MX Master 4 through a Logi Bolt receiver. Its HID++ host table shows
  both Macs, and it is confirmed over Bluetooth on the MacBook, so direct
  Easy-Switch handoff is a viable experimental transport.

Serial numbers, Bluetooth addresses, and account information are deliberately
excluded from project diagnostics and documentation.

## Diagnostics

Run the sanitized inventory tool on either Mac while the relevant monitor and
input devices are connected:

```sh
swift run deskmux-diagnostics
```

The command prints JSON containing the Mac model, macOS version, connected
displays, USB device names, and Bluetooth device names. It omits hardware UUIDs,
serial numbers, network addresses, and Bluetooth addresses.

## Agent development commands

Build and install the menu-bar app into the current user's Applications folder:

```sh
Scripts/install-app.sh
```

The build prefers `Developer ID Application`, then `Apple Development`, from
the login keychain. A stable certificate gives every version a compatible
macOS designated requirement, so privacy grants survive upgrades. When neither
identity exists, the script falls back to ad-hoc signing and warns that a
rebuild may require permission approval again. A specific identity can be set
with `DESKMUX_SIGNING_IDENTITY`.

The status-bar icon shows whether the agent is running and whether Input
Monitoring and Accessibility are granted. Its permission guide requests the
grants, links directly to each System Settings page, and refreshes status while
the panel is open. Using the app bundle gives macOS a stable `dev.deskmux.app`
identity; the CLI remains available for diagnostics and development tests.

Once permissions are granted, the stable agent automatically advertises an
encrypted input receiver as `studio` or `macbook`, based on the Mac model. Its
pairing code is generated locally and saved in Keychain. Put the same code into
the app on both Macs, then use the bounded 15-second keyboard test. Keyboard-only
capture installs an event tap containing only key-down, key-up, and modifier
events; mouse motion, buttons, dragging, and scrolling cannot be suppressed by
that tap. The emergency chord Control-Option-Command-Escape always returns the
keyboard to the source Mac.

The menu identifies the configured **keyboard anchor**: the Mac to which the
physical keyboard is connected and where it returns after a handoff. It defaults
to Studio and can be changed with **Make This Mac Anchor**. While receiving
keyboard input, every destination display gets a click-through cyan ownership
border.

For compatible Logitech mice, the menu also reports a **native Logitech mouse**
path separately from the keyboard anchor. DeskMux resolves HID++ ChangeHost at
runtime and can let the mouse reconnect directly to the destination Mac, so
pointer motion never crosses the network. Native switch controls stay locked
until both Macs have identified their own Easy-Switch return channel.
**Automatic edge handoff** first waits for the stable agent to confirm that the
keyboard-only relay is active, then invokes the native mouse switch. On return,
the destination releases injected keys and asks the anchor to stop capturing
before the mouse changes channel. A setup, permission, network, or mouse-switch
failure leaves or restores the keyboard locally and fails closed. The edge and
trigger are stored independently on each Mac. The default trigger requires the
configured logical modifier (Option/Alt, Command, Control, or Shift) at the edge
and fires immediately; without that modifier the edge has no effect. The legacy
push-and-wait trigger remains selectable. In that mode an outward push starts
the dwell; a timer completes it while the pointer stays at the edge, so continued
movement is not required and tiny edge jitter does not reset the countdown.
Moving away cancels the pending gesture; moving at least 24 points inward after
a switch rearms it and prevents a switch loop. Accepted gestures show the cursor
cue immediately and recheck unavailable mouse-channel status rather than being
silently dropped on a stale background poll. Millisecond timestamps and failure reasons
are written to `~/Library/Application Support/DeskMux/handoff.jsonl`.

Each stable agent prepares an authenticated keyboard channel to its paired Mac
before a handoff is requested. A two-second heartbeat verifies that the idle
channel is still usable; a missing reply expires and replaces it automatically.
The receiver remains logically idle until the source sends `beginInput`, so the
warm connection never captures or injects input by itself. The menu reports the
warm channel state and its latest round-trip time. Connection lifecycle records
are appended to `~/Library/Application Support/DeskMux/network.jsonl`.

That same encrypted warm channel synchronizes plain text copied on either Mac,
independently of which Mac currently owns the mouse and keyboard. Clipboard
changes are observed every 150 milliseconds, capped at 1 MiB, and tagged with a
unique update identifier. Remote writes advance the local pasteboard generation
and duplicate identifiers are discarded, preventing the two peers from echoing
an update back and forth. Rich text, images, files, and file promises remain
local for now. Delivery metadata (identifier, byte count, and acknowledgement,
but never clipboard contents) is written to
`~/Library/Application Support/DeskMux/clipboard.jsonl`.

Create a signed archive that can be copied to the MacBook without moving the
source tree:

```sh
Scripts/package-macbook.sh
```

This writes `~/Downloads/DeskMux-MacBook.zip`. Copy it with AirDrop or file
sharing, extract it, and move `DeskMux.app` into the MacBook's Applications
folder. A Personal Team development certificate is stable for privacy grants
but is not a notarized public distribution identity, so the first launch on the
MacBook may require Control-clicking the app and choosing **Open**.

That manual copy is the bootstrap. After both peers run the update-capable
version, each app compares the Bonjour-advertised build and input-protocol
versions of both menu apps and both stable agents. A green **DeskMux versions**
row confirms all four match. The Studio shows **Send Update** only when it
detects an older MacBook build; synchronized peers do not show the button.
The button packages its currently running app and sends it over the encrypted pairing. The MacBook accepts the update only
when its SHA-256 hash, bundle identifier, full code signature, and designated
signing requirement validate and its build number is newer. It keeps the prior
bundle in a non-app `.DeskMux.previous` directory, installs the candidate as
`~/Applications/DeskMux.app`, and relaunches it from there. A bootstrap copy
launched from Downloads is hidden as rollback data after this migration, so
Finder and Launch Services expose only the canonical application. The new app
shows a persistent update receipt until the user
dismisses it.

Inspect the local Mac from the agent's point of view:

```sh
swift run deskmux-agent snapshot studio
```

Passively inspect the vendor HID interface exposed by the configured ASUS
keyboard:

```sh
swift run deskmux-agent asus inventory
swift run deskmux-agent asus receiver-status
swift run deskmux-agent asus inspect 30
swift run deskmux-agent asus paths 10
```

The inventory lists only the exact `0x1A05` wired keyboard and `0x1A07` RF
receiver without opening them. The inspector matches only ASUS
`0x0B05:0x1A05` usage `0xFF00:0x0001` and has no output-report API. Neither
command can transmit a report or alter keyboard state.
The path monitor samples only macOS kernel input-report counters for each exact
wired/receiver keyboard interface; it does not open them or retain key contents.
The receiver-status command sends only the documented non-mutating `12 01`
query to the exact `0x1A07` receiver; it never opens the keyboard. The guarded
RF experiment and its hardware results are documented in
`docs/asus-keyboard-switching-research.md` and are intentionally excluded from
the passive command block above.

This emits a sanitized JSON snapshot of the machine model and currently online
displays. The optional peer ID is a user-defined DeskMux name, not a hardware
identifier.

## Virtual displays

DeskMux can create a temporary 1920×1200 HiDPI display on either paired Mac and
show it in a window on the other Mac. Open **Settings → Displays → Open Display**.
The source Mac's stable **DeskMux Agent** needs **Screen & System Audio
Recording** permission; the Displays page detects the grant and provides the
permission and agent-restart controls.

The local pointer is never captured. Moving over the streamed image sends a
remote pointer position, clicking the image gives its keyboard focus, and
clicking elsewhere returns keyboard input to the local Mac. Press Escape to
release remote keyboard focus. Closing the viewer tears down both the stream
and the virtual display.

Screen messages and remote input use the existing pairing secret with
authenticated encryption. Video is real-time H.264 over a persistent TCP
connection, while Bonjour selects the paired source and the best ordinary LAN
route available.

DeskMux can also register its menu app as a macOS Login Item. Use **Settings →
General → Launch DeskMux at login**; this is independent of the stable
background agent and can be disabled at any time.

Exercise a profile transaction without touching DDC or input devices:

```sh
swift run deskmux-agent simulate studio
swift run deskmux-agent simulate macbook
swift run deskmux-agent simulate split
```

The simulation starts from the currently observed split layout. Its input
numbers are fixtures for testing the planner; the setup flow will replace them
with routes learned from the permanent cables.

### Input-only MVP

Keyboard and mouse relay is now the first hardware milestone. Check or request
the two macOS permissions with:

```sh
swift run deskmux-agent input permissions
swift run deskmux-agent input permissions --request
```

The source needs permission to capture an active event tap, and the destination
needs Accessibility permission to post events. Accessibility can authorize both
operations, so DeskMux may correctly show input capture as available without a
separate entry in the Input Monitoring list. A bounded local verification is
available before involving the second Mac:

```sh
swift run deskmux-agent input monitor 5
swift run deskmux-agent input loopback 5
```

The monitor is passive. Loopback actively suppresses and reinjects events for a
maximum of 30 seconds. Press Control-Option-Command-Escape at any time to return
input locally.

Discover and read the current Logitech Easy-Switch state without changing it:

```sh
swift run deskmux-agent logitech discover
swift run deskmux-agent logitech probe
```

The development-only switch command uses zero-based host indexes and requires
the expected current host so stale state fails closed:

```sh
swift run deskmux-agent logitech switch --from 0 --to 1
```

The menu-bar app is the preferred first cross-Mac test. The CLI remains useful
for transport debugging: use the same secret of at least 16 characters in both
terminals and start the MacBook receiver first:

```sh
DESKMUX_SHARED_KEY='replace-with-a-long-random-secret' \
  swift run deskmux-agent input receive --peer macbook
```

Then run the relay on the Studio:

```sh
DESKMUX_SHARED_KEY='replace-with-the-same-secret' \
  swift run deskmux-agent input relay --peer studio --to macbook --keyboard-only
```

The receiver advertises itself with Bonjour. Input messages are encrypted and
authenticated with ChaCha20-Poly1305, use separate keys in each direction, and
reject replayed or out-of-order frames. The environment-based secret is a
development pairing mechanism; the app will replace it with a Keychain-backed
pairing flow.

Run the formatting and test gates with:

```sh
swift format lint --strict --recursive Package.swift Sources Tests
swift test
```

Pointer-latency work uses a motion-only record/replay loop with receiver-side
echoes and an append-only experiment ledger. See
[docs/motion-research.md](docs/motion-research.md) for its safety invariants,
acceptance thresholds, and candidate protocol.

## Status

See [docs/architecture.md](docs/architecture.md) for the design and implemented
transaction core, and
[docs/hardware-topology.md](docs/hardware-topology.md) for the connection plan
and remaining compatibility tests. Reproducible hardware results are recorded
in [docs/studio-validation.md](docs/studio-validation.md).
