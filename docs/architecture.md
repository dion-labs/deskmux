# DeskMux architecture

## Product boundary

DeskMux runs after login on both Macs. It is not a boot-time KVM and does not
attempt to work in FileVault unlock, Recovery, or the boot picker.

The same menu-bar app runs on every peer. One instance initiates a profile
transition, while both instances execute the operations that are locally
reachable. No cloud service is required.

## Components

### Implemented foundation

`DeskMuxCore` currently provides:

- stable peer, monitor, observation, route, and profile models;
- a route registry that confirms a guided observation immediately or requires
  the same passive route in two distinct observation sessions;
- a hard rule that an inactive display path cannot teach DeskMux an input route;
- a planner that rejects missing, ambiguous, duplicate, and contradictory state
  before any operation is executed; and
- a transaction engine with explicit prepare, switch, confirm, and input-routing
  phases. Partial failures report the completed operations and never claim a
  rollback that did not happen.

`deskmux-agent snapshot` is the first read-only local observation surface.
`deskmux-agent simulate` exercises Studio, MacBook, and split transactions using
a no-hardware driver.

The input-only MVP now includes native Quartz event serialization, active
capture, destination-relative pointer injection, Bonjour discovery, and an
encrypted authenticated stream. A receiver must acknowledge readiness before
the source suppresses a single event. Disconnects and the reserved
Control-Option-Command-Escape chord return ownership locally and release held
keys, modifiers, and mouse buttons on the receiver. Pairing secrets are stored
in Keychain, small latency-sensitive frames use TCP `noDelay`, and a local
destination click or key press is an out-of-band return signal. Persistent
display routes and real DDC remain deliberately behind the input milestone.

### Peer and control plane

- Discover peers with Bonjour on the local network.
- Pair explicitly and persist peer public keys in the Keychain.
- Use an encrypted persistent connection for profile commands, acknowledgements,
  input events, and clipboard updates.
- Treat every profile transition as a transaction: prepare, execute, confirm,
  and either complete or report a recoverable partial state.

Different macOS accounts are supported. Apple Universal Control is not a
dependency because it requires the same Apple Account on both Macs.

### Display plane

- Identify physical displays by EDID manufacturer, product, and stable serial
  data rather than transient CoreGraphics display IDs.
- Switch monitor inputs with DDC/CI VCP code `0x60`.
- Execute a DDC command on the peer that currently has a usable DDC path to the
  monitor. After an input switch, control normally transfers to the destination
  peer.
- Observe CoreGraphics display reconfiguration callbacks and wait for the target
  topology before advancing the profile transaction.

The common DDC implementation on Apple silicon uses private `IOAVService` APIs.
Initial distribution should therefore be a signed and notarized open-source DMG,
not an App Store assumption.

### Input plane

Input ownership is elected per device, not per computer. Each peer reports which
keyboard and pointing devices it can currently see.

DeskMux supports two strategies:

1. **Keyboard-only relay**: capture key-down, key-up, and modifier events on the
   keyboard anchor, suppress them when focus is remote, transmit them, and inject
   them on the destination. Its event tap does not subscribe to any pointing-device
   event, so a relay failure cannot disable the native mouse, clicks, or scrolling.
2. **Direct handoff**: ask supported hardware to change its paired host. The MX
   Master 4 exposes Logitech HID++ `ChangeHost` feature `0x1814`, so DeskMux can
   hand the mouse directly to the other Mac and avoid relay latency.

The automatic policy combines these strategies: arm the keyboard relay first,
then switch the mouse through HID++. Returning reverses that order and releases
all injected keys before capture stops. Input Monitoring and Accessibility
permissions are required for the keyboard relay.

When a peer owns relayed input, DeskMux may hold an `IOPMAssertion` to prevent
idle system sleep. This is opt-in, visible in the UI, and released immediately
when ownership moves or DeskMux exits.

### Clipboard plane

The first version synchronizes plain text through `NSPasteboard` with loop
prevention and a bounded payload size. Images, rich text, and file promises are
later features because they require larger transfers and more careful security
handling.

### Agent update plane

The first MacBook installation is manual. Later development builds can be sent
from the Studio over a purpose-separated update session on the authenticated
DeskMux transport. The destination accepts only a newer `dev.deskmux.app`
bundle whose archive hash, embedded build metadata, strict code signature, and
designated signing requirement all validate against the running app. The
current bundle becomes a non-app `.DeskMux.previous` backup before the verified
candidate is installed. A signed bundled helper waits for the old process to
exit before it opens the new bundle, avoiding same-instance LaunchServices
races. Update sessions cannot carry input events. The destination writes a
persistent receipt naming the source and installed build, and the menu displays
it after relaunch until the user dismisses it.

### MacBook display receiver

AirPlay to Mac is the first compatibility path for using the MacBook panel as a
Studio display. It must be validated manually before DeskMux attempts any UI
automation. A custom virtual display and video transport is explicitly outside
the MVP.

## Profile transition sketch

For every target profile:

1. Discover both peers and snapshot displays, input owners, and active DDC paths.
2. Validate that the target does not violate a machine's native display limit.
3. Switch each destination monitor from the peer that currently controls it.
4. Wait for the destination peer to confirm the expected display topology.
5. Route input using direct handoff or relay and update clipboard focus.
6. Confirm success. Never silently claim success after a partial transition.

Route learning is separate from the current topology snapshot. A DDC read of
VCP `0x60` identifies a peer-to-monitor route only while that peer also reports
the monitor online. Otherwise it may merely be reading the input selected for a
different cable. Guided setup therefore activates and confirms each physical
route once, then stores the result for later profile transitions.
