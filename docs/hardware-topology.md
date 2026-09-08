# Initial hardware topology

## Confirmed devices

| Device | Capability relevant to DeskMux | Status |
| --- | --- | --- |
| Mac Studio M1 Ultra | Multiple native external displays | Confirmed |
| 14-inch 2021 MacBook Pro, M1 Pro, 32 GB | Two native external displays up to 6K60 | Confirmed |
| ViewSonic VP2768 | HDMI 1/2, DisplayPort, mini DisplayPort; DDC reachable | Confirmed on Studio HDMI 1 |
| AOC U27B3CF | 4K60, HDMI, USB-C DP Alt Mode/65 W; DDC/CI documented | Historical identity confirmed |
| ASUS ROG Strix Scope RX TKL Wireless Deluxe | USB, 2.4 GHz, three Bluetooth slots | Bluetooth confirmed on MacBook; USB confirmed on Studio |
| Logitech MX Master 4 | Three HID++ Easy-Switch hosts | Bluetooth confirmed on MacBook; Bolt confirmed on Studio |

### ASUS keyboard control probe

The Studio enumerates the keyboard as ASUS `0x0B05:0x1A05`. Its composite USB
device includes a 64-byte input/output vendor collection at usage
`0xFF00:0x0001`; this is the same interface OpenRGB uses for lighting. DeskMux's
passive inspector observed no vendor input report for `Fn+8`, `Fn+9`, or
`Fn+0` in USB mode. A subsequent physical USB-to-Bluetooth transition removed
the entire vendor interface immediately even though the USB cable remained
connected; no vendor report preceded removal. The probe sent zero output
reports.

There is no persistent USB control path while the selector is in Bluetooth
mode, and no observed or published host-selection command comparable to
Logitech HID++ ChangeHost. Do not guess output packets. Any write experiment
requires an independently derived command and a recovery plan.

The Bluetooth-only B1/B2 hypothesis is not adopted. ASUS documents physical
slot selection through `Fn+8/9/0`, but no software host-switch operation was
found in the device documentation, Armoury Crate capabilities, OpenRGB, or the
upstream ASUS HID driver. A Bluetooth product identity alone would not prove a
writable host-selection command, so the working USB/B1 setup should not be
changed for this hypothesis.

## Recommended cabling

DeskMux is not tied to these exact ports. This is a convenient layout that
preserves USB-C charging for the MacBook and gives both Macs a physical path to
both monitors:

| Monitor | Mac Studio path | MacBook path |
| --- | --- | --- |
| ViewSonic VP2768 | Thunderbolt/USB-C → DisplayPort | Built-in HDMI → HDMI |
| AOC U27B3CF | Built-in HDMI → HDMI | USB-C → USB-C |

The Studio's current HDMI cable would move from the ViewSonic to the AOC. The
Studio would need a USB-C-to-DisplayPort cable for the ViewSonic. The MacBook
can keep its existing USB-C link to the AOC and use its built-in HDMI port for
the ViewSonic. Both Macs can drive both external monitors natively at the same
time, although only the selected source is visible on each monitor.

If the existing setup already has one persistent cable from each Mac to each
monitor, it does not need to be rewired: the agents can discover and store the
actual input mapping. If a cable is physically moved between Macs today, that
link must become two persistent cables into two monitor inputs. Software can
select a connected input but cannot reroute a single physical cable.

### Port-agnostic development assumption

Development proceeds against four logical links regardless of their eventual
cable types:

```text
Studio  -> ViewSonic
Studio  -> AOC
MacBook -> ViewSonic
MacBook -> AOC
```

The detected original VP2768 exposes DisplayPort, mini-DisplayPort, and HDMI
video inputs rather than USB-C video. A Mac-side USB-C port can still drive it
through USB-C-to-DisplayPort or USB-C-to-mini-DisplayPort. If both AOC links use
HDMI, they must terminate at two distinct HDMI inputs; this will be confirmed
from the physical port labels when the permanent cables are installed.

## Expected DDC input mapping

These values are provisional until read back on both Macs:

| Monitor | Studio input | MacBook input |
| --- | --- | --- |
| ViewSonic VP2768 | DisplayPort 1 (`15`) | HDMI 1 (`17`) |
| AOC U27B3CF | HDMI 1 (`17`) | USB-C (`27`) |

## Remaining tests

1. Confirm the AOC input value through DDC on both USB-C and HDMI.
2. Enable DDC/CI in both monitor OSD menus.
3. Test whether each monitor accepts DDC commands only from its active input.
4. Connect the ViewSonic to the MacBook's HDMI port and confirm both external
   displays operate together at their native resolutions.
5. Test AirPlay from Studio to MacBook as an extended display at the desired
   resolution and latency.
6. Validate automatic keyboard-only relay plus native mouse handoff in both
   directions, including forced network failure and held-modifier recovery.
