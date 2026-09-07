# One desktop companion

The native SwiftUI/AppKit app owns assistance requests, confirmed reply settings, local lessons, shared document copies, placement and the selected companion artwork. `CompanionStore` coordinates those existing services. `CompanionEvolution` retains appearance choices and reviewed history; natural starter variation is a projection of the existing Journey origin.

`src/model.ts` owns the game's Journey and its validated event history. `src/battle-engine.ts` resolves the QiMon battle rules. Habitat, Arena and Relay run inside the retained native WebKit host. `HostedPlayHost` and `src/desktop-host.ts` exchange bounded, revision-aware projections and commands; they do not introduce another character or history store.

Qwen, optional Codex and deliberate Compare retain distinct requests and receipts. Optional Reactor imagery is presentation with a local fallback. Blender and Unity support asset authoring and evaluation; neither is a second production game engine in this Alpha.

The `arc/` directory is an isolated synthetic exact-grid evidence lab. It is not a trained solver or a live ARC competition integration, and it is not imported by the app.

Working documents, replies and temporary context are session state. Preferences, explicitly kept lessons, explicit Evolution saves and game Journey persistence have different retention boundaries. See the root README before testing recovery.

Mobile and AR will need adapters around these owners. The released Alpha focuses on the native desktop path.
