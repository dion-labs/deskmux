# Studio validation baseline

Validated on 2026-08-24 with macOS 26.5.2 on the M1 Ultra Mac Studio.
Hardware serial numbers are intentionally omitted.

## Display and DDC

| Check | Result |
| --- | --- |
| Active external display | ViewSonic VP2768 |
| Active resolution | 2560×1440 at 60 Hz |
| Active monitor input | HDMI 1, DDC value `17` |
| DDC input reads | 20/20 successful |
| No-op input write | Writing `17` succeeded; display remained online |
| Hardware brightness | Current `38`, maximum `100` |
| Hardware contrast | Current `65`, maximum `100` |
| macOS transport report | Upstream DisplayPort, downstream HDMI |

Switching to a different monitor input is deliberately deferred. Many monitors
stop answering DDC on an inactive source, so an isolated test could leave the
Studio unable to issue the command that switches the panel back. The first real
source change will be transactional, with the destination agent running or the
monitor controls immediately available as a recovery path.

## Input ownership

| Device | Studio transport | Current observation |
| --- | --- | --- |
| ASUS ROG Strix Scope RX TKL Wireless Deluxe | USB | Keyboard HID services present |
| Logitech MX Master 4 | Logi Bolt receiver | Mouse HID service present; Logi Options+ reports the Studio host connected |

The earlier MacBook diagnostics confirmed the same keyboard and mouse over
Bluetooth there. DeskMux should therefore elect ownership from live HID presence
instead of assuming a permanent anchor.

The signed menu-bar agent passed its bounded local capture-and-injection test on
2026-08-24, relaying 155 keyboard and mouse events without a crash. This
validates the Studio's event-tap permissions and the local input codec/injector
path before the network handoff test.

## Peer visibility

The MacBook advertises an AirPlay receiver on the local network and is visible
from the Studio through Bonjour. This confirms basic peer reachability and gives
the "Studio max" profile a native display-receiver path to test before any
custom video transport is considered.

## What the Studio cannot infer alone

An inactive monitor input may hide its EDID from the connected Mac. Therefore,
absence from `system_profiler` does not prove that no cable is attached. DeskMux
can learn a mapping as each source becomes active, but initial setup must either
ask the user which cable reaches which input or cycle inputs with a safe recovery
path.
