# Alpha source validation

7 September 2026 · `v0.7.0-alpha.1` · source package version `0.7.0`.

The following checks were run against the clean publication copy on the development Apple Silicon Mac. This is a source Alpha for supervised local testing, not Beta qualification or another-Mac installation evidence.

| Check | Observed result |
| --- | --- |
| Clean npm dependency installation | `npm ci --offline --ignore-scripts` passed from the existing package cache. |
| Shared app and battle source | 229 tests passed. |
| Boundary text and episode trace helpers | 11 tests passed. |
| Retained PWA asset contracts | 10 tests passed; this is compatibility coverage, not a new browser release target. |
| Isolated synthetic ARC lab | Typecheck and 23 tests passed. These are synthetic contracts, not solver benchmark results. |
| Aggregate public `npm run check` | Passed, including TypeScript checks and asset build. |
| Fresh native build from the publication copy | Passed Swift build, plist validation, local signing, strict signature verification and requested Review-app launch. |
| Default native XCTest suite | 222 executed, 10 skipped, zero failures. Skipped tests are not passes. |
| Swift Testing report | 182 tests in 22 suites reported passed; installed Reactor worker preflight was explicitly skipped. No live-provider result is inferred. |

Separate checks against the packaged publication artifact passed **8/8 native host/layout tests with zero skips**, including all four opt-in production tests: hidden startup/reopen continuity, latest-request artwork recovery, retained appearance/Journey and minimum-window layout. The packaged render diagnostic passed **29/29 checks with zero assistant calls**. Its synthetic form sheet was visually inspected.

PNG byte equality after help changes and Return was false. Dimensions and full alpha were exact; the maximum 8-bit premultiplied sRGB difference was **1/255**, mean **0.014122/255**, within the declared Alpha thresholds of peak 2/255 and mean 0.1/255. This records a bounded presentation check, not byte determinism.

The default native suite intentionally skips tests requiring opted-in model calls, installed worker prerequisites or a windowed bundled-host fixture. The separate host tests above ran against isolated acceptance profiles; they did not alter user preferences or history.

## Publication-specific changes

This release copies current source, including previously untracked native and battle work, into a clean public history. It excludes private research conversations, accountability records, user saves, credentials, build caches, installed tools and model weights. The original development checkout and authored files are preserved.

The two runtime companion PNGs contained a private source-file path in a text metadata chunk. The public copies omit that chunk; their compressed image payload, decompressed scanlines and every other chunk are unchanged. The public native hash pins match the sanitized files. This does not alter the artwork's pixels.

The public package replaces internal research/accountability commands with verification paths that operate on the included source. The package uses numeric `0.7.0` because the existing PWA cache contract accepts numeric versions; the Git tag and release explicitly identify the Alpha. The initial build failure on an Alpha-suffixed package version was corrected before the successful aggregate check.

## Limits

Broader ordinary-day use, sleep/wake, display changes, full VoiceOver traversal, resource budgets, combined backup/restore, update/rollback and another-Mac installation remain open. The generated app is locally signed and staged in the operating system's temporary directory. No notarized installer is included.

No new live Codex, Compare or Reactor acceptance is claimed by these source checks. The source contains optional adapters; installation and a successful connection are distinct from a representative end-to-end provider result. Natural appearance variation is not trained development, authenticated authorship, transferable ownership or market valuation.
