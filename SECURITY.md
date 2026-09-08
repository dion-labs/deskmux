# Security and privacy

Use DeskMux between Macs you own or trust, on a trusted local network. This is
an early release, not a security-audited remote-access product. Do not expose
its services to the public internet.

DeskMux stores pairing secrets in Keychain and authenticates/encrypts peer
messages. The current protocol uses a shared secret and does not provide
forward secrecy or a formal cross-session replay guarantee. Input permissions
allow sensitive access: grant them only to builds you trust.

Plain-text clipboard changes are automatically shared with the paired Mac,
including sensitive text you copy. Clipboard contents remain in memory;
delivery logs contain identifiers, timestamps and byte counts. Non-text
formats, files, and images are not transferred. Logs and diagnostics should be
reviewed before sharing; device names can identify their owner.

Updates require a newer build signed by the same designated signing
requirement. The initial preview uses Apple Development signing and is not
notarized. Build from source if that distribution model does not suit you.

Report vulnerabilities through GitHub's private vulnerability reporting on
this repository. Do not post pairing keys or sensitive logs in public issues.
