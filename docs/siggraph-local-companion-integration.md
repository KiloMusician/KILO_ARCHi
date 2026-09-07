# Broken Relay provenance

The pure Broken Relay activity was adapted from Patrick Hampton's existing SigGraph Hackathon work into ARCHi's current Journey and native-hosted game.

Its sequence is Start → redirect three nodes → inspect three transmissions → resolve the contradiction. ARCHi retains the original puzzle behavior while validating bounded action receipts, replaying eligible completion and keeping accepted outcomes through the existing Journey owner. The presentation import was replaced with a local cue type; no second renderer, assistant identity or persistent history system was imported.

Relevant files:

- `src/companion-activities/broken-relay.ts`: pure activity rules.
- `src/companion-activities/broken-relay.test.ts`: rule and malformed-input checks.
- `src/model.ts` and `src/journey-activity.test.ts`: accepted completion and Journey replay.

The research conversations, user records and shelved extraction experiments are not part of this source distribution. A puzzle completion records accepted game progress; it does not prove transferable ownership or real-world mastery.
