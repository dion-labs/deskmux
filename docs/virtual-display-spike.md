# Virtual display feasibility spike

DeskMux's preferred screen-sharing mode creates an additional display on the
source Mac and streams that display to the destination. macOS treats it as an
extended monitor, so applications can be moved onto it without exposing or
duplicating the source Mac's physical screen.

## Compatibility boundary

Apple does not publish an API for creating displays. `CGVirtualDisplay` is an
undocumented Core Graphics runtime used by projects such as DeskPad. DeskMux
resolves every private class and selector dynamically in `CVirtualDisplayBridge`.
Unsupported macOS versions therefore report an error without loading private
symbols into the Swift application layer.

The probe uses a 3840×2400 backing mode exposed as a 1920×1200 HiDPI display at
60 Hz. It verifies that:

1. Core Graphics lists the new display.
2. ScreenCaptureKit lists it and, when Screen Recording permission already
   exists, produces a frame.
3. Releasing the owning object removes the display.

Run it with:

```sh
swift run deskmux-virtual-display-probe
```

The probe intentionally does not request Screen Recording permission. A
`permissionMissing` result proves display creation and cleanup but defers the
capture-frame check to the signed DeskMux app, where the permission grant will
remain stable across development builds.

## Studio result — 2026-08-27

The probe passed on the Mac Studio running macOS 26.5.2 (25F84):

- Core Graphics added an online, non-main 1920×1200 display.
- ScreenCaptureKit enumerated it and delivered a 1920×1200 frame.
- Releasing the session removed it and restored the original display topology.
- Three immediate repeat runs created display IDs 11, 12, and 13; every run
  captured a frame and removed the display without leaving a phantom monitor.

This validates the private API for the current Studio environment. The next
milestone is to keep the virtual display in the stable DeskMux service, encode
its ScreenCaptureKit frames with VideoToolbox, and render them in a focus-aware
window on the paired Mac. Physical-display capture remains the fallback when
the private runtime is unavailable.

## Attribution

The private object graph and selectors were independently validated against
[DeskPad](https://github.com/Stengo/DeskPad), Copyright © 2022 Bastian
Andelefski, distributed under the MIT License.
