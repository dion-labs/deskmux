# Contributing to DeskMux

Welcome. Start with a bug report, a hardware compatibility report, or a small
focused pull request. DeskMux is a native Swift package; the website lives in
the separate [deskmux-site](https://github.com/dion-labs/deskmux-site) repository.

Use Swift 6 on macOS 14 or later. Run `swift test` and `Scripts/build-app.sh`.
Do not run hardware experiments or install builds on someone else's working
desk as part of automated tests. Test clipboard behavior with an isolated
pasteboard and input behavior with synthetic events.

Keep keyboard escape and release-all behavior intact. Changes to wire messages
must consider mixed-version peers and remote update compatibility. Never check
in pairing keys, signing certificates, device serials, private logs, firmware
images, or vendor application binaries. Hardware reports should include model,
macOS version, transport, and a sanitized description of the failure.

The current hardware target is a desktop Mac paired with a MacBook and a
Logitech mouse exposing HID++ ChangeHost. Broader device support is welcome,
but must be verified on the relevant hardware before being advertised.
