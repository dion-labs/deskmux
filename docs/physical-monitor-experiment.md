# AOC physical input switching — local evaluation

Validated manually on 2026-09-18: Studio USB-C input `21`, MacBook HDMI 1 input
`17`. Both directions displayed the expected desktop. Studio DDC reads remained
available while HDMI was active. Earlier automatic fallback to USB-C is not
explained; an input read is not proof of a valid picture.

The Displays page contains explicit controls for this desk only. It resolves exactly one local AOC by vendor/product IDs before each operation;
a stored Studio UUID is never used to address the MacBook display. It persists
the input mapping in local preferences. It never modifies the
other monitor or sends monitor commands through the peer.

Studio desk selects AOC USB-C; Split desk selects AOC HDMI 1. The ViewSonic
is assumed to remain on its existing Studio connection. These are video-only
presets, not keyboard/mouse routing commands. Choosing a preset disables follow.

Optional AOC following is off by default and persists locally when enabled.
The app-lifetime model observes confirmed agent ownership even when settings
are closed. It requires two seconds of stable ownership, serializes DDC work,
coalesces changes to the latest owner, and waits three seconds after an operation
before starting another. Unknown agent state cancels the candidate. Any control
failure disables follow until explicitly re-enabled; no infinite retries occur.
Before a write, the exact UUID must support a valid input read. A changed input
must be observed three consecutive times, with three-second intervals, within
the bounded verification period. Helper invocations time out after three
seconds. No automatic rollback is sent. Physical monitor controls are the
fallback if a destination has no picture.

The health panel distinguishes macOS desktop dimensions/refresh from actual
link timing and cable bandwidth. It cannot measure the MacBook HDMI mode from
the Studio.

Backend: signed bundled m1ddc, pinned source and MIT license in Vendor/m1ddc.
This is not yet a generic monitor-discovery or routing implementation.

## Visible-screen window placement

Opt-in separately on each Mac under Displays. Each app reads the shared AOC's
actual selected input (two matching reads, four-second polling), using its own
local display UUID discovered by AOC vendor/product IDs. Unknown/failed reads,
ambiguous monitor matches and layout changes cause no window moves. There is
no new network protocol or reliance on keyboard ownership for visibility.

Ordinary, resizable AX windows centered on the hidden AOC move to the remaining
screen (prefer the built-in MacBook display). Minimized, full-screen,
nonstandard and DeskMux windows are skipped. AX calls run off the main actor.
The app retains original and applied bounds in memory; restoration is attempted
only when the window still matches the applied bounds and the source display
geometry is unchanged. Closing DeskMux loses these restoration records.
Disabling preserves current positions and clears the records. Pointer boundaries
and the macOS display arrangement are not changed. Other Spaces and unusual app
window behavior require real-desk testing; readback is not a picture-health test.

MacBook inactive-HDMI DDC access is not yet validated. If unavailable, its UI
reports that window placement is paused rather than guessing the active input.
