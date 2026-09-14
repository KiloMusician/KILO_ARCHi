# Local marketplace and canon item policy

14 September 2026 · Implemented desktop development Alpha

The native Marketplace (sidebar, Window menu / Command–5, menu-bar item and Wardrobe link) shares the existing companion, renderer, Work together and native profile. It adds no second character, model router, market server or game save.

## Working local flow

- Discover three bundled recipes: Focus Staff, decorative Starlight Staff and Grove Staff.
- Inspect static artwork and the exact supported local action. Previewing changes no outfit, identity, memory or progression.
- Add to My items explicitly retains the recipe on this Mac. The Alpha collection holds eight exact designs. Duplicate adds do not write another record.
- Equip applies the item for the visit. Existing Save preferences keeps the outfit. A kept personal staff gesture overrides the creator default; Forget restores that design's default.
- Create variations using five palettes, three crown shapes, either decoration or pointing, and bounded pace/sparkle/hold choices. No arbitrary code, images, remote URLs or model prompts are imported.
- Import a local JSON recipe (maximum 4 KB) for review before Add. Export shares the design and declared license only. It does not share private memory or companion identity, issue an edition, or transfer ownership.
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

## Evidence and limits

Current checkout: full Swift suite passed 629 XCTest cases (32 skipped, zero failures) and reported 234 Swift Testing tests with the existing installed-worker opt-in skip. New tests cover strict recipe exchange, claimed registration, digest binding, palette/crown rendering, decorative activation, restart, equip/Save, atomic removal, conflict protection, older saves and actual backup restore/undo. These counts overlap the focused runs.

A hidden actual Marketplace view rendered legibly at 630×500 with no model calls or profile/identity changes. Native SwiftUI accessibility proxies were unavailable for the hidden panel; that acceptance is explicitly skipped. Full keyboard/VoiceOver, import/save-panel interaction, creator flow clicks, long-session use and another-Mac installation remain unqualified. No live LLM request was made. Build and staging evidence remains in the maintainer’s local qualification record.

The existing [website marketplace guide](https://archi-it-begins-when-you-do.channelph.chatgpt.site/marketplace) links [public source](https://github.com/cr8ph8/ARCHi), explains the technical and proposed stewardship foundations, and separates local items from production registration and later Arena. Audience remains owner-private. Commerce, wallets, NFTs, transfers, creator submissions and popularity rankings are not enabled.
