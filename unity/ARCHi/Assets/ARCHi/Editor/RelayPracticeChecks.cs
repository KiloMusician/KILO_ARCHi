using System;
using System.Collections.Generic;
using System.Linq;

namespace ARCHi.Port.Editor
{
    /// <summary>
    /// Source-parity fixtures adapted from src/companion-activities/broken-relay.test.ts.
    /// Run from the existing Editor validation entry point. No scene, player,
    /// profile, provider or persistence is touched. Throws on the first failure.
    /// </summary>
    public static class RelayPracticeChecks
    {
        public static int Run()
        {
            var checks = 0;
            Action<bool, string> expect = (condition, message) =>
            {
                checks++;
                if (!condition) throw new InvalidOperationException("Relay parity: " + message);
            };
            expect(RelayPractice.Route.SequenceEqual(new[] { 2, 1, 3 }), "source route");
            expect(RelayPractice.FieldLog == "18:40 — The west bridge is closed until inspection. The north path is open. No later inspection or reopening has been recorded.", "source field log");
            expect(RelayPractice.Claims.Select(claim => claim.Id).SequenceEqual(new[] { 'A', 'B', 'C' }), "source claim IDs");
            expect(RelayPractice.Claims[0].Text == "18:42 — Use the north path. It remains open after 18:40.", "claim A");
            expect(RelayPractice.Claims[1].Text == "18:44 — The west bridge is clear. Send the convoy west now.", "claim B");
            expect(RelayPractice.Claims[2].Text == "18:45 — Keep the west beacon offline until the bridge inspection is recorded.", "claim C");

            var practice = new RelayPractice();
            expect(practice.Phase == RelayPhase.Ready && practice.Cue == RelayCue.Rest && !practice.Done, "initial phase and cue");
            practice.Apply(RelayAction.Start);
            expect(practice.Phase == RelayPhase.Interference && practice.Cue == RelayCue.Focus, "Start");
            practice.Apply(RelayAction.Redirect, node: 2);
            practice.Apply(RelayAction.Redirect, node: 3);
            expect(practice.ProtectedSteps == 1 && practice.Phase == RelayPhase.Interference, "wrong node preserves progress");
            expect(practice.Feedback.Contains("node 1 next"), "retry explains the next node");
            practice.Apply(RelayAction.Redirect, node: 1);
            practice.Apply(RelayAction.Redirect, node: 3);
            expect(practice.Phase == RelayPhase.Puzzle && practice.ProtectedSteps == 3, "protected Core enters puzzle");
            expect(practice.Feedback.Contains("memory scar") && practice.Cue == RelayCue.Focus, "puzzle feedback and cue");
            var earlierClues = practice.ReadTransmissionIds;
            practice.Apply(RelayAction.Inspect, id: 'B');
            practice.Apply(RelayAction.Inspect, id: 'B');
            expect(practice.ReadTransmissionIds.SequenceEqual(new[] { 'B' }) && earlierClues.Count == 0, "deduplicated clues and stable previous snapshot");
            practice.Apply(RelayAction.Resolve, id: 'B');
            expect(!practice.Done && practice.SelectedTransmissionId == 'B' && practice.Feedback.Contains("Inspect all three"), "correct guess requires all clues");
            practice.Apply(RelayAction.Inspect, id: 'A');
            practice.Apply(RelayAction.Inspect, id: 'C');
            foreach (var incorrect in new[] { 'A', 'C' })
            {
                practice.Apply(RelayAction.Resolve, id: incorrect);
                expect(!practice.Done && practice.ProtectedSteps == 3 && practice.ReadTransmissionIds.Count == 3,
                    "incorrect answer preserves progress and clues");
                expect(practice.SelectedTransmissionId == incorrect && practice.Feedback.Contains("agrees with the field log"), "incorrect answer feedback");
            }
            practice.Apply(RelayAction.Resolve, id: 'B');
            expect(practice.Done && practice.SelectedTransmissionId == 'B' && practice.Cue == RelayCue.Rest, "only B repairs the relay");
            expect(practice.Feedback.Contains("contradicts"), "completed explanation");
            practice.Apply(RelayAction.TryFocus);
            expect(practice.FocusPreview && practice.Cue == RelayCue.Focus && practice.Done, "temporary Focus cue");
            expect(practice.Feedback.Contains("nothing is saved"), "preview disclosure");
            var focused = Snapshot(practice);
            practice.Apply(RelayAction.TryFocus);
            expect(Snapshot(practice) == focused, "duplicate preview does not accumulate effects");
            practice.Apply(RelayAction.RestoreBase);
            expect(!practice.FocusPreview && practice.Done && practice.Cue == RelayCue.Rest, "restore keeps repaired session");

            // Every legal no-op shape is checked in every phase where the source ignores it.
            foreach (var phase in (RelayPhase[])Enum.GetValues(typeof(RelayPhase)))
            {
                var state = InPhase(phase);
                var before = Snapshot(state);
                if (phase != RelayPhase.Ready) { state.Apply(RelayAction.Start); expect(Snapshot(state) == before, "out-of-phase Start"); }
                if (phase != RelayPhase.Interference) { state.Apply(RelayAction.Redirect, node: 2); expect(Snapshot(state) == before, "out-of-phase Redirect"); }
                if (phase != RelayPhase.Puzzle)
                {
                    state.Apply(RelayAction.Inspect, id: 'A'); expect(Snapshot(state) == before, "out-of-phase Inspect");
                    state.Apply(RelayAction.Resolve, id: 'C'); expect(Snapshot(state) == before, "out-of-phase Resolve and duplicate completion");
                }
                if (phase != RelayPhase.Restored)
                {
                    state.Apply(RelayAction.TryFocus); expect(Snapshot(state) == before, "early Focus");
                    state.Apply(RelayAction.RestoreBase); expect(Snapshot(state) == before, "early RestoreBase");
                }
                var invalid = new List<Action>
                {
                    () => state.Apply((RelayAction)(-1)), () => state.Apply((RelayAction)999),
                    () => state.Apply(RelayAction.Redirect), () => state.Apply(RelayAction.Redirect, node: 0),
                    () => state.Apply(RelayAction.Redirect, node: 4), () => state.Apply(RelayAction.Redirect, node: 2, id: 'A'),
                    () => state.Apply(RelayAction.Inspect), () => state.Apply(RelayAction.Inspect, id: 'D'),
                    () => state.Apply(RelayAction.Inspect, node: 1, id: 'A'),
                    () => state.Apply(RelayAction.Resolve), () => state.Apply(RelayAction.Resolve, id: 'D'),
                    () => state.Apply(RelayAction.Resolve, node: 1, id: 'B')
                };
                foreach (var noPayload in new[] { RelayAction.Start, RelayAction.TryFocus, RelayAction.RestoreBase, RelayAction.Reset })
                {
                    var action = noPayload;
                    invalid.Add(() => state.Apply(action, node: 1));
                    invalid.Add(() => state.Apply(action, id: 'A'));
                }
                foreach (var action in invalid)
                {
                    var rejected = false;
                    try { action(); } catch (ArgumentException) { rejected = true; }
                    expect(rejected && Snapshot(state) == before, "malformed action rejected before mutation");
                }
                if (state.Done) state.Apply(RelayAction.TryFocus);
                var previous = state.ReadTransmissionIds;
                state.Apply(RelayAction.Reset);
                expect(Snapshot(state) == Snapshot(new RelayPractice()), "Reset clears every phase and cue");
                expect(!ReferenceEquals(previous, state.ReadTransmissionIds), "Reset does not mutate earlier clue snapshot");
            }
            foreach (var order in new[] { "ABC", "ACB", "BAC", "BCA", "CAB", "CBA" })
            {
                var state = InPhase(RelayPhase.Puzzle);
                foreach (var id in order) state.Apply(RelayAction.Inspect, id: id);
                state.Apply(RelayAction.Resolve, id: 'B');
                expect(state.Done && state.ReadTransmissionIds.SequenceEqual(order), "all clue orders complete without reordering evidence");
            }
            return checks;
        }

        private static RelayPractice InPhase(RelayPhase phase)
        {
            var state = new RelayPractice();
            if (phase == RelayPhase.Ready) return state;
            state.Apply(RelayAction.Start);
            if (phase == RelayPhase.Interference) return state;
            foreach (var node in RelayPractice.Route) state.Apply(RelayAction.Redirect, node: node);
            if (phase == RelayPhase.Puzzle) return state;
            foreach (var claim in RelayPractice.Claims) state.Apply(RelayAction.Inspect, id: claim.Id);
            state.Apply(RelayAction.Resolve, id: 'B');
            return state;
        }

        private static string Snapshot(RelayPractice state)
        {
            return state.Phase + "|" + state.ProtectedSteps + "|" + string.Join(",", state.ReadTransmissionIds)
                + "|" + state.SelectedTransmissionId + "|" + state.FocusPreview + "|" + state.Cue + "|" + state.Feedback;
        }
    }
}
