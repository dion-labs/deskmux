# ASUS keyboard native-switch research

Current decision: stop active native-switch hunting pending new evidence. See
[research conclusion](asus-keyboard-switching-conclusion.md) for the outcome,
limitations, and criteria for reopening. Historical next-step notes below are
superseded by that decision.

Research date: 2026-08-31; evidence audit resumed 2026-09-04

## 2026-09-04: resumed investigation and evidence corrections

Recovered the prior task, “Investigate keyboard switching”, and checked the
monitor implementation against the recorded experiment. The historical test
proves that wired input continued during factory/RF mode. It does **not** prove
that the receiver carried no input: both receiver counters were unavailable,
and there was no confirmed positive-control run demonstrating that the monitor
could detect ordinary physical RF-mode typing. Simultaneous USB/RF delivery
therefore remains untested. This does not establish a working switch.

The counter delta calculation also treated a missing baseline as zero whenever
an ending counter existed. It now returns unknown unless both counters exist
and are nondecreasing; regression tests cover missing values and resets.

A new one-second passive sample on this Mac found receiver PID `0x1A07`'s
8-byte keyboard interface with counter `3 -> 3`, and wired PID `0x1A05`'s
8-byte interface with `1829 -> 1848`. Both 15-byte interfaces still lacked a
counter. This demonstrates receiver-counter availability today, not RF typing
or software switching. No output report was sent.

A 30-second physical-selector baseline was then recorded in
`.build/asus-research/baselines/20260904-222934-physical-selector.json`.
The wired 8-byte counter rose from 2154 to 2194 by 7.18 seconds and remained
flat through 29.40 seconds. The receiver 8-byte counter stayed at 3 throughout;
both 15-byte counters remained unavailable, and registry identities were stable.
User confirmation of the actual selector/typing sequence is pending. This run
does not yet validate receiver observability; do not interpret it as a negative
software-RF result. No output reports were sent.

The user subsequently clarified that they had not performed the manual steps
during that first run, so it is not a physical-switch experiment. A guided
three-stage run after an explicit “ready” produced:

| Guided sample | Wired 8-byte counter | Receiver 8-byte counter |
| --- | --- | --- |
| Wired typing, 10 seconds | 2334 -> 2378 (+44) | 3 -> 3 (+0) |
| Physical RF switch and typing, 20 seconds | 2388 -> unavailable | 3 -> 68 (+65) |
| Return to wired, 20 seconds | absent from initial inventory | 77 -> 77 (+0) |

Raw samples are `wired-guided.json`, `rf-guided.json`, and
`wired-return-guided.json` in the same baseline directory. This is a successful
positive control for detecting receiver input on the 8-byte interface. The
return sample does not measure wired typing: the monitor inventories only once
and cannot discover an interface reappearing during the window. Post-run
inventory confirmed all four wired interfaces returned with new registry IDs,
including keyboard interface 4294975700 and vendor interface 4294975697;
revisions remain `0x0117` wired and `0x0105` receiver. The original wired
keyboard registry ID was 4294973444. The receiver kept its identity.

Thus physical RF selection removes the wired HID path in this observed setup;
software factory/RF mode previously preserved it. The receiver measurement is
now validated for a future bounded diagnostic experiment. No vendor commands
were sent during these guided samples.

### Validated-counter factory/RF repeat

With user authorization, the existing seven-command factory/RF diagnostic was
repeated for 15 seconds while the user was prompted to tap a letter, keeping
the physical selector wired. The receiver again returned `FA 20 06 00 01`.
The now-validated receiver 8-byte counter stayed `77 -> 77` (+0); the wired
8-byte counter increased `274 -> 353` (+79). Both 15-byte counters remained
unavailable. Thus the tested sequence did not deliver reports on the receiver
interface demonstrated to carry normal RF typing in the positive control.
Simultaneous normal typing on that receiver interface is ruled out for this run;
this does not prove absence of every firmware switching mechanism.

All seven writes returned success and all seven commands had vendor responses,
including RF exit and both factory exits. Post-test inventory contained all
eight interfaces with unchanged revisions (`0x0117`/`0x0105`), and both vendor
registry identities survived. No pairing or firmware commands were sent.
Artifacts: `factory-rf-validated-counter.json` and
`post-factory-rf-inventory.json` in the baseline directory.

The next unresolved mechanism is whether factory mode itself suppresses normal
receiver delivery. The current result alone does not justify changing the
sequence; inspect the firmware or find documented state-transition behavior
before another hardware experiment. Repeating this same diagnostic adds no
useful evidence now that receiver observability has been validated.

### Offline factory-state control-flow audit

Re-read the decompiled pairing client's `EnableFactory` (Pairing.cs:240),
`EnterRFMode` (:566), `CheckRFConnection` (:605), and
`DoPairingActionForKB` (:1007). The successful keyboard sequence always exits
RF before exiting either device's factory mode. No normal keyboard-input
measurement occurs in the utility. Factory entry/exit uses the same payload
builder for keyboard and receiver, but that does not establish identical
firmware effects. The newer `ForceFactoryMode` builder adds ASCII `EN_RF` /
`LV_RF` fields and belongs to the protocol-2 branch; its name is not evidence
that it is applicable to this model or selects normal HID routing.

An additional caution: the receiver callback stores command-6 responses in
`m_byteInConnectStatus`, but the old keyboard routine checks
`m_byteInDGData[4]` after `CheckRFConnection`. That buffer also receives pairing
data. Thus the client's success conditional is not a clean specification of
the connection-response meaning. Our actual captured `FA 20 06 00 01` remains
a repeatable response, but its interpretation should not rely solely on that
conditional. No pairing data was queried in our experiments.

Neither this control flow nor the bounded string survey of extracted keyboard
HAL/Core DLLs documents receiver HID suppression or RF persistence after
factory exit. Public exact-model/factory-protocol searches added no relevant
implementation. Offline evidence therefore leaves receiver suppression open.

A discriminating next experiment would hold the keyboard in **physical RF**,
establish receiver typing, send only the already-tested receiver factory entry,
measure typing again, then unconditionally send receiver factory exit and
measure recovery. The keyboard receives no mode command. An on/off/on report
pattern would implicate receiver factory mode; continued typing would argue
against it in normal physical RF operation. Neither outcome alone demonstrates
software switching or proves behavior under the keyboard's diagnostic RF mode.
This experiment has not been implemented or run. No device writes occurred
during the offline audit.

### Receiver-only experiment preparation and first baseline attempt

Implemented `asus receiver-factory-input-test
--acknowledge-temporary-factory-mode-and-recovery-plan`. It pins receiver
revision `0x0105`, requires at least four measured receiver reports during a
10-second baseline before any write, then measures 10 seconds with receiver
factory mode and 10 seconds after exit. A deferred cleanup sends factory exit
if observation throws after entry. Only the receiver handle is opened.

The first attempt stopped at the baseline gate: receiver counter `77 -> 77`,
with no wired interface in the initial inventory. No commands were sent.
Saved as `baselines/receiver-factory-isolation.json`. The test has compiled,
but its active and recovery phases have not yet run. User confirmation of
working physical RF typing is needed before repeating it.

### Receiver-only factory test completed

The user clarified distraction during the first attempt and requested a retry.
With the keyboard physically in RF mode, receiver 8-byte input reports were:

| Phase (10 seconds each) | Counter | Delta |
| --- | --- | --- |
| Baseline | 168 -> 212 | +44 |
| Receiver factory mode | 213 -> 273 | +60 |
| After factory exit | 274 -> 322 | +48 |

Both receiver entry and exit returned I/O success and matching vendor echoes.
Normal receiver input continued during factory mode. This rules out receiver
factory mode as a blanket HID-input suppressor in physical RF operation; it
does not establish how keyboard diagnostic RF traffic differs from normal RF.
The result shifts attention toward the keyboard's diagnostic mode/routing,
rather than trying receiver factory-exit reordering on speculation.

Post-run inventory retained all four receiver interfaces and revision `0x0105`.
Only two receiver factory commands were sent; no keyboard, pairing, or firmware
commands were sent. Raw evidence: `receiver-factory-isolation-retry.json` and
`post-receiver-factory-inventory.json` in the baseline directory. Physical RF
mode was left unchanged for the user.

### Windows VM preparation

User authorized choosing and preparing a local VM and will connect an external
SSD. Selected UTM + Windows 11 ARM first for live package retrieval, with full
x86-64 emulation as fallback if ASUS dependencies prevent useful execution.
Installed official UTM v4.7.5 at `/Applications/UTM.app`; deep/strict codesign
verification and Gatekeeper assessment passed. Release metadata and DMG are in
`.build/asus-research/vm-setup/`. No VM has been created yet.

Microsoft's official Windows ARM page generated an English Windows 11 25H2
download for `Win11_25H2_English_Arm64_v2.iso`, expiring
2026-09-05T20:55:10Z. Published SHA-256:
`638AA2C88E94385B00F4F178D071E3DF0B7D9E335577A83BD533B7F2EB65ADF0`.
The download page is preserved in the in-app browser. ISO download and VM
creation await the SSD; `diskutil list external physical` showed no external
disk at the last check. Planned allocation: 8 vCPUs, 16 GiB RAM, expandable
virtual disk on the SSD, initially no USB passthrough. Preserve existing SSD
contents; do not format it. No Windows or ASUS executable has been run.

External SSD troubleshooting: user subsequently allowed erasing the old backup
drive if necessary. T7 is now directly connected and blinking blue. Full
`ioreg -r -c IOMedia -l` identifies Samsung PSSD T7 as disk24, 1,000,204,886,016
bytes, MBR with disk24s1. The partition Content hint is Windows_NTFS, but the
actual filesystem has not been verified. Earlier `ioreg -a` queries omitted
`-l`, so absent properties in those outputs were not evidence of absent media.
Both diskutil and a bounded 512-byte partition-header read time out. No SSD
writes have been performed. Kernel logs show USB stalls, USB2 enumeration, and
transient exclusive opens by adb/ChatGPT. The idle adb server had no devices
and was stopped via its official `kill-server` command; causal involvement is
unproven. Next step: reconnect after stopping adb and recheck read access.
Re-resolve disk identity before any future write; disk24 is not a stable name.

After reconnect at 23:14:19 with adb stopped, diskutil still timed out. Fresh
kernel logs again show ChatGPT PID 662 briefly owning exclusive USB access,
then endpoint stalls and MODE_SENSE_06 failure. Removing adb alone did not
resolve the issue. The newest raw-header read returned permission denied, so
that attempt supplies no evidence about media readability. Do not classify
the drive as failed solely from these diagnostics. Next isolation candidate is
closing the separate ChatGPT desktop app before reconnect, or testing on the
MacBook. No formatting has been attempted.

User subsequently freed internal space (109.4 GiB available) and authorized
internal VM creation. Downloaded the official English Windows ARM ISO to
`~/VirtualMachines/Installers/Win11_25H2_English_Arm64_v2.iso`.
SHA-256 verified exactly against Microsoft's published value above. UTM wizard
was started with Virtualize / Windows, requested 16384 MiB and 8 cores. VM has
not yet been saved or booted: the native file picker automation repeatedly
returns Go to Folder to `/` when confirming a valid path. Manual selection of
the ISO is the next required UI step; then verify hardware settings and finish
the planned 64 GiB expandable disk configuration. No Windows license accepted
and no ASUS software run. UTM v4.7.5 source was fetched into vm-setup/utm-source
for configuration-format inspection, but no alternate VM package was created.

After user selected the ISO manually, saved VM “ASUS Firmware Research”, UUID
`7E534CDF-71F8-403E-B93B-40DBC0482981`, at
`~/Library/Containers/com.utmapp.UTM/Data/Documents/ASUS Firmware Research.utm`.
Verified config: ARM64 virt, 8 CPUs, 16384 MiB, Hypervisor/UEFI/TPM enabled,
USB passthrough disabled, no host shared directory. NVMe qcow2 header verifies
64 GiB virtual capacity. VM started and ISO boot prompt appeared, but automated
keys were dropped. Exited EFI shell to Boot Manager; first USB installer entry
is selected. User must press Enter then promptly any key at the CD/DVD boot
prompt. Windows setup has not yet loaded; no Windows EULA accepted. Cursor
capture was enabled during troubleshooting; UTM says Ctrl+Option releases it.

September 5 setup completion: the installer was still mounted, but the virtual
disk already contained Windows partitions and an installed system. Accepted
Windows terms with explicit user authorization, then exited the duplicate
installer without installing over the disk. Ejected both CD images and selected
Windows Boot Manager in UEFI. Windows booted to the existing `D` account desktop.
Installed official UTM Guest Tools 0.1.271 from UTM's tools ISO; the installer
reported success and the display driver increased the guest resolution. Ejected
the tools ISO and performed a normal Windows restart, which reached Windows
automatically without manual boot selection. No ASUS software or firmware
updater was executed in this setup step. Next: obtain ASUS live firmware
metadata/packages within the isolated Windows ARM environment.

Next, validate the measurement using ordinary physical-selector RF typing and
return-to-wired typing, with idle intervals for comparison. Only after that
positive control is confirmed can a bounded diagnostic repeat resolve whether
the existing RF command delivers simultaneous input. A separate hypothesis is
that factory mode suppresses normal receiver input; the existing experiment
kept **both** devices in factory mode throughout measurement. Changing that
sequence requires further protocol evidence, not an assumption that factory
exit preserves the RF override.

The previous HAL analysis establishes no identified host selector in the
inspected software. It cannot establish absence of an unexposed firmware
command. Firmware acquisition remains an independent lead; a fresh exact
updater-name/package-ID web search did not locate an actionable download.

## Goal

Determine whether DeskMux can move the ASUS ROG Strix Scope RX TKL Wireless
Deluxe between its wired USB path and its paired 2.4 GHz receiver without
flashing firmware, changing pairing data, or relying on guessed HID packets.

The desired topology is:

```text
Mac Studio -- USB cable --> keyboard vendor control
MacBook    -- USB dongle -> keyboard native input over 2.4 GHz
```

Bluetooth-slot selection remains a separate problem. In Bluetooth mode the
keyboard removes its wired USB HID interfaces even while the cable stays
connected, so a host command cannot subsequently return it through that path.

## Confirmed local hardware

The wired keyboard currently enumerates as:

| Property | Value |
| --- | --- |
| Vendor/product | `0x0B05:0x1A05` |
| Product | `ROG STRIX SCOPE RX TKL WIRELESS DELUXE` |
| USB device revision | `0x0117` |
| Vendor collection | usage `0xFF00:0x0001` |
| Input/output report size | 64 bytes / 64 bytes |
| Serial number | none exposed |

The bundled 2.4 GHz receiver enumerates as `0x0B05:0x1A07`, USB device
revision `0x0105`, with the same 64-byte vendor collection. It was connected
alongside the wired keyboard for the closed-loop tests below.

DeskMux's existing ASUS inspector is passive. It observed no vendor input
report for `Fn+8`, `Fn+9`, or `Fn+0`, and the entire vendor interface vanished
when the physical selector moved from USB to Bluetooth. Those observations
rule out synthesizing the Bluetooth shortcuts through an ordinary host key
event.

## Model-specific protocol lead

ASUS's own Dongle Pairing Tool version 1.00.12 contains an entry for this exact
wired/dongle pair and uses a 64-byte vendor protocol. The tool was inspected
offline; it was not executed and no report was sent to the keyboard.

For the older protocol selected by this model, its reversible RF-test commands
are:

| Operation | 64-byte report payload prefix | Remaining bytes |
| --- | --- | --- |
| Enter factory mode | `FA 00 D6 A5 00` | zero |
| Enter RF mode | `FA 20 04 00 00` | zero |
| Leave RF mode | `FA 20 05 00 00` | zero |
| Leave factory mode | `FA 00 00 00 00` | zero |

The pairing tool uses the RF-mode pair after creating and copying pairing data
to test that the keyboard can reach the dongle. This is evidence that the
command can activate the keyboard's 2.4 GHz radio while the physical selector
is in wired mode. It is not yet proof that normal keyboard reports are routed
over the receiver, nor that the wired vendor interface remains available for
the reverse command.

The same tool also contains commands that clear, generate, and overwrite the
keyboard/dongle pairing material. DeskMux must not implement or transmit those
commands. They are unnecessary for switching an already paired keyboard and
are the first commands in this protocol with a clear persistent-state risk.

## Risk classification

| Experiment | Persistent-state risk | Current decision |
| --- | --- | --- |
| Passive HID inventory/report capture | none | safe |
| Receiver battery/status query `12 01` | no known mutation | only after receiver inventory |
| RF enter immediately followed by RF leave, without factory mode | low; observed reversible | completed; acknowledged but did not activate receiver |
| Official factory + RF connection-test sequence | medium; intended by ASUS but temporarily changes both device modes | completed once; receiver reported RF connection success and cleanup passed |
| Pairing read | exposes radio secrets without helping switching | do not run |
| Pairing clear/generate/write | can destroy the working dongle pairing | prohibited |
| Firmware extraction/flash | can make the device unrecoverable | prohibited on the working keyboard |

The RF-mode commands are not firmware payloads and do not address flash in the
vendor utility. The primary expected failure is temporary loss of input, not a
brick. That conclusion is an inference from the utility's control flow, not a
vendor guarantee.

## Recovery ladder

Prepare a second keyboard or use the MacBook's built-in keyboard before the
first write test.

1. Keep the keyboard's physical selector in the center wired position.
2. If input or the vendor interface disappears, unplug and reconnect the USB
   cable with the selector still centered.
3. Power-cycle the keyboard using its physical selector.
4. As a last local reset, hold `Fn+Esc` until the keyboard flashes green. ASUS
   documents this as a factory reset, so it may erase profiles or pairing and
   should not be the first recovery action.
5. If the 2.4 GHz pairing is lost, use ASUS's official pairing/update flow on
   Windows with both the cable and receiver connected.

## Staged test plan

No stage advances merely because a HID write returned success.

1. Connect the original `0x1A07` receiver to the same Mac as the wired keyboard.
   Run `swift run deskmux-agent asus inventory` to passively inventory both
   devices and their report sizes.
2. Monitor keyboard input reports separately by USB product ID to establish the
   wired baseline and prove the receiver is quiet.
3. Send only `FA 20 04 00 00`, wait at most 500 ms, then send
   `FA 20 05 00 00` through the same open wired interface. The guarded command
   is `swift run deskmux-agent asus rf-test --acknowledge-transient-input-loss`.
   It pins the observed `0x0117` keyboard and `0x0105` receiver revisions and
   records every vendor response and post-test identity check.
4. If stage 3 is acknowledged but ineffective and both interfaces remain
   healthy, repeat once with the non-pairing subset of ASUS's exact keyboard
   protocol-1.0 sequence: factory on for keyboard, factory on for receiver, RF
   on for keyboard, connection check on receiver, RF off for keyboard, factory
   off for keyboard, and factory off for receiver. All three cleanup writes are
   unconditional even if an earlier write or response fails.
5. A candidate passes only if normal key reports move to `0x1A07`, return to
   `0x1A05`, pairing survives a power cycle, and the sequence succeeds multiple
   times without changing revision or descriptors.
6. Only after the same-Mac closed-loop test passes should the receiver move to
   the other Mac for a native cross-Mac handoff test.

## Experiment log

### 2026-08-30: receiver baseline

With the keyboard selector centered in wired mode, DeskMux sent the receiver
the independently documented, non-mutating `12 01` battery/status request. The
receiver returned no response. This is the expected quiet baseline while the
keyboard radio is inactive.

### 2026-08-30: RF enter/leave without factory mode

The guarded stage-3 command sent exactly two 64-byte output reports to the
wired vendor interface:

1. `FA 20 04 00 00` followed by zeroes (enter RF mode)
2. `FA 20 05 00 00` followed by zeroes (leave RF mode)

Both writes returned `kIOReturnSuccess`, and each command produced the same
64-byte vendor acknowledgement: `FF AA` followed by zeroes. While between the
two commands, the receiver did not answer the `12 01` status query. After the
leave command, both exact devices still exposed all four expected interfaces
with unchanged revisions (`0x0117` wired, `0x0105` receiver). A second
receiver-status query was again silent.

Result: the keyboard recognizes both RF-mode opcodes, but RF enter alone is
insufficient to activate the receiver path. This is a clean negative result,
not a transport or device-identification failure. The next justified test is
the pairing utility's factory-mode wrapper around the same RF enter/leave pair.
Offline reinspection confirmed that ASUS puts both the keyboard and receiver
in factory mode and issues `FA 20 06 00 00` to check their RF connection. The
guarded reproduction omits every pairing read, clear, generate, and write
operation. It has higher transient-state risk and requires a separate explicit
approval.

### 2026-08-30: factory-wrapped RF connection test

After explicit approval, DeskMux sent the exact seven-report non-pairing
sequence described in stage 4. All seven `IOHIDDeviceSetReport` calls returned
`kIOReturnSuccess`. Each device echoed every command addressed to it. Most
importantly, the receiver answered the connection check with:

```text
FA 20 06 00 01 00 00 ...
```

Byte 4 is `01`, which is the exact success condition checked by ASUS's
protocol-1.0 pairing utility. This proves that the already-paired keyboard's
2.4 GHz radio can reach its receiver while the physical selector remains in
wired mode. No pairing material needed to be read or changed.

All cleanup commands were acknowledged. Immediately afterward, all eight
original HID interfaces remained present with their original registry IDs and
USB revisions, and the receiver returned to the same silent `12 01` status
baseline. The keyboard continued to work over USB. The remaining central
question is whether ordinary keyboard reports move to the receiver during this
temporary RF mode; ASUS's connection response alone does not prove that.

For that proof, the earlier userspace callback monitor was replaced with a
read-only sampler of macOS's kernel `InputReportCount` field. In a two-second
idle wired baseline, the active wired keyboard interface advanced by 25
reports while both receiver keyboard interfaces had no counter. A guarded
follow-up can hold the already-tested factory/RF state for at most 15 seconds
while sampling only these counters; it stores no report bytes or key values.

### 2026-08-30: normal input-path test during RF connection

During an explicitly approved 15-second factory/RF window, the user repeatedly
tapped a letter key. The receiver again reported `FA 20 06 00 01`, proving the
radio connection was active. Kernel input-report counters changed as follows:

| Path | Before | After | Delta |
| --- | ---: | ---: | ---: |
| Wired keyboard, 8-byte input interface | 26943 | 27009 | +66 |
| Wired keyboard, 15-byte input interface | unavailable | unavailable | 0 observed |
| RF receiver, 8-byte input interface | unavailable | unavailable | 0 observed |
| RF receiver, 15-byte input interface | unavailable | unavailable | 0 observed |

Therefore normal key reports continued on the wired USB path. The factory/RF
sequence is a radio connection diagnostic used by the pairing utility and did
not demonstrate an exclusive native host switch. Receiver delivery was unknown
because its counters were unavailable (see the 2026-09-04 audit above).
Cleanup again passed, all interfaces and revisions remained
unchanged, the receiver returned to its silent baseline, and the keyboard
continued to work. An identical repeat with the same unvalidated measurement
would not resolve receiver delivery.

## Offline ASUS HAL analysis

The official ASUS Keyboard HAL package was downloaded from ASUS's current
Armoury Crate distribution, decrypted and unpacked without executing any of its
Windows binaries. The WiX manifest identifies the package as ASUS Keyboard HAL
`1.2.97.0`; the extracted 64-bit `AacKbHal_x64.dll` has SHA-256
`f85c4b98f14d85ecb688512b091fe14c3162b3272f01b26ffea055df88b37a6e`.
The embedded CAB and all four payloads matched the sizes and SHA-1 values in
ASUS's signed installer manifest.

The HAL provides unusually strong model-specific evidence:

- Its USB transport table contains both exact endpoints, vendor/product
  `0x0B05:0x1A05` and `0x0B05:0x1A07`, with the same vendor HID usage used by
  the live tests.
- The exact product string `ROG STRIX SCOPE RX TKL WIRELESS DELUXE` maps to
  ASUS's internal `AacX807` device class. The construction path uses internal
  device ID `0x1A09`; this is distinct from the two external USB product IDs.
- Run-time type information proves that the model-specific helper is
  `AacX807Function`. Its five-entry virtual interface resolves to the RF-remake
  implementation's input-event initialization, secondary-interface event
  initialization, key-event handling, device-info query, and connection-status
  query.
- The model's device-info/status path constructs read/query reports including
  `12 00` and `12 03`. Its event path also contains the documented BLE-host-LED
  operation (`51 41`). There is no transport-selection method in the exact
  model helper, no report builder named or shaped like a wired/RF selector, and
  no alternate selector in the `AacX807` class vtables.
- A function named `SwitchWDL` exists only in a newer RF-remake extension class
  not instantiated by `AacX807`. It builds a different `73 00 00 00 xx` report
  and belongs to the HAL's lighting/device-mode path; it is not evidence of a
  wireless transport switch and must not be tried on this model.
- The HAL contains no firmware image, bootloader/DFU routine, or firmware
  updater. ASUS distributes firmware through a separate dynamic Armoury Crate
  update flow, so the installed HAL cannot be used to obtain a safe firmware
  dump or a vendor-supported selector command.

This closes the official host-software lead: ASUS's own current model branch
can inspect RF connection state while the cable is attached, but it does not
offer a command that changes the normal HID input route. Combined with the
live negative input-path test, the evidence points to the physical selector
being authoritative inside keyboard firmware.

Further firmware work would require obtaining and reverse engineering the
separate signed updater/image or extracting firmware from the device. No
readback protocol has been identified, and guessing bootloader or flash
commands on the working keyboard is outside the acceptable risk boundary.

## Bluetooth host slots

ASUS documents Bluetooth host selection for this exact model as an on-keyboard
firmware action: put the physical selector in Bluetooth mode, then use
`Fn+8`, `Fn+9`, or `Fn+0` for paired device 1, 2, or 3. The quick-start guide
also says the selected number key remains lit white and that Armoury Crate can
disable that light. ASUS excludes `Fn` from the keyboard's programmable keys.
Consequently, an operating-system-generated `8`, `9`, or `0` key event cannot
recreate this chord: normal HID key traffic travels from the keyboard to the
host, and `Fn` is consumed locally by the keyboard firmware.

The exact `AacX807_BLE` branch in ASUS Keyboard HAL 1.2.97.0 was inspected for
a separate software selector. Its `SetFunction` dispatcher supports function
ID `0x15`, named `SetBLEHostLED`, and its `GetFunction` dispatcher supports ID
`0x16`, named `GetBLEHostLED`. These initially looked like possible host-slot
controls, but their implementations settle the distinction:

| HAL operation | BLE report | Effect represented by ASUS |
| --- | --- | --- |
| `SetBLEHostLED` | `51 41 00 00 <value>` | enable/configure the white selected-slot key light |
| `GetBLEHostLED` | `12 06 00 00 ...` | query that indicator setting |

There is no `SetBLEHost`, `SwitchBLEHost`, channel/slot selector, or pairing
selector in the exact model class, its two-method `AacX807Function_BLE`
helper, or the generic BLE function strings. The remaining BLE calls cover
device information, connection status, power, profiles, key configuration,
lighting, and input-event initialization.

This means Bluetooth does not provide a known safe software-switching path.
While connected over Bluetooth, a host can configure supported vendor
features, but ASUS exposes only the indicator LED—not the firmware action
behind `Fn+8/9/0`. In Bluetooth selector mode the wired vendor HID interface
also disappears, so the USB-connected Mac cannot act as an out-of-band control
path. No Bluetooth vendor report was transmitted during this analysis; trying
`51 41` would only alter the documented indicator and would not test host
selection.

## Armoury Crate package and updater analysis

### September 5 breakthrough: exact firmware acquired

Installed official Armoury Crate bootstrapper 3.3.6.0 in the isolated ARM VM.
Windows validated its ASUSTeK Authenticode signature. The Store supplied
Armoury Crate 6.5.14.0 **arm64**, and ROG Live Service 3.5.11.0 installed and ran.
This corrects the earlier assumption that all relevant ASUS components were
x86/x64: the newly downloaded service includes native ARM64 plugins. The app
completed service setup and requested a restart; no keyboard was passed through.

Copied `C:\Program Files\ASUS\ROG Live Service\Plugins\RLSDownload.dll`
to `.build/asus-research/windows-live/`. Its exported `GetProfile` accepts an
MSVC vector of pairs of UTF-16 strings plus a detail flag, and returns a
thread-local UTF-16 JSON string. Confirmed ABI by ARM64 disassembly: export RVA
`0x1ea58`, profile implementation `0x2f948`, vector copy `0x3d730`, request
builder `0x32900`. The query `id=14161` with detail=1 returned exact firmware
metadata; `id=14162` returned the receiver metadata. No update/install export
was called. The VM's bundled PowerShell runs x64; used Microsoft-signed portable
PowerShell 7.6.5 ARM64 to load the ARM64 DLL. The reproducible query wrapper is
`.build/asus-research/windows-live/get-profile.ps1`.

Downloaded and hash-verified both official archives on macOS:

- Keyboard: `https://dlcdn-rogboxbu2.asus.com/pub/ASUS/APService/Gaming/SYS/ROGS/14161-3BQO6Z-dc3ca9eb0ad88717a5959f3d124d3437.zip`
  SHA256 `693fcafc6a521791c364b482fde9dce62afff1f699c44cc18f8589359da28afe`.
- Receiver: `https://dlcdn-rogboxbu2.asus.com/pub/ASUS/APService/Gaming/SYS/ROGS/14162-W6N3U1-459d67a20bfbaf6db8468cce68dfc130.zip`
  SHA256 `6d7400c083dd2312718d39b26ef0e8597f8e1f2877aa4dc312f06af222831c62`.

Archives, JSON provenance, extracted files, and query helpers are under
`.build/asus-research/windows-live/`. Actual images are
`keyboard/FW_Update_Tool_X807_Kb_v124203/FW/X807_KEYBOARD_V12_42_03.bin`
(487424 bytes) and
`receiver/FW_Update_Tool_X807_Dongle_v20005/FW/X807_DONGLE_V02_00_05.bin`
(30720 bytes). Firmware updater executables have **not** been run.

Initial offline analysis:

- Keyboard image begins with a Cortex-M vector table at flash base `0x08000000`;
  another valid vector table at file offset `0x6000` identifies the application
  reset vector `0x080061a1`. Later image content includes TI SYS/BIOS strings,
  so the complete package should not be assumed to be one contiguous program.
- Receiver header is consistent with an 8051-family vector table (`LJMP`
  opcodes at reset/interrupt slots); exact silicon still unconfirmed.
- Keyboard application has readable diagnostic strings: `USB mode` at file
  `0x10598`, `Fake USB mode` at `0x105b0`, `RF mode` at `0x105c0`, `BT mode` at
  `0x105c8`. Mode-selection routine starts `0x08010490` and accesses packed
  flags at RAM `0x200002a4`. Physical switch/debounce routine `0x08008a84`
  reports `RF sw change`, `BT sw change`, and `mode change`.
- Vendor dispatcher starts `0x08006a04`; the `0xFA` branch reaches
  `0x08007344`. Factory entry recognizes `0xa5d6` and sets flag bit7; other
  factory commands are gated on that bit. The known `FA 20` family is forwarded
  by `0x0800756e` through `0x080174f4`, explaining why RF diagnostic handling
  must also be traced in the radio image. This is preliminary static analysis,
  not evidence that a host-accessible transport override exists.

Next: trace writes to the mode flags and paths from the vendor dispatcher to
the physical/Fn transport handlers. Do not infer an executable test payload
from strings alone, and do not run firmware updaters to investigate switching.

Windows is not required to inspect Armoury Crate. ASUS's current bootstrapper,
the approximately 5.07 GB official full-install archive, its 227 MB Core split,
and the current live loader were downloaded from ASUS and unpacked statically
on macOS. None of the Windows executables was run. The decrypted Core archive
has SHA-256
`4df7272449e9deffd807335bc49c9e6e275b0a5536bb7949b61ba2d07760d406`;
the encrypted live-loader download has SHA-256
`bb895dfa6618d6deb7e4440bb16d881785b2ad9c8dcad20e8d7c0bc51b3e66c9`.

The Core manifest maps all three exact transport identities to separate
Armoury UI packages:

| Transport | USB product ID | ASUS UI package |
| --- | --- | --- |
| wired | `0x1A05` | `15996-2K6U28-ded963f5655574b2aeef72b32a31b4e8.zip` |
| 2.4 GHz receiver | `0x1A07` | `15998-ZJ6JGN-f97b515771ba191734127dd3fe99fae4.zip` |
| Bluetooth | `0x1A09` | `15997-BXHZVR-97c5203b40b74709d785c3bd4c781614.zip` |

The generic keyboard plug-in exposes profile, key, lighting, power, host-LED,
and firmware-update functions. It contains no transport or Bluetooth-slot
selector. A separate Omni Receiver plug-in does have pairing and a
`SWITCH_BUTTON` feature, but it is for ASUS's newer multi-device Omni Receiver
and does not target this keyboard's `0x1A07` receiver.

The same official manifest identifies two exact firmware update packages:

| Target | Published version | Update tool | Package |
| --- | --- | --- | --- |
| keyboard `0x1A05` | `12.42.03` | `FW_Update_Tool_X807_Kb.exe -s` | `14161-3BQO6Z-dc3ca9eb0ad88717a5959f3d124d3437.zip` |
| dongle `0x1A07` | `2.00.05` | `FW_Update_Tool_X807_Dongle.exe -s` | `14162-W6N3U1-459d67a20bfbaf6db8468cce68dfc130.zip` |

Those firmware archives are deliberately absent from the offline full-install
bundle: its setup configuration excludes `Firmware` and `New Firmware`.
Firmware is resolved dynamically by ROG Live Service. Static extraction of
that official service confirms separate firmware categories, profile-detail
requests, short-lived authorization, signed download handling, and explicit
firmware installation/recovery states. It does not expose a reusable unsigned
CDN path in clear text. ASUS's public support API currently returns no driver
payload for this model, so the public support page is not an alternate firmware
source.

The remaining useful role for Windows is therefore narrow: run Armoury Crate in
an isolated VM to observe the live metadata requests and retrieve the exact
signed packages. Start with no USB passthrough, do not select Install or Update,
and capture only network/file activity. Passing through the keyboard and
receiver is justified only if the updater refuses to enumerate the model
without hardware; even then, package discovery must stop before any update
command. Once obtained, the UI and updater packages can again be analyzed
offline on macOS. Wine is a worse fit because this software installs privileged
Windows services and drivers and provides less faithful isolation.

This workstation is an Apple M1 Ultra, so its local VM option is Windows 11
Arm64. Windows 11 can emulate x86/x64 user-mode applications, but it cannot
emulate x86/x64 kernel drivers. The extracted ASUS packages contain x86/x64
HAL and driver payloads, not Arm64 equivalents. A local Arm VM may therefore be
enough to observe the bootstrapper or downloader, but it is not a reliable
environment for hardware enumeration. If USB passthrough becomes necessary,
use an x86-64 Windows machine or VM host rather than interpreting an Arm-driver
failure as evidence about the keyboard.

## Linux and public custom-software survey

No public project found in an exact-model, exact-PID, or ASUS HAL-class search
implements wired/RF transport switching or Bluetooth host-slot switching for
this keyboard.

- OpenRGB recognizes wired PID `0x1A05`, but its exact-model implementation is
  an ASUS Aura USB lighting controller only.
- Linux's `hid-asus` driver contains generic ASUS HID quirks and laptop hotkey
  handling; it has no `0x1A05`/`0x1A07` transport state machine.
- The exact-model Linux workaround found publicly changes receiver power/wakeup
  handling to avoid suspend problems. It does not send a switch command.
- The public ASUS pairing utility and battery monitor remain useful protocol
  references, but neither implements switching. The pairing utility's RF mode
  is the diagnostic already disproved by the normal-input-path test above.

Generic multi-host BLE keyboard firmware projects demonstrate that software
slot switching is technically possible when the firmware is designed to
expose it. They do not establish an equivalent command in X807 firmware. The
absence of a public Linux implementation is not proof that no hidden opcode
exists, but it removes the best low-risk source of an independently tested
payload.

## Sources and provenance

- [ASUS's product page](https://rog.asus.com/us/keyboards/keyboards/compact/rog-strix-scope-rx-tkl-wireless-deluxe-model/)
  and [official specification](https://rog.asus.com/us/keyboards/keyboards/compact/rog-strix-scope-rx-tkl-wireless-deluxe-model/spec/)
  establish the tri-mode hardware, the three `Fn+8/9/0` Bluetooth host slots,
  Bluetooth 5.2, the non-programmable `Fn` key, Windows-only Armoury Crate
  support, and the cable-plus-dongle update topology.
- [ASUS's exact-model quick-start guide](https://dlcdnets.asus.com/pub/ASUS/Accessory/Keyboard_Mouse/ROG_STRIX_SCOPE_RX_TKL_WIRELESS_DELUXE/Q20898_X807_ROG_STRIX_SCOPE_RX_TKL_QSG_V4_WEB.pdf)
  documents the white selected-host key indicator and says Armoury Crate can
  turn it off, distinguishing the HAL's host-LED setting from host selection.
- [ASUS's exact-model support page](https://rog.asus.com/us/keyboards/keyboards/compact/rog-strix-scope-rx-tkl-wireless-deluxe-model/helpdesk_download/)
  is the public entry point for Armoury Crate and model support. Its current
  driver API returns no downloadable firmware entry for X807.
- ASUS's official full-install package is published as
  [Armoury Crate Full Installation Package](https://dlcdnets.asus.com/pub/ASUS/mb/14Utilities/Armoury_Crate_Full_Installation_Package.zip),
  and the signed bootstrapper retrieves the live loader from ASUS's
  `liveupdate01s.asus.com` service.
- ASUS official support documents `Fn+Esc` as the reset operation for this
  model family.
- [OpenRGB](https://openrgb.org/devices_0.9.html) identifies `0x1A05` usage
  `0xFF00:0x0001` and uses only the lighting command family for this model.
- [Linux's `hid-asus` driver](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-asus.c)
  has no exact-model switching support. The public
  [X807 receiver workaround](https://gist.github.com/jnettlet/afb20a048b8720f3b4eb8506d8b05643)
  addresses erroneous sleep/power events rather than transport selection.
- ASUS forum reports independently identify the current X807 keyboard firmware
  as [`12.42.03`](https://rog-forum.asus.com/t5/gaming-keyboards/rog-strix-scope-rx-tkl-wireless-deluxe-2-4ghz-rf-connection/td-p/1047790),
  matching the extracted official manifest.
- ASUS Dongle Pairing Tool 1.00.12, redistributed in the
  `GG-GhostGaming/Asus-pairing-utility-tool` research repository, identifies
  the exact `0x1A05`/`0x1A07` pair and supplied the RF-test state machine above.
- `JKWTCN/BatteryMonitor` independently validates the receiver identity and the
  non-mutating `12 01` receiver status query.

Protocol discovery was performed offline. Hardware testing has now completed
the low-risk RF toggle and one factory-wrapped connection test. Four transient
factory-mode commands were transmitted and acknowledged. No pairing or
firmware command has been transmitted. The current official ASUS Keyboard HAL
was also unpacked and inspected offline; none of its Windows code was executed.

## Firmware transport reachability follow-up — 2026-09-05

Offline analysis of the official keyboard `X807_KEYBOARD_V12_42_03.bin`
(SHA256 `5ee4e39b9d1ccd4509c2957546e60e198967a78ad057c0505b1910860c18b064`)
identified the following paths. Addresses are Thumb flash addresses with base
`0x08000000`. These findings concern the downloaded version, not necessarily
all code in the currently installed revision. No hardware commands or flashes
were performed in this follow-up.

- `0x08017bd8` samples active-low GPIO selector inputs and updates bits 17
  (RF) and 18 (Bluetooth) of the flags word at `0x200002a4`. These are physical
  selector state, not persistent software preferences.
- `0x08010490` classifies the active mode using those inputs, cable state
  (bit 9), and additional configuration. Active RF, Bluetooth, USB and
  “Fake USB” are bits 10, 11, 12 and 13 respectively. This routine does not
  clear every active-mode flag at entry; its surrounding lifecycle matters.
- `0x08008a84` resamples and debounces the physical selector. Consequently,
  merely finding a RAM mode flag does not establish a durable override.
- `0x080090f4` copies the physical RF/Bluetooth choice into the active flags.
  The direct caller located is `0x08012858`, in a local-key action handler.
- Local action 10 at `0x08012818` toggles classification bits 25:26 between
  1 and 2, persists setting 5, and calls that copy routine. Embedded labels
  at offsets `0x10580`, `0x1058c`, and `0x105a4` are `DM_Inactive`,
  `DM_Wired`, and `DM_Wireless`. This is a **demo-mode toggle candidate**,
  not yet an established general-purpose software transport command.
  No producer of pending action 10 has been established. Candidate stores
  at `0x08011b4e` clear the action; a halfword-scanner hit at `0x08013d2e`
  was inside a different instruction. The branch could be dormant in this
  model or have an indirect trigger; neither is proven.
- Local action 9 handles Fn+8/9/0 slots. It updates the slot at `0x20002825`,
  persists it, and calls `0x080128f4`. That function sends five bytes
  `[0x91, slot, 0, 0, 0]` on internal radio channel `0x35`, only when the
  active Bluetooth flag is set. **This is an internal processor packet,
  not a discovered USB HID command.** Its only direct caller located is
  the local-key slot handler at `0x08012812`.
- USB dispatcher `0x08006a04` implements `12 03` as a mode query returning
  0 USB, 1 RF, 2 Bluetooth, or FF none. The reviewed paths do not expose
  the internal slot sender. `FA 20` forwards a factory packet to internal
  channel `0x34`, consistent with the prior unsuccessful RF diagnostic.
  `51 41` remains an LED setting, not host selection.
- USB opcode `7B` with its magic sequence leads into reset/bootloader code;
  `FD 00` also branches into that reset region. Neither is a transport
  experiment candidate.

Reproduction: `Scripts/asus-research/firmware-evidence.py` verifies the binary
hash and prints selected disassembly blocks. Run with
`PYTHONPATH=.build/asus-research/python python3 Scripts/asus-research/firmware-evidence.py`.
The current output is `.build/asus-research/windows-live/transport-evidence.txt`.
Literal pools and jump tables can decode as instructions; selected output is
supporting evidence, not a complete control-flow graph. Direct-call scans do
not exclude indirect calls, aliased stores, or other processor images.

The actionable next target is the producer of local action 10 or a USB path
into the internal Bluetooth slot sender. Until reachability is established,
there is no justified new switching payload to test on the keyboard.

### Demo-action producer and remapping audit

The follow-up literal-reference scan of offsets `0x6000..0x19000` located
11 PC-relative loads into `0x200027c4..0x200027e3`; all load the state base
`0x200027c4`. They belong to the local Fn handler, its input accumulator,
and its reset/timer paths. No direct USB reference to this state was found.
`Scripts/asus-research/firmware-action-xrefs.py` reproduces this candidate
list with the same firmware hash guard. This scan is not an alias analysis.

Manual decoding of the Fn handler's jump tables and stores gives:

| Input/path | Pending action |
| --- | --- |
| Fn+1 through Fn+6 | 1 (profile argument 1..5,0) |
| Fn+7 | 8 (pairing path) |
| Fn+8/9/0 | 9 (Bluetooth slot argument 0/1/2) |
| Fn+left/right | 2 |
| Fn+Esc | 6 (reset path) |
| Release/timer cleanup | 0 |

None of these writes 10. The rest of the inspected Fn branches perform
lighting, Fn lock, Windows-key lock, or output-key operations directly.
The demo handler is therefore a dormant-code candidate, not a newly found
keyboard shortcut. No proposed shortcut should be tried based on this table;
it includes pairing and reset operations unrelated to the investigation.

A straightforward remapping route is also excluded by the reviewed paths:
`0x08012126..0x08012130` obtains the Fn dispatch usage from the fixed flash
table at `0x08018622`. USB `51 20`, at `0x08006e78..0x08006ef6`, instead
uses that table to index remapped output halfwords in RAM based at
`0x200011f4 + 0xca`. Changing that output mapping does not change the flash
usage read by the Fn handler. This establishes separation of those two
paths, not a proof about every possible macro or indirect event source.

Status: no normal Fn producer or direct USB trigger for action 10 found.
The next distinct approach would require fuller control-flow/alias analysis
or offline emulation of USB configuration writes; repeating the same key or
RF diagnostic tests has no new supporting evidence.

### Offline USB dispatcher emulation

`Scripts/asus-research/emulate-usb-handler.py` now executes the actual Thumb
USB dispatcher in Unicorn, with firmware hash verification and synthetic RAM.
It records writes to the mode flags and pending-action byte, and records
external calls. It models memcpy/memzero; other callees return zero without
executing. It never accesses a USB device. Dependencies are installed under
`.build/asus-research/python`; invoke with that directory in `PYTHONPATH`.

The sweep contains 1,034 cases: all 256 `51` subcommands with zero parameters
under four flag states, plus configuration record indices 0..9 with a small
nonzero payload. 1,023 cases return; 11 fault on null configuration pointers
because firmware startup/data initialization is not yet modeled. None writes
the pending-action byte or mode flags on the paths executed. Recorded external
call targets are `6250`, `787a`, `78ba`, `113c8`, and `12f4c` (flash-relative).
Their unmodeled side effects remain outside this result.

Four controls return successfully. Factory-on changes flags `1000 -> 1080`;
factory-off changes `1080 -> 1000`; the selected key-remap and mode-query
controls leave watched state unchanged. Assertions enforce those controls.
An initial harness run omitted the dispatcher's distant epilogue at `7874`
and hit instruction limits; the allowed execution range was corrected and
the final artifact regenerated. Those initial results are not used.

Raw final results: `.build/asus-research/windows-live/usb-emulation.json`.
Compact output: `.build/asus-research/windows-live/usb-emulation-summary.json`.
The 11 failures are specifically the `51 2c` indexed-record copy path; these
are harness initialization gaps, not observed keyboard faults. A follow-up
literal-reference audit identifies the RAM configuration table at `200001bc`,
but its startup population is not yet reconstructed. Completing that data
initialization and executing selected downstream callees is necessary before
making any stronger reachability claim. The sweep does not cover arbitrary
payloads, persistent state sequences, or full firmware behavior.

### Startup data reconstructed; incomplete cases resolved

The preceding zero-RAM limitation is now resolved for C runtime initialization.
The reset path enters the scatter loader at `0800631c`. Its table at
`08019468` has two entries:

- Source `08019488`, destination `20000000`, length `4b8`, decompressor `08006340`.
- Source `08019708`, destination `200004b8`, length `37a0`, initializer `08017868`.

The harness executes the actual loader and stops at `08006194`, before
application startup. This reconstructs the pointer table at `200001bc` as:
`200011f8, 20001206, 20001214, 2000126c, 20001222, 20001247, 2000127a,
20001288, 200012a2, 200012b0`. These are firmware-derived addresses, not
invented stand-in buffers. All ten point away from the hidden action state.

All 1,034 sweep cases now return with no faults. The harness also executes
configuration callback `08006894` and helpers `08012f4c`/`08012fd0`, rather
than stubbing them. The callback reads GPIO at `48000414`; the GPIO page is
explicitly modeled as zero memory, not a measured hardware state. With that
model, all cases still return, none writes the watched flags/action state,
and all four original controls pass. The remaining recorded external calls
are `08006250`, `0800787a`, `080078ba`, `080113c8`, and `080149d8`.

The raw JSON and summary paths above now contain this newer run. Results
still concern selected individual packets under four synthetic flag states;
application initialization, realistic GPIO values, other callees, multi-packet
configuration sequences, and arbitrary payload coverage are not established.
This closes the specific uninitialized-pointer gap without establishing the
absence of all possible software switching paths. No live keyboard commands
were sent during this work.

### Shared callback and stateful configuration sequences

The shared callback at `080149d8` is consistent with lighting-effect state
management, not an additional transport selector. It clears arrays in a
lighting-state structure, dispatches effect IDs 0..9, and finishes through
`080091a0`, which writes three-byte RGB values into indexed buffers. The
`FA` argument used by the demo-mode branch maps via the TBB at `08014a34`
to `08014b22` (common cleanup), not a special transport routine. Thus the
shared call does not itself provide the missing USB-to-demo activation link.
This interpretation is based on static code and buffer operations; the
callback remains stubbed in the dispatcher harness because its application-
initialized lighting pointer is not populated by the C runtime loader.
Selected disassembly is now included in `firmware-evidence.py` output.

The dispatcher harness now accepts a prior RAM snapshot and returns updated
RAM. `Scripts/asus-research/emulate-usb-sequences.py` uses it to test 60
sequences / 210 packets: ten configuration records under three transport
flag states, with and without a factory-on/off wrapper. Each sequence writes
an initial record with a brightness-byte variation to 25, then queries mode.
The record lengths are read from the firmware table: 14 bytes for ordinary
records, 37 for indices 4/5, and 26 for index 7. Indices 4/5 use part order
2,1,0 (14+16+7 bytes); index 7 uses 1,0 (14+12 bytes). RAM persists between
packets, including the part counter and factory flag.

All sequences return, all resulting record bytes match the intended data,
and final mode flags equal initial flags with action byte zero. Assertions
check completion, byte-for-byte record matches, and final watched state.
Raw results are `.build/asus-research/windows-live/usb-sequences.json`.
The original single-packet sweep and four controls were rerun after the
harness change. All previous modeling limits remain: no application main
loop, no real GPIO state, no full lighting callback execution, and no claim
of coverage for arbitrary payloads or all possible command sequences.
These results close the tested multipart-configuration route; they do not
establish that software switching is universally impossible. No hardware
commands were transmitted.

### USB-to-radio forwarding boundary audit

Five direct dispatcher calls to radio enqueue `080174f4` were identified:
`0800752e` (FA 05, 4 bytes), `08007574` (FA 20, 5 bytes), `080075e6`
(FA 21, 6 bytes), `0800760e` (FA 22, 4 bytes), and `0800763c` (FA 23,
7 bytes, parameter magic 9f7b). Every site loads channel `34` as an immediate
and forwards from the start of the FA report, preserving its opcode/subcode.
This is not a raw USB payload-to-Bluetooth-channel bridge. FA 23 is recorded
for offline analysis only, not proposed as a hardware experiment.

The enqueue routine accepts only channel 34 or 35, chooses a separate queue
by subtracting 34, checks busy/capacity, and copies the supplied bytes. The
Bluetooth slot routine `080128f4` instead builds `[91, slot, 00, 00, 00]`
and selects channel 35. Other direct channel-35 call sites build fixed
internal command headers, including 94, 90, 93, and 8a. No reviewed direct
USB forwarding site lets the host choose channel 35 or replace the FA header.
A direct-call scan is not a complete indirect-call analysis.

`Scripts/asus-research/emulate-radio-forwarding.py` captures arguments and
payload bytes at enqueue, without executing the queue or touching hardware.
804 selected cases completed: every low parameter byte for FA 20 under three
flag states, plus selected parameters for FA 05/21/22/23. They produced 536
captured packets, all on channel 34 and all retaining the FA header. Three
positive controls execute the real local slot function for slots 0/1/2;
all produce the expected five-byte 91 packet on channel 35. Assertions check
completion, channels, headers, and exact control packets. Raw evidence:
`.build/asus-research/windows-live/radio-forwarding.json`.

The harness now supports choosing a function entry point for these controls
and records radio enqueue arguments. The original dispatcher controls and
stateful configuration sequences were rerun after that change.

Conclusion is limited to this boundary: the reviewed forwarding handlers do
not directly expose the Bluetooth slot packet. It remains possible that the
receiving radio processor interprets an FA diagnostic subcommand as another
operation; that processor's parser has not been traced here. A fresh test of
arbitrary FA parameters is therefore not justified by these results. No live
keyboard command was sent.

### Radio image and receiving FA parser located

The package contains another Cortex-M image beginning at file offset `1f000`,
mapped to radio address zero. Its vector starts SP `20014000`, reset `2af81`.
At package offset `49f80` (= `1f000 + 2af80`), the reset code explicitly
loads SP `20014000` and calls `2a715`, corroborating the mapping. All addresses
below are **radio-local**, not main-MCU addresses.

The receive framing code at `1569e..156f4` distinguishes channels 30..35.
Channel 34 expects a length field of 15 hex, while channel 35 expects 6.
The FA parser at `15a36` checks the payload header and dispatches only
subcommands 05,20,21,22,23. This matches the five main-MCU forwarding sites.
FA20 accepts only word parameters 0..5 (larger values go to cleanup):

- 0 branches on the following byte (1 calls `123bc`, 2 calls `16b88`).
- 1 calls `125fe` with zero arguments.
- 2 builds a response using data read through `123c2`.
- 3 goes straight to cleanup.
- 4 sets bit 1 of a radio state byte and invokes `12340`.
- 5 clears that bit if set, calls `1378`, writes 1 to `4320057c`, and spins.
  This is a reset-request path, consistent with leaving a test state.

FA21 controls additional state bits and parameters, posts events and/or starts
workers; its disable paths also use that reset-request pattern. FA22 toggles
bit 7 with worker/event/reset paths. FA23 passes its trailing parameters to
`125fe`. These are not direct jumps into the Bluetooth slot handler.

The separate internal-command parser at `15d3c` recognizes 88,89,8a,90,91,
etc. The 91 branch at `15fec` stores its argument into `2000172c` and posts
event `200` through the handle at `20001730` via `6878`. The FA dispatch has
no direct translation into this branch. However, `12340` constructs an
asynchronous worker through `d18`, and FA21 posts other events. Those worker
bodies/event consumers have not all been traced. Therefore the supported
answer is **no direct FA-to-slot translation in the receive parser**, not a
proof excluding every asynchronous mode effect.

Reproduce selected disassembly with
`Scripts/asus-research/radio-parser-evidence.py`; output saved as
`.build/asus-research/windows-live/radio-parser-evidence.txt`. The script
checks the full package binary hash and vector mapping. No live commands,
radio resets, or firmware updates were performed in this follow-up.

### Asynchronous worker follow-up and FA05 correction

Resolved the three task entry pointers passed by `12340` to task creation
`d18`: `13768`, `13be4`, and `13c6c`. Selection depends on radio state bit 5,
bit 7, and a configuration byte at an object offset 8e. `13be4` repeatedly
calls `12e00` and waits on event bit 0; the two larger entries initialize
radio buffers, timers and worker state. FA21's `1718e` constructs another
task. Their full transitive behavior remains incompletely analyzed; merely
identifying their entry points is not sufficient to label every effect.

A material correction to a too-broad interpretation of the preceding result:
**some FA commands do write the Bluetooth slot variable.** FA05 (and FA20
parameter 0 with trailing byte 2) calls `16b88`. This routine writes slot
`2000172c` successively as 0,1,2,0, calls `17704` and `176b6` for each slot,
and finishes through `17e06`. `17704` builds six per-slot bytes using repeated
calls to `1509c` and ORs the final byte with c0, then writes the record through
`17ed2`. This is consistent with regenerating Bluetooth identities and
resetting stored per-slot data, not selecting an arbitrary existing host.
It must not be used as a supposedly harmless switching test. No such command
was sent to hardware in this follow-up.

The event loop at `181c6` receives a mask including bit 9; its bit-9 branch
at `18244` sets object byte +9 to 1 and +a to 0. This provides an additional
candidate stage in event-driven processing; numeric event bits alone are
not enough to establish matching event objects. The established parser
still writes the requested slot and posts event 200 for internal opcode 91.
A literal-reference scan found the slot variable also used by storage and
connection-state routines, reinforcing that reset and connection selection
must be distinguished.

Selected new blocks are included in `radio-parser-evidence.py` and its saved
output. Current practical conclusion: no demonstrated non-destructive,
selectable host-switch command through FA. Full asynchronous reachability
has not been proven absent. Further static work needs to connect the task
objects and their downstream event consumers; repeating the already-tested
FA20 RF diagnostic is not supported by new evidence.

### Event objects connected: normal slot event versus FA21 test event

Resolved the event-object identity, rather than matching numeric masks alone:

1. Internal 91 stores the slot at `2000172c` and posts 200 to the handle
   stored at `20001730`.
2. Normal Bluetooth worker `172a4` loads object base `200016fc` into r7.
   Its receive loop at `173ec` waits on `[r7+34]`, exactly `20001730`.
3. The bit-9 branch at `173ce` passes `r7+30` (exactly `2000172c`) to
   `17e06`, then posts 200 to the handle at `2000d9c4`.
4. Main radio worker `18168` creates its event at object `2000d9b4+10`,
   exactly `2000d9c4`. Its bit-9 branch at `18244` sets +9=1 and +a=0.

This connects the previously provisional main-event branch to the actual
normal slot request. The persistence helper is identified by its use in
other stored-data paths; its complete storage implementation is not modeled.

FA21 parameter 2 can instead construct worker `17156` through `1718e` when
its state/configuration conditions choose that entry. This worker loads the
same base `200016fc`, waits on the same handle at +34, but requests only mask
`20000000` at `1717a`. That is the exact mask posted by the FA21 update branch
at `15c7c`. On this event, it calls `17094` and repeats the wait. `17094`
dispatches configuration operations through `14e84`, with parameters derived
from test configuration bytes. It does not post 200 or write the slot. The
alternative entry chosen by `1718e` is the normal worker `172a4`; simply
creating that task does not supply a requested slot or a 200 event.

Therefore the inspected FA21 asynchronous event is not an alias for the
normal host-selection event. This closes the specific event-object ambiguity
left in the prior entry. The larger RF workers 13768/13c6c and transitive
library/ROM calls still lack complete analysis; this is not a universal
absence proof. No new non-destructive selectable switching command has been
established, and no live keyboard commands were sent.

### Remaining RF worker bodies audited

Reviewed the bounded bodies `13768..13be4` and `13c6c..14158`. Both use RF
worker state at `20000fe0`; their event handle is at +b0 (`20001090`) and
RF command handle at +ac. These are distinct from the Bluetooth slot
`2000172c`, Bluetooth event `20001730`, and main radio event `2000d9c4`.
No direct literal reference to those switching objects occurs in either
body, and neither directly calls the established slot persistence/relay
branch. This is a bounded static result, not an alias-analysis proof.

The first worker repeatedly updates command descriptors around `200034e8`,
runs `dc30`, and examines status `5400`. Its helper `12ae8` constructs the
literal packet prefixes `PER` and `END`, supporting packet-error-rate test
behavior. The second configures transmit/receive buffers, cycles parameters,
runs `dc30`/`d61e`, and processes results through `13070`. Its explicit event
post at `1414a` sends bit 1 (mask 2) to its own event at `20001090`, not mask
200 to either switching event object.

Inspected helper examples: `12f9c` creates the RF command handle through
`d412` and stores it at worker +ac; `127be` clears test buffers/counters;
`126e8` reads configuration from flash address 54000; `13070` parses incoming
RF data and includes the previously identified FA20/06 diagnostic response.
`dc30` delegates through lower-level RF command submission/wait routines.
This audit does not fully resolve driver callbacks, ROM calls or every
transitive callee. Accordingly, absence of a hidden switching path is not
proven mathematically or by full-device emulation.

Reproduce direct-call and literal-reference inventories with
`Scripts/asus-research/radio-worker-audit.py`; saved JSON is
`.build/asus-research/windows-live/radio-worker-audit.json`. Full bounded
worker disassembly and key helpers are included in the parser evidence output.

Practical decision: close the inspected factory-command route as unsupported
for a non-destructive selectable transport/host switch. Every established
connection is to RF diagnostics, test-state configuration, or slot-data
initialization rather than the normal selectable host-switch chain. This
is a research conclusion, not a claim that all conceivable firmware routes
are impossible. No new hardware test is justified by this audit, and no
commands were sent to hardware.

### Final command-surface pass and stopping decision

`Scripts/asus-research/emulate-remaining-commands.py` executed 5,630 additional
selected cases, all returning with no harness errors. No captured radio packets
occurred. Only FA00's known factory-clear instruction wrote the watched flags,
leaving value 1000 unchanged. Results are saved in
`.build/asus-research/windows-live/remaining-commands.json` and its summary.
The scope and inherited emulation limits are recorded in the script/artifact.

The new call inventory exposed `12 13 -> 9ac4`; manual inspection at
`08006c78` confirms its settings index is hard-coded to zero. Therefore this
path cannot simply address demo setting 5. `12 12` similarly reads index 0.
These subcommands must not be confused with the independently identified
read-only status/mode queries. `12 13` performs a persistent configuration
write, and was evaluated offline only.

The investigation has reached the practical stopping point described in
`asus-keyboard-switching-conclusion.md`. No viable selectable switching path
was found. Remaining uncertainty does not amount to a concrete hardware-test
candidate. Preserve the research for new exact-model evidence; use the existing
keyboard relay for the current product rather than continuing this route.
