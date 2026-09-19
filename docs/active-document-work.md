# Active document work in ARCHi

ARCHi uses its existing local Qwen/Reasons and native Work together pipeline for a bounded working task: revise one selected passage. This integrates observation, a declared objective, proposal, verification, explicit application and retained outcome into ordinary assistance. It does not run an ARC benchmark or establish general ARC-to-document transfer.

## Use

Choose a UTF-8 document in Work together, select a passage, and choose Rewrite or Shorten. Set the visible requirements, edit the instruction and Send through the selected provider. Review Before/After and the mechanical checks, then Apply or Dismiss. Apply affects only the app-owned copy; Undo is available for that exact result. Export creates a separate draft.

Local Qwen remains the local route. Existing explicit Codex/Compare choices use the same captured revision target and independent lane ownership; no new fallback, paid route or second model broker was introduced. Preparing a task does not send it.

## Implemented contract

- `RevisionTarget` binds source SHA-256, source revision, exact UTF-16 selected occurrence and immutable requirements at Send.
- `DocumentWorkCapability` checks the existing closed proposal schema, exact current source, size, revision capacity, unchanged surrounding bytes, optional shorter Unicode-character length and exact numeric/literal-URL token counts.
- Token preservation is deliberately literal, including punctuation within URL tokens. It does not resolve URLs, recognize every relative link or establish semantic equivalence.
- Apply remains explicit. A pending receipt with the predicted output digest is persisted before mutation; the native owner then checks the actual resulting bytes. Undo uses the same pending/observed discipline. A failed final receipt is retained in the current session for explicit retry; Undo is enabled only after the completed Apply receipt is saved.
- A per-profile `preferences.document-work.json` sidecar retains up to 64 metadata records, preserving active records. It contains IDs, digests, requirements, authored check labels and lifecycle states, not document text, prompts or model explanations. The lock and fresh disk baseline reject stale writes.
- Restart cancels unexecuted proposals and marks interrupted mutations unverified; history never replays an action. Completed history remains inspectable but does not restore an unsaved working copy.
- Shared revision cards serve Work together, Chat and the Seed bubble. Existing selection/spatial invalidation remains in force: changing the selection, leaving its document surface, moving ARCHi or replacing context can retire a proposal. This update does not promise seamless task resumption across navigation/restart.
- Activity map retains document execution nodes after Apply clears a reply. Usage links require the exact existing request ID; document actions do not double-charge model usage or count as semantic acceptance.

## Evidence boundary

Mechanical checks do not prove truth, preserved meaning, writing quality, general intelligence, a learned skill or companion evolution. The user reviews those properties. A successful Apply must not automatically mark a task useful or a lesson learned.

The focused check group is `DocumentWorkCapabilityTests|DocumentWorkJournalTests|WorkingCopyStoreTests`: 7 XCTest cases and 10 Swift Testing cases passed across the focused runs in the recorded local delivery. No full suite, ARC environment, new model call or paid request ran for this integration. Installed native inspection confirmed the requirements controls and dark-mode layout; a fresh live Qwen revision was not executed during that inspection.

## Hampton integration priorities after this delivery

1. **Outcome-to-learning bridge.** Keep explicit usefulness/correction feedback available after Apply, tied to the retained task, captured lesson versions and observed result. Reuse Evolution, kept lessons and Usage; never derive learning merely from Apply.
2. **Task-scoped memory and dependencies.** Extend the current lexical/topic and exact-source matching to declared task scopes and versioned lesson dependencies, including correction/withdrawal propagation. Keep generated hypotheses distinct from user-confirmed guidance.
3. **More typed working capabilities.** Add extraction and comparison with their own objectives, source observations and completion criteria. Reuse cancellation, providers and accounting rather than a second runtime.
4. **Reviewable procedure learning.** Retain expected effects, observed outcomes and counterexamples across reviewed tasks. Offer scoped procedure candidates; do not automatically promote task-local ARC3 observation/action mappings into general skills.
5. **Bounded orchestration.** Add an optional local reviewer/correction pass with a fixed call budget and retained disagreements. Review evidence cannot itself authorize Apply.
6. **Task continuity.** Resume only by reacquiring and validating the original source, preserving the same companion identity and causal history. Metadata history is not a complete working-state snapshot.

These are code-grounded implementation gaps, not claims that all historical Q2E equations have been installed or validated. The native Reasons roles, exact-span memory, kept lessons and admission controls already implement parts of Hampton's architecture. The recovered ARC donor's Beta critic currently influences static-grid verification ordering; it is not a general adaptive quotient controller throughout the app. A broader numerical controller needs explicit observable state definitions, bounded update contracts and measured application outcomes before integration claims are made.
