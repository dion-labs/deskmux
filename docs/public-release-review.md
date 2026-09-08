# Public preview review

DeskMux graduates into Dion Labs as an input-sharing utility for a desktop Mac
and a MacBook. Monitor switching is a roadmap item. Virtual-display streaming
is experimental and relies on an undocumented macOS runtime.

The source move retains a compatibility symlink at the old checkout location
for existing research sessions. Running installed apps are not replaced by
release preparation.

Publication checklist:

- [x] Public README, MIT license, attribution and support/security documentation.
- [x] Original Mux mascot, app icon, menu-bar mark and settings header.
- [x] Gitleaks history scan clean; 96 local tests; strict signature and ZIP checks.
- [x] Public GitHub repository, passing macOS CI and v0.1.0 preview artifacts.
- [x] Independent showcase repository and successful Git-triggered Cloudflare deployment.
- [x] Live Dion Labs portfolio integration; desktop/mobile browser checks.

Published on 2026-09-08:

- App: https://github.com/dion-labs/deskmux
- Release: https://github.com/dion-labs/deskmux/releases/tag/v0.1.0
- Showcase: https://deskmux.dionlabs.ai
- Site source: https://github.com/dion-labs/deskmux-site

The showcase builds through Cloudflare Pages on site-repository pushes only.
A small custom-domain Worker proxies its Pages origin. Portfolio changes deploy
through the existing independent Dion Labs Workers Build.

The preview is limited to Apple silicon. Only an Apple Development signing
identity is currently available locally; notarization is not claimed. No
vendor firmware binaries, personal signing bootstrap, runtime logs or build
backups belong in the public repository.
