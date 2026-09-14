using System;
using System.Collections.Generic;

namespace ARCHi.Port
{
    public enum RelayPhase { Ready, Interference, Puzzle, Restored }
    public enum RelayCue { Rest, Focus }
    public enum RelayAction { Start, Redirect, Inspect, Resolve, TryFocus, RestoreBase, Reset }

    public sealed class RelayClaim
    {
        public char Id { get; }
        public string Title { get; }
        public string Text { get; }
        internal RelayClaim(char id, string title, string text) { Id = id; Title = title; Text = text; }
    }

    /// <summary>
    /// Direct C# port of src/companion-activities/broken-relay.ts:1-171,
    /// rules version 1; upstream provenance: docs/siggraph-local-companion-integration.md.
    /// Source SHA-256: ccf86ba32794d16aad6fc60e3a81764db933c703c5f3c099d95d7fd2768301e3.
    /// Only copy/API deltas: Proto is called KIN, and RESTORE_PROTO maps to RestoreBase.
    /// One UI-owned rehearsal session. No Unity lifecycle, files, identity, scores,
    /// rewards, growth admission, model calls or persisted Journey are owned here.
    /// </summary>
    public sealed class RelayPractice
    {
        public const int RulesVersion = 1;
        public const string SessionLabel = "Practice preview · not saved";
        public const string FieldLog = "18:40 — The west bridge is closed until inspection. The north path is open. No later inspection or reopening has been recorded.";
        public static IReadOnlyList<int> Route { get; } = Array.AsReadOnly(new[] { 2, 1, 3 });
        public static IReadOnlyList<RelayClaim> Claims { get; } = Array.AsReadOnly(new[]
        {
            new RelayClaim('A', "North route", "18:42 — Use the north path. It remains open after 18:40."),
            new RelayClaim('B', "West bridge", "18:44 — The west bridge is clear. Send the convoy west now."),
            new RelayClaim('C', "West beacon", "18:45 — Keep the west beacon offline until the bridge inspection is recorded.")
        });

        public RelayPhase Phase { get; private set; }
        public int ProtectedSteps { get; private set; }
        public IReadOnlyList<char> ReadTransmissionIds { get; private set; }
        public char? SelectedTransmissionId { get; private set; }
        public string Feedback { get; private set; }
        public bool FocusPreview { get; private set; }
        public bool Done => Phase == RelayPhase.Restored;
        public RelayCue Cue => Phase == RelayPhase.Ready || (Done && !FocusPreview) ? RelayCue.Rest : RelayCue.Focus;

        public RelayPractice() { ResetSession(); }

        /// <summary>
        /// Redirect accepts only node 1..3; Inspect/Resolve accept only id A..C.
        /// Other actions have no payload. Invalid or extra payloads throw before
        /// mutation, including when a well-shaped action would be out of phase.
        /// Out-of-phase legal actions are harmless, matching the retained reducer.
        /// </summary>
        public void Apply(RelayAction action, int? node = null, char? id = null)
        {
            Validate(action, node, id);
            switch (action)
            {
                case RelayAction.Reset:
                    ResetSession();
                    return;
                case RelayAction.Start:
                    if (Phase != RelayPhase.Ready) return;
                    Phase = RelayPhase.Interference;
                    Feedback = "Redirect the interference through nodes 2 → 1 → 3 to protect the Core.";
                    return;
                case RelayAction.Redirect:
                    if (Phase != RelayPhase.Interference) return;
                    var nextNode = Route[ProtectedSteps];
                    if (node.Value != nextNode)
                    {
                        Feedback = $"That route is unstable. Progress is safe; redirect through node {nextNode} next.";
                        return;
                    }
                    ProtectedSteps++;
                    if (ProtectedSteps == Route.Count)
                    {
                        Phase = RelayPhase.Puzzle;
                        Feedback = "Core protected. A memory scar has scrambled the message channel. Read all three transmissions and compare them with the field log.";
                    }
                    else Feedback = $"Node {node.Value} secured. Redirect through node {Route[ProtectedSteps]} next.";
                    return;
                case RelayAction.Inspect:
                    if (Phase != RelayPhase.Puzzle) return;
                    SelectedTransmissionId = id.Value;
                    if (!HasRead(id.Value))
                    {
                        // Replace the collection so earlier UI snapshots remain unchanged.
                        var next = new List<char>(ReadTransmissionIds) { id.Value };
                        ReadTransmissionIds = next.AsReadOnly();
                    }
                    Feedback = $"Transmission {id.Value} inspected. Compare its claim with the field log before choosing the false message.";
                    return;
                case RelayAction.Resolve:
                    if (Phase != RelayPhase.Puzzle) return;
                    SelectedTransmissionId = id.Value;
                    if (ReadTransmissionIds.Count != Claims.Count)
                    {
                        Feedback = "Inspect all three transmissions before choosing. Your relay progress is preserved.";
                        return;
                    }
                    if (id.Value != 'B')
                    {
                        Feedback = "That message agrees with the field log. Look for a bridge reopening without a recorded inspection; your progress is preserved.";
                        return;
                    }
                    Phase = RelayPhase.Restored;
                    Feedback = "Relay restored. Transmission B contradicts the recorded west-bridge closure. You can now try a reversible Focus preview for KIN.";
                    return;
                case RelayAction.TryFocus:
                    if (!Done) return;
                    FocusPreview = true;
                    Feedback = "Focus preview active for this rehearsal. Restore KIN at any time; nothing is saved as an evolution.";
                    return;
                case RelayAction.RestoreBase:
                    if (!Done) return;
                    FocusPreview = false;
                    Feedback = "KIN restored to its base presentation. The repaired relay remains available until Reset.";
                    return;
            }
        }

        public bool HasRead(char id)
        {
            for (var index = 0; index < ReadTransmissionIds.Count; index++)
                if (ReadTransmissionIds[index] == id) return true;
            return false;
        }

        private void ResetSession()
        {
            Phase = RelayPhase.Ready;
            ProtectedSteps = 0;
            ReadTransmissionIds = Array.AsReadOnly(new char[0]);
            SelectedTransmissionId = null;
            FocusPreview = false;
            Feedback = "Protect the relay Core, then trace the damaged message channel.";
        }

        private static void Validate(RelayAction action, int? node, char? id)
        {
            var valid = Enum.IsDefined(typeof(RelayAction), action);
            if (action == RelayAction.Redirect)
                valid &= node.HasValue && node.Value >= 1 && node.Value <= 3 && !id.HasValue;
            else if (action == RelayAction.Inspect || action == RelayAction.Resolve)
                valid &= !node.HasValue && id.HasValue && (id.Value == 'A' || id.Value == 'B' || id.Value == 'C');
            else valid &= !node.HasValue && !id.HasValue;
            if (!valid) throw new ArgumentException("Unknown Broken Relay action.");
        }
    }
}
