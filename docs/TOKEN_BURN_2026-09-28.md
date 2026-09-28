# DeskMux token burn — 2026-09-28

## Fresh reconciliation before implementation

D resumed on September 28, with sole-project ownership and the existing September22 inbox/registry authoritative. New coordination audit is qa/token-burn-2026-09-28. Current ancestor AGENTS.md retains D-only naming and packaged-release completion policy. README, development/architecture scope, physical-monitor notes, QA registry and prior journal reviewed. No standalone project VISION/JOURNAL exists; these dated ledgers carry continuity. Exclude Voxta and deprecated standalone streaming; DeskMux's existing experimental streaming remains a deferred native capability.

Git freshly fetched: main/origin/main eab3f91c4e29ea7459976fdcb9e51354c66d0682, no later product commits. Preserve inherited modifications in ReceiverSessionAcceptanceTests.swift, RuntimeEventLogTests.swift and September22 journal, plus preexisting untracked output/. Test changes replace global dispatch work with dedicated threads for deliberately blocked/deadline-sensitive fixtures; assertions/deadlines remain unchanged. Snapshot/diff/hashes: dist/qa-2026-09-28/reconciliation.json and inherited.patch.

Fresh GitHub release audit: v0.2.6 remains latest, published2026-09-22T08:02:04Z at af7ff55, uploadedZIP5,219,263/checksum receipt retained. No v0.2.7 release. Current source/plists/README say0.2.7 but package workflow is unfinished. CI35705868922 at eab3f91 failed receiver/log fixture deadlines; earlier blocking-candidate green CI is not acceptance for current source. Prior /tmp thread-test/sanitizer/build logs are now absent. Existing dist/DeskMux-0.2.7-macOS-arm64.zip5,224,366 SHA2564a574e565ab618e94a87f9bdf62e7135f84c617263e49f174935acd531db1117 is an unqualified inherited artifact, not for publication. Preserve it before fresh packaging.

Recent tasks “Fix DeskMux display app migration” and “Fix Mac display switching” supersede old live-state assumptions: user reports Studio routing was disabled and enabledSeptember28; targeted read confirms persisted DeskMux.KeepWindowsVisible=1. Read-only installed bundle metadata is0.2.1/build20260921174432 in ~/Applications, with current live app/agent observed. This is NOT a physical switching or in-memory UI acceptance test. Do not change settings, run DDC/AX probes, install, relaunch or stop services. No new product-source commits for these live-setting tasks were found; preserve current configuration.

Current Swift6.3.2 arm64macOS26 toolchain, ~50GiB free. Live shared-resource users observed with lsof; old PIDs are not reused. Heavy commands use existing resource-run.py lock. Fresh fullsuite is required for inherited changed fixtures and failed supported-CI gate; no old /tmp claim substitutes. Raw new evidence will remain under dist/qa-2026-09-28 rather than transient /tmp.

## QA audit and next milestone

Registry DM-001–056 spans happy/error/recovery/privacy/platform. Refresh full150-case suite, targeted sanitizer for log and changed receiver fixtures, supported-toolchain CI, review of preserved thread fix, and new signed artifact before completing the pending0.2.7 logging milestone. Runtime logger SHA remains the previously reviewed nonblocking best-effort implementation; contention may drop records, detail/error strings remain verbatim, no crash/partial-write durability or automatic rotation promise.

Correct stale DM-043 mapping (network/handoff now have a seam), retain DM-055partial, and distinguish changed-fixture pending acceptance from unchanged historical evidence. Native cases remain open even with routing enabled. Report fresh suite result and scoped milestone before substantive implementation; no new source edits yet.

## Exact deferred post-burn acceptance

- DM-009/010/028/029/030: coordinated real two-Mac AOC switching with separate DDC readback and visible-picture checks, MacBook inactive-HDMI access, opt-in window evacuation/restoration respecting user moves, and Your desk reopen/restart. September28 enabled preference is not completion.
- DM-003/004/005/007/032/046/050: real held key/modifier/button release, emergency/local-return, sleep/wake/network loss and native UDP pointer input on both Macs. Fake sinks/loopback do not prove CGEvent or actual peripherals.
- DM-008/020/036/048: disposable live pasteboards, echo suppression, poll timing, unsupported/oversized replacement and reconnect in both directions. Personal clipboard is not a fixture.
- DM-011/012/034/051: isolated signed installer upgrade/rejection/rollback/failure and permission retention; no replacement of running installation.
- DM-002/015/031/033: disposable login/older macOS, TCC revocation, launch-at-login, VoiceOver/keyboard/large text. Current running app left alone.
- DM-013/018: experimental DeskMux display-stream lifecycle/capture permission/receiver disconnect, only in a coordinated disposable session.
- DM-014/027/055: actual diagnostic-input privacy and Options+ behavior; schemas/escaping do not redact arbitrary detail/error strings. No home log reads.
- Site worker owns newer footer/icon integration and local release links; no website deployment authorized.

Read-only live executable check also confirms BOTH current app and agent run from ~/Applications/DeskMux.app, not workspace .build. Build/package operations can remain isolated from the active installation. No process signaled. Fresh version/asset receipt sent to requesting DeskMux/DionLabs/Dinstinct site owners; each must keep0.2.6 until actual new publication.

## Fresh baseline result and next milestone

Resource-wrapped full suite on current inherited working tree passed **150 tests in3 suites**, exit0, Swift6.3.2; raw dist/qa-2026-09-28/baseline.log. Both changed fixture files participated; no new runtime edits. Baseline and next milestone reported before substantive implementation. The next milestone is completion of the existing0.2.7 metadata logging release: targetedTSan(logs+changedreceiver concurrency), new supported-toolchainCI, fresh root fixture review, preserve inheritedartifact then build/signature/archive/metadata verification, publish and hand off actual download links. Installed0.2.1 and enabledrouting remain untouched.
