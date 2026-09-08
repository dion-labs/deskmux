# DeskMux motion autoresearch

The motion lab replays one natural HID-boundary recording through the real
Studio → MacBook receiver. It exists to separate measurable transport latency
from subjective pointer-shaping problems and to make every code change compete
against the same input.

## Safety invariants

- Traces contain only ordinary mouse-move samples. Keys, clicks, dragging, and
  scrolling are filtered during recording and rejected again before replay.
- Each run uses a fresh authenticated input session and retains DeskMux's normal
  receiver timeout, local escape, release-all, and pairing protections.
- A receiver echo is emitted only after the motion state has been injected.
  Sender-side `contentProcessed` timing is diagnostic only and never treated as
  end-to-end latency.
- A failed candidate is removed rather than blended into the baseline. The
  source-location acceleration heuristic from build `20260824201417` is the
  first rejected candidate: it altered only 22 of 1,781 samples and did not
  improve perceived lag.

## Acceptance gate

At least 30 sampled receiver echoes are required. A candidate reaches the
initial native-latency target when all of these hold:

| Metric | Target |
| --- | ---: |
| Echo delivery | ≥ 98% |
| Median motion RTT | ≤ 8 ms |
| p95 motion RTT | ≤ 16.7 ms |
| p99 motion RTT | ≤ 25 ms |
| Maximum motion RTT | ≤ 50 ms |

The scalar score is lower-is-better and deliberately punishes tails and loss:

`median + 2×p95 + 2×p99 + 0.25×max + 1000×lossFraction`

Passing this gate proves that transport and injection are fast enough for a
60 Hz display. It does not by itself prove that acceleration and cursor gain
feel native; those are evaluated separately from the flattened event fields and
one final blind human comparison.

## Experiment loop

1. Capture one 15-second natural movement trace with the regular bounded input
   test. Move slowly and quickly, make small corrections and large sweeps, and
   finish near the starting point.
2. State one falsifiable hypothesis and give the candidate a stable name.
3. Build/install the candidate on Studio and update MacBook when receiver code
   changed.
4. Run `Scripts/run-motion-experiment.sh <candidate>`.
5. Compare the latest score and component metrics with the best accepted run in
   `~/Library/Application Support/DeskMux/motion-research.jsonl`.
6. Keep an improvement only when repeated runs beat the baseline without
   violating correctness or safety tests; otherwise revert it and record the
   rejection here.

## Hypothesis ledger

| Candidate | Hypothesis | Result |
| --- | --- | --- |
| `tcp-original` | Encrypted ordered TCP is sufficient for all input. | Rejected: injection acknowledgements developed 100 ms–1.7 s tails. |
| `udp-latest-state` | Loss-tolerant cumulative UDP motion removes stale TCP backlog. | Kept: receiver injection remained sub-millisecond and motion no longer queued behind reliable input. |
| `udp-immediate` | The 120 Hz sender timer is adding avoidable delay. | Kept: observed delivery rose from roughly 57 Hz to 128 Hz without sender backlog. |
| `awdl-forced` | Forcing Apple peer-to-peer Wi-Fi lowers network delay. | Rejected: the scoped service record did not resolve and connections timed out. |
| `source-location-heuristic` | Source event location preserves macOS acceleration. | Rejected: affected 1.2% of samples and still felt laggy. |
| `receiver-echo-baseline` | Actual injected-motion RTT is already within one display frame. | Pending first recorded replay. |
| `receiver-latency-critical` | Preventing App Nap/background coalescing removes the forward-path bursts. | Rejected as latency fix: one improved run was followed by a 1.09 s maximum; wake assertion retained for reliability. |
| `udp-interactive-voice` | Wi-Fi QoS classification prevents best-effort UDP batching. | Kept: repeatable median 6.7 ms and 4–5× score improvement, though tails remain. |
| `udp-ack-latest` | One state in flight prevents stale catch-up trains. | Rejected: 810/1000 sends and p99 regressed to 309 ms. |
| `udp-signaling` | Signaling QoS has lower tails than voice QoS. | Rejected: median regressed to 19 ms and p95 to 192 ms. |
| `udp-interactive-video` | Video QoS avoids voice-class power-save tail behavior. | Rejected: median regressed to 27 ms and p95 to 208 ms. |
| `udp-interactive-voice-60hz` | Lower event rate avoids Wi-Fi batching while remaining display-rate aligned. | Rejected: one improved run was followed by a 1.07 s maximum. |
| `continuous-tcp-probe` | TCP remains healthy during UDP bursts, favoring a dedicated latest-state TCP channel. | Rejected: TCP stalled concurrently (p95 69 ms, max 94 ms), isolating the shared infrastructure-Wi-Fi path. |
| `multipeer-unreliable` | MultipeerConnectivity selects a lower-latency peer-to-peer path. | Rejected and removed: it selected infrastructure Wi-Fi and regressed to p95 233 ms/max 530 ms. |
| `logitech-changehost` | Let the MX Master use its own radio instead of streaming pointer motion. | Kept as a parallel mouse-only fallback: Studio discovery resolved Bolt device index `2`, ChangeHost feature index `0x0E`, three hosts, and current host `0`. |

## Artifacts

- `latest-motion-trace.json`: the reusable, motion-only source recording.
- `motion-research.jsonl`: append-only experiment ledger.
- `latest-motion-research.json`: most recent successful experiment.
- `latest-motion-research-failure.json`: most recent failed experiment.

All live artifacts are under `~/Library/Application Support/DeskMux/` and are
kept out of the repository because flattened input events can describe a user's
pointer activity.

## 2026-08-24 isolation result

The current infrastructure Wi-Fi path is the limiting layer. The final restored
`udp-latest-state` + `interactiveVoice` build measured:

| Layer | Median | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Sender submission | 0.217 ms | — | 3.16 ms |
| Receiver injection | 0.052 ms | 0.135 ms | 11.44 ms |
| UDP injected-motion RTT | 6.98 ms | 195 ms | 682 ms |
| Simultaneous encrypted TCP RTT | 7.56 ms | 940 ms | 1,340 ms |

Directional receiver timestamps show delayed packets arriving in rapid bursts.
The simultaneous TCP stalls rule out UDP framing, encryption, event sampling,
and injection as the common cause. MultipeerConnectivity also selected the same
infrastructure path and regressed, so it was removed.

The Studio link itself reports a strong signal (`-54 dBm`, noise `-92 dBm`, 866
Mb/s PHY), but the access point is using 5 GHz channel 60, which is a DFS
channel. The least-invasive next physical experiment is to configure the 5 GHz
network on a fixed non-DFS channel 36, 40, 44, or 48 and rerun the unchanged
trace. If tails remain, connect at least the Studio by Ethernet to remove one
wireless hop; a direct Thunderbolt Bridge or wired Ethernet path between both
Macs is the authoritative native-latency test.

No new input recording is needed for those comparisons:

```sh
Scripts/run-motion-experiment.sh non-dfs-wifi
Scripts/run-motion-experiment.sh studio-ethernet
Scripts/run-motion-experiment.sh wired-direct
```

## Native Logitech mouse side track

DeskMux now has a clean-room Swift HID++ implementation for Logitech
Easy-Switch. It discovers vendor control interfaces, resolves feature `0x1814`
at runtime, reads the current host, and provides a fail-closed switch command.
It does not copy implementation code from the research projects.

The Studio experiment found the MX Master 4 behind the Bolt receiver at device
index `2`. The mouse reported ChangeHost at feature index `0x0E`, three host
channels, and channel `0` as the current Studio channel. The signed background
agent can read the same state, and the menu displays it separately from the
keyboard anchor.

This path removes motion sampling, encryption, Wi-Fi, and remote event
injection from mouse movement: after a handoff, the destination receives native
mouse reports directly. Handoff itself is asymmetric. The Mac currently owning
the mouse sends it away, so the other Mac must also run DeskMux and know the
channel that returns the mouse. Switch controls remain hidden until both Macs
have identified their local return channel. Keyboard routing remains an
independent network or manual path.

Read-only development commands:

```sh
swift run deskmux-agent logitech discover
swift run deskmux-agent logitech probe
```

The guarded switch command uses zero-based Logitech host indexes, verifies the
expected current host immediately before writing, and refuses ambiguous or
stale routing:

```sh
swift run deskmux-agent logitech switch --from 0 --to 1
```

Protocol research references:

- [Logitech HID++ 2.0 documentation](https://github.com/Logitech/cpg-docs/tree/master/hidpp20)
- [LogiGate ChangeHost hardware notes](https://github.com/ashumeet/logi-gate/blob/main/HARDWARE_PROTOCOL.md)
- [logi_mx_auto_switch HID++ reference](https://github.com/omar16100/logi_mx_auto_switch/blob/main/docs/hidpp_reference.md)
- [fwupd Bolt receiver implementation](https://github.com/fwupd/fwupd/blob/main/plugins/logitech-hidpp/fu-logitech-hidpp-runtime-bolt.c)
- [hidapi macOS transport implementation](https://github.com/libusb/hidapi/blob/master/mac/hid.c)
