# Local marketplace and canon item policy

14 September 2026 · Implemented desktop development Alpha

The native Marketplace (sidebar, Window menu / Command–5, menu-bar item and Wardrobe link) shares the existing companion, renderer, Work together and native profile. It adds no second character, model router, market server or game save.

## Working local flow

- Discover three bundled recipes: Focus Staff, decorative Starlight Staff and Grove Staff.
- Inspect static artwork and the exact supported local action. Previewing changes no outfit, identity, memory or progression.
- Add to My items explicitly retains the recipe on this Mac. The Alpha collection holds eight exact designs. Duplicate adds do not write another record.
- Equip applies the item for the visit. Wearing now and Next visit show the current and saved outfits separately, including a saved empty outfit. Review saved choices opens the existing preference controls; Save preferences keeps the outfit. A kept personal staff gesture overrides the creator default; Forget restores that design's default.
- Create variations using five palettes, three crown shapes, either decoration or pointing, and bounded pace/sparkle/hold choices. No arbitrary code, images, remote URLs or model prompts are imported.
- Import a local JSON recipe (maximum 4 KB) for review before Add. Feedback stays inside the sheet; Make a variation dismisses review before revealing Create. A full collection explains the limit and disables Add while keeping variation/export available. Removal remains in My items, avoiding a second confirmation behind import review. Export shares the design and declared license only. It does not share private memory or companion identity, issue an edition, or transfer ownership.
- Use in Work together appears for the exact equipped, collected pointing recipe. It opens the existing working copy; selection and Point with staff remain deliberate actions. It does not capture a new source, call a model, automatically equip a different item or invent a passage. Decorative items cannot use this shortcut.
- Unequip refreshes feedback and changes this visit only. The next-visit outfit remains saved until explicitly updated or forgotten. A known external profile conflict or recovery block makes the next-visit label unavailable until a successful write or reload verifies it again.
- Remove atomically removes the recipe and any saved equipped reference, then clears a matching current outfit after the write succeeds. A conflicting or failed write preserves the prior collection and outfit.

## What registration means

| State | Current meaning | Canon effect |
| --- | --- | --- |
| Unregistered design | A new or edited recipe that does not exactly match the bundled approved catalog. Creator and license text are declarations. | Zero official battle modifiers, rewards, rankings or progression. |
| Registered local Alpha design | Every recipe field matches one of three bundled catalog entries in `archi-local-alpha-registry/v1`, for `archi-local-item-actions/v1`. | No Arena effect is approved in this release. |
| Production registered item (future) | Reviewed exact version with authenticated creator/rights, compatibility, assets and supported effects. | Registration alone grants no game effect. |
| Canon-approved game profile (future) | Registered version separately approved for a named ruleset/mode, with costs, limits, balance and counterplay. | Only those approved effects may count in that ruleset. |

A SHA-256 design fingerprint binds exact recipe content. It is not an owner UID, signature, NFT, market price, scarcity proof or Hampton Designed endorsement. An imported `registered`, `owner`, `power`, `script` or other unsupported field is rejected. Renaming a creator Hampton does not register a recipe. Modifying any field changes its fingerprint and loses a bundled exact match. Copying an exact bundled recipe remains the same freely copyable design, not a newly issued edition.

The native catalog returns an empty canonical-effect list for every item. The retained Arena does not consume these recipes as loadout/stat inputs. Arena remains paused. This is a local non-effect boundary, not server-authoritative multiplayer enforcement. Future official play must validate signed registry versions and ruleset-specific loadouts before accepting an event; sandbox outcomes cannot be retroactively promoted by registering an item later.

## Persistence and continuity

`NativePreferenceDocument` advances to v5 with `itemLibrary`; v2–v4 and bare preferences still load with no disk rewrite until an explicit save. An equipped custom design must exist exactly in its library. The existing 64 KB profile cap, duplicate-key checks, file conflict comparison, atomic replacement, backup/restore and rollback stay authoritative. Item-only saves remain on disk. Lessons-only export excludes the library. Saved & this visit explains collection versus outfit retention.

The equipment identity includes the recipe digest, invalidating stale artwork/cue bindings when a design changes. Decorative items cannot activate pointing. A bounded label keeps the native/embedded artwork contract within 80 UTF-16 units without splitting visible characters. Seed/body continuity, local-first assistance and appearance choices remain in their existing owners.

## Earlier evidence and limits

Current checkout: full Swift suite passed 629 XCTest cases (32 skipped, zero failures) and reported 234 Swift Testing tests with the existing installed-worker opt-in skip. New tests cover strict recipe exchange, claimed registration, digest binding, palette/crown rendering, decorative activation, restart, equip/Save, atomic removal, conflict protection, older saves and actual backup restore/undo. These counts overlap the focused runs.

A hidden actual Marketplace view rendered legibly at 630×500 with no model calls or profile/identity changes. Native SwiftUI accessibility proxies were unavailable for the hidden panel; that acceptance is explicitly skipped. Full keyboard/VoiceOver, import/save-panel interaction, creator flow clicks, long-session use and another-Mac installation remain unqualified. No live LLM request was made. Build/staging evidence is recorded in `output/marketplace-increment-2026-09-14/`.

The existing [website marketplace guide](https://archi-it-begins-when-you-do.channelph.chatgpt.site/marketplace) links [public source](https://github.com/cr8ph8/ARCHi), explains the technical and proposed stewardship foundations, and separates local items from production registration and later Arena. Audience remains owner-private. Commerce, wallets, NFTs, transfers, creator submissions and popularity rankings are not enabled.

Delivery: [public source commit 6fd91a9](https://github.com/cr8ph8/ARCHi/commit/6fd91a954fc1a089d3de418753fa9f7ef0de86ba) pushed and remote manifest verified. Exported focused tests: 44 cases, two opt-in skips, zero failures. Site version 9 deployed; authenticated live page includes the marketplace, canon rule, GitHub link and foundation text. Native Review candidate built, plist checked and strict signature verified at `/private/tmp/archi-desktop-candidate-501/ARCHi Development Review.app`; installed/open apps preserved. Exact IDs and evidence are in `output/marketplace-increment-2026-09-14/delivery.json`.

## Marketplace interaction polish — 14 September 2026

The focused contract run passed **65 tests, zero failures/skips**. Eleven new outfit tests cover current/saved distinction, unrelated setting changes, Save opt-in off, forget, removal, store recreation, unreadable profiles, external edits and nonregular file replacement, recovery readback, exact equipped-item checks, stale actions and shutdown. Existing package, equipment, atomic collection, gesture-store and recovery-integration tests are included in that count.

Two **visible native interaction tests passed with zero failures/skips**, using a disposable profile and actual SwiftUI/AppKit controls. At 880×640 the test followed decoded import review → Make a variation → Create → Add → Equip → Work together, confirmed the real document body and NSTextView-selected passage, then used the native Remember/Save controls. Unequip changed the current label while preserving the saved next-visit outfit; a fresh store loaded the retained item and synthetic KIN identity. The 630×500 collection-limit test exercised disabled Add, inline explanation and the variation handoff. No model or capture calls occurred and no Arena view was loaded.

The initial harness run failed on native sizing, accessibility role lookup and view-update timing; these were corrected before the passing run. This is native accessibility-action testing and store recreation, not full keyboard/VoiceOver traversal, native Open/Save file-panel acceptance, an operating-system process restart, or ordinary-day use. Image artifacts are native view-cache captures and can omit composited layers; they are not a complete visual sign-off. Evidence: `output/marketplace-polish-2026-09-14/`.

Delivery for this polish: Development Review compiled and staged with plist and strict ad-hoc signature checks; the prior candidate bundle, installed app and active session were preserved. The separately exported public source compiled and passed 23 marketplace persistence/outfit tests with zero failures or skips. The historical Alpha tag, Arena pause and owner-private site remain unchanged.
