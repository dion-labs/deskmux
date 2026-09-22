# Changelog

## 0.2.7 — Reliable diagnostic appends

- Prevent concurrent network and handoff log writers from overwriting or
  interleaving JSONL records through atomic append and per-file serialization.
  Skip records on lock contention so diagnostics cannot wait on a paused writer.
- Isolate the existing writer behind an explicit directory dependency for
  disposable persistence, recreation, external rotation and error-recovery tests.
- Preserve existing metadata fields and synchronous error handling. Diagnostic
  details remain verbatim; JSON escaping does not provide general redaction.

## 0.2.6 — Receiver session lifecycle

- Reject input after shutdown or destination return, including decoded frames
  remaining in the same encrypted receive batch.
- Require one hello and an explicit input-session start; reject repeated starts
  before constructing another native input sink.
- Prevent input construction racing with shutdown from registering a new session;
  serialize event injection with terminal release and unregister.
- Unregister pointer motion before terminal input release and drain admitted
  motion, preventing UDP motion from outliving local return or shutdown.
- Check update admission atomically; an already-admitted installation may finish
  after transport shutdown, while new requests are rejected.
- Add isolated receiver acceptance using real encrypted localhost connections
  and in-memory input, clipboard and update sinks. Native input, pasteboard,
  installer and physical two-Mac acceptance remain separate manual gates.

## 0.2.5 — Reliable concurrent transport

- Keep encrypted sequence assignment and network enqueue in the same critical
  section, preventing concurrent senders from causing out-of-order disconnects.
- Reject new sends immediately after local cancellation, including while native
  state callbacks are delayed.
- Isolate the unchanged clipboard metadata logger for disposable-directory
  persistence, concurrent append, redaction and failure-recovery acceptance.
- Add localhost-only encrypted transport acceptance for reconnect, wrong-key
  rejection, consumer rejection, concurrent sends and a 1 MiB UTF-8 payload.

## 0.2.4 — Swift concurrency compatibility

- Promote the timer callback’s weak capture to a strong local before entering
  the main actor, satisfying Swift 6.2 concurrency checking while preserving
  serialized clipboard observation and replay.

## 0.2.3 — Clipboard replay ordering

- Serialize reconnect replay with clipboard observation and remote application.
  A queued reconnect now checks the current text at delivery instead of carrying
  an old snapshot past a clipboard invalidation.
- Add deterministic paused-replay tests for unsupported/oversized replacements,
  remote application, valid replay, subsequent text and observer removal.

## 0.2.2 — Clipboard reconnect privacy

- Discard cached outgoing text when a new clipboard generation is observed,
  including images, files, cleared clipboard and oversized text. Reconnecting
  peers no longer receive text from the preceding observed clipboard generation.
- Add synthetic clipboard recovery and encrypted-frame boundary regression tests.
- Document risk-based QA and remaining physical/manual acceptance gates.

## 0.2.1 — Desk window and local monitor discovery

- Open Your desk as an explicit window from the menu bar.
- Resolve the experimental AOC video controls on each Mac independently.
- Show local monitor identity and helper errors when DDC control fails.
- Include opt-in AOC input following and visible-screen window placement.
- MacBook HDMI switching still requires physical validation.

## 0.2.0 — Your desk, redesigned

- A two-Mac dashboard with clear input ownership and keyboard anchor.
- Sidebar navigation separates handoff, connection, display experiments and access.
- Redesigned menu-bar popover with matching destination cards.
- Appearance-aware foreground accents improve light/dark contrast without
  lightening the filled cards behind white text.
- Mux accompanies the new settings workspace. Input transport is unchanged.

## 0.1.1 — Menu-bar visibility

- Supply the Mux mark as a native template image instead of a bare SwiftUI
  shape, so the menu-bar status item has an image to display.
- Add a rasterization check for a non-empty, appearance-adaptive status icon.

## 0.1.0 — First public preview

- Native Logitech mouse handoff with configurable edge and modifier trigger.
- Keyboard follows the mouse through an encrypted local connection.
- Bidirectional plain-text clipboard sharing.
- Permission guidance, startup option, connection status and paired-Mac updates.
- Original Mux mascot, dedicated menu-bar mark and refined settings identity.
- Experimental virtual-display streaming; physical monitor switching remains
  on the roadmap.

Validated in daily use on a Mac Studio M1 Ultra and MacBook Pro M1 Pro with
an MX Master 4. Other compatible mice and macOS versions need community testing.
