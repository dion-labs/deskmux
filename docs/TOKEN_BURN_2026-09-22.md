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

## Checkpoint 11 — v0.2.4 awaiting CI

Compatibility source committed/pushed as `184bf802e297e2c1f5ce421661b7ead7ddf8763c`. Local full 114 tests pass. Release build exited 0 (/tmp/deskmux-burn-v024-release.log). ZIP is 5,210,852 bytes, SHA256 `37c9ca19b64baf8f27a4bfae65c00b6d7420033ef2808b7de73df2540ebaa710`; fresh temp extraction passes unzip/strict deep signature, app and agent 0.2.4 build 20260922065943, arm64, unchanged designated requirements from v0.2.3. CI run 35697374677 still in progress; publication held until it passes. Added DM-038 toolchain compatibility gate to registry to distinguish local and CI evidence. No installed app or hardware action.

## Checkpoint 12 — final v0.2.4 published and CI green

CI https://github.com/dion-labs/deskmux/actions/runs/35697374677 completed SUCCESS on Swift 6.2.4/macOS 15 (tests, menu-bar icon smoke, app build, deep strict signature). Tagged exact tested source `184bf802e297e2c1f5ce421661b7ead7ddf8763c` as v0.2.4, then published https://github.com/dion-labs/deskmux/releases/tag/v0.2.4 at 2026-09-22T07:02:44Z. Redownloaded both published assets and independently matched ZIP SHA256 `37c9ca19b64baf8f27a4bfae65c00b6d7420033ef2808b7de73df2540ebaa710`. Updated prior v0.2.2/v0.2.3 release notes to point to v0.2.4; existing artifacts untouched. Site worker received final version/URLs/checksum and is responsible for local download-link validation, not deployment.

### Ready report and remaining work

Delivered 38-case stable risk registry, 11 additional automated tests (103→114), clipboard stale-generation invalidation, main-actor delivery ordering with paused replay fixtures, Swift6.2/6.3 compatibility, signed validated arm64 release and independent published checksum verification. All actual data/pasteboards/hardware/running apps untouched; preexisting output/ retained. No Voxta work. Full manual acceptance list remains under checkpoint 4; add queued-reconnect overlap scenario DM-037 and verify actual two-Mac asynchronous behavior after coordinated upgrade. No claim of physical or permission/installation acceptance from unit/build checks.

Implementation/release milestone sequence complete. Remaining scope-backed product acceptance requires coordinated disposable Macs/permissions/hardware/session access (not allowed in this worker), plus site worker's final link receipt. Further runtime work should follow a concrete failure or reviewer finding rather than invent new vision. Resume from this ledger, current Git and worker inbox; do not replay completed releases or touch running app to force acceptance.

## Final worker handoff

Latest inbox read contained no new review finding or STOP marker. Site worker last receipt covers v0.2.2 and status says waiting for v0.2.4; final v0.2.4 validated URLs/checksum were appended to its inbox. **Site link update receipt is still pending** and cannot be completed by this worker without violating the assigned-project boundary. Root should resume/check site worker to finish that handoff; no deployment is authorized. All product source/package/publication checks are complete for v0.2.4; local and CI each explicitly report 114 tests in 3 suites. Final documentation-only commit records receipts/registry and does not change the tested release source.

No further concrete safe implementation milestone is selected: outstanding supported-desk behavior requires coordinated live acceptance, and full installer/permission/runtime gates need an isolated signed-bundle/login or hardware harness rather than touching the active installation. These are open gates, not passed results. Do not call the entire portfolio or site release workflow complete until root has the site receipt.

### Site receipt received at final inbox check

Supersedes the site-handoff blocker above: site worker confirmed final local v0.2.4 version/schema/archive/notes, independently verified published ZIP size/checksum and successful CI at exact source 184bf80. Site build and targeted 390/320 metadata/link/copy/download layout checks passed; actual release/ZIP/checksum HEAD returned 200. Prior 63 cross-engine checks retained with unchanged CSS/JS/harness/router/package hashes. No website deployment or site main push. Release/download-link coordination is complete within authorized local scope; live/manual product acceptance remains open. Product tree still preserves only preexisting untracked output/ after documentation receipts.

## Checkpoint 13 — coordinator-approved isolated runtime harness

Burn resumed for local-only encrypted loopback/runtime/persistence coverage, preserving v0.2.4 and 114-test receipts. Existing loopback test covered only happy handshake; existing codecs covered malformed frames as value tests. New harness binds NWListener exclusively to 127.0.0.1 with no Bonjour advertisement, creates fresh InputPeerConnection objects and synthetic keys/identities, waits on explicit state/message signals and cancels all owned sockets. It never calls input injector, capture, clipboard bridge, TCC or installed services.

Five new transport cases: 100 ordered encrypted messages plus fresh reconnect, wrong-key disconnect plus successful fresh connection, throwing-consumer rejection over authenticated transport, immediate cancel while callbacks are paused, and eight concurrent producers sending 800 encrypted messages. First run against unchanged released transport (/tmp/deskmux-burn-loopback-baseline.log) passed the first three but FAILED cancel (send returned success after cancel) and concurrency (receiver EPROTO from out-of-order sequence). This is new runtime evidence, not duplicated unit assertions.

Fix candidate: hold connection lock across sequence sealing AND NWConnection enqueue; clear ready synchronously on cancel and prevent late ready state from reopening owner-cancelled transport. Focused tests next. Full receiver identity/session policy remains untested: ReceiverSession directly constructs MacInputInjector and calls shared clipboard/update services without injectable sinks; no installed receiver launched. Consumer-rejection case proves the transport closes on a throwing callback, not production peer/session policy.

## Checkpoint 14 — runtime failures fixed; persisted redaction acceptance

Focused transport after fix: 5/5 passed, /tmp/deskmux-burn-loopback-fixed.log. Extracted the existing clipboard metadata JSONL sink into internal DeskMuxClipboardEventLog with injectable directory/queue; production default path and schema unchanged. Tests instantiate only temporary directories, append metadata asynchronously, recreate writer, run 100 concurrent writes, assert whole valid JSONL with allowlisted metadata and absent synthetic text, and repair a file-blocked directory after a swallowed logging failure. Combined runtime/log run: **8/8 passed**, /tmp/deskmux-burn-runtime-log-tests.log. No production log, clipboard, Keychain or preferences read/written. Initial status incorrectly suggested MotionTraceRecorder had a URL seam; source inspection showed it only exposes an in-memory trace, so no persistence claim is based on that class.

Added one additional transport acceptance: 1 MiB synthetic UTF-8 clipboard message crosses real 64 KiB receive chunks and gets encrypted update-ID acknowledgement at the fake endpoint; full run next. Registry extends DM-039–DM-044 without renumbering prior cases. Root reserves v0.2.5 for this coherent transport/cancel/logging acceptance milestone and will review lock/callback ordering before publication. Prior v0.2.4 immutable release and 114-test evidence retained. Full production ReceiverSession identity/input-session enforcement still requires fake input/clipboard/update sinks before safe exercise; custom-consumer rejection does not substitute for it. Network/handoff production logs also have no isolated sink and remain deferred rather than launching services.

## Checkpoint 15 — 123 tests pass and independent review accepted

Full resource-wrapped suite passed **123 tests in 3 suites**, /tmp/deskmux-burn-v025-tests.log, exit 0. The additional ninth test confirms a 1 MiB UTF-8 payload survives actual encrypted TCP receive chunking and ID acknowledgement at isolated endpoints. Registry now 44 cases. Root independent review PASS: same-lock seal/enqueue, immediate cancellation gate and delayed-ready guard inspected for lock inversion/callback-under-lock; reviewer independently ran 8 focused loopback/log cases. No review blocker. Reviewed transport SHA256: `85af4d9784cfda8b58e22aa7057c57d897fee77c4d9dc9db8c872e0a4989e190`.

Thread Sanitizer targeted runtime/log run queued under shared resource wrapper in .build/burn-tsan, /tmp/deskmux-burn-v025-tsan.log. Preparing v0.2.5 app/agent/README/CHANGELOG. CI on supported Swift6.2.4 required before publication, in addition to current local Swift6.3.2 results. No live acceptance boundary changed.

## Checkpoint 16 — sanitizer acceptance and release preparation

Candidate source/tests committed/pushed as `e52bc95bf4e8eb635e9c96ef0a5c178798f69fc8`. Resource-wrapped `swift test --sanitize=thread --scratch-path .build/burn-tsan --filter 'loopbackTransport|loopbackCancel|loopbackConcurrent|loopbackClipboard|clipboardLog'` exited 0, **9 tests passed**, no ThreadSanitizer/data-race/error reports (/tmp/deskmux-burn-v025-tsan.log). This specifically exercises the new runtime/log concurrency paths, not real desktop services. Local full suite remains 123/3 PASS. Supported-toolchain CI run 35699084226 and reserved v0.2.5 resource-wrapped package build subsequently completed successfully (/tmp/deskmux-burn-v025-release.log). Publication requires the artifact checks recorded next.

## Checkpoint 17 — v0.2.5 CI and artifacts pass

CI https://github.com/dion-labs/deskmux/actions/runs/35699084226 SUCCESS at exact candidate e52bc95 on Swift6.2.4: 123 tests in 3 suites, icon smoke, app build and signature checks. Local Swift6.3.2 also 123/3; targeted Thread Sanitizer 9/9 with no reports. Signed release ZIP `DeskMux-0.2.5-macOS-arm64.zip`: 5,213,461 bytes; SHA256 `9ceac7b7158ceaf78d95c23a3668aa6fff7c60141c76a401e510361af2d3122e`. Fresh extraction passed unzip integrity, strict deep codesign, arm64, app+agent 0.2.5 build20260922072100, helper/resources and unchanged designated requirements from v0.2.4. Apple Development signed, not notarized. Root independent review and exclusive release slot confirmed; publication next. Previous 0.2.4/114-test evidence remains preserved.

## Checkpoint 18 — v0.2.5 published; exact resumed-burn handoff

Tagged tested e52bc95 as v0.2.5 and published https://github.com/dion-labs/deskmux/releases/tag/v0.2.5 at 2026-09-22T07:23:04Z. Fresh download of published ZIP and checksum independently matches `9ceac7b7158ceaf78d95c23a3668aa6fff7c60141c76a401e510361af2d3122e`. Previous releases and v0.2.4/114-test receipts remain unchanged. Site worker received actual final URLs/size/checksum/CI and request for local affected-link validation; no deployment. Current product release source is e52bc95; forthcoming documentation receipt does not alter tested code.

Resumed milestone result: two real runtime bugs reproduced then fixed; six isolated real encrypted TCP acceptance tests plus three asynchronous filesystem/logging tests; **123 full tests pass on both Swift6.3.2 and6.2.4**, **9 Thread Sanitizer cases pass without reports**, independent root lock/callback review passes, signed release validated and published. Registry44 cases. No real clipboard/input/keyboard/displays, Bonjour advertisement, login/TCC, installed bundle/service, Keychain or personal log access.

Exact remaining gates for this harness request:

- DM-001/003/005/007/032 production receiver expected-peer/session enforcement, automatic warm reconnect/ownership recovery and input release remain NOT RUN. ReceiverSession directly constructs MacInputInjector and calls shared clipboard/app-update services; BonjourInputReceiver.start also checks permissions/starts native services. There is no fake sink seam for those boundaries. The custom throwing-consumer case verifies only that InputPeerConnection rejects callback failures, not production peer/session authorization. A separately scoped injected receiver-sink harness is needed before safe local testing; never launch installed services to bypass this blocker.
- DM-014: actual clipboard metadata writer persistence/redaction/failure recovery now automated in disposable directories. Network and handoff loggers remain private to production service/UI with hard-coded home paths and unisolated lifecycle; do not claim their logs passed or launch those processes. An injected metadata sink is needed for equivalent acceptance.
- DM-008/020/036/037: 1MiB payload transport/ACK and pure queued clipboard delivery pass; actual pasteboards, two-Mac echo/reconnect/timing remain manual under coordinated acceptance. No real clipboard was inspected.
- All physical/DDC/window/upgrade/TCC/older-OS gates from checkpoint4 remain open; this local harness does not advance them.

Next: finish site receipt and document handoff. Further receiver/service acceptance requires a concrete safe fake-sink design or coordinated environment rather than broadening into live services. All preexisting output/ retained.

## Checkpoint 19 — root-approved receiver seam design (before implementation)

Root supplied a concrete next milestone: introduce the smallest explicit side-effect seam for actual ReceiverSession tests, keeping initial production defaults unchanged; no new release slot until behavior/evidence exists. Current couplings mapped: MacInputInjector construction/inject/release; motion registry register/unregister; modifier publication; MacLocalEscapeMonitor construction/run/stop; shared clipboard apply with asynchronous acknowledgement; installer invocation. Transport already accepts a raw NWConnection, so tests can attach the real ReceiverSession to the existing localhost-only harness without starting BonjourInputReceiver, permission checks, datagram listener or app services.

Candidate design for independent review: internal ReceiverInputSink and ReceiverEscapeMonitor protocols matching existing concrete methods; a Sendable ReceiverSessionDependencies value containing factory/register/unregister/modifier/clipboard/install closures. A production factory binds exactly the existing objects and calls; tests supply only in-memory recorders and paused async completions. ReceiverSession changes from file-private to internal for @testable access; no public API/UI or fake production path. Motion registry stores the input-sink protocol with the same UUID lookup. Initial extraction preserves behavior, then fixtures expose any policy/lifecycle defects before fixes.

Invariants/fixtures: require compatible hello/purpose before input/clipboard/update side effects; clipboard source must match authenticated hello peer and UTF8 size bound; stable identity/purpose throughout a connection; input belongs to current session; disconnect/stop/return should release held fake input and unregister exactly once; malformed/unsupported messages terminate without later side effects; update path honors acceptsAppUpdates and returns fake result only; old-session clipboard completions must not acknowledge into a new connection. Native MacInputInjector currently owns packet UUID/order validation; tests must not pretend a fake's own validator proves receiver enforcement. Separate behavior changes, if needed, will be explicitly documented and reviewed rather than silently attributed to the seam.

## Checkpoint 20 — receiver seam baseline exposes lifecycle holes

Pure forwarding extraction compiles. First fixture compile failed on nested shorthand closure parameters; corrected to explicit names (compile log retained separately). Behavior-preserving receiver baseline /tmp/deskmux-burn-receiver-seam-baseline.log then ran 15 new receiver tests plus one existing parser test matched by filter: 5 new tests FAILED. Exact observed failures: event before explicit begin created/registered an input sink; repeated hello changed peer/purpose and sent another ready; duplicate begin constructed a second sink before rejection; a decoded event after stop injected key43 after one-time cleanup and left it held; a peer ignoring local return could inject again and leave key43 held. Happy handshake/disconnect cleanup, missing-hello rejection, unsupported version/message rejection, clipboard source/size gates, fake installer capability gating and sink-error cleanup passed. UUID/malformed sink errors were injected contract failures; they do not claim native CGEvent validation.

Independent root seam review confirms forwarding equivalence and prioritizes encrypted goodbye+tail in one receive batch plus paused factory against concurrent stop. Adding those fixtures before fixing. Proposed bounded fix: pin hello to one identity/purpose, require explicit begin for input protocol9, check terminal/return state at admission, recheck state after factory returns, adopt/register atomically, and serialize injection against finish cleanup. A top-level finished guard alone cannot fix factory/adoption races. Internal dependency contract will explicitly forbid synchronous reentry into ReceiverSession (matching existing native adapter behavior); async escape/clipboard completion callbacks remain supported. No new release slot until these fixes/fixtures form coherent evidence.

Site v0.2.5 receipt arrived and is complete: independent publication/checksum/CI verification, local version/schema/ZIP/notes updated, affected390/320 link/copy/layout checks and HEAD200 passed, no deployment/main push. Prior v0.2.5 delivery fully complete; current work is a separate receiver milestone.

## Checkpoint 21 — encrypted terminal tail and factory race reproduced/fix candidate

Additional actual encrypted batch fixture sends goodbye followed by input/clipboard frames in one TCP write, both with an existing sink and before any sink. Baseline failed: post-terminal key43 was injected/held, or a fresh sink registered after cleanup. Paused factory/concurrent stop also failed: factory resumed after finish and registered/published modifiers. Raw /tmp/deskmux-burn-receiver-adversarial-baseline.log: two test functions (batch has two variants), six failed assertions, no hardware effects. Root reserves v0.2.6 for coherent fixes with full/TSan/review/CI/package gates.

Candidate fixes now implemented: active/return checks at decoded ingress and within effect critical sections; immutable hello identity/purpose; explicit begin required; duplicate begin rejected before construction; slow factory stays outside receiver lock but rechecks/adopts/registers/publishes atomically after return; injection serialized with finish cleanup; clipboard admission serialized with terminal checks; monitor adoption rejects stopped/returning state. Native sink retains UUID/sequence/CGEvent validation. Dependencies explicitly retain nonreentrant synchronous entry-point contract, matching native adapters; no arbitrary callbacks generalized. Focused run /tmp/deskmux-burn-receiver-fixed.log in progress/result to inspect next. No release/version bump yet, no production factories used by tests.

## Checkpoint 22 — focused receiver fixes pass

Resource-wrapped receiver filter passed 18 functions (17 new acceptance functions plus existing parser case), /tmp/deskmux-burn-receiver-fixed.log. All baseline lifecycle failures now pass including actual encrypted terminal batches and factory-stop interleaving. Full suite and targeted Thread Sanitizer queued. Final candidate available for independent coordinator review; v0.2.6 slot remains reserved, publication still gated.

## Checkpoint 23 — independent review exposes motion cleanup gap

Full TCP-era suite140 PASS and receiver TSan18 PASS. Root held release after finding motion registry bypasses return state and copies sink before unregister. Added real-registry/fake-input fixtures first: both failed (/tmp/deskmux-burn-motion-baseline.log), post-return motion count2 instead of1 and paused in-flight motion landed AFTER terminal release. Fix: registry serializes lookup+inject against unregister; receiver retires/unregisters before release and clears sink, so return/finish cleanup is idempotent. Lock order receiver -> registry -> sink, no callbacks to receiver/registry from sink. Native adapter follows this existing nonreentrant contract.

Installer admission now atomically checks active/purpose/capability/source. Already-admitted installer work is noncancellable and remains outside lock so stop stays responsive; synthetic paused-installer fixture verifies stop/new-admission/result behavior. No real installer, UDP listener or input effects. Updated suite next; prior140/18 results are explicitly before these additions.

## Checkpoint 24 — final receiver suite and sanitizer pass

Final candidate fullsuite **143 tests in3 suites PASS**, resource-wrapped /tmp/deskmux-burn-v026-final-tests.log. Targeted receiver Thread Sanitizer **21 functions PASS**, no sanitizer/data-race/error reports, /tmp/deskmux-burn-v026-final-tsan.log. Includes20 new receiver functions plus existing parser case; motion fixtures use real registry with fake input, not a UDP listener. Registry51 IDs. Final code/metadata ready for supportedSwift6.2 CI and package validation. Root motion hold remains until independent final rereview; no publication yet.

## Checkpoint 25 — supported CI and signed archive pass

Exact tested/pushed source af7ff55ea8f5730059079ee09063b765271c74c5. CI https://github.com/dion-labs/deskmux/actions/runs/35702224225 SUCCESS on Swift6.2.4:143 tests/3 suites, icon smoke, build and signature. LocalSwift6.3.2 full143 and receiverTSan21 PASS. Resource-wrapped release build exited0; archive DeskMux-0.2.6-macOS-arm64.zip 5,219,263 bytes SHA2569f361cc837463cfa5f2fedf91e08460d351c8aedd47f2ff95f59d308545ad81d. Fresh extraction strictdeepcodesign, app+agent0.2.6/build20260922075740, arm64, all prior helper/resource paths and unchanged designatedrequirements from0.2.5 PASS. AppleDevelopment signed, not notarized. Raw artifact receipt /tmp/deskmux-burn-v026-artifact.json and CI log /tmp/deskmux-burn-v026-ci.log.

Only final independent root review/hold clearance outstanding before tag/publication. No installed session touched. Release notes prepared in /tmp/deskmux-v026-release-notes.md; source is unchanged since fullsuite/TSan/CI.

### Exact review-held resume action and remaining acceptance

As of final checkpoint, root inbox still holds publication pending independent motion rereview. All requested motion failures were reproduced and fixed, full/TSan/CI/package gates passed; no further source change is needed unless review finds one. Resume by reading inbox/STOP, obtain final coordinator clearance, then tag **af7ff55ea8f5730059079ee09063b765271c74c5** as v0.2.6, publish existing validated dist ZIP+SHA256SUMS with prepared release notes, redownload/verify hash and notify deskmux-site for actual-link receipt. Do not rebuild/replace the existing release archive or tag a different source by accident. Until then v0.2.5 remains the latest published release and site target; v0.2.6 delivery is incomplete.

Deferred acceptance after this receiver milestone: physical held-key/modifier/button release and emergency/local-return under disconnect/sleep/wake; actual native UUID/sequence/CGEvent decode and injection; UDP network transport under loss/reordering (registry cleanup is tested directly); real clipboard bidirectionality/echo/poll timing/reconnect; complete signed installer rejection/upgrade/rollback/permission retention; MacBook AOC HDMI/DDC visible switching and windows/Your desk restart; TCC revocation/login/VoiceOver/olderOS; experimental streaming lifecycle; network/handoff log redaction with an isolated sink. Existing QA IDs and checkpoint4 procedures remain authoritative. This fixes receiver admission/lifecycle with fake effects, not physical desktop acceptance.

## Checkpoint 26 — review cleared and v0.2.6 published

Supersedes checkpoint25 review hold: independent root rereview cleared scoped gate; relay SHA256ffac332225dc44e862adf024c7db3eeede3c8a147c930f1d18f4f015ac57db80 matches final source. Reviewer verified lock graph/no inverse path and independently passed6 focused motion/installer/terminal/factory functions.

Tagged exact testedsourceaf7ff55 as v0.2.6 and published https://github.com/dion-labs/deskmux/releases/tag/v0.2.6 at2026-09-22T08:02:04Z. Published ZIP5,219,263 bytes and checksums redownloaded; SHA2569f361cc837463cfa5f2fedf91e08460d351c8aedd47f2ff95f59d308545ad81d matches validated local artifact. Final CI143, local143, receiverTSan21 and artifact checks remain PASS. Exact asset URLs/evidence sent to deskmux-site for local affected-link update/receipt, no deployment. Earlier releases unchanged. Site receipt is remaining release-delivery step. Native/manual gates above remain open; no installedsession/hardware/clipboard/TCC interaction.
