# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Build/run/test via the `Makefile` (`make build|run|test|dump`); SwiftPM package plus `scripts/build-app.sh` assembles the universal `.app`. No Xcode project.
- Keep system access in `Sources/NerdStatsCore` (no UI) and SwiftUI in `Sources/NerdStats`; put hardware-free logic in pure types so it can be unit tested. CONTRIBUTING.md "Architecture" describes the data flow; README.md is the user-facing product page, so developer docs go in CONTRIBUTING.md.
- Every reading is optional: missing sensors/keys must render as unavailable, never crash. Intel code paths cannot be exercised on the Apple Silicon dev machine.
- `make dump` prints what the current Mac actually reports; use it to check sensor changes. The dev environment has no screen-recording or accessibility permission, so screenshots/UI clicking do not work.
- `docs/` is the static GitHub Pages site (no build step, no external assets); `docs/download.js` resolves the latest release DMG, keeping the releases/latest link as fallback.
- Beware `.map(Double.init)` on unsigned integers: it resolves to `Double(bitPattern:)`. Use `{ Double($0) }`.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
