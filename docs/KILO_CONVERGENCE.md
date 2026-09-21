# KILO_ARCHi convergence contract

Status: active working contract for the KiloMusician/KILO_ARCHi fork.

KILO_ARCHi exists to help finish, harden and demonstrate ARCHi without erasing the product's existing authority boundaries or turning the fork into a generic agent shell. The fork is both a development laboratory and a clean contribution staging area for work that may later be proposed back to cr8ph8/ARCHi.

## Authority and upstream relationship

Patrick Hampton's ARCHi remains the upstream product and source of product intent. This fork may move faster, test broader integrations and restructure implementation seams, but changes should remain legible as one of three classes:

1. **Upstream-ready**: generally useful ARCHi improvements that preserve product semantics and can be proposed back cleanly.
2. **Kilo integration**: optional adapters for the Kilo/ΞNuSyQ ecosystem that must not become required for normal ARCHi operation.
3. **Experiment**: measured research or prototype work that must not silently redefine ARCHi's claims, memory policy, privacy model or release status.

The fork should prefer small, attributable commits even when the working branch contains a larger convergence candidate.

## Branch roles

- main: stable fork baseline kept close to upstream, plus minimal fork infrastructure such as CI.
- kilo/finish: convergence lane for making the active ARCHi candidate reproducible, reviewable and Beta-ready.
- kilo/integration: bounded Kilo/ΞNuSyQ adapters and interoperability contracts.
- kilo/experiments: Q2E, routing, evaluation and other research where conclusions must remain tied to observed evidence.

Additional short-lived branches are encouraged for isolated fixes.

## Definition of "finished enough"

A Beta-quality ARCHi candidate is not defined by feature count. It should satisfy a bounded set of product and evidence gates:

- clean reproducible source checks on the exact candidate commit;
- deterministic tests and explicit reporting of skips and opt-in tests;
- native build evidence on a supported macOS runner and another-Mac install/open evidence for a distributable candidate;
- permission recovery, sleep/wake, multi-display, keyboard and VoiceOver acceptance;
- bounded long-session resource observations;
- explicit release signing/notarization/update/rollback story for public distribution;
- no private authoring records, credentials or unrelated development history in a promoted source packet;
- clear separation between local-only context, deliberately shared exact copies and external-provider input;
- explicit user admission for durable lessons, evolution outcomes or other retained state;
- a documented recovery path for interrupted model, capture, marketplace and Unity sessions.

Feature experiments that do not meet those gates may remain available behind clearly described boundaries without moving the Beta goalposts.

## Integration boundary with the Kilo / ΞNuSyQ system

ARCHi should be treated as a human-facing companion and consent boundary. The Greater System may provide orchestration, repository intelligence, model routing, agent execution and evidence, but it must not silently inherit ARCHi authority.

A future Colony adapter should use a narrow request/result envelope containing, at minimum:

- request/session identity;
- source identity, revision and digest when source material is involved;
- requested capability and privacy scope;
- selected route/agent/model identity;
- execution status and evidence references;
- result digest;
- optional action proposal requiring explicit user confirmation.

The first integration should be read-only and evidence-oriented. Generic shell access, arbitrary filesystem mutation, silent memory import, automatic companion evolution and desktop action should remain outside the initial boundary.

The invariants are:

- receipt is not truth;
- graph edge is not authority;
- model output is not memory;
- proposal is not action;
- successful execution is not accepted outcome;
- external system availability does not weaken a local privacy choice.

## Architectural direction

CompanionStore should remain the visible product authority/facade while implementation responsibility is gradually extracted into focused coordinators where this reduces coupling without changing behavior. Candidate seams include assistance/routing, desktop context, memory/lessons, presence, marketplace, evolution and receipts.

Node Lab should remain a bounded human-readable evidence projection. External project graphs or GitNexus-style code intelligence may be summarized or paged into it, but should not be mirrored wholesale or treated as product authority.

Local Qwen remains a first-class protected lane. Colony routing, LiteLLM or other model systems should be introduced as optional supervised providers rather than replacing ARCHi's local inference boundary.

## Evidence discipline

Every material claim should identify which of these it represents:

- source inspection;
- deterministic automated test;
- integration test;
- installed-app observation;
- human acceptance observation;
- external-provider result;
- experiment;
- inference or hypothesis.

Q2E/ARC and related adaptive mechanisms should be described according to demonstrated behavior. Architecture, donor derivation or mathematical form alone does not establish calibrated prediction, learning advantage, generalization, AGI or scientific validation.

When an experiment compares retain/expand/repair/stop or other policies, preserve the baseline, task set, exact candidate SHA, outcome definition and raw aggregate results needed to repeat the comparison.

## Contribution path

Work intended for upstream should be separable from Kilo-specific integration. Prefer upstream-ready fixes first when they benefit both trees. Kilo-only adapters should live behind narrow interfaces and documentation so removing them leaves a coherent ARCHi.

Before presenting a package upstream, produce a concise delta report covering:

- candidate commit and ancestry;
- tests and acceptance gates run;
- known skips/blockers;
- upstream-ready commits;
- optional Kilo integration commits;
- experimental findings and their limitations;
- release/distribution state.

The goal is not to replace ARCHi with the Greater System. The goal is to let both systems sharpen each other while preserving a clean path back to Patrick's project.
