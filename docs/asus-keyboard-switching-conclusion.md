# ASUS keyboard switching: research decision

Stop active native-switch protocol hunting for now. There is no verified,
non-destructive software command to select a transport or an existing Bluetooth
host on this X807 keyboard. The remaining leads no longer justify more live
experiments or open-ended disassembly for DeskMux.

This is a practical stopping decision, not proof of impossibility.

## Evidence behind the decision

- Hardware experiments had a successful physical-RF positive control. The
  tested factory/RF sequence produced wired typing but no receiver typing.
- The downloaded official 12.42.03 firmware samples the physical selector.
  Its normal Bluetooth host selection builds a channel-35 `91` packet.
- USB factory forwarding is fixed to channel 34 and retains the FA header.
  The radio parser and resolved FA21 worker events do not alias normal slot
  selection. FA05 can reinitialize per-slot data; it is not a safe switch.
- The apparent hidden demo-mode branch has no established trigger. Its shared
  callback is lighting-related. Ordinary key remapping uses a different table
  from the fixed Fn-key dispatch table.
- Configuration writes, including multipart sequences preserving RAM, did
  not activate the hidden action or transport flags in the modeled paths.
- The two remaining RF workers use separate test state/events, RF command
  descriptors and PER/END packets. No switching connection was established.
- A final bounded USB-surface pass completed 5,630 additional cases: all
  subcommands of 12/41/43/50/52/53/C0 under three synthetic flag states,
  plus top-level opcode probes excluding reset/bootloader entries. No radio
  enqueue occurred and no transport/action change was found. The only watched
  flags write was the known FA00 factory-clear operation, leaving 1000 intact.
- The additional settings-write path `12 13` calls `9ac4` with hard-coded
  index 0. It does not expose index 5 used by the demo-mode branch. Its
  persistent-write behavior also means opcode 12 is not universally read-only.

## Limits

The emulator executes selected firmware routines with real C-runtime RAM
initialization, but uses synthetic flags/GPIO and stubs many callees. It does
not emulate the complete device or scheduler. Most packet parameters were
not exhaustively varied. Driver/ROM callbacks and aliased writes have not all
been resolved. The official downloaded firmware is not established as the
exact installed version. No absence claim should ignore these limitations.

## What would justify reopening

A captured successful switch from ASUS software for this exact model, an
independently verified exact-model command, or a concrete code path connecting
USB input to the normal slot/transport transition. An apparent diagnostic ACK,
a similarly named command from another model, or a flag in RAM is insufficient.

Firmware modification and hardware reverse engineering are separate projects
with substantially different costs and risks. They are not necessary to ship
DeskMux's existing keyboard relay. Continue with that relay for this keyboard;
keep the native mouse-switch work separate.

No firmware was flashed and no new live HID commands were sent during the
firmware analysis and emulation work. The Windows research VM and downloaded
artifacts were not removed. Full provenance, addresses, earlier experiments,
reproduction scripts and limitations are in `asus-keyboard-switching-research.md`.
