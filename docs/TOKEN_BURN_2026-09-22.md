# DM sustained-work record — 2026-09-22

## Baseline and boundaries

Baseline revision: `e9e6ac0547288b2d65f6292ff36e4905f4e316cf`. Preexisting status:

```text
?? output/
```

Preserve preexisting edits and user data. No installed application replacement, running-session restart, personal-account mutation or website deployment occurred. Synthetic/isolated automated tests do not certify hardware or account acceptance.

## Automated evidence

2026-09-22: 103 Swift tests in 3 suites passed; swift test --scratch-path .build/public-preview. Raw local logs: `/tmp/dionlabs-burn-*.log`; durable counts recorded here because temporary logs may expire. No previous test result substituted for this current-tree baseline.

## Risk-based case register

[QA_CASES.md](QA_CASES.md) is the authoritative expanded registry (DM-001–DM-035), preserving original IDs and correcting overly broad automation claims. In particular installer rejection, pasteboard echo, actual event-tap recovery and hardware acceptance are not proven by the 103-test count.

## Dedicated worker intake and checkpoint 1

2026-09-22: inspected applicable ancestor AGENTS.md, README, development scope, current sources, tests and Git. No separate vision/journal found; this ledger is the resume journal. Intake additionally contained this preexisting untracked ledger and output/; preserved both. No tracked source differences from e9e6ac0. Verified /tmp/dionlabs-burn-deskmux.log timestamp (2026-09-22 08:38 local), compilation records and 103-test completion. Reuse that baseline for unchanged source. Coordinator inbox had no pending instructions; no stop marker at checkpoint.

Milestone 1: authored comprehensive risk-based registry with exact test mappings, honest manual gaps, expected outcomes, priorities, platform/privacy/recovery cases and reproducible acceptance receipts. Next milestone: add synthetic encrypted-wire parser/replay/tamper/recovery boundary tests; no product scope expansion or live app action.

## Deferred acceptance and next checkpoint

Run mapped manual flows using synthetic data and isolated profiles; record actual device/runtime versions and outcome per ID. Never replace a physical/account gate with a unit count. Release-eligible changes require built/validated artifacts and GitHub release coordination; documentation-only baseline creates no package release. Next: finish portfolio baseline, inspect vision-defined gaps and execute a concrete milestone with impacted checks.

## Checkpoint 2 — wire boundaries and scope correction

2026-09-22: resource-wrapped targeted Swift run passed five newly drafted protocol tests (/tmp/deskmux-burn-wire-tests.log). Two input tests retained: oversized header/incomplete/coalesced framing and authentication/order rejection with sequence recovery. Three streaming tests removed immediately after coordinator inbox said D deprecated/excluded streaming. Historical registry IDs retained and marked excluded; no streaming source changed. Re-run retained tests next. README corrected to acknowledge shipped experimental AOC controls and deprecated streaming; v0.2.1 publication/asset verified using gh release view and site worker notified. No new packaged source change, install or release.

## Checkpoint 3 — clipboard fix and release slot

Root corrected scope: deprecation concerns only the separate incubation/streaming project, NOT DeskMux screen functionality. Restored DeskMux screen regression tests/registry and experimental wording. Root assigned exclusive v0.2.2 release slot and authorized validated publication; running installed app/hardware remain untouched.

Found actual privacy/recovery defect: pollPasteboard updated its generation then returned for unsupported or oversized replacements without clearing pendingLocalUpdate; reconnect observers could replay preceding text. Extracted synthetic-testable DeskMuxClipboardObservation and invalidate pending text on every newly observed generation. Startup still does not share initial clipboard; unchanged text remains resendable; remote application suppresses echo. Three new synthetic state tests cover unsupported/oversized replacement and recovery/remote suppression. This does not certify the real pasteboard or instantaneous changes inside the 150 ms polling interval.

First affected run failed compiling test macros around mutating methods (Swift Testing immutable argument expansion); moved mutations into local result variables. Full fresh suite queued via resource wrapper at /tmp/deskmux-burn-final-tests.log. Source/plist/README/CHANGELOG prepared for 0.2.2. Release build next after tests pass. No app restart, hardware interaction, personal clipboard access or Voxta work.

## Checkpoint 4 — full suite passes

2026-09-22: `python3 /Users/deathcodevision/dev/dionlabs/qa/token-burn-2026-09-22/resource-run.py -- swift test --scratch-path .build/public-preview` exited 0: **111 tests in 3 suites passed**, including all eight new regression tests; raw /tmp/deskmux-burn-final-tests.log. `git diff --check` clean. Registry now 36 cases, DM-036 covering clipboard generation/reconnect behavior. Resource-wrapped Scripts/release.sh running for v0.2.2; no installed bundle touched.

### Exact deferred post-burn acceptance

- DM-036/008/020: on coordinated disposable two-Mac session, copy synthetic text A, disconnect peer, replace with image/file/cleared clipboard or text >1 MiB, allow at least one 150 ms poll, reconnect: A must not appear; copy eligible B and verify sync resumes. Repeat directions and Unicode exact byte limit. Actual pasteboards untouched in automated tests.
- DM-003/004/005/007/032: held-modifier disconnect, sleep/wake, network loss, native mouse return-channel failure and emergency chord on both Macs. Requires physical keyboard/mouse and permission/session coordination.
- DM-009/010/028/029/030: MacBook-local AOC identity, HDMI return with DDC readback AND visible signal separately; opt-in follow/windows respecting manual repositioning; Your desk close/reopen and after coordinated restart. Cannot infer from geometry/parser tests.
- DM-011/012/034: signed disposable app upgrade/rejection/rollback and permission retention; corruption/wrong signer/older version/disk-write failure. Current suite checks layout only, not full installer execution; never overwrite installed production bundle to test.
- DM-002/015/031/033: permission revocation, VoiceOver/keyboard/large text, macOS 14 and Apple silicon clean launch, launch-at-login. Requires disposable login/OS sessions.
- DM-013/018: experimental DeskMux screen runtime/permission/receiver-disconnect acceptance; protocol tests do not certify private macOS runtime or capture behavior.
- DM-014/027: synthetic runtime-log redaction and real Options+ Flow behavior remain manual; existing parser and temp-file tests are partial evidence.

Scope correction supersedes checkpoint 2: DeskMux streaming remains in scope. All Voxta integrations excluded throughout. Next: inspect signed release artifact/archive, commit scoped files, publish coordinated v0.2.2, notify site worker. No website deployment authorized.

## Checkpoint 5 — release artifact validated

`resource-run.py -- Scripts/release.sh` exited 0 (/tmp/deskmux-burn-release.log). Release ZIP: `dist/DeskMux-0.2.2-macOS-arm64.zip`, 5,206,410 bytes; SHA-256 `f5e7555c9b68b1f413daee4a931f164a252c7b87b9e9c21856d52a241464d877` matches dist/SHA256SUMS.txt. `unzip -tq` passed. Extracted into a fresh temporary directory, `codesign --verify --deep --strict` passed; both app/agent report 0.2.2 / build 20260922065006; lipo confirms arm64; DDC/relauncher/Mux/license resources present. Stable Apple Development signature, not notarized. Temporary extraction removed automatically; preexisting output/ remains untouched. Source diff reviewed; no unrelated staged files. Publication next within root-assigned slot.

## Checkpoint 6 — published release and resume state

Committed release source/tests/docs as `aab61ae4cd0c7a2dcd711d2430c59d2316d1d2e8`; pushed main and annotated v0.2.2. Published prerelease https://github.com/dion-labs/deskmux/releases/tag/v0.2.2 at 2026-09-22T06:51:01Z. Both ZIP and SHA256SUMS uploaded. Downloaded both published assets into a fresh temporary directory and independently verified digest matches the validated local ZIP. Site worker received exact validated links/change summary; awaiting local-site validation confirmation (deployment remains unauthorized). Git worktree after release contains only preexisting untracked output/ before this journal update.

GitHub macOS CI for release head was in progress at this checkpoint (runs 35696700732 and 35696700349); local tests/package checks already passed. No new physical/manual acceptance claimed. Next: check CI and site worker receipt, record final outcome, then continue only concrete scope-backed work or coordinated acceptance; do not restart apps/hardware to clear remaining gates.

## Checkpoint 7 — reviewer-directed replay ordering follow-up

Root review of released aab61ae found that addObserver captured pending text under lock and invoked its callback after unlocking; a main-thread invalidation could occur between snapshot and callback. The 0.2.2 observation tests did not cover delivery ordering. Implemented a MainActor-isolated DeskMuxClipboardDelivery used by the bridge: queued registration/replay obtains current pending state at execution, and observations, remote application and callbacks all execute serially on main. No snapshot crosses an observed invalidation. Added injected paused-scheduler tests with no NSPasteboard calls for unsupported/oversized/remote invalidation, valid replay, subsequent local text and observer removal. Preparing a separate v0.2.3 release per root; existing 0.2.2 artifacts remain unchanged. Targeted tests in /tmp/deskmux-burn-replay-tests.log.

## Checkpoint 8 — v0.2.3 release candidate

Seven targeted clipboard tests passed (/tmp/deskmux-burn-replay-tests.log), then full `resource-run.py -- swift test --scratch-path .build/public-preview` passed **114 tests in 3 suites** (/tmp/deskmux-burn-v023-tests.log), exit 0. Registry now DM-001–DM-037. Root granted exclusive next patch publication slot. v0.2.3 app/agent/README/CHANGELOG prepared; resource-wrapped release build running (/tmp/deskmux-burn-v023-release.log). Site worker independently confirmed v0.2.2 links, checksum, browser QA and no deployment; final v0.2.3 notification will supersede those links.

The follow-up regression tests exercise the production delivery component using an injected paused work queue, not merely the observation value type. Observed invalidation happens before replay resumes, and no stale callback is emitted; valid current replay, later text and observer removal are checked. Real pasteboard timing, running app behavior and physical acceptance remain deferred as listed above. Root reviewer may inspect the dirty release diff before publication.

## Checkpoint 9 — v0.2.3 artifact accepted

Release build exited 0. ZIP `DeskMux-0.2.3-macOS-arm64.zip` is 5,210,972 bytes; SHA256 `dae82e8701818881d096f7a17bf6598fa92da4e1d3b4d99b71b2cb1d6f2fed1b`. Fresh temp extraction: unzip integrity and strict deep codesign pass; app/agent 0.2.3 build 20260922065630; arm64 binary. Both app and agent designated requirements exactly match extracted v0.2.2 equivalents. This is signature evidence, not live TCC/upgrade acceptance. Diff reviewed, git diff --check clean. Publication next under root-authorized follow-up slot.

## Checkpoint 10 — v0.2.3 publication and compiler compatibility follow-up

Published v0.2.3 at https://github.com/dion-labs/deskmux/releases/tag/v0.2.3 on 2026-09-22T06:57:30Z, commit b7cb7c7. Redownloaded ZIP/checksum and matched `dae82e8701818881d096f7a17bf6598fa92da4e1d3b4d99b71b2cb1d6f2fed1b`. Site notified. However, GitHub runs 35697210679/35697210883 then FAILED compiling the timer weak-self capture inside MainActor.assumeIsolated. Toolchain facts: local Swift **6.3.2** passes; CI Xcode 26.3 / Swift **6.2.4** reports SendingRisksDataRace. Earlier coordination called CI newer; that was incorrect, the failure is compiler-version-dependent actor analysis.

Promoted weak self to a strong immutable Sendable local before entering assumeIsolated; serial main-actor behavior unchanged. v0.2.4 prepared and full local **114 tests pass**, /tmp/deskmux-burn-v024-tests.log. Commit/push source then require fresh CI green before next publication. No artifact was overwritten or installed. Site told to hold final version pass; root status records continued patch release coordination request.
